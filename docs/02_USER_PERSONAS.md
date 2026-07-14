# User Personas

## Overview

Right Answer serves multiple user types, but the product must be optimized first for the daily study workflow of Kerala SSLC students. Other personas should support that core experience.

## Persona 1: Student - Amina

| Attribute | Details |
| --- | --- |
| Age | 15 |
| Class | Kerala SSLC Class 10 |
| Language | Malayalam at home, English in some subjects |
| Device | Android phone |
| Usage Time | After school, tuition, late-night revision |
| Goal | Understand textbook answers and score better in exams |

### Needs

- Fast answers without long chat
- 1 mark, 3 mark, and 5 mark formats
- Malayalam explanation for difficult English textbook topics
- Chapter-wise revision before exams
- Confidence that answers match textbook expectations

### Pain Points

- Generic AI answers are too long
- Notes from different teachers are inconsistent
- Hard to understand diagrams and graphs
- Limited mobile data and low patience for slow apps

### Product Implications

- Mobile-first interface
- Big answer format buttons
- Cache-heavy fast paths
- Simple wording and chapter/page citation

## Persona 2: Parent - Suresh

| Attribute | Details |
| --- | --- |
| Age | 42 |
| Role | Parent funding student prep |
| Goal | Reliable learning support without requiring subject expertise |

### Needs

- Trustworthy study tool
- Clear subscription value
- Progress visibility in later phases

### Product Implications

- Clear textbook-grounded positioning
- Easy subscription page
- Minimal complexity in onboarding

## Persona 3: Tuition Teacher - Meera

| Attribute | Details |
| --- | --- |
| Age | 31 |
| Role | Tuition teacher |
| Goal | Save time preparing worksheets and revision material |

### Needs

- Generate important questions by chapter
- Create worksheets in exam format
- Verify or correct AI answers
- See common student doubts

### Product Implications

- Teacher dashboard
- Verification workflow
- Exportable worksheet generation

## Persona 4: Tuition Center Owner - Faisal

| Attribute | Details |
| --- | --- |
| Role | Runs batches for multiple SSLC students |
| Goal | Use one system for many students with priority access during exam season |

### Needs

- Higher concurrency
- Staff accounts later
- Central billing
- Priority queue

### Product Implications

- Tuition Center plan
- Queue priority controls
- Higher rate limits on cached and worksheet flows

## Persona 5: Admin / Content Operator - Anjali

| Attribute | Details |
| --- | --- |
| Role | Internal operator |
| Goal | Keep textbook corpus accurate, complete, and updated |

### Needs

- Official source tracking
- Upload and download workflow
- OCR correction
- Embedding rebuild tools
- Retrieval inspection

### Product Implications

- Strong admin dashboard
- Job queues and audit trails
- Content approval lifecycle

## User Priorities by Persona

| Persona | Highest Priority |
| --- | --- |
| Student | Fast, simple, correct answers |
| Parent | Trust and value |
| Teacher | Time-saving content generation |
| Tuition Center | Scale and priority |
| Admin | Data quality and system control |

## Journey Risks

- Student asks vague question with no subject selected
- Malayalam transliterated question is ambiguous
- Textbook PDF parse quality is poor
- High traffic causes slow live generation
- Teacher uses generated answer without checking weak citations

## Persona-Level Acceptance Criteria

- Students can get useful answers in under a few taps
- Teachers can verify and reuse strong answers
- Admin can trace every answer back to textbook source units
