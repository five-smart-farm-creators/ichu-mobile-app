import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/iam/application/services/auth_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_failure.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_user.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_access.dart';

import '../../../support/fake_iam_repositories.dart';

void main() {
  test(
    'initial auth state is validated sequentially and ranches are immutable',
    () async {
      const ranch = RanchAccess(
        ranchId: 'ranch-1',
        scope: AccessScope.read,
        name: 'North pasture',
      );
      final authentication = FakeAuthenticationRepository();
      final accounts = FakeAccountRepository(
        ranches: const <RanchAccess>[ranch],
      );
      final service = _createService(authentication, accounts);
      _disposeAfterTest(service, authentication);

      final initialization = service.initialize();
      expect(identical(initialization, service.initialize()), isTrue);
      await initialization;

      expect(service.status, SessionStatus.authenticated);
      expect(service.user, syntheticAuthUser);
      expect(service.account, syntheticIamAccount);
      expect(service.ranches, const <RanchAccess>[ranch]);
      expect(authentication.reloadUserCalls, 1);
      expect(accounts.calls, <String>['currentAccount', 'ranchAccess']);
      expect(
        () => service.ranches.add(
          const RanchAccess(ranchId: 'another', scope: AccessScope.read),
        ),
        throwsUnsupportedError,
      );

      authentication.emit(syntheticAuthUser);
      expect(accounts.currentAccountCalls, 1);
    },
  );

  test(
    'sign-in uses a fresh verification result before requesting an account',
    () async {
      final authentication = FakeAuthenticationRepository(user: null)
        ..overrideReloadUserResult = true
        ..reloadUserResult = const AuthUser(
          uid: 'synthetic-uid',
          email: 'user@example.test',
          emailVerified: false,
        );
      final accounts = FakeAccountRepository();
      final service = _createService(authentication, accounts);
      _disposeAfterTest(service, authentication);
      await service.initialize();

      expect(
        await service.signIn('  user@example.test  ', '  exact password  '),
        isFalse,
      );
      expect(authentication.lastSignInEmail, 'user@example.test');
      expect(authentication.lastSignInPassword, '  exact password  ');
      expect(service.status, SessionStatus.unavailable);
      expect(service.error?.code, AuthFailureCode.emailNotVerified);
      expect(accounts.currentAccountCalls, 0);
      expect(authentication.idTokenCalls, 0);
      expect(authentication.signOutCalls, 1);
    },
  );

  test('inactive or mismatched accounts cannot be granted a session', () async {
    const rejectedAccounts = <IamAccount>[
      IamAccount(
        id: 'accountUUID',
        email: 'someone-else@example.test',
        role: AccountRole.ranchManager,
        status: 'active',
      ),
      IamAccount(
        id: 'accountUUID',
        email: 'user@example.test',
        role: AccountRole.ranchManager,
        status: 'pending',
      ),
    ];

    for (final account in rejectedAccounts) {
      final authentication = FakeAuthenticationRepository();
      final accounts = FakeAccountRepository(account: account);
      final service = _createService(authentication, accounts);
      _disposeAfterTest(service, authentication);

      await service.initialize();

      expect(service.status, SessionStatus.unavailable);
      expect(service.error?.code, AuthFailureCode.accountUnavailable);
      expect(accounts.ranchAccessCalls, 0);
      expect(authentication.signOutCalls, 1);
    }
  });

  test(
    'unavailable repositories are not called and recovery needs identity only',
    () async {
      final authentication = FakeAuthenticationRepository(user: null);
      final accounts = FakeAccountRepository(isConfigured: false);
      final service = _createService(authentication, accounts);
      _disposeAfterTest(service, authentication);
      await service.initialize();

      expect(service.canSignIn, isFalse);
      expect(service.canRecover, isTrue);
      expect(await service.signIn('user@example.test', 'password'), isFalse);
      expect(authentication.signInCalls, 0);
      expect(accounts.currentAccountCalls, 0);
      expect(await service.sendPasswordReset('user@example.test'), isTrue);
      expect(authentication.passwordResetCalls, 1);

      authentication.isConfigured = false;
      expect(service.canRecover, isFalse);
      expect(await service.sendPasswordReset('user@example.test'), isFalse);
      expect(authentication.passwordResetCalls, 1);
    },
  );

  test(
    'duplicate sign-in requests do not duplicate an in-flight backend request',
    () async {
      final authentication = FakeAuthenticationRepository(user: null);
      final accounts = FakeAccountRepository()
        ..currentAccountCompleter = Completer<IamAccount>();
      final service = _createService(authentication, accounts);
      _disposeAfterTest(service, authentication);
      await service.initialize();

      final signIn = service.signIn('user@example.test', 'password');
      await accounts.firstCurrentAccountCall.future;
      expect(service.status, SessionStatus.signingIn);
      expect(await service.sendPasswordReset('user@example.test'), isFalse);
      expect(authentication.passwordResetCalls, 0);
      expect(
        await service.signIn('user@example.test', 'another-password'),
        isFalse,
      );
      expect(authentication.signInCalls, 1);

      accounts.currentAccountCompleter!.complete(syntheticIamAccount);
      expect(await signIn, isTrue);
      expect(accounts.calls, <String>['currentAccount', 'ranchAccess']);
    },
  );

  test(
    'a user switch prevents a late account response from replacing the new user',
    () async {
      const firstUser = AuthUser(
        uid: 'first-uid',
        email: 'first@example.test',
        emailVerified: true,
      );
      const secondUser = AuthUser(
        uid: 'second-uid',
        email: 'second@example.test',
        emailVerified: true,
      );
      final authentication = FakeAuthenticationRepository(user: firstUser);
      final staleAccountResponse = Completer<IamAccount>();
      final accounts = FakeAccountRepository()
        ..currentAccountCompleter = staleAccountResponse;
      final service = _createService(authentication, accounts);
      _disposeAfterTest(service, authentication);
      final secondUserAuthenticated = Completer<void>();
      service.addListener(() {
        if (service.user?.uid == secondUser.uid &&
            !secondUserAuthenticated.isCompleted) {
          secondUserAuthenticated.complete();
        }
      });

      final initialization = service.initialize();
      await accounts.firstCurrentAccountCall.future;
      accounts
        ..currentAccountCompleter = null
        ..account = const IamAccount(
          id: 'second-account',
          email: 'second@example.test',
          role: AccountRole.veterinarian,
          status: 'active',
        );
      authentication.emit(secondUser);

      await accounts.secondCurrentAccountCall.future;
      await secondUserAuthenticated.future;
      await initialization;
      expect(service.user, secondUser);

      // Resolve the first request only after the second identity is active.
      // The stale response must be discarded before ranch access is requested.
      staleAccountResponse.complete(
        const IamAccount(
          id: 'first-account',
          email: 'first@example.test',
          role: AccountRole.ranchManager,
          status: 'active',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.user, secondUser);
      expect(service.account?.id, 'second-account');
      expect(accounts.ranchAccessCalls, 1);
      expect(accounts.calls, <String>[
        'currentAccount',
        'currentAccount',
        'ranchAccess',
      ]);
      expect(authentication.signOutCalls, 0);
    },
  );

  test(
    'a late validation failure never signs out the new current identity',
    () async {
      const firstUser = AuthUser(
        uid: 'first-uid',
        email: 'first@example.test',
        emailVerified: true,
      );
      const secondUser = AuthUser(
        uid: 'second-uid',
        email: 'second@example.test',
        emailVerified: true,
      );
      final authentication = FakeAuthenticationRepository(user: firstUser);
      final deferredAccount = Completer<IamAccount>();
      final accounts = FakeAccountRepository(
        account: const IamAccount(
          id: 'second-account',
          email: 'second@example.test',
          role: AccountRole.veterinarian,
          status: 'active',
        ),
      )..currentAccountCompleter = deferredAccount;
      final service = _createService(authentication, accounts);
      _disposeAfterTest(service, authentication);
      final secondUserAuthenticated = Completer<void>();
      service.addListener(() {
        if (service.user?.uid == secondUser.uid &&
            !secondUserAuthenticated.isCompleted) {
          secondUserAuthenticated.complete();
        }
      });

      final initialization = service.initialize();
      await accounts.firstCurrentAccountCall.future;
      authentication.user = secondUser;
      deferredAccount.completeError(StateError('old identity response failed'));
      await initialization;

      expect(authentication.signOutCalls, 0);
      accounts.currentAccountCompleter = null;
      authentication.emit(secondUser);
      await secondUserAuthenticated.future;
      expect(service.status, SessionStatus.authenticated);
      expect(service.user, secondUser);
      expect(authentication.signOutCalls, 0);
    },
  );

  test(
    'late native sign-in after sign-out is cleaned and cannot restore access',
    () async {
      const lateUser = AuthUser(
        uid: 'late-uid',
        email: 'late@example.test',
        emailVerified: true,
      );
      final authentication = FakeAuthenticationRepository(user: null);
      final deferredSignIn = Completer<AuthUser>();
      authentication.deferredSignInResponses.add(deferredSignIn);
      final accounts = FakeAccountRepository();
      final service = _createService(authentication, accounts);
      _disposeAfterTest(service, authentication);
      await service.initialize();

      final signIn = service.signIn('user@example.test', 'password');
      await authentication.signInCallStarted.first.future;
      expect(await service.signOut(), isTrue);
      expect(authentication.signOutCalls, 1);

      deferredSignIn.complete(lateUser);
      expect(await signIn, isFalse);
      expect(authentication.signOutCalls, 2);
      expect(authentication.currentUser, isNull);
      expect(service.status, SessionStatus.signedOut);
      expect(service.account, isNull);

      authentication.emit(lateUser);
      expect(service.status, SessionStatus.signedOut);
      expect(accounts.currentAccountCalls, 0);
    },
  );

  for (final lateUser in [
    const AuthUser(
      uid: 'late-uid',
      email: 'late@example.test',
      emailVerified: true,
    ),
    syntheticAuthUser,
  ]) {
    test(
      'new sign-in waits for late ${lateUser.uid} cleanup and safe restoration',
      () async {
        final authentication = FakeAuthenticationRepository(user: null);
        final staleSignIn = Completer<AuthUser>();
        authentication.deferredSignInResponses.add(staleSignIn);
        final accounts = FakeAccountRepository();
        final service = _createService(authentication, accounts);
        _disposeAfterTest(service, authentication);
        await service.initialize();
        final busyChanges = <bool>[];
        service.addListener(() => busyChanges.add(service.busy));

        final oldRequest = service.signIn('old@example.test', 'old-password');
        await authentication.signInCallStarted.first.future;
        expect(await service.signOut(), isTrue);
        expect(service.busy, isTrue);
        expect(
          await service.signIn('user@example.test', 'new-password'),
          isFalse,
        );
        expect(await service.sendPasswordReset('user@example.test'), isFalse);
        expect(authentication.signInCalls, 1);
        expect(accounts.currentAccountCalls, 0);

        staleSignIn.complete(lateUser);
        expect(await oldRequest, isFalse);
        expect(authentication.signOutCalls, 2);
        expect(authentication.currentUser, isNull);
        expect(service.status, SessionStatus.signedOut);
        expect(service.user, isNull);
        expect(service.busy, isFalse);
        expect(busyChanges.last, isFalse);
        service.dispose();

        // A fresh service has no suppressed-UID memory: native persistence must
        // itself be clear, rather than relying only on an in-memory rejection.
        final restarted = _createService(authentication, accounts);
        addTearDown(restarted.dispose);
        await restarted.initialize();
        expect(restarted.status, SessionStatus.signedOut);
        expect(accounts.currentAccountCalls, 0);
        expect(
          await restarted.signIn('user@example.test', 'new-password'),
          isTrue,
        );
        expect(restarted.user, syntheticAuthUser);
        expect(authentication.currentUser, syntheticAuthUser);
        expect(accounts.currentAccountCalls, 1);
        expect(authentication.signOutCalls, 2);
      },
    );
  }

  test('new sign-in stays blocked throughout late native cleanup', () async {
    final authentication = FakeAuthenticationRepository(user: null);
    final staleSignIn = Completer<AuthUser>();
    authentication.deferredSignInResponses.add(staleSignIn);
    final service = _createService(authentication, FakeAccountRepository());
    _disposeAfterTest(service, authentication);
    await service.initialize();
    final request = service.signIn('user@example.test', 'password');
    expect(await service.signOut(), isTrue);
    final cleanup = Completer<void>();
    authentication.signOutCompleter = cleanup;

    staleSignIn.complete(syntheticAuthUser);
    await Future<void>.delayed(Duration.zero);
    expect(authentication.signOutCalls, 2);
    expect(service.busy, isTrue);
    expect(await service.signIn('user@example.test', 'password'), isFalse);
    cleanup.complete();
    expect(await request, isFalse);
    expect(service.busy, isFalse);
    expect(authentication.currentUser, isNull);
  });

  test(
    'failed late cleanup offers sign-out retry without granting access',
    () async {
      final authentication = FakeAuthenticationRepository(user: null);
      final staleSignIn = Completer<AuthUser>();
      authentication.deferredSignInResponses.add(staleSignIn);
      final accounts = FakeAccountRepository();
      final service = _createService(authentication, accounts);
      _disposeAfterTest(service, authentication);
      await service.initialize();
      final request = service.signIn('user@example.test', 'password');
      expect(await service.signOut(), isTrue);
      authentication.signOutFailure = StateError('private SDK detail');

      staleSignIn.complete(syntheticAuthUser);
      expect(await request, isFalse);
      expect(service.status, SessionStatus.unavailable);
      expect(service.error?.code, AuthFailureCode.signOutFailed);
      expect(service.busy, isFalse);
      expect(accounts.currentAccountCalls, 0);
      authentication.signOutFailure = null;
      expect(await service.signOut(), isTrue);
      expect(authentication.currentUser, isNull);
    },
  );

  test(
    'late SDK sign-in failure releases the gate without restoring a user',
    () async {
      final authentication = FakeAuthenticationRepository(user: null);
      final staleSignIn = Completer<AuthUser>();
      authentication.deferredSignInResponses.add(staleSignIn);
      final service = _createService(authentication, FakeAccountRepository());
      _disposeAfterTest(service, authentication);
      await service.initialize();
      final request = service.signIn('user@example.test', 'password');
      expect(await service.signOut(), isTrue);
      expect(service.busy, isTrue);

      staleSignIn.completeError(StateError('private SDK detail'));
      expect(await request, isFalse);
      expect(service.busy, isFalse);
      expect(service.status, SessionStatus.signedOut);
      expect(authentication.currentUser, isNull);
      expect(await service.signIn('user@example.test', 'password'), isTrue);
    },
  );

  test(
    'sign-out clears a session immediately and wins a pending validation race',
    () async {
      final authentication = FakeAuthenticationRepository();
      final deferredAccount = Completer<IamAccount>();
      final accounts = FakeAccountRepository()
        ..currentAccountCompleter = deferredAccount;
      final service = _createService(authentication, accounts);
      _disposeAfterTest(service, authentication);

      final initialization = service.initialize();
      await accounts.firstCurrentAccountCall.future;
      expect(service.busy, isTrue);

      expect(await service.signOut(), isTrue);
      expect(service.status, SessionStatus.signedOut);
      expect(service.user, isNull);
      await initialization;

      deferredAccount.complete(syntheticIamAccount);
      await Future<void>.delayed(Duration.zero);
      expect(service.status, SessionStatus.signedOut);
      expect(service.account, isNull);
      expect(accounts.ranchAccessCalls, 0);
    },
  );

  test(
    'failed sign-out stays fail-closed and suppresses the old identity',
    () async {
      final authentication = FakeAuthenticationRepository();
      final accounts = FakeAccountRepository();
      final service = _createService(authentication, accounts);
      _disposeAfterTest(service, authentication);
      await service.initialize();
      expect(service.ranches, isEmpty);
      authentication.signOutFailure = StateError('private SDK detail');

      expect(await service.signOut(), isFalse);
      expect(service.status, SessionStatus.unavailable);
      expect(service.error?.code, AuthFailureCode.signOutFailed);
      authentication.emit(syntheticAuthUser);
      expect(service.status, SessionStatus.unavailable);
      expect(accounts.currentAccountCalls, 1);
      authentication.emit(null);
      expect(service.status, SessionStatus.unavailable);
      expect(service.error?.code, AuthFailureCode.signOutFailed);
    },
  );

  test(
    'validation failures expose only stable failures and suppress retries',
    () async {
      final authentication = FakeAuthenticationRepository()
        ..emitSignOutEvents = false;
      final accounts = FakeAccountRepository()
        ..currentAccountFailure = StateError('sensitive token and password');
      final service = _createService(authentication, accounts);
      _disposeAfterTest(service, authentication);

      await service.initialize();

      expect(service.status, SessionStatus.unavailable);
      expect(service.error?.code, AuthFailureCode.serviceUnavailable);
      expect(service.error.toString(), isNot(contains('sensitive')));
      expect(authentication.signOutCalls, 1);
      authentication.emit(null);
      expect(service.status, SessionStatus.unavailable);
      expect(service.error?.code, AuthFailureCode.serviceUnavailable);
      authentication.emit(syntheticAuthUser);
      expect(accounts.currentAccountCalls, 1);
      expect(authentication.signOutCalls, 1);
    },
  );

  test(
    'password reset errors do not reveal whether an account exists',
    () async {
      final authentication = FakeAuthenticationRepository(user: null)
        ..passwordResetFailure = const AuthFailure(
          AuthFailureCode.invalidCredentials,
        );
      final accounts = FakeAccountRepository();
      final service = _createService(authentication, accounts);
      _disposeAfterTest(service, authentication);

      expect(
        await service.sendPasswordReset('  unknown@example.test  '),
        isTrue,
      );
      expect(authentication.lastPasswordResetEmail, 'unknown@example.test');
      expect(service.error, isNull);

      authentication.passwordResetFailure = StateError(
        'unknown@example.test has a private reset detail',
      );
      expect(
        await service.sendPasswordReset('  unknown@example.test  '),
        isFalse,
      );
      expect(service.error?.code, AuthFailureCode.serviceUnavailable);
      expect(service.error.toString(), isNot(contains('unknown@example.test')));
    },
  );

  test('refresh only validates an authenticated session', () async {
    final authentication = FakeAuthenticationRepository(user: null);
    final accounts = FakeAccountRepository();
    final service = _createService(authentication, accounts);
    _disposeAfterTest(service, authentication);
    await service.initialize();
    final authenticated = Completer<void>();
    service.addListener(() {
      if (service.status == SessionStatus.authenticated &&
          !authenticated.isCompleted) {
        authenticated.complete();
      }
    });

    await service.refresh();
    expect(authentication.reloadUserCalls, 0);

    authentication.emit(syntheticAuthUser);
    await accounts.firstCurrentAccountCall.future;
    await authenticated.future;
    await service.refresh();
    expect(service.status, SessionStatus.authenticated);
    expect(authentication.reloadUserCalls, 2);
  });

  test(
    'auth stream completion during validation fails closed and completes initialize',
    () async {
      final authentication = FakeAuthenticationRepository();
      final deferredAccount = Completer<IamAccount>();
      final accounts = FakeAccountRepository()
        ..currentAccountCompleter = deferredAccount;
      final service = _createService(authentication, accounts);
      addTearDown(service.dispose);

      final initialization = service.initialize();
      await accounts.firstCurrentAccountCall.future;
      await authentication.close();
      await initialization;

      expect(service.status, SessionStatus.unavailable);
      expect(service.error?.code, AuthFailureCode.serviceUnavailable);
      deferredAccount.complete(syntheticIamAccount);
      await Future<void>.delayed(Duration.zero);
      expect(service.status, SessionStatus.unavailable);
    },
  );

  test('disposing while observing auth state is safe', () async {
    final authentication = FakeAuthenticationRepository();
    final accounts = FakeAccountRepository();
    final service = _createService(authentication, accounts);
    await service.initialize();
    expect(service.status, SessionStatus.authenticated);
    service.dispose();

    authentication.emit(
      const AuthUser(
        uid: 'later-uid',
        email: 'later@example.test',
        emailVerified: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(service.status, SessionStatus.authenticated);
    await authentication.close();
  });

  test(
    'initialization completes if disposed before the first auth event',
    () async {
      final authentication = FakeAuthenticationRepository()
        ..emitInitialState = false;
      final service = _createService(authentication, FakeAccountRepository());
      _disposeAfterTest(service, authentication);
      final initialization = service.initialize();

      service.dispose();
      await initialization;
    },
  );

  test('pending refresh completes safely when disposed', () async {
    final authentication = FakeAuthenticationRepository();
    final deferredAccount = Completer<IamAccount>();
    final accounts = FakeAccountRepository();
    final service = _createService(authentication, accounts);
    _disposeAfterTest(service, authentication);
    await service.initialize();
    accounts.currentAccountCompleter = deferredAccount;

    final refresh = service.refresh();
    await accounts.secondCurrentAccountCall.future;
    service.dispose();

    await refresh;
    deferredAccount.complete(syntheticIamAccount);
    await Future<void>.delayed(Duration.zero);
  });

  test(
    'password reset completes false without stale errors after disposal',
    () async {
      final authentication = FakeAuthenticationRepository(user: null)
        ..passwordResetCompleter = Completer<void>();
      final service = _createService(authentication, FakeAccountRepository());
      _disposeAfterTest(service, authentication);

      final reset = service.sendPasswordReset(' user@example.test ');
      expect(authentication.passwordResetCalls, 1);
      expect(authentication.lastPasswordResetEmail, 'user@example.test');
      authentication.passwordResetFailure = StateError('private reset detail');
      service.dispose();

      expect(await reset, isFalse);
      authentication.passwordResetCompleter!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(await service.sendPasswordReset('user@example.test'), isFalse);
      expect(service.error, isNull);
      expect(authentication.passwordResetCalls, 1);
    },
  );
}

AuthService _createService(
  FakeAuthenticationRepository authentication,
  FakeAccountRepository accounts,
) => AuthService(authentication: authentication, accounts: accounts);

void _disposeAfterTest(
  AuthService service,
  FakeAuthenticationRepository authentication,
) {
  addTearDown(() async {
    service.dispose();
    await authentication.close();
  });
}
