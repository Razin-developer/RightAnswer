# Evaluation and Metrics

## Objective

Measure whether Right Answer is accurate, grounded, fast, and cost-efficient enough for real SSLC usage.

## Target Metrics

```txt
Retrieval Recall@5: 90%+
Chapter match accuracy: 95%+
Citation correctness: 95%+
Premium fallback rate: <5%
Cache hit rate: 70%+
P95 cached answer latency: <500ms
P95 generated answer latency: <15s
Wrong answer rate: <3–5%
```

## Evaluation Categories

- Retrieval accuracy
- Answer groundedness
- Citation correctness
- Cache hit quality
- Malayalam answer quality
- English answer quality
- Exam answer quality
- Hallucination rate
- Cost per answer
- Latency
- Provider failure rate
- Queue wait time
- Student feedback

## Offline Test Dataset Design

### Gold Set Composition

- 1000 to 3000 real or teacher-authored SSLC questions
- Balanced across subjects, chapters, and answer formats
- Mix of English, Malayalam, and mixed-language wording
- Include diagram/table/graph questions
- Include easy definition and hard reasoning questions

### Labels Required

- correct subject
- correct chapter
- expected supporting page or pages
- answer type
- textbook-grounded reference answer
- accepted alternate phrasings

## Retrieval Evaluation

- `Recall@5`
- `Recall@10`
- chapter match accuracy
- first relevant result rank
- content-type match rate

## Answer Quality Evaluation

- groundedness score
- citation correctness
- mark-format compliance
- readability for Class 10
- bilingual fluency
- unsupported-claim count

## Live Metrics Dashboard

- cache hit rates by layer
- live generation rate
- premium fallback rate
- provider error rate
- cost per 1000 requests
- P50/P95 latency
- queue backlog and wait times
- negative feedback rate

## Review Workflow

- Weekly offline retrieval benchmark
- Daily live quality anomaly review
- Teacher sampling of Silver answers for Gold promotion
- Monthly pricing and routing review

## Acceptance Criteria

- Every release includes retrieval and answer quality benchmark runs
- Regression alerts fire when citation correctness or cache hit rate drops materially
