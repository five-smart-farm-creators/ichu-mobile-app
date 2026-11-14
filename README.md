# ICHU Mobile

Flutter app for ICHU field work on **Android and iOS**.

## What it does
- Firebase sign-in and supported account registration.
- Explicit selection of a server-authorized ranch.
- Read-only animal profiles, latest telemetry summaries, paginated cloud alerts, and synchronized Edge Gateway alert details.
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
The backend authorizes every request; selecting a ranch does not grant access. Monitoring and alerts are read-only snapshots. The app does not provide live tracking, telemetry history, direct Edge access, or alert notifications/actions.

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
