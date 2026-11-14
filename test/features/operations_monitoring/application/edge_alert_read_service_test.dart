import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/iam/application/facades/authorized_ranch_session.dart';
import 'package:ichu_mobile_app/features/iam/application/services/auth_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/authentication_lifecycle.dart';
import 'package:ichu_mobile_app/features/iam/application/services/ranch_selection_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_access.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/application/services/edge_alert_read_service.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/edge_alert.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/monitoring_failure.dart';

import '../../../support/fake_edge_alert_repository.dart';
import '../../../support/fake_iam_repositories.dart';

const _ranchA = 'a1111111-1111-4111-8111-111111111111';
const _ranchB = 'b2222222-2222-4222-8222-222222222222';

void main() {
  late _Harness harness;
  late FakeEdgeAlertRepository repository;
  late EdgeAlertReadService service;

  setUp(() async {
    harness = _Harness();
    repository = FakeEdgeAlertRepository();
    await harness.initializeAndSelect(_ranchA);
    service = EdgeAlertReadService(
      access: harness.access,
      edgeAlerts: repository,
    );
  });

  tearDown(() {
    service.dispose();
    harness.dispose();
  });

  test('loads only the selected ranch and accepts an empty page', () async {
    repository.pageResult = _page(_ranchA, 1, 20, 0, const []);

    expect(service.status, EdgeAlertLoadStatus.idle);
    expect(repository.requests, isEmpty);
    expect(await service.load(), isTrue);

    expect(service.status, EdgeAlertLoadStatus.ready);
    expect(service.alerts, isEmpty);
    expect(service.page!.totalCount, 0);
    expect(repository.requests.single.ranchId, _ranchA);
    expect(repository.requests.single.page, 1);
  });

  test('rejects a page containing another ranch', () async {
    repository.pageResult = _page(_ranchA, 1, 20, 1, [_alert(_ranchB)]);

    expect(await service.load(), isFalse);
    expect(service.status, EdgeAlertLoadStatus.unavailable);
    expect(service.error!.code, MonitoringFailureCode.invalidResponse);
    expect(service.alerts, isEmpty);
  });

  test(
    'a ranch change fences a pending result and clears the old snapshot',
    () async {
      final response = Completer<EdgeAlertPage>();
      repository.completer = response;
      final pending = service.load();
      await Future<void>.value();

      expect(harness.selection.select(_ranchB), isTrue);
      expect(service.alerts, isEmpty);
      expect(service.status, EdgeAlertLoadStatus.idle);
      response.complete(_page(_ranchA, 1, 20, 1, [_alert(_ranchA)]));

      expect(await pending, isFalse);
      expect(service.alerts, isEmpty);
      expect(repository.requests.single.ranchId, _ranchA);
    },
  );

  test(
    'permission failures clear data while network failures preserve stale data',
    () async {
      repository.pageResult = _page(_ranchA, 1, 20, 1, [_alert(_ranchA)]);
      expect(await service.load(), isTrue);

      repository.failure = const MonitoringFailure(
        MonitoringFailureCode.forbidden,
      );
      expect(await service.refresh(), isFalse);
      expect(service.status, EdgeAlertLoadStatus.unavailable);
      expect(service.alerts, isEmpty);

      repository.failure = null;
      expect(await service.load(), isTrue);
      repository.failure = const MonitoringFailure(
        MonitoringFailureCode.network,
      );
      expect(await service.refresh(), isFalse);
      expect(service.status, EdgeAlertLoadStatus.stale);
      expect(service.alerts, hasLength(1));

      repository.failure = null;
      repository.pageResult = _page(_ranchA, 1, 20, 1, [
        _alert(_ranchA, suffix: '2'),
      ]);
      expect(await service.retry(), isTrue);
      expect(service.status, EdgeAlertLoadStatus.ready);
      expect(
        service.alerts.single.alertId,
        _alert(_ranchA, suffix: '2').alertId,
      );
    },
  );

  test('unexpected failures are sanitized and retryable', () async {
    repository.failure = StateError('private transport detail');

    expect(await service.load(), isFalse);
    expect(service.status, EdgeAlertLoadStatus.unavailable);
    expect(service.error!.code, MonitoringFailureCode.unknown);
    expect(
      service.error.toString(),
      isNot(contains('private transport detail')),
    );

    repository.failure = null;
    repository.pageResult = _page(_ranchA, 1, 20, 0, const []);
    expect(await service.retry(), isTrue);
    expect(service.status, EdgeAlertLoadStatus.ready);
  });

  test('logout hides the loaded page and prevents a new read', () async {
    repository.pageResult = _page(_ranchA, 1, 20, 1, [_alert(_ranchA)]);
    expect(await service.load(), isTrue);

    await harness.auth.signOut();

    expect(service.hasContext, isFalse);
    expect(service.alerts, isEmpty);
    expect(service.status, EdgeAlertLoadStatus.idle);
    expect(await service.load(), isFalse);
    expect(repository.requests, hasLength(1));
  });
}

EdgeAlert _alert(String ranchId, {String suffix = '1'}) => EdgeAlert(
  alertId: 'a8888888-8888-4888-8888-00000000000$suffix',
  ranchId: ranchId,
  cattleId: 'c3333333-3333-4333-8333-333333333333',
  deviceId: 'd4444444-4444-4444-8444-444444444444',
  gatewayId: 'e5555555-5555-4555-8555-555555555555',
  type: EdgeAlertType.temperature,
  severity: EdgeAlertSeverity.warning,
  raisedAt: DateTime.utc(2026, 1, 1),
  receivedAt: DateTime.utc(2026, 1, 1, 0, 0, 1),
  detectedValue: 40.2,
  unit: 'celsius',
  thresholdMinValue: 37.5,
  thresholdMaxValue: 39.5,
  configurationRevision: 1,
  readingIds: const <String>['b7777777-7777-4777-8777-777777777777'],
);

EdgeAlertPage _page(
  String ranchId,
  int page,
  int pageSize,
  int totalCount,
  List<EdgeAlert> items,
) => EdgeAlertPage(
  page: page,
  pageSize: pageSize,
  totalCount: totalCount,
  items: items,
);

RanchAccess _ranch(String id) => RanchAccess(
  ranchId: id,
  scope: AccessScope.read,
  name: 'Ranch $id',
  region: 'Synthetic region',
  district: 'Synthetic district',
);

final class _Harness {
  _Harness()
    : identity = FakeAuthenticationRepository(),
      accounts = FakeAccountRepository(
        account: const IamAccount(
          id: 'e5555555-5555-4555-8555-555555555555',
          email: 'user@example.test',
          role: AccountRole.ranchManager,
          status: 'Active',
        ),
        ranches: <RanchAccess>[_ranch(_ranchA), _ranch(_ranchB)],
      ) {
    lifecycle = AuthenticationLifecycle(identity);
    auth = AuthService(authentication: lifecycle, accounts: accounts);
    selection = RanchSelectionService(session: auth);
    access = AuthorizedRanchSession(
      session: auth,
      selection: selection,
      authentication: identity,
    );
  }

  final FakeAuthenticationRepository identity;
  final FakeAccountRepository accounts;
  late final AuthenticationLifecycle lifecycle;
  late final AuthService auth;
  late final RanchSelectionService selection;
  late final AuthorizedRanchSession access;

  Future<void> initializeAndSelect(String ranchId) async {
    await auth.initialize();
    expect(selection.select(ranchId), isTrue);
  }

  void dispose() {
    access.dispose();
    selection.dispose();
    auth.dispose();
    lifecycle.dispose();
    unawaited(identity.close());
  }
}
