# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
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

### Changed
- Aligned mobile email inputs with the backend's 254-character bound and kept new-account password rules separate from existing-identity sign-in validation.
- Made backend contracts and tests authoritative for mobile behavior; the unfinished Web App remains a visual reference only.
- Kept native cleanup intent and failed-sign-out retry requirements in a shared authentication lifecycle so session-service disposal cannot reopen a discarded identity.
- Aligned account access with backend authorization and time-based block expiry instead of copying the unfinished web client's status-label restriction; the account view reports server-validated access without relabeling stored status.
- Raised the minimum iOS deployment target to 15.0 to meet the Firebase plugins' requirements; Android network access is declared and local cleartext API traffic is debug-only.
- Replaced the starter counter and temporary unauthenticated preview with web-aligned IAM pages, stable guarded routing, and session revalidation when the app resumes.

## [0.1.0] - 2026-11-07

### Changed
- Clarified Flutter contribution standards and agent operating instructions.

### Added
- Initial Flutter application setup configured exclusively for Android and iOS targets.
- GitFlow repository architecture setup with main and develop branches.
- Repository documentation suite: CONTRIBUTING.md, AGENTS.md, LICENSE.md, and CHANGELOG.md.
- Customized .gitignore protecting secrets, local.properties, build artifacts, and local IDE configurations while keeping pubspec.lock tracked.
