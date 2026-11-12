# Contributing

Thank you for contributing to ICHU Mobile App. This guide describes the skills, workflow, and quality standards for changes to the Flutter project.

## Prerequisites

- Dart and Flutter versions compatible with the constraints in pubspec.yaml.
- Git and familiarity with branches, commits, and pull requests.
- Android Studio and the Android SDK to build and run Android.
- macOS and Xcode to build and run iOS.

## Local setup

~~~sh
git clone --branch develop https://github.com/five-smart-farm-creators/ichu-mobile-app.git
cd ichu-mobile-app
flutter pub get
flutter doctor
flutter run
~~~

The available device determines the target for flutter run. iOS builds require macOS and Xcode.

## Project structure and code quality

- Keep shared Flutter application code in lib/, automated tests in test/, and native platform configuration in android/ or ios/.
- Android and iOS are the only supported targets. Do not add or restore web or desktop platform folders.
- Follow Effective Dart, the configured lints in analysis_options.yaml, and the existing project structure.
- Use lowercase_with_underscores for Dart filenames, UpperCamelCase for types, and lowerCamelCase for members, parameters, and variables. Follow Dart conventions for private identifiers.
- Keep widgets focused. Reuse existing widgets, themes, styles, services, and helpers when they fit; avoid duplicated behavior and unnecessary dependencies.
- Create directories and abstractions only when required by the feature and consistent with the existing structure.
- Keep source identifiers, comments, and documentation in English. User-facing text must follow product language requirements and the existing localization approach, if one is present.
- Use concise Dart comments: /// for useful public API documentation and // for implementation notes. Explain non-obvious intent; do not narrate clear code.
- Keep pubspec.lock tracked. Do not commit secrets, signing credentials, local.properties, Xcode user data, caches, or build output.

Before submitting code changes, run:

~~~sh
flutter analyze
flutter test
~~~

Add or update tests for changed behavior. Report any checks that could not be run.

### DDD boundaries and Flutter composition

- Organize authorized business capabilities under `lib/features/<context>/`, using Dart `lowercase_with_underscores` names. IAM is the current implemented context; do not create the other product contexts or unused folders speculatively.
- Add `domain/model/` and `domain/repositories/` when models and ports are required. Keep domain code plain Dart: no Flutter, Firebase, platform storage, HTTP clients, or transport serialization.
- Put use-case coordination in `application/`, adapters in `infrastructure/`, and pages/widgets in `presentation/`. Widgets call application services rather than platform adapters. Future cross-context collaboration must use explicit application facades, not another context's internals.
- Keep bootstrap, deployment settings, app-wide layout, and theme in `lib/core/` and the app entrypoints. Keep `lib/shared/` business-neutral; do not move IAM rules there for convenience.
- Use constructor injection and the existing Flutter notification approach. Introduce routing/state packages only for demonstrated requirements, not to recreate Angular or ASP.NET structure mechanically.
- Reuse the explicit palette in `IchuColors` and `IchuTheme`. Preserve the web brand while adapting layout, navigation, touch targets, and scrolling to mobile. Do not add a dark theme without an approved design.
- Treat the backend's implemented contracts, domain rules, and tests as the functional source of truth. The web client is unfinished and is a visual reference, not authority for available capabilities or business policy. Do not copy client-side restrictions that contradict the backend.
- Identify test fixtures as fixtures. Do not show fake sessions or records as a real integration, and do not claim live REST verification unless the backend was reachable and the calls were actually made.

### Localization and accessibility

- English is the default and source catalog. Use neutral Latin American Spanish with correct accents. Localize all user-visible text through the generated `AppLocalizations`; product names and language endonyms are intentional exceptions.
- Keep identical message keys in `lib/shared/infrastructure/i18n/app_en.arb` and `app_es.arb`. Declare placeholders in the English template. Run `flutter gen-l10n` after changing catalogs; generated Dart is ignored and must not be hand-edited.
- Keep non-sensitive language preferences separate from authentication data. A storage failure must not prevent opening the app.
- Preserve text scaling and native safe areas. Use scrollable content, labeled controls, and at least 48 logical-pixel touch targets. Test narrow screens, landscape, and large text in both languages.
- Bundle licensed brand assets/fonts instead of downloading them at runtime. Keep provenance and third-party licenses accurate in `assets/README.md` and the font folders.

## Git Flow

Use main for release history and develop for integration. Do not commit directly to either branch.

| Branch | Start from | Pull request target |
| --- | --- | --- |
| feature/<short-description> | develop | develop |
| bugfix/<short-description> | develop | develop |
| release/vX.Y.Z | develop | main, then merge back into develop |
| hotfix/vX.Y.Z | main | main, then merge back into develop |

Use lowercase kebab-case branch descriptions. Keep branches focused and delete topic branches after they are merged.

Never open a pull request from `develop` to `main`; releases always go through `release/vX.Y.Z`. Do not use other branch prefixes, such as `fix/`, `docs/`, `refactor/`, `chore/`, or `audit/`.

~~~sh
git switch develop
git pull --ff-only origin develop
git switch -c feature/short-description
~~~

## Commit messages

Write commit messages in English using Conventional Commits:

~~~text
<type>(<scope>): <imperative summary>
~~~

Keep each commit focused and the summary concise, without a trailing period. Common types include feat, fix, docs, style, refactor, perf, test, build, ci, chore, and revert.

~~~text
feat(cattle-information): add cattle overview
fix(iam): handle expired sessions
docs: clarify local setup
~~~

Commit messages must also follow these rules:

- Start the summary with a lowercase letter, and keep the header at most 72 characters.
- Use only these scopes: `iam`, `cattle-information`, `iot-assets`, `operations-monitoring`, `planning`, `dashboard-analytics`, `subscription-plans`, `shared`, `i18n`.
- Use `feat` only for new functionality, `docs` for documentation and diagram changes, and `chore` for changelog, version, or maintenance changes.
- Do not use the default message of the GitHub web editor, such as `Update file.md`.

Invalid examples:

~~~text
(Docs): Add user personas
Update chapter02.md
feat: add controllers.
faet: add planning service
~~~

## Changelog

Record each logical code, configuration, architecture, or documentation change in CHANGELOG.md under [Unreleased]. Use the applicable Keep a Changelog category and describe the user-visible effect; do not list commit hashes.

## Pull requests

Open feature and bugfix pull requests against develop. Include the purpose, a concise summary, relevant checks, and screenshots for user interface changes. Link related issues when applicable, address review feedback, and do not merge until the required review and checks are complete.

## Commit granularity

A commit is one complete logical change that can be described in a single sentence and leaves the project working.

| Too fine | Balanced | Too coarse |
| --- | --- | --- |
| One commit per folder or file (`feat: add commands models`, `feat: add events models`, ...) | `feat(iot-assets): add device aggregate with commands and events` | `feat: implement iot assets` (a whole bounded context) |
| Several consecutive typo commits | `docs(chapter-ii): add segment 1 interview analysis` | `docs: update report` |

- Code: a feature branch usually has 3 to 8 commits of roughly 3 to 10 files each, split by layer or use case (for example domain model, persistence, REST endpoints, tests).
- Documentation: one commit per complete artifact or section, not per paragraph and not per whole chapter.
- Group typo fixes with the section they belong to; a later round of fixes goes in a single `docs(<scope>): fix typos in <section>` commit.
- Before pushing a branch that only you use, squash local work-in-progress commits into logical commits. Never rewrite commits that are already published.
- The convention is enforced for commits created from 2026-11-07, when it was adopted; older history is kept unchanged.

## Enforcement

- After cloning, run once: `git config core.hooksPath .githooks`. The `commit-msg` hook rejects invalid messages locally.
- The `Git Flow checks` GitHub Actions workflow validates the branch name, the pull request target, and every commit message on pull requests to `main` and `develop`.
- Configure Git with your real name and the email linked to your GitHub account (`git config user.name` and `git config user.email`). `.mailmap` maps previously used alternative identities.
