# Admin and Teacher Dashboard

## Objective

Provide operational tooling for textbook ingestion, content quality, cost control, teacher workflows, and answer verification.

## Admin Dashboard Modules

### Textbook Management

- Upload textbook PDF
- Trigger download from official source
- View textbook versions
- Activate or archive version
- See checksum and provenance

### Ingestion Monitoring

- View ingestion jobs
- View per-stage status
- Retry failed stage
- Inspect page parse previews
- Open OCR correction editor

### Content Review

- Browse chapters, pages, and content units
- Review extracted tables, graphs, and diagrams
- Correct labels or captions
- Approve content version for student use

### Retrieval and AI Ops

- View retrieval logs
- View top failed queries
- View cache hit mix
- View provider health
- Enable or disable model providers
- Adjust route priorities
- Enable or disable exam mode

### Governance

- Manage rate limits
- Manage subscription plans
- Review user feedback
- Mark answer as verified or unsafe
- View audit logs

## Teacher Dashboard Modules

- Generate worksheet
- Generate important questions
- Verify answers
- Create question sets
- Export PDF
- View common student doubts
- Recommend corrections

## Role Permissions

| Action | Admin | Teacher | Student |
| --- | --- | --- | --- |
| Upload textbook | Yes | No | No |
| Approve textbook version | Yes | No | No |
| Verify answer | Yes | Yes | No |
| Generate worksheet | Yes | Yes | No |
| View provider cost dashboard | Yes | No | No |
| View student-facing revision pages | Yes | Yes | Yes |

## Key Pages

- Admin overview
- Textbook library
- Ingestion job detail
- Page review editor
- Content unit inspector
- Provider control panel
- Exam mode settings
- Feedback moderation queue
- Teacher worksheet builder
- Teacher verified-answer queue

## Acceptance Criteria

- Admin can fully ingest and publish a textbook without database access
- Teacher can verify answers and generate worksheets without using hidden internal tools
