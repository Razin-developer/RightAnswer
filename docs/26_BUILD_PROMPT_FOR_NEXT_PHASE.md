# Build Prompt For Next Phase

Use the following prompt for the coding phase.

```txt
You are building the full production-oriented MVP of Right Answer, a Kerala SSLC-focused AI study companion.

Before writing code:
1. Read every file in /docs first.
2. Follow the documentation pack as the source of truth.
3. Do not treat this as a generic chatbot build. It is a textbook-grounded SSLC study system.
4. Prioritize cache-first, retrieval-first, and cost-controlled architecture.

Build the application in phases, but continue until the system is runnable end to end.

Required implementation scope:

1. Create a clean monorepo structure.
   - apps/web
   - apps/api
   - apps/workers
   - packages/ui
   - packages/config
   - packages/types
   - packages/prompts
   - packages/storage
   - packages/database

2. Implement the database layer.
   - PostgreSQL + pgvector
   - Prisma or Drizzle schema and migrations
   - seed data for subjects, plans, and one sample textbook corpus

3. Implement the local storage abstraction.
   - raw textbook storage
   - processed textbook artifacts
   - cache storage
   - export storage

4. Implement the textbook ingestion pipeline.
   - admin upload
   - official download job
   - checksum
   - metadata registration
   - PDF page extraction
   - OCR fallback hooks
   - structured content unit generation
   - asset extraction
   - chunking
   - embedding generation hooks
   - ingestion job tracking

5. Implement the RAG pipeline.
   - query normalization
   - subject/chapter detection
   - exact cache
   - semantic cache
   - hybrid retrieval
   - reranking
   - parent-child expansion
   - confidence scoring
   - citation packaging

6. Implement the cache system.
   - Redis-backed exact cache
   - semantic cache
   - retrieval cache
   - answer cache persistence
   - verified answer cache
   - exam hot cache

7. Implement the model gateway.
   - provider abstraction
   - model registry
   - route policies
   - retries
   - circuit breaker
   - cost logging
   - provider enable/disable controls

8. Implement rate limiting and subscription behavior.
   - free and paid plan limits
   - cached vs live quotas
   - premium fallback gating
   - queue priority by plan

9. Implement exam mode.
   - admin toggle
   - route overrides
   - hot cache preference
   - shorter answers by default
   - free-user premium fallback block

10. Implement the student web app.
   - landing page
   - login/signup
   - dashboard
   - subject/chapter selector
   - ask question flow
   - answer card with citations
   - revision page
   - important questions
   - flashcards
   - quiz
   - exam mode page
   - answer history
   - subscription page

11. Implement the admin dashboard.
   - textbook upload and download
   - ingestion jobs
   - page/content review
   - provider controls
   - exam mode controls
   - rate-limit controls
   - feedback review

12. Implement the teacher dashboard.
   - worksheet generation
   - answer verification
   - common doubts
   - question set creation

13. Add tests.
   - unit tests
   - API tests
   - retrieval logic tests
   - cache behavior tests
   - basic end-to-end UI tests

14. Add operational basics.
   - README
   - .env.example
   - Docker setup
   - docker-compose for postgres and redis
   - seed commands
   - clear run commands

15. Make pragmatic MVP decisions when implementation details are missing, but stay consistent with the docs.

Important build rules:
- Keep the project local-first but cloud-migratable.
- Use TypeScript throughout.
- Keep student-facing UX fast and minimal.
- Never expose full textbook files publicly.
- Ensure free users cannot trigger premium fallback models.
- Log cache hits, model calls, retrieval decisions, and feedback.
- Add sample data so the app can be run and demonstrated immediately.

When finished:
- verify the app runs locally
- document all commands
- summarize what is complete
- list any clearly marked follow-up items
```
