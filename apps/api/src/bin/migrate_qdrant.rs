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
    let has_vector_column = sqlx::query_scalar::<_, bool>(
        r#"
        SELECT EXISTS (
          SELECT 1
          FROM information_schema.columns
          WHERE table_schema = 'public'
            AND table_name = 'Embedding'
            AND column_name = 'embedding_vector'
        )
        "#,
    )
    .fetch_one(&pool)
    .await?;

    let embedding_vector_select = if has_vector_column {
        "e.embedding_vector::text AS embedding_vector"
    } else {
        "NULL::text AS embedding_vector"
    };

    // Stream in pages rather than fetch_all: this binary runs inside a
    // memory-capped container (384MB), and loading every embedding vector
    // (1024 floats each) plus text/payload for ~30k+ rows at once was
    // getting OOM-killed. A page of 200 keeps peak memory well under limit.
    const PAGE_SIZE: i64 = 200;
    let mut offset: i64 = 0;
    let mut migrated = 0usize;
    let mut collection_ready = false;

    loop {
        let rows = sqlx::query(&format!(
            r#"
            SELECT
              e.id::text AS embedding_id,
              {embedding_vector_select},
              e.embedding_values,
              e.embedding_model,
              e.embedding_version,
              cu.id::text AS content_unit_id,
              cu.text,
              cu.content_type::text AS content_type,
              cu.chapter_id::text AS chapter_id,
              ch.title AS chapter_name,
              s.id::text AS subject_id,
              s.name AS subject_name,
              p.page_number,
              a.file_path AS image_url
            FROM "Embedding" e
            JOIN "ContentUnit" cu ON cu.id = e.content_unit_id
            JOIN "Page" p ON p.id = cu.page_id
            JOIN "Chapter" ch ON ch.id = cu.chapter_id
            JOIN "TextbookVersion" tv ON tv.id = ch.textbook_version_id
            JOIN "Textbook" t ON t.id = tv.textbook_id
            JOIN "Subject" s ON s.id = t.subject_id
            LEFT JOIN LATERAL (
              SELECT file_path
              FROM "TextbookAsset"
              WHERE content_unit_id = cu.id
              ORDER BY created_at ASC
              LIMIT 1
            ) a ON true
            ORDER BY e.created_at ASC
            LIMIT {PAGE_SIZE} OFFSET {offset}
            "#
        ))
        .fetch_all(&pool)
        .await?;

        if rows.is_empty() {
            break;
        }

        if !collection_ready {
            let first_vector = vector_from_row(&rows[0])?;
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
            collection_ready = true;
        }

        for batch in rows.chunks(64) {
            let mut points = Vec::with_capacity(batch.len());
            for row in batch {
                let vector = vector_from_row(row)?;
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
                        "chapter_name": row.get::<String, _>("chapter_name"),
                        "subject_id": row.get::<String, _>("subject_id"),
                        "subject_name": row.get::<String, _>("subject_name"),
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

        let page_len = rows.len();
        drop(rows);
        println!("Migrated {migrated} embeddings so far...");
        if (page_len as i64) < PAGE_SIZE {
            break;
        }
        offset += PAGE_SIZE;
    }

    if migrated == 0 {
        return Err(anyhow!(
            "No PostgreSQL embeddings found. Stop: Qdrant migration would lose data."
        ));
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
        "Migrated {migrated} PostgreSQL embeddings into Qdrant collection {qdrant_collection}. Vector source: {}.",
        if has_vector_column { "pgvector embedding_vector" } else { "JSON embedding_values fallback" }
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
    let collection_url = format!(
        "{}/collections/{}",
        base_url.trim_end_matches('/'),
        collection
    );
    let mut inspect = client.get(&collection_url);
    if let Some(api_key) = api_key {
        inspect = inspect.header("api-key", api_key);
    }
    let inspect_response = inspect.send().await?;
    if inspect_response.status().is_success() {
        let value: Value = inspect_response.json().await?;
        let existing_size = value["result"]["config"]["params"]["vectors"]["size"]
            .as_u64()
            .or_else(|| value["result"]["config"]["params"]["vectors"][""]["size"].as_u64());
        if existing_size == Some(vector_size as u64) {
            return Ok(());
        }
        return Err(anyhow!(
            "Qdrant collection {collection} already exists with vector size {:?}, expected {vector_size}. Stop to avoid mixing incompatible data.",
            existing_size
        ));
    }
    if inspect_response.status().as_u16() != 404 {
        let status = inspect_response.status();
        let text = inspect_response.text().await.unwrap_or_default();
        return Err(anyhow!(
            "Qdrant inspect collection failed ({status}): {text}"
        ));
    }

    let mut request = client.put(collection_url);
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

fn vector_from_row(row: &sqlx::postgres::PgRow) -> anyhow::Result<Vec<f32>> {
    let embedding_id = row.get::<String, _>("embedding_id");
    if let Some(vector_text) = row.try_get::<Option<String>, _>("embedding_vector")? {
        let vector = parse_pgvector_text(&vector_text).with_context(|| {
            format!("Failed to parse pgvector embedding_vector for embedding {embedding_id}")
        })?;
        if !vector.is_empty() {
            return Ok(vector);
        }
    }

    let value = row.get::<Value, _>("embedding_values");
    let vector: Vec<f32> = serde_json::from_value(value)
        .with_context(|| format!("Failed to parse JSON embedding_values for {embedding_id}"))?;
    Ok(vector)
}

fn parse_pgvector_text(value: &str) -> anyhow::Result<Vec<f32>> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return Ok(vec![]);
    }
    let inner = trimmed
        .strip_prefix('[')
        .and_then(|value| value.strip_suffix(']'))
        .ok_or_else(|| anyhow!("expected pgvector text like [0.1,0.2], got {trimmed}"))?;
    if inner.trim().is_empty() {
        return Ok(vec![]);
    }
    inner
        .split(',')
        .map(|part| {
            part.trim()
                .parse::<f32>()
                .with_context(|| format!("invalid vector number: {}", part.trim()))
        })
        .collect()
}
