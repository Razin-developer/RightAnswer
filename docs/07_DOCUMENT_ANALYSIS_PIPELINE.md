# Document Analysis Pipeline

## Goal

Convert raw textbook PDFs into high-quality, structured study data with explicit links between text, visuals, exercises, and textbook metadata.

## Pipeline Stages

1. File registration
2. PDF fingerprinting and metadata extraction
3. Digital text extraction
4. OCR fallback for scanned pages
5. Layout analysis
6. Structural segmentation
7. Visual asset extraction
8. Specialized content labeling
9. Chunk generation
10. Validation and correction

## Per-Page Analysis Contract

Each page should produce a JSON record like:

```json
{
  "pageId": "page_uuid",
  "pageNumber": 34,
  "width": 2480,
  "height": 3508,
  "languageHints": ["en", "ml"],
  "hasDigitalText": true,
  "ocrUsed": false,
  "blocks": [],
  "assets": [],
  "warnings": ["possible_header_overlap"]
}
```

## Extraction Strategy

### Digital PDFs

- Use PDF text extraction first
- Preserve bounding boxes if tool support exists
- Reconstruct reading order using coordinates

### Scanned PDFs

- Render page image
- Run OCR with Malayalam and English models
- Merge OCR lines into paragraphs using layout heuristics
- Flag low-confidence pages for manual review

## Structure Detection Rules

| Unit | Detection Heuristics |
| --- | --- |
| Chapter | Font size, numbering, page reset, table-of-contents match |
| Section | Medium-sized bold text, spacing before block |
| Paragraph | Continuous lines with consistent indentation |
| Definition | Bold term + separator, glossary-like phrasing |
| Formula | High symbol density or math layout |
| Exercise | Keywords plus numbering patterns |
| Activity / Experiment | Title keywords and boxed layout |
| Summary box | Highlight box or section header near page end |

## Asset Extraction

- Export images and diagrams as page-linked files
- Store table as both image snapshot and structured rows if extraction succeeds
- Capture graph area and OCR labels
- Link every asset to previous and next nearest paragraph IDs

## Multilingual Handling

- Store original text as extracted
- Store normalized text separately for retrieval
- Preserve Malayalam Unicode
- Maintain transliteration helper fields only if later needed for search assistance

## Quality Scoring

Each page and each structural unit should receive:

- `text_confidence`
- `structure_confidence`
- `asset_link_confidence`
- `ocr_confidence`
- `requires_review`

## Correction Workflow

- Admin edits page text
- Admin fixes chapter or section boundaries
- Admin re-tags content type
- System invalidates downstream chunks and embeddings only for affected units

## Recommended Implementation Components

- PDF extraction library
- OCR engine with Malayalam support
- Layout parser
- Rule-based labeler for textbook unit types
- Validation engine
- Admin review UI

## Acceptance Criteria

- 100% of pages are registered and mapped
- 95%+ of paragraphs are linked to correct chapter and page
- 90%+ of exercises are detected in pilot subjects
- Assets are stored with nearby text links and captions
