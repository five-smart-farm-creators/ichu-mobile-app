# ICHU Mobile App

Flutter client for ICHU, SmartFarm's livestock management platform, targeting **Android and iOS only**. It implements IAM authentication, registration, read-only professional profiles, authorized ranch selection, animal information, latest monitoring summaries, and read-only ranch alerts on the shared mobile foundation.

The implemented backend is the functional source of truth for API contracts and business rules. The report defines mobile product scope; the unfinished Web App supplies visual brand references only. Mobile delivery selects field-oriented use cases, not every backend module or browser workflow. Proposed report endpoints must be checked against implemented contracts before use.

## Current scope

- Sign-in and password recovery through the native Firebase Authentication SDK, with the web app's palette, Outfit headings, Plus Jakarta Sans body text, and Andean herd imagery.
- Session restoration and a guarded account summary that opens only after verified identity and sequential IAM account/access validation.
- Account registration for the backend-supported veterinarian and ranch-manager roles; manager registration includes the required creation of a new ranch.
- Email verification and continuation of an existing registration using an isolated native identity session, without replacing the workspace identity.
- Authenticated, read-only professional profiles with strict nullable response mapping and an explicit reload. Profile writes are not exposed in the UI, application service, repository port, or HTTP client.
- Explicit, session-only ranch selection from the server-authorized list, with ranch metadata, effective access scopes, expiration, and no automatic choice or stored access code.
- Ranch-scoped animal pages with exact ear-tag/status filters, replacement pagination, identification and productive-stage history, and the backend's available collar/last-received-communication summary.
- Read-only latest valid temperature, activity, rumination, and historical last-known coordinates, each with explicit availability, capture time, server-evaluated freshness, and reported units/origin. No live tracking or clinical classification is inferred.
- Read-only persisted cloud alerts with a workflow-status filter, real server pagination/counts, and expandable event metadata from the returned list. No acknowledgement or notification delivery is implemented.
- Scrollable sign-in, recovery, account, and terms pages with safe areas, accessible controls, and large-text/keyboard support.
- English by default, Latin American Spanish, and a device language preference. Changing the language updates the current page without resetting navigation.
- Validated, non-secret API and native Firebase settings. Missing settings leave sign-in unavailable without initializing a fabricated Firebase project or loading sample accounts.

**Ranch administration and advisory management remain separate work.** Choosing an authorized ranch does not join a ranch, grant access, or create records. Field operators cannot self-register through the backend registration use case; existing field-operator accounts may select only server-returned ranches without a role-based scope upgrade. There are no simulated production sessions or records. Animal creation/editing/deactivation, collar assignment, telemetry history/live readings, alert mutations/push delivery, offline storage, and the remaining business contexts are not implemented by this branch.

### Field-focused mobile delivery

The report distinguishes a field client for quick monitoring, alerts, and offline work from the fuller web management experience (`10-introduction.md`, objective at line 146; `40-solution-software-design.md`, container responsibilities). The product mapping in `annex-i-requirements-traceability.md` is the scope reference, not evidence of implemented services. Delivery proceeds sequentially:

1. Finish IAM with safe read-only profiles; preserve veterinarian and ranch-manager onboarding and the backend's existing field-operator role without adding self-registration or inferring permissions.
2. Select an authorized ranch using the existing IAM access contract. Keep the selection session-bound, clear it on account/access changes, and never expose management-only access codes as general navigation data.
3. Add animal summaries, recent telemetry, and last known location through actual implemented contracts. Always show available units, capture time, origin, and freshness; missing data is not zero or a healthy state.
4. Add authorized cloud alert reads and acknowledgement only with the backend's supported identity, idempotency, and concurrency contracts. Validate local Edge connectivity and authorization separately before claiming local alert support.
5. Add persistent field records and explicit sync outcomes after auditing snapshot/local-authorization and batch-sync contracts. Pending records must survive restart; authorization expiry, rejection, and conflict need deliberate recovery. Do not silently drop unsynced work on logout or expose it to another identity; storage isolation and retention require an explicit security design before this stage.
6. Review reminders, trough monitoring, and selected veterinarian workflows as later increments rather than copying full web clinical or planning modules.

The initial mobile users are ranch managers and veterinarians. Field-operator task assignment is a product decision still to confirm; existing server role data remains supported. Device inventory administration, geofence editing, payments/subscriptions, detailed analytics, and report exports are not included automatically. Other contexts are created only when an approved mobile use case requires them; the backend's seven-module structure is not a requirement to scaffold seven mobile features.

Each branch starts from updated `develop`, receives contract/security/UX tests, and is published for maintainer review before a separately authorized PR/merge. Next-stage work must not be stacked onto an unapproved feature or committed directly to `develop`. Under the maintainer's standing cleanup instruction, remove local and remote topic branches only after verifying their closed/merged PR, matching branch tip, and integrated history; preserve `main`, `develop`, and unmerged work.

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

Options are passed programmatically to named Firebase apps: `ichu-iam-mobile` for workspace authentication and `ichu-registration-mobile` for onboarding. Both use the same approved public project/native options; these are local SDK app instances, not additional cloud app registrations. No generated service-account credentials, `google-services.json`, or `GoogleService-Info.plist` are needed by this implementation. Unsupported platforms and incomplete/malformed native settings never initialize a Firebase client. Existing named Firebase apps must match the requested options before reuse.

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

### Registration contract and lifecycle

- The backend permits `RanchManager` and `Veterinarian` registration, not `FieldOperator`. Veterinarians submit only `role`; managers also submit `ranchName`, `region`, `district`, and `estimatedHeadCount`. Email and UID come from the bearer identity, never from the request body. Passwords go only to Firebase.
- Ranch names have a 160-character limit; region and district have 120-character limits. The animal count is nonnegative and must fit the backend request's Int32 representation. Email inputs support the backend's 254-character limit. The mobile creation form uses an 8–128-character nonblank password UX bound; Firebase project password policy may apply additional requirements. Existing-identity sign-in/continuation accepts a nonblank password up to 128 characters without imposing the new-account minimum. These are not backend registration password rules.
- Native identity creation sends a verification email. Returning users can continue with the already-created Firebase identity instead of creating it again. Restoring an onboarding identity sends no automatic email and submits no automatic account-creation request.
- The mobile flow explicitly reloads the user, refreshes verification claims, and waits for a verified identity before account submission. **This is a mobile flow decision, not a backend guarantee:** backend integration tests also permit an authenticated unverified identity to create a `PendingVerification` account, despite the endpoint description. This branch does not modify that server behavior.
- `POST /api/v1/accounts` returns `{account, ranchId}` with a pending account. That acknowledgement is not a workspace session. The isolated identity is signed out after success; normal workspace sign-in later performs the backend account activation and sequential access checks.
- Registration is not idempotent: duplicate email/UID returns `409 Iam.AccountAlreadyExists`. No POST is automatically retried. After an ambiguous outcome or conflict, the explicit reconciliation action checks the identity-bound `GET /accounts/me` instead of replaying creation; that verified GET can activate an already-created account. It does not grant a mobile workspace session by itself.
- Onboarding uses a separate named SDK identity so the existing verified-account observer cannot reject a newly created unverified identity, and a restored workspace identity cannot be replaced by registration. Both lifecycles use the same native mutation/cleanup coordinator implementation. Cancellation signs out the isolated session; it does not delete Firebase users, accounts, or ranches.
- A failed verification-email request preserves the created identity for resend/continuation. A failed native cleanup keeps new identity mutations blocked until sign-out retry succeeds. Registration-service disposal invalidates late work and preserves native cleanup intent; a late server POST may already have committed and is never represented as an authenticated workspace.
- Uncertain outcomes are tracked per Firebase UID within the service lifetime. Cancelling one identity cannot force a different identity into its reconciliation flow; returning to the original UID still requires its own safe check. This is not a persisted idempotency ledger: after process restart, an explicit creation attempt may return the backend's duplicate-account conflict and then be reconciled.

### Professional profile contract

- `GET /api/v1/profiles/me` returns the authenticated caller's complete account resource, including a nullable `profile`. The existing `GET /accounts/me` carries the same typed profile data. No account ID is accepted to select another person's account.
- Specialty is nonblank and bounded to 120 characters; license is nonblank and bounded to 80. Mapping follows backend trimming and uppercase-license normalization, without a license regex or specialty allowlist. Experience must be an integer from 0 through 2147483647; malformed non-null profile resources fail closed.
- GET supports every server-authorized verified role, including accounts returned with a historical block status after expiry. Veterinarians have the normal navigation entry; other roles can open a direct protected read-only route. No account-ID selector or mutation path is offered.
- Profile editing is deliberately deferred. The backend exposes a full-replacement PUT but no conditional-write/version or operation-result guarantee. A timeout does not cancel server processing: a subsequent GET can precede that delayed PUT, so it cannot prove settlement or safely unlock another save. This mobile client includes no dormant PUT implementation, simulated completion, or client-invented concurrency token. Future editing requires a separately reviewed backend guarantee and ordering tests.
- A separate application service observes the validated session and discards profile data/results on logout, UID/account/role changes, or session revalidation. Concurrent equivalent loads share one request. A 401/403 clears the profile; an explicit authorized GET may recover access without reopening cached data prematurely. Raw server titles, payloads, and tokens are not logged or presented as error messages.

### Authorized ranch selection

- `GET /api/v1/accounts/me/ranches` remains part of the existing sequential session validation, after `GET /accounts/me`. The selector consumes that validated snapshot; opening it or changing the choice sends no additional HTTP request. An empty array is a valid session with an explicit empty view, not a fabricated ranch.
- Each entry has a UUID `ranchId`, known `scope`, required nonblank `name`, `region`, and `district`, and nullable `expiresAt`. Mapping enforces the backend's 160/120/120 text bounds, rejects duplicate ranch identities, and requires an explicit UTC/offset expiration with a valid calendar/time. It never substitutes an ID or sample text for missing metadata.
- The backend resolves membership and advisory access. A manager's owner membership can yield `Manage`; other memberships yield `Read`. A veterinarian's currently granted advisory may yield `Read` or `ClinicalWrite` with expiration. The client preserves the returned scope rather than inferring elevated access from the account role. Later resource requests must still be authorized by the backend.
- The server may return an `accessCode` for managed ranches. The selector deliberately discards it during mapping: there is no model property, persisted value, log, or UI control for the code. The displayed ranch identifier is not that credential.
- `RanchSelectionService` is an IAM application service observing `AuthService`, not a new bounded context or another authentication state machine. It stores only the canonical chosen grant in memory. Even a single available ranch requires an explicit choice; query-string IDs do not choose one. Unknown, duplicate, and expired grants cannot be selected.
- Selection and available data clear on logout, session checking/revalidation, UID/account/role changes, snapshot replacement, or disposal. Explicit refresh uses the existing session validation and returns to the account route; it does not restore the previous choice. A locale change alone preserves selection. Restarting the app does not restore a ranch choice from preferences.
- A timer removes locally expired grants and clears an expired choice at the boundary, while pure getters also filter by the current instant. This is a conservative UI restriction, not an offline authorization lease, server-clock substitute, or guarantee that a grant cannot be revoked remotely. Resume and explicit refresh revalidate with the server; selecting a ranch itself fetches no livestock data.
- No invitation, access-code entry, ranch CRUD, advisory decision, local Edge connection, or offline synchronization is introduced by the selector.

### Read-only animal information

- `GET /api/v1/ranches/{ranchId}/cattle` returns an array, not a pagination envelope. Mobile uses 20 records per page, replaces rather than appends results, and shows no invented total or `hasMore`. A full page permits an explicit attempt at the next page; an empty following page remains valid and allows returning to the previous page.
- The exposed filters are exact, trimmed, case-sensitive `earTag` (at most 30 UTF-16 code units) and optional `status` (`Active`/`Inactive`). No status filter includes inactive animals. `page` and `pageSize` must fit server Int32/query limits, with `page >= 1`, `pageSize` from 1 to 100, and a valid Int32 offset. Lot filtering exists on the server but is not exposed in this increment.
- `GET /api/v1/ranches/{ranchId}/cattle/{cattleId}` returns `{cattle, device}`. Mapping validates both requested identities, nonempty GUIDs/version, known enum names, immutable stage periods, lifecycle fields, and real calendar dates. Date-only birth/exit/stage values never undergo local-time conversion; stage-period ends are exclusive and same-day transitions remain valid.
- Collar integration has four distinct presentations: unavailable information (not proof of no collar), confirmed no assigned collar, assigned collar without received communication, and assigned collar with a reception timestamp. Only that timestamp is localized as an instant. It is not sensor capture time, a telemetry reading, location, or evidence of a healthy/live animal.
- Cattle production code depends only on the public IAM `AuthorizedRanchSession` facade. Its opaque context identity binds each read/token to the validated account and canonical selected grant, including A→B→A changes. SDK tokens are obtained per request without manual caching. The Cattle GET client has fixed same-origin routes, disabled redirects, a bounded body/deadline, and no automatic retries, writes, or raw server-error presentation.
- Independent list/detail operation generations discard superseded responses. Selection loss, expiry, revalidation, identity changes, and logout hide/clear scoped data; a 401/403 invalidates both views and pending reads. Recovery requires an explicit read, not reopening the previous snapshot. Choosing a ranch alone triggers no animal request.
- The protected list route is `/account/animals`; detail is `/account/animals/{ranchId}/{cattleId}`. An incoming route/query cannot select a ranch. A foreign ranch in a detail route redirects to the current list without requesting that animal. Every real GET still requires backend ranch authorization; local selection grants no permissions.

### Latest animal monitoring

- Only `GET /api/v1/ranches/{ranchId}/cattle/{cattleId}/telemetry/latest` is consumed. The backend independently authorizes monitoring access to that ranch and checks the animal/ranch pair. A 404 means that pair was not found, not that telemetry is empty. A valid **200** can contain four unavailable observations, with no substitute zeros.
- The summary contains `cattleId`, `evaluatedAt`, nullable `lastReadingRecordedAt`, `origin: EdgeGateway`, three indicators (`bodyTemperature`, `activityIndex`, `ruminationMinutes`), and `lastKnownPosition`. Indicators have exact units `celsius`, `index`, and `minutes`. Each available observation has its own capture time and server `isStale` decision; unavailable values, timestamps, and freshness are null. Valid zero values remain available. The latest response contains no battery, collar/device identity, thresholds, alerts, or health assessment.
- Mapping validates the requested animal ID, known statuses/origin/units, all required nullable fields, real offset-aware timestamps, and finite numbers. Activity and rumination are nonnegative doubles without invented maxima or integer restrictions; temperature has no client-invented clinical range. Available positions require latitude from -90 through 90, longitude from -180 through 180, and nonnegative reported accuracy in meters.
- Freshness is the server's decision **at `evaluatedAt`**, not a continuously updated mobile clock or live status. The page displays evaluation/capture instants in local time, explicitly warns that it is a snapshot, and offers manual reload. It does not recompute `isStale`, silently refresh, diagnose health, or fabricate absent positions. Independent captures may have different times; sequential server reads do not promise an atomic cross-field snapshot. Future capture timestamps are not rejected using a client clock.
- Historical readings can remain attributed to an animal after collar reassignment, because the backend resolves assignment at capture time. The monitoring entry is therefore available from a loaded animal profile even without a currently assigned collar. Last-known coordinates are historical, not a live GPS fix, current collar location, map, or geofence.
- Operations Monitoring depends only on the public IAM authorized-ranch facade, never Cattle Information internals. The app composes a cattle-ID callback and the guarded `/account/animals/{ranchId}/{cattleId}/monitoring` route; URL/query identifiers cannot select a ranch. This sibling route does not construct hidden animal list/profile pages or trigger their reads on a direct monitoring link. The fixed GET adapter obtains an SDK token per request, follows no redirects, bounds response size/time, and automatically retries nothing.
- Reads are deduplicated by opaque authorization context and cattle ID, and superseded operations are fenced. Selection change/expiry, revalidation, SDK identity drift, logout, and disposal hide old data. Configuration/permission/network recovery requires an explicit new read; old snapshots never reopen by themselves. Pending intent is installed before notifying loading observers so reentrant calls share one request, including after synchronous repository failures.
- The backend history endpoint is intentionally **not** implemented in this increment. Ingestion, alert mutations/push delivery, Edge connectivity, offline persistence/sync, subscriptions, administration, and analytics remain separate work. A displayed `EdgeGateway` origin describes the cloud response's provenance; it is not evidence of a direct mobile-to-Edge connection.
- Numeric presentation localizes the decimal separator while keeping the shortest round-trippable decimal, avoiding binary artifacts such as `38.600000000000001`. Very small/large values use scientific notation rather than rounding a valid measurement to zero.

### Read-only cloud alerts

- `GET /api/v1/ranches/{ranchId}/alerts` returns `{page, pageSize, totalCount, items}` ordered by event capture descending, then alert ID. Mobile replaces pages rather than appending, uses 20 rows by default, and exposes only the optional `Pending`/`Acknowledged` workflow-status filter. No filter means all statuses. The backend also supports a cattle-ID filter, but this screen does not expose it or add speculative type/severity/date filters.
- Mobile accepts page sizes from 1 through 100 as a conservative client bound; the backend's configurable maximum defaults to 500. Page and size must fit Int32, and mobile also prevents `(page - 1) * pageSize` from overflowing the server's Int32 offset. Actual server `totalCount` controls the next-page action; it is not a severity count. Sequential list/count queries can legitimately disagree after concurrent changes, so the client does not fabricate cross-field consistency or infer health from totals.
- The response carries alert/ranch/animal/device/gateway GUIDs, known type/severity/status/origin, capture and cloud-reception times, threshold or geofence evidence, configuration revision (Int64), version (Int32), related reading IDs, and nullable stored acknowledgement metadata. Mapping requires the implemented JSON fields and validates their types, identifiers, finite numbers, units, timestamps, and domain-shaped nullable combinations. All alert ranch IDs must match the selected context; duplicate alert identities are rejected.
- `raisedAt` is the triggering reading's capture time; `receivedAt` is cloud receipt, not evaluation time. The alert DTO contains no `evaluatedAt`, animal name, or ear tag. The UI invents none and performs no animal-metadata lookup. `Informative`/`Warning`/`Critical` are reported event classifications, not the animal's current clinical state. Geofence return/clear information remains separate from `Pending`/`Acknowledged` workflow state.
- There is **no implemented REST alert-detail GET**. Expanding a card displays the snapshot already returned in the page, with no extra request, edit form, or fabricated detail route. The first ten related reading IDs are shown with an explicit shown/returned count if truncated. Repeated reading GUIDs are preserved: backend evidence identity is `(deviceId, readingId)`, but this DTO exposes only reading IDs, not the device for each evidence entry.
- The protected `/account/alerts` route requires an explicit current ranch selection. Incoming URL/query identifiers cannot choose a ranch; existing server-authorized manager, veterinarian, and field-operator accounts use the same read navigation without a client role-based scope upgrade. An empty page means no matching persisted cloud alerts were returned; it cannot establish healthy animals, no local alerts, current coverage, or successful synchronization.
- Operations Monitoring reuses its bounded fixed-GET client and public IAM context/token facade. A shared presentation formatter preserves existing latest-telemetry decimal/time behavior. Context and request generations fence late pages across query/ranch changes, revalidation, same-UID relogin, expiry, SDK drift, logout, and disposal. Opening details changes no server state; failures clear the owned page/count, and recovery requires an explicit read.
- A backend PATCH exists with `operationId`, `expectedVersion`, finding, and optional action; identical normalized replay is supported. **It is deliberately outside this read-only branch, not claimed unsupported by the backend.** Its acknowledgement time comes from the cloud clock, and it does not guarantee mobile-to-Edge synchronization or resolution of the alert. A separate cloud-only acknowledgement workflow needs deliberate same-key ambiguous-outcome/conflict handling and must not be presented as the report's complete field-attendance/offline-sync use case. This client has no dormant PATCH port or automatic mutation retry.

### Structure

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
      application/services/         # Session, registration, profiles, ranch choice
      application/facades/          # Public selected-ranch context/token boundary
      infrastructure/               # Native Firebase and authenticated REST adapters
      presentation/                 # IAM flows and protected account/profile/ranch views
    cattle_information/
      domain/                       # Animal snapshots, calendar dates, filters, read port
      application/services/         # Context-bound list/detail coordination
      infrastructure/               # Fixed GET transport and strict resource mapping
      presentation/                 # Localized read-only animal pages and labels
    operations_monitoring/
      domain/                       # Latest observations, units, availability, read port
      application/services/         # Explicit context-bound summary and alert reads
      infrastructure/               # Fixed monitoring GETs and strict resource mapping
      presentation/                 # Snapshots, cloud events, shared display formatting
  shared/
    domain/model/                   # Framework-independent language values
    domain/repositories/            # Preference persistence port
    application/services/           # Language coordination and UI notifications
    infrastructure/i18n/            # EN/ES ARBs; generated output is ignored
    infrastructure/preferences/     # Device preference adapter
    presentation/widgets/           # Reused language control
```

Dependencies point inward. Domain code is plain Dart, without Flutter, HTTP, Firebase, or JSON transport dependencies. Application services coordinate ports; presentation never accesses platform storage directly. Constructor injection is used instead of a global service locator. `ChangeNotifier` supplies notifications in the language and session application services, not in domain models.

`go_router` owns the stable route graph: `/login`, `/recover`, `/register`, `/terms`, protected `/account`, and its profile/ranch/animal children; `/` selects login or account. Every `/account/` descendant requires a validated session; animal routes also require a current explicit ranch selection. A validated workspace identity cannot open registration. Direct public routes have reliable back behavior. External return destinations are ignored. Locale changes preserve the router, and session/selection notifications drive authorization redirects. App bootstrap composes the SDK, HTTP transport, and domain ports; widgets do not access adapters directly.

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

### Registration branch verification

Verified on Windows with Flutter 3.44.6 / Dart 3.12.2 on 2026-11-12:

- Formatting and static analysis pass; the expanded suite has **217 passing tests**, including verification-before-POST, both permitted registration roles, unknown-outcome reconciliation, UID switching, cancellation/disposal races, password hygiene, EN/ES layouts at 200% text, and accessibility checks. A separate run of the 25 API configuration tests also passes with production defines.
- The final Android debug APK builds and runs on the Android API 37 emulator. Native checks cover registration entry/back navigation, EN/ES page preservation, blocked submission without approved settings, existing public recovery/terms flows, and persistent language after force-stop/relaunch.
- Source/test directories were audited for `lowercase_with_underscores`; no invalid names were found. Platform-required native folders, identifiers, and cloud registrations were not renamed or changed.
- Native identity creation, verification email delivery, and live account/ranch creation remain **unverified**. Public Firebase setup is still missing, and Render continues to return 503 `Service Suspended`. Synthetic test results must not be presented as live integration.
- iOS build/run still requires macOS/Xcode. The existing upstream Firebase/Kotlin warning remains; the current debug build succeeds.

### Read-only profile branch verification

Verified on Windows with Flutter 3.44.6 / Dart 3.12.2 on 2026-11-12:

- Formatting and static analysis pass; the full suite has **273 passing tests**. A separate production-configuration run has **25 passing tests**. The count replaces the earlier unpublished editor suite: write-only cases were removed with the unsupported mutation feature, not presented as coverage for the read-only product.
- Read tests cover complete-account/nullable-profile mapping, backend field bounds, each known role, fresh SDK tokens, fixed own-account routes, disabled redirects, safe errors, and no automatic replay. Service tests cover deduplicated loads, denied-read recovery, failed refresh, and stale responses across logout, disposal, UID changes, and same-UID revalidation with unchanged or changed account/role.
- Widget tests cover the protected route, server-loaded values without form/save controls, empty/error/loading states, service replacement, long values, EN/ES, Android/iOS theme platforms, 320-pixel portrait and landscape layouts at 200% text, keyboard insets, labeled controls, tap targets, and contrast. These iOS-themed widget tests are not an iOS native build or device run.
- The final Android debug APK builds and runs on the Android API 37 emulator. The emulator initially remained offline; a cold start without loading its saved snapshot restored it. Native regression checks pass for public registration/recovery/terms navigation, EN/ES preservation, unavailable-configuration submission guards, and persistent language after restart. Launching with `/account/profile` without a session returns to sign-in. Public screenshots were reviewed locally; captures and build output are not committed.
- Source/test folders and Dart filenames pass the naming audit. No tracked unused placeholder folders were found: required native targets, generated local build folders, fonts, and licenses were preserved. Unused profile editor/mutation code and localization entries were removed instead of leaving dormant features.
- A read-only security review found no P1/P2 findings in this snapshot. Profile editing remains deferred because the backend does not guarantee settlement or ordering of an ambiguous PUT; no profile mutation exists in the client.
- The latest public `/health` check returned **200**; the service is no longer assumed suspended based on earlier branch checks. Live native authentication and authenticated profile responses remain **unverified**, because approved Firebase options/native registrations are still missing. Test identities/resources are synthetic only; no cloud registrations, native identifiers, or backend files were changed.
- Native iOS validation still requires macOS/Xcode. The documented upstream Firebase/Kotlin warning persists, but the current debug APK builds successfully. This is not a signed store release or completion of the later ranch, animal, alert, Edge, or offline stages.

### Ranch selection branch verification

Verified on Windows with Flutter 3.44.6 / Dart 3.12.2 on 2026-11-12:

- Formatting and static analysis pass; **333 tests pass** in the full suite. The separate production-configuration run passes all **25 tests**. The suite includes **38 selector widget tests**; these are a subset, not an additional production test count.
- Contract tests cover required ranch metadata/bounds, nullable UTC and numeric-offset expiration, invalid calendar/time values, immutable lists, duplicate identities, known scopes, and discarded access codes. Selection tests cover empty/single/multiple lists without automatic choice, canonical scopes, expiry notifications, initial validation notifications, reentrant refresh, unrelated notifications, UID/account/role changes, rejection, logout, and disposal.
- EN/ES selector tests cover Android/iOS theme platforms in narrow and landscape layouts at normal and 200% text, long server-provided values, keyboard insets, scope-only presentation for all existing roles, empty/unavailable states, selection/switch/clear, pending refresh privacy, locale preservation, and accessibility guidelines. Router tests reject unauthenticated selection and ignore incoming ranch IDs as selection instructions.
- The final debug APK builds, installs, and runs on the Android API 37 emulator. Public registration, recovery, terms, EN/ES navigation, absent-configuration submission guards, and persisted language regression checks pass. An initial package-update launch exposed no accessibility root; a forced app relaunch resolved that transient state, and the final checks passed. Native launches with `/account/ranches`, a ranch-ID query, and `/account/profile` return to sign-in without a validated session.
- Synthetic EN/ES selector previews with bundled fonts/icons were rendered and visually inspected locally; fixture ranch names explicitly identify test data. The preview harness, images, public native captures, and build output remain outside version control. These images are not evidence of real ranch access or a native authenticated selector run.
- A read-only security review found no P1/P2 findings. Dart source/test directory and filename checks pass; no speculative feature folders, dependencies, platform targets, or management APIs were introduced.
- Public health initially timed out, then returned **200** on the later check. No authenticated ranch response or real user selection is claimed verified: approved native Firebase options/registrations remain missing. iOS-themed widget tests are not a native iOS build/run; that still requires macOS/Xcode. The existing upstream Firebase/Kotlin warning remains documented and the debug APK builds successfully.

### Read-only animal branch verification

Verified on Windows with Flutter 3.44.6 / Dart 3.12.2 on 2026-11-12:

- Formatting and static analysis pass; the complete suite has **422 passing tests**. A separate production-configuration run passes all **25 tests**. The new animal widget file contains **31 tests**; these are included in the full count.
- Domain, facade, adapter, and service coverage checks Int32/query bounds, calendar dates, implemented enums, tenant/animal IDs, all four device states, duplicate identities, no invented totals, replacement pagination, fresh tokens, same-origin GETs, disabled redirects/replay, bounded/malformed responses, and sanitized failures. Async tests cover superseded filters/profiles, A→B→A selection, revalidation, same-UID relogin, silent SDK identity drift, local grant expiry, logout/disposal, and cross-view permission invalidation.
- EN/ES list/profile widget tests cover read-only returned values, empty/loading/errors, explicit retry, filters/pages, keyboard insets, narrow/landscape layouts at 200% text, Android/iOS themes, and accessibility labels/tap targets/contrast. Router tests reject unsigned animal links, refuse URL-driven ranch selection, and redirect foreign-ranch detail links without fetching that animal.
- Synthetic EN/ES list/profile previews were rendered with bundled fonts/icons and visually reviewed. Ranch names and animal tags explicitly mark test fixtures. The temporary harness, captures, and build outputs are not committed or evidence of authenticated native animal access.
- The final debug APK builds, installs, and runs on the Android API 37 emulator. Native launches of the animal list, a ranch-ID query, ranch-scoped detail, selector, and professional profile all return to sign-in without a validated session. Public registration/recovery/terms flows, EN/ES preservation, missing-configuration submission guards, and persistent language regression checks pass. An initial post-install accessibility-root failure was resolved by a forced relaunch before repeating the checks. The existing upstream Firebase/Kotlin warning persists; the debug build succeeds.
- An independent read-only contract/security review found no P1/P2 findings. No new dependencies, native identifiers, cloud registrations, backend changes, mutations, telemetry history, local Edge client, or offline persistence were introduced.
- Live Firebase authentication and authorized animal requests remain **unverified**, because approved native Firebase options/registrations are missing. Public health was not rechecked for this snapshot; the earlier ranch-branch result is historical, not a current availability guarantee. Native iOS build/run still requires macOS/Xcode; iOS-themed tests do not substitute for it.

### Latest monitoring branch verification

Verified on Windows with Flutter 3.44.6 / Dart 3.12.2 on 2026-11-12:

- Formatting and static analysis pass; the complete suite has **497 passing tests**. The separate production-configuration run passes **25 tests**. New monitoring coverage includes **30 service tests**, **15 adapter tests**, **3 domain tests**, **22 widget tests**, and **5 router regressions**, all included in the full count.
- Tests cover empty 200 responses, independent observation times, exact units/origin, required nullable fields, malformed resources, finite numbers/GPS limits, valid zeros and extreme magnitudes, offset-aware timestamps, no fabricated clinical bounds, fresh tokens, fixed GET paths, disabled redirects/replay, bounded bodies/timeouts, and safe failures. Sequential-server-read shapes are accepted without inventing cross-field atomicity.
- Session tests exercise A→B→A ranch changes, superseded animal IDs, loading-observer reentrancy, synchronous adapter failures, explicit recovery after configuration/network/401/403 failures, same-UID relogin, unchanged/changed account and role revalidation, silent SDK identity drift, local expiry, logout, disposal, and cancellation before scheduled I/O starts.
- EN/ES widget coverage checks snapshot warnings, historical position, local evaluation/capture timestamps, scientific notation, decimal separators without binary artifacts, unavailable versus zero, explicit retry, route/service replacement, locale preservation, Android/iOS themes, narrow/landscape 200% text, keyboard insets, labels, tap targets, and contrast. Direct monitoring routes do not issue hidden animal list/profile reads; unsigned, unselected, malformed, and foreign-ranch links remain guarded.
- Synthetic EN/ES previews with bundled fonts/icons were rendered and visually reviewed. The visual pass identified decimal artifacts, which were corrected and covered by two dedicated regressions. Fixture names mark synthetic data; temporary preview harnesses, images, logs, and build output remain outside version control and do not demonstrate live monitoring.
- The final debug APK builds, installs, and runs on the Android API 37 emulator. Unsigned native launches of valid monitoring, a foreign ranch-ID query, malformed animal ID, animal list, ranch selector, and professional profile return to sign-in. Public registration/recovery/terms navigation, EN/ES preservation, unavailable-configuration submission guards, and persisted language regression checks pass. A combined verification command first timed out during installation; a separate native run with a longer budget succeeded. The initial package-update activity handoff was resolved by explicitly relaunching the app before checking routes. The existing upstream Firebase/Kotlin warning persists, but the debug build succeeds.
- Contract, source/test naming, and DDD dependency checks were performed by the coordinator. No additional independent security sign-off is claimed for this snapshot. There are no backend edits, new dependencies, platform targets, cloud/native identifier changes, ingestion/history/alert APIs, local Edge client, or offline storage.
- Live Firebase authentication and authorized latest telemetry remain **unverified**, because approved public native Firebase settings/registrations are missing. Public health was not rechecked for this snapshot. Native iOS build/run still needs macOS/Xcode; iOS-themed tests are not a native build/run.

### Read-only alerts branch verification

Verified on Windows with Flutter 3.44.6 / Dart 3.12.2 on 2026-11-12:

- Localization generation, formatting, and static analysis pass. The full suite passes **567 tests**, including **24 alert service**, **14 alert adapter**, **3 alert query**, **24 alert widget**, and **5 new router** tests. A separate production-configuration run passes **25 tests**. Existing latest-telemetry transport, display, and navigation regressions remain in the full count.
- Contract coverage checks real server envelopes/counts, conservative mobile size/Int32 offset limits, all event types/severities/statuses, Int64 revision and Int32 version bounds, capture/reception offsets, geofence/acknowledgement nullable combinations, required fields, immutable evidence/pages, tenant/filter mismatches, and duplicate alert IDs. Equal evidence reading GUIDs remain valid because backend identity also includes a device ID. Concurrent list/count changes are accepted without fabricated consistency.
- Application coverage checks replacement pagination, status drafts and committed queries, explicit retries, reentrant load deduplication, synchronous failures, superseded queries, A→B→A selection, same-UID relogin, unchanged/changed account and role revalidation, local expiry, SDK drift, logout, and disposal. Inaccessible data and totals hide immediately; no permission, identity, or mutation is inferred from selecting a ranch.
- EN/ES widget tests cover expanded returned snapshots without additional reads, reported event metadata, clear versus acknowledgement state, plain stored finding/action text without editing controls, zero/nullable/scientific values, the ten-ID presentation cap with actual returned counts, locale/service replacement, keyboard insets, normal and 200% narrow/landscape layouts, Android/iOS themes, labels, tap targets, and contrast. Router regressions cover all three existing roles, absent sessions/selection, ignored ranch-ID queries, and revalidation without hidden animal/telemetry requests.
- Synthetic EN/ES collapsed/expanded alert previews with bundled fonts/icons were rendered and visually reviewed; test ranch names explicitly mark fixtures. These captures, temporary harnesses, logs, and build output are not committed or proof of live alert access. The visual review shortened explanatory copy while retaining the cloud-only, historical, read-only, and non-clinical caveats.
- The final debug APK builds, installs, and runs on the Android API 37 emulator. Native unsigned alert links, a foreign ranch-ID query, an unsupported detail path, and existing monitoring/ranch/profile routes return to sign-in. Public registration/recovery/terms navigation, EN/ES preservation, missing-configuration submission guards, and persisted language regression checks pass. The first post-install launch remained in Android's package-update activity and exposed no accessibility root; an explicit cold relaunch resolved it before all checks were repeated successfully. The existing upstream Firebase/Kotlin warning persists, but the debug build succeeds.
- An independent read-only security/contract review reported no actionable P1/P2 findings. Source/test naming, inward domain dependencies, and public-IAM-only collaboration checks pass; dependencies and native targets remain unchanged. No backend changes, dormant alert mutation API, push delivery, Edge client, or offline queue were introduced.
- Live Firebase authentication and authorized cloud-alert responses remain **unverified**, because approved native Firebase settings/registrations are missing. Public health was not rechecked for this snapshot. Native iOS build/run still needs macOS/Xcode; iOS-themed tests do not substitute for native execution.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md). Code, comments, documentation, and Conventional Commit messages are in English. All visible interface copy is localized. Feature branches start from and target `develop`; do not commit directly to `develop` or `main`. Published feature branches must remain unmerged until the maintainer authorizes their PR and merge.

## License

Copyright (c) 2026 SmartFarm. All rights reserved. The application is proprietary; see [LICENSE.md](LICENSE.md). Bundled fonts retain their SIL Open Font License notices.
