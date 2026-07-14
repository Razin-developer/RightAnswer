# Architecture Notes

This document is a concise technical map of the current RightAnswer codebase.

## Layers

The app mostly follows a simple Flutter local-first layering style:

1. `screens/`
   User-facing feature flows and local UI state.
2. `services/`
   AI requests, retrieval, notifications, background processing, speech, and connectivity.
3. `repositories/`
   CRUD wrappers around `sqflite`.
4. `models/`
   App entities passed between repositories, services, and UI.
5. `database/`
   Central schema and migration setup.
6. `config/`
   Build-time runtime configuration.

## Main App Boot Sequence

`lib/main.dart` currently does the following:

1. Ensures Flutter bindings are initialized.
2. Creates a `SettingsRepository`.
3. Deletes any legacy stored OpenAI key.
4. Loads theme mode from local settings.
5. Initializes local notifications.
6. Initializes `Workmanager` background tasks.
7. Initializes the queue service.
8. Registers reconnect behavior through `ConnectivityService`.
9. Restores daily reminders from settings.
10. Starts `RightAnswerApp`.

## Navigation Architecture

Root:

- `RightAnswerApp`
- `MainScreen`

Tab shell:

- `ChatScreen`
- `ExamScreen`
- `HomeScreen`

Detail screens:

- `SettingsScreen`
- `QueueScreen`
- `SavedOutputsScreen`
- `SubjectScreen`
- `ChapterScreen`
- `ResultScreen`

Notifications navigate through a global `navigatorKey`.

## AI Service Split

The codebase now has three separate AI-facing service paths:

### `OpenAIService`

Purpose:

- Chapter-based structured generation
- Embedding generation
- Usage logging for study-tool outputs

Used by:

- `ChapterScreen`
- `QueueService`
- background queue processing

### `ChatAIService`

Purpose:

- Conversational tutoring
- Optional image understanding
- Context-aware chat over selected chapters
- Chat name generation
- Daily chat token limit enforcement

Used by:

- `ChatScreen`

### `ExamAIService`

Purpose:

- Exam generation from scratch
- Exam editing / rewriting
- Context-aware exam prompts
- Exam title generation

Used by:

- `ExamScreen`

## Retrieval Pattern

`RetrievalService` is the common bridge between stored chapter content and AI calls.

Core behavior:

- chunk and store raw chapter content
- estimate tokens for fallback accounting
- semantic-ish retrieval from stored chunks per chapter
- feed selected chunk text into AI prompts

This retrieval path is shared by:

- `OpenAIService`
- `ChatAIService`
- `ExamAIService`
- `QueueService`

## Local-First Persistence Pattern

Every major feature has a repository boundary:

- `SubjectRepository`
- `ChapterRepository`
- `ChunkRepository`
- `SavedOutputRepository`
- `QueueRepository`
- `UsageLogRepository`
- `SettingsRepository`
- `ChatRepository`
- `ChatMessageRepository`
- `ExamRepository`
- `ExamQuestionRepository`
- `ExamMessageRepository`

The repositories are thin wrappers. Domain logic mostly lives in screens and services rather than in a separate controller/use-case layer.

## Background / Queue Architecture

Foreground path:

- `ChapterScreen` enqueues offline study-tool requests
- `QueueService` processes them once online

Background path:

- `BackgroundService` registers a periodic `Workmanager` task
- the task reconstructs repositories/services inside the background isolate
- it calls `processQueueItems(...)`

Queue output:

- completed items are saved into `saved_outputs`
- failed items store a user-friendly error message

## UX Utility Services

### `ConnectivityService`

- online/offline state
- reconnect callbacks
- used by queue + UI banners

### `NotificationService`

- generation completion notifications
- queue notifications
- reminder scheduling
- notification tap routing

### `SpeechService`

- microphone / speech-to-text
- used by chat and exam flows

### `TtsService`

- text-to-speech playback
- used in chat

### `AppFeedback`

- centralized snackbars/toasts
- centralized error dialog presentation

### `AppException`

- typed app-level error model
- configuration, network, auth, rate limit, service, validation, unknown

## Notable Current Design Choices

- The app is local-first and SQLite-backed rather than server-backed.
- Business logic is screen-heavy, especially in `ChatScreen` and `ExamScreen`.
- Chat and exams are now large feature modules with substantial in-file UI logic.
- The original subject/chapter tool flow remains the only area with offline queueing.
- OpenAI configuration is build-time only, not user-entered.

## Likely Future Refactor Targets

If the codebase keeps growing, the most obvious extraction points are:

- split `chat_screen.dart` into smaller widgets/files
- split `exam_screen.dart` into smaller widgets/files
- introduce feature-specific controllers or notifiers
- centralize shared context-selection UI
- centralize OpenAI request plumbing shared across AI services
