# Answer Generation Algorithms

## Objective

Generate concise, exam-ready, textbook-grounded answers in Malayalam or English with strong citation discipline and low hallucination risk.

## Generation Modes

- Direct cached answer
- Template-composed answer from retrieved content
- Cheap-model grounded answer
- Premium fallback grounded answer

## Core Rules

- Use only retrieved textbook context and approved answer templates
- Never claim textbook certainty when retrieval confidence is low
- Keep excerpts short and avoid republishing long copyrighted passages
- Always attach chapter/page citations when available

## Answer Types

- Short answer
- Long answer
- 1 mark answer
- 2 mark answer
- 3 mark answer
- 5 mark answer
- Exam-style answer
- Simple explanation
- Malayalam explanation
- English explanation
- Step-by-step solution
- Table explanation
- Graph explanation
- Diagram explanation
- Key points
- Chapter summary
- Important questions
- Flashcards
- Quiz questions
- Teacher worksheet

## Answer Assembly Algorithm

```txt
if verified_cache_hit:
  return cached_answer

if simple_definition and high_confidence_context:
  return template_answer(context)

context = retrieve_context()
strategy = choose_generation_strategy(confidence, answer_type, user_plan, exam_mode)

draft = generate_or_compose(strategy, context)
citations = attach_citations(context)
final = run_guardrails(draft, citations, confidence)
store_cache(final)
return final
```

## Output Structure By Type

| Type | Pattern |
| --- | --- |
| 1 mark | One sentence definition or fact |
| 2 mark | Two concise points |
| 3 mark | Short paragraph or three bullet-like points |
| 5 mark | Intro + key points + conclusion |
| Step-by-step | Ordered reasoning or process steps |
| Table/Graph/Diagram | Identify + explain + likely exam angle |

## Prompt Template Variables

- `{language}`
- `{answer_type}`
- `{student_question}`
- `{retrieved_context}`
- `{chapter_title}`
- `{citation_list}`
- `{max_length_rule}`

## Base Prompt Template

```txt
You are generating a Kerala SSLC textbook-grounded answer.
Use only the provided textbook context.
If the answer is not clearly present, say that clearly and give the closest useful explanation.
Return the answer in {language}.
Follow the requested format: {answer_type}.
Keep the answer within {max_length_rule}.
Do not copy long textbook passages.
Attach citations using chapter and page references from the provided context.
Question: {student_question}
Context: {retrieved_context}
```

## Type-Specific Templates

### 1 Mark

```txt
Return exactly one crisp exam-ready sentence unless a two-part factual phrase is required.
```

### 2 Mark

```txt
Return two concise points or one short sentence plus one supporting point.
```

### 3 Mark

```txt
Return a short exam-style paragraph or three clear points suitable for a 3-mark answer.
```

### 5 Mark

```txt
Return a structured answer with a brief introduction, key explanation points, and a short concluding line.
```

### Simple Explanation

```txt
Explain in student-friendly language as if teaching a Class 10 student who is confused.
```

### Malayalam Explanation

```txt
Write fully in natural Malayalam, but keep textbook terms accurate where translation may confuse the student.
```

### English Explanation

```txt
Use clear SSLC-friendly English and avoid unnecessary advanced terminology.
```

### Step-by-Step Solution

```txt
Return ordered steps and explicitly mention if any step is inferred from textbook context rather than directly stated.
```

### Table Explanation

```txt
Explain what the table shows, the important rows or comparisons, and one likely exam takeaway.
```

### Graph Explanation

```txt
Explain the graph type, axes, trend, and likely textbook interpretation.
```

### Diagram Explanation

```txt
Name the diagram, explain important labeled parts, and mention one common exam-style question angle.
```

### Key Points

```txt
Return compact revision points, each one short and memorable.
```

### Chapter Summary

```txt
Return the chapter in concise study-note form, organized by major concepts only.
```

### Important Questions

```txt
Generate likely textbook-grounded exam questions by mixing definitions, processes, diagrams, and exercises.
```

### Flashcards

```txt
Return JSON-style Q/A flashcards with short answers and citation references.
```

### Quiz Questions

```txt
Return a balanced set of objective and short-answer questions grounded in the chapter.
```

### Teacher Worksheet

```txt
Generate a clean worksheet with mixed mark questions, chapter heading, and answer key stored separately.
```

## Hallucination Guardrails

- Reject unsupported claims not backed by retrieved context
- If citation coverage is weak, shorten the answer
- If no answer found, explicitly say so and provide a nearby explanation

## Acceptance Criteria

- All generated answers are bounded by answer-type length rules
- Responses remain textbook-grounded and citation-backed
- Not-found behavior is explicit, not evasive
