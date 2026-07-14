# Tech Stack Decision

## Recommended Stack

### Frontend

- Next.js App Router
- TypeScript
- Tailwind CSS
- shadcn/ui

### Backend

- NestJS or Fastify
- TypeScript
- Zod for request validation

### Data

- PostgreSQL
- pgvector
- Redis
- Prisma or Drizzle ORM

### Background Work

- BullMQ
- Worker service in same monorepo

### Storage

- Local storage abstraction in development
- Cloudflare R2 or S3-compatible object storage in production

### AI Observability

- Langfuse or custom structured logging
- OpenTelemetry optional

### Developer Experience

- Docker Compose
- pnpm monorepo
- ESLint, Prettier, Vitest, Playwright

## Primary Recommendation

### Backend Choice

- Prefer **NestJS** if the team values strong module boundaries, decorators, and enterprise-style structure.
- Prefer **Fastify** if the team wants a lighter, lower-overhead API core and is comfortable designing module patterns manually.

Recommended MVP choice: **NestJS**, because the product has many modules, admin flows, workers, and policy-rich services.

### ORM Choice

- Prefer **Prisma** for productivity, schema clarity, and team familiarity.
- Prefer **Drizzle** if tighter SQL control is required early.

Recommended MVP choice: **Prisma**, with raw SQL migrations for pgvector indexes if needed.

## Alternatives and Tradeoffs

| Area | Preferred | Alternative | Tradeoff |
| --- | --- | --- | --- |
| Frontend | Next.js | Remix | Next.js has stronger ecosystem fit for dashboard + landing flows |
| Backend | NestJS | Fastify | NestJS adds structure; Fastify may be leaner |
| ORM | Prisma | Drizzle | Prisma faster for CRUD; Drizzle gives more SQL control |
| Queue | BullMQ | Temporal later | BullMQ simpler for MVP; Temporal better for very complex workflows |
| Storage | R2 | S3 | Similar interface; choose by hosting environment and egress economics |
| Observability | Langfuse | custom | Langfuse faster for AI tracing, custom cheaper long-term |

## Why This Stack Fits Right Answer

- TypeScript across web, API, and workers reduces coordination overhead
- PostgreSQL + pgvector matches structured content plus semantic retrieval
- Redis supports cache, limits, and queues in one operational layer
- Next.js enables student, teacher, and admin apps from one codebase
- Docker keeps local-first ingestion and OCR workflows reproducible

## Acceptance Criteria

- Stack supports local-first development and cloud migration
- Core dependencies are stable and common enough for a follow-on coding agent to implement quickly
