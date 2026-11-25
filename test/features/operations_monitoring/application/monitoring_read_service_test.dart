import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/iam/application/facades/authorized_ranch_session.dart';
import 'package:ichu_mobile_app/features/iam/application/services/auth_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/authentication_lifecycle.dart';
import 'package:ichu_mobile_app/features/iam/application/services/ranch_selection_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_access.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_user.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/application/services/monitoring_read_service.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/latest_telemetry.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/monitoring_failure.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/telemetry_history.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/telemetry_history_query.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/repositories/monitoring_repository.dart';

import '../../../support/fake_iam_repositories.dart';
import '../../../support/fake_monitoring_repository.dart';

void main() {
  late _Harness harness;
  late FakeMonitoringRepository repository;
  late MonitoringReadService service;
  setUp(() async {
    harness = _Harness();
    repository = FakeMonitoringRepository();
    service = harness.createService(repository);
    await harness.initializeAndSelect(_ranchA);
  });
  tearDown(() {
    service.dispose();
    harness.dispose();
  });

  test(
    'does not load until explicitly asked and accepts an all-unavailable snapshot',
    () async {
      expect(repository.requests, isEmpty);
      repository.latestResult = syntheticLatestTelemetry(cattleId: _cattleA);
      expect(await service.load(_cattleA), isTrue);
      expect(service.status, MonitoringLoadStatus.ready);
      expect(service.snapshot!.bodyTemperature.value, isNull);
      expect(service.snapshot!.lastKnownPosition.isAvailable, isFalse);
      expect(repository.requests.single.ranchId, _ranchA);
    },
  );

  test(
    'returns the exact pending future for a repeated same-context request',
    () async {
      final completer = Completer<LatestTelemetry>();
      repository.completer = completer;
      final first = service.load(_cattleA);
      final second = service.load(_cattleA.toUpperCase());
      expect(identical(first, second), isTrue);
      await Future<void>.value();
      expect(repository.requests, hasLength(1));
      completer.complete(syntheticLatestTelemetry(cattleId: _cattleA));
      expect(await first, isTrue);
    },
  );

  test(
    'discards an older cattle response when a newer request supersedes it',
    () async {
      final older = Completer<LatestTelemetry>();
      final newer = Completer<LatestTelemetry>();
      repository.completer = older;
      final oldRead = service.load(_cattleA);
      await Future<void>.value();
      repository.completer = newer;
      final newRead = service.load(_cattleB);
      await Future<void>.value();
      newer.complete(syntheticLatestTelemetry(cattleId: _cattleB));
      expect(await newRead, isTrue);
      older.complete(syntheticLatestTelemetry(cattleId: _cattleA));
      expect(await oldRead, isFalse);
      expect(service.cattleId, _cattleB);
      expect(service.snapshot!.cattleId, _cattleB);
    },
  );

  test(
    'rejects invalid IDs locally and clears previously visible data',
    () async {
      repository.latestResult = syntheticLatestTelemetry(cattleId: _cattleA);
      expect(await service.load(_cattleA), isTrue);
      final requestCount = repository.requests.length;
      expect(await service.load('../bad'), isFalse);
      expect(repository.requests, hasLength(requestCount));
      expect(service.snapshot, isNull);
      expect(service.error!.code, MonitoringFailureCode.notFound);
    },
  );

  test('rejects zero UUID and malformed IDs without remote requests', () async {
    for (final id in [
      '',
      'not-a-uuid',
      ' $_cattleA ',
      '../cattle',
      '00000000-0000-0000-0000-000000000000',
    ]) {
      expect(await service.load(id), isFalse, reason: id);
    }
    expect(repository.calls, 0);
    expect(service.error!.code, MonitoringFailureCode.notFound);
  });

  test(
    'rejects a validly-shaped response for another cattle identity',
    () async {
      repository.latestResult = syntheticLatestTelemetry(cattleId: _cattleB);
      expect(await service.load(_cattleA), isFalse);
      expect(service.status, MonitoringLoadStatus.unavailable);
      expect(service.error!.code, MonitoringFailureCode.invalidResponse);
      expect(service.snapshot, isNull);
    },
  );

  test(
    'a context switch immediately hides data and does not auto-read',
    () async {
      repository.latestResult = syntheticLatestTelemetry(cattleId: _cattleA);
      await service.load(_cattleA);
      final beforeRevision = service.revision;
      await harness.select(_ranchB);
      expect(service.snapshot, isNull);
      expect(service.status, MonitoringLoadStatus.idle);
      expect(service.revision, beforeRevision + 1);
      expect(repository.requests, hasLength(1));
    },
  );

  test(
    'configuration and repository failures require explicit retry',
    () async {
      repository.configured = false;
      expect(await service.load(_cattleA), isFalse);
      expect(service.error!.code, MonitoringFailureCode.configuration);
      expect(repository.requests, isEmpty);
      repository.configured = true;
      repository.latestResult = syntheticLatestTelemetry(cattleId: _cattleA);
      expect(await service.load(_cattleA), isTrue);
      expect(repository.requests, hasLength(1));
    },
  );

  test(
    'preserves independent measurements, server evaluation, and stale flags verbatim',
    () async {
      final temperatureTime = DateTime.utc(2027, 4, 5, 10);
      final positionTime = DateTime.utc(2027, 4, 4, 9);
      final expected = syntheticLatestTelemetry(
        cattleId: _cattleA,
        evaluatedAt: DateTime.utc(2027, 4, 5, 11),
        bodyTemperature: LatestIndicator.available(
          value: 38.25,
          unit: TelemetryUnit.celsius,
          recordedAt: temperatureTime,
          isStale: true,
        ),
        lastKnownPosition: LastKnownPosition.available(
          latitude: -12.1,
          longitude: -76.2,
          accuracyMeters: 4.5,
          recordedAt: positionTime,
          isStale: false,
        ),
      );
      repository.latestResult = expected;
      expect(await service.load(_cattleA), isTrue);
      expect(identical(service.snapshot, expected), isTrue);
      expect(service.snapshot!.activityIndex.isAvailable, isFalse);
      expect(service.snapshot!.bodyTemperature.isStale, isTrue);
      expect(service.snapshot!.lastKnownPosition.isStale, isFalse);
      expect(service.snapshot!.evaluatedAt, expected.evaluatedAt);
    },
  );

  test(
    'a loading listener can reenter without starting another request',
    () async {
      final completer = Completer<LatestTelemetry>();
      repository.completer = completer;
      Future<bool>? reentrant;
      void listener() {
        if (service.status == MonitoringLoadStatus.loading) {
          reentrant ??= service.load(_cattleA);
        }
      }

      service.addListener(listener);
      final initial = service.load(_cattleA);
      expect(identical(initial, reentrant), isTrue);
      await Future<void>.value();
      expect(repository.calls, 1);
      completer.complete(syntheticLatestTelemetry(cattleId: _cattleA));
      expect(await initial, isTrue);
      service.removeListener(listener);
    },
  );

  test(
    'late permission failure from a superseded request cannot clear newer success',
    () async {
      final oldCompleter = Completer<LatestTelemetry>();
      final newCompleter = Completer<LatestTelemetry>();
      repository.completer = oldCompleter;
      final oldRead = service.load(_cattleA);
      await Future<void>.value();
      repository.completer = newCompleter;
      final newRead = service.load(_cattleB);
      await Future<void>.value();
      newCompleter.complete(syntheticLatestTelemetry(cattleId: _cattleB));
      expect(await newRead, isTrue);
      oldCompleter.completeError(
        const MonitoringFailure(MonitoringFailureCode.forbidden),
      );
      expect(await oldRead, isFalse);
      expect(service.snapshot!.cattleId, _cattleB);
      expect(service.error, isNull);
    },
  );

  test(
    'A to B to A ranch changes discard an earlier response for the first A context',
    () async {
      final firstA = Completer<LatestTelemetry>();
      repository.completer = firstA;
      final pending = service.load(_cattleA);
      await Future<void>.value();
      await harness.select(_ranchB);
      await harness.select(_ranchA);
      firstA.complete(syntheticLatestTelemetry(cattleId: _cattleA));
      expect(await pending, isFalse);
      expect(service.snapshot, isNull);
      expect(repository.calls, 1);
    },
  );

  test(
    'clear fences a started pending request and late completion does not notify',
    () async {
      final completer = Completer<LatestTelemetry>();
      repository.completer = completer;
      var notifications = 0;
      service.addListener(() => notifications++);
      final pending = service.load(_cattleA);
      await Future<void>.value();
      service.clear();
      final afterClear = notifications;
      completer.complete(syntheticLatestTelemetry(cattleId: _cattleA));
      expect(await pending, isFalse);
      expect(notifications, afterClear);
      expect(service.snapshot, isNull);
    },
  );

  test(
    'changing selection before scheduled read starts prevents repository access',
    () async {
      final pending = service.load(_cattleA);
      await harness.select(_ranchB);
      expect(await pending, isFalse);
      expect(repository.calls, 0);
    },
  );

  test(
    'missing selection and unconfigured repository never issue a read',
    () async {
      harness.selection.clearSelection();
      expect(await service.load(_cattleA), isFalse);
      expect(repository.calls, 0);
      await harness.select(_ranchA);
      repository.configured = false;
      expect(service.canLoad, isFalse);
      expect(await service.load(_cattleA), isFalse);
      expect(repository.calls, 0);
      expect(service.error!.code, MonitoringFailureCode.configuration);
    },
  );

  test(
    'disposal fences an already-started request without late notification',
    () async {
      final completer = Completer<LatestTelemetry>();
      repository.completer = completer;
      var notifications = 0;
      service.addListener(() => notifications++);
      final pending = service.load(_cattleA);
      await Future<void>.value();
      final beforeDispose = notifications;
      service.dispose();
      completer.complete(syntheticLatestTelemetry(cattleId: _cattleA));
      expect(await pending, isFalse);
      expect(notifications, beforeDispose);
      expect(service.snapshot, isNull);
    },
  );

  test('logout invalidates a pending result', () async {
    final completer = Completer<LatestTelemetry>();
    repository.completer = completer;
    final pending = service.load(_cattleA);
    await harness.auth.signOut();
    completer.complete(syntheticLatestTelemetry(cattleId: _cattleA));
    expect(await pending, isFalse);
    expect(service.snapshot, isNull);
  });

  for (final code in [
    MonitoringFailureCode.network,
    MonitoringFailureCode.unauthenticated,
    MonitoringFailureCode.forbidden,
  ]) {
    test(
      '${code.name} clears a loaded snapshot and recovers only on explicit retry',
      () async {
        repository.latestResult = syntheticLatestTelemetry(cattleId: _cattleA);
        expect(await service.load(_cattleA), isTrue);
        repository.failure = MonitoringFailure(code);
        expect(await service.load(_cattleA), isFalse);
        expect(service.snapshot, isNull);
        expect(service.status, MonitoringLoadStatus.unavailable);
        expect(service.error!.code, code);
        expect(repository.calls, 2);
        repository.failure = null;
        await Future<void>.value();
        expect(repository.calls, 2);
        expect(service.snapshot, isNull);
        expect(await service.load(_cattleA), isTrue);
        expect(repository.calls, 3);
      },
    );
  }

  test(
    'synchronous repository throws do not latch the completed pending future',
    () async {
      final throwing = _SynchronousFailureRepository();
      final other = harness.createService(throwing);
      expect(await other.load(_cattleA), isFalse);
      expect(other.error!.code, MonitoringFailureCode.unknown);
      expect(other.error.toString(), isNot(contains('private SDK detail')));
      throwing.fail = false;
      expect(await other.load(_cattleA), isTrue);
      expect(throwing.calls, 2);
    },
  );

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
      'revalidation to ${account.id}/${account.role.name} rejects the prior summary',
      () async {
        final pendingResult = Completer<LatestTelemetry>();
        repository.completer = pendingResult;
        final oldContext = harness.access.context;
        final read = service.load(_cattleA);
        await Future<void>.value();
        expect(repository.calls, 1);
        final accountResult = Completer<IamAccount>();
        harness.accounts.currentAccountCompleter = accountResult;
        final refresh = harness.auth.refresh();
        await harness.accounts.secondCurrentAccountCall.future;
        expect(harness.access.context, isNull);
        expect(service.snapshot, isNull);
        accountResult.complete(account);
        await refresh;
        await harness.select(_ranchA);
        expect(harness.access.context, isNot(same(oldContext)));
        pendingResult.complete(syntheticLatestTelemetry(cattleId: _cattleA));
        expect(await read, isFalse);
        expect(service.snapshot, isNull);
        repository.completer = null;
        repository.latestResult = syntheticLatestTelemetry(cattleId: _cattleA);
        expect(await service.load(_cattleA), isTrue);
        expect(repository.calls, 2);
      },
    );
  }

  test(
    'same UID login after logout cannot revive an earlier pending summary',
    () async {
      final result = Completer<LatestTelemetry>();
      repository.completer = result;
      final read = service.load(_cattleA);
      await Future<void>.value();
      expect(repository.calls, 1);
      expect(await harness.auth.signOut(), isTrue);
      expect(
        await harness.auth.signIn('user@example.test', 'synthetic-password'),
        isTrue,
      );
      await harness.select(_ranchA);
      result.complete(syntheticLatestTelemetry(cattleId: _cattleA));
      expect(await read, isFalse);
      expect(service.snapshot, isNull);
      repository.completer = null;
      repository.latestResult = syntheticLatestTelemetry(cattleId: _cattleA);
      expect(await service.load(_cattleA), isTrue);
      expect(repository.calls, 2);
    },
  );

  for (final identity in [
    const AuthUser(
      uid: 'other-uid',
      email: 'user@example.test',
      emailVerified: true,
    ),
    const AuthUser(
      uid: 'synthetic-uid',
      email: 'other@example.test',
      emailVerified: true,
    ),
    const AuthUser(
      uid: 'synthetic-uid',
      email: 'user@example.test',
      emailVerified: false,
    ),
  ]) {
    test(
      'silent SDK drift ${identity.uid}/${identity.email}/${identity.emailVerified} hides data',
      () async {
        repository.latestResult = syntheticLatestTelemetry(cattleId: _cattleA);
        expect(await service.load(_cattleA), isTrue);
        var notifications = 0;
        service.addListener(() => notifications++);
        harness.identity.user = identity;
        expect(service.snapshot, isNull);
        expect(service.cattleId, isNull);
        expect(service.status, MonitoringLoadStatus.idle);
        expect(service.canLoad, isFalse);
        expect(repository.calls, 1);
        expect(notifications, 0);
      },
    );
  }

  test(
    'unrelated session notifications and same ranch selection preserve the snapshot',
    () async {
      repository.latestResult = syntheticLatestTelemetry(cattleId: _cattleA);
      await service.load(_cattleA);
      final snapshot = service.snapshot;
      final revision = service.revision;
      harness.auth.clearError();
      await harness.select(_ranchA);
      expect(service.snapshot, same(snapshot));
      expect(service.revision, revision);
      expect(repository.calls, 1);
    },
  );

  test('loads an explicit history period under the selected ranch', () async {
    final from = DateTime.utc(2026, 10, 1);
    final to = DateTime.utc(2026, 10, 2);
    final query = TelemetryHistoryQuery(from: from, to: to);
    repository.historyResult = syntheticTelemetryHistory(
      cattleId: _cattleA,
      from: from,
      to: to,
      oldestRetainedRecordedAt: DateTime.utc(2026, 9, 1),
    );

    expect(await service.loadHistory(_cattleA, query), isTrue);

    expect(repository.historyRequests, hasLength(1));
    expect(repository.historyRequests.single.ranchId, _ranchA);
    expect(repository.historyRequests.single.cattleId, _cattleA);
    expect(repository.historyRequests.single.query, query);
    expect(service.historyStatus, TelemetryHistoryLoadStatus.ready);
    expect(service.historyPage!.totalCount, 0);
    expect(
      service.historyPage!.oldestRetainedRecordedAt,
      DateTime.utc(2026, 9, 1),
    );
  });

  test(
    'invalid history period is rejected without a repository request',
    () async {
      final instant = DateTime.utc(2026, 10, 1);

      expect(
        await service.loadHistory(
          _cattleA,
          TelemetryHistoryQuery(from: instant, to: instant),
        ),
        isFalse,
      );

      expect(repository.historyCalls, 0);
      expect(service.historyStatus, TelemetryHistoryLoadStatus.unavailable);
      expect(
        service.historyError!.code,
        MonitoringFailureCode.invalidHistoryQuery,
      );
    },
  );

  test('history pagination uses the count and selected query', () async {
    final from = DateTime.utc(2026, 10, 1);
    final to = DateTime.utc(2026, 10, 2);
    final firstQuery = TelemetryHistoryQuery(from: from, to: to, pageSize: 10);
    repository.historyResult = syntheticTelemetryHistory(
      cattleId: _cattleA,
      from: from,
      to: to,
      pageSize: 10,
      totalCount: 11,
    );

    expect(await service.loadHistory(_cattleA, firstQuery), isTrue);
    expect(service.canGoNextHistoryPage, isTrue);

    repository.historyResult = syntheticTelemetryHistory(
      cattleId: _cattleA,
      from: from,
      to: to,
      page: 2,
      pageSize: 10,
      totalCount: 11,
    );
    expect(await service.nextHistoryPage(), isTrue);

    expect(repository.historyRequests.last.query.page, 2);
    expect(service.historyPage!.page, 2);
    expect(service.canGoNextHistoryPage, isFalse);
    expect(service.canGoPreviousHistoryPage, isTrue);
  });

  test('a ranch switch fences pending history and hides its page', () async {
    final from = DateTime.utc(2026, 10, 1);
    final to = DateTime.utc(2026, 10, 2);
    final pending = Completer<TelemetryHistoryPage>();
    repository.historyCompleter = pending;
    final read = service.loadHistory(
      _cattleA,
      TelemetryHistoryQuery(from: from, to: to),
    );
    await Future<void>.value();
    await harness.select(_ranchB);
    pending.complete(
      syntheticTelemetryHistory(cattleId: _cattleA, from: from, to: to),
    );

    expect(await read, isFalse);
    expect(service.historyPage, isNull);
    expect(service.historyStatus, TelemetryHistoryLoadStatus.idle);
  });

  testWidgets(
    'expired grants hide data before the expiry timer notifies consumers',
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
      final data = FakeMonitoringRepository()
        ..latestResult = syntheticLatestTelemetry(cattleId: _cattleA);
      final monitored = expiring.createService(data);
      try {
        await expiring.initializeAndSelect(_ranchA);
        final read = monitored.load(_cattleA);
        await tester.pump();
        expect(await read, isTrue);
        var notifications = 0;
        monitored.addListener(() => notifications++);
        now = expiration;
        expect(monitored.snapshot, isNull);
        expect(monitored.hasContext, isFalse);
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
const String _cattleA = 'c3333333-3333-4333-8333-333333333333';
const String _cattleB = 'd4444444-4444-4444-8444-444444444444';
const _accountId = 'e5555555-5555-4555-8555-555555555555';
const _account = IamAccount(
  id: _accountId,
  email: 'user@example.test',
  role: AccountRole.ranchManager,
  status: 'Active',
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
  final services = <MonitoringReadService>[];

  MonitoringReadService createService(MonitoringRepository repository) {
    final created = MonitoringReadService(
      access: access,
      monitoring: repository,
    );
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
    for (final item in services) {
      item.dispose();
    }
    access.dispose();
    selection.dispose();
    auth.dispose();
    lifecycle.dispose();
    unawaited(identity.close());
  }
}

final class _SynchronousFailureRepository implements MonitoringRepository {
  bool fail = true;
  int calls = 0;
  @override
  bool get isConfigured => true;
  @override
  Future<LatestTelemetry> latest(String ranchId, String cattleId) {
    calls++;
    if (fail) throw StateError('private SDK detail');
    return Future.value(syntheticLatestTelemetry(cattleId: cattleId));
  }

  @override
  Future<TelemetryHistoryPage> history(
    String ranchId,
    String cattleId,
    TelemetryHistoryQuery query,
  ) => throw StateError('private SDK detail');
}
