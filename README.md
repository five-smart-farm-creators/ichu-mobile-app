# ICHU Mobile App

Flutter client for ICHU, SmartFarm's livestock management platform, targeting **Android and iOS only**. It implements existing-account IAM authentication on the shared mobile foundation.

The completed backend is the functional source of truth for API contracts and business rules. The unfinished Web App supplies visual brand references only; mobile delivery proceeds by bounded context and verified backend use cases, not by copying unfinished browser workflows.

## Current scope

- Sign-in and password recovery through the native Firebase Authentication SDK, with the web app's palette, Outfit headings, Plus Jakarta Sans body text, and Andean herd imagery.
- Session restoration and a guarded account summary that opens only after verified identity and sequential IAM account/access validation.
- Scrollable sign-in, recovery, account, and terms pages with safe areas, accessible controls, and large-text/keyboard support.
- English by default, Latin American Spanish, and a device language preference. Changing the language updates the current page without resetting navigation.
- Validated, non-secret API and native Firebase settings. Missing settings leave sign-in unavailable without initializing a fabricated Firebase project or loading sample accounts.

**Account registration, profile editing, ranch selection, and advisory management remain separate work.** There are no simulated production sessions or ranch records. Cattle Information, IoT Assets, Operations Monitoring, Planning, Dashboard Analytics, and Subscription Plans remain outside this branch's scope.

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

`10.0.2.2` refers to the host machine from the standard Android emulator, not from a physical phone. API configuration alone does not enable sign-in: approved native Firebase options are also required.

| Define | Values and behavior |
| --- | --- |
| `APP_ENV` | `development`, `staging`, or `production`. Defaults to `production` in product/release builds, otherwise `development`. Invalid values disable API configuration. |
| `ICHU_API_BASE_URL` | Optional HTTPS origin or an HTTPS URL ending in `/api/v1`. A single trailing slash is accepted. The API version is normalized exactly once. There is no default remote endpoint. |

Development HTTP is restricted to `localhost`, `127.0.0.1`, `[::1]`, and `10.0.2.2`. Staging and production require HTTPS. Credentials, queries, fragments, arbitrary paths, and duplicate version segments are rejected. Missing or invalid settings show a safe localized notice, without printing the supplied value. An invalid environment's internal enum fallback does **not** make the configuration usable.

Compile-time defines and `--dart-define-from-file` values are recoverable from an app binary; **they are not secret storage**. Never include passwords, private Firebase credentials, signing keys, or service-account files. Do not copy browser configuration files into this repository.

### Native Firebase configuration

Copy `config.example.json` to the ignored `config.local.json` and populate only approved public Firebase client settings. Never commit the local file or print its values in diagnostics.

```sh
flutter run --dart-define-from-file=config.local.json
```

| Define | Purpose |
| --- | --- |
| `ICHU_FIREBASE_API_KEY` | Public Firebase client API key, with project restrictions configured by the owner. |
| `ICHU_FIREBASE_PROJECT_ID` | Same Firebase project trusted by the ICHU API. |
| `ICHU_FIREBASE_MESSAGING_SENDER_ID` | Firebase project sender/project number. This does not enable notifications. |
| `ICHU_FIREBASE_ANDROID_APP_ID` | Approved Firebase Android app ID, associated with the actual Android application ID. |
| `ICHU_FIREBASE_IOS_APP_ID` | Approved Firebase iOS app ID. |
| `ICHU_FIREBASE_IOS_BUNDLE_ID` | Approved iOS bundle identifier matching the installed target and Firebase registration. |

Options are passed programmatically to a named Firebase app; no generated service-account credentials, `google-services.json`, or `GoogleService-Info.plist` are needed by this implementation. Unsupported platforms and incomplete/malformed native settings never initialize a Firebase client. Existing Firebase apps must match the requested project/options before reuse.

Firebase app IDs use the native `1:<sender-id>:android:<app-hash>` or `1:<sender-id>:ios:<app-hash>` format. They are not Android package names or iOS bundle identifiers; use the actual values issued by the Firebase project owner.

**External setup is still required.** This branch does not create Firebase registrations, enable email/password providers, change package/bundle identifiers, configure project restrictions, or supply test accounts. Android/iOS identifiers are inherited template values until the owner approves replacements. Register the actual native IDs in the correct project before validating live authentication. A successful APK build or fixture test is not evidence of live Firebase/API integration.

### Session and transport behavior

- Passwords are sent only to Firebase Authentication, never `POST /accounts/sessions` or the ICHU API. The backend accepts the native Firebase ID token for protected resources. This supported bearer flow does **not** execute `/accounts/sessions`' attempt auditing, failed-attempt counter, or successful-attempt reset; it is not claimed equivalent to that separate backend sign-in use case. Adopting backend-audited credential sign-in would require an explicit session/token design, not a second duplicate password call.
- The app reloads the Firebase user and refreshes verification claims, requires a verified email, then calls `GET /api/v1/accounts/me` **before** `GET /api/v1/accounts/me/ranches`. This avoids concurrent first-use activation of pending backend accounts.
- A session requires the same current UID, a verified email matching the normalized account email, and successful authenticated responses from both account/access endpoints. The backend decides whether verification and time-based blocks permit access; zero authorized ranches is a valid signed-in state. Revoked/failed validation clears the account snapshot.
- Generation checks discard late responses after user changes/sign-out. Account routes redirect to login unless the application session is fully validated; sign-out removes protected navigation access immediately.
- An injected `AuthenticationLifecycle` is shared by the session service and HTTP client. It retains pending native cleanup when a session service is disposed; replacement services must reuse that same lifecycle. If logout supersedes a pending native sign-in, the form remains busy until that request settles and its late identity is signed out. A new native sign-in cannot overlap the discarded request or its cleanup.
- If native sign-out fails, the lifecycle hides that identity, keeps new sign-in blocked, and preserves the sign-out retry requirement across replacement services. Local access remains closed, but native persistence cannot be claimed cleared until a retry succeeds. Cleanup continues even if lifecycle UI notifications have been disposed; process termination cannot guarantee completion of an in-flight native operation.
- Tokens are obtained from the SDK for each API request and never manually cached in preferences. The SDK handles expired-token refresh. A 401 is not automatically replayed: a blocked/missing account must not be mistaken for token expiry.
- The authenticated client accepts only relative API resource paths under the configured origin and `/api/v1` root. Redirect following is disabled to prevent bearer forwarding to another destination. Requests have a timeout and bounded response handling; server errors become safe, localized categories rather than raw response titles/exceptions.
- Password reset has a generic outcome that does not reveal whether an address exists. Password controllers clear after an attempt, backgrounding, or leaving the form; visibility resets to hidden. Controllers are disposed with the page. Firebase manages native session persistence; application preferences contain only the language.
- Resuming a signed-in app or manually checking the session revalidates access. A service outage never unlocks cached account data. As in the web flow, failed validation may require signing in again.

The backend's `UserAccount.IsActive(now)` evaluates the block expiry independently of its persisted status label. After expiry, both protected endpoints can return success while `AccountResource.status` still reads `TemporarilyBlocked`. Mobile respects those successful server decisions rather than applying the unfinished web client's literal-`Active` gate or inventing a local clock-based unlock. The account view reports server-validated access, not a fabricated `Active` status. An active block's 401, or rejection by either endpoint, always keeps the app unauthorized.

## Architecture

```text
lib/
  main.dart                         # Platform bootstrap and dependency composition
  app.dart                          # Theme, locale, guarded navigation, lifecycle
  core/
    config/                         # Validated deployment settings
    layout/                         # Public shell and app-wide terms
    theme/                          # Explicit web-aligned design tokens
  features/
    iam/
      domain/                       # Identity, account, permissions, errors, ports
      application/services/         # Session/recovery coordination
      infrastructure/               # Native Firebase and authenticated REST adapters
      presentation/                 # Login, recovery, guarded account summary
  shared/
    domain/model/                   # Framework-independent language values
    domain/repositories/            # Preference persistence port
    application/services/           # Language coordination and UI notifications
    infrastructure/i18n/            # EN/ES ARBs; generated output is ignored
    infrastructure/preferences/     # Device preference adapter
    presentation/widgets/           # Reused language control
```

Dependencies point inward. Domain code is plain Dart, without Flutter, HTTP, Firebase, or JSON transport dependencies. Application services coordinate ports; presentation never accesses platform storage directly. Constructor injection is used instead of a global service locator. `ChangeNotifier` supplies notifications in the language and session application services, not in domain models.

`go_router` owns the stable route graph: `/login`, `/recover`, `/terms`, and protected `/account`; `/` selects login or account. Direct public routes have reliable back behavior. External return destinations are ignored. Locale changes preserve the router, and the session service drives authorization redirects. App bootstrap composes the SDK, HTTP transport, and domain ports; widgets do not access adapters directly.

`shared_preferences` is used only for the language preference. Flutter's `flutter_localizations`, `intl`, and `gen_l10n` provide localizations. `firebase_core` / `firebase_auth` provide native identity, `http` provides the bounded REST transport, and `go_router` provides guarded navigation. The fonts and images are bundled and never fetched at runtime. See [assets/README.md](assets/README.md) for provenance and font licenses.

## Checks

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter test test/core/config/app_config_test.dart --dart-define=APP_ENV=production --dart-define=ICHU_API_BASE_URL=https://api.example.test/api/v1
flutter build apk --debug
```

Unit tests cover configuration, identity/account contracts, session transitions and stale-response races, REST token boundaries and parsing, recovery, language preferences, and equal EN/ES catalog keys. Widget tests cover guarded routes, form/error behavior, password clearing, locale changes, large text, and accessibility. Fixtures are explicitly test-only; passing tests does not demonstrate Firebase or live REST integration.

Native validation also needs a run on Android and an iOS build/run on macOS. Complete the Android SDK command-line tools and license setup if `flutter doctor` reports them missing. Android declares Internet access for Firebase/API traffic; local cleartext API access is debug-only, while production/staging endpoints require HTTPS. No global iOS ATS exception is introduced; use an approved HTTPS API on iOS. Native identifiers, release signing, launcher icons, and store distribution are not changed. The inherited Android release configuration uses debug signing; do not distribute it as a production release.

The current Firebase plugins require iOS **15.0 or later**, so the Xcode deployment target is raised from the starter's 13.0. Android Firebase plugins require API 24; the application continues to use Flutter's supported minimum SDK (verify it when upgrading Flutter). The iOS configuration change has not been validated with Xcode on this Windows host.

The current Firebase Android plugins emit Flutter's warning about applying the Kotlin Gradle Plugin rather than using built-in Kotlin. The debug APK builds with Flutter 3.44.6, but recheck plugin compatibility before upgrading Flutter. Do not patch downloaded plugin/cache files or suppress the warning as a substitute for an upstream-compatible upgrade.

The existing Git Flow workflow checks conventions on PRs, not Flutter builds. Build automation belongs to the later quality-gates work. Live service availability must be checked separately from local tests.

### Authentication branch verification

Verified on Windows with Flutter 3.44.6 / Dart 3.12.2 on 2026-11-11:

- Formatting and static analysis pass; the full suite has **138 passing tests**. A separate run of the 25 API configuration tests also passes with production defines.
- The Android debug APK builds and runs on an Android API 37 emulator. Native checks cover the unavailable-configuration state, public recovery, terms/back navigation, EN/ES switching, and language persistence after force-stop/relaunch.
- Session/SDK/HTTP tests use synthetic fixtures, including cleanup across service disposal/replacement, latched sign-out retries, and backend-authorized historical block status. They do not demonstrate real Firebase sign-in, password-reset delivery, or authenticated REST responses.
- Live integration remains blocked: the Render `/health` endpoint returns **503** with a `Service Suspended` page, and approved native Firebase options/registrations have not been supplied. No project registrations or native identifiers were changed.
- iOS build/run remains unverified because this host does not provide macOS/Xcode. This debug build is not a signed store release.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md). Code, comments, documentation, and Conventional Commit messages are in English. All visible interface copy is localized. Feature branches start from and target `develop`; do not commit directly to `develop` or `main`. Published feature branches must remain unmerged until the maintainer authorizes their PR and merge.

## License

Copyright (c) 2026 SmartFarm. All rights reserved. The application is proprietary; see [LICENSE.md](LICENSE.md). Bundled fonts retain their SIL Open Font License notices.
