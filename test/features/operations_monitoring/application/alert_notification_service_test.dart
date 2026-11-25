import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/iam/application/facades/authorized_ranch_session.dart';
import 'package:ichu_mobile_app/features/iam/application/services/auth_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/authentication_lifecycle.dart';
import 'package:ichu_mobile_app/features/iam/application/services/ranch_selection_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_access.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/application/services/alert_notification_service.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/alert_search.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/monitoring_failure.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/ranch_alert.dart';

import '../../../support/fake_alert_notifier.dart';
import '../../../support/fake_alert_repository.dart';
import '../../../support/fake_iam_repositories.dart';
import '../../../support/memory_notified_alert_repository.dart';

const String _ranchA = 'a1111111-1111-4111-8111-111111111111';
const String _ranchB = 'b2222222-2222-4222-8222-222222222222';
const String _accountId = 'e5555555-5555-4555-8555-555555555555';
const String _first = '10000000-0000-4000-8000-000000000001';
const String _second = '10000000-0000-4000-8000-000000000002';
const String _third = '10000000-0000-4000-8000-000000000003';
const _pollInterval = Duration(seconds: 30);
const _pendingSearch = AlertSearch(status: AlertStatus.pending, pageSize: 20);
const _account = IamAccount(
  id: _accountId,
  email: 'user@example.test',
  role: AccountRole.ranchManager,
  status: 'Active',
);

void main() {
  testWidgets(
    'records existing pending alerts on the first poll without announcing them',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.alerts.pageResult = _page(_ranchA, [_first]);
      harness.createService();

      await harness.initializeAndSelect(_ranchA);
      await tester.pump();

      expect(harness.notifier.initialized, isTrue);
      expect(harness.alerts.requests.single.query, _pendingSearch);
      expect(harness.notifier.shown, isEmpty);
      expect(await harness.notified.read(_ranchA), [_first]);
    },
  );

  testWidgets('announces each new pending alert once', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.alerts.pageResult = _page(_ranchA, [_first]);
    harness.createService();
    await harness.initializeAndSelect(_ranchA);
    await tester.pump();
    harness.alerts.pageResult = _page(_ranchA, [_first, _second]);

    await tester.pump(_pollInterval);
    await tester.pump(_pollInterval);

    expect(_shownIds(harness), [_second]);
    expect(await harness.notified.read(_ranchA), [_first, _second]);
  });

  testWidgets('does not announce remembered alerts again after a restart', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.alerts.pageResult = _page(_ranchA, [_first]);
    final before = harness.createService();
    await harness.initializeAndSelect(_ranchA);
    await tester.pump();
    harness.alerts.pageResult = _page(_ranchA, [_first, _second]);
    await tester.pump(_pollInterval);
    before.dispose();

    harness.createService();
    await tester.pump();
    await tester.pump(_pollInterval);

    expect(_shownIds(harness), [_second]);
  });

  testWidgets('keeps only the most recent 200 announced IDs per ranch', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.notified.write(_ranchA, [
      for (var index = 0; index < 200; index++) 'older-$index',
    ]);
    harness.alerts.pageResult = _page(_ranchA, [_first]);
    harness.createService();

    await harness.initializeAndSelect(_ranchA);
    await tester.pump();

    final remembered = await harness.notified.read(_ranchA);
    expect(remembered, hasLength(200));
    expect(remembered.first, 'older-1');
    expect(remembered.last, _first);
  });

  testWidgets(
    'retries the pending alerts on the next tick after a failed poll',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.alerts.pageResult = _page(_ranchA, [_first]);
      harness.createService();
      await harness.initializeAndSelect(_ranchA);
      await tester.pump();
      harness.alerts
        ..failure = const MonitoringFailure(MonitoringFailureCode.network)
        ..pageResult = _page(_ranchA, [_first, _second]);

      await tester.pump(_pollInterval);
      expect(harness.notifier.shown, isEmpty);
      harness.alerts.failure = null;
      await tester.pump(_pollInterval);

      expect(_shownIds(harness), [_second]);
    },
  );

  testWidgets('leaves an alert unrecorded when showing it fails', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.alerts.pageResult = _page(_ranchA, [_first]);
    harness.createService();
    await harness.initializeAndSelect(_ranchA);
    await tester.pump();
    harness.notifier.showFailure = StateError('synthetic notification failure');
    harness.alerts.pageResult = _page(_ranchA, [_first, _second]);

    await tester.pump(_pollInterval);
    expect(harness.notifier.shown, isEmpty);
    expect(await harness.notified.read(_ranchA), [_first]);
    harness.notifier.showFailure = null;
    await tester.pump(_pollInterval);

    expect(_shownIds(harness), [_second]);
    expect(await harness.notified.read(_ranchA), [_first, _second]);
  });

  testWidgets('polls only while the app is in the foreground', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.alerts.pageResult = _page(_ranchA, [_first]);
    final service = harness.createService();
    await harness.initializeAndSelect(_ranchA);
    await tester.pump();
    service.setActive(false);
    harness.alerts.pageResult = _page(_ranchA, [_first, _second]);

    await tester.pump(_pollInterval * 2);
    expect(harness.alerts.calls, 1);
    service.setActive(true);
    await tester.pump();

    expect(_shownIds(harness), [_second]);
  });

  testWidgets(
    'stops on sign-out and treats the next login as a new first poll',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.alerts.pageResult = _page(_ranchA, [_first]);
      harness.createService();
      await harness.initializeAndSelect(_ranchA);
      await tester.pump();

      await harness.auth.signOut();
      await tester.pump(_pollInterval * 2);
      expect(harness.alerts.calls, 1);

      harness.alerts.pageResult = _page(_ranchA, [_first, _second]);
      await harness.auth.signIn('user@example.test', 'synthetic-password');
      expect(harness.selection.select(_ranchA), isTrue);
      await tester.pump();

      expect(harness.alerts.calls, 2);
      expect(harness.notifier.shown, isEmpty);
    },
  );

  testWidgets('ignores a response that arrives after the ranch changed', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.alerts.pageResult = _page(_ranchA, [_first]);
    harness.createService();
    await harness.initializeAndSelect(_ranchA);
    await tester.pump();
    final staleResponse = Completer<AlertPage>();
    harness.alerts.completer = staleResponse;
    await tester.pump(_pollInterval);
    expect(harness.alerts.calls, 2);

    expect(harness.selection.select(_ranchB), isTrue);
    staleResponse.complete(_page(_ranchA, [_first, _second]));
    await tester.pump();
    expect(harness.notifier.shown, isEmpty);

    harness.alerts
      ..completer = null
      ..pageResult = _page(_ranchB, [_third]);
    await tester.pump(_pollInterval);

    expect(harness.notifier.shown, isEmpty);
    expect(await harness.notified.read(_ranchB), [_third]);
    expect(await harness.notified.read(_ranchA), [_first]);
  });

  testWidgets('does not poll without a configured alert repository', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.alerts.configured = false;
    harness.createService();

    await harness.initializeAndSelect(_ranchA);
    await tester.pump(_pollInterval * 2);

    expect(harness.alerts.calls, 0);
    expect(harness.notifier.initialized, isFalse);
  });
}

List<String> _shownIds(_Harness harness) =>
    harness.notifier.shown.map((alert) => alert.alertId).toList();

AlertPage _page(String ranchId, List<String> alertIds) {
  final items = [
    for (final id in alertIds)
      syntheticRanchAlert(ranchId: ranchId, alertId: id),
  ];
  return AlertPage(
    page: 1,
    pageSize: 20,
    totalCount: items.length,
    items: items,
  );
}

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
        account: _account,
        ranches: [_ranch(_ranchA), _ranch(_ranchB)],
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
  final alerts = FakeAlertRepository();
  final notifier = FakeAlertNotifier();
  final notified = MemoryNotifiedAlertRepository();
  final services = <AlertNotificationService>[];

  AlertNotificationService createService() {
    final created = AlertNotificationService(
      access: access,
      alerts: alerts,
      notifier: notifier,
      notified: notified,
    );
    services.add(created);
    return created;
  }

  Future<void> initializeAndSelect(String ranchId) async {
    await auth.initialize();
    expect(selection.select(ranchId), isTrue);
  }

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
