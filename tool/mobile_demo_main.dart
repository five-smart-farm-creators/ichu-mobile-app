// Screenshot-only runner. It composes the real mobile UI with test fakes and
// synthetic fixtures; never use this target as a production build.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:ichu_mobile_app/app.dart';
import 'package:ichu_mobile_app/features/cattle_information/application/facades/cattle_lookup_facade.dart';
import 'package:ichu_mobile_app/features/cattle_information/application/services/cattle_management_service.dart';
import 'package:ichu_mobile_app/features/cattle_information/application/services/cattle_read_service.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle.dart';
import 'package:ichu_mobile_app/features/iam/application/facades/authorized_ranch_session.dart';
import 'package:ichu_mobile_app/features/iam/application/services/auth_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/authentication_lifecycle.dart';
import 'package:ichu_mobile_app/features/iam/application/services/herd_advisory_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/professional_profile_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/ranch_selection_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/registration_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/herd_advisory.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_access.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/application/services/alert_read_service.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/application/services/edge_alert_read_service.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/application/services/field_record_service.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/application/services/monitoring_read_service.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/application/services/waterer_read_service.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/edge_alert.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/field_record.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/field_record_sync.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/ranch_alert.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/repositories/field_cattle_directory.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/infrastructure/adapters/field_cattle_directory_adapter.dart';
import 'package:ichu_mobile_app/shared/application/services/language_service.dart';
import 'package:ichu_mobile_app/shared/domain/model/app_language.dart';

import '../test/support/fake_alert_repository.dart';
import '../test/support/fake_cattle_command_repository.dart';
import '../test/support/fake_cattle_repository.dart';
import '../test/support/fake_edge_alert_repository.dart';
import '../test/support/fake_field_record_sync_repository.dart';
import '../test/support/fake_herd_advisory_repository.dart';
import '../test/support/fake_iam_repositories.dart';
import '../test/support/fake_monitoring_repository.dart';
import '../test/support/fake_professional_profile_repository.dart';
import '../test/support/fake_registration_repositories.dart';
import '../test/support/memory_field_record_repository.dart';
import '../test/support/memory_language_preferences.dart';
import '../test/support/waterer_test_support.dart';

const _ranchId = '22222222-2222-4222-8222-222222222222';
const _cattleId = '33333333-3333-4333-8333-333333333333';
const _ranch = RanchAccess(
  ranchId: _ranchId,
  scope: AccessScope.manage,
  name: 'Estancia Las Nubes',
  region: 'Puno',
  district: 'Ayaviri',
);
const _account = IamAccount(
  id: '11111111-1111-4111-8111-111111111111',
  email: 'user@example.test',
  role: AccountRole.ranchManager,
  status: 'Active',
);
const _initialRoute = String.fromEnvironment(
  'ICHU_DEMO_ROUTE',
  defaultValue: '/account',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final language = LanguageService(
    MemoryLanguagePreferences(language: AppLanguage.spanish),
  );
  await language.initialize();

  final identity = FakeAuthenticationRepository();
  final registrationIdentity = FakeIdentityRegistrationRepository();
  final accounts = FakeAccountRepository(
    account: _account,
    ranches: const <RanchAccess>[_ranch],
  );
  final lifecycle = AuthenticationLifecycle(identity);
  final registrationLifecycle = AuthenticationLifecycle(registrationIdentity);
  final authentication = AuthService(
    authentication: lifecycle,
    accounts: accounts,
  );
  final ranchSelection = RanchSelectionService(session: authentication);
  final ranchAccess = AuthorizedRanchSession(
    session: authentication,
    selection: ranchSelection,
    authentication: identity,
  );
  unawaited(
    authentication.initialize().then((_) {
      ranchSelection.select(_ranchId);
    }),
  );

  final cattleRepository = FakeCattleRepository()
    ..listResult = <Cattle>[
      syntheticCattle(ranchId: _ranchId, id: _cattleId, earTag: 'ICHU-042'),
      syntheticCattle(
        ranchId: _ranchId,
        id: '44444444-4444-4444-8444-444444444444',
        earTag: 'ICHU-108',
      ),
    ];
  final cattleService = CattleReadService(
    access: ranchAccess,
    cattle: cattleRepository,
  );
  final FieldCattleDirectory cattleDirectory = FieldCattleDirectoryAdapter(
    lookup: CattleLookupFacade(access: ranchAccess, cattle: cattleRepository),
  );
  final cattleManagementService = CattleManagementService(
    access: ranchAccess,
    commands: FakeCattleCommandRepository(),
  );

  final fieldStorage = MemoryFieldRecordRepository();
  final fieldSync = FakeFieldRecordSyncRepository()
    ..respond = (records) => <FieldRecordSyncResult>[
      for (final pending in records)
        FieldRecordSyncResult(
          operationId: pending.operationId,
          status: FieldRecordSyncStatus.conflict,
          reason: 'Synthetic conflict for screenshot fixture',
        ),
    ];
  final fieldRecord = FieldRecord(
    operationId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    ranchId: _ranchId,
    cattleId: _cattleId,
    cattleEarTag: 'ICHU-042',
    type: FieldRecordType.healthEvent,
    occurredAt: DateTime.utc(2026, 11, 15, 10),
    observation: 'Actividad baja observada durante la ronda',
  );
  await fieldStorage.appendPending(
    accountId: _account.id,
    ranchId: _ranchId,
    record: fieldRecord,
  );
  await fieldStorage.applySyncResults(
    accountId: _account.id,
    ranchId: _ranchId,
    submitted: <FieldRecord>[fieldRecord],
    results: <FieldRecordSyncResult>[
      FieldRecordSyncResult(
        operationId: fieldRecord.operationId,
        status: FieldRecordSyncStatus.conflict,
      ),
    ],
  );
  await fieldStorage.cacheCattleOptions(
    accountId: _account.id,
    ranchId: _ranchId,
    options: <FieldCattleOption>[
      FieldCattleOption(
        cattleId: _cattleId,
        ranchId: _ranchId,
        earTag: 'ICHU-042',
      ),
      FieldCattleOption(
        cattleId: '44444444-4444-4444-8444-444444444444',
        ranchId: _ranchId,
        earTag: 'ICHU-108',
      ),
    ],
  );
  final fieldRecordService = FieldRecordService(
    access: ranchAccess,
    repository: fieldStorage,
    syncRepository: fieldSync,
  );

  final monitoringService = MonitoringReadService(
    access: ranchAccess,
    monitoring: FakeMonitoringRepository(),
  );
  final alertService = AlertReadService(
    access: ranchAccess,
    alerts: FakeAlertRepository()
      ..pageResult = AlertPage(
        page: 1,
        pageSize: 20,
        totalCount: 3,
        items: <RanchAlert>[
          _alert(
            alertId: '55555555-5555-4555-8555-555555555555',
            severity: AlertSeverity.critical,
            type: AlertType.temperature,
            value: 40.2,
            raisedAt: DateTime.utc(2026, 11, 14, 8),
          ),
          _alert(
            alertId: '66666666-6666-4666-8666-666666666666',
            severity: AlertSeverity.warning,
            type: AlertType.activity,
            value: 21,
            raisedAt: DateTime.utc(2026, 11, 15, 9),
          ),
          _alert(
            alertId: '77777777-7777-4777-8777-777777777777',
            severity: AlertSeverity.informative,
            type: AlertType.heartRate,
            value: 68,
            raisedAt: DateTime.utc(2026, 11, 15, 7),
          ),
        ],
      ),
  );
  final edgeAlertService = EdgeAlertReadService(
    access: ranchAccess,
    edgeAlerts: FakeEdgeAlertRepository()
      ..pageResult = EdgeAlertPage(
        page: 1,
        pageSize: 20,
        totalCount: 0,
        items: const <EdgeAlert>[],
      ),
  );
  final watererService = WatererReadService(
    access: ranchAccess,
    waterers: FakeWatererRepository(),
  );
  final herdAdvisoryService = HerdAdvisoryService(
    advisories: FakeHerdAdvisoryRepository(
      advisories: <HerdAdvisory>[
        HerdAdvisory(
          id: '88888888-8888-4888-8888-888888888888',
          veterinarianId: '99999999-9999-4999-8999-999999999999',
          ranchId: _ranchId,
          reason: 'Seguimiento preventivo de salud del hato',
          status: HerdAdvisoryStatus.granted,
          scope: AccessScope.clinicalWrite,
          requestedAt: DateTime.utc(2026, 11, 12),
          grantedAt: DateTime.utc(2026, 11, 13),
          expiresAt: DateTime.utc(2027, 1, 15),
        ),
      ],
    ),
    selection: ranchSelection,
  );
  final profileService = ProfessionalProfileService(
    session: authentication,
    profiles: FakeProfessionalProfileRepository(account: _account),
  );
  final registration = RegistrationService(
    authentication: registrationLifecycle,
    accounts: FakeAccountRegistrationRepository(),
  );

  runApp(
    IchuApp(
      language: language,
      authentication: authentication,
      registration: registration,
      profileService: profileService,
      ranchSelection: ranchSelection,
      cattleService: cattleService,
      herdAdvisoryService: herdAdvisoryService,
      cattleManagementService: cattleManagementService,
      monitoringService: monitoringService,
      alertService: alertService,
      edgeAlertService: edgeAlertService,
      watererService: watererService,
      fieldRecordService: fieldRecordService,
      fieldCattleDirectory: cattleDirectory,
      initialRoute: _initialRoute,
      demoBannerText: 'CAPTURA DEMOSTRATIVA · DATOS SINTÉTICOS',
      onDispose: () {
        watererService.dispose();
        edgeAlertService.dispose();
        alertService.dispose();
        fieldRecordService.dispose();
        monitoringService.dispose();
        cattleManagementService.dispose();
        cattleService.dispose();
        ranchAccess.dispose();
        profileService.dispose();
        ranchSelection.dispose();
        authentication.dispose();
        registration.dispose();
        lifecycle.dispose();
        registrationLifecycle.dispose();
        unawaited(identity.close());
        unawaited(registrationIdentity.close());
        language.dispose();
      },
    ),
  );
}

RanchAlert _alert({
  required String alertId,
  required AlertSeverity severity,
  required AlertType type,
  required double value,
  required DateTime raisedAt,
}) => RanchAlert(
  alertId: alertId,
  ranchId: _ranchId,
  cattleId: _cattleId,
  deviceId: 'aaaaaaaa-1111-4111-8111-111111111111',
  gatewayId: 'bbbbbbbb-2222-4222-8222-222222222222',
  type: type,
  severity: severity,
  status: AlertStatus.pending,
  origin: AlertOrigin.edgeGateway,
  raisedAt: raisedAt,
  receivedAt: raisedAt.add(const Duration(seconds: 4)),
  detectedValue: value,
  unit: type == AlertType.temperature ? 'celsius' : 'index',
  thresholdMinValue: type == AlertType.temperature ? 37.5 : 30,
  thresholdMaxValue: type == AlertType.temperature ? 39.5 : 70,
  configurationRevision: 1,
  version: 1,
  readingIds: const <String>['cccccccc-3333-4333-8333-333333333333'],
);
