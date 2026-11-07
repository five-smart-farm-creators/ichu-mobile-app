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

## Enforcement

- After cloning, run once: `git config core.hooksPath .githooks`. The `commit-msg` hook rejects invalid messages locally.
- The `Git Flow checks` GitHub Actions workflow validates the branch name, the pull request target, and every commit message on pull requests to `main` and `develop`.
- Configure Git with your real name and the email linked to your GitHub account (`git config user.name` and `git config user.email`). `.mailmap` maps previously used alternative identities.
