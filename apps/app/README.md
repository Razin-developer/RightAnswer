# RightAnswer

Flutter app for chapter-based AI study tools with offline queueing.

## Project Docs

- `docs/APP_OVERVIEW.md`: current product surfaces and runtime behavior
- `docs/ARCHITECTURE.md`: code structure, service split, and app boot flow
- `docs/DATA_MODEL.md`: local SQLite schema and persistence notes

## Backend Configuration

The app does not contain AI provider keys. It talks to the Right Answer backend,
which owns provider routing, caching, embeddings, and reranking.

Provide the backend URL at run or build time:

```bash
flutter run --dart-define=API_URL=https://your-api.example.com
flutter build apk --debug --dart-define=API_URL=https://your-api.example.com
flutter build apk --release --dart-define=API_URL=https://your-api.example.com
```

You can also use `--dart-define-from-file` if you prefer a local config file.

## Development Checks

```bash
flutter pub get
flutter analyze --no-fatal-infos
flutter test
```
