use std::time::Duration;

use sqlx::{postgres::PgPoolOptions, PgPool};
use uuid::Uuid;

use crate::models::{Chat, ChatMessage, User};

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
