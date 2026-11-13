# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Authorized, paginated historical telemetry for a selected animal, with bounded time ranges, validated capture status, and EN/ES date, metric, and empty-state presentation.
- Protected, localized ranch-advisory navigation and service composition for veterinarian access requests and manager review/direct grants, with selected-ranch authorization context.
- Ranch-manager animal registration, detail correction, productive-stage change, and deactivation screens (EN/ES) wired into app composition and shown only for server-issued manage grants.
- Version-checked, idempotent cloud-only alert acknowledgements with server timestamps, safe same-operation retries, conflict refresh, and explicit limits against implying clinical attendance, resolution, or Edge synchronization.
- Immutable ranch alert contracts and real page envelopes with known workflow/type/severity metadata, captured/cloud-received times, stored acknowledgement fields, and server-bounded pagination/filter validation.
- A constrained alert-list GET sharing the existing Operations Monitoring transport, with tenant/resource mapping, canonical status queries, safe errors, fresh IAM-facade tokens, and preserved timeout/redirect/replay safeguards.
- Context-bound alert page coordination with replacement pagination, real server totals, explicit retry, deduplicated pending intent, and isolation across query/ranch/session changes and late responses.
- Guarded EN/ES cloud-alert reads for all existing server-authorized roles, expandable returned event snapshots without detail requests or mutations, and explicit historical/empty/zero/synchronization caveats.
- Latest-only animal monitoring contracts with independent nullable observations, typed units/origin, capture timestamps, and server-evaluated freshness without inferred health states.
- Fixed authorized monitoring GET transport and strict response mapping for identifiers, availability, finite numbers, GPS bounds, and offset-aware timestamps, with bounded responses and no replay or redirects.
- Context-bound monitoring coordination with deduplicated pending intent, explicit retry, and stale-result isolation across ranch/animal changes, identity drift, expiry, revalidation, logout, and disposal.
- EN/ES monitoring snapshots and historical coordinates, truthful unavailable/zero states, local capture/evaluation times, accessible large-text layouts, and guarded navigation from loaded animal profiles even without a current collar.
- Read-only animal contracts with immutable stage histories, timezone-independent calendar dates, exact ear-tag/status searches, and server-bounded replacement pagination.
- Public IAM facade exposing an opaque current ranch context and per-request SDK tokens without leaking IAM infrastructure into Cattle Information.
- Fixed ranch-scoped animal GET adapters with strict tenant/identity/resource validation, bounded responses, disabled redirects, and no automatic replay.
- Independent list/detail coordination with stale-response fencing across selection, identity, revalidation, logout, and permission failures.
- Protected EN/ES animal list/profile pages, explicit empty/error states, productive-stage history, and four distinct collar integration presentations without editing or invented live telemetry.
- Required server-issued ranch names and locations with strict access-list mapping, immutable results, duplicate-ID rejection, and validated expiration instants; access codes are intentionally discarded.
- Explicit in-memory selection from validated ranch grants, preserving backend scopes and clearing choices on session/snapshot changes, logout, disposal, and local grant expiry.
- Protected EN/ES ranch selection and account summaries, explicit empty states, refresh/clear actions, accessible scope labels, and Android/iOS large-text layout coverage without management controls.
- Own-account professional profile values with backend field bounds and nullable account profile data.
- Strict authenticated profile reads with full-account response validation, fresh SDK tokens, disabled redirects, and no profile mutation API.
- Session-bound profile loading with deduplicated reads, explicit recovery after denial, immediate cached-data clearing, and late-response isolation across logout, revalidation, account, and role changes.
- Protected EN/ES read-only profile screens with Android/iOS layout tests, large-text and keyboard-safe scrolling, accessible controls, and veterinarian account navigation.
- Backend-aligned registration contracts for veterinarians and ranch managers, including required ranch-creation fields, creation acknowledgements, and stable registration failures.
- Isolated native Firebase identity creation, existing-registration sign-in, and verification email support using shared safe SDK initialization and error mapping.
- A constrained authenticated account-creation POST with backend-shaped payloads and response mapping, no credential fields or automatic retries, and identity-bound GET reconciliation.
- Registration orchestration for verification, continuation, cancellation, and cleanup, with per-UID uncertain-outcome tracking and regression coverage across native/server async races.
- Localized registration and verification screens with supported-role selection, manager ranch fields, explicit safe reconciliation, and accessible mobile/large-text layouts.
- Framework-independent IAM identity/account/access contracts, safe authentication failures, and shared credential input rules.
- Native Firebase, HTTP, and guarded-routing dependencies, with an example for approved public client settings and ignored local overrides.
- Native Firebase identity/recovery and same-origin authenticated account adapters, with per-request SDK tokens, disabled redirects, bounded responses, and safe localized failure categories.
- Fail-closed session coordination with sequential account/access validation, guarded restoration, immediate local sign-out, and serialized cleanup of superseded native sign-ins.
- Regression tests for session races and restart safety, plus SDK-adapter unit tests with explicitly synthetic identities and credentials.
- Validated, non-secret API build configuration with HTTPS enforcement outside local development and no default production endpoint.
- English and Latin American Spanish catalogs, with generated localizations and equal-key checks.
- A device language preference with English fallback, session-only recovery on storage failures, and ordered writes that prevent stale preferences after timeouts.
- Bundled Outfit and Plus Jakarta Sans fonts with their licenses, plus optimized brand imagery from the web application.
- Localized mobile sign-in/recovery forms and terms pages with safe areas, scrolling, explicit configuration failures, and a guarded account summary with real API data only.
- Widget coverage for guarded navigation, form validation, password clearing, keyboard handling, language persistence, 200% text, and accessibility guidelines.
- Documented inward-facing DDD boundaries, configuration setup, mobile accessibility expectations, and bundled asset/font provenance.
- Documented native Firebase setup, session/transport guarantees, verified Android checks, and the remaining live-service and iOS validation blockers.
- Documented registration contracts, isolated identity ownership, per-UID reconciliation, remaining native/live-service limits, and source/test folder naming standards.
- Documented the report-aligned field-focused mobile scope, sequential delivery boundaries, profile-write safety prerequisite, read-only profile checks, and current live/native validation limits.
- Documented authorized ranch selection, discarded access credentials, conservative expiration handling, session-only context ownership, and verified selector/native regression checks with explicit live-integration limits.

### Changed
- Reused Operations Monitoring presentation formatting for both latest observations and alert events, preserving localized decimals without binary artifacts and local capture/reception instants.
- Extended account navigation with selection-bound animal reads and ranch-scoped detail guards; documented topic-branch cleanup after confirmed merges while preserving integration/release branches and unmerged work.
- Restricted mobile professional profiles to read-only until the backend can safely order or identify ambiguous writes; removed unused editor contracts, save errors, and mutation transport code.
- Aligned mobile email inputs with the backend's 254-character bound and kept new-account password rules separate from existing-identity sign-in validation.
- Made backend contracts and tests authoritative for mobile behavior; the unfinished Web App remains a visual reference only.
- Kept native cleanup intent and failed-sign-out retry requirements in a shared authentication lifecycle so session-service disposal cannot reopen a discarded identity.
- Aligned account access with backend authorization and time-based block expiry instead of copying the unfinished web client's status-label restriction; the account view reports server-validated access without relabeling stored status.
- Raised the minimum iOS deployment target to 15.0 to meet the Firebase plugins' requirements; Android network access is declared and local cleartext API traffic is debug-only.
- Replaced the starter counter and temporary unauthenticated preview with web-aligned IAM pages, stable guarded routing, and session revalidation when the app resumes.

### Fixed
- Deferred initial animal-page reads until after widget construction so covered list/profile listeners are not notified during nested navigation builds.
- Preserved shortest decimal representations in localized monitoring values so temperature/coordinates do not expose binary rounding artifacts and extreme magnitudes are not displayed as zero.

## [0.1.0] - 2026-11-07

### Changed
- Clarified Flutter contribution standards and agent operating instructions.

### Added
- Initial Flutter application setup configured exclusively for Android and iOS targets.
- GitFlow repository architecture setup with main and develop branches.
- Repository documentation suite: CONTRIBUTING.md, AGENTS.md, LICENSE.md, and CHANGELOG.md.
- Customized .gitignore protecting secrets, local.properties, build artifacts, and local IDE configurations while keeping pubspec.lock tracked.
