# ICHU Mobile

Flutter app for ICHU field work on **Android and iOS**.

## What it does
- Firebase sign-in and supported account registration.
- Explicit selection of a server-authorized ranch.
- Read-only animal profiles, latest telemetry summaries, and paginated cloud alerts.
- English and Latin American Spanish, with accessible, adaptable layouts.

## Run
Requires Flutter 3.44.6 / Dart 3.12.2 or compatible SDKs.

```sh
flutter pub get
flutter gen-l10n
flutter run --dart-define=APP_ENV=development --dart-define=ICHU_API_BASE_URL=http://10.0.2.2:5099/api/v1
```

Use approved native Firebase settings to enable authentication. The API URL is optional but required for backend data; use HTTPS outside local development. Never put secrets in `--dart-define`.

## Scope
The backend authorizes every request; selecting a ranch does not grant access. Monitoring and alerts are read-only snapshots. The app does not provide live tracking, telemetry history, direct Edge access, offline sync, or alert notifications/actions.

## Checks

```sh
flutter analyze
flutter test
```
