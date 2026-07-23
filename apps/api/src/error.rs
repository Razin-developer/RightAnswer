use axum::{http::StatusCode, response::IntoResponse, Json};
use serde::Serialize;

#[derive(Debug, thiserror::Error)]
pub enum ApiError {
    #[error("{0}")]
    BadRequest(String),
    #[error("{0}")]
    Unauthorized(String),
    #[error("{0}")]
    Upstream(String),
    #[error("{0}")]
    NotFound(String),
    #[error("{0}")]
    LimitExceeded(String),
    #[error(transparent)]
    Sqlx(#[from] sqlx::Error),
    #[error(transparent)]
    Anyhow(#[from] anyhow::Error),
}

#[derive(Serialize)]
struct ErrorBody {
    success: bool,
    error: ErrorPayload,
}

#[derive(Serialize)]
struct ErrorPayload {
    code: &'static str,
    message: String,
}

impl IntoResponse for ApiError {
    fn into_response(self) -> axum::response::Response {
        let (status, code) = match &self {
            ApiError::BadRequest(_) => (StatusCode::BAD_REQUEST, "VALIDATION_ERROR"),
            ApiError::Unauthorized(_) => (StatusCode::UNAUTHORIZED, "AUTH_REQUIRED"),
            ApiError::Upstream(_) => (StatusCode::BAD_GATEWAY, "UPSTREAM_ERROR"),
            ApiError::NotFound(_) => (StatusCode::NOT_FOUND, "NOT_FOUND"),
            ApiError::LimitExceeded(_) => (StatusCode::TOO_MANY_REQUESTS, "LIMIT_EXCEEDED"),
            ApiError::Sqlx(_) | ApiError::Anyhow(_) => {
                (StatusCode::INTERNAL_SERVER_ERROR, "INTERNAL_ERROR")
            }
        };

        // Internal errors (DB, unexpected failures) can carry raw driver
        // messages, query fragments, or file paths — never hand those to the
        // client. Log them server-side and return a generic message instead.
        // Every other variant is still logged (at warn, not error) — a
        // silent 4xx/502 here previously left zero trace of failures like a
        // missing share link or an upstream AI timeout, making them
        // impossible to diagnose from server logs after the fact.
        let message = match &self {
            ApiError::Sqlx(_) | ApiError::Anyhow(_) => {
                tracing::error!(error = %self, "internal error");
                "An internal error occurred".to_string()
            }
            _ => {
                tracing::warn!(code, error = %self, "request failed");
                self.to_string()
            }
        };

        let body = ErrorBody {
            success: false,
            error: ErrorPayload { code, message },
        };
        (status, Json(body)).into_response()
    }
}
