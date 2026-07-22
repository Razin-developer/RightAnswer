mod admin;
mod auth;
mod config;
mod content_policy;
mod db;
mod error;
mod models;
mod openrouter;
mod qdrant;
mod rag;
mod routes;

use std::{net::SocketAddr, sync::Arc, time::Duration};

use axum::{
    http::{HeaderValue, Method, StatusCode},
    response::IntoResponse,
    Json, Router,
};
use tokio::net::TcpListener;
use tower_http::{
    catch_panic::CatchPanicLayer, cors::CorsLayer, timeout::TimeoutLayer, trace::TraceLayer,
};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use crate::{
    config::Config,
    db::Database,
    openrouter::AiGateway,
    qdrant::QdrantGateway,
    routes::{api_router, AppState},
};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    dotenvy::dotenv().ok();

    // File logging (in addition to stdout, which docker already captures):
    // survives container log rotation and is directly greppable over SSH
    // without depending on `docker logs`, especially for panics caught by
    // CatchPanicLayer below — those are exactly the "the server seemed to
    // stop responding" reports that are hardest to diagnose after the fact.
    let log_dir = std::env::var("LOG_DIR").unwrap_or_else(|_| "/app/logs".into());
    std::fs::create_dir_all(&log_dir).ok();
    let file_appender = tracing_appender::rolling::daily(&log_dir, "right-answer-api.log");
    let (file_writer, _file_guard) = tracing_appender::non_blocking(file_appender);

    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "right_answer_api=info,tower_http=info,axum=info".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .with(
            tracing_subscriber::fmt::layer()
                .with_writer(file_writer)
                .with_ansi(false),
        )
        .init();

    let config = Config::from_env()?;
    let db = Database::connect(&config.database_url).await?;
    db.migrate().await?;

    let state = Arc::new(AppState {
        config: config.clone(),
        db,
        ai: AiGateway::new(config.clone()),
        qdrant: QdrantGateway::new(config.clone()),
    });

    let cors = if config.cors_origins.is_empty() {
        tracing::warn!(
            "CORS_ORIGINS is not set; falling back to a permissive (allow-any-origin) CORS policy. \
             Set CORS_ORIGINS in production."
        );
        CorsLayer::permissive()
    } else {
        let origins = config
            .cors_origins
            .iter()
            .filter_map(|origin| origin.parse::<HeaderValue>().ok())
            .collect::<Vec<_>>();
        CorsLayer::new()
            .allow_origin(origins)
            .allow_methods([
                Method::GET,
                Method::POST,
                Method::PUT,
                Method::PATCH,
                Method::DELETE,
            ])
            .allow_headers(tower_http::cors::Any)
    };

    let app = Router::new()
        .route("/health", axum::routing::get(routes::health))
        .nest("/api", api_router(state.clone()))
        .nest("/api/v1", api_router(state))
        .layer(TimeoutLayer::with_status_code(
            StatusCode::REQUEST_TIMEOUT,
            Duration::from_secs(180),
        ))
        .layer(TraceLayer::new_for_http())
        .layer(cors)
        // Last line of defense: a panic anywhere in a handler (a bad
        // .unwrap(), an out-of-bounds index, etc.) is caught here and
        // turned into a 500 instead of dropping the connection/task
        // silently — the process itself was never actually at risk from a
        // single-request panic (Tokio isolates it to that task), but
        // without this the client just sees a hung/reset connection, which
        // reads as "the server stopped" even though it's still running.
        .layer(CatchPanicLayer::custom(handle_panic));

    let addr = SocketAddr::from(([0, 0, 0, 0], config.port));
    tracing::info!(%addr, "right-answer rust api listening");
    let listener = TcpListener::bind(addr).await?;
    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .with_graceful_shutdown(shutdown_signal())
    .await?;
    Ok(())
}

fn handle_panic(err: Box<dyn std::any::Any + Send + 'static>) -> axum::response::Response {
    let details = if let Some(s) = err.downcast_ref::<String>() {
        s.clone()
    } else if let Some(s) = err.downcast_ref::<&str>() {
        (*s).to_string()
    } else {
        "unknown panic payload".to_string()
    };
    tracing::error!(panic = %details, "request handler panicked, recovered");
    let body = Json(serde_json::json!({
        "success": false,
        "error": { "code": "INTERNAL_ERROR", "message": "An internal error occurred" }
    }));
    (StatusCode::INTERNAL_SERVER_ERROR, body).into_response()
}

async fn shutdown_signal() {
    let ctrl_c = async {
        tokio::signal::ctrl_c()
            .await
            .expect("failed to install Ctrl+C handler");
    };

    #[cfg(unix)]
    let terminate = async {
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
            .expect("failed to install SIGTERM handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }
}
