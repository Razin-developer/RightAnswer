# Embedding Strategy

## Objective

Generate stable embeddings for textbook content and cache questions so retrieval remains accurate, cheap, and auditable.

## Embedding Targets

- Content unit embeddings
- Chunk embeddings
- Semantic cache question embeddings
- Optional teacher-generated verified answer embeddings later

## What To Embed

### Content Units

- Paragraphs
- Definitions
- Summary items
- Exercise questions
- Answer hints
- Diagram/table/graph descriptions

### Do Not Embed Directly

- Raw full pages as the only retrieval unit
- Empty OCR fragments
- Boilerplate page headers and footers

## Chunking Strategy

- Paragraph-first storage
- Retrieval chunk is usually 1 to 3 adjacent paragraphs
- Merge tiny fragments under minimum token threshold
- Keep chapter heading and page references in chunk metadata

## Recommended Metadata on Every Embedding

```json
{
  "embeddingId": "embedding_uuid",
  "targetType": "content_unit",
  "targetId": "unit_uuid",
  "embeddingModel": "chosen-model",
  "embeddingVersion": "v1",
  "vectorDimensions": 768,
  "contentHash": "sha256_hash",
  "subject": "Biology",
  "chapterNumber": 2,
  "language": "en"
}
```

## Rebuild Triggers

- Content unit text changed
- Chunking algorithm changed
- Embedding model changed
- Normalization pipeline changed
- Poor retrieval metrics require refresh

## Versioning Policy

- Maintain `embedding_version`
- Maintain `chunking_version`
- Keep old embeddings until cutover validation completes
- Reindex semantic cache separately from textbook content

## Language Strategy

- Store original Malayalam text
- Embed normalized text suitable for multilingual semantic similarity
- Preserve script fidelity in stored text even if normalization removes some punctuation

## Operational Strategy

- Generate embeddings asynchronously
- Batch inserts for throughput
- Store backup export files for disaster recovery
- Use background validation query set after rebuild

## Acceptance Criteria

- Embeddings are reproducible from stored artifacts
- Every published textbook chunk has an embedding unless explicitly excluded
- Retrieval tests run after embedding refresh
