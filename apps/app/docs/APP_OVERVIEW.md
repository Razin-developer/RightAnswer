# RightAnswer Overview

This document reflects the current app structure in the repository as of June 30, 2026.

## Product Shape

RightAnswer is now a multi-surface study app with three primary tabs:

- `Chat`: free-form AI tutoring with optional chapter context, image input, speech-to-text, and text-to-speech.
- `Exams`: AI-generated exams with editable questions, exam history, context-aware generation, and image-assisted creation/editing.
- `Subjects`: the original chapter-based study workflow for storing study material, chunking chapter content, and generating structured outputs.

The root shell is `MainScreen`, which uses an `IndexedStack` with:

- `ChatScreen`
- `ExamScreen`
- `HomeScreen`

## Current Navigation

Entry flow:

1. `main.dart` initializes theme, notifications, background queue processing, connectivity listeners, and reminders.
2. `RightAnswerApp` launches `MainScreen`.
3. `MainScreen` provides bottom navigation between chat, exams, and subjects.

Secondary screens:

- `SettingsScreen`
- `SavedOutputsScreen`
- `QueueScreen`
- `SubjectScreen`
- `ChapterScreen`
- `ResultScreen`

## Feature Summary

### 1. Chat

Chat is now a first-class workspace rather than a simple single-thread prompt box.

Capabilities:

- Persistent chats stored locally
- Temporary chats that are not saved
- Optional context binding to a subject and selected chapters
- Image input using camera/gallery
- Speech-to-text input
- Text-to-speech playback
- Regenerate assistant replies
- Auto-generated chat titles
- Daily output token limit from settings

Primary files:

- `lib/screens/chat_screen.dart`
- `lib/services/chat_ai_service.dart`
- `lib/repositories/chat_repository.dart`
- `lib/repositories/chat_message_repository.dart`

### 2. Exams

Exams have evolved into a full create-and-edit workflow.

Capabilities:

- Generate exams from prompt, optional image, and optional chapter context
- Configure question count, difficulty, time limit, and MCQ option count
- Support for `mcq`, `true_false`, `fill_blank`, `short_answer`, `long_answer`, and `mixed`
- Persist exam metadata, questions, and edit history
- Edit existing exams through conversational prompts
- Inline question editing and deletion
- Exam renaming and deletion
- Voice input for create/edit prompts

Primary files:

- `lib/screens/exam_screen.dart`
- `lib/services/exam_ai_service.dart`
- `lib/repositories/exam_repository.dart`
- `lib/repositories/exam_question_repository.dart`
- `lib/repositories/exam_message_repository.dart`

### 3. Subjects / Chapter Tools

This is the original structured study-material pipeline and still powers saved outputs plus the offline queue.

Capabilities:

- Create subjects and chapters
- Paste raw chapter content
- Split content into chunks
- Optionally generate embeddings when the backend API is available
- Generate structured study outputs from chapter context
- Queue requests offline
- Store completed outputs for later review

Primary files:

- `lib/screens/home_screen.dart`
- `lib/screens/subject_screen.dart`
- `lib/screens/chapter_screen.dart`
- `lib/screens/result_screen.dart`
- `lib/services/backend_generation_service.dart`
- `lib/services/queue_service.dart`
- `lib/services/retrieval_service.dart`

## Runtime Configuration

Backend access is build-time configured through:

- `--dart-define=API_URL=...`

Code source:

- `lib/config/app_config.dart`

AI provider keys live only on the backend.

## Offline / Background Behavior

Only the subject/chapter generation flow currently supports queued offline generation.

Behavior:

- If the user is offline during a chapter tool action, the request is stored in `request_queue`.
- `ConnectivityService` triggers processing when the device comes back online.
- `Workmanager` periodically checks pending queue items in the background.
- Successful queue processing stores results in `saved_outputs`.

## Local Persistence

The app is heavily local-first and uses `sqflite` for persistence.

Stored data includes:

- subjects
- chapters
- chunks
- saved outputs
- usage logs
- settings
- request queue
- chats
- chat messages
- exams
- exam questions
- exam edit messages

For schema details, see `docs/DATA_MODEL.md`.
