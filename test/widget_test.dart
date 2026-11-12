import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/app.dart';
import 'package:ichu_mobile_app/core/theme/ichu_colors.dart';
import 'package:ichu_mobile_app/features/iam/application/services/auth_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_user.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/presentation/pages/login_page.dart';
import 'package:ichu_mobile_app/features/iam/presentation/pages/session_account_page.dart';
import 'package:ichu_mobile_app/shared/application/services/language_service.dart';
import 'package:ichu_mobile_app/shared/domain/model/app_language.dart';

import 'support/fake_iam_repositories.dart';
import 'support/memory_language_preferences.dart';

const _user = AuthUser(
  uid: 'widget-user',
  email: 'user@example.test',
  emailVerified: true,
);
const _account = IamAccount(
  id: '11111111-1111-4111-8111-111111111111',
  email: 'user@example.test',
  role: AccountRole.ranchManager,
  status: 'Active',
);

Future<
  ({
    AuthService auth,
    FakeAuthenticationRepository identity,
    FakeAccountRepository accounts,
  })
>
pumpApp(
  WidgetTester tester, {
  bool configured = true,
  bool restored = false,
  AppLanguage initialLanguage = AppLanguage.english,
  String initialRoute = '/',
  IamAccount account = _account,
  MemoryLanguagePreferences? preferences,
}) async {
  final language = LanguageService(
    preferences ?? MemoryLanguagePreferences(language: initialLanguage),
  );
  await language.initialize();
  final identity = FakeAuthenticationRepository()
    ..isConfigured = configured
    ..user = restored ? _user : null
    ..signInUser = _user;
  final accounts = FakeAccountRepository()
    ..isConfigured = configured
    ..account = account;
  final auth = AuthService(authentication: identity, accounts: accounts);
  addTearDown(() async {
    auth.dispose();
    await identity.close();
    language.dispose();
  });
  await tester.pumpWidget(
    IchuApp(
      language: language,
      authentication: auth,
      initialRoute: initialRoute,
    ),
  );
  await tester.pumpAndSettle();
  return (auth: auth, identity: identity, accounts: accounts);
}

Future<void> fillSignIn(
  WidgetTester tester, {
  String password = ' test-only-password ',
}) async {
  await tester.ensureVisible(find.byKey(const Key('login-email')));
  await tester.enterText(
    find.byKey(const Key('login-email')),
    'user@example.test',
  );
  await tester.ensureVisible(find.byKey(const Key('login-password')));
  await tester.enterText(find.byKey(const Key('login-password')), password);
}

TextField passwordField(WidgetTester tester) => tester.widget<TextField>(
  find.descendant(
    of: find.byKey(const Key('login-password')),
    matching: find.byType(TextField),
  ),
);

void main() {
  test(
    'photo scrim maintains contrast against the brightest possible image pixel',
    () {
      final background = Color.alphaBlend(
        const Color(0xBF193B2A),
        Colors.white,
      );
      expect(
        1.05 / (background.computeLuminance() + 0.05),
        greaterThanOrEqualTo(4.5),
      );
    },
  );

  testWidgets('language options expose their selected state to accessibility', (
    tester,
  ) async {
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
  });

  testWidgets(
    'failed language persistence shows feedback in the selected language',
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
      expect(find.text('Hola de nuevo'), findsOneWidget);
      expect(find.textContaining('no se pudo guardar'), findsOneWidget);
    },
  );

  testWidgets(
    'missing configuration renders a safe real form without simulated data',
    (tester) async {
      tester.binding.platformDispatcher.localeTestValue = const Locale('es');
      addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
      await pumpApp(tester, configured: false);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(
        find.textContaining('Check the Firebase and API settings'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('login-submit')))
            .onPressed,
        isNull,
      );
      expect(find.byType(SessionAccountPage), findsNothing);
      expect(find.text('Mobile preview'), findsNothing);
      final theme = Theme.of(tester.element(find.byType(LoginPage)));
      expect(theme.colorScheme.primary, IchuColors.forest);
      expect(theme.scaffoldBackgroundColor, IchuColors.background);
      expect(theme.textTheme.bodyLarge!.fontFamily, 'PlusJakartaSans');
      expect(theme.textTheme.headlineLarge!.fontFamily, 'Outfit');
    },
  );

  testWidgets(
    'invalid credentials never leave the form or call the identity adapter',
    (tester) async {
      final fixture = await pumpApp(tester);
      await tester.ensureVisible(find.byKey(const Key('login-submit')));
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a valid email address, up to 120 characters.'),
        findsOneWidget,
      );
      expect(find.text('Use 8–128 characters.'), findsOneWidget);
      expect(fixture.auth.status, SessionStatus.signedOut);
      expect(fixture.identity.currentUser, isNull);
      final emailField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('login-email')),
          matching: find.byType(TextField),
        ),
      );
      expect(emailField.focusNode!.hasFocus, isTrue);
    },
  );

  testWidgets(
    'sign-in opens only the validated account and sign-out removes access',
    (tester) async {
      final fixture = await pumpApp(
        tester,
        initialRoute: '/account?returnUrl=https://outside.example',
      );
      expect(find.byType(LoginPage), findsOneWidget);
      await fillSignIn(tester);
      await tester.ensureVisible(find.byKey(const Key('login-submit')));
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();
      expect(fixture.auth.status, SessionStatus.authenticated);
      expect(find.text('Verified account'), findsOneWidget);
      expect(find.text('user@example.test'), findsOneWidget);
      expect(
        find.textContaining('does not currently have authorized ranch access'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(const Key('account-sign-out')));
      await tester.tap(find.byKey(const Key('account-sign-out')));
      await tester.pumpAndSettle();
      expect(find.byType(SessionAccountPage), findsNothing);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(fixture.auth.account, isNull);
    },
  );

  testWidgets('rejected accounts leave no session and clear the password', (
    tester,
  ) async {
    final fixture = await pumpApp(
      tester,
      account: const IamAccount(
        id: '11111111-1111-4111-8111-111111111111',
        email: 'user@example.test',
        role: AccountRole.ranchManager,
        status: 'TemporarilyBlocked',
      ),
    );
    await fillSignIn(tester);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('login-submit')));
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    expect(fixture.auth.account, isNull);
    expect(
      find.textContaining('This ICHU account is unavailable'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('login-password')))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.byType(SessionAccountPage), findsNothing);
    expect(passwordField(tester).obscureText, isTrue);
  });

  testWidgets(
    'password visibility is labeled and backgrounding clears the input',
    (tester) async {
      await pumpApp(tester);
      await fillSignIn(tester);
      expect(passwordField(tester).obscureText, isTrue);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pumpAndSettle();
      expect(passwordField(tester).obscureText, isFalse);
      expect(find.byTooltip('Hide password'), findsOneWidget);
      expect(passwordField(tester).enableIMEPersonalizedLearning, isFalse);
      expect(passwordField(tester).smartQuotesType, SmartQuotesType.disabled);
      expect(passwordField(tester).smartDashesType, SmartDashesType.disabled);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('login-password')))
            .controller!
            .text,
        isEmpty,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(passwordField(tester).obscureText, isTrue);
    },
  );

  testWidgets('restored identity opens only a server-validated account', (
    tester,
  ) async {
    final fixture = await pumpApp(tester, restored: true);
    expect(fixture.auth.status, SessionStatus.authenticated);
    expect(find.text('Verified account'), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets(
    'opening recovery clears credentials in the covered login route',
    (tester) async {
      await pumpApp(tester);
      await fillSignIn(tester);
      await tester.ensureVisible(find.text('Forgot your password?'));
      await tester.tap(find.text('Forgot your password?'));
      await tester.pumpAndSettle();
      final coveredPassword = find.byKey(
        const Key('login-password'),
        skipOffstage: false,
      );
      expect(
        tester.widget<TextFormField>(coveredPassword).controller!.text,
        isEmpty,
      );
      expect(find.text('Reset your password'), findsOneWidget);
    },
  );

  testWidgets('recovery has generic success and clears the submitted address', (
    tester,
  ) async {
    await pumpApp(tester, initialRoute: '/recover');
    await tester.enterText(
      find.byKey(const Key('recovery-email')),
      'user@example.test',
    );
    await tester.ensureVisible(find.byKey(const Key('recovery-submit')));
    await tester.tap(find.byKey(const Key('recovery-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Check your email'), findsOneWidget);
    expect(
      find.textContaining('If the address belongs to an account'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('recovery-email')))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.text('user@example.test'), findsNothing);
    await tester.tap(find.byTooltip('Back to sign in'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets(
    'recovery validates its email and does not imply a reset was sent',
    (tester) async {
      await pumpApp(tester, initialRoute: '/recover');
      await tester.ensureVisible(find.byKey(const Key('recovery-submit')));
      await tester.tap(find.byKey(const Key('recovery-submit')));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a valid email address, up to 120 characters.'),
        findsOneWidget,
      );
      expect(find.text('Check your email'), findsNothing);
    },
  );

  testWidgets('language switching preserves the recovery route and persists', (
    tester,
  ) async {
    final preferences = MemoryLanguagePreferences();
    await pumpApp(tester, initialRoute: '/recover', preferences: preferences);
    await tester.tap(find.byTooltip('Language: English'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<AppLanguage>, 'Español'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Restablece tu contraseña'), findsOneWidget);
    expect(preferences.language, AppLanguage.spanish);
    expect(find.byTooltip('Volver al inicio de sesión'), findsOneWidget);
  });

  testWidgets('terms are public and direct-route back returns to sign-in', (
    tester,
  ) async {
    await pumpApp(
      tester,
      initialRoute: '/terms',
      initialLanguage: AppLanguage.spanish,
    );
    expect(find.text('Términos y privacidad'), findsOneWidget);
    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();
    expect(find.text('Hola de nuevo'), findsOneWidget);
  });

  testWidgets('an unknown route has a safe localized fallback', (tester) async {
    await pumpApp(tester, initialRoute: '/not-a-mobile-page');
    expect(find.text('Page not found'), findsOneWidget);
    expect(find.byType(SessionAccountPage), findsNothing);
  });

  for (final route in ['/login', '/recover', '/terms', '/account']) {
    for (final size in [
      const Size(320, 568),
      const Size(640, 360),
      const Size(800, 1024),
    ]) {
      testWidgets('$route supports Spanish at 200% text on $size', (
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
          initialRoute: route,
          restored: route == '/account',
          initialLanguage: AppLanguage.spanish,
        );
        expect(tester.takeException(), isNull);
        if (route == '/login') {
          await tester.ensureVisible(find.byKey(const Key('login-password')));
          await tester.ensureVisible(find.byKey(const Key('login-submit')));
        } else if (route == '/account') {
          await tester.ensureVisible(find.byKey(const Key('account-sign-out')));
        } else if (route == '/recover') {
          await tester.ensureVisible(find.byKey(const Key('recovery-submit')));
        } else {
          await tester.ensureVisible(find.text('Volver'));
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('$route controls meet accessibility guidelines', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await pumpApp(
          tester,
          initialRoute: route,
          restored: route == '/account',
        );
        expect(tester, meetsGuideline(androidTapTargetGuideline));
        expect(tester, meetsGuideline(iOSTapTargetGuideline));
        expect(tester, meetsGuideline(labeledTapTargetGuideline));
        expect(tester, meetsGuideline(textContrastGuideline));
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('a phone can scroll password entry above the software keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await pumpApp(tester);
    await tester.ensureVisible(find.byKey(const Key('login-password')));
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'test-only-password',
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byKey(const Key('login-password'))).bottom,
      lessThanOrEqualTo(360),
    );
  });
}
