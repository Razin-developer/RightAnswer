# Local Storage Schema

## Objective

Provide a local-first storage layout that is easy to debug during development and easy to migrate to cloud object storage later.

## Base Structure

```txt
storage/
  textbooks/
    raw/
      sslc/
        biology/
          english/
            textbook.pdf
    processed/
      sslc/
        biology/
          english/
            textbook.json
            pages/
            chapters/
            chunks/
            assets/
            tables/
            graphs/
            diagrams/
            embeddings/
  cache/
    exact/
    semantic/
    retrieval/
    answers/
  exports/
  logs/
```

## Recommended Expanded Layout

```txt
storage/
  textbooks/
    raw/{syllabus}/{subject_slug}/{medium}/{version_label}/
      source.pdf
      source.meta.json
    processed/{syllabus}/{subject_slug}/{medium}/{version_label}/
      textbook.json
      manifest.json
      pages/
        001.json
        001.png
      chapters/
        chapter-01.json
      chunks/
        chunk-000001.json
      assets/
        asset-000001.png
      tables/
        table-000001.json
      graphs/
        graph-000001.json
      diagrams/
        diagram-000001.json
      embeddings/
        content-units.jsonl
        question-cache.jsonl
  cache/
    exact/{hash_prefix}/
    semantic/{hash_prefix}/
    retrieval/{hash_prefix}/
    answers/{hash_prefix}/
    hot/
  exports/
    worksheets/
    teacher-sets/
    reports/
  logs/
    ingestion/
    workers/
    api/
    audits/
```

## Folder Responsibilities

| Folder | Stores |
| --- | --- |
| `textbooks/raw` | Original PDFs and source metadata |
| `textbooks/processed` | Structured textbook artifacts used by the app |
| `pages` | Per-page JSON and optional rendered preview images |
| `chapters` | Chapter-level consolidated JSON |
| `chunks` | Retrieval-ready content chunk JSON files |
| `assets` | Extracted images, diagrams, illustrations |
| `tables` | Table JSON, snapshots, and parse metadata |
| `graphs` | Graph metadata, label extraction, explanations |
| `diagrams` | Diagram labels, descriptions, possible questions |
| `embeddings` | Exported embedding payloads or backups |
| `cache` | File-backed dev cache snapshots and debugging artifacts |
| `exports` | Generated worksheets and downloadable teacher assets |
| `logs` | Operational logs and audit evidence |

## File Contracts

### `manifest.json`

- textbook version metadata
- checksum
- chunking version
- embedding version
- extraction timestamp
- approval status

### `textbook.json`

- normalized high-level textbook object
- chapter list
- page mapping
- asset index
- content unit index

### `chunk-*.json`

- chunk ID
- source content unit IDs
- chunk text
- metadata filters
- linked asset IDs

## Storage Rules

- Raw source files are immutable after registration
- Processed files are versioned by textbook version and pipeline version
- File paths are stored in database records
- No student PII should be stored under textbook paths

## Migration Strategy

- Build a storage adapter with methods like `put`, `get`, `exists`, `list`, `delete_soft`
- Use same logical keys for local disk and future object storage
- Keep derived artifacts reproducible so they can be rebuilt if needed

## Acceptance Criteria

- Developer can inspect any textbook version without database-only tooling
- Paths are deterministic and safe for reprocessing
- Raw and processed artifacts are clearly separated
