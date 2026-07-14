# Right Answer

Right Answer is a Kerala SSLC-focused AI study companion built around textbook-grounded retrieval, layered caching, and cost-aware model routing. This repo contains the first production-oriented monorepo version with:

- `apps/web`: Next.js student, teacher, and admin UI
- `apps/api`: NestJS + Fastify backend
- `apps/workers`: BullMQ worker runtime
- `packages/database`: Prisma schema, pgvector-ready design, and seed data
- `packages/storage`: local-first storage adapter for raw and processed textbook artifacts
- `packages/prompts`, `packages/types`, `packages/config`, `packages/ui`: shared domain packages

## Stack

- Next.js App Router
- NestJS + Fastify
- PostgreSQL + pgvector
- Redis
- BullMQ
- Prisma
- Tailwind CSS
- TypeScript

## Embedding Configuration

- Code defaults now target `Qwen/Qwen3-Embedding-4B`
- Local `.env` is intentionally pinned to `Qwen/Qwen3-Embedding-0.6B` for safer development runs
- Switch models entirely through environment variables without changing code:
  - `RIGHT_ANSWER_EMBEDDING_BACKEND`
  - `RIGHT_ANSWER_EMBEDDING_MODEL`
  - `RIGHT_ANSWER_EMBEDDING_DIMENSIONS`
  - `RIGHT_ANSWER_EMBEDDING_MAX_LENGTH`
  - `RIGHT_ANSWER_EMBEDDING_BATCH_SIZE`
  - `RIGHT_ANSWER_EMBEDDING_THREADS`
  - `RIGHT_ANSWER_EMBEDDING_MAX_REQUESTS_PER_WORKER`
  - `RIGHT_ANSWER_EMBEDDING_DEVICE`

Recommended production-safe default for the current DB layout: keep `RIGHT_ANSWER_EMBEDDING_DIMENSIONS=1024` unless the vector column strategy is migrated for larger dimensions.

## Operations

- `pnpm ops:status` shows the current embedding env, running `node/python/postgres` processes, storage directories, and DB counts
- `pnpm ops:status:logs` includes the latest ingestion logs
- `pnpm ops:db:check` runs a direct Prisma-based DB connectivity and row-count check

## Colab

- GPU batch scripts are in [scripts/colab/all-in-one.sh](/C:/Users/razin/Desktop/Coding/t-answer/scripts/colab/all-in-one.sh), [scripts/colab/bootstrap-right-answer.sh](/C:/Users/razin/Desktop/Coding/t-answer/scripts/colab/bootstrap-right-answer.sh), [scripts/colab/run-right-answer-batch.sh](/C:/Users/razin/Desktop/Coding/t-answer/scripts/colab/run-right-answer-batch.sh), and [scripts/colab/zip-storage.sh](/C:/Users/razin/Desktop/Coding/t-answer/scripts/colab/zip-storage.sh)
- These are intended for Google Colab or another Linux GPU machine so the full 49-subject run does not happen on your local PC

## Current Product Coverage

- Auth with student/teacher/admin flows
- Student dashboard with subject, chapter, and answer-format driven Q&A
- Cache-first ask flow with exact cache, semantic cache, retrieval cache, and answer cache persistence
- Hybrid retrieval using keyword search plus pgvector-ready semantic search
- Local deterministic embedding and grounded-answer fallback when external AI keys are absent
- Admin endpoints for textbook upload/download ingestion, ingestion jobs, model providers, content-unit review, and exam mode
- Teacher endpoints for answer verification, worksheet generation, and common doubts
- Local textbook storage layout aligned with the docs pack

## Quick Start

1. Copy `.env.example` to `.env`.
2. Start infrastructure:

```bash
docker compose up -d
```

3. Generate Prisma client, run migrations, and seed:

```bash
pnpm db:generate
pnpm db:migrate
pnpm db:seed
```

4. Start the apps:

```bash
pnpm dev
```

5. Open:

- Web: [http://localhost:3000](http://localhost:3000)
- API: [http://localhost:4000/api/v1](http://localhost:4000/api/v1)

## Demo Credentials

- `student@rightanswer.local` / `Password123!`
- `teacher@rightanswer.local` / `Password123!`
- `admin@rightanswer.local` / `Password123!`

## Useful Commands

```bash
pnpm install
pnpm build
pnpm test
pnpm dev:web
pnpm dev:api
pnpm dev:workers
pnpm db:generate
pnpm db:migrate
pnpm db:seed
```

## Local Textbook Pipeline Scripts

The repo now includes a local-first textbook ingestion pipeline that can:

- extract page text from a local PDF
- detect chapter names and start pages from the index / contents pages
- optionally use the local `codex` CLI plus page screenshots for image-heavy TOC pages
- split textbook pages into chapter-linked content units
- detect question blocks, tables, graphs, diagrams, and illustrations heuristically
- write processed textbook artifacts to `storage/textbooks/...`
- insert the structured result into the local PostgreSQL database

PowerShell entrypoint:

```powershell
.\scripts\textbook-pipeline.ps1 run-all `
  --pdf "C:\path\to\textbook.pdf" `
  --subject biology `
  --medium en `
  --version 2026-v1 `
  --title "Biology SCERT Textbook"
```

Optional review and override flags:

```powershell
.\scripts\textbook-pipeline.ps1 run-all `
  --pdf "C:\path\to\textbook.pdf" `
  --subject biology `
  --medium en `
  --version 2026-v1 `
  --interactive `
  --index-page 4 `
  --index-page 5 `
  --chapter "1|Life Processes|12" `
  --chapter "2|Nutrition|24"
```

Notes:

- `--interactive` opens a terminal confirmation step before ingestion.
- `--index-page` can be repeated to force which PDF pages should be treated as the contents/index pages.
- `--chapter` can be repeated to override chapter detection using `chapterNumber|title|printedStartPage`.
- In `run-all`, any chapter data you confirm in the review step is passed into the final ingest step automatically.

Available subcommands:

- `extract-pages`
- `detect-chapters`
- `ingest-local`
- `run-all`

Equivalent package scripts:

```bash
pnpm textbook:extract-pages -- --pdf ... --subject biology --medium en --version 2026-v1
pnpm textbook:detect-chapters -- --pdf ... --subject biology --medium en --version 2026-v1
pnpm textbook:ingest-local -- --pdf ... --subject biology --medium en --version 2026-v1
pnpm textbook:run-all -- --pdf ... --subject biology --medium en --version 2026-v1
```

## External Providers

The model gateway is already structured for Groq, Gemini, and OpenAI provider routing. If provider API keys are not configured, the system falls back to a local deterministic grounded-answer composer so the app remains usable while preserving:

- textbook-first retrieval
- cache-first answering
- premium-fallback protection for free users
- exam-mode routing constraints

## Known MVP Gaps

- OCR fallback is detected conceptually but not yet expanded into a full scanned-PDF OCR pipeline
- Visual asset extraction is scaffolded through storage and schema, but deep diagram/table segmentation can be improved
- Payment checkout is an interface stub pending gateway credentials
- Worker consumers are wired and queue-aware, but still need fuller background job execution logic for long-running ingest/export flows
