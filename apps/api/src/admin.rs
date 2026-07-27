use std::sync::Arc;

use axum::{extract::State, http::HeaderMap, response::Html, Json};
use serde::Serialize;
use serde_json::json;

use crate::{auth::require_user, error::ApiError, routes::AppState};

/// Static dashboard shell — baked into the binary at compile time, so
/// deploys need no extra static-file mount. Publicly reachable (the page
/// itself has no data), but it can only ever show anything by calling
/// `GET /api/admin/metrics` with an admin's bearer token pasted into the
/// page, which is where the real access control lives.
pub async fn dashboard_page() -> Html<&'static str> {
    Html(include_str!("../static/admin_dashboard.html"))
}

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

#[derive(Debug, Serialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
struct DailyCostRow {
    day: chrono::NaiveDate,
    api_calls: i64,
    estimated_cost_usd: f64,
}

#[derive(Debug, Serialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
struct PlanCostRow {
    plan: Option<String>,
    api_calls: i64,
    estimated_cost_usd: f64,
}

/// USD/day revenue proxy from the `payments` table, grouped by plan. This
/// is NOT real collected revenue — the payment gateway is still mock (see
/// migrations/0003_plans.sql), so this only reflects money the app
/// *would* have recorded had a live gateway been wired in. Treat as a
/// rough planning signal, not an accounting figure.
#[derive(Debug, Serialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
struct DailyRevenueRow {
    day: chrono::NaiveDate,
    plan: String,
    amount_usd: f64,
}

const INR_PER_USD: f64 = 96.57;

pub async fn metrics(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> Result<Json<crate::routes::ApiResponse<serde_json::Value>>, ApiError> {
    let user = require_user(&state, &headers).await?;
    if user.role != "admin" {
        return Err(ApiError::Forbidden("Admin access required".into()));
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

    let daily_cost = sqlx::query_as::<_, DailyCostRow>(
        r#"
        SELECT
          created_at::date AS day,
          count(*)::bigint AS api_calls,
          coalesce(sum(estimated_cost_usd), 0)::float8 AS estimated_cost_usd
        FROM ai_usage_events
        WHERE created_at > now() - interval '30 days'
        GROUP BY day
        ORDER BY day DESC
        "#,
    )
    .fetch_all(&state.db.pool)
    .await?;

    let cost_by_plan = sqlx::query_as::<_, PlanCostRow>(
        r#"
        SELECT
          u.plan,
          count(*)::bigint AS api_calls,
          coalesce(sum(e.estimated_cost_usd), 0)::float8 AS estimated_cost_usd
        FROM ai_usage_events e
        LEFT JOIN users u ON u.id = e.user_id
        GROUP BY u.plan
        ORDER BY estimated_cost_usd DESC
        "#,
    )
    .fetch_all(&state.db.pool)
    .await?;

    let daily_revenue = sqlx::query_as::<_, DailyRevenueRow>(
        r#"
        SELECT
          completed_at::date AS day,
          plan,
          coalesce(sum(amount_inr), 0)::float8 / $1 AS amount_usd
        FROM payments
        WHERE status = 'success' AND completed_at > now() - interval '30 days'
        GROUP BY day, plan
        ORDER BY day DESC
        "#,
    )
    .bind(INR_PER_USD)
    .fetch_all(&state.db.pool)
    .await?;

    let total_cost_usd: f64 = daily_cost.iter().map(|row| row.estimated_cost_usd).sum();
    let total_revenue_usd: f64 = daily_revenue.iter().map(|row| row.amount_usd).sum();

    Ok(crate::routes::ok(json!({
        "aiUsage": by_model,
        "userUsage": by_user,
        "dailyCostUsd": daily_cost,
        "costByPlan": cost_by_plan,
        "dailyRevenueUsd": daily_revenue,
        "totals": {
            "costUsd30d": total_cost_usd,
            "revenueUsd30d": total_revenue_usd,
            "marginUsd30d": total_revenue_usd - total_cost_usd,
        },
        "notes": [
            "Costs are estimates based on configured per-model heuristics until exact provider pricing is connected.",
            "Revenue is a proxy from the mock payment flow (payments.status = 'success') converted at a fixed INR/USD rate — not real collected money until a live payment gateway is wired in.",
            "Visits are intentionally not tracked."
        ]
    })))
}
