# ICHU Mobile App

Flutter client for ICHU, SmartFarm's livestock management platform, targeting **Android and iOS only**. The current build provides the mobile foundation, not a complete IAM client.

## Current scope

- A public, explicitly labeled preview using the web app's green/gold palette, Outfit headings, Plus Jakarta Sans body text, and Andean herd imagery.
- Scrollable welcome and terms pages with safe areas, accessible controls, and large-text support.
- English by default, Latin American Spanish, and a device language preference. Changing the language updates the current page without resetting navigation.
- Validated, non-secret API configuration for subsequent integration. A valid URL is not a health check and does not enable sign-in.

**Authentication, account registration, professional profiles, ranch selection, and advisories are not implemented in this branch.** There are no simulated sessions, ranch records, or API calls. Cattle Information, IoT Assets, Operations Monitoring, Planning, Dashboard Analytics, and Subscription Plans remain outside this foundation's scope.

## Run locally

Use Flutter stable with Dart SDK `^3.12.2`. The foundation was developed with Flutter 3.44.6 / Dart 3.12.2. Android needs the Android SDK and a device or emulator; iOS needs macOS and Xcode.

```sh
flutter pub get
flutter gen-l10n
flutter run
```

The language preference is loaded before the first page. Unsupported values or inaccessible storage fall back to English, regardless of the device language. Failed writes retain the chosen language for the session and display a localized message. Preferences are for non-sensitive UI settings, never passwords or tokens.

### Build configuration

```sh
flutter run --dart-define=APP_ENV=development --dart-define=ICHU_API_BASE_URL=http://10.0.2.2:5099/api/v1
```

This prepares configuration only; this build does not contact the endpoint. `10.0.2.2` refers to the host machine from the standard Android emulator, not from a physical phone.

| Define | Values and behavior |
| --- | --- |
| `APP_ENV` | `development`, `staging`, or `production`. Defaults to `production` in product/release builds, otherwise `development`. Invalid values disable API configuration. |
| `ICHU_API_BASE_URL` | Optional HTTPS origin or an HTTPS URL ending in `/api/v1`. A single trailing slash is accepted. The API version is normalized exactly once. There is no default remote endpoint. |

Development HTTP is restricted to `localhost`, `127.0.0.1`, `[::1]`, and `10.0.2.2`. Staging and production require HTTPS. Credentials, queries, fragments, arbitrary paths, and duplicate version segments are rejected. Missing or invalid settings show a safe localized notice, without printing the supplied value. An invalid environment's internal enum fallback does **not** make the configuration usable.

Compile-time defines and `--dart-define-from-file` values are recoverable from an app binary; **they are not secret storage**. Never include passwords, private Firebase credentials, signing keys, or service-account files. Firebase mobile application registration and native identifiers must be agreed before the authentication branch. Do not copy browser configuration files into this repository.

## Architecture

```text
lib/
  main.dart                         # Platform bootstrap and dependency composition
  app.dart                          # Theme, locale, and public navigation
  core/
    config/                         # Validated deployment settings
    layout/                         # Public shell and app-wide terms
    theme/                          # Explicit web-aligned design tokens
  features/
    iam/presentation/pages/          # Public welcome preview only
  shared/
    domain/model/                   # Framework-independent language values
    domain/repositories/            # Preference persistence port
    application/services/           # Language coordination and UI notifications
    infrastructure/i18n/            # EN/ES ARBs; generated output is ignored
    infrastructure/preferences/     # Device preference adapter
    presentation/widgets/           # Reused language control
```

Dependencies point inward. Domain code is plain Dart, without Flutter, HTTP, Firebase, or JSON transport dependencies. Application services coordinate ports; presentation never accesses platform storage directly. Constructor injection is used instead of a global service locator. `ChangeNotifier` is a UI notification mechanism in the language application service, not a domain dependency.

Flutter's built-in Navigator handles the two public pages; `/terms` can open directly and returns to welcome. There are no protected routes yet. Authentication redirects and account models belong in the later IAM implementation, not speculative empty folders.

`shared_preferences` is used only for the required language preference. Flutter's `flutter_localizations`, `intl`, and `gen_l10n` provide localizations. The fonts and images are bundled and never fetched at runtime. See [assets/README.md](assets/README.md) for provenance and font licenses.

## Checks

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter test test/core/config/app_config_test.dart --dart-define=APP_ENV=production --dart-define=ICHU_API_BASE_URL=https://api.example.test/api/v1
flutter build apk --debug
```

Unit tests cover API URL validation, language fallback/persistence, failure handling, and equal EN/ES catalog keys. Widget tests cover public navigation, locale switching, truthful preview states, sensitive-input suppression, large text on phone/landscape/tablet viewports, and Flutter accessibility guidelines. Fixtures are test-only; passing widget tests does not demonstrate Firebase or live REST integration.

Native validation also needs a run on Android and an iOS build/run on macOS. Complete the Android SDK command-line tools and license setup if `flutter doctor` reports them missing. This branch does not change native identifiers, release signing, launcher icons, or store distribution. The inherited Android release configuration uses debug signing; do not distribute it as a production release.

The existing Git Flow workflow checks conventions on PRs, not Flutter builds. Build automation belongs to the later quality-gates work. No backend availability claim is made by this preview.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md). Code, comments, documentation, and Conventional Commit messages are in English. All visible interface copy is localized. Feature branches start from and target `develop`; do not commit directly to `develop` or `main`. Published feature branches must remain unmerged until the maintainer authorizes their PR and merge.

## License

Copyright (c) 2026 SmartFarm. All rights reserved. The application is proprietary; see [LICENSE.md](LICENSE.md). Bundled fonts retain their SIL Open Font License notices.
