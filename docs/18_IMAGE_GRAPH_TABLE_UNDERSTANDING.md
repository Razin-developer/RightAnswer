# Image, Graph, Table, and Illustration Understanding

## Objective

Handle textbook visuals as first-class study content so student questions about tables, graphs, and diagrams can often be answered without live vision calls.

## Asset Types

- Images
- Diagrams
- Illustrations
- Charts
- Graphs
- Table images

## Stored Fields For Every Asset

- asset ID
- textbook version
- chapter
- page number
- caption
- OCR text
- nearby paragraph references
- asset file path
- manual correction notes
- generated study explanation
- possible exam questions

## Processing Strategy

### Tables

- Extract image snapshot
- Attempt structured row/column extraction
- Store raw table text
- Link to nearby paragraph and heading
- Pre-generate explanation and possible questions

### Graphs

- Detect graph type if possible
- Extract axis labels using OCR
- Store caption and surrounding text
- Generate graph explanation
- Generate likely exam-style interpretation questions

### Diagrams

- Extract labels
- Store caption
- Create short description
- Generate part-wise explanation
- Generate common textbook questions

## Data Contracts

### Table JSON

```json
{
  "tableId": "table_uuid",
  "pageNumber": 40,
  "caption": "Comparison of ...",
  "rawTableText": "row1 ...",
  "columnHeaders": ["A", "B"],
  "rows": [["x", "y"]],
  "linkedContentUnitIds": ["unit_uuid"],
  "generatedExplanation": "This table compares ..."
}
```

### Graph JSON

```json
{
  "graphId": "graph_uuid",
  "graphType": "line",
  "axisXLabel": "Time",
  "axisYLabel": "Growth",
  "caption": "Growth over time",
  "generatedExplanation": "The graph shows an increasing trend ..."
}
```

### Diagram JSON

```json
{
  "diagramId": "diagram_uuid",
  "caption": "Human heart",
  "labels": [{"text": "aorta", "x": 0.4, "y": 0.2}],
  "generatedDescription": "This diagram shows the human heart and its major parts."
}
```

## Student Q&A Strategy

- If asset already exists and has structured description, answer from stored text first
- Only use live vision later for admin correction or unsupported visuals
- Cite page and chapter along with nearby explanatory paragraph

## Manual Correction Workflow

- Admin can rename misdetected graph type
- Admin can fix axis labels or diagram part names
- Teacher can improve generated explanation or exam questions

## Acceptance Criteria

- Visual asset questions can be answered from preprocessed data in most cases
- Each table/graph/diagram has chapter and page mapping
- Asset explanations remain tied to textbook context, not generic image interpretation
