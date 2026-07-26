//! Walks storage/textbooks/processed/sslc/{subject_code}/{medium}/*/pages/
//! *.json (one file per textbook page, written by the processing pipeline)
//! and, for every page that also has a full-page render at
//! .../assets/page-{NNN}.png, upserts one row into `page_assets` pointing
//! at that PNG. The API serves this as the single reference image for a
//! cited page — deliberately just the plain page scan, not the separate
//! "-embedded-NN" illustration/table crops also produced by the pipeline
//! (those are a different asset type this binary no longer indexes).
//!
//! Run the same way as migrate_qdrant:
//!   docker compose --env-file .env.production -f docker-compose.prod.yml \
//!     run --rm api ingest_page_assets
//!
//! Safe to re-run — truncates and fully re-populates the table each time,
//! so it stays a straightforward mirror of whatever page-NNN.png files
//! currently exist on disk (new textbooks added, none removed).

use std::{env, fs, path::Path};

use anyhow::{Context, Result};
use serde::Deserialize;
use sqlx::PgPool;

#[derive(Deserialize)]
struct PageManifest {
    #[serde(rename = "pageNumber")]
    page_number: i32,
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

    // Repopulating from scratch: this table's meaning changed (full page
    // scans, not embedded-illustration crops) — a stale mix of both shapes
    // would double up on some pages and reference now-unindexed files.
    sqlx::query("TRUNCATE page_assets").execute(&pool).await?;

    let mut inserted = 0usize;
    let mut pages_examined = 0usize;
    let mut pages_without_image = 0usize;
    let mut skipped_parse_errors = 0usize;

    // storage/textbooks/processed/sslc/{subject_code}/{medium}/{version}/pages/*.json
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
                let pages_dir = version_dir.join("pages");
                let assets_dir = version_dir.join("assets");
                if !pages_dir.is_dir() {
                    continue;
                }

                for page_entry in fs::read_dir(&pages_dir)? {
                    let page_path = page_entry?.path();
                    if page_path.extension().and_then(|e| e.to_str()) != Some("json") {
                        continue;
                    }
                    pages_examined += 1;

                    let raw = match fs::read_to_string(&page_path) {
                        Ok(raw) => raw,
                        Err(_) => {
                            skipped_parse_errors += 1;
                            continue;
                        }
                    };
                    let manifest: PageManifest = match serde_json::from_str(&raw) {
                        Ok(m) => m,
                        Err(_) => {
                            skipped_parse_errors += 1;
                            continue;
                        }
                    };

                    let image_filename = format!("page-{:03}.png", manifest.page_number);
                    let image_path = assets_dir.join(&image_filename);
                    if !image_path.is_file() {
                        pages_without_image += 1;
                        continue;
                    }

                    // Relative to storage_dir, matching how nginx/the app's
                    // full_image_url helper serves everything under
                    // /textbook-assets/.
                    let relative_path = image_path
                        .strip_prefix(&storage_dir)
                        .unwrap_or(&image_path)
                        .to_string_lossy()
                        .replace('\\', "/");

                    let result = sqlx::query(
                        r#"
                        INSERT INTO page_assets
                          (subject_code, medium, chapter_number, page_number, asset_type, file_path)
                        VALUES ($1, $2, $3, $4, 'page', $5)
                        ON CONFLICT (subject_code, medium, chapter_number, page_number, file_path)
                        DO NOTHING
                        "#,
                    )
                    .bind(&subject_code)
                    .bind(&medium)
                    .bind(manifest.chapter_number)
                    .bind(manifest.page_number)
                    .bind(&relative_path)
                    .execute(&pool)
                    .await;

                    match result {
                        Ok(r) => inserted += r.rows_affected() as usize,
                        Err(e) => {
                            eprintln!("insert failed for {}: {e}", page_path.display());
                            skipped_parse_errors += 1;
                        }
                    }
                }
            }
        }
    }

    println!(
        "Examined {pages_examined} page manifests, inserted {inserted} page_assets rows \
         ({pages_without_image} pages had no page-NNN.png, {skipped_parse_errors} skipped on parse/insert errors)."
    );
    Ok(())
}
