import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/core/theme/ichu_theme.dart';
import 'package:ichu_mobile_app/features/cattle_information/application/services/cattle_management_service.dart';
import 'package:ichu_mobile_app/features/cattle_information/application/services/cattle_read_service.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle_failure.dart';
import 'package:ichu_mobile_app/features/cattle_information/presentation/pages/cattle_list_page.dart';
import 'package:ichu_mobile_app/features/cattle_information/presentation/pages/cattle_profile_page.dart';
import 'package:ichu_mobile_app/features/iam/application/facades/authorized_ranch_session.dart';
import 'package:ichu_mobile_app/features/iam/application/services/auth_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/authentication_lifecycle.dart';
import 'package:ichu_mobile_app/features/iam/application/services/ranch_selection_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_user.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_access.dart';
import 'package:ichu_mobile_app/shared/application/services/language_service.dart';
import 'package:ichu_mobile_app/shared/domain/model/app_language.dart';
import 'package:ichu_mobile_app/shared/infrastructure/i18n/generated/app_localizations.dart';

import 'support/fake_cattle_command_repository.dart';
import 'support/fake_cattle_repository.dart';
import 'support/fake_iam_repositories.dart';
import 'support/memory_language_preferences.dart';

const _ranchId = '11111111-1111-4111-8111-111111111111';
const _cattleId = '33333333-3333-4333-8333-333333333333';
const _identity = AuthUser(
  uid: 'cattle-management-widget-user',
  email: 'rancher@example.test',
  emailVerified: true,
);
const _account = IamAccount(
  id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  email: 'rancher@example.test',
  role: AccountRole.ranchManager,
  status: 'active',
);

void main() {
  testWidgets('read-only grants and absent management show no write actions', (
    tester,
  ) async {
    await _pump(tester, scope: AccessScope.read, page: _listPage);
    expect(find.byKey(const Key('cattle-manage-register')), findsNothing);

    await _pump(
      tester,
      withManagement: false,
      page: _profilePage,
      profile: _activeCattle(),
    );
    expect(find.byKey(const Key('cattle-manage-edit')), findsNothing);
    expect(find.byKey(const Key('cattle-profile-data')), findsOneWidget);
  });

  testWidgets('inactive animals expose no management actions', (tester) async {
    await _pump(
      tester,
      page: _profilePage,
      profile: syntheticCattle(
        ranchId: _ranchId,
        id: _cattleId,
        status: CattleStatus.inactive,
      ),
    );

    expect(find.byKey(const Key('cattle-manage-edit')), findsNothing);
    expect(find.byKey(const Key('cattle-manage-stage')), findsNothing);
    expect(find.byKey(const Key('cattle-manage-deactivate')), findsNothing);
  });

  testWidgets('manager registers an animal and the list refreshes', (
    tester,
  ) async {
    final fixture = await _pump(tester, page: _listPage);
    final created = syntheticCattle(
      ranchId: _ranchId,
      id: '44444444-4444-4444-8444-444444444444',
      earTag: 'PE-7',
    );
    fixture.commands.result = created;
    final listCallsBefore = fixture.cattle.listCalls;

    await _tap(tester, find.byKey(const Key('cattle-manage-register')));
    await tester.enterText(
      find.byKey(const Key('cattle-manage-form-ear-tag')),
      ' PE-7 ',
    );
    await _choose(tester, 'cattle-manage-form-breed', 'Crossbred');
    await _choose(tester, 'cattle-manage-form-sex', 'Female');
    await _choose(tester, 'cattle-manage-form-stage', 'Calf');
    await _pickToday(tester, 'cattle-manage-form-birth-date');
    await _tap(tester, find.byKey(const Key('cattle-manage-form-save')));

    expect(fixture.commands.requests.single.operation, 'register');
    expect(find.byKey(const Key('cattle-manage-form-save')), findsNothing);
    expect(fixture.cattle.listCalls, listCallsBefore + 1);
    expect(_text((s) => s.cattleManageRegistered), findsOneWidget);
  });

  testWidgets('manager corrects details from the profile and reloads', (
    tester,
  ) async {
    final fixture = await _pump(
      tester,
      page: _profilePage,
      profile: _activeCattle(),
    );
    fixture.commands.result = _activeCattle(earTag: 'TAG-2');

    await _tap(tester, find.byKey(const Key('cattle-manage-edit')));
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('cattle-manage-form-ear-tag')),
          )
          .controller!
          .text,
      'TAG-1',
    );
    await tester.enterText(
      find.byKey(const Key('cattle-manage-form-ear-tag')),
      'TAG-2',
    );
    await _tap(tester, find.byKey(const Key('cattle-manage-form-save')));

    final request = fixture.commands.requests.single;
    expect(request.operation, 'correct');
    expect(request.expectedVersion, _activeCattle().version);
    expect(fixture.cattle.profileCalls, 2);
    expect(_text((s) => s.cattleManageUpdated), findsOneWidget);
  });

  testWidgets('stage change sends the chosen stage and date', (tester) async {
    final fixture = await _pump(
      tester,
      page: _profilePage,
      profile: _activeCattle(),
    );
    fixture.commands.result = _activeCattle();

    await _tap(tester, find.byKey(const Key('cattle-manage-stage')));
    await _choose(tester, 'cattle-manage-stage-value', 'Milking cow');
    await _pickToday(tester, 'cattle-manage-stage-date');
    await _tap(tester, find.byKey(const Key('cattle-manage-stage-save')));

    expect(fixture.commands.requests.single.operation, 'changeStage');
    expect(fixture.cattle.profileCalls, 2);
    expect(_text((s) => s.cattleManageStageChanged), findsOneWidget);
  });

  testWidgets('deactivation explains the archive and sends the exit', (
    tester,
  ) async {
    final fixture = await _pump(
      tester,
      page: _profilePage,
      profile: _activeCattle(),
    );
    fixture.commands.result = _activeCattle();

    await _tap(tester, find.byKey(const Key('cattle-manage-deactivate')));
    expect(_text((s) => s.cattleManageDeactivateNotice), findsOneWidget);
    await _choose(tester, 'cattle-manage-exit-reason', 'Sale');
    await _pickToday(tester, 'cattle-manage-exit-date');
    await _tap(tester, find.byKey(const Key('cattle-manage-exit-save')));

    expect(fixture.commands.requests.single.operation, 'deactivate');
    expect(_text((s) => s.cattleManageDeactivated), findsOneWidget);
  });

  testWidgets('a version conflict shows the notice and reloads on close', (
    tester,
  ) async {
    final fixture = await _pump(
      tester,
      page: _profilePage,
      profile: _activeCattle(),
    );
    fixture.commands.failure = const CattleFailure(
      CattleFailureCode.versionConflict,
    );

    await _tap(tester, find.byKey(const Key('cattle-manage-edit')));
    await _tap(tester, find.byKey(const Key('cattle-manage-form-save')));
    expect(_text((s) => s.cattleManageErrorVersion), findsOneWidget);
    final save = tester.widget<ButtonStyleButton>(
      find.byKey(const Key('cattle-manage-form-save')),
    );
    expect(save.onPressed, isNull);

    await _tap(tester, find.byKey(const Key('cattle-manage-form-cancel')));
    expect(fixture.cattle.profileCalls, 2);
    expect(fixture.management.error, isNull);
  });

  testWidgets('a denied write explains the missing manage permission', (
    tester,
  ) async {
    final fixture = await _pump(
      tester,
      page: _profilePage,
      profile: _activeCattle(),
    );
    fixture.commands.failure = const CattleFailure(CattleFailureCode.forbidden);

    await _tap(tester, find.byKey(const Key('cattle-manage-edit')));
    await _tap(tester, find.byKey(const Key('cattle-manage-form-save')));
    expect(_text((s) => s.cattleManageErrorForbidden), findsOneWidget);
    expect(_text((s) => s.cattleErrorForbidden), findsNothing);
  });

  testWidgets('Spanish manager sees the registration action in Spanish', (
    tester,
  ) async {
    await _pump(tester, page: _listPage, language: AppLanguage.spanish);

    expect(find.text('Registrar animal'), findsOneWidget);
  });
}

Widget _listPage(_Fixture fixture) => CattleListPage(
  language: fixture.language,
  service: fixture.read,
  onBack: () {},
  onOpenRanches: () {},
  onOpenCattle: (_) {},
  management: fixture.withManagement ? fixture.management : null,
);

Widget _profilePage(_Fixture fixture) => CattleProfilePage(
  language: fixture.language,
  service: fixture.read,
  cattleId: _cattleId,
  onBack: () {},
  onOpenRanches: () {},
  management: fixture.withManagement ? fixture.management : null,
);

Cattle _activeCattle({String earTag = 'TAG-1'}) =>
    syntheticCattle(ranchId: _ranchId, id: _cattleId, earTag: earTag);

Finder _text(String Function(AppLocalizations) pick) =>
    find.text(pick(lookupAppLocalizations(const Locale('en'))));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String key, String label) async {
  await _tap(tester, find.byKey(Key(key)));
  await _tap(tester, find.text(label).last);
}

Future<void> _pickToday(WidgetTester tester, String key) async {
  await _tap(tester, find.byKey(Key(key)));
  await _tap(tester, find.text('OK'));
}

Future<_Fixture> _pump(
  WidgetTester tester, {
  required Widget Function(_Fixture fixture) page,
  AccessScope scope = AccessScope.manage,
  bool withManagement = true,
  AppLanguage language = AppLanguage.english,
  Cattle? profile,
}) async {
  final authentication = FakeAuthenticationRepository(user: _identity);
  final accounts = FakeAccountRepository(
    account: _account,
    ranches: <RanchAccess>[
      RanchAccess(
        ranchId: _ranchId,
        scope: scope,
        name: 'Selected ranch',
        region: 'Central Region',
        district: 'North District',
      ),
    ],
  );
  final lifecycle = AuthenticationLifecycle(authentication);
  final auth = AuthService(authentication: lifecycle, accounts: accounts);
  await auth.initialize();
  final selection = RanchSelectionService(session: auth);
  expect(selection.select(_ranchId), isTrue);
  final access = AuthorizedRanchSession(
    session: auth,
    selection: selection,
    authentication: authentication,
  );
  final cattle = FakeCattleRepository();
  if (profile != null) {
    cattle.profileResult = CattleProfile(
      cattle: profile,
      device: const CattleDevice(isAvailable: true),
    );
  }
  final commands = FakeCattleCommandRepository();
  final management = CattleManagementService(
    access: access,
    commands: commands,
    clock: () => DateTime.utc(2026, 11, 13),
  );
  final languageService = LanguageService(
    MemoryLanguagePreferences(language: language),
  );
  await languageService.initialize();
  final fixture = _Fixture(
    authentication: authentication,
    lifecycle: lifecycle,
    auth: auth,
    selection: selection,
    access: access,
    cattle: cattle,
    commands: commands,
    management: management,
    read: CattleReadService(access: access, cattle: cattle),
    language: languageService,
    withManagement: withManagement,
  );
  addTearDown(fixture.dispose);
  await tester.pumpWidget(
    ListenableBuilder(
      listenable: languageService,
      builder: (context, _) => MaterialApp(
        theme: IchuTheme.light,
        locale: Locale(languageService.current.code),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: page(fixture),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fixture;
}

final class _Fixture {
  _Fixture({
    required this.authentication,
    required this.lifecycle,
    required this.auth,
    required this.selection,
    required this.access,
    required this.cattle,
    required this.commands,
    required this.management,
    required this.read,
    required this.language,
    required this.withManagement,
  });

  final FakeAuthenticationRepository authentication;
  final AuthenticationLifecycle lifecycle;
  final AuthService auth;
  final RanchSelectionService selection;
  final AuthorizedRanchSession access;
  final FakeCattleRepository cattle;
  final FakeCattleCommandRepository commands;
  final CattleManagementService management;
  final CattleReadService read;
  final LanguageService language;
  final bool withManagement;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    management.dispose();
    read.dispose();
    access.dispose();
    selection.dispose();
    auth.dispose();
    lifecycle.dispose();
    language.dispose();
    unawaited(authentication.close());
  }
}
