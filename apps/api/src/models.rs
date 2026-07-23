use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, FromRow)]
pub struct User {
    pub id: Uuid,
    pub email: String,
    #[serde(skip_serializing)]
    pub password_hash: String,
    pub name: String,
    pub role: String,
    pub plan: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthUser {
    pub id: Uuid,
    pub email: String,
    pub name: String,
    pub role: String,
    pub plan: String,
}

impl From<User> for AuthUser {
    fn from(user: User) -> Self {
        Self {
            id: user.id,
            email: user.email,
            name: user.name,
            role: user.role,
            plan: user.plan,
        }
    }
}

#[derive(Debug, Clone, Serialize, FromRow)]
pub struct Chat {
    pub id: Uuid,
    pub owner_id: Uuid,
    pub local_id: String,
    pub name: String,
    pub subject_id: Option<String>,
    pub subject_name: Option<String>,
    pub chapter_ids: Vec<String>,
    pub chapter_names: Vec<String>,
    pub is_temporary: bool,
    pub is_pinned: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, FromRow)]
pub struct ChatMessage {
    pub id: Uuid,
    pub owner_id: Uuid,
    pub chat_id: Uuid,
    pub local_id: String,
    pub role: String,
    pub content: String,
    pub response_language: Option<String>,
    pub response_length: Option<String>,
    pub reasoning_level: Option<String>,
    pub token_count: i32,
    pub source_chunks: Vec<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, FromRow)]
#[serde(rename_all = "camelCase")]
pub struct ShareLink {
    pub id: Uuid,
    #[allow(dead_code)]
    #[serde(skip_serializing)]
    pub owner_id: Uuid,
    pub token: String,
    pub share_type: String,
    pub ref_id: Uuid,
    pub access_level: String,
    pub use_count: i32,
    pub expires_at: DateTime<Utc>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, FromRow)]
pub struct ContentShare {
    #[allow(dead_code)]
    pub id: Uuid,
    #[allow(dead_code)]
    pub owner_id: Uuid,
    pub filename: String,
    pub mime_type: String,
    pub bytes: Vec<u8>,
    #[allow(dead_code)]
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, FromRow)]
#[serde(rename_all = "camelCase")]
pub struct Payment {
    pub id: Uuid,
    #[allow(dead_code)]
    #[serde(skip_serializing)]
    pub user_id: Uuid,
    pub plan: String,
    pub amount_inr: i64,
    pub credits_usd: f64,
    pub status: String,
    #[allow(dead_code)]
    pub provider: String,
    #[allow(dead_code)]
    pub provider_ref: Option<String>,
    pub created_at: DateTime<Utc>,
    pub completed_at: Option<DateTime<Utc>>,
}

/// One synced exam or study plan — the full local record (exam+questions,
/// or plan+days+tasks) stored opaquely in `data`, matching the client's
/// own local SQLite shape rather than a normalized server schema. See
/// migrations/0004_exams_study_plans.sql.
#[derive(Debug, Clone, Serialize, FromRow)]
#[serde(rename_all = "camelCase")]
pub struct SyncedRecord {
    pub local_id: String,
    pub name: String,
    pub data: serde_json::Value,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatPromptMessage {
    pub role: String,
    pub content: String,
}

#[derive(Debug, Default, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AiChatRequest {
    pub question: Option<String>,
    pub message: Option<String>,
    pub content: Option<String>,
    pub system_prompt: Option<String>,
    pub history: Option<Vec<ChatPromptMessage>>,
    pub response_length: Option<String>,
    pub reasoning_level: Option<String>,
    pub response_language: Option<String>,
    pub subject_id: Option<String>,
    pub subject_name: Option<String>,
    pub chapter_ids: Option<Vec<String>>,
    pub chapter_names: Option<Vec<String>>,
    pub contexts: Option<Vec<String>>,
    pub source_chunks: Option<Vec<String>>,
    pub temperature: Option<f32>,
    pub max_tokens: Option<u32>,
    pub json_mode: Option<bool>,
    pub response_format: Option<String>,
    pub rich_answer: Option<bool>,
    pub answer_format: Option<String>,
    pub chat_local_id: Option<String>,
    pub chat_name: Option<String>,
    pub user_message_local_id: Option<String>,
    pub assistant_message_local_id: Option<String>,
    /// Set when the client is re-sending a request after the user tapped
    /// "Yes" on the beta-chapter confirmation prompt (see rag::select_contexts).
    pub confirm_beta_chapter_id: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SourceInfo {
    pub text: String,
    pub page_number: Option<i32>,
    pub subject_name: Option<String>,
    pub chapter_name: Option<String>,
    /// Full, directly-fetchable URL to the source page's embedded
    /// illustration/diagram/table image, when the retrieved chunk has one
    /// (served as a static file by nginx — see content_assets::image_url).
    pub image_url: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AiAnswer {
    pub content: String,
    /// Clean speaker-only prose for TTS, when the model returned a rich/json
    /// envelope that included one. Falls back to None for plain answers.
    pub speech_text: Option<String>,
    /// Structured render blocks (markdown/math/table/geometry/...), passed
    /// through verbatim when the model returned a parseable rich envelope.
    pub blocks: Option<serde_json::Value>,
    pub served_from: String,
    pub model: String,
    pub provider: String,
    pub input_tokens: i32,
    pub output_tokens: i32,
    pub source_chunks: Vec<String>,
    pub sources: Vec<SourceInfo>,
}

#[derive(Debug, Clone, FromRow)]
pub struct CachedAnswer {
    pub answer: String,
    pub model: String,
    pub provider: String,
    pub source_chunks: Vec<String>,
    pub subject_id: Option<String>,
    pub subject_name: Option<String>,
    pub chapter_ids: Vec<String>,
}
