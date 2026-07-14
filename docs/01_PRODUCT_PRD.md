# Product PRD

## Product Name

**Right Answer**

## Product Summary

Right Answer is a Kerala SSLC-focused AI study companion that answers student questions using official Kerala Class 10 textbook content. It is not a generic chatbot. Its primary job is to produce short, exam-style, source-grounded answers with chapter and page references while keeping AI serving cost low through caching, retrieval, and strict model routing.

## Problem Statement

Kerala SSLC students often rely on tuition notes, YouTube explanations, or generic AI tools that:

- are not aligned to the official textbook
- produce overly long or incorrect answers
- do not match exam mark formats
- fail in Malayalam or mixed Malayalam-English usage
- become expensive to operate at scale if every question requires a fresh model call

## Product Goal

Deliver fast, reliable, textbook-grounded answers and revision tools for Kerala SSLC students, while ensuring that most requests are served from local content, cache, or inexpensive generation paths.

## Primary Success Outcomes

| Outcome | Target |
| --- | --- |
| Cache-assisted answer rate | 70% to 90% |
| Premium fallback usage | Less than 5% |
| Citation correctness | 95%+ |
| Retrieval Recall@5 | 90%+ |
| P95 cached response latency | Under 500 ms |
| P95 generated response latency | Under 15 s |
| Wrong answer rate | Under 3% to 5% |

## Core Value Proposition

- Textbook-grounded answers instead of generic AI responses
- Answers in SSLC exam styles: 1, 2, 3, 4, and 5 mark
- English and Malayalam explanations
- Chapter and page citations
- Fast answers through cache-first design
- Reliable service through multi-provider model routing and fallback

## Users

- Students
- Parents
- Tuition teachers
- Tuition centers
- Schools in later phases

## Product Principles

1. **Textbook first**: answers must originate from stored Kerala SSLC textbook knowledge.
2. **Cost discipline**: avoid unnecessary live model calls.
3. **Citation over confidence theater**: show chapter and page references whenever possible.
4. **Exam-fit responses**: optimize for marks, clarity, and recall.
5. **Bilingual clarity**: support Malayalam and English naturally.
6. **Operational safety**: ingest only trusted textbook sources and store provenance.

## In-Scope Capabilities

- Subject and chapter browsing
- Ask-a-question flow
- Paragraph-wise retrieval
- Exercise question support
- Table, graph, and diagram explanation
- Chapter summaries
- Important questions
- Flashcards and quizzes
- Exam mode
- Teacher worksheet generation
- Teacher verification of answers
- Admin textbook ingestion and correction workflows

## Out of Scope for MVP

- Voice tutoring
- Open-ended life coaching chat
- Real-time collaborative classroom features
- Personalized learning paths based on exams from multiple boards
- Native Android/iOS apps

## Business Constraints

The dominant system constraint is **AI serving cost**.

Required cost behavior:

- Most answers should be served by exact cache, semantic cache, or pre-generated answer sets
- Live generation should be restricted to ambiguous or unseen questions
- Premium model usage must be gated by subscription tier and traffic mode
- Free users must never consume the most expensive fallback path

## Product Requirements

### Functional

- Allow admin to upload or fetch textbook PDFs from official sources
- Parse textbook content into structured storage
- Generate and persist embeddings locally
- Retrieve grounded content using hybrid search
- Return answer formats by mark count and language
- Cache answer outputs and retrieval outputs
- Log all model calls, costs, cache hits, and feedback

### Non-Functional

- Mobile-first UX
- Local development mode without cloud dependencies
- Clear migration path from local storage to object storage
- Auditability for textbook source, version, and answer provenance
- Resilience under exam-season traffic spikes

## Release Strategy

### Phase 1

- Core subjects
- Admin ingestion tools
- Student Q&A
- Cache layers
- Teacher verification
- Subscription plans

### Phase 2

- More subjects and mediums
- School dashboards
- Stronger analytics
- More automated textbook refresh workflows

## Acceptance Criteria

- Product answers are traceable to textbook pages or structured textbook units
- Q&A works in English and Malayalam
- Answer format selection is explicit and predictable
- Textbook provenance is stored for every ingest
- Free plans cannot trigger premium fallback generation
