# Rust Backend Migration Plan

## Why Rust

The Rust backend is compiled, memory safe, fast under concurrency, and a better
fit for a VPS where predictable CPU and memory use matters.

Selected stack:

- Axum: HTTP framework.
- Tokio: async runtime.
- SQLx: PostgreSQL access.
- Qdrant: vector retrieval.
- Reqwest: OpenRouter/HackAI calls.
- Tower: middleware, timeout, trace, rate-limit path.
- Tracing: diagnostics.
- Serde: JSON.

## Official References Checked

- Axum integrates with Tower middleware, which gives timeout, tracing,
  compression, authorization, and related middleware patterns.
- SQLx is an async Rust SQL toolkit supporting PostgreSQL and SQLite.
- Qdrant is an open-source vector search engine written in Rust, and provides
  REST/gRPC APIs plus client libraries.
- OpenRouter chat and embedding schemas are close to OpenAI-style APIs.

## Folder Map

```text
apps/api                 New Rust backend
apps/api-node-legacy     Preserved Node/Nest/Hono backend
apps/web                 New React/Vite web app
apps/web-next-legacy     Preserved Next.js app
apps/app                 Flutter app
packages/database        Existing Prisma/PostgreSQL schema
```

## Route Parity Checklist

Initial Rust routes:

- `GET /health`
- `GET /api/health`
- `POST /api/auth/register`
- `POST /api/auth/signup`
- `POST /api/auth/login`
- `GET /api/auth/me`
- `POST /api/ai/chat`
- `POST /api/ai/embeddings`
- `POST /api/ai/rerank`
- `GET /api/chats`
- `POST /api/chats`
- `GET /api/admin/metrics`

Still to port from legacy:

- Full account endpoints.
- Full teacher endpoints.
- Full content endpoints.
- Full ingestion endpoints.
- Full billing/subscription endpoints.
- Share-link endpoints.
- Evaluation metrics endpoints.
- Local textbook pipeline.

## Migration Rules

1. Never delete PostgreSQL data during migration.
2. Keep legacy Node folders until parity tests pass.
3. Run Qdrant migration with exact count verification.
4. Compare route-by-route responses before switching the Flutter app to the Rust
   backend in production.
5. Switch traffic gradually by route or environment.
6. Keep rollback simple: point `API_URL` back to the legacy API if needed.

## Qdrant Migration

Command:

```bash
cargo run --manifest-path apps/api/Cargo.toml --bin migrate_qdrant
```

Failure conditions:

- No PostgreSQL embeddings.
- Empty vector in any row.
- Qdrant collection create/upsert/count error.
- Qdrant point count lower than migrated PostgreSQL rows.

## Admin Expense Model

The Rust API records every AI call in `ai_usage_events`.

Admin page shows:

- AI usage by model/provider.
- User-per-user usage.
- API calls.
- Input/output tokens.
- Estimated expense.

Visits are intentionally not tracked.

Exact provider pricing should be wired later from a pricing config table or
OpenRouter pricing metadata. The current implementation uses conservative
per-model heuristics.
