# ICHU Mobile App

Flutter client for ICHU, SmartFarm's livestock management platform, targeting **Android and iOS only**. It implements IAM authentication, registration, read-only professional profiles, and authorized ranch selection on the shared mobile foundation.

The implemented backend is the functional source of truth for API contracts and business rules. The report defines mobile product scope; the unfinished Web App supplies visual brand references only. Mobile delivery selects field-oriented use cases, not every backend module or browser workflow. Proposed report endpoints must be checked against implemented contracts before use.

## Current scope

- Sign-in and password recovery through the native Firebase Authentication SDK, with the web app's palette, Outfit headings, Plus Jakarta Sans body text, and Andean herd imagery.
- Session restoration and a guarded account summary that opens only after verified identity and sequential IAM account/access validation.
- Account registration for the backend-supported veterinarian and ranch-manager roles; manager registration includes the required creation of a new ranch.
- Email verification and continuation of an existing registration using an isolated native identity session, without replacing the workspace identity.
- Authenticated, read-only professional profiles with strict nullable response mapping and an explicit reload. Profile writes are not exposed in the UI, application service, repository port, or HTTP client.
- Explicit, session-only ranch selection from the server-authorized list, with ranch metadata, effective access scopes, expiration, and no automatic choice or stored access code.
- Scrollable sign-in, recovery, account, and terms pages with safe areas, accessible controls, and large-text/keyboard support.
- English by default, Latin American Spanish, and a device language preference. Changing the language updates the current page without resetting navigation.
- Validated, non-secret API and native Firebase settings. Missing settings leave sign-in unavailable without initializing a fabricated Firebase project or loading sample accounts.

**Ranch administration and advisory management remain separate work.** Choosing an authorized ranch does not join a ranch, grant access, or create records. Field operators cannot self-register through the backend registration use case; existing field-operator accounts may select only server-returned ranches without a role-based scope upgrade. There are no simulated production sessions or ranch records. Cattle Information, IoT Assets, Operations Monitoring, Planning, Dashboard Analytics, and Subscription Plans remain outside this branch's scope.

### Field-focused mobile delivery

The report distinguishes a field client for quick monitoring, alerts, and offline work from the fuller web management experience (`10-introduction.md`, objective at line 146; `40-solution-software-design.md`, container responsibilities). The product mapping in `annex-i-requirements-traceability.md` is the scope reference, not evidence of implemented services. Delivery proceeds sequentially:

1. Finish IAM with safe read-only profiles; preserve veterinarian and ranch-manager onboarding and the backend's existing field-operator role without adding self-registration or inferring permissions.
2. Select an authorized ranch using the existing IAM access contract. Keep the selection session-bound, clear it on account/access changes, and never expose management-only access codes as general navigation data.
3. Add animal summaries, recent telemetry, and last known location through actual implemented contracts. Always show available units, capture time, origin, and freshness; missing data is not zero or a healthy state.
4. Add authorized cloud alert reads and acknowledgement only with the backend's supported identity, idempotency, and concurrency contracts. Validate local Edge connectivity and authorization separately before claiming local alert support.
5. Add persistent field records and explicit sync outcomes after auditing snapshot/local-authorization and batch-sync contracts. Pending records must survive restart; authorization expiry, rejection, and conflict need deliberate recovery. Do not silently drop unsynced work on logout or expose it to another identity; storage isolation and retention require an explicit security design before this stage.
6. Review reminders, trough monitoring, and selected veterinarian workflows as later increments rather than copying full web clinical or planning modules.

The initial mobile users are ranch managers and veterinarians. Field-operator task assignment is a product decision still to confirm; existing server role data remains supported. Device inventory administration, geofence editing, payments/subscriptions, detailed analytics, and report exports are not included automatically. Other contexts are created only when an approved mobile use case requires them; the backend's seven-module structure is not a requirement to scaffold seven mobile features.

Each branch starts from updated `develop`, receives contract/security/UX tests, and is published for maintainer review before a separately authorized PR/merge. Next-stage work must not be stacked onto an unapproved feature or committed directly to `develop`.

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
- A timer removes locally expired grants and clears an expired choice at the boundary, while pure getters also filter by the current instant. This is a conservative UI restriction, not an offline authorization lease, server-clock substitute, or guarantee that a grant cannot be revoked remotely. Resume and explicit refresh revalidate with the server; no livestock data is fetched by this stage.
- No invitation, access-code entry, ranch CRUD, advisory decision, animal navigation, local Edge connection, or offline synchronization is introduced in this branch. Those need separately reviewed product scope and implemented contracts.

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
      infrastructure/               # Native Firebase and authenticated REST adapters
      presentation/                 # IAM flows and protected account/profile/ranch views
  shared/
    domain/model/                   # Framework-independent language values
    domain/repositories/            # Preference persistence port
    application/services/           # Language coordination and UI notifications
    infrastructure/i18n/            # EN/ES ARBs; generated output is ignored
    infrastructure/preferences/     # Device preference adapter
    presentation/widgets/           # Reused language control
```

Dependencies point inward. Domain code is plain Dart, without Flutter, HTTP, Firebase, or JSON transport dependencies. Application services coordinate ports; presentation never accesses platform storage directly. Constructor injection is used instead of a global service locator. `ChangeNotifier` supplies notifications in the language and session application services, not in domain models.

`go_router` owns the stable route graph: `/login`, `/recover`, `/register`, `/terms`, protected `/account`, and its protected `/account/profile` and `/account/ranches` children; `/` selects login or account. Every `/account/` descendant requires a validated session. A validated workspace identity cannot open registration. Direct public routes have reliable back behavior. External return destinations are ignored. Locale changes preserve the router, and the session service drives authorization redirects. App bootstrap composes the SDK, HTTP transport, and domain ports; widgets do not access adapters directly.

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

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md). Code, comments, documentation, and Conventional Commit messages are in English. All visible interface copy is localized. Feature branches start from and target `develop`; do not commit directly to `develop` or `main`. Published feature branches must remain unmerged until the maintainer authorizes their PR and merge.

## License

Copyright (c) 2026 SmartFarm. All rights reserved. The application is proprietary; see [LICENSE.md](LICENSE.md). Bundled fonts retain their SIL Open Font License notices.
