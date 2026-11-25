import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/core/theme/ichu_theme.dart';
import 'package:ichu_mobile_app/features/iam/application/services/auth_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/authentication_lifecycle.dart';
import 'package:ichu_mobile_app/features/iam/application/services/professional_profile_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_failure.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_user.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/professional_profile.dart';
import 'package:ichu_mobile_app/features/iam/presentation/pages/professional_profile_page.dart';
import 'package:ichu_mobile_app/shared/application/services/language_service.dart';
import 'package:ichu_mobile_app/shared/domain/model/app_language.dart';
import 'package:ichu_mobile_app/shared/infrastructure/i18n/generated/app_localizations.dart';

import 'support/fake_iam_repositories.dart';
import 'support/fake_professional_profile_repository.dart';
import 'support/memory_language_preferences.dart';

const _identity = AuthUser(
  uid: 'profile-widget-veterinarian',
  email: 'vet@example.test',
  emailVerified: true,
);
const _accountId = '11111111-1111-4111-8111-111111111111';
const _profile = ProfessionalProfile(
  specialty: 'Bovine health',
  licenseNumber: 'CMVP-123',
  yearsOfExperience: 5,
);

void main() {
  for (final role in AccountRole.values) {
    testWidgets('${role.name} sees the same profile in read-only mode', (
      tester,
    ) async {
      final fixture = await _pumpProfile(tester, role: role);

      expect(fixture.profileService.status, ProfessionalProfileStatus.ready);
      expect(fixture.profileService.canView, isTrue);
      expect(find.text('vet@example.test'), findsOneWidget);
      expect(find.text('Bovine health'), findsOneWidget);
      expect(find.text('CMVP-123'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.byType(EditableText), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.byKey(const Key('profile-save')), findsNothing);
      expect(find.textContaining('read-only'), findsOneWidget);
      expect(fixture.profiles.loadCalls, 1);
    });
  }

  testWidgets('a ready account without a profile has a clear empty state', (
    tester,
  ) async {
    final fixture = await _pumpProfile(tester, initialProfile: null);

    expect(fixture.profileService.status, ProfessionalProfileStatus.ready);
    expect(find.text('vet@example.test'), findsOneWidget);
    expect(find.textContaining('No professional profile'), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);
  });

  testWidgets('loading hides account data and exposes a disabled reload', (
    tester,
  ) async {
    final pending = Completer<IamAccount>();
    final fixture = await _pumpProfile(tester, loadCompleter: pending);

    expect(fixture.profileService.status, ProfessionalProfileStatus.loading);
    expect(find.text('Loading your professional profile…'), findsOneWidget);
    expect(find.text('vet@example.test'), findsNothing);
    expect(find.text('Bovine health'), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('profile-reload')))
          .onPressed,
      isNull,
    );

    pending.complete(_profileAccount(_profile));
    await tester.pumpAndSettle();
    expect(find.text('vet@example.test'), findsOneWidget);
  });

  testWidgets('failure hides old data and a forbidden read can be retried', (
    tester,
  ) async {
    final fixture = await _pumpProfile(
      tester,
      loadFailure: const AuthFailure(AuthFailureCode.forbidden),
    );

    expect(
      fixture.profileService.status,
      ProfessionalProfileStatus.unavailable,
    );
    expect(fixture.profileService.canReload, isTrue);
    expect(find.text('vet@example.test'), findsNothing);
    expect(find.text('Bovine health'), findsNothing);
    expect(
      find.text('Your account does not have permission for this action.'),
      findsOneWidget,
    );

    fixture.profiles
      ..loadFailure = null
      ..account = _profileAccount(_profile);
    await _tap(tester, find.byKey(const Key('profile-reload')));

    expect(fixture.profiles.loadCalls, 2);
    expect(fixture.profileService.status, ProfessionalProfileStatus.ready);
    expect(find.text('Bovine health'), findsOneWidget);
  });

  testWidgets('logout immediately clears a loaded snapshot', (tester) async {
    final fixture = await _pumpProfile(tester);
    expect(find.text('Bovine health'), findsOneWidget);

    expect(await fixture.session.signOut(), isTrue);
    await tester.pumpAndSettle();

    expect(fixture.profileService.account, isNull);
    expect(fixture.profileService.profile, isNull);
    expect(find.text('vet@example.test'), findsNothing);
    expect(find.text('Bovine health'), findsNothing);
  });

  testWidgets('late response after logout cannot restore profile data', (
    tester,
  ) async {
    final pending = Completer<IamAccount>();
    final fixture = await _pumpProfile(tester, loadCompleter: pending);

    expect(await fixture.session.signOut(), isTrue);
    await tester.pumpAndSettle();
    pending.complete(_profileAccount(_profile));
    await tester.pumpAndSettle();

    expect(fixture.profileService.account, isNull);
    expect(fixture.profileService.profile, isNull);
    expect(find.text('Bovine health'), findsNothing);
    expect(find.text('vet@example.test'), findsNothing);
  });

  testWidgets('session revalidation hides the previous snapshot', (
    tester,
  ) async {
    final fixture = await _pumpProfile(tester);
    final pendingAccount = Completer<IamAccount>();
    fixture.accounts.currentAccountCompleter = pendingAccount;

    final refresh = fixture.session.refresh();
    await fixture.accounts.secondCurrentAccountCall.future;
    await tester.pumpAndSettle();
    expect(find.text('vet@example.test'), findsNothing);
    expect(find.text('Bovine health'), findsNothing);

    pendingAccount.complete(
      _sessionAccount(AccountRole.veterinarian, identity: _identity),
    );
    await refresh;
    await tester.pumpAndSettle();
    expect(fixture.profileService.account, isNull);

    await _tap(tester, find.byKey(const Key('profile-reload')));
    expect(fixture.profileService.account?.email, _identity.email);
    expect(find.text('Bovine health'), findsOneWidget);
  });

  testWidgets('UID change hides old data and ignores an older pending read', (
    tester,
  ) async {
    const nextIdentity = AuthUser(
      uid: 'profile-widget-second-user',
      email: 'second-vet@example.test',
      emailVerified: true,
    );
    const nextId = '22222222-2222-4222-8222-222222222222';
    const nextProfile = ProfessionalProfile(
      specialty: 'Small animal medicine',
      licenseNumber: 'SECOND-456',
      yearsOfExperience: 3,
    );
    final fixture = await _pumpProfile(tester);
    final staleRead = Completer<IamAccount>();
    fixture.profiles.loadCompleter = staleRead;
    await _tap(
      tester,
      find.byKey(const Key('profile-reload')),
      settleAfterTap: false,
    );
    expect(fixture.profiles.loadCalls, 2);

    fixture
      ..accounts.account = _sessionAccount(
        AccountRole.veterinarian,
        identity: nextIdentity,
        accountId: nextId,
      )
      ..profiles.account = _profileAccount(
        nextProfile,
        identity: nextIdentity,
        accountId: nextId,
      );
    final nextSession = Completer<void>();
    void observeNextSession() {
      if (fixture.session.status == SessionStatus.authenticated &&
          fixture.session.user?.uid == nextIdentity.uid &&
          !nextSession.isCompleted) {
        nextSession.complete();
      }
    }

    fixture.session.addListener(observeNextSession);
    fixture.identity.emit(nextIdentity);
    await nextSession.future;
    fixture.session.removeListener(observeNextSession);
    await tester.pumpAndSettle();

    expect(find.text('vet@example.test'), findsNothing);
    expect(find.text('Bovine health'), findsNothing);
    fixture.profiles.loadCompleter = null;
    await _tap(tester, find.byKey(const Key('profile-reload')));
    expect(fixture.profileService.account?.email, nextIdentity.email);
    expect(find.text('Small animal medicine'), findsOneWidget);

    staleRead.complete(_profileAccount(_profile));
    await tester.pumpAndSettle();
    expect(fixture.profileService.profile?.specialty, 'Small animal medicine');
    expect(find.text('Bovine health'), findsNothing);
  });

  testWidgets('missing profile configuration provides no stale data', (
    tester,
  ) async {
    final fixture = await _pumpProfile(tester, profilesConfigured: false);

    expect(
      fixture.profileService.status,
      ProfessionalProfileStatus.unavailable,
    );
    expect(fixture.profiles.loadCalls, 0);
    expect(find.text('vet@example.test'), findsNothing);
    expect(find.text('Bovine health'), findsNothing);
    expect(find.byType(EditableText), findsNothing);
  });

  testWidgets('service replacement and maximum profile text remain readable', (
    tester,
  ) async {
    const longIdentity = AuthUser(
      uid: 'profile-widget-long-email',
      email: 'a.very.long.professional.email.address@example.test',
      emailVerified: true,
    );
    final longestSpecialty = List<String>.filled(120, 'W').join();
    final longProfile = ProfessionalProfile(
      specialty: longestSpecialty,
      licenseNumber: List<String>.filled(80, 'L').join(),
      yearsOfExperience: 2147483647,
    );
    tester.view.physicalSize = const Size(640, 360);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );

    final fixture = await _pumpProfile(
      tester,
      authUser: longIdentity,
      initialProfile: longProfile,
    );
    final replacementRepository = FakeProfessionalProfileRepository(
      account: _profileAccount(longProfile, identity: longIdentity),
    );
    final replacementService = ProfessionalProfileService(
      session: fixture.session,
      profiles: replacementRepository,
    );
    addTearDown(replacementService.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: IchuTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ProfessionalProfilePage(
          language: fixture.languageService,
          profileService: replacementService,
          onBack: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(longIdentity.email), findsOneWidget);
    expect(find.text(longestSpecialty), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('profile-reload')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final language in AppLanguage.values) {
    for (final platform in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.iOS,
    ]) {
      for (final size in <Size>[const Size(320, 568), const Size(640, 360)]) {
        testWidgets(
          '${language.name} $platform read-only layout fits $size at 200%',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(
              tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
            );

            await _pumpProfile(tester, language: language, platform: platform);
            expect(find.byType(SafeArea), findsOneWidget);
            expect(find.byType(SingleChildScrollView), findsOneWidget);
            await tester.ensureVisible(find.byKey(const Key('profile-reload')));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('${language.name} read-only content scrolls above keyboard', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );

      await _pumpProfile(tester, language: language);
      await tester.ensureVisible(find.byKey(const Key('profile-reload')));
      await tester.pumpAndSettle();

      expect(
        tester.getRect(find.byKey(const Key('profile-reload'))).bottom,
        lessThanOrEqualTo(360),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('${language.name} controls meet accessibility guidelines', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pumpProfile(tester, language: language);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      } finally {
        semantics.dispose();
      }
    });
  }
}

Future<_ProfileFixture> _pumpProfile(
  WidgetTester tester, {
  bool authenticated = true,
  bool profilesConfigured = true,
  AuthUser authUser = _identity,
  AccountRole role = AccountRole.veterinarian,
  ProfessionalProfile? initialProfile = _profile,
  Object? loadFailure,
  Completer<IamAccount>? loadCompleter,
  AppLanguage language = AppLanguage.english,
  TargetPlatform platform = TargetPlatform.android,
}) async {
  final languageService = LanguageService(
    MemoryLanguagePreferences(language: language),
  );
  await languageService.initialize();

  final identity = FakeAuthenticationRepository(
    user: authenticated ? authUser : null,
  );
  final accounts = FakeAccountRepository(
    account: _sessionAccount(role, identity: authUser),
  );
  final lifecycle = AuthenticationLifecycle(identity);
  final session = AuthService(authentication: lifecycle, accounts: accounts);
  await session.initialize();

  final profiles =
      FakeProfessionalProfileRepository(
          isConfigured: profilesConfigured,
          account: _profileAccount(
            initialProfile,
            role: role,
            identity: authUser,
          ),
        )
        ..loadFailure = loadFailure
        ..loadCompleter = loadCompleter;
  final profileService = ProfessionalProfileService(
    session: session,
    profiles: profiles,
  );
  final fixture = _ProfileFixture(
    identity: identity,
    session: session,
    accounts: accounts,
    profiles: profiles,
    profileService: profileService,
    languageService: languageService,
  );
  addTearDown(() async {
    profileService.dispose();
    session.dispose();
    lifecycle.dispose();
    await identity.close();
    languageService.dispose();
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: IchuTheme.light.copyWith(platform: platform),
      locale: Locale(language.code),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ProfessionalProfilePage(
        language: languageService,
        profileService: profileService,
        onBack: () {},
      ),
    ),
  );
  if (loadCompleter == null) await tester.pumpAndSettle();
  return fixture;
}

IamAccount _sessionAccount(
  AccountRole role, {
  required AuthUser identity,
  String accountId = _accountId,
}) => IamAccount(
  id: accountId,
  email: identity.email,
  role: role,
  status: 'Active',
);

IamAccount _profileAccount(
  ProfessionalProfile? profile, {
  AccountRole role = AccountRole.veterinarian,
  AuthUser identity = _identity,
  String accountId = _accountId,
}) => IamAccount(
  id: accountId,
  email: identity.email,
  role: role,
  status: 'Active',
  profile: profile,
);

Future<void> _tap(
  WidgetTester tester,
  Finder finder, {
  bool settleAfterTap = true,
}) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  if (settleAfterTap) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

final class _ProfileFixture {
  const _ProfileFixture({
    required this.identity,
    required this.session,
    required this.accounts,
    required this.profiles,
    required this.profileService,
    required this.languageService,
  });

  final FakeAuthenticationRepository identity;
  final AuthService session;
  final FakeAccountRepository accounts;
  final FakeProfessionalProfileRepository profiles;
  final ProfessionalProfileService profileService;
  final LanguageService languageService;
}
