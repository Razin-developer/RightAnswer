# Local Development

This is a pnpm/Turborepo monorepo. Current stack, by app:

- `apps/app`: Flutter mobile app (SQLite for local/offline data).
- `apps/api`: Rust backend (Axum, Tokio, SQLx, Reqwest, Tower, Tracing) —
  talks to PostgreSQL and Qdrant.
- `apps/web`: React/Vite landing page, docs, features, and admin UI.
- `apps/workers`: Node background workers.
- `packages/database`: Prisma/PostgreSQL textbook schema.
- `apps/api-node-legacy`: superseded Node/Nest/Hono backend, kept only until
  the remaining ingestion pipeline is ported to Rust. Don't build new
  features on it.
- `apps/web-next-legacy`: superseded Next.js app, preserved for reference.

## Prerequisites

- Node.js + pnpm (`packageManager: pnpm@11.7.0`, see root `package.json`)
- Rust toolchain (for `apps/api`, built with `cargo`)
- Flutter SDK (for `apps/app`)
- Docker, if you want to run Postgres/Qdrant/Redis in containers instead of
  the local Node-based helper scripts

Install JS/TS dependencies from the repo root:

```bash
pnpm install
```

## Environment variables

Copy the example env file and fill in secrets/keys as needed:

```bash
copy .env.example .env
```

Key variables (see `.env.example` for the full list):

- `DATABASE_URL` — PostgreSQL connection string, e.g.
  `postgresql://postgres:postgres@localhost:5432/right_answer`
- `REDIS_URL` — e.g. `redis://localhost:6379`
- `QDRANT_URL` — e.g. `http://localhost:6333`, plus `QDRANT_API_KEY` and
  `QDRANT_COLLECTION` (default `right_answer_textbook_chunks`)
- `JWT_SECRET`, `PORT` (API port, default `4000`), `APP_URL`,
  `CORS_ORIGINS`
- `VITE_API_URL` — API URL the web app calls, e.g.
  `http://localhost:4000/api`
- `AI_METHOD` (`openrouter` or `hackai`), `OPENROUTER_API_KEY`,
  `HACKAI_API_KEY`, plus the `AI_*_MODEL` variables for chat, reasoning,
  embedding, and rerank models
- Optional provider keys `GROQ_API_KEY`, `GEMINI_API_KEY`, `OPENAI_API_KEY`
  — if absent, the app falls back to a local rule-based grounded answer
  composer

## Infrastructure: Postgres, Qdrant, Redis

With Docker Desktop:

```bash
docker compose up -d postgres qdrant redis
```

Without Docker Desktop, run the local helper scripts in separate terminals
(also exposed as pnpm scripts):

```bash
pnpm dev:db       # node scripts/start-local-postgres.mjs
pnpm dev:qdrant   # node scripts/start-local-qdrant.mjs
```

## Running each app

Run everything (API + web + workers) concurrently:

```bash
pnpm dev
```

Or run pieces individually:

```bash
pnpm dev:api       # cargo run --manifest-path apps/api/Cargo.toml
pnpm dev:web       # pnpm --filter @right-answer/web dev
pnpm dev:workers   # pnpm --filter @right-answer/workers dev
```

Rust API checks:

```bash
cargo check --manifest-path apps/api/Cargo.toml
```

Flutter app:

```bash
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter run --dart-define=API_URL=http://localhost:4000
```

Once running, by default:

- Web: http://localhost:3000
- API health: http://localhost:4000/api/health

## Database (Prisma textbook schema)

The textbook schema lives in `packages/database` (Prisma) and is separate
from the Rust API's own PostgreSQL migrations (`apps/api/migrations`).

```bash
pnpm db:generate   # prisma generate
pnpm db:migrate    # prisma migrate dev
pnpm db:deploy     # prisma migrate deploy
pnpm db:seed       # seed script
```

## Qdrant vector migration

PostgreSQL is always the source of truth for textbook embeddings; Qdrant
stores a vector copy for fast retrieval. After Postgres has embeddings, sync
them into Qdrant:

```bash
cargo run --manifest-path apps/api/Cargo.toml --bin migrate_qdrant
```

This fails (rather than silently losing data) if PostgreSQL has no
embeddings, if any vector is empty, if Qdrant writes fail, or if the final
Qdrant point count is lower than the migrated PostgreSQL embedding count. It
reads `Embedding.embedding_vector` (pgvector column) when present, and falls
back to `Embedding.embedding_values` for older local databases that only
have the JSON backup values.

## Textbook ingestion (legacy)

Textbook ingestion still runs through `apps/api-node-legacy` until it's
ported to Rust:

```bash
pnpm textbook:extract-pages
pnpm textbook:detect-chapters
pnpm textbook:ingest-local
pnpm textbook:run-all -- --pdf <path> --subject biology --medium en --version 2026-v1
pnpm textbook:batch-csv
```

Production seed data is tracked with Git LFS under `storage/`. After local
ingestion, refresh the PostgreSQL textbook seed with:

```bash
pnpm seed:export-postgres
```

## Build, lint, test, format

```bash
pnpm build     # cargo build --release + web build + workers build
pnpm lint      # pnpm -r lint
pnpm test      # pnpm -r test
pnpm format    # pnpm -r format
```

## Other useful scripts

```bash
pnpm ops:status         # scripts/show-runtime-status.ps1
pnpm ops:status:logs     # same, with logs
pnpm ops:db:check        # node scripts/check-db.mjs
```

## Related docs

- [System Documentation](SYSTEM_DOCUMENTATION.md)
- [Rust Backend Migration](RUST_BACKEND_MIGRATION.md)
- [Production VPS Deployment](PRODUCTION_VPS_DEPLOYMENT.md)
- [Flutter App Overview](../apps/app/docs/APP_OVERVIEW.md)
- [Flutter Architecture](../apps/app/docs/ARCHITECTURE.md)
- App-specific setup: `apps/app/README.md`, `apps/api/README.md`,
  `apps/web/README.md`
