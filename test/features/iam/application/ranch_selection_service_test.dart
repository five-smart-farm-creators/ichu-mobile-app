import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/iam/application/services/auth_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/authentication_lifecycle.dart';
import 'package:ichu_mobile_app/features/iam/application/services/ranch_selection_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_user.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_access.dart';

import '../../../support/fake_iam_repositories.dart';

void main() {
  test(
    'initial validation notifies selection listeners even for an empty list',
    () async {
      final harness = _Harness();
      var notifications = 0;
      harness.selection.addListener(() => notifications++);
      expect(harness.selection.canSelect, isFalse);
      await harness.initialize();
      expect(harness.selection.canSelect, isTrue);
      expect(harness.selection.ranches, isEmpty);
      expect(notifications, greaterThan(0));
      harness.dispose();
    },
  );

  test(
    'irrelevant same-session notifications preserve the explicit choice',
    () async {
      final ranch = _ranch('same-snapshot');
      final harness = _Harness(ranches: [ranch]);
      await harness.initialize();
      expect(harness.selection.select(ranch.ranchId), isTrue);
      await harness.auth.sendPasswordReset('user@example.test');
      expect(harness.selection.selectedRanch, same(ranch));
      expect(harness.accounts.currentAccountCalls, 1);
      harness.dispose();
    },
  );

  test(
    'reentrant refresh during selection notification cannot restore a choice',
    () async {
      final ranch = _ranch('refresh-during-notification');
      final harness = _Harness(ranches: [ranch]);
      await harness.initialize();
      Future<void>? refresh;
      var requested = false;
      harness.selection.addListener(() {
        if (!requested && harness.selection.selectedRanch != null) {
          requested = true;
          refresh = harness.selection.refresh();
        }
      });
      harness.selection.select(ranch.ranchId);
      expect(harness.selection.selectedRanch, isNull);
      await refresh;
      expect(harness.selection.selectedRanch, isNull);
      expect(harness.accounts.currentAccountCalls, 2);
      harness.dispose();
    },
  );

  test('zero, one, and multiple grants never auto-select', () async {
    for (final grants in <List<RanchAccess>>[
      const <RanchAccess>[],
      <RanchAccess>[_ranch('only')],
      <RanchAccess>[_ranch('one'), _ranch('two')],
    ]) {
      final harness = _Harness(ranches: grants);
      await harness.initialize();

      expect(harness.selection.selectedRanch, isNull);
      expect(harness.selection.canSelect, isTrue);
      expect(harness.selection.ranches, grants);
      harness.dispose();
    }
  });

  test(
    'selection fails closed and retains the canonical server grant',
    () async {
      final now = DateTime.utc(2026, 1, 1);
      final canonical = _ranch('available', scope: AccessScope.manage);
      final grants = <RanchAccess>[
        canonical,
        _ranch('expired', expiresAt: now),
        _ranch('duplicate'),
        _ranch('duplicate'),
      ];
      final harness = _Harness(ranches: grants, now: () => now);
      await harness.initialize();

      expect(harness.selection.ranches, <RanchAccess>[canonical]);
      expect(harness.selection.select(''), isFalse);
      expect(harness.selection.select('unknown'), isFalse);
      expect(harness.selection.select('expired'), isFalse);
      expect(harness.selection.select('duplicate'), isFalse);
      expect(harness.selection.select('available'), isTrue);
      expect(identical(harness.selection.selectedRanch, canonical), isTrue);
      expect(
        () => harness.selection.ranches.add(_ranch('mutated')),
        throwsUnsupportedError,
      );
      harness.dispose();
    },
  );

  test('preserves backend-provided scopes for every account role', () async {
    final grants = <RanchAccess>[
      _ranch('read', scope: AccessScope.read),
      _ranch('clinical', scope: AccessScope.clinicalWrite),
      _ranch('manage', scope: AccessScope.manage),
    ];
    for (final role in AccountRole.values) {
      final harness = _Harness(ranches: grants, role: role);
      await harness.initialize();

      expect(harness.selection.ranches, grants);
      for (final grant in grants) {
        expect(harness.selection.select(grant.ranchId), isTrue);
        expect(harness.selection.selectedRanch?.scope, grant.scope);
      }
      harness.dispose();
    }
  });

  test('same-scope refresh clears selection and never restores it', () async {
    final first = _ranch('same-id', scope: AccessScope.read);
    final harness = _Harness(ranches: <RanchAccess>[first]);
    await harness.initialize();
    expect(harness.selection.select('same-id'), isTrue);
    final replacement = _ranch('same-id', scope: AccessScope.manage);
    harness.accounts.ranches = <RanchAccess>[replacement];

    await harness.selection.refresh();
    expect(harness.selection.selectedRanch, isNull);
    expect(harness.selection.ranches.single, same(replacement));
    expect(harness.selection.select('same-id'), isTrue);
    expect(harness.selection.selectedRanch, same(replacement));
    expect(harness.selection.selectedRanch?.scope, AccessScope.manage);
    expect(harness.identity.reloadUserCalls, 2);
    harness.dispose();
  });

  test('account and role changes invalidate the prior selection', () async {
    final ranch = _ranch('ranch');
    final harness = _Harness(ranches: <RanchAccess>[ranch]);
    await harness.initialize();
    expect(harness.selection.select('ranch'), isTrue);

    harness.accounts.account = _account(
      role: AccountRole.fieldOperator,
      id: 'changed-account',
    );
    await harness.selection.refresh();
    expect(harness.selection.selectedRanch, isNull);

    expect(harness.selection.select('ranch'), isTrue);
    harness.accounts.account = _account(role: AccountRole.ranchManager);
    await harness.selection.refresh();
    expect(harness.selection.selectedRanch, isNull);
    harness.dispose();
  });

  test(
    'failed refresh clears selection and invalid session cannot refresh',
    () async {
      final harness = _Harness(ranches: <RanchAccess>[_ranch('ranch')]);
      await harness.initialize();
      expect(harness.selection.select('ranch'), isTrue);

      harness.accounts.ranchAccessFailure = StateError('private failure');
      await harness.selection.refresh();
      expect(harness.selection.selectedRanch, isNull);
      expect(harness.auth.status, SessionStatus.unavailable);
      final reloadCalls = harness.identity.reloadUserCalls;
      await harness.selection.refresh();
      expect(harness.identity.reloadUserCalls, reloadCalls);
      harness.dispose();
    },
  );

  test(
    'late refresh for UID A cannot restore selection after switching to B',
    () async {
      const userB = AuthUser(
        uid: 'uid-b',
        email: 'b@example.test',
        emailVerified: true,
      );
      final harness = _Harness(ranches: <RanchAccess>[_ranch('a-ranch')]);
      await harness.initialize();
      expect(harness.selection.select('a-ranch'), isTrue);

      final staleAccount = Completer<IamAccount>();
      harness.accounts.currentAccountCompleter = staleAccount;
      final refresh = harness.selection.refresh();
      await harness.accounts.secondCurrentAccountCall.future;
      harness.accounts
        ..currentAccountCompleter = null
        ..account = _account(id: 'account-b', email: userB.email)
        ..ranches = <RanchAccess>[_ranch('b-ranch')];
      final switched = Completer<void>();
      harness.auth.addListener(() {
        if (harness.auth.user?.uid == userB.uid && !switched.isCompleted) {
          switched.complete();
        }
      });
      harness.identity.emit(userB);
      await switched.future;

      expect(harness.selection.selectedRanch, isNull);
      expect(harness.selection.ranches.single.ranchId, 'b-ranch');
      staleAccount.complete(_account());
      await refresh;
      expect(harness.auth.user?.uid, userB.uid);
      expect(harness.selection.selectedRanch, isNull);
      expect(harness.selection.ranches.single.ranchId, 'b-ranch');
      harness.dispose();
    },
  );

  test('logout immediately removes ranches and selection', () async {
    final harness = _Harness(ranches: <RanchAccess>[_ranch('ranch')]);
    await harness.initialize();
    expect(harness.selection.select('ranch'), isTrue);

    expect(await harness.auth.signOut(), isTrue);
    expect(harness.selection.selectedRanch, isNull);
    expect(harness.selection.ranches, isEmpty);
    expect(harness.selection.canSelect, isFalse);
    harness.dispose();
  });

  testWidgets('expiry at the exact boundary clears selection and notifies', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 1, 1);
    final expiring = _ranch(
      'expiring',
      expiresAt: now.add(const Duration(seconds: 5)),
    );
    final harness = _Harness(ranches: <RanchAccess>[expiring], now: () => now);
    await harness.initialize();
    expect(harness.selection.select('expiring'), isTrue);
    var notifications = 0;
    harness.selection.addListener(() => notifications++);

    now = now.add(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));

    expect(harness.selection.ranches, isEmpty);
    expect(harness.selection.selectedRanch, isNull);
    expect(harness.selection.canSelect, isTrue);
    expect(notifications, greaterThan(0));
    harness.dispose();
  });

  testWidgets('dispose cancels expiry timers and ignores later auth changes', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 1, 1);
    final harness = _Harness(
      ranches: <RanchAccess>[
        _ranch('later', expiresAt: now.add(const Duration(seconds: 10))),
      ],
      now: () => now,
    );
    await harness.initialize();
    expect(harness.selection.select('later'), isTrue);
    var notifications = 0;
    harness.selection.addListener(() => notifications++);
    harness.selection.dispose();
    now = now.add(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));
    harness.identity.emit(null);
    expect(notifications, 0);
    harness.dispose();
  });
}

RanchAccess _ranch(
  String id, {
  AccessScope scope = AccessScope.read,
  DateTime? expiresAt,
}) => RanchAccess(
  ranchId: id,
  scope: scope,
  name: 'Ranch $id',
  region: 'Region',
  district: 'District',
  expiresAt: expiresAt,
);

IamAccount _account({
  AccountRole role = AccountRole.ranchManager,
  String id = '11111111-1111-4111-8111-111111111111',
  String email = 'user@example.test',
}) =>
    IamAccount(id: id, email: email, role: role, status: 'TemporarilyBlocked');

final class _Harness {
  _Harness({
    List<RanchAccess> ranches = const <RanchAccess>[],
    AccountRole role = AccountRole.ranchManager,
    DateTime Function()? now,
  }) : identity = FakeAuthenticationRepository() {
    accounts = FakeAccountRepository(
      account: _account(role: role),
      ranches: ranches,
    );
    lifecycle = AuthenticationLifecycle(identity);
    auth = AuthService(authentication: lifecycle, accounts: accounts);
    selection = RanchSelectionService(session: auth, now: now);
  }

  final FakeAuthenticationRepository identity;
  late final FakeAccountRepository accounts;
  late final AuthenticationLifecycle lifecycle;
  late final AuthService auth;
  late final RanchSelectionService selection;

  Future<void> initialize() => auth.initialize();

  void dispose() {
    selection.dispose();
    auth.dispose();
    lifecycle.dispose();
    unawaited(identity.close());
  }
}
