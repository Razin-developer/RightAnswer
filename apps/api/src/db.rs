use std::time::Duration;

use sqlx::{postgres::PgPoolOptions, PgPool};
use uuid::Uuid;

use crate::models::{CachedAnswer, Chat, ChatMessage, User};

#[derive(Clone)]
pub struct Database {
    pub pool: PgPool,
}

impl Database {
    pub async fn connect(database_url: &str) -> anyhow::Result<Self> {
        let pool = PgPoolOptions::new()
            .max_connections(20)
            .acquire_timeout(Duration::from_secs(10))
            .connect(database_url)
            .await?;
        Ok(Self { pool })
    }

    pub async fn migrate(&self) -> anyhow::Result<()> {
        sqlx::migrate!("./migrations").run(&self.pool).await?;
        Ok(())
    }

    /// Subject/chapter catalog for the app's optional chapter picker. Reads
    /// from the Prisma-managed textbook schema (not this crate's own
    /// migrations) — only the currently active textbook version per subject
    /// is included.
    pub async fn list_catalog(&self) -> Result<Vec<CatalogSubject>, sqlx::Error> {
        let rows = sqlx::query_as::<_, CatalogRow>(
            r#"
            SELECT
              s.id::text AS subject_id,
              s.name AS subject_name,
              s.code AS subject_code,
              ch.id::text AS chapter_id,
              ch.chapter_number,
              ch.title AS chapter_title
            FROM "Subject" s
            JOIN "Textbook" t ON t.subject_id = s.id
            JOIN "TextbookVersion" tv ON tv.textbook_id = t.id AND tv.is_active = true
            JOIN "Chapter" ch ON ch.textbook_version_id = tv.id
            WHERE s.active = true
            ORDER BY s.name, ch.chapter_number
            "#,
        )
        .fetch_all(&self.pool)
        .await?;

        let mut subjects: Vec<CatalogSubject> = Vec::new();
        for row in rows {
            let subject = match subjects.last_mut() {
                Some(existing) if existing.id == row.subject_id => existing,
                _ => {
                    subjects.push(CatalogSubject {
                        id: row.subject_id.clone(),
                        name: row.subject_name.clone(),
                        code: row.subject_code.clone(),
                        chapters: Vec::new(),
                    });
                    subjects.last_mut().unwrap()
                }
            };
            subject.chapters.push(CatalogChapter {
                id: row.chapter_id,
                number: row.chapter_number,
                title: row.chapter_title,
            });
        }
        Ok(subjects)
    }

    pub async fn create_user(
        &self,
        email: &str,
        password_hash: &str,
        name: &str,
    ) -> Result<User, sqlx::Error> {
        sqlx::query_as::<_, User>(
            r#"
            INSERT INTO users (email, password_hash, name)
            VALUES ($1, $2, $3)
            RETURNING id, email, password_hash, name, role, created_at
            "#,
        )
        .bind(email)
        .bind(password_hash)
        .bind(name)
        .fetch_one(&self.pool)
        .await
    }

    pub async fn user_by_email(&self, email: &str) -> Result<Option<User>, sqlx::Error> {
        sqlx::query_as::<_, User>(
            "SELECT id, email, password_hash, name, role, created_at FROM users WHERE email = $1",
        )
        .bind(email)
        .fetch_optional(&self.pool)
        .await
    }

    pub async fn user_by_id(&self, id: Uuid) -> Result<Option<User>, sqlx::Error> {
        sqlx::query_as::<_, User>(
            "SELECT id, email, password_hash, name, role, created_at FROM users WHERE id = $1",
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await
    }

    #[allow(clippy::too_many_arguments)]
    pub async fn find_or_create_chat(
        &self,
        owner_id: Uuid,
        local_id: &str,
        name: &str,
        subject_id: Option<&str>,
        subject_name: Option<&str>,
        chapter_ids: &[String],
        chapter_names: &[String],
    ) -> Result<Chat, sqlx::Error> {
        sqlx::query_as::<_, Chat>(
            r#"
            INSERT INTO chats
              (owner_id, local_id, name, subject_id, subject_name, chapter_ids, chapter_names)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            ON CONFLICT (owner_id, local_id) DO UPDATE SET updated_at = chats.updated_at
            RETURNING id, owner_id, local_id, name, subject_id, subject_name,
              chapter_ids, chapter_names, is_temporary, is_pinned, created_at, updated_at
            "#,
        )
        .bind(owner_id)
        .bind(local_id)
        .bind(name)
        .bind(subject_id)
        .bind(subject_name)
        .bind(chapter_ids)
        .bind(chapter_names)
        .fetch_one(&self.pool)
        .await
    }

    pub async fn list_chats(&self, owner_id: Uuid) -> Result<Vec<Chat>, sqlx::Error> {
        sqlx::query_as::<_, Chat>(
            r#"
            SELECT id, owner_id, local_id, name, subject_id, subject_name,
              chapter_ids, chapter_names, is_temporary, is_pinned, created_at, updated_at
            FROM chats
            WHERE owner_id = $1
            ORDER BY is_pinned DESC, updated_at DESC
            "#,
        )
        .bind(owner_id)
        .fetch_all(&self.pool)
        .await
    }

    #[allow(clippy::too_many_arguments)]
    pub async fn insert_message(
        &self,
        owner_id: Uuid,
        chat_id: Uuid,
        local_id: &str,
        role: &str,
        content: &str,
        token_count: i32,
        source_chunks: &[String],
    ) -> Result<ChatMessage, sqlx::Error> {
        sqlx::query_as::<_, ChatMessage>(
            r#"
            INSERT INTO chat_messages
              (owner_id, chat_id, local_id, role, content, token_count, source_chunks)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            ON CONFLICT (chat_id, local_id) DO UPDATE SET content = EXCLUDED.content
            RETURNING id, owner_id, chat_id, local_id, role, content,
              response_language, response_length, reasoning_level, token_count, source_chunks, created_at
            "#,
        )
        .bind(owner_id)
        .bind(chat_id)
        .bind(local_id)
        .bind(role)
        .bind(content)
        .bind(token_count)
        .bind(source_chunks)
        .fetch_one(&self.pool)
        .await
    }

    pub async fn touch_chat(&self, chat_id: Uuid) -> Result<(), sqlx::Error> {
        sqlx::query("UPDATE chats SET updated_at = now() WHERE id = $1")
            .bind(chat_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    #[allow(clippy::too_many_arguments)]
    pub async fn record_usage(
        &self,
        user_id: Option<Uuid>,
        route: &str,
        provider: &str,
        model: &str,
        input_tokens: i32,
        output_tokens: i32,
        served_from: &str,
    ) -> Result<(), sqlx::Error> {
        let estimated = estimate_cost(model, input_tokens, output_tokens);
        sqlx::query(
            r#"
            INSERT INTO ai_usage_events
              (user_id, route, provider, model, input_tokens, output_tokens, estimated_cost_usd, served_from)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            "#,
        )
        .bind(user_id)
        .bind(route)
        .bind(provider)
        .bind(model)
        .bind(input_tokens)
        .bind(output_tokens)
        .bind(estimated)
        .bind(served_from)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn lookup_exact_cache(
        &self,
        exact_key: &str,
    ) -> Result<Option<CachedAnswer>, sqlx::Error> {
        let answer = sqlx::query_as::<_, CachedAnswer>(
            r#"
            UPDATE answer_cache
            SET hit_count = hit_count + 1, updated_at = now()
            WHERE exact_key = $1
            RETURNING answer, model, provider, source_chunks, subject_id, subject_name, chapter_ids
            "#,
        )
        .bind(exact_key)
        .fetch_optional(&self.pool)
        .await?;
        Ok(answer)
    }

    #[allow(clippy::too_many_arguments)]
    pub async fn lookup_semantic_cache(
        &self,
        embedding: &[f32],
        threshold: f32,
        language: Option<&str>,
        response_length: &str,
        reasoning_level: &str,
        subject_id: Option<&str>,
        chapter_ids: &[String],
    ) -> Result<Option<CachedAnswer>, sqlx::Error> {
        if embedding.is_empty() {
            return Ok(None);
        }

        let candidates = sqlx::query_as::<_, CacheCandidate>(
            r#"
            SELECT id, answer, model, provider, source_chunks, embedding, subject_id, subject_name, chapter_ids
            FROM answer_cache
            WHERE cardinality(embedding) = $1
              AND ($2::text IS NULL OR language = $2)
              AND response_length = $3
              AND reasoning_level = $4
              AND ($5::text IS NULL OR subject_id = $5)
              AND chapter_ids = $6
            ORDER BY updated_at DESC
            LIMIT 80
            "#,
        )
        .bind(embedding.len() as i32)
        .bind(language)
        .bind(response_length)
        .bind(reasoning_level)
        .bind(subject_id)
        .bind(chapter_ids)
        .fetch_all(&self.pool)
        .await?;

        let mut best: Option<(CacheCandidate, f32)> = None;
        for candidate in candidates {
            let score = cosine_similarity_f64(&candidate.embedding, embedding);
            if score >= threshold && best.as_ref().map(|(_, best)| score > *best).unwrap_or(true) {
                best = Some((candidate, score));
            }
        }

        let Some((candidate, _)) = best else {
            return Ok(None);
        };
        sqlx::query(
            "UPDATE answer_cache SET hit_count = hit_count + 1, updated_at = now() WHERE id = $1",
        )
        .bind(candidate.id)
        .execute(&self.pool)
        .await?;
        Ok(Some(CachedAnswer {
            answer: candidate.answer,
            model: candidate.model,
            provider: candidate.provider,
            source_chunks: candidate.source_chunks,
            subject_id: candidate.subject_id,
            subject_name: candidate.subject_name,
            chapter_ids: candidate.chapter_ids,
        }))
    }

    #[allow(clippy::too_many_arguments)]
    pub async fn store_answer_cache(
        &self,
        exact_key: &str,
        normalized_question: &str,
        question: &str,
        answer: &str,
        embedding: &[f32],
        model: &str,
        provider: &str,
        language: Option<&str>,
        response_length: &str,
        reasoning_level: &str,
        subject_id: Option<&str>,
        subject_name: Option<&str>,
        chapter_ids: &[String],
        source_chunks: &[String],
        input_tokens: i32,
        output_tokens: i32,
    ) -> Result<(), sqlx::Error> {
        let embedding = embedding
            .iter()
            .map(|value| *value as f64)
            .collect::<Vec<_>>();
        sqlx::query(
            r#"
            INSERT INTO answer_cache
              (exact_key, normalized_question, question, answer, embedding, model, provider,
               language, response_length, reasoning_level, subject_id, subject_name, chapter_ids,
               source_chunks, input_tokens, output_tokens)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
            ON CONFLICT (exact_key) DO UPDATE SET
              answer = EXCLUDED.answer,
              embedding = EXCLUDED.embedding,
              model = EXCLUDED.model,
              provider = EXCLUDED.provider,
              source_chunks = EXCLUDED.source_chunks,
              input_tokens = EXCLUDED.input_tokens,
              output_tokens = EXCLUDED.output_tokens,
              updated_at = now()
            "#,
        )
        .bind(exact_key)
        .bind(normalized_question)
        .bind(question)
        .bind(answer)
        .bind(&embedding)
        .bind(model)
        .bind(provider)
        .bind(language)
        .bind(response_length)
        .bind(reasoning_level)
        .bind(subject_id)
        .bind(subject_name)
        .bind(chapter_ids)
        .bind(source_chunks)
        .bind(input_tokens)
        .bind(output_tokens)
        .execute(&self.pool)
        .await?;
        Ok(())
    }
}

#[derive(sqlx::FromRow)]
struct CatalogRow {
    subject_id: String,
    subject_name: String,
    subject_code: String,
    chapter_id: String,
    chapter_number: i32,
    chapter_title: String,
}

#[derive(serde::Serialize)]
pub struct CatalogChapter {
    pub id: String,
    pub number: i32,
    pub title: String,
}

#[derive(serde::Serialize)]
pub struct CatalogSubject {
    pub id: String,
    pub name: String,
    pub code: String,
    pub chapters: Vec<CatalogChapter>,
}

#[derive(sqlx::FromRow)]
struct CacheCandidate {
    id: Uuid,
    answer: String,
    model: String,
    provider: String,
    source_chunks: Vec<String>,
    embedding: Vec<f64>,
    subject_id: Option<String>,
    subject_name: Option<String>,
    chapter_ids: Vec<String>,
}

fn estimate_cost(model: &str, input_tokens: i32, output_tokens: i32) -> f64 {
    let (input_per_million, output_per_million) =
        if model.contains("gemma-4") || model.contains("reasoning") {
            (0.20, 0.40)
        } else {
            (0.05, 0.10)
        };
    (input_tokens as f64 / 1_000_000.0) * input_per_million
        + (output_tokens as f64 / 1_000_000.0) * output_per_million
}

fn cosine_similarity_f64(left: &[f64], right: &[f32]) -> f32 {
    if left.len() != right.len() || left.is_empty() {
        return 0.0;
    }
    let mut dot = 0.0;
    let mut left_norm = 0.0;
    let mut right_norm = 0.0;
    for (a, b) in left.iter().zip(right.iter()) {
        let b = *b as f64;
        dot += a * b;
        left_norm += a * a;
        right_norm += b * b;
    }
    if left_norm == 0.0 || right_norm == 0.0 {
        0.0
    } else {
        (dot / (left_norm.sqrt() * right_norm.sqrt())) as f32
    }
}
