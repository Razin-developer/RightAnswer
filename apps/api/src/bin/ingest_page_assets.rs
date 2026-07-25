//! Walks storage/textbooks/processed/sslc/{subject_code}/{medium}/*/assets/
//! *.json (per-embedded-asset manifests written by the textbook processing
//! pipeline) and upserts them into the `page_assets` table, so the API can
//! answer "every embedded illustration/table/graph on page N of this
//! chapter" instead of only whichever single image a matched Qdrant chunk
//! happened to carry.
//!
//! Run the same way as migrate_qdrant:
//!   docker compose --env-file .env.production -f docker-compose.prod.yml \
//!     run --rm api ingest_page_assets
//!
//! Safe to re-run — every insert is ON CONFLICT DO NOTHING keyed on the
//! natural (subject_code, medium, chapter_number, page_number, file_path)
//! tuple, so re-running after new textbooks are added only adds new rows.

use std::{env, fs, path::Path};

use anyhow::{Context, Result};
use serde::Deserialize;
use sqlx::PgPool;

#[derive(Deserialize)]
struct AssetManifest {
    #[serde(rename = "assetType")]
    asset_type: String,
    #[serde(rename = "pageNumber")]
    page_number: i32,
    #[serde(rename = "filePath")]
    file_path: String,
    metadata: AssetMetadata,
}

#[derive(Deserialize)]
struct AssetMetadata {
    #[serde(rename = "chapterNumber")]
    chapter_number: i32,
}

#[tokio::main]
async fn main() -> Result<()> {
    dotenvy::dotenv().ok();
    let database_url = env::var("DATABASE_URL").context("DATABASE_URL is required")?;
    let storage_dir = env::var("STORAGE_DIR").unwrap_or_else(|_| "/app/storage".into());
    let root = Path::new(&storage_dir).join("textbooks/processed/sslc");

    if !root.exists() {
        anyhow::bail!(
            "storage dir {} not found — is the storage volume mounted into this container?",
            root.display()
        );
    }

    let pool = PgPool::connect(&database_url).await?;

    let mut inserted = 0usize;
    let mut skipped_parse_errors = 0usize;
    let mut examined = 0usize;

    // storage/textbooks/processed/sslc/{subject_code}/{medium}/{version}/assets/*.json
    for subject_entry in fs::read_dir(&root).with_context(|| format!("reading {}", root.display()))? {
        let subject_dir = subject_entry?.path();
        if !subject_dir.is_dir() {
            continue;
        }
        let subject_code = subject_dir
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or_default()
            .to_string();

        for medium_entry in fs::read_dir(&subject_dir)? {
            let medium_dir = medium_entry?.path();
            if !medium_dir.is_dir() {
                continue;
            }
            let medium = medium_dir
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or_default()
                .to_string();

            for version_entry in fs::read_dir(&medium_dir)? {
                let version_dir = version_entry?.path();
                let assets_dir = version_dir.join("assets");
                if !assets_dir.is_dir() {
                    continue;
                }

                for asset_entry in fs::read_dir(&assets_dir)? {
                    let asset_path = asset_entry?.path();
                    if asset_path.extension().and_then(|e| e.to_str()) != Some("json") {
                        continue;
                    }
                    examined += 1;

                    let raw = match fs::read_to_string(&asset_path) {
                        Ok(raw) => raw,
                        Err(_) => {
                            skipped_parse_errors += 1;
                            continue;
                        }
                    };
                    let manifest: AssetManifest = match serde_json::from_str(&raw) {
                        Ok(m) => m,
                        Err(_) => {
                            skipped_parse_errors += 1;
                            continue;
                        }
                    };

                    let result = sqlx::query(
                        r#"
                        INSERT INTO page_assets
                          (subject_code, medium, chapter_number, page_number, asset_type, file_path)
                        VALUES ($1, $2, $3, $4, $5, $6)
                        ON CONFLICT (subject_code, medium, chapter_number, page_number, file_path)
                        DO NOTHING
                        "#,
                    )
                    .bind(&subject_code)
                    .bind(&medium)
                    .bind(manifest.metadata.chapter_number)
                    .bind(manifest.page_number)
                    .bind(&manifest.asset_type)
                    .bind(&manifest.file_path)
                    .execute(&pool)
                    .await;

                    match result {
                        Ok(r) => inserted += r.rows_affected() as usize,
                        Err(e) => {
                            eprintln!("insert failed for {}: {e}", asset_path.display());
                            skipped_parse_errors += 1;
                        }
                    }
                }
            }
        }
    }

    println!(
        "Examined {examined} manifest files, inserted {inserted} new page_assets rows, {skipped_parse_errors} skipped (parse/insert errors)."
    );
    Ok(())
}
