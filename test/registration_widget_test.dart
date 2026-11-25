import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/core/theme/ichu_theme.dart';
import 'package:ichu_mobile_app/features/iam/application/services/authentication_lifecycle.dart';
import 'package:ichu_mobile_app/features/iam/application/services/registration_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/account_registration_result.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_failure.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_user.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/presentation/pages/registration_page.dart';
import 'package:ichu_mobile_app/shared/application/services/language_service.dart';
import 'package:ichu_mobile_app/shared/domain/model/app_language.dart';
import 'package:ichu_mobile_app/shared/infrastructure/i18n/generated/app_localizations.dart';

import 'support/fake_registration_repositories.dart';
import 'support/memory_language_preferences.dart';

void main() {
  testWidgets('missing configuration blocks registration submission', (
    tester,
  ) async {
    final fixture = await _pumpRegistration(
      tester,
      identityConfigured: false,
      accountsConfigured: false,
    );

    final submit = find.byKey(const Key('registration-submit'));
    expect(submit, findsOneWidget);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    expect(
      find.text(
        'Account access is unavailable. Check the Firebase and API settings for this build.',
      ),
      findsOneWidget,
    );
    expect(fixture.identity.createUserCalls, 0);
    expect(fixture.accounts.registerCalls, 0);
  });

  testWidgets('invalid email and mismatched confirmation call no adapter', (
    tester,
  ) async {
    final fixture = await _pumpRegistration(tester);

    await _enterField(tester, 'registration-email', 'not-an-email');
    await _enterField(tester, 'registration-password', 'test-only-password');
    await _enterField(
      tester,
      'registration-confirmation',
      'test-only-password',
    );
    await _tap(tester, find.byKey(const Key('registration-submit')));
    expect(
      find.text('Enter a valid email address, up to 254 characters.'),
      findsOneWidget,
    );
    expect(fixture.identity.createUserCalls, 0);

    await _enterField(tester, 'registration-email', 'new-user@example.test');
    await _enterField(
      tester,
      'registration-confirmation',
      'different-test-only-password',
    );
    await _tap(tester, find.byKey(const Key('registration-submit')));

    expect(find.text('The passwords must match.'), findsOneWidget);
    expect(fixture.identity.createUserCalls, 0);
    expect(fixture.identity.sendVerificationCalls, 0);
    expect(fixture.accounts.registerCalls, 0);
  });

  testWidgets(
    'identity creation sends verification but waits before any backend request',
    (tester) async {
      final fixture = await _pumpRegistration(tester);
      await _enterCredentials(tester);
      final password = _textField(tester, 'registration-password').controller!;
      final confirmation = _textField(
        tester,
        'registration-confirmation',
      ).controller!;

      await _tap(tester, find.byKey(const Key('registration-submit')));

      expect(fixture.service.status, RegistrationStatus.awaitingVerification);
      expect(fixture.service.verificationSent, isTrue);
      expect(fixture.identity.createUserCalls, 1);
      expect(fixture.identity.lastCreateEmail, 'new-user@example.test');
      expect(fixture.identity.sendVerificationCalls, 1);
      expect(fixture.accounts.registerCalls, 0);
      expect(fixture.accounts.currentAccountCalls, 0);
      expect(find.text('Verify your email'), findsOneWidget);
      expect(
        find.text(
          'A verification email was requested. Check your inbox and spam folder.',
        ),
        findsOneWidget,
      );
      expect(find.text('new-user@example.test'), findsOneWidget);
      expect(password.text, isEmpty);
      expect(confirmation.text, isEmpty);
    },
  );

  testWidgets('role selection is explicit and excludes field operator', (
    tester,
  ) async {
    final fixture = await _pumpRegistration(tester);
    await _createPendingIdentity(tester);

    await _tap(tester, find.byKey(const Key('registration-complete')));
    expect(find.text('Select a role to continue.'), findsOneWidget);
    expect(fixture.accounts.registerCalls, 0);

    final role = find.byType(DropdownButtonFormField<AccountRole>);
    await tester.ensureVisible(role);
    await tester.tap(role);
    await tester.pumpAndSettle();
    expect(find.text('Veterinarian'), findsWidgets);
    expect(find.text('Ranch manager'), findsWidgets);
    expect(find.text('Field operator'), findsNothing);
    expect(fixture.accounts.registerCalls, 0);
    expect(find.byKey(const Key('registration-ranch-name')), findsNothing);
    await tester.tap(find.text('Veterinarian').last);
    await tester.pumpAndSettle();
  });

  testWidgets('unverified identity cannot reach account creation', (
    tester,
  ) async {
    final fixture = await _pumpRegistration(tester);
    await _createPendingIdentity(tester);
    await _chooseRole(tester, 'Veterinarian');

    await _tap(tester, find.byKey(const Key('registration-complete')));

    expect(fixture.identity.reloadUserCalls, 1);
    expect(fixture.accounts.registerCalls, 0);
    expect(fixture.service.status, RegistrationStatus.awaitingVerification);
    expect(fixture.service.error?.code, AuthFailureCode.emailNotVerified);
    expect(
      find.textContaining('Your email is not verified yet.'),
      findsOneWidget,
    );
  });

  testWidgets('manager fields validate before creating the account', (
    tester,
  ) async {
    final fixture = await _pumpRegistration(tester);
    await _createPendingIdentity(tester);
    await _chooseRole(tester, 'Ranch manager');
    expect(_textField(tester, 'registration-ranch-name').maxLength, 160);
    expect(_textField(tester, 'registration-region').maxLength, 120);
    expect(_textField(tester, 'registration-district').maxLength, 120);

    await _tap(tester, find.byKey(const Key('registration-complete')));
    expect(find.text('Enter 1–160 characters.'), findsOneWidget);
    expect(find.text('Enter 1–120 characters.'), findsNWidgets(2));
    expect(
      find.text('Enter a whole number between 0 and 2147483647.'),
      findsOneWidget,
    );
    expect(fixture.accounts.registerCalls, 0);

    await _enterField(tester, 'registration-ranch-name', 'North pasture');
    await _enterField(tester, 'registration-region', 'Northern region');
    await _enterField(tester, 'registration-district', 'West district');
    await _enterField(tester, 'registration-head-count', '2147483648');
    await _tap(tester, find.byKey(const Key('registration-complete')));
    expect(
      find.text('Enter a whole number between 0 and 2147483647.'),
      findsOneWidget,
    );
    expect(fixture.accounts.registerCalls, 0);

    await _enterField(tester, 'registration-head-count', '0');
    fixture.identity
      ..overrideReloadUserResult = true
      ..reloadUserResult = _verifiedIdentity;
    fixture.accounts.result = _registrationResult(
      email: 'new-user@example.test',
      role: AccountRole.ranchManager,
    );
    await _tap(tester, find.byKey(const Key('registration-complete')));

    expect(fixture.accounts.registerCalls, 1);
    expect(fixture.accounts.currentAccountCalls, 0);
    expect(fixture.identity.reloadUserCalls, 1);
    expect(fixture.accounts.requests.single.email, 'new-user@example.test');
    expect(
      fixture.accounts.requests.single.details.role,
      AccountRole.ranchManager,
    );
    expect(
      fixture.accounts.requests.single.details.ranch?.estimatedHeadCount,
      0,
    );
    expect(fixture.service.status, RegistrationStatus.completed);
    expect(fixture.service.account?.role, AccountRole.ranchManager);
    expect(fixture.identity.signOutCalls, 1);
    expect(fixture.identity.currentUser, isNull);
    expect(find.text('Your ICHU account is registered'), findsOneWidget);
    expect(
      find.textContaining('Registration alone does not open a workspace.'),
      findsOneWidget,
    );
  });

  testWidgets('a second submit cannot duplicate an in-flight POST', (
    tester,
  ) async {
    final fixture = await _pumpRegistration(tester);
    await _createPendingIdentity(tester);
    await _chooseRole(tester, 'Veterinarian');
    fixture.identity
      ..overrideReloadUserResult = true
      ..reloadUserResult = _verifiedIdentity;
    fixture.accounts
      ..result = _registrationResult(
        email: 'new-user@example.test',
        role: AccountRole.veterinarian,
      )
      ..registerCompleter = Completer<AccountRegistrationResult>();

    final submit = find.byKey(const Key('registration-complete'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();

    expect(fixture.service.status, RegistrationStatus.completing);
    expect(fixture.accounts.registerCalls, 1);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    fixture.accounts.registerCompleter!.complete(
      _registrationResult(
        email: 'new-user@example.test',
        role: AccountRole.veterinarian,
      ),
    );
    await tester.pumpAndSettle();
    expect(fixture.accounts.registerCalls, 1);
    expect(fixture.service.status, RegistrationStatus.completed);
  });

  testWidgets(
    'verification delivery failure can be resent without recreating',
    (tester) async {
      final fixture = await _pumpRegistration(tester);
      fixture.identity.sendVerificationFailure = StateError(
        'private mail detail',
      );
      await _enterCredentials(tester);

      await _tap(tester, find.byKey(const Key('registration-submit')));

      expect(fixture.identity.createUserCalls, 1);
      expect(fixture.identity.sendVerificationCalls, 1);
      expect(fixture.service.status, RegistrationStatus.awaitingVerification);
      expect(fixture.service.user, isNotNull);
      expect(fixture.accounts.registerCalls, 0);
      expect(find.byKey(const Key('registration-resend')), findsOneWidget);
      expect(find.textContaining('private mail detail'), findsNothing);

      fixture.identity.sendVerificationFailure = null;
      await _tap(tester, find.byKey(const Key('registration-resend')));

      expect(fixture.identity.createUserCalls, 1);
      expect(fixture.identity.sendVerificationCalls, 2);
      expect(fixture.service.verificationSent, isTrue);
      expect(fixture.accounts.registerCalls, 0);
    },
  );

  for (final failure in <AuthFailure>[
    const AuthFailure(AuthFailureCode.network),
    const AuthFailure(AuthFailureCode.accountAlreadyExists),
  ]) {
    testWidgets('uncertain or conflicting POST reconciles without replay '
        '(${failure.code.name})', (tester) async {
      final fixture = await _pumpRegistration(tester);
      await _createPendingIdentity(tester);
      await _chooseRole(tester, 'Veterinarian');
      fixture.identity
        ..overrideReloadUserResult = true
        ..reloadUserResult = _verifiedIdentity;
      fixture.accounts
        ..registerFailure = failure
        ..currentAccountFailure = const AuthFailure(
          AuthFailureCode.accountUnavailable,
        );

      await _tap(tester, find.byKey(const Key('registration-complete')));

      expect(fixture.accounts.registerCalls, 1);
      expect(fixture.service.needsReconciliation, isTrue);
      expect(find.text('Check existing registration'), findsOneWidget);
      expect(
        find.textContaining('The last request may have created your account.'),
        findsOneWidget,
      );
      expect(find.byType(DropdownButtonFormField<AccountRole>), findsNothing);

      await _tap(tester, find.byKey(const Key('registration-complete')));

      expect(fixture.accounts.currentAccountCalls, 1);
      expect(fixture.accounts.registerCalls, 1);
      expect(fixture.service.needsReconciliation, isTrue);
      expect(find.byKey(const Key('registration-complete')), findsOneWidget);
    });
  }

  testWidgets('adapter errors are generic and announced as a live region', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final fixture = await _pumpRegistration(tester);
      fixture.identity.createUserFailure = StateError(
        'private token and test-only-password',
      );
      await _enterCredentials(tester);

      await _tap(tester, find.byKey(const Key('registration-submit')));

      const safeMessage =
          'The service is temporarily unavailable. Try again later.';
      expect(find.text(safeMessage), findsOneWidget);
      expect(find.textContaining('private token'), findsNothing);
      expect(find.textContaining('test-only-password'), findsNothing);
      expect(
        find.ancestor(
          of: find.text(safeMessage),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.liveRegion == true,
          ),
        ),
        findsOneWidget,
      );
      expect(fixture.accounts.registerCalls, 0);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('an existing isolated identity resumes without resending mail', (
    tester,
  ) async {
    final fixture = await _pumpRegistration(
      tester,
      currentIdentity: syntheticRegistrationUser,
    );

    expect(fixture.service.status, RegistrationStatus.awaitingVerification);
    expect(fixture.service.user, syntheticRegistrationUser);
    expect(find.text('Verify your email'), findsOneWidget);
    expect(find.text(syntheticRegistrationUser.email), findsOneWidget);
    expect(find.byKey(const Key('registration-password')), findsNothing);
    expect(fixture.identity.createUserCalls, 0);
    expect(fixture.identity.sendVerificationCalls, 0);
    expect(fixture.accounts.registerCalls, 0);
  });

  testWidgets('resuming registration signs in without creating or resending', (
    tester,
  ) async {
    final fixture = await _pumpRegistration(tester);

    await _tap(tester, find.text('I already started registration'));
    expect(find.byKey(const Key('registration-confirmation')), findsNothing);
    await _enterField(tester, 'registration-email', 'resume-user@example.test');
    await _enterField(tester, 'registration-password', 'test-only-password');
    final password = _textField(tester, 'registration-password').controller!;
    await _tap(tester, find.byKey(const Key('registration-submit')));

    expect(fixture.identity.signInCalls, 1);
    expect(fixture.identity.createUserCalls, 0);
    expect(fixture.identity.sendVerificationCalls, 0);
    expect(fixture.accounts.registerCalls, 0);
    expect(fixture.service.status, RegistrationStatus.awaitingVerification);
    expect(find.text('resume-user@example.test'), findsOneWidget);
    expect(password.text, isEmpty);
  });

  testWidgets('cancel signs out the isolated identity without deleting it', (
    tester,
  ) async {
    final fixture = await _pumpRegistration(tester);
    await _createPendingIdentity(tester);

    await _tap(tester, find.text('Cancel registration'));

    expect(fixture.identity.signOutCalls, 1);
    expect(fixture.identity.currentUser, isNull);
    expect(fixture.service.status, RegistrationStatus.idle);
    expect(fixture.accounts.registerCalls, 0);
  });

  testWidgets('passwords clear on background and before opening terms', (
    tester,
  ) async {
    final fixture = await _pumpRegistration(tester);
    await _enterCredentials(tester);
    await _tap(tester, find.byTooltip('Show password'));
    expect(_textField(tester, 'registration-password').obscureText, isFalse);
    expect(find.byTooltip('Hide password'), findsOneWidget);
    expect(
      _textField(tester, 'registration-password').enableIMEPersonalizedLearning,
      isFalse,
    );
    expect(
      _textField(
        tester,
        'registration-confirmation',
      ).enableIMEPersonalizedLearning,
      isFalse,
    );
    expect(
      _textField(tester, 'registration-password').smartQuotesType,
      SmartQuotesType.disabled,
    );
    expect(
      _textField(tester, 'registration-password').smartDashesType,
      SmartDashesType.disabled,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(
      _textField(tester, 'registration-password').controller!.text,
      isEmpty,
    );
    expect(
      _textField(tester, 'registration-confirmation').controller!.text,
      isEmpty,
    );
    expect(_textField(tester, 'registration-password').obscureText, isTrue);
    expect(find.byTooltip('Show password'), findsOneWidget);

    await _enterCredentials(tester);
    await _tap(tester, find.text('Terms and privacy'));
    expect(fixture.termsOpened(), isTrue);
    expect(
      _textField(tester, 'registration-password').controller!.text,
      isEmpty,
    );
    expect(
      _textField(tester, 'registration-confirmation').controller!.text,
      isEmpty,
    );
  });

  for (final language in <AppLanguage>[
    AppLanguage.english,
    AppLanguage.spanish,
  ]) {
    final isSpanish = language == AppLanguage.spanish;
    final title = isSpanish
        ? 'Crea tu cuenta de ICHU'
        : 'Create your ICHU account';
    final managerLabel = isSpanish ? 'Administrador ganadero' : 'Ranch manager';
    final languageName = isSpanish ? 'Spanish' : 'English';
    for (final size in <Size>[const Size(320, 568), const Size(640, 360)]) {
      testWidgets('$languageName registration at 200% on $size', (
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

        await _pumpRegistration(tester, initialLanguage: language);
        expect(find.text(title), findsOneWidget);
        expect(find.byType(SafeArea), findsOneWidget);
        expect(find.byType(SingleChildScrollView), findsOneWidget);
        await _enterCredentials(tester);
        await _tap(tester, find.byKey(const Key('registration-submit')));
        expect(
          find.text(isSpanish ? 'Verifica tu correo' : 'Verify your email'),
          findsOneWidget,
        );

        final role = find.byType(DropdownButtonFormField<AccountRole>);
        await tester.ensureVisible(role);
        await tester.tap(role);
        await tester.pumpAndSettle();
        await tester.tap(find.text(managerLabel).last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('registration-ranch-name')),
        );
        await tester.ensureVisible(
          find.byKey(const Key('registration-complete')),
        );

        expect(
          find.byKey(const Key('registration-ranch-name')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('registration controls meet accessibility guidelines', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpRegistration(tester);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      await _createPendingIdentity(tester);
      await _chooseRole(tester, 'Veterinarian');
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    } finally {
      semantics.dispose();
    }
  });
}

Future<_RegistrationFixture> _pumpRegistration(
  WidgetTester tester, {
  bool identityConfigured = true,
  bool accountsConfigured = true,
  AuthUser? currentIdentity,
  AppLanguage initialLanguage = AppLanguage.english,
}) async {
  final language = LanguageService(
    MemoryLanguagePreferences(language: initialLanguage),
  );
  await language.initialize();
  final identity = FakeIdentityRegistrationRepository()
    ..isConfigured = identityConfigured
    ..user = currentIdentity
    ..createUserResult = _identityFor('new-user@example.test')
    ..signInUser = _identityFor('resume-user@example.test');
  final accounts = FakeAccountRegistrationRepository()
    ..isConfigured = accountsConfigured;
  final lifecycle = AuthenticationLifecycle(identity);
  final service = RegistrationService(
    authentication: lifecycle,
    accounts: accounts,
  );
  var termsOpened = false;

  addTearDown(() async {
    if (identity.currentUser != null) await service.cancel();
    service.dispose();
    lifecycle.dispose();
    await identity.close();
    language.dispose();
  });

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: IchuTheme.light,
      locale: Locale(language.current.code),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RegistrationPage(
        language: language,
        registration: service,
        onBack: () {},
        onOpenTerms: () => termsOpened = true,
      ),
    ),
  );
  await service.initialize();
  await tester.pumpAndSettle();

  return _RegistrationFixture(
    identity: identity,
    accounts: accounts,
    service: service,
    termsOpened: () => termsOpened,
  );
}

Future<void> _enterCredentials(
  WidgetTester tester, {
  String email = 'new-user@example.test',
  String password = 'test-only-password',
  String confirmation = 'test-only-password',
}) async {
  await _enterField(tester, 'registration-email', email);
  await _enterField(tester, 'registration-password', password);
  await _enterField(tester, 'registration-confirmation', confirmation);
}

Future<void> _enterField(WidgetTester tester, String key, String value) async {
  final field = find.byKey(Key(key));
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
}

Future<void> _createPendingIdentity(WidgetTester tester) async {
  await _enterCredentials(tester);
  await _tap(tester, find.byKey(const Key('registration-submit')));
}

Future<void> _chooseRole(WidgetTester tester, String label) async {
  final role = find.byType(DropdownButtonFormField<AccountRole>);
  await tester.ensureVisible(role);
  await tester.pumpAndSettle();
  await tester.tap(role);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

TextField _textField(WidgetTester tester, String key) =>
    tester.widget<TextField>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(TextField),
      ),
    );

final class _RegistrationFixture {
  const _RegistrationFixture({
    required this.identity,
    required this.accounts,
    required this.service,
    required this.termsOpened,
  });

  final FakeIdentityRegistrationRepository identity;
  final FakeAccountRegistrationRepository accounts;
  final RegistrationService service;
  final bool Function() termsOpened;
}

const AuthUser _verifiedIdentity = AuthUser(
  uid: 'synthetic-registration-uid',
  email: 'new-user@example.test',
  emailVerified: true,
);

AuthUser _identityFor(String email) => AuthUser(
  uid: 'synthetic-registration-uid',
  email: email,
  emailVerified: false,
);

AccountRegistrationResult _registrationResult({
  required String email,
  required AccountRole role,
}) => AccountRegistrationResult(
  account: IamAccount(
    id: 'synthetic-registration-account',
    email: email,
    role: role,
    status: 'PendingVerification',
  ),
  ranchId: role == AccountRole.ranchManager ? 'synthetic-ranch-id' : null,
);
