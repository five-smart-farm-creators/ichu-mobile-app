import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/iam/application/facades/authorized_ranch_session.dart';
import 'package:ichu_mobile_app/features/iam/application/services/auth_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/authentication_lifecycle.dart';
import 'package:ichu_mobile_app/features/iam/application/services/ranch_selection_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_failure.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_user.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_access.dart';
import 'package:ichu_mobile_app/features/iam/domain/repositories/authentication_repository.dart';

import '../../../support/fake_iam_repositories.dart';

void main() {
  group('AuthorizedRanchSession', () {
    late _Harness harness;

    setUp(() => harness = _Harness(ranches: <RanchAccess>[_ranch(_ranchA)]));
    tearDown(() => harness.dispose());

    test(
      'requires a configured, validated selection before token access',
      () async {
        final facade = harness.createFacade();
        expect(facade.context, isNull);
        expect(facade.isConfigured, isTrue);
        expect(harness.identity.idTokenCalls, 0);

        await harness.initialize();
        expect(facade.context, isNull);
        expect(harness.identity.idTokenCalls, 0);
      },
    );

    test(
      'unconfigured IAM remains closed and makes no SDK token call',
      () async {
        harness.identity.isConfigured = false;
        final facade = harness.createFacade();
        await harness.initialize();

        expect(facade.isConfigured, isFalse);
        expect(facade.context, isNull);
        expect(harness.identity.idTokenCalls, 0);
      },
    );

    test(
      'returns public ranch context and fetches a fresh token every time',
      () async {
        final facade = harness.createFacade();
        await harness.initialize();
        expect(harness.selection.select(_ranchA), isTrue);

        final first = facade.context!;
        expect(first.accountId, '33333333-3333-4333-8333-333333333333');
        expect(first.ranchId, _ranchA);
        expect(first.ranchName, 'Ranch $_ranchA');
        expect(facade.isCurrent(first), isTrue);
        expect(await facade.idTokenFor(first), 'synthetic-token');
        expect(await facade.idTokenFor(first), 'synthetic-token');
        expect(harness.identity.idTokenCalls, 2);
      },
    );

    test(
      'same selection and unrelated auth notifications preserve context',
      () async {
        final facade = harness.createFacade();
        await harness.initialize();
        harness.selection.select(_ranchA);
        final original = facade.context!;

        harness.selection.select(_ranchA);
        expect(identical(facade.context, original), isTrue);

        harness.identity.passwordResetFailure = StateError('synthetic failure');
        expect(
          await harness.auth.sendPasswordReset('user@example.test'),
          isFalse,
        );
        harness.auth.clearError();
        expect(identical(facade.context, original), isTrue);
        expect(facade.isCurrent(original), isTrue);
      },
    );

    test('SDK identity drift fails closed before auth notifications', () async {
      final facade = harness.createFacade();
      await harness.initialize();
      harness.selection.select(_ranchA);
      final original = facade.context!;
      final user = harness.identity.user!;

      for (final drifted in <AuthUser>[
        const AuthUser(
          uid: 'different-synthetic-uid',
          email: 'user@example.test',
          emailVerified: true,
        ),
        const AuthUser(
          uid: 'synthetic-uid',
          email: 'different@example.test',
          emailVerified: true,
        ),
        const AuthUser(
          uid: 'synthetic-uid',
          email: 'user@example.test',
          emailVerified: false,
        ),
      ]) {
        harness.identity.user = drifted;
        expect(facade.context, isNull);
        expect(facade.isCurrent(original), isFalse);
        await expectLater(
          facade.idTokenFor(original),
          throwsA(isA<RanchSessionFailure>()),
        );
        expect(harness.identity.idTokenCalls, 0);
      }

      harness.identity.user = user;
      expect(identical(facade.context, original), isTrue);
    });

    test(
      'revalidation invalidates old context and requires reselection',
      () async {
        final facade = harness.createFacade();
        await harness.initialize();
        harness.selection.select(_ranchA);
        final original = facade.context!;

        final refresh = harness.auth.refresh();
        expect(facade.context, isNull);
        await refresh;
        expect(facade.context, isNull);
        expect(facade.isCurrent(original), isFalse);

        harness.selection.select(_ranchA);
        final replacement = facade.context!;
        expect(identical(replacement, original), isFalse);
        expect(facade.isCurrent(original), isFalse);
      },
    );

    test('account identity and role changes invalidate contexts', () async {
      final facade = harness.createFacade();
      await harness.initialize();
      harness.selection.select(_ranchA);
      var previous = facade.context!;

      harness.accounts.account = const IamAccount(
        id: '33333333-3333-4333-8333-333333333333',
        email: 'user@example.test',
        role: AccountRole.veterinarian,
        status: 'active',
      );
      await harness.auth.refresh();
      expect(facade.isCurrent(previous), isFalse);
      harness.selection.select(_ranchA);
      previous = facade.context!;

      harness.accounts.account = const IamAccount(
        id: '44444444-4444-4444-8444-444444444444',
        email: 'user@example.test',
        role: AccountRole.veterinarian,
        status: 'active',
      );
      await harness.auth.refresh();
      expect(facade.isCurrent(previous), isFalse);
      harness.selection.select(_ranchA);
      expect(facade.isCurrent(previous), isFalse);
    });

    test('selection away and back invalidates the original context', () async {
      harness.accounts.ranches = <RanchAccess>[
        _ranch(_ranchA),
        _ranch(_ranchB),
      ];
      final facade = harness.createFacade();
      await harness.initialize();
      harness.selection.select(_ranchA);
      final original = facade.context!;

      harness.selection.select(_ranchB);
      final second = facade.context!;
      expect(facade.isCurrent(original), isFalse);
      expect(facade.isCurrent(second), isTrue);

      harness.selection.select(_ranchA);
      final returned = facade.context!;
      expect(returned.ranchId, original.ranchId);
      expect(identical(returned, original), isFalse);
      expect(facade.isCurrent(original), isFalse);
    });

    test(
      'does not release a token when selection changes during SDK request',
      () async {
        harness.accounts.ranches = <RanchAccess>[
          _ranch(_ranchA),
          _ranch(_ranchB),
        ];
        final facade = harness.createFacade();
        await harness.initialize();
        harness.selection.select(_ranchA);
        final context = facade.context!;
        final pending = Completer<String>();
        harness.authentication.tokenFuture = pending.future;

        final response = facade.idTokenFor(context);
        await Future<void>.delayed(Duration.zero);
        harness.selection.select(_ranchB);
        pending.complete('sensitive-sdk-token');

        await expectLater(
          response,
          throwsA(
            isA<RanchSessionFailure>().having(
              (failure) => failure.code,
              'code',
              RanchSessionFailureCode.unavailable,
            ),
          ),
        );
      },
    );

    test(
      'late A token is rejected after A to B to A selection changes',
      () async {
        harness.accounts.ranches = <RanchAccess>[
          _ranch(_ranchA),
          _ranch(_ranchB),
        ];
        final facade = harness.createFacade();
        await harness.initialize();
        harness.selection.select(_ranchA);
        final oldA = facade.context!;
        final pending = Completer<String>();
        harness.authentication.tokenFuture = pending.future;
        final response = facade.idTokenFor(oldA);
        await Future<void>.delayed(Duration.zero);

        harness.selection.select(_ranchB);
        harness.selection.select(_ranchA);
        pending.complete('late-synthetic-token');
        await expectLater(response, throwsA(isA<RanchSessionFailure>()));
      },
    );

    test(
      'logout and disposal prevent late token release and notification',
      () async {
        final facade = harness.createFacade();
        await harness.initialize();
        harness.selection.select(_ranchA);
        final context = facade.context!;
        final logoutToken = Completer<String>();
        harness.authentication.tokenFuture = logoutToken.future;
        final logoutResponse = facade.idTokenFor(context);
        await Future<void>.delayed(Duration.zero);
        await harness.auth.signOut();
        logoutToken.complete('late-after-logout');
        await expectLater(logoutResponse, throwsA(isA<RanchSessionFailure>()));

        // Use a fresh fixture for the disposal race after logout.
        facade.dispose();
        harness.dispose();
        harness = _Harness(ranches: <RanchAccess>[_ranch(_ranchA)]);
        final disposedFacade = harness.createFacade();
        await harness.initialize();
        harness.selection.select(_ranchA);
        final secondContext = disposedFacade.context!;
        final disposedToken = Completer<String>();
        harness.authentication.tokenFuture = disposedToken.future;
        final notifications = <int>[];
        disposedFacade.addListener(() => notifications.add(1));
        final disposedResponse = disposedFacade.idTokenFor(secondContext);
        await Future<void>.delayed(Duration.zero);
        disposedFacade.dispose();
        disposedToken.complete('late-after-dispose');
        await expectLater(
          disposedResponse,
          throwsA(isA<RanchSessionFailure>()),
        );
        expect(notifications, isEmpty);
        expect(disposedFacade.context, isNull);
      },
    );

    test(
      'SDK configuration loss rejects token requests without SDK calls',
      () async {
        final facade = harness.createFacade();
        await harness.initialize();
        harness.selection.select(_ranchA);
        final context = facade.context!;
        final tokenCalls = harness.identity.idTokenCalls;
        harness.identity.isConfigured = false;

        await expectLater(
          facade.idTokenFor(context),
          throwsA(
            isA<RanchSessionFailure>().having(
              (failure) => failure.code,
              'code',
              RanchSessionFailureCode.configuration,
            ),
          ),
        );
        expect(harness.identity.idTokenCalls, tokenCalls);
      },
    );

    test(
      'maps authentication failure codes without exposing details',
      () async {
        final facade = harness.createFacade();
        await harness.initialize();
        harness.selection.select(_ranchA);
        final context = facade.context!;
        final cases = <AuthFailureCode, RanchSessionFailureCode>{
          AuthFailureCode.configuration: RanchSessionFailureCode.configuration,
          AuthFailureCode.network: RanchSessionFailureCode.network,
          AuthFailureCode.serviceUnavailable:
              RanchSessionFailureCode.serviceUnavailable,
          AuthFailureCode.invalidResponse: RanchSessionFailureCode.unavailable,
        };

        for (final entry in cases.entries) {
          harness.authentication.tokenFailure = AuthFailure(entry.key);
          await expectLater(
            facade.idTokenFor(context),
            throwsA(
              isA<RanchSessionFailure>().having(
                (failure) => failure.code,
                'code',
                entry.value,
              ),
            ),
          );
        }
        harness.authentication.tokenFailure = StateError('raw-synthetic-token');
        try {
          await facade.idTokenFor(context);
          fail('Expected a sanitized failure');
        } on RanchSessionFailure catch (failure) {
          expect(failure.code, RanchSessionFailureCode.serviceUnavailable);
          expect(failure.toString(), isNot(contains('raw-synthetic-token')));
        }
      },
    );

    test('rejects empty and whitespace-bearing SDK tokens', () async {
      final facade = harness.createFacade();
      await harness.initialize();
      harness.selection.select(_ranchA);
      final context = facade.context!;

      for (final token in <String>['', '   ', '\r\n', 'token\r\nvalue']) {
        harness.authentication.tokenFuture = Future<String>.value(token);
        await expectLater(
          facade.idTokenFor(context),
          throwsA(
            isA<RanchSessionFailure>().having(
              (failure) => failure.code,
              'code',
              RanchSessionFailureCode.unavailable,
            ),
          ),
        );
      }
    });

    testWidgets('expires selected grant before expiry timer is pumped', (
      tester,
    ) async {
      var now = DateTime.utc(2026, 1, 1);
      harness.dispose();
      harness = _Harness(
        ranches: <RanchAccess>[
          _ranch(_ranchA, expiresAt: now.add(const Duration(seconds: 5))),
        ],
        now: () => now,
      );
      final facade = harness.createFacade();
      await harness.initialize();
      harness.selection.select(_ranchA);
      final context = facade.context!;
      now = now.add(const Duration(seconds: 5));

      expect(facade.context, isNull);
      expect(facade.isCurrent(context), isFalse);
      expect(harness.identity.idTokenCalls, 0);
      await tester.pump(const Duration(seconds: 5));
      expect(facade.context, isNull);
      harness.dispose();
    });

    test('sanitizes unknown token errors', () async {
      final facade = harness.createFacade();
      await harness.initialize();
      harness.selection.select(_ranchA);
      final context = facade.context!;
      harness.authentication.tokenFailure = StateError('sensitive-sdk-token');

      try {
        await facade.idTokenFor(context);
        fail('Expected token failure');
      } on RanchSessionFailure catch (failure) {
        expect(failure.code, RanchSessionFailureCode.serviceUnavailable);
        expect(failure.toString(), isNot(contains('sensitive-sdk-token')));
      }
    });

    test('canManage is true only for a server-issued manage grant', () async {
      const clinicalRanch = '55555555-5555-4555-8555-555555555555';
      RanchAccess grant(String id, AccessScope scope) => RanchAccess(
        ranchId: id,
        scope: scope,
        name: 'Ranch $id',
        region: 'Synthetic region',
        district: 'Synthetic district',
      );
      harness.accounts.ranches = <RanchAccess>[
        grant(_ranchA, AccessScope.manage),
        grant(_ranchB, AccessScope.read),
        grant(clinicalRanch, AccessScope.clinicalWrite),
      ];
      final facade = harness.createFacade();
      await harness.initialize();

      expect(harness.selection.select(_ranchA), isTrue);
      expect(facade.context!.canManage, isTrue);
      expect(harness.selection.select(_ranchB), isTrue);
      expect(facade.context!.canManage, isFalse);
      expect(harness.selection.select(clinicalRanch), isTrue);
      expect(facade.context!.canManage, isFalse);
    });
  });
}

const String _ranchA = '11111111-1111-4111-8111-111111111111';
const String _ranchB = '22222222-2222-4222-8222-222222222222';

RanchAccess _ranch(String id, {DateTime? expiresAt}) => RanchAccess(
  ranchId: id,
  scope: AccessScope.read,
  name: 'Ranch $id',
  region: 'Synthetic region',
  district: 'Synthetic district',
  expiresAt: expiresAt,
);

final class _Harness {
  _Harness({required List<RanchAccess> ranches, DateTime Function()? now})
    : identity = FakeAuthenticationRepository(),
      accounts = FakeAccountRepository(
        account: const IamAccount(
          id: '33333333-3333-4333-8333-333333333333',
          email: 'user@example.test',
          role: AccountRole.ranchManager,
          status: 'TemporarilyBlocked',
        ),
        ranches: ranches,
      ) {
    lifecycle = AuthenticationLifecycle(identity);
    auth = AuthService(authentication: lifecycle, accounts: accounts);
    selection = RanchSelectionService(session: auth, now: now);
    authentication = _TokenAuthentication(lifecycle);
  }

  final FakeAuthenticationRepository identity;
  final FakeAccountRepository accounts;
  late final AuthenticationLifecycle lifecycle;
  late final AuthService auth;
  late final RanchSelectionService selection;
  late final _TokenAuthentication authentication;
  final List<AuthorizedRanchSession> facades = <AuthorizedRanchSession>[];
  bool _disposed = false;

  Future<void> initialize() => auth.initialize();

  AuthorizedRanchSession createFacade() {
    final facade = AuthorizedRanchSession(
      session: auth,
      selection: selection,
      authentication: authentication,
    );
    facades.add(facade);
    return facade;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final facade in facades) {
      facade.dispose();
    }
    selection.dispose();
    auth.dispose();
    lifecycle.dispose();
    unawaited(identity.close());
  }
}

final class _TokenAuthentication implements AuthenticationRepository {
  _TokenAuthentication(this._delegate);

  final AuthenticationRepository _delegate;
  Future<String>? tokenFuture;
  Object? tokenFailure;

  @override
  bool get isConfigured => _delegate.isConfigured;

  @override
  AuthUser? get currentUser => _delegate.currentUser;

  @override
  Stream<AuthUser?> observeAuthState() => _delegate.observeAuthState();

  @override
  Future<AuthUser> signIn(String email, String password) =>
      _delegate.signIn(email, password);

  @override
  Future<AuthUser?> reloadUser() => _delegate.reloadUser();

  @override
  Future<String> idToken({bool forceRefresh = false}) {
    final failure = tokenFailure;
    if (failure != null) return Future<String>.error(failure);
    final future = tokenFuture;
    if (future != null) return future;
    return _delegate.idToken(forceRefresh: forceRefresh);
  }

  @override
  Future<void> sendPasswordReset(String email) =>
      _delegate.sendPasswordReset(email);

  @override
  Future<void> signOut() => _delegate.signOut();
}
