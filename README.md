# RightAnswer

RightAnswer is a local-first AI study partner for textbook-grounded learning.
The app reads local SQLite data offline, uses a compiled Rust backend when
online, retrieves textbook context from PostgreSQL/Qdrant, and renders rich AI
answers with Markdown, LaTeX, tables, charts, diagrams, images, sources, and
clean text-to-speech.

## Current Stack

- `apps/app`: Flutter mobile app with SQLite local storage.
- `apps/api`: Rust backend using Axum, Tokio, SQLx, Reqwest, Tower, Tracing, and
  Qdrant.
- `apps/web`: React/Vite landing, documentation, features, and admin UI.
- `packages/database`: existing Prisma/PostgreSQL textbook schema.
- `apps/workers`: legacy Node workers still used for background jobs.
- `apps/api-node-legacy`: preserved Node/Nest/Hono backend.
- `apps/web-next-legacy`: preserved Next.js app.

## AI Flow

1. Query is embedded.
2. Qdrant retrieves textbook vector candidates.
3. OpenRouter/HackAI rerank selects the best 3 to 5 contexts.
4. The chat model receives the selected context and rich-answer instructions.
5. The app renders typed answer blocks and stores the answer locally.
6. Text-to-speech reads `speechText`, not Markdown symbols or raw LaTeX.

## Quick Start

Copy env:

```bash
copy .env.example .env
```

Start infrastructure:

```bash
docker compose up -d postgres qdrant redis
```

Run the Rust API:

```bash
cargo run --manifest-path apps/api/Cargo.toml
```

Run the web app:

```bash
pnpm --filter @right-answer/web dev
```

Open:

- Web: [http://localhost:3000](http://localhost:3000)
- API health: [http://localhost:4000/api/health](http://localhost:4000/api/health)

## Qdrant Migration

PostgreSQL remains the source of truth. Qdrant stores vector copies for fast
retrieval.

Run:

```bash
cargo run --manifest-path apps/api/Cargo.toml --bin migrate_qdrant
```

The migration stops if PostgreSQL embeddings are empty, any vector is empty,
Qdrant writes fail, or the final Qdrant point count is lower than the migrated
PostgreSQL row count.

## Documentation

- [System Documentation](docs/SYSTEM_DOCUMENTATION.md)
- [Rust Backend Migration](docs/RUST_BACKEND_MIGRATION.md)
- [Flutter App Overview](apps/app/docs/APP_OVERVIEW.md)
- [Flutter Architecture](apps/app/docs/ARCHITECTURE.md)

## Commands

```bash
pnpm dev
pnpm dev:api
pnpm dev:web
cargo check --manifest-path apps/api/Cargo.toml
pnpm --filter @right-answer/web build
```

Legacy textbook ingestion is still available:

```bash
pnpm textbook:run-all -- --pdf ... --subject biology --medium en --version 2026-v1
```

Those scripts run through `apps/api-node-legacy` until the ingestion pipeline is
ported to Rust.

## Deployment

The VPS target is:

- Rust API on port `4000`.
- React static web app served by Nginx on port `3000` or behind a reverse proxy.
- Self-hosted PostgreSQL.
- Self-hosted Qdrant.
- Optional Redis/workers while legacy background jobs remain.

See `docker-compose.yml` for the current container layout.
