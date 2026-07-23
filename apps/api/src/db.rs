use std::time::Duration;

use base64::Engine;
use sqlx::{postgres::PgPoolOptions, PgPool};
use uuid::Uuid;

use crate::{
    content_policy::{is_chapter_enabled, ChapterInfo},
    models::{
        CachedAnswer, Chat, ChatMessage, ContentShare, Payment, ShareLink, SyncedRecord, User,
    },
};

/// 24 random bytes, base64url-encoded (no padding) — matches the
/// pre-migration Node backend's `randomBytes(24).toString("base64url")`,
/// so existing/cached share URLs have the same shape.
fn generate_share_token() -> String {
    use argon2::password_hash::rand_core::{OsRng, RngCore};
    let mut bytes = [0u8; 24];
    OsRng.fill_bytes(&mut bytes);
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes)
}

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

    /// Every chapter across every active textbook version, including
    /// currently-disabled ones (wrong medium, excluded subject, front
    /// matter) — used for beta-content gating decisions, not for display.
    pub async fn list_chapter_info(&self) -> Result<Vec<ChapterInfo>, sqlx::Error> {
        let rows = sqlx::query_as::<_, ChapterInfoRow>(
            r#"
            SELECT
              s.id::text AS subject_id,
              s.name AS subject_name,
              s.code AS subject_code,
              t.medium::text AS medium,
              t.part_label AS part_label,
              ch.id::text AS chapter_id,
              ch.chapter_number,
              ch.title AS chapter_title
            FROM "Subject" s
            JOIN "Textbook" t ON t.subject_id = s.id
            JOIN "TextbookVersion" tv ON tv.textbook_id = t.id AND tv.is_active = true
            JOIN "Chapter" ch ON ch.textbook_version_id = tv.id
            WHERE s.active = true
            ORDER BY s.id, t.part_label NULLS FIRST, ch.chapter_number
            "#,
        )
        .fetch_all(&self.pool)
        .await?;

        Ok(rows
            .into_iter()
            .map(|row| {
                let enabled =
                    is_chapter_enabled(&row.subject_code, &row.medium, row.chapter_number);
                ChapterInfo {
                    chapter_id: row.chapter_id,
                    chapter_number: row.chapter_number,
                    chapter_name: row.chapter_title,
                    subject_id: row.subject_id,
                    subject_name: row.subject_name,
                    subject_code: row.subject_code,
                    medium: row.medium,
                    part_label: row.part_label,
                    enabled,
                }
            })
            .collect())
    }

    /// Subject/part/chapter catalog for the app's optional chapter picker —
    /// enabled chapters only (see content_policy). Subjects whose textbook
    /// isn't split into volumes get a single part with `label: None`.
    pub async fn list_catalog(&self) -> Result<Vec<CatalogSubject>, sqlx::Error> {
        let chapters = self.list_chapter_info().await?;

        let mut subjects: Vec<CatalogSubject> = Vec::new();
        for chapter in chapters.into_iter().filter(|c| c.enabled) {
            let subject = match subjects.last_mut() {
                Some(existing) if existing.id == chapter.subject_id => existing,
                _ => {
                    subjects.push(CatalogSubject {
                        id: chapter.subject_id.clone(),
                        name: chapter.subject_name.clone(),
                        code: chapter.subject_code.clone(),
                        parts: Vec::new(),
                    });
                    subjects.last_mut().unwrap()
                }
            };
            let part = match subject.parts.last_mut() {
                Some(existing) if existing.label == chapter.part_label => existing,
                _ => {
                    subject.parts.push(CatalogPart {
                        label: chapter.part_label.clone(),
                        chapters: Vec::new(),
                    });
                    subject.parts.last_mut().unwrap()
                }
            };
            part.chapters.push(CatalogChapter {
                id: chapter.chapter_id,
                number: chapter.chapter_number,
                title: chapter.chapter_name,
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
            RETURNING id, email, password_hash, name, role, plan, created_at
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
            "SELECT id, email, password_hash, name, role, plan, created_at FROM users WHERE email = $1",
        )
        .bind(email)
        .fetch_optional(&self.pool)
        .await
    }

    pub async fn user_by_id(&self, id: Uuid) -> Result<Option<User>, sqlx::Error> {
        sqlx::query_as::<_, User>(
            "SELECT id, email, password_hash, name, role, plan, created_at FROM users WHERE id = $1",
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await
    }

    pub async fn update_user_name(&self, user_id: Uuid, name: &str) -> Result<User, sqlx::Error> {
        sqlx::query_as::<_, User>(
            r#"
            UPDATE users SET name = $2 WHERE id = $1
            RETURNING id, email, password_hash, name, role, plan, created_at
            "#,
        )
        .bind(user_id)
        .bind(name)
        .fetch_one(&self.pool)
        .await
    }

    pub async fn update_user_password(
        &self,
        user_id: Uuid,
        password_hash: &str,
    ) -> Result<(), sqlx::Error> {
        sqlx::query("UPDATE users SET password_hash = $2 WHERE id = $1")
            .bind(user_id)
            .bind(password_hash)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    // ── Exam / study-plan sync ──────────────────────────────────────────────
    // Both follow the identical shape (see SyncedRecord) — one row per
    // local record, upserted wholesale on every local save.

    pub async fn upsert_exam(
        &self,
        owner_id: Uuid,
        local_id: &str,
        name: &str,
        data: &serde_json::Value,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            r#"
            INSERT INTO exams (owner_id, local_id, name, data)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (owner_id, local_id)
              DO UPDATE SET name = $3, data = $4, updated_at = now()
            "#,
        )
        .bind(owner_id)
        .bind(local_id)
        .bind(name)
        .bind(data)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn list_exams(&self, owner_id: Uuid) -> Result<Vec<SyncedRecord>, sqlx::Error> {
        sqlx::query_as::<_, SyncedRecord>(
            "SELECT local_id, name, data, updated_at FROM exams WHERE owner_id = $1 ORDER BY updated_at DESC",
        )
        .bind(owner_id)
        .fetch_all(&self.pool)
        .await
    }

    pub async fn delete_exam(&self, owner_id: Uuid, local_id: &str) -> Result<(), sqlx::Error> {
        sqlx::query("DELETE FROM exams WHERE owner_id = $1 AND local_id = $2")
            .bind(owner_id)
            .bind(local_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    pub async fn upsert_study_plan(
        &self,
        owner_id: Uuid,
        local_id: &str,
        name: &str,
        data: &serde_json::Value,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            r#"
            INSERT INTO study_plans (owner_id, local_id, name, data)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (owner_id, local_id)
              DO UPDATE SET name = $3, data = $4, updated_at = now()
            "#,
        )
        .bind(owner_id)
        .bind(local_id)
        .bind(name)
        .bind(data)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn list_study_plans(&self, owner_id: Uuid) -> Result<Vec<SyncedRecord>, sqlx::Error> {
        sqlx::query_as::<_, SyncedRecord>(
            "SELECT local_id, name, data, updated_at FROM study_plans WHERE owner_id = $1 ORDER BY updated_at DESC",
        )
        .bind(owner_id)
        .fetch_all(&self.pool)
        .await
    }

    pub async fn delete_study_plan(
        &self,
        owner_id: Uuid,
        local_id: &str,
    ) -> Result<(), sqlx::Error> {
        sqlx::query("DELETE FROM study_plans WHERE owner_id = $1 AND local_id = $2")
            .bind(owner_id)
            .bind(local_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    // ── Plans / usage / payments ────────────────────────────────────────────

    pub async fn user_credit_balance(&self, user_id: Uuid) -> Result<f64, sqlx::Error> {
        sqlx::query_scalar::<_, f64>("SELECT credit_balance_usd FROM users WHERE id = $1")
            .bind(user_id)
            .fetch_one(&self.pool)
            .await
    }

    /// Number of `/api/ai/chat`-family requests (i.e. questions asked) by
    /// this user since UTC midnight today.
    pub async fn count_questions_today(&self, user_id: Uuid) -> Result<i64, sqlx::Error> {
        sqlx::query_scalar::<_, i64>(
            r#"
            SELECT COUNT(*) FROM ai_usage_events
            WHERE user_id = $1
              AND route IN ('/api/ai/chat', '/api/ai/chat/stream')
              AND created_at >= date_trunc('day', now())
            "#,
        )
        .bind(user_id)
        .fetch_one(&self.pool)
        .await
    }

    /// Total estimated OpenRouter/HackAI spend by this user since the start
    /// of the current ISO week (Monday, UTC) — the basis for the weekly
    /// credit limit.
    pub async fn sum_cost_this_week(&self, user_id: Uuid) -> Result<f64, sqlx::Error> {
        sqlx::query_scalar::<_, f64>(
            r#"
            SELECT COALESCE(SUM(estimated_cost_usd), 0) FROM ai_usage_events
            WHERE user_id = $1
              AND created_at >= date_trunc('week', now())
            "#,
        )
        .bind(user_id)
        .fetch_one(&self.pool)
        .await
    }

    pub async fn set_user_plan(&self, user_id: Uuid, plan: &str) -> Result<(), sqlx::Error> {
        sqlx::query("UPDATE users SET plan = $2 WHERE id = $1")
            .bind(user_id)
            .bind(plan)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    pub async fn add_credits(&self, user_id: Uuid, amount_usd: f64) -> Result<(), sqlx::Error> {
        sqlx::query("UPDATE users SET credit_balance_usd = credit_balance_usd + $2 WHERE id = $1")
            .bind(user_id)
            .bind(amount_usd)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    pub async fn create_payment(
        &self,
        user_id: Uuid,
        plan: &str,
        amount_inr: i64,
        credits_usd: f64,
    ) -> Result<Payment, sqlx::Error> {
        sqlx::query_as::<_, Payment>(
            r#"
            INSERT INTO payments (user_id, plan, amount_inr, credits_usd)
            VALUES ($1, $2, $3, $4)
            RETURNING id, user_id, plan, amount_inr, credits_usd, status,
              provider, provider_ref, created_at, completed_at
            "#,
        )
        .bind(user_id)
        .bind(plan)
        .bind(amount_inr)
        .bind(credits_usd)
        .fetch_one(&self.pool)
        .await
    }

    /// Marks a pending payment success/failed. Only ever transitions a
    /// `pending` row (idempotent against double-submits/retries of the
    /// mock success/failure buttons) — already-completed payments are left
    /// untouched and the caller gets back `None`.
    pub async fn complete_payment(
        &self,
        payment_id: Uuid,
        user_id: Uuid,
        status: &str,
    ) -> Result<Option<Payment>, sqlx::Error> {
        sqlx::query_as::<_, Payment>(
            r#"
            UPDATE payments SET status = $3, completed_at = now()
            WHERE id = $1 AND user_id = $2 AND status = 'pending'
            RETURNING id, user_id, plan, amount_inr, credits_usd, status,
              provider, provider_ref, created_at, completed_at
            "#,
        )
        .bind(payment_id)
        .bind(user_id)
        .bind(status)
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

    pub async fn find_chat_by_local_id(
        &self,
        owner_id: Uuid,
        local_id: &str,
    ) -> Result<Option<Chat>, sqlx::Error> {
        sqlx::query_as::<_, Chat>(
            r#"
            SELECT id, owner_id, local_id, name, subject_id, subject_name,
              chapter_ids, chapter_names, is_temporary, is_pinned, created_at, updated_at
            FROM chats
            WHERE owner_id = $1 AND local_id = $2
            "#,
        )
        .bind(owner_id)
        .bind(local_id)
        .fetch_optional(&self.pool)
        .await
    }

    pub async fn chat_by_id(&self, chat_id: Uuid) -> Result<Option<Chat>, sqlx::Error> {
        sqlx::query_as::<_, Chat>(
            r#"
            SELECT id, owner_id, local_id, name, subject_id, subject_name,
              chapter_ids, chapter_names, is_temporary, is_pinned, created_at, updated_at
            FROM chats
            WHERE id = $1
            "#,
        )
        .bind(chat_id)
        .fetch_optional(&self.pool)
        .await
    }

    pub async fn list_messages(&self, chat_id: Uuid) -> Result<Vec<ChatMessage>, sqlx::Error> {
        sqlx::query_as::<_, ChatMessage>(
            r#"
            SELECT id, owner_id, chat_id, local_id, role, content,
              response_language, response_length, reasoning_level, token_count, source_chunks, created_at
            FROM chat_messages
            WHERE chat_id = $1
            ORDER BY created_at ASC
            "#,
        )
        .bind(chat_id)
        .fetch_all(&self.pool)
        .await
    }

    /// Creates a 10-minute share link referencing an existing chat directly
    /// (no data duplication — the recipient fetches the live chat + its
    /// messages through the token).
    pub async fn create_chat_share(
        &self,
        owner_id: Uuid,
        chat_id: Uuid,
        access_level: &str,
    ) -> Result<ShareLink, sqlx::Error> {
        let token = generate_share_token();
        sqlx::query_as::<_, ShareLink>(
            r#"
            INSERT INTO share_links (owner_id, token, share_type, ref_id, access_level, expires_at)
            VALUES ($1, $2, 'chat', $3, $4, now() + interval '10 minutes')
            RETURNING id, owner_id, token, share_type, ref_id, access_level, use_count, expires_at, created_at
            "#,
        )
        .bind(owner_id)
        .bind(token)
        .bind(chat_id)
        .bind(access_level)
        .fetch_one(&self.pool)
        .await
    }

    /// Stores an uploaded content blob (an exam/study-plan export ZIP) and
    /// creates a 10-minute share link pointing at it.
    pub async fn create_content_share(
        &self,
        owner_id: Uuid,
        filename: &str,
        mime_type: &str,
        metadata: &serde_json::Value,
        bytes: &[u8],
    ) -> Result<ShareLink, sqlx::Error> {
        let content_id: Uuid = sqlx::query_scalar(
            r#"
            INSERT INTO content_shares (owner_id, filename, mime_type, metadata, bytes)
            VALUES ($1, $2, $3, $4, $5)
            RETURNING id
            "#,
        )
        .bind(owner_id)
        .bind(filename)
        .bind(mime_type)
        .bind(metadata)
        .bind(bytes)
        .fetch_one(&self.pool)
        .await?;

        let token = generate_share_token();
        sqlx::query_as::<_, ShareLink>(
            r#"
            INSERT INTO share_links (owner_id, token, share_type, ref_id, expires_at)
            VALUES ($1, $2, 'content', $3, now() + interval '10 minutes')
            RETURNING id, owner_id, token, share_type, ref_id, access_level, use_count, expires_at, created_at
            "#,
        )
        .bind(owner_id)
        .bind(token)
        .bind(content_id)
        .fetch_one(&self.pool)
        .await
    }

    /// Resolves a share token (only if not expired) and bumps its use
    /// count. Returns None for an invalid or expired token — callers
    /// shouldn't distinguish the two, both just mean "can't be used".
    pub async fn resolve_share(&self, token: &str) -> Result<Option<ShareLink>, sqlx::Error> {
        let share = sqlx::query_as::<_, ShareLink>(
            r#"
            UPDATE share_links
            SET use_count = use_count + 1
            WHERE token = $1 AND expires_at > now()
            RETURNING id, owner_id, token, share_type, ref_id, access_level, use_count, expires_at, created_at
            "#,
        )
        .bind(token)
        .fetch_optional(&self.pool)
        .await?;
        Ok(share)
    }

    pub async fn get_content_share(
        &self,
        content_id: Uuid,
    ) -> Result<Option<ContentShare>, sqlx::Error> {
        sqlx::query_as::<_, ContentShare>(
            r#"
            SELECT id, owner_id, filename, mime_type, bytes, created_at
            FROM content_shares
            WHERE id = $1
            "#,
        )
        .bind(content_id)
        .fetch_optional(&self.pool)
        .await
    }

    /// Partial update — only fields that are `Some` are changed. Returns
    /// `None` if no chat with this owner/local_id exists (not a distinct
    /// error case; the caller decides whether that's a 404).
    #[allow(clippy::too_many_arguments)]
    pub async fn update_chat_fields(
        &self,
        owner_id: Uuid,
        local_id: &str,
        name: Option<&str>,
        subject_id: Option<&str>,
        subject_name: Option<&str>,
        chapter_ids: Option<&[String]>,
        chapter_names: Option<&[String]>,
        is_pinned: Option<bool>,
    ) -> Result<Option<Chat>, sqlx::Error> {
        sqlx::query_as::<_, Chat>(
            r#"
            UPDATE chats SET
              name = COALESCE($3, name),
              subject_id = COALESCE($4, subject_id),
              subject_name = COALESCE($5, subject_name),
              chapter_ids = COALESCE($6, chapter_ids),
              chapter_names = COALESCE($7, chapter_names),
              is_pinned = COALESCE($8, is_pinned),
              updated_at = now()
            WHERE owner_id = $1 AND local_id = $2
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
        .bind(is_pinned)
        .fetch_optional(&self.pool)
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
struct ChapterInfoRow {
    subject_id: String,
    subject_name: String,
    subject_code: String,
    medium: String,
    part_label: Option<String>,
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
pub struct CatalogPart {
    pub label: Option<String>,
    pub chapters: Vec<CatalogChapter>,
}

#[derive(serde::Serialize)]
pub struct CatalogSubject {
    pub id: String,
    pub name: String,
    pub code: String,
    pub parts: Vec<CatalogPart>,
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

/// Rough per-model pricing tiers (USD per million tokens) for admin-dashboard
/// cost estimates — not exact invoiced pricing (HackAI/OpenRouter route
/// through several upstream providers whose rates aren't exposed per-call),
/// but distinguishes model families instead of one binary guess, so relative
/// cost between e.g. embeddings vs. reasoning chat is meaningful.
fn estimate_cost(model: &str, input_tokens: i32, output_tokens: i32) -> f64 {
    let (input_per_million, output_per_million) = if model.contains("embed") {
        (0.02, 0.0)
    } else if model.contains("vl") {
        // Vision calls: image tokens dominate real cost and aren't counted
        // here at all (no per-image token count from the provider), so
        // this consistently undercounts actual vision spend.
        (0.20, 0.40)
    } else if model.contains("gemma-4") || model.contains("qwen3-14b") {
        (0.20, 0.40)
    } else if model.contains("gemma-3") || model.contains("qwen3-8b") {
        (0.05, 0.10)
    } else {
        (0.10, 0.20)
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
