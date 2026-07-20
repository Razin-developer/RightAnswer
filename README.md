# Right Answer

Right Answer is an AI study partner for Kerala SSLC students. Students ask
questions in chat and get answers grounded in their official textbook content
(no generic web answers), can generate practice exams and important-question
sets from a chapter or subject, and get study plans that break syllabus
coverage into a schedule they can actually follow.

Answers are retrieved from the textbook (RAG: embed the question, search
Qdrant for the matching textbook passages, rerank the best few) and rendered
as rich content — Markdown, LaTeX, tables, charts, diagrams, and images —
plus clean text-to-speech, with sources cited back to the textbook.

## What's in the app

- **Chat-based Q&A** — ask a question, get a textbook-grounded answer with
  cited sources.
- **Exam generation** — generate practice exams and important-question sets
  per chapter or subject.
- **Study plans** — turn syllabus coverage into a schedule.
- **Rich answers** — math, tables, charts, diagrams, and images render
  natively in the app, with text-to-speech that reads the answer cleanly
  instead of raw Markdown/LaTeX symbols.

## Product

- **Mobile app** (`apps/app`) — the primary way students use Right Answer,
  built with Flutter.
- **Web** (`apps/web`) — landing page, feature overview, and admin
  dashboard.

## How it's built

Right Answer runs as a deployed service: a Flutter mobile app talking to a
Rust API backend (Axum), with PostgreSQL as the relational source of truth,
Qdrant for textbook vector retrieval, and Redis supporting background
workers. It's deployed on a VPS behind Nginx.

---

Contributing or setting up a local development environment: see
[`docs/development.md`](docs/development.md).
