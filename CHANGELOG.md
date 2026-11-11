# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Framework-independent IAM identity/account/access contracts, safe authentication failures, and shared credential input rules.
- Native Firebase, HTTP, and guarded-routing dependencies, with an example for approved public client settings and ignored local overrides.
- Validated, non-secret API build configuration with HTTPS enforcement outside local development and no default production endpoint.
- English and Latin American Spanish catalogs, with generated localizations and equal-key checks.
- A device language preference with English fallback, session-only recovery on storage failures, and ordered writes that prevent stale preferences after timeouts.
- Bundled Outfit and Plus Jakarta Sans fonts with their licenses, plus optimized brand imagery from the web application.
- Public mobile welcome and terms pages with localized preview notices, scrolling, safe areas, and language selection that preserves navigation.
- Widget coverage for public navigation, safe configuration notices, large text, screen-reader language selection, and accessibility guidelines.
- Documented inward-facing DDD boundaries, configuration setup, mobile accessibility expectations, and bundled asset/font provenance.

### Changed
- Raised the minimum iOS deployment target to 15.0 to meet the Firebase plugins' requirements; Android network access is declared and local cleartext API traffic is debug-only.
- Replaced the starter counter with an explicitly unauthenticated ICHU preview using the web palette and mobile-adapted brand styling.

## [0.1.0] - 2026-11-07

### Changed
- Clarified Flutter contribution standards and agent operating instructions.

### Added
- Initial Flutter application setup configured exclusively for Android and iOS targets.
- GitFlow repository architecture setup with main and develop branches.
- Repository documentation suite: CONTRIBUTING.md, AGENTS.md, LICENSE.md, and CHANGELOG.md.
- Customized .gitignore protecting secrets, local.properties, build artifacts, and local IDE configurations while keeping pubspec.lock tracked.
