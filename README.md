# RightAnswer

Flutter app for chapter-based AI study tools with offline queueing.

## OpenAI Configuration

The app no longer reads an API key from Settings or local storage.

Provide the key at run or build time:

```bash
flutter run --dart-define=OPENAI_API_KEY=your_key_here
flutter build apk --debug --dart-define=OPENAI_API_KEY=your_key_here
flutter build apk --release --dart-define=OPENAI_API_KEY=your_key_here
```

You can also use `--dart-define-from-file` if you prefer keeping secrets in a local json file.

## Development Checks

```bash
flutter pub get
flutter analyze --no-fatal-infos
flutter test
```
