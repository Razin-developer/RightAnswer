use std::sync::Arc;

use axum::{
    extract::State,
    http::HeaderMap,
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use serde_json::json;
use uuid::Uuid;

use crate::{
    admin,
    auth::{hash_password, require_user, sign_token, user_from_headers, verify_password},
    config::Config,
    db::Database,
    error::ApiError,
    models::{AiAnswer, AiChatRequest, AuthUser, Chat},
    openrouter::AiGateway,
    qdrant::QdrantGateway,
    rag::select_contexts,
};

#[derive(Clone)]
pub struct AppState {
    pub config: Config,
    pub db: Database,
    pub ai: AiGateway,
    pub qdrant: QdrantGateway,
}

#[derive(Serialize)]
pub struct ApiResponse<T> {
    success: bool,
    data: T,
}

pub fn api_router(state: Arc<AppState>) -> Router {
    Router::new()
        .route("/health", get(health))
        .route("/auth/register", post(register))
        .route("/auth/signup", post(register))
        .route("/auth/login", post(login))
        .route("/auth/me", get(me))
        .route("/ai/chat", post(ai_chat))
        .route("/ai/embeddings", post(embeddings))
        .route("/ai/rerank", post(rerank))
        .route("/chats", get(list_chats).post(upsert_chat))
        .route("/admin/metrics", get(admin::metrics))
        .with_state(state)
}

pub async fn health() -> Json<serde_json::Value> {
    Json(json!({
        "success": true,
        "data": {
            "status": "ok",
            "service": "right-answer-rust-api"
        }
    }))
}

#[derive(Deserialize)]
struct RegisterRequest {
    email: String,
    password: String,
    name: Option<String>,
    #[serde(rename = "fullName")]
    full_name: Option<String>,
}

async fn register(
    State(state): State<Arc<AppState>>,
    Json(body): Json<RegisterRequest>,
) -> Result<Json<ApiResponse<serde_json::Value>>, ApiError> {
    if body.email.trim().is_empty() || body.password.len() < 6 {
        return Err(ApiError::BadRequest(
            "email and a 6+ character password are required".into(),
        ));
    }
    let name = body
        .name
        .or(body.full_name)
        .unwrap_or_default()
        .trim()
        .to_string();
    let password_hash = hash_password(&body.password)?;
    let user = state
        .db
        .create_user(&body.email.trim().to_lowercase(), &password_hash, &name)
        .await?;
    let user = AuthUser::from(user);
    let token = sign_token(&user, &state.config.jwt_secret)?;
    Ok(ok(json!({ "token": token, "user": user })))
}

#[derive(Deserialize)]
struct LoginRequest {
    email: String,
    password: String,
}

async fn login(
    State(state): State<Arc<AppState>>,
    Json(body): Json<LoginRequest>,
) -> Result<Json<ApiResponse<serde_json::Value>>, ApiError> {
    let user = state
        .db
        .user_by_email(&body.email.trim().to_lowercase())
        .await?
        .ok_or_else(|| ApiError::Unauthorized("Invalid email or password".into()))?;
    if !verify_password(&body.password, &user.password_hash) {
        return Err(ApiError::Unauthorized("Invalid email or password".into()));
    }
    let user = AuthUser::from(user);
    let token = sign_token(&user, &state.config.jwt_secret)?;
    Ok(ok(json!({ "token": token, "user": user })))
}

async fn me(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> Result<Json<ApiResponse<serde_json::Value>>, ApiError> {
    let user = require_user(&state, &headers).await?;
    Ok(ok(json!({ "user": user })))
}

async fn ai_chat(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(body): Json<AiChatRequest>,
) -> Result<Json<ApiResponse<serde_json::Value>>, ApiError> {
    let user = user_from_headers(&state, &headers).await?;
    let question = body
        .question
        .as_deref()
        .or(body.message.as_deref())
        .or(body.content.as_deref())
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| ApiError::BadRequest("question is required".into()))?;

    let selected_contexts = select_contexts(&state, &body, question).await?;
    let answer = state.ai.chat(&body, &selected_contexts).await?;
    persist_ai_chat(&state, user.as_ref(), &body, question, &answer).await?;

    Ok(ok(json!({
        "answer": answer,
        "content": answer.content,
        "servedFrom": answer.served_from,
        "sourceChunks": answer.source_chunks
    })))
}

async fn persist_ai_chat(
    state: &AppState,
    user: Option<&AuthUser>,
    body: &AiChatRequest,
    question: &str,
    answer: &AiAnswer,
) -> Result<(), ApiError> {
    state
        .db
        .record_usage(
            user.map(|u| u.id),
            "/api/ai/chat",
            &answer.provider,
            &answer.model,
            answer.input_tokens,
            answer.output_tokens,
            &answer.served_from,
        )
        .await?;

    let Some(user) = user else {
        return Ok(());
    };
    let Some(local_id) = body.chat_local_id.as_deref() else {
        return Ok(());
    };
    let chat = state
        .db
        .find_or_create_chat(
            user.id,
            local_id,
            body.chat_name.as_deref().unwrap_or("New Chat"),
            body.subject_id.as_deref(),
            body.subject_name.as_deref(),
            &body.chapter_ids.clone().unwrap_or_default(),
            &body.chapter_names.clone().unwrap_or_default(),
        )
        .await?;

    let user_local = body
        .user_message_local_id
        .clone()
        .unwrap_or_else(|| Uuid::new_v4().to_string());
    let assistant_local = body
        .assistant_message_local_id
        .clone()
        .unwrap_or_else(|| Uuid::new_v4().to_string());
    state
        .db
        .insert_message(user.id, chat.id, &user_local, "user", question, 0, &[])
        .await?;
    state
        .db
        .insert_message(
            user.id,
            chat.id,
            &assistant_local,
            "assistant",
            &answer.content,
            answer.output_tokens,
            &answer.source_chunks,
        )
        .await?;
    state.db.touch_chat(chat.id).await?;
    Ok(())
}

#[derive(Deserialize)]
struct EmbeddingRequest {
    text: Option<String>,
    input: Option<String>,
}

async fn embeddings(
    State(state): State<Arc<AppState>>,
    Json(body): Json<EmbeddingRequest>,
) -> Result<Json<ApiResponse<serde_json::Value>>, ApiError> {
    let text = body
        .text
        .or(body.input)
        .ok_or_else(|| ApiError::BadRequest("text is required".into()))?;
    let embedding = state.ai.embed(&text).await?;
    Ok(ok(json!({
        "model": state.config.embedding_model,
        "embedding": embedding
    })))
}

#[derive(Deserialize)]
struct RerankRequest {
    question: Option<String>,
    query: Option<String>,
    documents: Vec<String>,
}

async fn rerank(
    State(state): State<Arc<AppState>>,
    Json(body): Json<RerankRequest>,
) -> Result<Json<ApiResponse<serde_json::Value>>, ApiError> {
    let question = body
        .question
        .or(body.query)
        .ok_or_else(|| ApiError::BadRequest("question is required".into()))?;
    let documents = state.ai.rerank(&question, &body.documents).await;
    Ok(ok(json!({ "documents": documents })))
}

async fn list_chats(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> Result<Json<ApiResponse<serde_json::Value>>, ApiError> {
    let user = require_user(&state, &headers).await?;
    let chats = state.db.list_chats(user.id).await?;
    Ok(ok(json!({ "chats": chats })))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct UpsertChatRequest {
    local_id: String,
    name: Option<String>,
    subject_id: Option<String>,
    subject_name: Option<String>,
    chapter_ids: Option<Vec<String>>,
    chapter_names: Option<Vec<String>>,
}

async fn upsert_chat(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(body): Json<UpsertChatRequest>,
) -> Result<Json<ApiResponse<serde_json::Value>>, ApiError> {
    let user = require_user(&state, &headers).await?;
    let chat: Chat = state
        .db
        .find_or_create_chat(
            user.id,
            &body.local_id,
            body.name.as_deref().unwrap_or("New Chat"),
            body.subject_id.as_deref(),
            body.subject_name.as_deref(),
            &body.chapter_ids.unwrap_or_default(),
            &body.chapter_names.unwrap_or_default(),
        )
        .await?;
    Ok(ok(json!({ "chat": chat })))
}

pub fn ok<T: Serialize>(data: T) -> Json<ApiResponse<T>> {
    Json(ApiResponse {
        success: true,
        data,
    })
}
