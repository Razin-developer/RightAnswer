# Feature Specification

## Feature Groups

1. Textbook Corpus Management
2. Student Q&A
3. Revision and Study Tools
4. Teacher Tools
5. Admin Operations
6. Billing, Limits, and Exam Mode

## Student Q&A Features

| Feature | Description | MVP | Acceptance Criteria |
| --- | --- | --- | --- |
| Ask question | Student asks free-text question | Yes | Answer returned with citations or explicit not-found status |
| Subject filter | Student chooses subject | Yes | Retrieval respects selected subject |
| Chapter filter | Student chooses chapter | Yes | Retrieval score boosted by selected chapter |
| Answer format | 1/2/3/4/5 mark, simple, long | Yes | Output length and structure follow requested format |
| Language toggle | English / Malayalam | Yes | Answer generated in selected language |
| Citation view | Show chapter/page/source lines | Yes | Every answer shows source references when available |
| Follow-up questions | Light follow-up within same chapter | Limited | Context window capped to control cost |

## Revision Features

| Feature | Description | MVP | Acceptance Criteria |
| --- | --- | --- | --- |
| Chapter summary | Pre-generated or generated summary | Yes | Summary uses textbook-grounded content only |
| Important questions | High-priority exam questions | Yes | Questions linked to chapter |
| Flashcards | Q/A cards from textbook units | Yes | Cards map to chapter and answer type |
| Quiz mode | Short chapter quiz | Yes | Questions generated from textbook units |
| Quick revision | Fast review cards | Yes | Loads from cache or pregenerated content |

## Teacher Features

| Feature | Description | MVP | Acceptance Criteria |
| --- | --- | --- | --- |
| Worksheet generation | Generate chapter worksheet | Yes | Output can be exported and saved |
| Answer verification | Mark answer as verified | Yes | Verified answer enters Gold cache |
| Common doubts view | View frequent student questions | Yes | Aggregated by chapter/subject |
| Custom question sets | Assemble teacher-curated sets | Limited | Stored and exportable |

## Admin Features

| Feature | Description | MVP | Acceptance Criteria |
| --- | --- | --- | --- |
| Textbook upload | Manual PDF upload | Yes | File stored with checksum and metadata |
| Official download | Download from approved source | Yes | URL provenance stored |
| OCR correction | Fix extracted text | Yes | Changes versioned and auditable |
| Re-index textbook | Rebuild chunks and embeddings | Yes | New version does not break old references |
| Provider controls | Enable/disable model providers | Yes | Routing tables update without redeploy |
| Exam mode toggle | Activate high-traffic controls | Yes | Free user premium fallback disabled immediately |

## System Features

- Exact cache
- Semantic cache
- Retrieval cache
- Answer cache
- Verified answer cache
- Exam hot cache
- Model routing
- Circuit breaker
- Queue-based ingestion and heavy background jobs

## User Stories

### Student

- As a student, I want a 3-mark answer from the Biology chapter I selected so I can write directly in exams.
- As a student, I want a Malayalam explanation of an English chapter paragraph so I can understand it quickly.
- As a student, I want a graph or table explained without uploading the image again if it already exists in the textbook.

### Teacher

- As a teacher, I want to generate a worksheet from one chapter and export it so I can use it for tuition batches.
- As a teacher, I want to verify a good answer so future students receive it from cache.

### Admin

- As an admin, I want to inspect extraction output page by page so I can correct OCR and structure errors before embeddings are generated.

## Edge Cases

- Question asks for chapter content from the wrong subject
- Exercise sub-question references previous sub-question context
- Malayalam and English mixed in same query
- Textbook answer not present directly; system must say so and provide nearby explanation carefully
- Multiple textbook versions exist for same subject and medium

## Priority Order

1. Textbook ingestion accuracy
2. Student answer quality
3. Cache effectiveness
4. Teacher verification workflow
5. Admin observability

## Feature Acceptance Test Checklist

- Question answers include source references
- Cached answer reuse increments usage counters
- Verification upgrades cache confidence
- Exam mode changes routing behavior immediately
- OCR corrections trigger re-index of affected chunks only
