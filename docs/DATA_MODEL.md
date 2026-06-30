# Data Model

This document summarizes the current local database schema defined in `lib/database/database_helper.dart`.

## Database Version

Current database version: `5`

Migration history:

- `v2`: queue table
- `v3`: chat tables
- `v4`: `chapters.rawContent`
- `v5`: exam tables

## Core Study Tables

### `subjects`

Stores top-level study subjects.

Columns:

- `id`
- `name`
- `createdAt`

### `chapters`

Stores subject chapters and raw pasted content.

Columns:

- `id`
- `subjectId`
- `title`
- `className`
- `rawContent`
- `createdAt`

Notes:

- `rawContent` was added later through migration.
- child records cascade through related tables via chapter IDs in feature flows.

### `chunks`

Stores processed chapter chunks used for retrieval and generation.

Columns:

- `id`
- `chapterId`
- `chunkIndex`
- `text`
- `embeddingJson`
- `page`
- `createdAt`

### `saved_outputs`

Stores generated study-tool results.

Columns:

- `id`
- `subjectId`
- `chapterId`
- `toolType`
- `question`
- `answer`
- `language`
- `usedChunkIds`
- `createdAt`

### `usage_logs`

Stores token/cost tracking for AI usage.

Columns:

- `id`
- `toolType`
- `inputTokensEstimate`
- `outputTokensEstimate`
- `estimatedCost`
- `createdAt`

### `settings`

Stores persistent user preferences and runtime knobs.

Examples:

- theme mode
- default language
- grade level
- tone
- output length
- token pricing
- chat daily token limit
- notification settings
- reminder time
- selected model

## Queue Table

### `request_queue`

Stores deferred chapter-tool requests for offline processing.

Columns:

- `id`
- `chapterId`
- `subjectId`
- `toolType`
- `question`
- `language`
- `gradeLevel`
- `tone`
- `outputLength`
- `status`
- `errorMessage`
- `createdAt`

Statuses used in code:

- `pending`
- `processing`
- `done`
- `failed`

## Chat Tables

### `chats`

Stores chat sessions.

Columns:

- `id`
- `name`
- `subjectId`
- `subjectName`
- `chapterIds`
- `chapterNames`
- `isTemporary`
- `createdAt`
- `updatedAt`

Notes:

- chapter and subject context are denormalized for faster UI loading
- temporary chats are supported in the UI, though they may skip persistence depending on flow

### `chat_messages`

Stores messages inside chats.

Columns:

- `id`
- `chatId`
- `role`
- `content`
- `imagePath`
- `responseLength`
- `reasoningLevel`
- `tokenCount`
- `cost`
- `createdAt`

## Exam Tables

### `exams`

Stores exam metadata.

Columns:

- `id`
- `name`
- `type`
- `subjectId`
- `subjectName`
- `chapterIds`
- `chapterNames`
- `questionCount`
- `timeLimit`
- `difficulty`
- `mcqOptionCount`
- `createdAt`
- `updatedAt`

### `exam_questions`

Stores the questions for each exam.

Columns:

- `id`
- `examId`
- `questionIndex`
- `type`
- `question`
- `options`
- `correctAnswer`
- `explanation`
- `userAnswer`

### `exam_messages`

Stores the conversational edit history for an exam.

Columns:

- `id`
- `examId`
- `role`
- `content`
- `imagePath`
- `createdAt`

## Clear-All Behavior

`DatabaseHelper.clearAllData()` currently clears:

- exam messages
- exam questions
- exams
- chat messages
- chats
- request queue
- chunks
- saved outputs
- usage logs
- chapters
- subjects

Settings are intentionally preserved.
