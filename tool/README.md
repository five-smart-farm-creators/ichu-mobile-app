# Mobile screenshot fixture runner

`mobile_demo_main.dart` launches the actual Flutter presentation layer with local fake repositories and fixed synthetic data. A visible banner identifies the screenshots as **demonstration captures with synthetic data**; the advisory grant form and revocation dialog repeat the disclosure inside those overlays. It does not initialize Firebase, contact the API, represent a production build, or provide evidence of user acceptance.

Run it on an Android emulator with a desired initial route:

```sh
flutter run --target tool/mobile_demo_main.dart -d emulator-5554 --dart-define=ICHU_DEMO_ROUTE=/account/alerts
```

Available authenticated sample routes include `/account`, `/account/animals`, `/account/alerts`, `/account/field-records`, and `/account/advisories`. Authentication and the selected ranch are test fixtures; never use this runner for production or release distribution.
