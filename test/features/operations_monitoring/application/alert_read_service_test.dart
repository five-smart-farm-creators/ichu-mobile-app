import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/iam/application/facades/authorized_ranch_session.dart';
import 'package:ichu_mobile_app/features/iam/application/services/auth_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/authentication_lifecycle.dart';
import 'package:ichu_mobile_app/features/iam/application/services/ranch_selection_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_user.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_access.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/application/services/alert_read_service.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/alert_acknowledgement.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/alert_acknowledgement_result.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/alert_search.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/monitoring_failure.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/ranch_alert.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/repositories/alert_repository.dart';

import '../../../support/fake_alert_repository.dart';
import '../../../support/fake_iam_repositories.dart';

void main() {
  late _Harness harness;
  late FakeAlertRepository repository;
  late AlertReadService service;

  setUp(() async {
    harness = _Harness();
    repository = FakeAlertRepository();
    service = harness.createService(repository);
    await harness.initializeAndSelect(_ranchA);
  });
  tearDown(() {
    service.dispose();
    harness.dispose();
  });

  test(
    'does not read on construction and a missing result is not fabricated',
    () async {
      expect(repository.requests, isEmpty);
      expect(service.status, AlertLoadStatus.idle);
      expect(await service.load(), isFalse);
      expect(service.error!.code, MonitoringFailureCode.invalidResponse);
      expect(service.alerts, isEmpty);
      expect(service.totalCount, isNull);
    },
  );

  test(
    'loads an empty page and uses the server count for pagination',
    () async {
      repository.pageResult = _page(_ranchA, 1, 2, 5, const []);
      expect(await service.load(query: const AlertSearch(pageSize: 2)), isTrue);
      expect(service.status, AlertLoadStatus.ready);
      expect(service.alerts, isEmpty);
      expect(service.totalCount, 5);
      expect(service.canGoNext, isTrue);
      expect(repository.requests.single.query, const AlertSearch(pageSize: 2));
    },
  );

  test('short page and count boundary govern next-page availability', () async {
    repository.pageResult = _page(_ranchA, 1, 3, 4, [
      _alert(_ranchA, 'alert-1'),
    ]);
    expect(await service.load(query: const AlertSearch(pageSize: 3)), isTrue);
    expect(service.canGoNext, isTrue);
    repository.pageResult = _page(_ranchA, 2, 3, 4, [
      _alert(_ranchA, 'alert-2'),
    ]);
    expect(await service.nextPage(), isTrue);
    expect(service.query.page, 2);
    expect(service.canGoNext, isFalse);
    expect(service.canGoPrevious, isTrue);
    repository.pageResult = _page(_ranchA, 1, 3, 4, [
      _alert(_ranchA, 'alert-back'),
    ]);
    expect(await service.previousPage(), isTrue);
    expect(service.query.page, 1);
    expect(service.alerts.single.alertId, _alertId('alert-back'));
  });

  test(
    'count smaller than rows is accepted for concurrent server snapshots',
    () async {
      repository.pageResult = _page(_ranchA, 1, 3, 0, [
        _alert(_ranchA, 'alert-1'),
        _alert(_ranchA, 'alert-2'),
      ]);
      expect(await service.load(query: const AlertSearch(pageSize: 3)), isTrue);
      expect(service.alerts, hasLength(2));
      expect(service.totalCount, 0);
      expect(service.canGoNext, isFalse);
    },
  );

  test(
    'never appends pages and retains status filter through navigation',
    () async {
      const query = AlertSearch(status: AlertStatus.pending, pageSize: 1);
      repository.pageResult = _page(_ranchA, 1, 1, 2, [
        _alert(_ranchA, 'alert-1'),
      ]);
      expect(await service.load(query: query), isTrue);
      repository.pageResult = _page(_ranchA, 2, 1, 2, [
        _alert(_ranchA, 'alert-2'),
      ]);
      expect(await service.nextPage(), isTrue);
      expect(service.alerts.single.alertId, _alertId('alert-2'));
      expect(
        service.query,
        const AlertSearch(status: AlertStatus.pending, page: 2, pageSize: 1),
      );
      expect(repository.requests.last.query.status, AlertStatus.pending);
    },
  );

  test('display list is immutable', () async {
    repository.pageResult = _page(_ranchA, 1, 20, 1, [
      _alert(_ranchA, 'alert-1'),
    ]);
    await service.load();
    expect(() => service.alerts.clear(), throwsUnsupportedError);
  });

  test('acknowledgement updates the loaded cloud snapshot', () async {
    final pendingAlert = _alert(_ranchA, 'alert-1');
    repository.pageResult = _page(_ranchA, 1, 20, 1, [pendingAlert]);
    expect(await service.load(), isTrue);
    final request = AlertAcknowledgement(
      alertId: pendingAlert.alertId,
      operationId: 'f1111111-1111-4111-8111-111111111111',
      finding: 'Observed the cloud alert',
      action: 'Recorded for review',
      expectedVersion: pendingAlert.version,
    );
    repository.acknowledgementResult = AlertAcknowledgementResult.acknowledged(
      _alert(_ranchA, 'alert-1', AlertStatus.acknowledged),
    );

    final result = await service.acknowledge(pendingAlert, request);

    expect(result.outcome, AlertAcknowledgementOutcome.acknowledged);
    expect(service.alerts.single.status, AlertStatus.acknowledged);
    expect(service.totalCount, 1);
    expect(repository.acknowledgements.single.ranchId, _ranchA);
    expect(repository.acknowledgements.single.request, same(request));
    expect(service.isAcknowledging, isFalse);
  });

  test(
    'pending-filter acknowledgement removes the row and adjusts the count',
    () async {
      final pendingAlert = _alert(_ranchA, 'alert-1');
      repository.pageResult = _page(_ranchA, 1, 20, 1, [pendingAlert]);
      const query = AlertSearch(status: AlertStatus.pending);
      expect(await service.load(query: query), isTrue);
      final request = AlertAcknowledgement(
        alertId: pendingAlert.alertId,
        operationId: 'f2222222-2222-4222-8222-222222222222',
        finding: 'Observed',
        expectedVersion: pendingAlert.version,
      );
      repository.pageResult = _page(_ranchA, 1, 20, 0, const []);
      repository.acknowledgementResult =
          AlertAcknowledgementResult.acknowledged(
            _alert(_ranchA, 'alert-1', AlertStatus.acknowledged),
          );

      await service.acknowledge(pendingAlert, request);

      expect(service.query, query);
      expect(service.alerts, isEmpty);
      expect(service.totalCount, 0);
      expect(service.status, AlertLoadStatus.ready);
      expect(repository.requests, hasLength(2));
    },
  );

  test(
    'conflict performs a fresh list read without retrying the write',
    () async {
      final pendingAlert = _alert(_ranchA, 'alert-1');
      repository.pageResult = _page(_ranchA, 1, 20, 1, [pendingAlert]);
      expect(await service.load(), isTrue);
      final request = AlertAcknowledgement(
        alertId: pendingAlert.alertId,
        operationId: 'f3333333-3333-4333-8333-333333333333',
        finding: 'Observed',
        expectedVersion: pendingAlert.version,
      );
      final acknowledged = _alert(_ranchA, 'alert-1', AlertStatus.acknowledged);
      repository.acknowledgementResult = AlertAcknowledgementResult.conflict(
        currentAlert: acknowledged,
      );
      repository.pageResult = _page(_ranchA, 1, 20, 1, [acknowledged]);

      final result = await service.acknowledge(pendingAlert, request);

      expect(result.outcome, AlertAcknowledgementOutcome.conflict);
      expect(repository.acknowledgements, hasLength(1));
      expect(repository.requests, hasLength(2));
      expect(service.alerts.single.status, AlertStatus.acknowledged);
    },
  );

  test(
    'retry after an uncertain failure reuses the same operation request',
    () async {
      final pendingAlert = _alert(_ranchA, 'alert-1');
      repository.pageResult = _page(_ranchA, 1, 20, 1, [pendingAlert]);
      expect(await service.load(), isTrue);
      final request = AlertAcknowledgement(
        alertId: pendingAlert.alertId,
        operationId: 'f4444444-4444-4444-8444-444444444444',
        finding: 'Observed',
        expectedVersion: pendingAlert.version,
      );
      repository.acknowledgementFailure = const MonitoringFailure(
        MonitoringFailureCode.network,
      );

      await expectLater(
        service.acknowledge(pendingAlert, request),
        throwsA(
          isA<MonitoringFailure>().having(
            (failure) => failure.code,
            'code',
            MonitoringFailureCode.network,
          ),
        ),
      );
      expect(service.isAcknowledging, isFalse);
      repository.acknowledgementFailure = null;
      repository.acknowledgementResult =
          AlertAcknowledgementResult.acknowledged(
            _alert(_ranchA, 'alert-1', AlertStatus.acknowledged),
          );

      await service.acknowledge(pendingAlert, request);

      expect(repository.acknowledgements, hasLength(2));
      expect(
        repository.acknowledgements.map((entry) => entry.request.operationId),
        everyElement(request.operationId),
      );
      expect(
        repository.acknowledgements.map((entry) => entry.request.finding),
        everyElement(request.finding),
      );
    },
  );

  test('a ranch change fences a pending acknowledgement response', () async {
    final pendingAlert = _alert(_ranchA, 'alert-1');
    repository.pageResult = _page(_ranchA, 1, 20, 1, [pendingAlert]);
    expect(await service.load(), isTrue);
    final request = AlertAcknowledgement(
      alertId: pendingAlert.alertId,
      operationId: 'f5555555-5555-4555-8555-555555555555',
      finding: 'Observed',
      expectedVersion: pendingAlert.version,
    );
    final response = Completer<AlertAcknowledgementResult>();
    repository.acknowledgementCompleter = response;
    final pending = service.acknowledge(pendingAlert, request);
    await Future<void>.value();
    await harness.select(_ranchB);
    response.complete(
      AlertAcknowledgementResult.acknowledged(
        _alert(_ranchA, 'alert-1', AlertStatus.acknowledged),
      ),
    );

    await expectLater(
      pending,
      throwsA(
        isA<MonitoringFailure>().having(
          (failure) => failure.code,
          'code',
          MonitoringFailureCode.contextUnavailable,
        ),
      ),
    );
    expect(service.alerts, isEmpty);
    expect(service.status, AlertLoadStatus.idle);
  });

  test('invalid page search is local and preserves no stale page', () async {
    repository.pageResult = _page(_ranchA, 1, 20, 1, [
      _alert(_ranchA, 'alert-1'),
    ]);
    await service.load();
    final calls = repository.calls;
    expect(await service.load(query: const AlertSearch(page: 0)), isFalse);
    expect(repository.calls, calls);
    expect(service.error!.code, MonitoringFailureCode.invalidSearch);
    expect(service.alerts, isEmpty);
    expect(service.totalCount, isNull);
  });

  test(
    'missing ranch context reports a failure without a repository call',
    () async {
      harness.selection.clearSelection();
      expect(service.hasContext, isFalse);
      expect(await service.load(), isFalse);
      expect(service.error, isNull);
      expect(repository.calls, 0);
    },
  );

  test('offset overflow cannot issue a next-page request', () async {
    const query = AlertSearch(page: AlertSearch.maximumInt32, pageSize: 1);
    repository.pageResult = _page(
      _ranchA,
      query.page,
      1,
      AlertSearch.maximumInt32,
      const [],
    );
    expect(await service.load(query: query), isTrue);
    expect(service.canGoNext, isFalse);
    expect(await service.nextPage(), isFalse);
    expect(repository.calls, 1);
  });

  test(
    'returns the exact future for a matching pending read and handles reentry',
    () async {
      final pendingResult = Completer<AlertPage>();
      repository.completer = pendingResult;
      Future<bool>? reentrant;
      void listener() {
        if (service.status == AlertLoadStatus.loading) {
          reentrant ??= service.load();
        }
      }

      service.addListener(listener);
      final first = service.load();
      expect(identical(first, reentrant), isTrue);
      expect(identical(first, service.load()), isTrue);
      await Future<void>.value();
      expect(repository.calls, 1);
      pendingResult.complete(_page(_ranchA, 1, 20, 0, const []));
      expect(await first, isTrue);
      service.removeListener(listener);
    },
  );

  test(
    'new query supersedes pending result and old permission failure cannot clear it',
    () async {
      final first = Completer<AlertPage>();
      final second = Completer<AlertPage>();
      repository.completer = first;
      final oldRead = service.load();
      await Future<void>.value();
      repository.completer = second;
      final newQuery = const AlertSearch(status: AlertStatus.acknowledged);
      final newRead = service.load(query: newQuery);
      await Future<void>.value();
      second.complete(
        _page(_ranchA, 1, 20, 1, [
          _alert(_ranchA, 'alert-new', AlertStatus.acknowledged),
        ]),
      );
      expect(await newRead, isTrue);
      first.completeError(
        const MonitoringFailure(MonitoringFailureCode.forbidden),
      );
      expect(await oldRead, isFalse);
      expect(service.alerts.single.alertId, _alertId('alert-new'));
      expect(service.error, isNull);
    },
  );

  test('A to B to A context changes fence the original response', () async {
    final first = Completer<AlertPage>();
    repository.completer = first;
    final pending = service.load();
    await Future<void>.value();
    await harness.select(_ranchB);
    await harness.select(_ranchA);
    first.complete(_page(_ranchA, 1, 20, 1, [_alert(_ranchA, 'old')]));
    expect(await pending, isFalse);
    expect(service.alerts, isEmpty);
    expect(service.status, AlertLoadStatus.idle);
  });

  test(
    'context switch clears query/data and does not automatically read',
    () async {
      repository.pageResult = _page(_ranchA, 1, 10, 1, [
        _alert(_ranchA, 'alert-1'),
      ]);
      expect(
        await service.load(
          query: const AlertSearch(status: AlertStatus.pending, pageSize: 10),
        ),
        isTrue,
      );
      final revision = service.revision;
      await harness.select(_ranchB);
      expect(service.revision, revision + 1);
      expect(service.query, const AlertSearch());
      expect(service.alerts, isEmpty);
      expect(service.totalCount, isNull);
      expect(service.status, AlertLoadStatus.idle);
      expect(repository.calls, 1);
    },
  );

  test(
    'configuration, network, unauthenticated, and forbidden require explicit retry',
    () async {
      repository.configured = false;
      expect(await service.load(), isFalse);
      expect(service.error!.code, MonitoringFailureCode.configuration);
      expect(repository.calls, 0);
      repository.configured = true;
      for (final code in [
        MonitoringFailureCode.network,
        MonitoringFailureCode.unauthenticated,
        MonitoringFailureCode.forbidden,
      ]) {
        repository.failure = MonitoringFailure(code);
        expect(await service.load(), isFalse);
        expect(service.error!.code, code);
        expect(service.alerts, isEmpty);
        repository.failure = null;
        repository.pageResult = _page(_ranchA, 1, 20, 0, const []);
        expect(await service.load(), isTrue);
      }
    },
  );

  test('synchronous port throws do not latch retry', () async {
    final throwing = _ThrowingRepository();
    final other = harness.createService(throwing);
    expect(await other.load(), isFalse);
    expect(other.error!.code, MonitoringFailureCode.unknown);
    throwing.fail = false;
    expect(await other.load(), isTrue);
    expect(throwing.calls, 2);
    other.dispose();
  });

  test(
    'rejects wrong tenant, duplicate IDs, wrong envelope, and wrong status',
    () async {
      final invalidPages = [
        _page(_ranchA, 1, 20, 1, [_alert(_ranchB, 'wrong-ranch')]),
        _page(_ranchA, 1, 20, 2, [
          _alert(_ranchA, 'dup'),
          _alert(_ranchA, 'DUP'),
        ]),
        _page(_ranchA, 2, 20, 1, [_alert(_ranchA, 'wrong-page')]),
        _page(_ranchA, 1, 20, -1, const []),
        _page(_ranchA, 1, 1, 1, [
          _alert(_ranchA, 'one'),
          _alert(_ranchA, 'two'),
        ]),
        _page(_ranchA, 1, 20, 1, [
          _alert(_ranchA, 'wrong-status', AlertStatus.acknowledged),
        ]),
      ];
      for (final page in invalidPages) {
        repository.pageResult = page;
        expect(
          await service.load(
            query: const AlertSearch(status: AlertStatus.pending),
          ),
          isFalse,
        );
        expect(service.error!.code, MonitoringFailureCode.invalidResponse);
      }
    },
  );

  test(
    'logout fences a pending result and disposal suppresses late notification',
    () async {
      final pendingResult = Completer<AlertPage>();
      repository.completer = pendingResult;
      final pending = service.load();
      await Future<void>.value();
      await harness.auth.signOut();
      pendingResult.complete(_page(_ranchA, 1, 20, 0, const []));
      expect(await pending, isFalse);

      final again = Completer<AlertPage>();
      repository.completer = again;
      await harness.auth.signIn('user@example.test', 'synthetic-password');
      await harness.select(_ranchA);
      final disposedRead = service.load();
      await Future<void>.value();
      var notifications = 0;
      service.addListener(() => notifications++);
      service.dispose();
      again.complete(_page(_ranchA, 1, 20, 0, const []));
      expect(await disposedRead, isFalse);
      expect(notifications, 0);
      expect(service.alerts, isEmpty);
    },
  );

  test('silent identity drift hides loaded data without notifying', () async {
    repository.pageResult = _page(_ranchA, 1, 20, 1, [
      _alert(_ranchA, 'alert-1'),
    ]);
    expect(await service.load(), isTrue);
    var notifications = 0;
    service.addListener(() => notifications++);
    harness.identity.user = const AuthUser(
      uid: 'other-uid',
      email: 'user@example.test',
      emailVerified: true,
    );
    expect(service.alerts, isEmpty);
    expect(service.status, AlertLoadStatus.idle);
    expect(service.canLoad, isFalse);
    expect(notifications, 0);
  });

  test('unrelated IAM notifications preserve page and revision', () async {
    repository.pageResult = _page(_ranchA, 1, 20, 1, [
      _alert(_ranchA, 'alert-1'),
    ]);
    await service.load();
    final rows = service.alerts;
    final revision = service.revision;
    harness.auth.clearError();
    await harness.select(_ranchA);
    expect(service.alerts, rows);
    expect(service.revision, revision);
    expect(repository.calls, 1);
  });

  for (final account in [
    _account,
    const IamAccount(
      id: 'f5555555-5555-4555-8555-555555555555',
      email: 'user@example.test',
      role: AccountRole.ranchManager,
      status: 'Active',
    ),
    const IamAccount(
      id: _accountId,
      email: 'user@example.test',
      role: AccountRole.veterinarian,
      status: 'Active',
    ),
  ]) {
    test(
      'revalidation ${account.id}/${account.role.name} rejects the previous alert page',
      () async {
        final response = Completer<AlertPage>();
        repository.completer = response;
        final oldContext = harness.access.context;
        final old = service.load();
        await Future<void>.value();
        final pendingAccount = Completer<IamAccount>();
        harness.accounts.currentAccountCompleter = pendingAccount;
        final validating = harness.auth.refresh();
        await harness.accounts.secondCurrentAccountCall.future;
        expect(service.alerts, isEmpty);
        expect(service.totalCount, isNull);
        pendingAccount.complete(account);
        await validating;
        await harness.select(_ranchA);
        expect(harness.access.context, isNot(same(oldContext)));
        response.complete(_page(_ranchA, 1, 20, 1, [_alert(_ranchA, 'old')]));
        expect(await old, isFalse);
        expect(service.alerts, isEmpty);
        repository.completer = null;
        repository.pageResult = _page(_ranchA, 1, 20, 0, const []);
        expect(await service.load(), isTrue);
        expect(repository.calls, 2);
      },
    );
  }

  test(
    'same UID relogin does not revive an earlier pending alert response',
    () async {
      final response = Completer<AlertPage>();
      repository.completer = response;
      final old = service.load();
      await Future<void>.value();
      await harness.auth.signOut();
      expect(
        await harness.auth.signIn('user@example.test', 'synthetic-password'),
        isTrue,
      );
      await harness.select(_ranchA);
      response.complete(_page(_ranchA, 1, 20, 1, [_alert(_ranchA, 'old')]));
      expect(await old, isFalse);
      expect(service.alerts, isEmpty);
      expect(service.totalCount, isNull);
    },
  );

  testWidgets(
    'expired authorization hides alert rows and count before timer notification',
    (tester) async {
      var now = DateTime.utc(2026, 11, 12);
      final expiration = now.add(const Duration(minutes: 1));
      final expiring = _Harness(
        now: () => now,
        ranches: [
          RanchAccess(
            ranchId: _ranchA,
            scope: AccessScope.read,
            name: 'Expiring fixture ranch',
            region: 'Synthetic region',
            district: 'Synthetic district',
            expiresAt: expiration,
          ),
        ],
      );
      final data = FakeAlertRepository()
        ..pageResult = _page(_ranchA, 1, 20, 1, [_alert(_ranchA, 'alert-1')]);
      final monitored = expiring.createService(data);
      try {
        await expiring.initializeAndSelect(_ranchA);
        final read = monitored.load();
        await tester.pump();
        expect(await read, isTrue);
        var notifications = 0;
        monitored.addListener(() => notifications++);
        now = expiration;
        expect(monitored.alerts, isEmpty);
        expect(monitored.totalCount, isNull);
        expect(monitored.canLoad, isFalse);
        expect(notifications, 0);
        await tester.pump(const Duration(minutes: 1));
        expect(notifications, 1);
        expect(data.calls, 1);
      } finally {
        expiring.dispose();
      }
    },
  );
}

const String _ranchA = 'a1111111-1111-4111-8111-111111111111';
const String _ranchB = 'b2222222-2222-4222-8222-222222222222';
const String _accountId = 'e5555555-5555-4555-8555-555555555555';
const _account = IamAccount(
  id: _accountId,
  email: 'user@example.test',
  role: AccountRole.ranchManager,
  status: 'Active',
);

RanchAlert _alert(
  String ranchId,
  String id, [
  AlertStatus status = AlertStatus.pending,
]) => syntheticRanchAlert(
  ranchId: ranchId,
  alertId: _alertId(id),
  status: status,
);

String _alertId(String alias) {
  const names = [
    'alert-1',
    'alert-2',
    'alert-back',
    'alert-new',
    'old',
    'wrong-ranch',
    'dup',
    'wrong-page',
    'one',
    'two',
    'wrong-status',
  ];
  final index = names.indexOf(alias.toLowerCase());
  assert(index >= 0);
  final id =
      'a8888888-8888-4888-8888-${(index + 1).toString().padLeft(12, '0')}';
  return alias == alias.toUpperCase() ? id.toUpperCase() : id;
}

AlertPage _page(
  String ranchId,
  int page,
  int pageSize,
  int totalCount,
  List<RanchAlert> items,
) => AlertPage(
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
  _Harness({DateTime Function()? now, List<RanchAccess>? ranches})
    : identity = FakeAuthenticationRepository(),
      accounts = FakeAccountRepository(
        account: _account,
        ranches: ranches ?? <RanchAccess>[_ranch(_ranchA), _ranch(_ranchB)],
      ) {
    lifecycle = AuthenticationLifecycle(identity);
    auth = AuthService(authentication: lifecycle, accounts: accounts);
    selection = RanchSelectionService(session: auth, now: now);
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
  final services = <AlertReadService>[];

  AlertReadService createService(AlertRepository alerts) {
    final created = AlertReadService(access: access, alerts: alerts);
    services.add(created);
    return created;
  }

  Future<void> initializeAndSelect(String ranchId) async {
    await auth.initialize();
    await select(ranchId);
  }

  Future<void> select(String ranchId) async =>
      expect(selection.select(ranchId), isTrue);

  void dispose() {
    for (final service in services) {
      service.dispose();
    }
    access.dispose();
    selection.dispose();
    auth.dispose();
    lifecycle.dispose();
    unawaited(identity.close());
  }
}

final class _ThrowingRepository implements AlertRepository {
  bool fail = true;
  int calls = 0;

  @override
  bool get isConfigured => true;

  @override
  Future<AlertPage> search(String ranchId, AlertSearch query) {
    calls++;
    if (fail) throw StateError('private SDK detail');
    return Future<AlertPage>.value(
      _page(ranchId, query.page, query.pageSize, 0, const []),
    );
  }

  @override
  Future<AlertAcknowledgementResult> acknowledge(
    String ranchId,
    AlertAcknowledgement request,
  ) => Future<AlertAcknowledgementResult>.error(
    const MonitoringFailure(MonitoringFailureCode.invalidResponse),
  );
}
