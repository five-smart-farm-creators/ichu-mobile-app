import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/app.dart';
import 'package:ichu_mobile_app/core/config/app_config.dart';
import 'package:ichu_mobile_app/core/theme/ichu_colors.dart';
import 'package:ichu_mobile_app/features/iam/presentation/pages/welcome_page.dart';
import 'package:ichu_mobile_app/shared/application/services/language_service.dart';
import 'package:ichu_mobile_app/shared/domain/model/app_language.dart';

import 'support/memory_language_preferences.dart';

Future<LanguageService> pumpApp(
  WidgetTester tester, {
  MemoryLanguagePreferences? preferences,
  AppConfig? config,
  String initialRoute = '/',
}) async {
  final language = LanguageService(preferences ?? MemoryLanguagePreferences());
  addTearDown(language.dispose);
  await language.initialize();
  await tester.pumpWidget(
    IchuApp(
      language: language,
      config: config ?? AppConfig.fromValues(),
      initialRoute: initialRoute,
    ),
  );
  await tester.pumpAndSettle();
  return language;
}

void main() {
  testWidgets('opens in English even when the device uses Spanish', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localeTestValue = const Locale('es');
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
    await pumpApp(tester);

    expect(find.text('Welcome to ICHU'), findsOneWidget);
    expect(find.text('Mobile preview'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Flutter Demo'), findsNothing);
    expect(find.textContaining('API settings have not'), findsOneWidget);
    final context = tester.element(find.byType(WelcomePage));
    expect(Theme.of(context).colorScheme.primary, IchuColors.forest);
    expect(Theme.of(context).scaffoldBackgroundColor, IchuColors.background);
    expect(
      Theme.of(context).textTheme.bodyLarge!.fontFamily,
      'PlusJakartaSans',
    );
    expect(Theme.of(context).textTheme.headlineLarge!.fontFamily, 'Outfit');
  });

  testWidgets('language selection updates the screen and persists', (
    tester,
  ) async {
    final preferences = MemoryLanguagePreferences();
    await pumpApp(tester, preferences: preferences);
    await tester.tap(find.byTooltip('Language: English'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<AppLanguage>, 'Español'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Te damos la bienvenida a ICHU'), findsOneWidget);
    expect(find.text('Vista previa móvil'), findsOneWidget);
    expect(preferences.language, AppLanguage.spanish);

    await tester.tap(find.byTooltip('Idioma: Español'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<AppLanguage>, 'English'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Welcome to ICHU'), findsOneWidget);
    expect(preferences.language, AppLanguage.english);
  });

  testWidgets(
    'restores saved Spanish and localizes terms and back navigation',
    (tester) async {
      await pumpApp(
        tester,
        preferences: MemoryLanguagePreferences(language: AppLanguage.spanish),
      );
      await tester.ensureVisible(find.text('Términos y privacidad'));
      await tester.tap(find.text('Términos y privacidad'));
      await tester.pumpAndSettle();
      expect(find.text('Preferencias del dispositivo'), findsOneWidget);
      await tester.tap(find.byTooltip('Volver al inicio'));
      await tester.pumpAndSettle();
      expect(find.text('Te damos la bienvenida a ICHU'), findsOneWidget);
    },
  );

  testWidgets('terms can be opened directly without authentication', (
    tester,
  ) async {
    await pumpApp(tester, initialRoute: '/terms');
    expect(find.text('Terms and privacy'), findsOneWidget);
    expect(find.text('Device preferences'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to welcome'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to ICHU'), findsOneWidget);
  });

  testWidgets('terms follow a language change without resetting navigation', (
    tester,
  ) async {
    await pumpApp(tester, initialRoute: '/terms');
    await tester.tap(find.byTooltip('Language: English'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<AppLanguage>, 'Español'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Términos y privacidad'), findsOneWidget);
    expect(find.byTooltip('Volver al inicio'), findsOneWidget);
  });

  testWidgets(
    'failed preference writes keep the selected language and show feedback',
    (tester) async {
      await pumpApp(
        tester,
        preferences: MemoryLanguagePreferences()..failWrite = true,
      );
      await tester.tap(find.byTooltip('Language: English'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<AppLanguage>, 'Español'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Te damos la bienvenida a ICHU'), findsOneWidget);
      expect(find.textContaining('no se pudo guardar'), findsOneWidget);
    },
  );

  testWidgets('invalid configuration exposes no raw endpoint or credentials', (
    tester,
  ) async {
    await pumpApp(
      tester,
      config: AppConfig.fromValues(
        apiBaseUrl: 'https://user:password@example.com',
      ),
    );
    expect(
      find.textContaining('API settings for this build are not valid'),
      findsOneWidget,
    );
    expect(find.textContaining('password'), findsNothing);
    expect(find.textContaining('example.com'), findsNothing);
  });

  testWidgets(
    'valid API configuration does not simulate account availability',
    (tester) async {
      await pumpApp(
        tester,
        config: AppConfig.fromValues(apiBaseUrl: 'https://api.example.com'),
      );
      expect(
        find.textContaining('Sign-in and account management are not available'),
        findsOneWidget,
      );
      expect(find.textContaining('API settings have not'), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
    },
  );

  for (final size in [
    const Size(320, 568),
    const Size(360, 640),
    const Size(640, 360),
    const Size(800, 1024),
  ]) {
    testWidgets('Spanish welcome and terms scroll at 200% text on $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
      await pumpApp(
        tester,
        preferences: MemoryLanguagePreferences(language: AppLanguage.spanish),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Términos y privacidad'));
      await tester.tap(find.text('Términos y privacidad'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Volver al inicio'));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Volver al inicio'));
      await tester.pumpAndSettle();
      expect(find.text('Te damos la bienvenida a ICHU'), findsOneWidget);
    });
  }

  testWidgets('invalid environment shows a safe notice without its raw value', (
    tester,
  ) async {
    await pumpApp(
      tester,
      config: AppConfig.fromValues(environment: 'unsafe-environment-value'),
    );
    expect(
      find.textContaining('environment settings for this build are not valid'),
      findsOneWidget,
    );
    expect(find.textContaining('unsafe-environment-value'), findsNothing);
  });

  testWidgets(
    'language menu exposes its checked state to assistive technology',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await pumpApp(tester);
        await tester.tap(find.byTooltip('Language: English'));
        await tester.pumpAndSettle();
        final english = find.widgetWithText(
          CheckedPopupMenuItem<AppLanguage>,
          'English',
        );
        final spanish = find.widgetWithText(
          CheckedPopupMenuItem<AppLanguage>,
          'Español',
        );
        expect(
          tester
              .getSemantics(english)
              .getSemanticsData()
              .flagsCollection
              .isChecked,
          ui.CheckedState.isTrue,
        );
        expect(
          tester
              .getSemantics(spanish)
              .getSemanticsData()
              .flagsCollection
              .isChecked,
          ui.CheckedState.isFalse,
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  test('photo scrim provides at least 4.5:1 contrast over a white pixel', () {
    final background = Color.alphaBlend(const Color(0xBF193B2A), Colors.white);
    expect(
      1.05 / (background.computeLuminance() + 0.05),
      greaterThanOrEqualTo(4.5),
    );
  });

  for (final route in ['/', '/terms']) {
    testWidgets(
      '$route controls meet accessibility target and label guidelines',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await pumpApp(tester, initialRoute: route);
          expect(tester, meetsGuideline(androidTapTargetGuideline));
          expect(tester, meetsGuideline(iOSTapTargetGuideline));
          expect(tester, meetsGuideline(labeledTapTargetGuideline));
          expect(tester, meetsGuideline(textContrastGuideline));
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
