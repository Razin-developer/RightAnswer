use std::{sync::Arc, time::Duration};

use axum::{
    extract::State,
    http::HeaderMap,
    routing::{get, post},
    Json, Router,
};
use governor::middleware::NoOpMiddleware;
use serde::{Deserialize, Serialize};
use serde_json::json;
use sha2::{Digest, Sha256};
use tower_governor::{
    governor::GovernorConfigBuilder, key_extractor::PeerIpKeyExtractor, GovernorLayer,
};
use uuid::Uuid;

use crate::{
    admin,
    auth::{hash_password, require_user, sign_token, user_from_headers, verify_password},
    config::Config,
    db::Database,
    error::ApiError,
    models::{AiAnswer, AiChatRequest, AuthUser, CachedAnswer, Chat},
    openrouter::AiGateway,
    qdrant::QdrantGateway,
    rag::{select_contexts, ContextsOutcome},
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

/// Rate limits brute-forceable / cost-bearing endpoints (auth and AI calls) by
/// peer IP. Keeps credential stuffing and anonymous AI-cost abuse bounded
/// without touching the rest of the router.
fn governed_layer(
    per_second: u64,
    burst_size: u32,
) -> GovernorLayer<PeerIpKeyExtractor, NoOpMiddleware, axum::body::Body> {
    let config = Arc::new(
        GovernorConfigBuilder::default()
            .per_second(per_second)
            .burst_size(burst_size)
            .finish()
            .expect("valid governor config"),
    );

    // The governor keeps per-key state forever unless it is periodically
    // swept; spawn a background task to evict stale entries.
    let cleanup_config = config.clone();
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(Duration::from_secs(60)).await;
            cleanup_config.limiter().retain_recent();
        }
    });

    GovernorLayer::new(config)
}

pub fn api_router(state: Arc<AppState>) -> Router {
    let auth_routes = Router::new()
        .route("/auth/register", post(register))
        .route("/auth/signup", post(register))
        .route("/auth/login", post(login))
        .layer(governed_layer(1, 5));

    let ai_routes = Router::new()
        .route("/ai/chat", post(ai_chat))
        .route("/ai/embeddings", post(embeddings))
        .route("/ai/rerank", post(rerank))
        .layer(governed_layer(1, 10));

    Router::new()
        .route("/health", get(health))
        .route("/catalog", get(catalog))
        .route("/auth/me", get(me))
        .route("/chats", get(list_chats).post(upsert_chat))
        .route("/admin/metrics", get(admin::metrics))
        .merge(auth_routes)
        .merge(ai_routes)
        .with_state(state)
}

async fn catalog(
    State(state): State<Arc<AppState>>,
) -> Result<Json<ApiResponse<serde_json::Value>>, ApiError> {
    let subjects = state.db.list_catalog().await?;
    Ok(ok(json!({ "subjects": subjects })))
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

    let normalized_question = normalize_question(question);
    let response_length = body.response_length.as_deref().unwrap_or("normal");
    let reasoning_level = body.reasoning_level.as_deref().unwrap_or("mid");
    let chapter_ids = normalized_chapter_ids(&body);
    let exact_key = cache_key(
        &normalized_question,
        body.response_language.as_deref(),
        response_length,
        reasoning_level,
        body.subject_id.as_deref(),
        &chapter_ids,
        body.confirm_beta_chapter_id.as_deref(),
    );

    if let Some(cached) = state
        .db
        .lookup_exact_cache(&exact_key)
        .await?
        .filter(|cached| !is_degenerate_answer(&cached.answer))
    {
        let context_meta = cache_context_meta(&cached);
        let answer = cached_answer(cached, "exact-cache", &context_meta);
        persist_ai_chat(
            &state,
            user.as_ref(),
            &body,
            question,
            &answer,
            &context_meta,
        )
        .await?;
        return Ok(ok(json!({
            "answer": answer,
            "content": answer.content,
            "speechText": answer.speech_text,
            "blocks": answer.blocks,
            "servedFrom": answer.served_from,
            "sourceChunks": answer.source_chunks,
            "sources": answer.sources,
            "subjectId": context_meta.subject_id,
            "subjectName": context_meta.subject_name,
            "chapterId": context_meta.chapter_id,
            "chapterName": context_meta.chapter_name
        })));
    }

    let question_embedding = state.ai.embed(question).await.unwrap_or_default();
    let semantic_cached = if body.confirm_beta_chapter_id.is_some() {
        // Never consult semantic cache for a beta-confirmed request: fuzzy
        // matching ignores confirmation state entirely, so it could hand
        // back an unrelated cached answer instead of honoring the explicit
        // bypass. Always regenerate fresh for these.
        None
    } else {
        state
            .db
            .lookup_semantic_cache(
                &question_embedding,
                state.config.semantic_cache_threshold,
                body.response_language.as_deref(),
                response_length,
                reasoning_level,
                body.subject_id.as_deref(),
                &chapter_ids,
            )
            .await?
            .filter(|cached| !is_degenerate_answer(&cached.answer))
    };
    if let Some(cached) = semantic_cached {
        let context_meta = cache_context_meta(&cached);
        let answer = cached_answer(cached, "semantic-cache", &context_meta);
        persist_ai_chat(
            &state,
            user.as_ref(),
            &body,
            question,
            &answer,
            &context_meta,
        )
        .await?;
        return Ok(ok(json!({
            "answer": answer,
            "content": answer.content,
            "speechText": answer.speech_text,
            "blocks": answer.blocks,
            "servedFrom": answer.served_from,
            "sourceChunks": answer.source_chunks,
            "sources": answer.sources,
            "subjectId": context_meta.subject_id,
            "subjectName": context_meta.subject_name,
            "chapterId": context_meta.chapter_id,
            "chapterName": context_meta.chapter_name
        })));
    }

    let outcome = select_contexts(&state, &body, question, Some(&question_embedding)).await?;
    let selected = match outcome {
        ContextsOutcome::Ready(selected) => selected,
        ContextsOutcome::NeedsBetaConfirmation(beta) => {
            return Ok(ok(json!({
                "needsBetaConfirmation": true,
                "chapterId": beta.chapter_id,
                "chapterName": beta.chapter_name,
                "subjectName": beta.subject_name,
                "message": format!(
                    "\"{}\" from {} is in your syllabus, but that content is still in beta. Do you want the response anyway?",
                    beta.chapter_name, beta.subject_name
                )
            })));
        }
    };
    let answer = state.ai.chat(&body, &selected.sources).await?;
    let subject_id = selected
        .primary_meta
        .subject_id
        .as_deref()
        .or(body.subject_id.as_deref());
    let subject_name = selected
        .primary_meta
        .subject_name
        .as_deref()
        .or(body.subject_name.as_deref());
    // Beta-confirmed answers are never cached: exact-cache and
    // semantic-cache share the same answer_cache table, and semantic
    // lookup matches purely on embedding similarity + subject/chapter —
    // it has no way to know a cached row required confirmation. Caching
    // it would let a differently-worded, unconfirmed request semantically
    // match straight to bypassed beta content. These are rare/edge-case
    // requests, so losing caching here is a fine tradeoff for correctness.
    if body.confirm_beta_chapter_id.is_none() {
        let _ = state
            .db
            .store_answer_cache(
                &exact_key,
                &normalized_question,
                question,
                &answer.content,
                &question_embedding,
                &answer.model,
                &answer.provider,
                body.response_language.as_deref(),
                response_length,
                reasoning_level,
                subject_id,
                subject_name,
                &chapter_ids,
                &answer.source_chunks,
                answer.input_tokens,
                answer.output_tokens,
            )
            .await;
    }
    persist_ai_chat(
        &state,
        user.as_ref(),
        &body,
        question,
        &answer,
        &selected.primary_meta,
    )
    .await?;

    Ok(ok(json!({
        "answer": answer,
        "content": answer.content,
        "speechText": answer.speech_text,
        "blocks": answer.blocks,
        "servedFrom": answer.served_from,
        "sourceChunks": answer.source_chunks,
        "sources": answer.sources,
        "subjectId": subject_id,
        "subjectName": subject_name,
        "chapterId": selected.primary_meta.chapter_id,
        "chapterName": selected.primary_meta.chapter_name
    })))
}

async fn persist_ai_chat(
    state: &AppState,
    user: Option<&AuthUser>,
    body: &AiChatRequest,
    question: &str,
    answer: &AiAnswer,
    context_meta: &crate::rag::ContextMeta,
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
    let subject_id = context_meta
        .subject_id
        .as_deref()
        .or(body.subject_id.as_deref());
    let subject_name = context_meta
        .subject_name
        .as_deref()
        .or(body.subject_name.as_deref());
    let chapter_ids: Vec<String> = context_meta
        .chapter_id
        .clone()
        .into_iter()
        .collect::<Vec<_>>();
    let chapter_names: Vec<String> = context_meta
        .chapter_name
        .clone()
        .into_iter()
        .collect::<Vec<_>>();
    let fallback_chapter_ids = body.chapter_ids.clone().unwrap_or_default();
    let fallback_chapter_names = body.chapter_names.clone().unwrap_or_default();
    let chat = state
        .db
        .find_or_create_chat(
            user.id,
            local_id,
            body.chat_name.as_deref().unwrap_or("New Chat"),
            subject_id,
            subject_name,
            if chapter_ids.is_empty() {
                &fallback_chapter_ids
            } else {
                &chapter_ids
            },
            if chapter_names.is_empty() {
                &fallback_chapter_names
            } else {
                &chapter_names
            },
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

/// Guards against ever serving a broken cached answer (e.g. a degenerate
/// "{}" JSON envelope that slipped through before a prompt/extraction fix)
/// forever. Treated as a cache miss, not an error — falls through to fresh
/// generation.
fn is_degenerate_answer(answer: &str) -> bool {
    let trimmed = answer.trim();
    trimmed.is_empty() || trimmed == "{}"
}

fn cache_context_meta(cached: &CachedAnswer) -> crate::rag::ContextMeta {
    crate::rag::ContextMeta {
        subject_id: cached.subject_id.clone(),
        subject_name: cached.subject_name.clone(),
        chapter_id: cached.chapter_ids.first().cloned(),
        chapter_name: None,
    }
}

fn cached_answer(
    cached: CachedAnswer,
    served_from: &str,
    context_meta: &crate::rag::ContextMeta,
) -> AiAnswer {
    let sources = cached
        .source_chunks
        .iter()
        .map(|text| crate::models::SourceInfo {
            text: text.clone(),
            page_number: None,
            subject_name: context_meta.subject_name.clone(),
            chapter_name: context_meta.chapter_name.clone(),
        })
        .collect();
    AiAnswer {
        content: cached.answer,
        speech_text: None,
        blocks: None,
        served_from: served_from.into(),
        model: cached.model,
        provider: cached.provider,
        input_tokens: 0,
        output_tokens: 0,
        source_chunks: cached.source_chunks,
        sources,
    }
}

fn normalized_chapter_ids(body: &AiChatRequest) -> Vec<String> {
    let mut chapter_ids = body.chapter_ids.clone().unwrap_or_default();
    chapter_ids.sort();
    chapter_ids.dedup();
    chapter_ids
}

fn normalize_question(question: &str) -> String {
    question
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || ch.is_whitespace() {
                ch.to_ascii_lowercase()
            } else {
                ' '
            }
        })
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

#[allow(clippy::too_many_arguments)]
fn cache_key(
    normalized_question: &str,
    language: Option<&str>,
    response_length: &str,
    reasoning_level: &str,
    subject_id: Option<&str>,
    chapter_ids: &[String],
    confirm_beta_chapter_id: Option<&str>,
) -> String {
    // confirm_beta_chapter_id is part of the key deliberately: a
    // beta-confirmed answer must never be served back to a plain,
    // unconfirmed request for the same question — that would silently
    // defeat the beta gate for every user after the first confirmation.
    let input = json!({
        "question": normalized_question,
        "language": language.unwrap_or(""),
        "responseLength": response_length,
        "reasoningLevel": reasoning_level,
        "subjectId": subject_id.unwrap_or(""),
        "chapterIds": chapter_ids,
        "confirmBetaChapterId": confirm_beta_chapter_id.unwrap_or(""),
    })
    .to_string();
    let digest = Sha256::digest(input.as_bytes());
    format!("{digest:x}")
}
