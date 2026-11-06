# ICHU Mobile App

[![Flutter stable](https://img.shields.io/badge/Flutter-stable-02569B?style=flat&logo=flutter&logoColor=white)](https://flutter.dev/)
[![Dart SDK ^3.12.2](https://img.shields.io/badge/Dart%20SDK-%5E3.12.2-0175C2?style=flat&logo=dart&logoColor=white)](https://dart.dev/)
[![Android](https://img.shields.io/badge/Platform-Android-3DDC84?style=flat&logo=android&logoColor=white)](https://developer.android.com/)
[![iOS](https://img.shields.io/badge/Platform-iOS-000000?style=flat&logo=apple&logoColor=white)](https://developer.apple.com/ios/)

Flutter client for ICHU, SmartFarm’s livestock management platform, targeting Android and iOS. The repository currently contains the initial Flutter scaffold.

## Run locally

Install Flutter SDK (with Dart SDK `^3.12.2`) and Git, then run:

```bash
git clone --branch develop https://github.com/five-smart-farm-creators/ichu-mobile-app.git
cd ichu-mobile-app
flutter pub get
flutter run
```

`flutter run` executes the application on the detected target device or emulator (e.g., Android on Windows or macOS). Building and running for iOS requires macOS and Xcode.

## Repository structure

```
ichu-mobile-app/
├── android/
├── ios/
├── lib/
│   └── main.dart
├── test/
│   └── widget_test.dart
├── analysis_options.yaml
├── pubspec.yaml
├── pubspec.lock
├── CONTRIBUTING.md
├── AGENTS.md
├── CHANGELOG.md
├── LICENSE.md
└── README.md
```

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) for setup, coding standards, GitFlow, Conventional Commits, and pull request requirements. Write source code, comments, documentation, and commit messages in English.

## License

Copyright (c) 2026 SmartFarm. All rights reserved. See [LICENSE.md](LICENSE.md) for terms.
