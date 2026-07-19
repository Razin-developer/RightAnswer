use std::sync::Arc;

use axum::{extract::State, http::HeaderMap, Json};
use serde::Serialize;
use serde_json::json;

use crate::{auth::require_user, error::ApiError, routes::AppState};

#[derive(Debug, Serialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
struct ModelUsageRow {
    model: String,
    provider: String,
    api_calls: i64,
    input_tokens: i64,
    output_tokens: i64,
    estimated_cost_usd: f64,
}

#[derive(Debug, Serialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
struct UserUsageRow {
    user_id: Option<uuid::Uuid>,
    email: Option<String>,
    api_calls: i64,
    input_tokens: i64,
    output_tokens: i64,
    estimated_cost_usd: f64,
}

pub async fn metrics(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> Result<Json<crate::routes::ApiResponse<serde_json::Value>>, ApiError> {
    let user = require_user(&state, &headers).await?;
    if user.role != "admin" {
        return Err(ApiError::Unauthorized("Admin access required".into()));
    }

    let by_model = sqlx::query_as::<_, ModelUsageRow>(
        r#"
        SELECT
          model,
          provider,
          count(*)::bigint AS api_calls,
          coalesce(sum(input_tokens), 0)::bigint AS input_tokens,
          coalesce(sum(output_tokens), 0)::bigint AS output_tokens,
          coalesce(sum(estimated_cost_usd), 0)::float8 AS estimated_cost_usd
        FROM ai_usage_events
        GROUP BY model, provider
        ORDER BY estimated_cost_usd DESC
        "#,
    )
    .fetch_all(&state.db.pool)
    .await?;

    let by_user = sqlx::query_as::<_, UserUsageRow>(
        r#"
        SELECT
          e.user_id,
          u.email,
          count(*)::bigint AS api_calls,
          coalesce(sum(e.input_tokens), 0)::bigint AS input_tokens,
          coalesce(sum(e.output_tokens), 0)::bigint AS output_tokens,
          coalesce(sum(e.estimated_cost_usd), 0)::float8 AS estimated_cost_usd
        FROM ai_usage_events e
        LEFT JOIN users u ON u.id = e.user_id
        GROUP BY e.user_id, u.email
        ORDER BY estimated_cost_usd DESC
        "#,
    )
    .fetch_all(&state.db.pool)
    .await?;

    Ok(crate::routes::ok(json!({
        "aiUsage": by_model,
        "userUsage": by_user,
        "notes": [
            "Costs are estimates based on configured per-model heuristics until exact provider pricing is connected.",
            "Visits are intentionally not tracked."
        ]
    })))
}
