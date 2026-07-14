# Retrieval Algorithms

## Objective

Design deterministic, debuggable, and high-recall retrieval for textbook-grounded student answers.

## Retrieval Stack

1. Metadata filter narrowing
2. BM25 / PostgreSQL full-text search
3. Vector similarity search
4. Merge and deduplicate
5. Reranking
6. Parent-child expansion
7. Confidence estimation

## Retrieval Input Features

- user-selected subject
- user-selected chapter
- answer format
- detected content type: definition, exercise, diagram, formula
- detected language
- textbook version

## Metadata Filter Rules

- If subject selected, make it mandatory
- If chapter selected, make it mandatory unless results are empty
- If answer asks for diagram/graph/table, boost asset-linked content types
- If question contains `define`, boost definition units
- If question contains `exercise`, boost extracted question units

## Keyword Search

- Use `to_tsvector('simple', normalized_text)` for first pass
- Add custom normalization for Malayalam punctuation and English stopword trimming
- Boost heading and question text matches higher than generic paragraph matches

## Vector Search

- Query against chunk embeddings
- Use cosine similarity
- Search top 30 to 50 candidates before merge

## Merge Logic

```txt
candidate_pool = union(top_bm25, top_vector)
group by content_unit_id or chunk_id
select highest evidence per group
compute final hybrid score
sort descending
```

## Hybrid Score Formula

```txt
final_score =
  0.35 * keyword_score +
  0.35 * vector_score +
  0.15 * metadata_match_score +
  0.10 * proximity_score +
  0.05 * historical_success_score
```

## Confidence Computation

```txt
confidence =
  0.30 * top_result_strength +
  0.20 * top3_score_consistency +
  0.20 * citation_density +
  0.15 * chapter_alignment +
  0.15 * content_type_alignment
```

## Parent-Child Expansion Rules

- For paragraph hit: include heading + adjacent paragraphs
- For exercise hit: include parent exercise container + sibling sub-question if referenced
- For asset hit: include caption + nearest explanatory paragraph

## Historical Success Score

Based on:

- prior positive feedback
- verified answer usage
- low hallucination reports
- stable citation correctness

## Retrieval Failure Modes

| Failure | Mitigation |
| --- | --- |
| Too many generic paragraphs | Increase chapter and heading boosts |
| Wrong subject hit | Make subject mandatory when selected |
| Exercise sub-question misses context | Expand to parent question chain |
| Malayalam phrasing mismatch | Improve normalization and semantic cache reuse |

## Acceptance Criteria

- Retrieval logs expose intermediate ranking data
- Top-5 results are sufficiently diverse but chapter-consistent
- Retrieval can explain why a result was chosen
