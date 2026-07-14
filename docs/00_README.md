# Right Answer Documentation Pack

## Purpose

This folder is the implementation-ready planning pack for **Right Answer**, a Kerala SSLC-focused AI study companion. The pack is written for an AI coding agent or engineering team that will build the product in the next phase.

The product is intentionally narrow:

- Audience: Kerala SSLC Class 10 students first
- Scope: Official Kerala SSLC textbook-grounded learning
- Output style: exam-oriented, citation-backed, Malayalam and English support
- Cost strategy: cache-first, retrieval-first, cheap-model-first, premium-last

## Build Philosophy

The system must be built in this order:

1. Textbook source strategy and ingestion reliability
2. Structured textbook storage
3. Retrieval quality
4. Multi-layer cache
5. Cost-aware model gateway
6. Student-facing and staff-facing web apps

## Documentation Map

| File | Purpose |
| --- | --- |
| `01_PRODUCT_PRD.md` | Core product requirements and business goals |
| `02_USER_PERSONAS.md` | Primary, secondary, and future user profiles |
| `03_FEATURE_SPEC.md` | Feature inventory, user stories, and acceptance criteria |
| `04_SYSTEM_ARCHITECTURE.md` | End-to-end system architecture and deployment model |
| `05_TEXTBOOK_INGESTION_PRD.md` | Ingestion product requirements and workflows |
| `06_TEXTBOOK_DOWNLOAD_AND_SOURCE_STRATEGY.md` | Safe source policy and download rules |
| `07_DOCUMENT_ANALYSIS_PIPELINE.md` | PDF parsing, OCR, asset extraction, validation |
| `08_RAG_PIPELINE.md` | Query understanding, retrieval, reranking, generation flow |
| `09_CACHE_SYSTEM.md` | Exact, semantic, retrieval, answer, verified, exam caches |
| `10_MODEL_ROUTING_AND_FALLBACK.md` | Model gateway, routing, retries, provider fallback |
| `11_EXAM_MODE.md` | High-traffic exam operation strategy |
| `12_RATE_LIMITING_AND_PLANS.md` | Plans, quotas, budgets, rate-limit rules |
| `13_DATABASE_SCHEMA.md` | PostgreSQL + pgvector relational schema |
| `14_LOCAL_STORAGE_SCHEMA.md` | Local-first storage layout and file contracts |
| `15_EMBEDDING_STRATEGY.md` | Embedding generation, versioning, rebuild strategy |
| `16_RETRIEVAL_ALGORITHMS.md` | Hybrid search, scoring, confidence, reranking |
| `17_ANSWER_GENERATION_ALGORITHMS.md` | Prompting, answer styles, grounding logic |
| `18_IMAGE_GRAPH_TABLE_UNDERSTANDING.md` | Visual asset ingestion and reasoning strategy |
| `19_EVALUATION_AND_METRICS.md` | Offline and live quality evaluation |
| `20_ADMIN_AND_TEACHER_DASHBOARD.md` | Operational and teacher tools |
| `21_STUDENT_WEB_APP_UX.md` | Student-facing UX, IA, flows, and components |
| `22_API_SPEC.md` | Backend API contracts |
| `23_SECURITY_PRIVACY_AND_COPYRIGHT.md` | Security model, privacy, upload safety, copyright |
| `24_SCALING_AND_FAILURE_ANALYSIS.md` | Scalability and resilience design |
| `25_TECH_STACK_DECISION.md` | Recommended stack and alternatives |
| `26_BUILD_PROMPT_FOR_NEXT_PHASE.md` | Exact handoff prompt for the coding phase |

## MVP Boundary

The MVP should support:

- Class 10 Kerala SSLC
- 4 to 8 core subjects first
- English and Malayalam textbook mediums
- Admin ingestion of official textbook PDFs
- Student Q&A grounded in textbook content
- Chapter revision, important questions, flashcards, and quiz generation
- Teacher answer verification and worksheet generation
- Free and paid plans with strict AI budget controls

## Non-Goals For First Build

- General knowledge chatbot behavior
- Support for all school boards
- Unlimited live vision calls
- Full textbook republication
- Rich collaborative classroom tools
- Native mobile app

## Folder-Level Acceptance Criteria

- Every markdown file is actionable and implementation-oriented
- Every major subsystem has storage, schema, API, and failure notes
- Diagrams are included using Mermaid
- Cost control is treated as a first-class architecture constraint
- Copyright-safe textbook usage is explicitly enforced
