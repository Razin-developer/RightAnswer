use std::{convert::Infallible, sync::Arc, time::Duration};

use axum::{
    body::Bytes,
    extract::{Multipart, Path, State},
    http::{header, HeaderMap},
    response::{
        sse::{Event, KeepAlive, KeepAliveStream, Sse},
        IntoResponse, Response,
    },
    routing::{get, post, put},
    Json, Router,
};
use futures_util::Stream;
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
    auth::{hash_password, require_user, sign_token, verify_password},
    config::Config,
    db::Database,
    error::ApiError,
    models::{AiAnswer, AiChatRequest, AuthUser, CachedAnswer, Chat, ChatMessage},
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
        .route("/auth/change-password", post(change_password))
        .layer(governed_layer(1, 5));

    let ai_routes = Router::new()
        .route("/ai/chat", post(ai_chat))
        .route("/ai/chat/stream", post(ai_chat_stream))
        .route("/ai/title", post(ai_title))
        .route("/ai/embeddings", post(embeddings))
        .route("/ai/rerank", post(rerank))
        .layer(governed_layer(1, 10));

    // Authenticated CRUD/data endpoints — not cost-bearing like ai_routes,
    // but every one of these previously had no rate limit at all beyond
    // whatever the client naturally does, so a compromised token (or a
    // buggy client stuck in a retry loop) could hammer the DB unbounded.
    // Generous limits since normal use (saving a chat message, syncing an
    // exam) is legitimately bursty.
    let data_routes = Router::new()
        .route("/chats", get(list_chats).post(upsert_chat))
        .route("/chats/by-local/{local_id}", put(update_chat))
        .route(
            "/chats/by-local/{local_id}/messages",
            post(add_chat_message),
        )
        .route("/chats/by-local/{local_id}/share", post(share_chat))
        .route("/content", post(upload_content))
        .route("/exams", get(list_exams))
        .route(
            "/exams/by-local/{local_id}",
            put(upsert_exam).delete(delete_exam),
        )
        .route("/study-plans", get(list_study_plans))
        .route(
            "/study-plans/by-local/{local_id}",
            put(upsert_study_plan).delete(delete_study_plan),
        )
        .route("/usage/me", get(usage_me))
        .route("/plans/checkout", post(plans_checkout))
        .route("/plans/payments/{id}/complete", post(complete_payment))
        .layer(governed_layer(5, 20));

    Router::new()
        .route("/health", get(health))
        .route("/catalog", get(catalog))
        .route("/auth/me", get(me).put(update_profile))
        .route("/share/{token}", get(resolve_share))
        .route("/plans", get(list_plans))
        .route("/admin/metrics", get(admin::metrics))
        .merge(auth_routes)
        .merge(ai_routes)
        .merge(data_routes)
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

#[derive(Deserialize)]
struct UpdateProfileRequest {
    name: Option<String>,
}

async fn update_profile(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(body): Json<UpdateProfileRequest>,
) -> Result<Json<ApiResponse<serde_json::Value>>, ApiError> {
    let user = require_user(&state, &headers).await?;
    let name = body
        .name
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| ApiError::BadRequest("name is required".into()))?;
    if name.chars().count() > 100 {
        return Err(ApiError::BadRequest(
            "name must be 100 characters or fewer".into(),
        ));
    }
    let updated = AuthUser::from(state.db.update_user_name(user.id, name).await?);
    Ok(ok(json!({ "user": updated })))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ChangePasswordRequest {
    old_password: String,
    new_password: String,
}

/// Requires the current password before setting a new one — this route is
/// rate-limited via `auth_routes`'s governed_layer for the same reason
/// login is, since it's brute-forceable against a known account.
async fn change_password(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(body): Json<ChangePasswordRequest>,
) -> Result<Json<ApiResponse<serde_json::Value>>, ApiError> {
    let user = require_user(&state, &headers).await?;
    if body.new_password.len() < 6 {
        return Err(ApiError::BadRequest(
            "New password must be at least 6 characters".into(),
        ));
    }
    let full_user = state
        .db
        .user_by_id(user.id)
        .await?
        .ok_or_else(|| ApiError::Unauthorized("Authentication required".into()))?;
    if !verify_password(&body.old_password, &full_user.password_hash) {
        return Err(ApiError::Unauthorized(
            "Current password is incorrect".into(),
        ));
    }
    let new_hash = hash_password(&body.new_password)?;
    state.db.update_user_password(user.id, &new_hash).await?;
    Ok(ok(json!({ "success": true })))
}

/// Public plan catalog — pricing/limits come straight from `PlanConfig`
/// (env-driven), so the client never hardcodes a price that could drift
/// from what the server actually charges/enforces.
async fn list_plans(State(state): State<Arc<AppState>>) -> Json<ApiResponse<serde_json::Value>> {
    let limits = &state.config.plans;
    ok(json!({
        "plans": [
            {
                "id": "hobby",
                "name": "Hobby",
                "priceInr": 0,
                "creditsUsd": 0.0,
                "dailyQuestionLimit": limits.hobby_daily_question_limit,
                "weeklyCreditUsd": limits.hobby_weekly_credit_usd,
                "studyPlans": false,
            },
            {
                "id": "pro",
                "name": "Pro",
                "priceInr": limits.pro_price_inr,
                "creditsUsd": limits.pro_credits_usd,
                "dailyQuestionLimit": limits.pro_daily_question_limit,
                "weeklyCreditUsd": limits.pro_weekly_credit_usd,
                "studyPlans": true,
            },
            {
                "id": "scholar",
                "name": "Scholar",
                "priceInr": limits.scholar_price_inr,
                "creditsUsd": limits.scholar_credits_usd,
                "dailyQuestionLimit": limits.scholar_daily_question_limit,
                "weeklyCreditUsd": limits.scholar_weekly_credit_usd,
                "studyPlans": true,
            },
        ]
    }))
}

fn plan_limits(config: &Config, plan: &str) -> (i64, f64) {
    let limits = &config.plans;
    match plan {
        "scholar" => (
            limits.scholar_daily_question_limit,
            limits.scholar_weekly_credit_usd,
        ),
        "pro" => (
            limits.pro_daily_question_limit,
            limits.pro_weekly_credit_usd,
        ),
        _ => (
            limits.hobby_daily_question_limit,
            limits.hobby_weekly_credit_usd,
        ),
    }
}

/// Usage snapshot for the current billing period — daily question count
/// and weekly credit spend against the caller's plan, plus whether the
/// client should show the "getting close to your limit" warning banner.
async fn usage_me(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> Result<Json<ApiResponse<serde_json::Value>>, ApiError> {
    let user = require_user(&state, &headers).await?;
    let (daily_limit, weekly_credit) = plan_limits(&state.config, &user.plan);

    let questions_today = state.db.count_questions_today(user.id).await?;
    let spent_this_week = state.db.sum_cost_this_week(user.id).await?;
    let credit_balance = state.db.user_credit_balance(user.id).await?;
    let weekly_allowance = weekly_credit + credit_balance;

    let daily_percent = if daily_limit > 0 {
        (questions_today as f64 / daily_limit as f64) * 100.0
    } else {
        0.0
    };
    let weekly_percent = if weekly_allowance > 0.0 {
        (spent_this_week / weekly_allowance) * 100.0
    } else {
        0.0
    };
    let usage_percent = daily_percent.max(weekly_percent);
    let threshold = state.config.plans.usage_warning_threshold_percent;

    Ok(ok(json!({
        "plan": user.plan,
        "dailyQuestionsUsed": questions_today,
        "dailyQuestionLimit": daily_limit,
        "weeklyCreditUsedUsd": spent_this_week,
        "weeklyCreditLimitUsd": weekly_allowance,
        "creditBalanceUsd": credit_balance,
        "usagePercent": usage_percent,
        "warningThresholdPercent": threshold,
        "showWarning": usage_percent >= threshold,
    })))
}

#[derive(Deserialize)]
struct CheckoutRequest {
    plan: String,
}

/// Starts a plan purchase — creates a `pending` payment row and returns
/// the amount to charge. Deliberately provider-agnostic: today only the
/// mock payment screen's Success/Failure buttons ever complete this (see
/// `complete_payment`), but the shape (a pending row a separate step
/// finalizes) is the same one a real gateway webhook would use.
async fn plans_checkout(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(body): Json<CheckoutRequest>,
) -> Result<Json<ApiResponse<serde_json::Value>>, ApiError> {
    let user = require_user(&state, &headers).await?;
    let (amount_inr, credits_usd) = match body.plan.as_str() {
        "pro" => (
            state.config.plans.pro_price_inr,
            state.config.plans.pro_credits_usd,
        ),
        "scholar" => (
            state.config.plans.scholar_price_inr,
            state.config.plans.scholar_credits_usd,
        ),
        _ => {
            return Err(ApiError::BadRequest(
                "plan must be \"pro\" or \"scholar\"".into(),
            ))
        }
    };
    let payment = state
        .db
        .create_payment(user.id, &body.plan, amount_inr, credits_usd)
        .await?;
    Ok(ok(json!({ "payment": payment })))
}

#[derive(Deserialize)]
struct CompletePaymentRequest {
    status: String,
}

/// Finalizes a pending payment. Stands in for a real gateway's
/// success/failure webhook — the mock payment screen calls this directly
/// with whichever button the user tapped. On success, upgrades the user's
/// plan and grants the purchased credits; on failure, the payment is just
/// marked failed and nothing else changes.
async fn complete_payment(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(payment_id): Path<Uuid>,
    Json(body): Json<CompletePaymentRequest>,
) -> Result<Json<ApiResponse<serde_json::Value>>, ApiError> {
    let user = require_user(&state, &headers).await?;
    if body.status != "success" && body.status != "failed" {
        return Err(ApiError::BadRequest(
            "status must be \"success\" or \"failed\"".into(),
        ));
    }
    let payment = state
        .db
        .complete_payment(payment_id, user.id, &body.status)
        .await?
        .ok_or_else(|| ApiError::NotFound("Payment not found, or already completed".into()))?;

    if payment.status == "success" {
        state.db.set_user_plan(user.id, &payment.plan).await?;
        state.db.add_credits(user.id, payment.credits_usd).await?;
    }

    Ok(ok(json!({ "payment": payment })))
}

#[derive(Deserialize)]
struct UpsertSyncedRecordRequest {
    name: String,
    data: serde_json::Value,
}

async fn list_exams(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> Result<Json<ApiResponse<serde_json::Value>>, ApiError> {
    let user = require_user(&state, &headers).await?;
    let exams = state.db.list_exams(user.id).await?;
    Ok(ok(json!({ "exams": exams })))
}

async fn upsert_exam(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(local_id): Path<String>,
    Json(body): Json<UpsertSyncedRecordRequest>,
) -> Result<Json<ApiResponse<serde_json::Value>>, ApiError> {
    let user = require_user(&state, &headers).await?;
    state
        .db
        .upsert_exam(user.id, &local_id, &body.name, &body.data)
        .await?;
    Ok(ok(json!({ "success": true })))
}

async fn delete_exam(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(local_id): Path<String>,
) -> Result<Json<ApiResponse<serde_json::Value>>, ApiError> {
    let user = require_user(&state, &headers).await?;
    state.db.delete_exam(user.id, &local_id).await?;
    Ok(ok(json!({ "success": true })))
}

async fn list_study_plans(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> Result<Json<ApiResponse<serde_json::Value>>, ApiError> {
    let user = require_user(&state, &headers).await?;
    let plans = state.db.list_study_plans(user.id).await?;
    Ok(ok(json!({ "studyPlans": plans })))
}

async fn upsert_study_plan(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(local_id): Path<String>,
    Json(body): Json<UpsertSyncedRecordRequest>,
) -> Result<Json<ApiResponse<serde_json::Value>>, ApiError> {
    let user = require_user(&state, &headers).await?;
    state
        .db
        .upsert_study_plan(user.id, &local_id, &body.name, &body.data)
        .await?;
    Ok(ok(json!({ "success": true })))
}

async fn delete_study_plan(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(local_id): Path<String>,
) -> Result<Json<ApiResponse<serde_json::Value>>, ApiError> {
    let user = require_user(&state, &headers).await?;
    state.db.delete_study_plan(user.id, &local_id).await?;
    Ok(ok(json!({ "success": true })))
}

/// Blocks the request before any embedding/cache/AI work happens if the
/// user has hit their plan's daily question count or weekly credit spend.
/// Anonymous requests (no valid session) are left unrestricted here, same
/// as the rest of `ai_chat`'s auth handling — this only tightens things
/// for signed-in users.
async fn enforce_plan_limits(state: &AppState, user: Option<&AuthUser>) -> Result<(), ApiError> {
    let Some(user) = user else {
        return Ok(());
    };
    let (daily_limit, weekly_credit) = plan_limits(&state.config, &user.plan);

    let questions_today = state.db.count_questions_today(user.id).await?;
    if questions_today >= daily_limit {
        return Err(ApiError::LimitExceeded(
            "You've reached today's question limit for your plan. Upgrade your plan or try again tomorrow.".into(),
        ));
    }

    let spent_this_week = state.db.sum_cost_this_week(user.id).await?;
    let credit_balance = state.db.user_credit_balance(user.id).await?;
    if spent_this_week >= weekly_credit + credit_balance {
        return Err(ApiError::LimitExceeded(
            "You've used this week's plan credit. Upgrade your plan or wait for the weekly reset."
                .into(),
        ));
    }

    Ok(())
}

async fn ai_chat(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(body): Json<AiChatRequest>,
) -> Result<Json<ApiResponse<serde_json::Value>>, ApiError> {
    let user = Some(require_user(&state, &headers).await?);
    enforce_plan_limits(&state, user.as_ref()).await?;
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

    let (question_embedding, embed_input_tokens) =
        state.ai.embed(question).await.unwrap_or_default();
    let _ = state
        .db
        .record_usage(
            user.as_ref().map(|u| u.id),
            "/api/ai/chat#embed",
            state.config.provider()?.name,
            &state.config.embedding_model,
            embed_input_tokens,
            0,
            "model",
        )
        .await;
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

#[derive(Deserialize)]
struct TitleRequest {
    message: Option<String>,
}

/// Generates a short chat title from a first message. Deliberately isolated
/// from the tutoring pipeline (`ai_chat`) — no embedding call, no RAG
/// retrieval, no beta-gate, no answer cache. Reusing `ai_chat` for this
/// (as the client used to) ran the user's opening message through the full
/// subject/chapter retrieval flow, which could hit the beta-confirmation
/// short-circuit and return a response shape with no `content` field —
/// silently breaking title generation with nothing logged server-side,
/// since that path returns 200 rather than an error.
async fn ai_title(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(body): Json<TitleRequest>,
) -> Result<Json<ApiResponse<serde_json::Value>>, ApiError> {
    let user = Some(require_user(&state, &headers).await?);
    let message = body
        .message
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| ApiError::BadRequest("message is required".into()))?;

    // A title only needs the opening context, not the whole message — kept
    // short enough to stay on the fast model tier (choose_model treats
    // long questions as needing the reasoning model).
    let truncated: String = message.chars().take(200).collect();

    let title_request = AiChatRequest {
        question: Some(truncated),
        system_prompt: Some(
            "You write short chat titles. Read the user's message and reply with ONLY a \
             concise 3-5 word title summarizing its topic — no quotes, no punctuation, no \
             preamble, no explanation. Reply in the same language as the message."
                .to_string(),
        ),
        max_tokens: Some(32),
        temperature: Some(0.3),
        ..Default::default()
    };

    let answer = state.ai.chat(&title_request, &[]).await?;
    let _ = state
        .db
        .record_usage(
            user.map(|u| u.id),
            "/api/ai/title",
            &answer.provider,
            &answer.model,
            answer.input_tokens,
            answer.output_tokens,
            &answer.served_from,
        )
        .await;

    Ok(ok(json!({ "title": answer.content.trim() })))
}

/// SSE counterpart to `ai_chat`: same cache/beta-gate/retrieval pipeline,
/// but the actual generation streams real text deltas as they arrive from
/// the provider instead of waiting for the full response. Event types sent
/// to the client:
///   - "chunk": {"delta": "..."} — a plain-text/markdown fragment, append
///     and re-render; never contains a partial JSON envelope.
///   - "beta": {chapterId, chapterName, subjectName, message} — terminal,
///     no chunks follow.
///   - "done": {sources, subjectId, subjectName, chapterId, chapterName,
///     servedFrom} — terminal, sent after the last chunk.
///   - "error": {"message": "..."} — terminal.
///
/// Rich-mode-only features (structured blocks, speechText, the two-pass
/// vision refinement) aren't available on this path — see chat_stream's
/// doc comment on why. Use the non-streaming /ai/chat when those matter.
type BoxedEventStream = std::pin::Pin<Box<dyn Stream<Item = Result<Event, Infallible>> + Send>>;

async fn ai_chat_stream(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(body): Json<AiChatRequest>,
) -> Result<Sse<KeepAliveStream<BoxedEventStream>>, ApiError> {
    let user = Some(require_user(&state, &headers).await?);
    enforce_plan_limits(&state, user.as_ref()).await?;
    let question = body
        .question
        .as_deref()
        .or(body.message.as_deref())
        .or(body.content.as_deref())
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| ApiError::BadRequest("question is required".into()))?
        .to_string();

    let normalized_question = normalize_question(&question);
    let response_length = body.response_length.clone().unwrap_or("normal".into());
    let reasoning_level = body.reasoning_level.clone().unwrap_or("mid".into());
    let chapter_ids = normalized_chapter_ids(&body);
    let exact_key = cache_key(
        &normalized_question,
        body.response_language.as_deref(),
        &response_length,
        &reasoning_level,
        body.subject_id.as_deref(),
        &chapter_ids,
        body.confirm_beta_chapter_id.as_deref(),
    );

    // Cache hits stream as a single immediate chunk + done — genuinely
    // instant, not simulated, since the full answer is already known.
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
            &question,
            &answer,
            &context_meta,
        )
        .await?;
        return Ok(
            Sse::new(Box::pin(single_shot_stream(answer, context_meta)) as BoxedEventStream)
                .keep_alive(KeepAlive::default()),
        );
    }

    let (question_embedding, embed_input_tokens) =
        state.ai.embed(&question).await.unwrap_or_default();
    let _ = state
        .db
        .record_usage(
            user.as_ref().map(|u| u.id),
            "/api/ai/chat/stream#embed",
            state.config.provider()?.name,
            &state.config.embedding_model,
            embed_input_tokens,
            0,
            "model",
        )
        .await;
    let semantic_cached = if body.confirm_beta_chapter_id.is_some() {
        None
    } else {
        state
            .db
            .lookup_semantic_cache(
                &question_embedding,
                state.config.semantic_cache_threshold,
                body.response_language.as_deref(),
                &response_length,
                &reasoning_level,
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
            &question,
            &answer,
            &context_meta,
        )
        .await?;
        return Ok(
            Sse::new(Box::pin(single_shot_stream(answer, context_meta)) as BoxedEventStream)
                .keep_alive(KeepAlive::default()),
        );
    }

    let outcome = select_contexts(&state, &body, &question, Some(&question_embedding)).await?;
    let selected = match outcome {
        ContextsOutcome::Ready(selected) => selected,
        ContextsOutcome::NeedsBetaConfirmation(beta) => {
            let message = format!(
                "\"{}\" from {} is in your syllabus, but that content is still in beta. Do you want the response anyway?",
                beta.chapter_name, beta.subject_name
            );
            let stream = async_stream::stream! {
                yield Ok(Event::default().event("beta").data(
                    json!({
                        "chapterId": beta.chapter_id,
                        "chapterName": beta.chapter_name,
                        "subjectName": beta.subject_name,
                        "message": message,
                    })
                    .to_string(),
                ));
            };
            return Ok(
                Sse::new(Box::pin(stream) as BoxedEventStream).keep_alive(KeepAlive::default())
            );
        }
    };

    let (model, text_stream) = state.ai.chat_stream(&body, &selected.sources).await?;
    let provider_name = state.config.provider()?.name;

    let stream_state = state.clone();
    let stream_body = body.clone();
    let stream_user = user.clone();
    let primary_meta = selected.primary_meta.clone();
    let sources = selected.sources.clone();
    let source_chunks: Vec<String> = sources.iter().map(|s| s.text.clone()).collect();

    let sse = async_stream::stream! {
        use futures_util::StreamExt;
        futures_util::pin_mut!(text_stream);
        let mut full_text = String::new();
        while let Some(delta) = text_stream.next().await {
            full_text.push_str(&delta);
            yield Ok(Event::default().event("chunk").data(json!({ "delta": delta }).to_string()));
        }

        if full_text.trim().is_empty() {
            yield Ok(Event::default().event("error").data(
                json!({ "message": "AI provider returned an empty response" }).to_string(),
            ));
            return;
        }

        let subject_id = primary_meta.subject_id.as_deref().or(stream_body.subject_id.as_deref());
        let subject_name = primary_meta.subject_name.as_deref().or(stream_body.subject_name.as_deref());
        let output_tokens = crate::openrouter::estimate_tokens(&full_text);

        if stream_body.confirm_beta_chapter_id.is_none() {
            let _ = stream_state
                .db
                .store_answer_cache(
                    &exact_key,
                    &normalized_question,
                    &question,
                    &full_text,
                    &question_embedding,
                    &model,
                    provider_name,
                    stream_body.response_language.as_deref(),
                    &response_length,
                    &reasoning_level,
                    subject_id,
                    subject_name,
                    &chapter_ids,
                    &source_chunks,
                    0,
                    output_tokens,
                )
                .await;
        }

        let answer = AiAnswer {
            content: full_text,
            speech_text: None,
            blocks: None,
            served_from: "model".into(),
            model,
            provider: provider_name.into(),
            input_tokens: 0,
            output_tokens,
            source_chunks,
            sources: sources.clone(),
        };
        let _ = persist_ai_chat(&stream_state, stream_user.as_ref(), &stream_body, &question, &answer, &primary_meta).await;

        yield Ok(Event::default().event("done").data(
            json!({
                "sources": sources,
                "subjectId": subject_id,
                "subjectName": subject_name,
                "chapterId": primary_meta.chapter_id,
                "chapterName": primary_meta.chapter_name,
                "servedFrom": answer.served_from,
            })
            .to_string(),
        ));
    };

    Ok(Sse::new(Box::pin(sse) as BoxedEventStream).keep_alive(KeepAlive::default()))
}

fn single_shot_stream(
    answer: AiAnswer,
    context_meta: crate::rag::ContextMeta,
) -> impl Stream<Item = Result<Event, Infallible>> {
    async_stream::stream! {
        yield Ok(Event::default().event("chunk").data(json!({ "delta": answer.content }).to_string()));
        yield Ok(Event::default().event("done").data(
            json!({
                "sources": answer.sources,
                "subjectId": context_meta.subject_id,
                "subjectName": context_meta.subject_name,
                "chapterId": context_meta.chapter_id,
                "chapterName": context_meta.chapter_name,
                "servedFrom": answer.served_from,
            })
            .to_string(),
        ));
    }
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
    headers: HeaderMap,
    Json(body): Json<EmbeddingRequest>,
) -> Result<Json<ApiResponse<serde_json::Value>>, ApiError> {
    let text = body
        .text
        .or(body.input)
        .ok_or_else(|| ApiError::BadRequest("text is required".into()))?;
    let user = Some(require_user(&state, &headers).await?);
    let (embedding, input_tokens) = state.ai.embed(&text).await?;
    let _ = state
        .db
        .record_usage(
            user.as_ref().map(|u| u.id),
            "/api/ai/embeddings",
            state.config.provider()?.name,
            &state.config.embedding_model,
            input_tokens,
            0,
            "model",
        )
        .await;
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

/// Previously had no authentication at all — anyone who found the URL
/// could call it for free with no rate limit beyond the shared per-IP
/// governed_layer. Requiring a session closes that off; usage isn't
/// tracked/billed here since NVIDIA rerank is currently free (see
/// AiGateway::rerank), so this is purely an abuse guard, not billing.
async fn rerank(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(body): Json<RerankRequest>,
) -> Result<Json<ApiResponse<serde_json::Value>>, ApiError> {
    require_user(&state, &headers).await?;
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

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct UpdateChatRequest {
    name: Option<String>,
    subject_id: Option<String>,
    subject_name: Option<String>,
    chapter_ids: Option<Vec<String>>,
    chapter_names: Option<Vec<String>>,
    is_pinned: Option<bool>,
}

/// Partial update for a chat's own fields (name, classification, pin
/// state) — used to push local-only changes (e.g. an AI-generated chat
/// name) up to the server. This route previously didn't exist even though
/// the Flutter client has always called it, so every one of these updates
/// was silently failing with a 404 the client swallows.
async fn update_chat(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(local_id): Path<String>,
    Json(body): Json<UpdateChatRequest>,
) -> Result<Json<ApiResponse<serde_json::Value>>, ApiError> {
    let user = require_user(&state, &headers).await?;
    let chat = state
        .db
        .update_chat_fields(
            user.id,
            &local_id,
            body.name.as_deref(),
            body.subject_id.as_deref(),
            body.subject_name.as_deref(),
            body.chapter_ids.as_deref(),
            body.chapter_names.as_deref(),
            body.is_pinned,
        )
        .await?
        .ok_or_else(|| ApiError::NotFound("Chat not found".into()))?;
    Ok(ok(json!({ "chat": chat })))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct AddMessageRequest {
    local_id: String,
    role: String,
    content: String,
    #[serde(default)]
    token_count: Option<i32>,
    #[serde(default)]
    source_chunks: Option<Vec<String>>,
}

/// Appends a message to a chat identified by its local_id — used by the
/// share flow to sync messages before creating a share link. Like
/// `update_chat` above, this route didn't exist even though the client has
/// always called it, so sharing a chat always 404'd partway through
/// syncing its messages.
async fn add_chat_message(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(local_id): Path<String>,
    Json(body): Json<AddMessageRequest>,
) -> Result<Json<ApiResponse<serde_json::Value>>, ApiError> {
    let user = require_user(&state, &headers).await?;
    let chat = state
        .db
        .find_chat_by_local_id(user.id, &local_id)
        .await?
        .ok_or_else(|| ApiError::NotFound("Chat not found".into()))?;
    let message: ChatMessage = state
        .db
        .insert_message(
            user.id,
            chat.id,
            &body.local_id,
            &body.role,
            &body.content,
            body.token_count.unwrap_or(0),
            &body.source_chunks.unwrap_or_default(),
        )
        .await?;
    Ok(ok(json!({ "message": message })))
}

fn share_url(app_url: &str, token: &str) -> String {
    format!("{}/api/share/{token}", app_url.trim_end_matches('/'))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ShareChatRequest {
    #[serde(default)]
    access_level: Option<String>,
}

/// Creates a 10-minute share link that points straight at an existing
/// chat — no data is copied, the recipient fetches the live chat +
/// messages through GET /share/:token while the link is valid.
async fn share_chat(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(local_id): Path<String>,
    Json(body): Json<ShareChatRequest>,
) -> Result<Json<ApiResponse<serde_json::Value>>, ApiError> {
    let user = require_user(&state, &headers).await?;
    let chat = state
        .db
        .find_chat_by_local_id(user.id, &local_id)
        .await?
        .ok_or_else(|| ApiError::NotFound("Chat not found".into()))?;
    let access_level = body.access_level.as_deref().unwrap_or("full");
    let share = state
        .db
        .create_chat_share(user.id, chat.id, access_level)
        .await?;
    Ok(ok(json!({
        "token": share.token,
        "url": share_url(&state.config.app_url, &share.token),
        "expiresAt": share.expires_at
    })))
}

/// Uploads a self-contained export (exam/study-plan ZIP) and creates a
/// 10-minute share link pointing at the stored blob. multipart fields:
/// `file` (required) and `metadata` (optional JSON string).
async fn upload_content(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    mut multipart: Multipart,
) -> Result<Json<ApiResponse<serde_json::Value>>, ApiError> {
    let user = require_user(&state, &headers).await?;

    let mut file_bytes: Option<Vec<u8>> = None;
    let mut filename = "content.zip".to_string();
    let mut mime_type = "application/zip".to_string();
    let mut metadata = serde_json::json!({});

    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|error| ApiError::BadRequest(format!("invalid multipart body: {error}")))?
    {
        let name = field.name().unwrap_or_default().to_string();
        if name == "file" {
            filename = field
                .file_name()
                .map(ToString::to_string)
                .unwrap_or(filename);
            mime_type = field
                .content_type()
                .map(ToString::to_string)
                .unwrap_or(mime_type);
            let bytes = field
                .bytes()
                .await
                .map_err(|error| ApiError::BadRequest(format!("failed reading file: {error}")))?;
            file_bytes = Some(bytes.to_vec());
        } else if name == "metadata" {
            if let Ok(text) = field.text().await {
                if let Ok(value) = serde_json::from_str(&text) {
                    metadata = value;
                }
            }
        }
    }

    let bytes = file_bytes.ok_or_else(|| ApiError::BadRequest("file is required".into()))?;
    let share = state
        .db
        .create_content_share(user.id, &filename, &mime_type, &metadata, &bytes)
        .await?;
    Ok(ok(json!({
        "token": share.token,
        "url": share_url(&state.config.app_url, &share.token),
        "expiresAt": share.expires_at
    })))
}

/// Resolves a share token. Content shares stream the stored bytes back
/// directly (matching the original download); chat shares return the
/// chat + its messages as JSON. An invalid/expired token is a 404 either
/// way — recipients shouldn't be able to distinguish the two.
async fn resolve_share(
    State(state): State<Arc<AppState>>,
    Path(token): Path<String>,
) -> Result<Response, ApiError> {
    let share = state
        .db
        .resolve_share(&token)
        .await?
        .ok_or_else(|| ApiError::NotFound("Share link is invalid or expired".into()))?;

    if share.share_type == "content" {
        let content = state
            .db
            .get_content_share(share.ref_id)
            .await?
            .ok_or_else(|| ApiError::NotFound("Shared content not found".into()))?;
        let disposition = format!(
            "attachment; filename=\"{}\"",
            content.filename.replace('"', "")
        );
        return Ok((
            [
                (header::CONTENT_TYPE, content.mime_type),
                (header::CONTENT_DISPOSITION, disposition),
            ],
            Bytes::from(content.bytes),
        )
            .into_response());
    }

    let chat = state
        .db
        .chat_by_id(share.ref_id)
        .await?
        .ok_or_else(|| ApiError::NotFound("Shared chat not found".into()))?;
    let messages = state.db.list_messages(chat.id).await?;
    Ok(ok(json!({
        "chat": chat,
        "messages": messages,
        "expiresAt": share.expires_at
    }))
    .into_response())
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
            // The cached text itself carries "\nImage: <full url>" inline
            // (see rag::finalize) — pull it back out rather than losing
            // image sources on a cache hit.
            image_url: text
                .split_once("\nImage: ")
                .map(|(_, url)| url.trim().to_string()),
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
