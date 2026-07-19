use std::env;

use anyhow::{anyhow, Context};
use reqwest::Client;
use serde_json::{json, Value};
use sqlx::{PgPool, Row};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    dotenvy::dotenv().ok();
    let database_url = env::var("DATABASE_URL").context("DATABASE_URL is required")?;
    let qdrant_url = env::var("QDRANT_URL").unwrap_or_else(|_| "http://localhost:6333".into());
    let qdrant_collection =
        env::var("QDRANT_COLLECTION").unwrap_or_else(|_| "right_answer_textbook_chunks".into());
    let qdrant_api_key = env::var("QDRANT_API_KEY").ok();

    let pool = PgPool::connect(&database_url).await?;
    let client = Client::new();

    let rows = sqlx::query(
        r#"
        SELECT
          e.id::text AS embedding_id,
          e.embedding_values,
          e.embedding_model,
          e.embedding_version,
          cu.id::text AS content_unit_id,
          cu.text,
          cu.content_type::text AS content_type,
          cu.chapter_id::text AS chapter_id,
          p.page_number,
          a.file_path AS image_url
        FROM "Embedding" e
        JOIN "ContentUnit" cu ON cu.id = e.content_unit_id
        JOIN "Page" p ON p.id = cu.page_id
        LEFT JOIN "TextbookAsset" a ON a.content_unit_id = cu.id
        ORDER BY e.created_at ASC
        "#,
    )
    .fetch_all(&pool)
    .await?;

    if rows.is_empty() {
        return Err(anyhow!(
            "No PostgreSQL embeddings found. Stop: Qdrant migration would lose data."
        ));
    }

    let first_vector: Vec<f32> =
        serde_json::from_value(rows[0].get::<Value, _>("embedding_values"))?;
    if first_vector.is_empty() {
        return Err(anyhow!("First embedding vector is empty. Stop."));
    }

    create_collection(
        &client,
        &qdrant_url,
        &qdrant_collection,
        qdrant_api_key.as_deref(),
        first_vector.len(),
    )
    .await?;

    let mut migrated = 0usize;
    for batch in rows.chunks(64) {
        let mut points = Vec::with_capacity(batch.len());
        for row in batch {
            let vector: Vec<f32> = serde_json::from_value(row.get::<Value, _>("embedding_values"))?;
            if vector.is_empty() {
                return Err(anyhow!(
                    "Embedding {} has an empty vector. Stop.",
                    row.get::<String, _>("embedding_id")
                ));
            }
            points.push(json!({
                "id": row.get::<String, _>("embedding_id"),
                "vector": vector,
                "payload": {
                    "content_unit_id": row.get::<String, _>("content_unit_id"),
                    "text": row.get::<String, _>("text"),
                    "content_type": row.get::<String, _>("content_type"),
                    "chapter_id": row.get::<String, _>("chapter_id"),
                    "page_number": row.get::<i32, _>("page_number"),
                    "image_url": row.try_get::<String, _>("image_url").ok(),
                    "embedding_model": row.get::<String, _>("embedding_model"),
                    "embedding_version": row.get::<String, _>("embedding_version")
                }
            }));
        }

        upsert_points(
            &client,
            &qdrant_url,
            &qdrant_collection,
            qdrant_api_key.as_deref(),
            points,
        )
        .await?;
        migrated += batch.len();
    }

    let qdrant_count = count_points(
        &client,
        &qdrant_url,
        &qdrant_collection,
        qdrant_api_key.as_deref(),
    )
    .await?;

    if qdrant_count < migrated as u64 {
        return Err(anyhow!(
            "Qdrant count check failed. PostgreSQL rows: {migrated}, Qdrant points: {qdrant_count}. Stop before switching traffic."
        ));
    }

    println!(
        "Migrated {migrated} PostgreSQL embeddings into Qdrant collection {qdrant_collection}."
    );
    Ok(())
}

async fn create_collection(
    client: &Client,
    base_url: &str,
    collection: &str,
    api_key: Option<&str>,
    vector_size: usize,
) -> anyhow::Result<()> {
    let mut request = client.put(format!(
        "{}/collections/{}",
        base_url.trim_end_matches('/'),
        collection
    ));
    if let Some(api_key) = api_key {
        request = request.header("api-key", api_key);
    }
    let response = request
        .json(&json!({
            "vectors": {
                "size": vector_size,
                "distance": "Cosine"
            }
        }))
        .send()
        .await?;
    if !response.status().is_success() {
        let status = response.status();
        let text = response.text().await.unwrap_or_default();
        return Err(anyhow!(
            "Qdrant create collection failed ({status}): {text}"
        ));
    }
    Ok(())
}

async fn upsert_points(
    client: &Client,
    base_url: &str,
    collection: &str,
    api_key: Option<&str>,
    points: Vec<Value>,
) -> anyhow::Result<()> {
    let mut request = client.put(format!(
        "{}/collections/{}/points?wait=true",
        base_url.trim_end_matches('/'),
        collection
    ));
    if let Some(api_key) = api_key {
        request = request.header("api-key", api_key);
    }
    let response = request.json(&json!({ "points": points })).send().await?;
    if !response.status().is_success() {
        let status = response.status();
        let text = response.text().await.unwrap_or_default();
        return Err(anyhow!("Qdrant upsert failed ({status}): {text}"));
    }
    Ok(())
}

async fn count_points(
    client: &Client,
    base_url: &str,
    collection: &str,
    api_key: Option<&str>,
) -> anyhow::Result<u64> {
    let mut request = client.post(format!(
        "{}/collections/{}/points/count",
        base_url.trim_end_matches('/'),
        collection
    ));
    if let Some(api_key) = api_key {
        request = request.header("api-key", api_key);
    }
    let response = request.json(&json!({ "exact": true })).send().await?;
    if !response.status().is_success() {
        let status = response.status();
        let text = response.text().await.unwrap_or_default();
        return Err(anyhow!("Qdrant count failed ({status}): {text}"));
    }
    let value: Value = response.json().await?;
    Ok(value["result"]["count"].as_u64().unwrap_or(0))
}
