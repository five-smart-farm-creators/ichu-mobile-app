# ICHU Mobile

Flutter app for ICHU field work on **Android and iOS**.

## What it does
- Firebase sign-in and supported account registration.
- Explicit selection of a server-authorized ranch.
- Read-only animal profiles, latest telemetry summaries, paginated cloud alerts, and synchronized Edge Gateway alert details.
- Notifications for new pending cloud alerts while the app is open.
- English and Latin American Spanish, with accessible, adaptable layouts.

## Run
Requires Flutter 3.44.6 / Dart 3.12.2 or compatible SDKs.

```sh
flutter pub get
flutter gen-l10n
flutter run --dart-define=APP_ENV=development --dart-define=ICHU_API_BASE_URL=http://10.0.2.2:5099/api/v1
```

Use approved native Firebase settings to enable authentication. The API URL is optional but required for backend data; use HTTPS outside local development. Never put secrets in `--dart-define`.

## Run against production

Firebase issues a different API key and app ID per platform, so keep one copy of the template per platform and replace its `REPLACE_WITH_...` values. The copies are ignored by git:

```sh
cp config/production.example.json config/android.json
cp config/production.example.json config/ios.json
flutter run --dart-define-from-file=config/android.json
```

The template sets `APP_ENV=production` and the Render API URL. Release APKs for Firebase App Distribution use the same file:

```sh
flutter build apk --release --dart-define-from-file=config/android.json
```

Release builds are still signed with the debug key (see the TODO in `android/app/build.gradle.kts`); add a release signing configuration before distributing outside the team.

## Test builds

The `Test builds` workflow builds a release APK and an unsigned IPA on every pull request (or on demand) with the production config stored in the `ICHU_ANDROID_CONFIG` and `ICHU_IOS_CONFIG` repository secrets. Download them from the run's artifacts. The APK installs directly; the IPA must be re-signed with a tester's Apple ID, and a free Apple ID install expires after 7 days.

## Android and iOS

- Firebase needs one Android app with package `com.smartfarm.ichu` and one iOS app with bundle ID `com.smartfarm.ichu` in the Firebase project. Put their app IDs in the `--dart-define-from-file` JSON as `ICHU_FIREBASE_ANDROID_APP_ID` and `ICHU_FIREBASE_IOS_APP_ID`; the iOS bundle ID goes in `ICHU_FIREBASE_IOS_BUNDLE_ID`.
- iOS builds require macOS with Xcode. Installing on physical iPhones requires an Apple developer account, distributed through TestFlight or Firebase App Distribution with ad-hoc signing.

## Scope
The backend authorizes every request; selecting a ranch does not grant access. Monitoring is read-only; the only writes are field-record synchronization and cloud alert acknowledgements. The app does not provide live tracking, direct Edge access, or notifications while it is closed.

### Alert notifications

While the app is open and a ranch is selected, the app checks the first page of pending cloud alerts every 30 seconds and announces each new alert once. The title reflects the severity, and the body names the alert type and the reporting device ID, because the alert record carries no ear tag. Tapping a notification opens the ranch alerts page. Android 13+ asks for notification permission (`POST_NOTIFICATIONS`); iOS asks for alert and sound permission the first time a ranch is selected. Alerts that are already pending when a ranch is selected are recorded silently, so an old backlog does not flood the phone.

Limitation: notifications arrive only while the app is in the foreground. Background and closed-app delivery requires Firebase Cloud Messaging and a backend change, which is future work. A tap that launches a closed app shows the normal start page.

### Offline field-record synchronization

Field records are captured locally first. In **Field records**, a manage-authorized account can explicitly synchronize the selected ranch's pending queue while connected. Capture remains available during synchronization and after network failures; new captures wait for the next explicit attempt. There is no background worker or automatic retry.

- Transport: `POST /api/v1/mobile-sync/batch`, using the current IAM token and an `operations` array. The payload contains each record's original `operationId`, `cattleId`, PascalCase `type`, UTC `occurredAt`, and optional observation/sire reference. Account/ranch authorization is enforced before sending; the backend derives the ranch from each animal. Cached cattle choices are never uploaded.
- The mobile client sends chunks of up to 50 entries (below the backend's default maximum of 500). The response must contain exactly one `LivestockOperation` decision for every submitted operation, with no unknown, missing, or duplicate identifiers.
- Only `Accepted` and `Duplicate` decisions remove records from the local pending queue, after the updated queue is successfully persisted. `Rejected` and `Conflict` records remain unchanged, with their server diagnostics stored locally. The UI shows localized review notices rather than rendering untrusted server diagnostics. This feature does not edit or replace conflicting operations.
- Retries reuse identical operation identifiers and event content. Lost responses, invalid responses, or failed local reconciliation leave unconfirmed records pending; the server's idempotency handles previously accepted operations on retry. Earlier successfully reconciled chunks are not resent after a later chunk fails.
- A changed/expired session or ranch context fences late responses and prevents subsequent chunks. Pending queues and review decisions remain isolated by account/ranch across logout and reopening the app. Existing version-1 queues remain readable; an optional `syncIssues` field stores review decisions without replacing cattle choices or new captures.

Contract sources inspected in `ichu-web-service` at `a0ac5fe` (under `FiveSmartFarmCreators.Ichu.Platform/OperationsMonitoring/`):

- `Interfaces/Rest/LivestockOperationsController.cs` and the mobile batch resources/assemblers define the route, payload, and per-entry result shape.
- `Application/Internal/CommandServices/LivestockOperationCommandService.cs`, `Application/Internal/OperationsMonitoringOptions.cs`, and `Application/Internal/OutboundServices/IamOperationsMonitoringAccessControl.cs` define idempotency, partial processing, batch limits, and the `Manage` field-event permission.
- `Domain/Model/Aggregates/LivestockOperation.cs` defines duplicate-content matching; `tests/FiveSmartFarmCreators.Ichu.Platform.IntegrationTests/OperationsMonitoring/ReproductiveEventsApiTests.cs` in the backend repository provides current-client batch examples.

Verification includes unit and widget tests for mixed batches, uncertain delivery, storage failures, authorization/context changes, concurrent capture, and EN/ES narrow/landscape layouts at 200% text scale. These tests use synthetic HTTP responses, not a live backend. Live-service and physical-device verification remain outstanding; no Android/iOS native configuration is changed by this feature. Consolidating the changelog is deferred to the integration owner while the feature branches are developed in parallel.

## Checks

```sh
flutter analyze
flutter test
```
