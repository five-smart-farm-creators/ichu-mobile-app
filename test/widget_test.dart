import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ichu_mobile_app/app.dart';
import 'package:ichu_mobile_app/core/theme/ichu_colors.dart';
import 'package:ichu_mobile_app/features/cattle_information/application/services/cattle_management_service.dart';
import 'package:ichu_mobile_app/features/cattle_information/application/services/cattle_read_service.dart';
import 'package:ichu_mobile_app/features/cattle_information/application/facades/cattle_lookup_facade.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle.dart';
import 'package:ichu_mobile_app/features/cattle_information/presentation/pages/cattle_list_page.dart';
import 'package:ichu_mobile_app/features/cattle_information/presentation/pages/cattle_profile_page.dart';
import 'package:ichu_mobile_app/features/iam/application/facades/authorized_ranch_session.dart';
import 'package:ichu_mobile_app/features/iam/application/services/auth_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/authentication_lifecycle.dart';
import 'package:ichu_mobile_app/features/iam/application/services/herd_advisory_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/registration_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/professional_profile_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/ranch_selection_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_failure.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_user.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/herd_advisory.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/professional_profile.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_access.dart';
import 'package:ichu_mobile_app/features/iam/presentation/pages/login_page.dart';
import 'package:ichu_mobile_app/features/iam/presentation/pages/session_account_page.dart';
import 'package:ichu_mobile_app/features/iam/presentation/pages/herd_advisory_page.dart';
import 'package:ichu_mobile_app/shared/infrastructure/i18n/generated/app_localizations.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/application/services/monitoring_read_service.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/application/services/alert_read_service.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/application/services/field_record_service.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/ranch_alert.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/presentation/pages/field_records_page.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/infrastructure/adapters/field_cattle_directory_adapter.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/presentation/pages/animal_monitoring_page.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/presentation/pages/ranch_alerts_page.dart';
import 'package:ichu_mobile_app/shared/application/services/language_service.dart';
import 'package:ichu_mobile_app/shared/domain/model/app_language.dart';

import 'support/fake_iam_repositories.dart';
import 'support/fake_cattle_command_repository.dart';
import 'support/fake_cattle_repository.dart';
import 'support/fake_monitoring_repository.dart';
import 'support/fake_alert_repository.dart';
import 'support/fake_herd_advisory_repository.dart';
import 'support/fake_registration_repositories.dart';
import 'support/fake_professional_profile_repository.dart';
import 'support/memory_language_preferences.dart';
import 'support/memory_field_record_repository.dart';

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
const _ranch = RanchAccess(
  ranchId: '22222222-2222-4222-8222-222222222222',
  scope: AccessScope.read,
  name: 'North ranch',
  region: 'Cusco',
  district: 'Anta',
);
const _managedRanch = RanchAccess(
  ranchId: '44444444-4444-4444-8444-444444444444',
  scope: AccessScope.manage,
  name: 'Managed ranch',
  region: 'Cusco',
  district: 'Anta',
);

Future<
  ({
    AuthService auth,
    FakeAuthenticationRepository identity,
    FakeAccountRepository accounts,
    RegistrationService registration,
    FakeIdentityRegistrationRepository registrationIdentity,
    FakeAccountRegistrationRepository registrationAccounts,
    ProfessionalProfileService profileService,
    FakeProfessionalProfileRepository profiles,
    RanchSelectionService ranchSelection,
    CattleReadService cattleService,
    HerdAdvisoryService herdAdvisoryService,
    FakeHerdAdvisoryRepository herdAdvisories,
    CattleManagementService cattleManagementService,
    FakeCattleCommandRepository cattleCommands,
    FakeCattleRepository cattle,
    MonitoringReadService monitoringService,
    FakeMonitoringRepository monitoring,
    AlertReadService alertService,
    FakeAlertRepository alerts,
    FieldRecordService fieldRecordService,
    MemoryFieldRecordRepository fieldRecordRepository,
  })
>
pumpApp(
  WidgetTester tester, {
  bool configured = true,
  bool restored = false,
  AppLanguage initialLanguage = AppLanguage.english,
  String initialRoute = '/',
  IamAccount account = _account,
  AuthFailure? accountFailure,
  MemoryLanguagePreferences? preferences,
  List<RanchAccess> ranches = const [],
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
    ..currentAccountFailure = accountFailure
    ..ranches = ranches
    ..account = account;
  final lifecycle = AuthenticationLifecycle(identity);
  final auth = AuthService(authentication: lifecycle, accounts: accounts);
  final ranchSelection = RanchSelectionService(session: auth);
  final ranchAccess = AuthorizedRanchSession(
    session: auth,
    selection: ranchSelection,
    authentication: lifecycle,
  );
  final cattle = FakeCattleRepository();
  final cattleService = CattleReadService(access: ranchAccess, cattle: cattle);
  final fieldRecordRepository = MemoryFieldRecordRepository();
  final fieldRecordService = FieldRecordService(
    access: ranchAccess,
    repository: fieldRecordRepository,
  );
  final fieldCattleDirectory = FieldCattleDirectoryAdapter(
    lookup: CattleLookupFacade(access: ranchAccess, cattle: cattle),
  );
  final herdAdvisories = FakeHerdAdvisoryRepository();
  final herdAdvisoryService = HerdAdvisoryService(
    advisories: herdAdvisories,
    selection: ranchSelection,
  );
  final cattleCommands = FakeCattleCommandRepository();
  final cattleManagementService = CattleManagementService(
    access: ranchAccess,
    commands: cattleCommands,
  );
  final monitoring = FakeMonitoringRepository();
  final monitoringService = MonitoringReadService(
    access: ranchAccess,
    monitoring: monitoring,
  );
  final alerts = FakeAlertRepository();
  final alertService = AlertReadService(access: ranchAccess, alerts: alerts);
  final profiles = FakeProfessionalProfileRepository()..account = account;
  final profileService = ProfessionalProfileService(
    session: auth,
    profiles: profiles,
  );
  final registrationIdentity = FakeIdentityRegistrationRepository()
    ..isConfigured = configured
    ..createUserResult = const AuthUser(
      uid: 'synthetic-registration-uid',
      email: 'new-user@example.test',
      emailVerified: false,
    );
  final registrationAccounts = FakeAccountRegistrationRepository()
    ..isConfigured = configured;
  final registrationLifecycle = AuthenticationLifecycle(registrationIdentity);
  final registration = RegistrationService(
    authentication: registrationLifecycle,
    accounts: registrationAccounts,
  );
  addTearDown(() async {
    alertService.dispose();
    fieldRecordService.dispose();
    monitoringService.dispose();
    cattleManagementService.dispose();
    cattleService.dispose();
    ranchAccess.dispose();
    profileService.dispose();
    ranchSelection.dispose();
    auth.dispose();
    registration.dispose();
    lifecycle.dispose();
    registrationLifecycle.dispose();
    await identity.close();
    await registrationIdentity.close();
    language.dispose();
  });
  await tester.pumpWidget(
    IchuApp(
      language: language,
      authentication: auth,
      registration: registration,
      profileService: profileService,
      ranchSelection: ranchSelection,
      cattleService: cattleService,
      herdAdvisoryService: herdAdvisoryService,
      cattleManagementService: cattleManagementService,
      monitoringService: monitoringService,
      alertService: alertService,
      fieldRecordService: fieldRecordService,
      fieldCattleDirectory: fieldCattleDirectory,
      initialRoute: initialRoute,
    ),
  );
  await tester.pumpAndSettle();
  return (
    auth: auth,
    identity: identity,
    accounts: accounts,
    registration: registration,
    registrationIdentity: registrationIdentity,
    registrationAccounts: registrationAccounts,
    profileService: profileService,
    profiles: profiles,
    ranchSelection: ranchSelection,
    cattleService: cattleService,
    herdAdvisoryService: herdAdvisoryService,
    herdAdvisories: herdAdvisories,
    cattleManagementService: cattleManagementService,
    cattleCommands: cattleCommands,
    cattle: cattle,
    monitoringService: monitoringService,
    monitoring: monitoring,
    alertService: alertService,
    alerts: alerts,
    fieldRecordService: fieldRecordService,
    fieldRecordRepository: fieldRecordRepository,
  );
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
  testWidgets('field record deep links require a validated session', (
    tester,
  ) async {
    final fixture = await pumpApp(
      tester,
      initialRoute: '/account/field-records',
    );
    expect(find.byType(LoginPage), findsOneWidget);
    expect(fixture.fieldRecordService.records, isEmpty);
  });

  testWidgets('field record URLs cannot select a ranch', (tester) async {
    final fixture = await pumpApp(
      tester,
      restored: true,
      ranches: const [_managedRanch],
    );
    GoRouter.of(
      tester.element(find.byType(SessionAccountPage)),
    ).go('/account/field-records?ranchId=${_managedRanch.ranchId}');
    await tester.pumpAndSettle();

    expect(find.text('Authorized ranches'), findsOneWidget);
    expect(find.byType(FieldRecordsPage), findsNothing);
    expect(fixture.ranchSelection.selectedRanch, isNull);
  });

  testWidgets(
    'manager opens field records and resolves cattle in selected ranch',
    (tester) async {
      final fixture = await pumpApp(
        tester,
        restored: true,
        ranches: const [_managedRanch],
      );
      fixture.cattle.listResult = <Cattle>[
        syntheticCattle(
          ranchId: _managedRanch.ranchId,
          id: 'field-record-cattle',
          earTag: 'TAG-88',
        ),
      ];
      expect(fixture.ranchSelection.select(_managedRanch.ranchId), isTrue);
      await tester.pumpAndSettle();

      final entry = find.byKey(const Key('account-field-records'));
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byType(FieldRecordsPage), findsOneWidget);
      expect(fixture.fieldRecordService.canCreate, isTrue);

      final strings = AppLocalizations.of(
        tester.element(find.byType(FieldRecordsPage)),
      );
      await tester.enterText(
        find.byKey(const Key('field-record-cattle-tag')),
        'TAG-88',
      );
      await tester.tap(find.byTooltip(strings.fieldRecordFindCattle));
      await tester.pumpAndSettle();
      expect(
        find.text(strings.fieldRecordSelectedCattle('TAG-88')),
        findsOneWidget,
      );
      expect(fixture.cattle.listRequests.single.ranchId, _managedRanch.ranchId);
      expect(fixture.cattle.listRequests.single.query.earTag, 'TAG-88');

      await tester.enterText(
        find.byKey(const Key('field-record-observation')),
        'Synthetic integration check',
      );
      await tester.ensureVisible(find.byKey(const Key('field-record-save')));
      await tester.tap(find.byKey(const Key('field-record-save')));
      await tester.pumpAndSettle();
      expect(fixture.fieldRecordService.records, hasLength(1));
      expect(
        fixture.fieldRecordService.records.single.observation,
        'Synthetic integration check',
      );
      expect(
        fixture.fieldRecordService.records.single.ranchId,
        _managedRanch.ranchId,
      );
    },
  );

  testWidgets(
    'read-only ranch grants can view but cannot create field records',
    (tester) async {
      final fixture = await pumpApp(
        tester,
        restored: true,
        ranches: const [_ranch],
      );
      expect(fixture.ranchSelection.select(_ranch.ranchId), isTrue);
      await tester.pumpAndSettle();

      final entry = find.byKey(const Key('account-field-records'));
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();

      expect(find.byType(FieldRecordsPage), findsOneWidget);
      expect(fixture.fieldRecordService.canCreate, isFalse);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('field-record-save')))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('ranch alert links require a validated session', (tester) async {
    final fixture = await pumpApp(tester, initialRoute: '/account/alerts');
    expect(find.byType(LoginPage), findsOneWidget);
    expect(fixture.alerts.calls, 0);
  });
  testWidgets('ranch advisory links require a validated session', (
    tester,
  ) async {
    final fixture = await pumpApp(tester, initialRoute: '/account/advisories');
    expect(find.byType(LoginPage), findsOneWidget);
    expect(fixture.herdAdvisories.lookupCalls, 0);
    expect(fixture.herdAdvisories.listCalls, 0);
  });
  testWidgets('advisory URL cannot select a ranch', (tester) async {
    final fixture = await pumpApp(tester, restored: true, ranches: [_ranch]);
    GoRouter.of(
      tester.element(find.byType(SessionAccountPage)),
    ).go('/account/advisories?ranchId=${_ranch.ranchId}');
    await tester.pumpAndSettle();
    expect(find.byType(HerdAdvisoryPage), findsOneWidget);
    expect(fixture.ranchSelection.selectedRanch, isNull);
    expect(fixture.herdAdvisories.listCalls, 0);
  });
  testWidgets('field operators cannot access ranch advisories', (tester) async {
    final fixture = await pumpApp(
      tester,
      restored: true,
      ranches: [_ranch],
      account: const IamAccount(
        id: '11111111-1111-4111-8111-111111111111',
        email: 'user@example.test',
        role: AccountRole.fieldOperator,
        status: 'Active',
      ),
    );
    expect(find.byKey(const Key('account-advisories')), findsNothing);
    GoRouter.of(
      tester.element(find.byType(SessionAccountPage)),
    ).go('/account/advisories');
    await tester.pumpAndSettle();
    expect(find.byType(HerdAdvisoryPage), findsNothing);
    expect(find.byType(SessionAccountPage), findsOneWidget);
    expect(fixture.herdAdvisories.listCalls, 0);
  });
  testWidgets(
    'manager can open advisory history only for the selected managed ranch',
    (tester) async {
      final fixture = await pumpApp(
        tester,
        restored: true,
        ranches: const [_managedRanch],
      );
      const advisoryId = '55555555-5555-4555-8555-555555555555';
      fixture.herdAdvisories.advisories = <HerdAdvisory>[
        HerdAdvisory(
          id: advisoryId,
          veterinarianId: '66666666-6666-4666-8666-666666666666',
          ranchId: _managedRanch.ranchId,
          reason: 'Herd health review',
          status: HerdAdvisoryStatus.pending,
          scope: AccessScope.read,
          requestedAt: DateTime.utc(2026, 11, 13),
        ),
      ];
      expect(fixture.ranchSelection.select(_managedRanch.ranchId), isTrue);
      await tester.pumpAndSettle();
      final entry = find.byKey(const Key('account-advisories'));
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();

      expect(find.byType(HerdAdvisoryPage), findsOneWidget);
      expect(fixture.herdAdvisories.listCalls, 1);
      expect(fixture.herdAdvisories.lastRanchId, _managedRanch.ranchId);
      expect(find.byKey(const Key('advisory-veterinarian-id')), findsOneWidget);
      expect(find.text('Grant read access'), findsOneWidget);
      expect(find.text('Reject request'), findsOneWidget);
    },
  );
  testWidgets('veterinarian advisory page does not expose manager actions', (
    tester,
  ) async {
    const veterinarianAccount = IamAccount(
      id: '11111111-1111-4111-8111-111111111111',
      email: 'user@example.test',
      role: AccountRole.veterinarian,
      status: 'Active',
    );
    final fixture = await pumpApp(
      tester,
      restored: true,
      ranches: [_ranch],
      account: veterinarianAccount,
    );
    expect(fixture.ranchSelection.select(_ranch.ranchId), isTrue);
    await tester.pumpAndSettle();
    final entry = find.byKey(const Key('account-advisories'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.byType(HerdAdvisoryPage), findsOneWidget);
    expect(find.byKey(const Key('advisory-access-code')), findsOneWidget);
    expect(find.byKey(const Key('advisory-veterinarian-id')), findsNothing);
    expect(find.text('Grant read access'), findsNothing);
    expect(find.text('Reject request'), findsNothing);
    expect(fixture.herdAdvisories.lastRanchId, _ranch.ranchId);
  });
  testWidgets('alert route query cannot choose a ranch', (tester) async {
    final fixture = await pumpApp(tester, restored: true, ranches: [_ranch]);
    GoRouter.of(
      tester.element(find.byType(SessionAccountPage)),
    ).go('/account/alerts?ranchId=${_ranch.ranchId}');
    await tester.pumpAndSettle();
    expect(find.text('Authorized ranches'), findsOneWidget);
    expect(fixture.ranchSelection.selectedRanch, isNull);
    expect(fixture.alerts.calls, 0);
  });
  for (final role in AccountRole.values) {
    testWidgets(
      '${role.name} can read alerts only in the explicitly selected ranch',
      (tester) async {
        final fixture = await pumpApp(
          tester,
          restored: true,
          ranches: [_ranch],
          account: IamAccount(
            id: _account.id,
            email: _account.email,
            role: role,
            status: 'Active',
          ),
        );
        final entry = find.byKey(const Key('account-alerts'));
        expect(tester.widget<OutlinedButton>(entry).onPressed, isNull);
        fixture.ranchSelection.select(_ranch.ranchId);
        fixture.alerts.pageResult = AlertPage(
          page: 1,
          pageSize: 20,
          totalCount: 1,
          items: [
            syntheticRanchAlert(
              ranchId: _ranch.ranchId,
              alertId: '88888888-8888-4888-8888-888888888888',
            ),
          ],
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(entry);
        await tester.pumpAndSettle();
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(find.byType(RanchAlertsPage), findsOneWidget);
        expect(fixture.alerts.requests.single.ranchId, _ranch.ranchId);
        final router = GoRouter.of(
          tester.element(find.byType(RanchAlertsPage)),
        );
        router.go(
          '/account/alerts?ranchId=99999999-9999-4999-8999-999999999999',
        );
        await tester.pumpAndSettle();
        expect(fixture.ranchSelection.selectedRanch, same(_ranch));
        expect(fixture.alerts.calls, 1);
        expect(fixture.cattle.listCalls, 0);
        expect(fixture.monitoring.calls, 0);
        await fixture.auth.refresh();
        await tester.pumpAndSettle();
        expect(find.byType(RanchAlertsPage), findsNothing);
        expect(fixture.alertService.alerts, isEmpty);
        expect(fixture.alertService.totalCount, isNull);
        expect(fixture.alerts.calls, 1);
      },
    );
  }
  const cattleId = '33333333-3333-4333-8333-333333333333';
  final monitoringRoute =
      '/account/animals/${_ranch.ranchId}/$cattleId/monitoring';
  testWidgets('monitoring deep links require a validated session', (
    tester,
  ) async {
    final fixture = await pumpApp(tester, initialRoute: monitoringRoute);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(fixture.monitoring.calls, 0);
  });
  testWidgets('monitoring URL and query cannot choose an authorized ranch', (
    tester,
  ) async {
    final fixture = await pumpApp(tester, restored: true, ranches: [_ranch]);
    GoRouter.of(
      tester.element(find.byType(SessionAccountPage)),
    ).go('$monitoringRoute?ranchId=${_ranch.ranchId}');
    await tester.pumpAndSettle();
    expect(find.text('Authorized ranches'), findsOneWidget);
    expect(fixture.ranchSelection.selectedRanch, isNull);
    expect(fixture.monitoring.calls, 0);
  });
  testWidgets(
    'foreign-ranch monitoring links redirect without a monitoring request',
    (tester) async {
      final fixture = await pumpApp(tester, restored: true, ranches: [_ranch]);
      fixture.ranchSelection.select(_ranch.ranchId);
      final router = GoRouter.of(
        tester.element(find.byType(SessionAccountPage)),
      );
      router.go(
        '/account/animals/99999999-9999-4999-8999-999999999999/$cattleId/monitoring',
      );
      await tester.pumpAndSettle();
      expect(find.byType(CattleListPage), findsOneWidget);
      expect(find.byType(AnimalMonitoringPage), findsNothing);
      expect(fixture.monitoring.calls, 0);
    },
  );
  testWidgets(
    'verified animal profile opens monitoring without requiring a current collar',
    (tester) async {
      final fixture = await pumpApp(tester, restored: true, ranches: [_ranch]);
      fixture.ranchSelection.select(_ranch.ranchId);
      fixture.cattle.profileResult = CattleProfile(
        cattle: syntheticCattle(
          ranchId: _ranch.ranchId,
          id: cattleId,
          earTag: 'ROUTE-FIXTURE-1',
        ),
        device: const CattleDevice(isAvailable: true),
      );
      fixture.monitoring.latestResult = syntheticLatestTelemetry(
        cattleId: cattleId,
      );
      GoRouter.of(
        tester.element(find.byType(SessionAccountPage)),
      ).go('/account/animals/${_ranch.ranchId}/$cattleId');
      await tester.pumpAndSettle();
      expect(fixture.monitoring.calls, 0);
      final open = find.byKey(const Key('cattle-open-monitoring'));
      await tester.ensureVisible(open);
      await tester.pumpAndSettle();
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(find.byType(AnimalMonitoringPage), findsOneWidget);
      expect(fixture.monitoring.requests.single.ranchId, _ranch.ranchId);
      expect(fixture.monitoring.requests.single.cattleId, cattleId);
      expect(fixture.cattle.profileCalls, 1);
      await tester.tap(find.byTooltip('Back to animal'));
      await tester.pumpAndSettle();
      expect(find.byType(CattleProfilePage), findsOneWidget);
      expect(find.text('ROUTE-FIXTURE-1'), findsOneWidget);
      expect(fixture.monitoringService.snapshot, isNull);
      expect(fixture.monitoring.calls, 1);
    },
  );
  testWidgets(
    'monitoring rejects malformed cattle IDs locally and revalidation removes data',
    (tester) async {
      final fixture = await pumpApp(tester, restored: true, ranches: [_ranch]);
      fixture.ranchSelection.select(_ranch.ranchId);
      final router = GoRouter.of(
        tester.element(find.byType(SessionAccountPage)),
      );
      router.go('/account/animals/${_ranch.ranchId}/not-a-guid/monitoring');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('monitoring-error')), findsOneWidget);
      expect(fixture.monitoring.calls, 0);
      expect(fixture.cattle.listCalls, 0);
      expect(fixture.cattle.profileCalls, 0);
      fixture.monitoring.latestResult = syntheticLatestTelemetry(
        cattleId: cattleId,
      );
      router.go(monitoringRoute);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('monitoring-snapshot')), findsOneWidget);
      expect(fixture.monitoring.calls, 1);
      expect(fixture.cattle.listCalls, 0);
      expect(fixture.cattle.profileCalls, 0);
      await fixture.auth.refresh();
      await tester.pumpAndSettle();
      expect(find.byType(AnimalMonitoringPage), findsNothing);
      expect(fixture.monitoringService.snapshot, isNull);
      expect(fixture.monitoring.calls, 1);
    },
  );
  for (final path in [
    '/account/animals',
    '/account/animals/${_ranch.ranchId}/33333333-3333-4333-8333-333333333333',
  ]) {
    testWidgets('animal route $path requires a validated session', (
      tester,
    ) async {
      final fixture = await pumpApp(tester, initialRoute: path);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(fixture.cattle.listCalls, 0);
      expect(fixture.cattle.profileCalls, 0);
    });
    testWidgets('animal route $path cannot select a ranch from its URL', (
      tester,
    ) async {
      final fixture = await pumpApp(tester, restored: true, ranches: [_ranch]);
      GoRouter.of(tester.element(find.byType(SessionAccountPage))).go(path);
      await tester.pumpAndSettle();
      expect(find.text('Authorized ranches'), findsOneWidget);
      expect(fixture.ranchSelection.selectedRanch, isNull);
      expect(fixture.cattle.listCalls, 0);
      expect(fixture.cattle.profileCalls, 0);
    });
  }

  testWidgets(
    'animal navigation is selection-bound and rejects a foreign ranch route',
    (tester) async {
      final fixture = await pumpApp(tester, restored: true, ranches: [_ranch]);
      expect(fixture.ranchSelection.select(_ranch.ranchId), isTrue);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('account-animals')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('account-animals')));
      await tester.pumpAndSettle();
      expect(find.byType(CattleListPage), findsOneWidget);
      expect(fixture.cattle.listCalls, 1);
      final router = GoRouter.of(tester.element(find.byType(CattleListPage)));
      router.go(
        '/account/animals/99999999-9999-4999-8999-999999999999/33333333-3333-4333-8333-333333333333',
      );
      await tester.pumpAndSettle();
      expect(find.byType(CattleListPage), findsOneWidget);
      expect(find.byType(CattleProfilePage), findsNothing);
      expect(fixture.cattle.profileCalls, 0);
      await fixture.auth.refresh();
      await tester.pumpAndSettle();
      expect(fixture.ranchSelection.selectedRanch, isNull);
      expect(find.byType(CattleListPage), findsNothing);
    },
  );

  testWidgets(
    'management grants reach cattle registration and profile actions through app routes',
    (tester) async {
      final fixture = await pumpApp(
        tester,
        restored: true,
        ranches: const [_managedRanch],
      );
      const cattleId = '33333333-3333-4333-8333-333333333333';
      final animal = syntheticCattle(
        ranchId: _managedRanch.ranchId,
        id: cattleId,
      );
      fixture.cattle
        ..listResult = <Cattle>[animal]
        ..profileResult = CattleProfile(
          cattle: animal,
          device: const CattleDevice(isAvailable: true),
        );

      expect(fixture.ranchSelection.select(_managedRanch.ranchId), isTrue);
      expect(fixture.cattleManagementService.canManage, isTrue);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('account-animals')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('account-animals')));
      await tester.pumpAndSettle();

      final register = find.byKey(const Key('cattle-manage-register'));
      expect(register, findsOneWidget);
      await tester.ensureVisible(register);
      await tester.tap(register);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cattle-manage-form-save')), findsOneWidget);
      final cancel = find.byKey(const Key('cattle-manage-form-cancel'));
      await tester.ensureVisible(cancel);
      await tester.tap(cancel);
      await tester.pumpAndSettle();

      final openProfile = find.byKey(Key('cattle-open-$cattleId'));
      await tester.ensureVisible(openProfile);
      await tester.tap(openProfile);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cattle-manage-edit')), findsOneWidget);
      expect(find.byKey(const Key('cattle-manage-stage')), findsOneWidget);
      expect(find.byKey(const Key('cattle-manage-deactivate')), findsOneWidget);
    },
  );

  testWidgets('read grants remain read-only through app composition', (
    tester,
  ) async {
    final fixture = await pumpApp(
      tester,
      restored: true,
      ranches: const [_ranch],
    );
    expect(fixture.ranchSelection.select(_ranch.ranchId), isTrue);
    expect(fixture.cattleManagementService.canManage, isFalse);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('account-animals')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-animals')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cattle-manage-register')), findsNothing);
  });

  testWidgets('ranch selection is protected without a validated session', (
    tester,
  ) async {
    final fixture = await pumpApp(tester, initialRoute: '/account/ranches');
    expect(find.byType(LoginPage), findsOneWidget);
    expect(fixture.ranchSelection.canSelect, isFalse);
    expect(fixture.ranchSelection.selectedRanch, isNull);
  });

  for (final role in AccountRole.values) {
    testWidgets(
      '${role.name} can choose an authorized ranch and logout clears it',
      (tester) async {
        final fixture = await pumpApp(
          tester,
          restored: true,
          ranches: [_ranch],
          account: IamAccount(
            id: _account.id,
            email: _account.email,
            role: role,
            status: 'Active',
          ),
        );
        expect(fixture.ranchSelection.selectedRanch, isNull);
        await tester.ensureVisible(find.byKey(const Key('account-ranches')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('account-ranches')));
        await tester.pumpAndSettle();
        expect(find.text('Authorized ranches'), findsOneWidget);
        final select = find.byKey(Key('ranch-select-${_ranch.ranchId}'));
        await tester.ensureVisible(select);
        await tester.pumpAndSettle();
        await tester.tap(select);
        await tester.pumpAndSettle();
        expect(fixture.ranchSelection.selectedRanch, same(_ranch));
        expect(fixture.ranchSelection.selectedRanch?.scope, AccessScope.read);
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('account-selected-ranch')), findsOneWidget);
        expect(find.text('North ranch'), findsOneWidget);
        expect(await fixture.auth.signOut(), isTrue);
        await tester.pumpAndSettle();
        expect(find.byType(LoginPage), findsOneWidget);
        expect(find.text('North ranch'), findsNothing);
        expect(fixture.ranchSelection.selectedRanch, isNull);
        expect(fixture.ranchSelection.ranches, isEmpty);
      },
    );
  }

  testWidgets(
    'route query IDs cannot choose a ranch and refresh does not restore selection',
    (tester) async {
      final fixture = await pumpApp(tester, restored: true, ranches: [_ranch]);
      GoRouter.of(
        tester.element(find.byType(SessionAccountPage)),
      ).go('/account/ranches?ranchId=${_ranch.ranchId}');
      await tester.pumpAndSettle();
      expect(fixture.ranchSelection.selectedRanch, isNull);
      expect(fixture.ranchSelection.select(_ranch.ranchId), isTrue);
      await tester.pumpAndSettle();
      final pending = Completer<IamAccount>();
      fixture.accounts.currentAccountCompleter = pending;
      final refresh = fixture.ranchSelection.refresh();
      await fixture.accounts.secondCurrentAccountCall.future;
      await tester.pumpAndSettle();
      expect(fixture.ranchSelection.selectedRanch, isNull);
      expect(find.text('North ranch'), findsNothing);
      pending.complete(_account);
      await refresh;
      await tester.pumpAndSettle();
      expect(find.byType(SessionAccountPage), findsOneWidget);
      expect(fixture.ranchSelection.selectedRanch, isNull);
      expect(find.byKey(const Key('account-selected-ranch')), findsNothing);
    },
  );

  testWidgets(
    'profile deep links remain protected without a validated session',
    (tester) async {
      final fixture = await pumpApp(tester, initialRoute: '/account/profile');
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byKey(const Key('profile-save')), findsNothing);
      expect(fixture.profiles.loadCalls, 0);
    },
  );

  testWidgets(
    'veterinarians can view their profile and logout removes protected data',
    (tester) async {
      final fixture = await pumpApp(
        tester,
        restored: true,
        account: const IamAccount(
          id: '11111111-1111-4111-8111-111111111111',
          email: 'user@example.test',
          role: AccountRole.veterinarian,
          status: 'Active',
          profile: ProfessionalProfile(
            specialty: 'Bovine health',
            licenseNumber: 'TEST-123',
            yearsOfExperience: 5,
          ),
        ),
      );
      await tester.ensureVisible(
        find.byKey(const Key('account-professional-profile')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('account-professional-profile')));
      await tester.pumpAndSettle();
      expect(find.text('Professional profile'), findsWidgets);
      expect(fixture.profiles.loadCalls, 1);
      expect(find.text('Bovine health'), findsOneWidget);
      expect(find.byType(EditableText), findsNothing);
      expect(find.byKey(const Key('profile-save')), findsNothing);
      expect(await fixture.auth.signOut(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.text('Bovine health'), findsNothing);
      expect(fixture.profileService.profile, isNull);
    },
  );

  testWidgets(
    'manager account navigation does not advertise a profile editor',
    (tester) async {
      await pumpApp(tester, restored: true);
      expect(
        find.byKey(const Key('account-professional-profile')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'registration uses an isolated identity and cannot grant workspace access',
    (tester) async {
      final fixture = await pumpApp(tester);
      await fillSignIn(tester);
      await tester.ensureVisible(find.byKey(const Key('login-register')));
      await tester.tap(find.byKey(const Key('login-register')));
      await tester.pumpAndSettle();
      expect(find.text('Create your ICHU account'), findsOneWidget);
      final coveredPassword = find.byKey(
        const Key('login-password'),
        skipOffstage: false,
      );
      expect(
        tester.widget<TextFormField>(coveredPassword).controller!.text,
        isEmpty,
      );
      await tester.enterText(
        find.byKey(const Key('registration-email')),
        'new-user@example.test',
      );
      await tester.ensureVisible(
        find.byKey(const Key('registration-password')),
      );
      await tester.enterText(
        find.byKey(const Key('registration-password')),
        'synthetic-password',
      );
      await tester.ensureVisible(
        find.byKey(const Key('registration-confirmation')),
      );
      await tester.enterText(
        find.byKey(const Key('registration-confirmation')),
        'synthetic-password',
      );
      await tester.ensureVisible(find.byKey(const Key('registration-submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('registration-submit')));
      await tester.pumpAndSettle();
      expect(
        fixture.registration.status,
        RegistrationStatus.awaitingVerification,
      );
      expect(fixture.auth.status, SessionStatus.signedOut);
      expect(fixture.identity.currentUser, isNull);
      expect(fixture.accounts.currentAccountCalls, 0);
      expect(find.byType(SessionAccountPage), findsNothing);
      await tester.tap(find.byTooltip('Back to sign in'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(fixture.registrationIdentity.currentUser, isNull);
    },
  );

  testWidgets(
    'a restored verified workspace redirects registration to account',
    (tester) async {
      final fixture = await pumpApp(
        tester,
        restored: true,
        initialRoute: '/register',
      );
      expect(find.byType(SessionAccountPage), findsOneWidget);
      expect(find.text('Create your ICHU account'), findsNothing);
      expect(fixture.registration.user, isNull);
    },
  );

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
        find.text('Enter a valid email address, up to 254 characters.'),
        findsOneWidget,
      );
      expect(
        find.text('Enter your password, up to 128 characters.'),
        findsOneWidget,
      );
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
      accountFailure: const AuthFailure(AuthFailureCode.accountUnavailable),
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

  testWidgets(
    'server-authorized historical block status is not relabeled active',
    (tester) async {
      await pumpApp(
        tester,
        restored: true,
        account: const IamAccount(
          id: '11111111-1111-4111-8111-111111111111',
          email: 'user@example.test',
          role: AccountRole.ranchManager,
          status: 'TemporarilyBlocked',
        ),
      );
      expect(find.byType(SessionAccountPage), findsOneWidget);
      expect(find.text('Validated by ICHU'), findsOneWidget);
      expect(find.text('Active'), findsNothing);
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
    'failed native sign-out keeps login disabled until retry succeeds',
    (tester) async {
      final fixture = await pumpApp(tester, restored: true);
      fixture.identity.signOutFailure = StateError('private SDK detail');
      expect(await fixture.auth.signOut(), isFalse);
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(fixture.auth.requiresSignOut, isTrue);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('login-submit')))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.byKey(const Key('login-email')));
      await tester.enterText(
        find.byKey(const Key('login-email')),
        'user@example.test',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('sign-out could not finish'), findsOneWidget);
      fixture.identity.signOutFailure = null;
      await tester.ensureVisible(find.text('Sign out'));
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(fixture.auth.requiresSignOut, isFalse);
      expect(fixture.identity.currentUser, isNull);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('login-submit')))
            .onPressed,
        isNotNull,
      );
    },
  );

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
        find.text('Enter a valid email address, up to 254 characters.'),
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
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
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
