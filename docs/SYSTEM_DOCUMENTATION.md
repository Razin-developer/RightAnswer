# RightAnswer System Documentation

RightAnswer is a local-first AI study partner. The mobile app stores learning
data in SQLite, the backend serves textbook-grounded AI answers, and the web app
explains the product plus exposes admin usage tables.

## Current Architecture

### Flutter App

- Stores local subjects, chapters, chunks, chats, exams, study plans, queue
  items, and outputs in SQLite.
- Opens existing local chats before creating a new one.
- Bypasses login for normal local use.
- Offline mode reads local data and blocks AI generation.
- Sync and sharing remain online/authenticated features.
- Chat rendering supports rich answer JSON through `RichAnswerView`.
- Text-to-speech uses `speechText` from rich answers or sanitizes Markdown,
  LaTeX, tables, code fences, and symbols before speaking.

### Rust API

New compiled backend location: `apps/api`.

Stack:

- Axum for HTTP routing.
- Tokio for async runtime.
- SQLx for PostgreSQL.
- Reqwest for OpenRouter/HackAI and Qdrant REST calls.
- Tower/Tower HTTP for timeout, CORS, and tracing middleware.
- Tracing for logs.
- Serde for all request/response JSON.

The Node backend is preserved at `apps/api-node-legacy`.

### Web

New React/Vite app location: `apps/web`.

The old Next.js app is preserved at `apps/web-next-legacy`.

Pages:

- Landing page.
- App Features page.
- Documentation page.
- Admin metrics page for AI usage, user usage, API calls, token totals, and
  estimated expenses.

## AI/RAG Pipeline

1. The app sends the question, optional chat history, selected subject/chapter
   ids, and any local source chunks to `/api/ai/chat`.
2. The Rust API embeds the query through OpenRouter/HackAI.
3. Qdrant retrieves textbook vectors filtered by chapter when chapter ids are
   available.
4. Direct app-provided contexts and Qdrant contexts are merged.
5. The rerank model selects the best 3 to 5 contexts.
6. The chat model receives the selected contexts and the rich-answer prompt
   contract.
7. The backend records usage and optional authenticated chat sync data.
8. The Flutter app stores and renders the answer locally.

## Rich Answer Contract

Schema: `right_answer.rich_answer.v1`

The model is prompted to return:

- `renderMarkdown`: complete fallback answer.
- `speechText`: clean speaker-only transcript.
- `blocks`: typed specialized renderer blocks.
- `sources`: text/page/image/table/graph/diagram source list.
- `needsMoreContext`.
- `limitations`.
- `confidence`.

Supported block families:

- Markdown.
- LaTeX math.
- Tables.
- Geometry.
- Function graphs.
- Charts.
- SVG.
- Images.
- Labelled diagrams.
- Physics diagrams.
- Circuits.
- Molecules and atoms.
- Concept graphs and flowcharts.
- Timelines.
- Code.
- Quotes, callouts, flashcards, and quizzes.

The 505-line specialized prompt lives at:

`apps/api-node-legacy/src/prompts/rich-answer.prompt.ts`

The Rust backend currently has a compact equivalent in `apps/api/src/openrouter.rs`.
When parity is required, move the full prompt text into Rust as a static prompt
module.

## Storage

### PostgreSQL

PostgreSQL is the relational source of truth.

Rust migration `apps/api/migrations/0001_core.sql` creates:

- `users`
- `chats`
- `chat_messages`
- `answer_cache`
- `ai_usage_events`

The existing Prisma textbook schema remains in `packages/database/prisma`.

### Qdrant

Qdrant stores vector copies and retrieval payloads for textbook chunks.

Collection default:

`right_answer_textbook_chunks`

Payload fields:

- `content_unit_id`
- `text`
- `content_type`
- `chapter_id`
- `page_number`
- `image_url`
- `embedding_model`
- `embedding_version`

## Data Migration Safety

Run:

```bash
cargo run --manifest-path apps/api/Cargo.toml --bin migrate_qdrant
```

The migration utility:

- Reads PostgreSQL `Embedding`, `ContentUnit`, `Page`, and `TextbookAsset`.
- Creates the Qdrant collection with the embedding dimension from PostgreSQL.
- Upserts points in batches.
- Counts Qdrant points after migration.
- Fails if PostgreSQL has no embeddings.
- Fails if Qdrant contains fewer migrated points than PostgreSQL rows.

Do not switch production traffic to Qdrant retrieval until this command succeeds.

## Environment

Rust API:

```bash
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/right_answer
JWT_SECRET=change-me
PORT=4000
APP_URL=http://localhost:3000
AI_METHOD=openrouter
OPENROUTER_API_KEY=...
HACKAI_API_KEY=...
AI_SIMPLE_MODEL=google/gemma-3-12b-it
AI_REASONING_MODEL=google/gemma-4-31b-it
AI_EMBEDDING_MODEL=perplexity/pplx-embed-v1-0.6b
AI_RERANK_MODEL=nvidia/llama-nemotron-rerank-vl-1b-v2:free
QDRANT_URL=http://localhost:6333
QDRANT_COLLECTION=right_answer_textbook_chunks
```

React web:

```bash
VITE_API_URL=http://localhost:4000/api
```

Flutter app build:

```bash
--dart-define=API_URL=http://your-vps:4000
```

## Development Commands

```bash
pnpm dev
pnpm dev:api
pnpm dev:web
cargo check --manifest-path apps/api/Cargo.toml
pnpm --filter @right-answer/web build
```

Legacy commands:

```bash
pnpm --filter @right-answer/api-node-legacy textbook:run-all
pnpm --filter @right-answer/web-next-legacy dev
```

## Deployment Shape

VPS services:

- `postgres`
- `qdrant`
- `redis` if workers still need it
- `api` Rust binary
- `web` Nginx static React app
- `workers` Node workers until ported

`docker-compose.yml` has been updated for this shape.

## Current Migration Status

Completed:

- Node backend moved to `apps/api-node-legacy`.
- Next.js app moved to `apps/web-next-legacy`.
- Rust Axum API scaffolded in `apps/api`.
- React/Vite web app scaffolded in `apps/web`.
- Qdrant migration utility added.
- Admin metrics endpoint and page added.
- Docker compose moved from Mongo to Qdrant for the new backend path.

Remaining parity work:

- Port all Nest modules from legacy into Rust one by one.
- Port textbook ingestion from Node to Rust or keep it as a legacy worker.
- Move the full rich-answer prompt from TypeScript into Rust static data.
- Add exact cache and semantic cache in Rust.
- Add share-link/content-share parity in Rust.
- Add full test coverage after dependencies build locally.
