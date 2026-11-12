import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/iam/application/services/authentication_lifecycle.dart';
import 'package:ichu_mobile_app/features/iam/application/services/registration_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/account_registration_result.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_failure.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_user.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/registration_details.dart';

import '../../../support/fake_registration_repositories.dart';

void main() {
  test(
    'absent native configuration remains a configuration failure, not network',
    () async {
      final harness = _Harness()
        ..identity.isConfigured = false
        ..identity.observationFailure = const AuthFailure(
          AuthFailureCode.configuration,
        );
      await harness.service.initialize();
      expect(harness.service.status, RegistrationStatus.unavailable);
      expect(harness.service.error?.code, AuthFailureCode.configuration);
      expect(harness.service.canRegister, isFalse);
      expect(harness.identity.createUserCalls, 0);
      expect(harness.accounts.registerCalls, 0);
      harness.dispose();
    },
  );

  test('restore observes identity without mail or backend calls', () async {
    final harness = _Harness(initialUser: _verifiedUser);

    final initialization = harness.service.initialize();
    expect(identical(initialization, harness.service.initialize()), isTrue);
    await initialization;

    expect(harness.service.status, RegistrationStatus.awaitingVerification);
    expect(harness.service.user, _verifiedUser);
    expect(harness.service.verificationSent, isFalse);
    expect(harness.identity.sendVerificationCalls, 0);
    expect(harness.identity.reloadUserCalls, 0);
    expect(harness.accounts.registerCalls, 0);
    expect(harness.accounts.currentAccountCalls, 0);
    harness.dispose();
  });

  test(
    'register trims email, preserves password, and waits for verification',
    () async {
      final harness = _Harness();
      await harness.service.initialize();

      expect(
        await harness.service.register(
          '  registration@example.test  ',
          '  exact password  ',
        ),
        isTrue,
      );

      expect(harness.identity.lastCreateEmail, 'registration@example.test');
      expect(harness.identity.lastCreatePassword, '  exact password  ');
      expect(harness.service.user, syntheticRegistrationUser);
      expect(harness.service.status, RegistrationStatus.awaitingVerification);
      expect(harness.service.verificationSent, isTrue);
      expect(harness.accounts.registerCalls, 0);
      expect(harness.accounts.currentAccountCalls, 0);
      harness.dispose();
    },
  );

  test(
    'identity creation failure is stable and never calls the backend',
    () async {
      final harness = _Harness()
        ..identity.createUserFailure = StateError('private provider detail');
      await harness.service.initialize();

      expect(
        await harness.service.register('registration@example.test', 'password'),
        isFalse,
      );
      expect(harness.service.status, RegistrationStatus.idle);
      expect(harness.service.error?.code, AuthFailureCode.serviceUnavailable);
      expect(
        harness.service.error?.toString(),
        'AuthFailure(serviceUnavailable)',
      );
      expect(harness.identity.createUserCalls, 1);
      expect(harness.identity.sendVerificationCalls, 0);
      expect(harness.accounts.registerCalls, 0);
      harness.dispose();
    },
  );

  test(
    'a created identity must match the requested email before verification mail',
    () async {
      final harness = _Harness()
        ..identity.createUserResult = const AuthUser(
          uid: 'unexpected-uid',
          email: 'someone-else@example.test',
          emailVerified: false,
        );
      await harness.service.initialize();
      expect(
        await harness.service.register('registration@example.test', 'password'),
        isFalse,
      );
      expect(harness.service.error?.code, AuthFailureCode.invalidResponse);
      expect(harness.service.user, isNull);
      expect(harness.identity.sendVerificationCalls, 0);
      expect(harness.accounts.registerCalls, 0);
      expect(await harness.service.cancel(), isTrue);
      expect(harness.identity.currentUser, isNull);
      harness.dispose();
    },
  );

  test(
    'verification-mail failure preserves the identity without recreating it',
    () async {
      final harness = _Harness()
        ..identity.sendVerificationFailure = StateError(
          'private provider detail',
        );
      await harness.service.initialize();

      expect(
        await harness.service.register('registration@example.test', 'password'),
        isFalse,
      );
      expect(harness.service.status, RegistrationStatus.awaitingVerification);
      expect(harness.service.user, syntheticRegistrationUser);
      expect(harness.service.verificationSent, isFalse);
      expect(harness.service.error?.code, AuthFailureCode.serviceUnavailable);
      expect(
        harness.service.error?.toString(),
        'AuthFailure(serviceUnavailable)',
      );
      expect(harness.identity.createUserCalls, 1);

      harness.identity.sendVerificationFailure = null;
      expect(
        await harness.service.register('registration@example.test', 'password'),
        isFalse,
      );
      expect(harness.identity.createUserCalls, 1);
      expect(await harness.service.resendVerification(), isTrue);
      expect(harness.identity.sendVerificationCalls, 2);
      expect(harness.accounts.registerCalls, 0);
      harness.dispose();
    },
  );

  test(
    'resume does not automatically resend mail, even for unverified user',
    () async {
      final harness = _Harness();
      await harness.service.initialize();

      expect(
        await harness.service.resume(
          '  registration@example.test  ',
          '  exact password  ',
        ),
        isTrue,
      );

      expect(harness.identity.lastSignInEmail, 'registration@example.test');
      expect(harness.identity.lastSignInPassword, '  exact password  ');
      expect(harness.identity.sendVerificationCalls, 0);
      expect(harness.service.user, syntheticRegistrationUser);
      expect(harness.service.status, RegistrationStatus.awaitingVerification);
      expect(await harness.service.resendVerification(), isTrue);
      expect(harness.identity.sendVerificationCalls, 1);
      expect(harness.accounts.registerCalls, 0);
      harness.dispose();
    },
  );

  test(
    'resume needs only the isolated identity provider to be configured',
    () async {
      final harness = _Harness()..accounts.isConfigured = false;
      await harness.service.initialize();

      expect(harness.service.canRegister, isFalse);
      expect(harness.service.canResume, isTrue);
      expect(
        await harness.service.resume('registration@example.test', 'password'),
        isTrue,
      );
      expect(harness.identity.signInCalls, 1);
      expect(harness.accounts.registerCalls, 0);
      harness.dispose();
    },
  );

  test('verified resumed identity still needs explicit completion', () async {
    final harness = _Harness()..identity.signInUser = _verifiedUser;
    await harness.service.initialize();

    expect(
      await harness.service.resume('registration@example.test', 'password'),
      isTrue,
    );
    expect(harness.service.status, RegistrationStatus.awaitingVerification);
    expect(harness.identity.sendVerificationCalls, 0);
    expect(harness.accounts.registerCalls, 0);

    expect(await harness.service.complete(_veterinarianDetails), isTrue);
    expect(harness.accounts.registerCalls, 1);
    expect(harness.service.status, RegistrationStatus.completed);
    harness.dispose();
  });

  test(
    'complete reloads verification and makes no POST while unverified',
    () async {
      final harness = _Harness(initialUser: syntheticRegistrationUser);
      await harness.service.initialize();

      expect(await harness.service.complete(_veterinarianDetails), isFalse);

      expect(harness.identity.reloadUserCalls, 1);
      expect(harness.accounts.registerCalls, 0);
      expect(harness.accounts.currentAccountCalls, 0);
      expect(harness.service.status, RegistrationStatus.awaitingVerification);
      expect(harness.service.error?.code, AuthFailureCode.emailNotVerified);
      expect(harness.service.needsReconciliation, isFalse);
      harness.dispose();
    },
  );

  test(
    'valid veterinarian registration accepts the backend account result',
    () async {
      final serverAccount = IamAccount(
        id: 'server-vet-id',
        email: syntheticRegistrationUser.email,
        role: AccountRole.veterinarian,
        status: 'PendingVerification',
      );
      final harness = _Harness(
        initialUser: syntheticRegistrationUser,
        result: AccountRegistrationResult(account: serverAccount),
      )..verifyOnReload();
      await harness.service.initialize();

      expect(await harness.service.complete(_veterinarianDetails), isTrue);

      expect(harness.accounts.registerCalls, 1);
      expect(harness.accounts.currentAccountCalls, 0);
      expect(
        harness.accounts.requests.single.email,
        'registration@example.test',
      );
      expect(harness.accounts.requests.single.details, _veterinarianDetails);
      expect(harness.service.account, serverAccount);
      expect(harness.service.user, isNull);
      expect(harness.service.status, RegistrationStatus.completed);
      expect(harness.identity.signOutCalls, 1);
      expect(harness.service.needsReconciliation, isFalse);
      harness.dispose();
    },
  );

  test(
    'valid ranch-manager registration forwards the required ranch details',
    () async {
      const details = RegistrationDetails(
        role: AccountRole.ranchManager,
        ranch: RanchRegistration(
          name: 'North Ranch',
          region: 'Highlands',
          district: 'North District',
          estimatedHeadCount: 42,
        ),
      );
      final account = IamAccount(
        id: 'server-manager-id',
        email: syntheticRegistrationUser.email,
        role: AccountRole.ranchManager,
        status: 'PendingVerification',
      );
      final harness = _Harness(
        initialUser: syntheticRegistrationUser,
        result: AccountRegistrationResult(account: account, ranchId: 'ranch-1'),
      )..verifyOnReload();
      await harness.service.initialize();

      expect(await harness.service.complete(details), isTrue);
      expect(harness.accounts.requests.single.details, details);
      expect(harness.service.account?.role, AccountRole.ranchManager);
      harness.dispose();
    },
  );

  test(
    'invalid role and manager-without-ranch are rejected before network work',
    () async {
      final harness = _Harness(initialUser: syntheticRegistrationUser);
      await harness.service.initialize();
      const managerWithoutRanch = RegistrationDetails(
        role: AccountRole.ranchManager,
      );
      const fieldOperator = RegistrationDetails(
        role: AccountRole.fieldOperator,
      );

      expect(await harness.service.complete(managerWithoutRanch), isFalse);
      expect(harness.service.error?.code, AuthFailureCode.registrationRejected);
      expect(await harness.service.complete(fieldOperator), isFalse);

      expect(harness.identity.reloadUserCalls, 0);
      expect(harness.accounts.registerCalls, 0);
      expect(harness.accounts.currentAccountCalls, 0);
      harness.dispose();
    },
  );

  test(
    'duplicate and timeout outcomes require explicit safe GET reconciliation',
    () async {
      for (final failureCode in <AuthFailureCode>[
        AuthFailureCode.accountAlreadyExists,
        AuthFailureCode.network,
      ]) {
        final backendAccount = IamAccount(
          id: 'existing-account-${failureCode.name}',
          email: syntheticRegistrationUser.email,
          // The backend's existing account is authoritative, not the form role.
          role: AccountRole.ranchManager,
          status: 'Active',
        );
        final harness = _Harness(
          initialUser: syntheticRegistrationUser,
          account: backendAccount,
        )..verifyOnReload();
        await harness.service.initialize();
        harness.accounts.registerFailure = AuthFailure(failureCode);

        expect(await harness.service.complete(_veterinarianDetails), isFalse);
        expect(harness.service.needsReconciliation, isTrue);
        expect(harness.service.error?.code, failureCode);
        // A stale creation submit is converted to the safe GET, never replayed.
        expect(await harness.service.complete(_fieldOperatorDetails), isTrue);
        expect(harness.accounts.registerCalls, 1);
        expect(harness.accounts.currentAccountCalls, 1);
        expect(harness.service.account, backendAccount);
        expect(harness.service.account?.role, AccountRole.ranchManager);
        expect(harness.service.needsReconciliation, isFalse);
        expect(harness.service.status, RegistrationStatus.completed);
        harness.dispose();
      }
    },
  );

  test(
    'current-account lookup failure keeps reconciliation required',
    () async {
      final harness = _Harness(initialUser: syntheticRegistrationUser)
        ..verifyOnReload();
      await harness.service.initialize();
      harness.accounts.registerFailure = const AuthFailure(
        AuthFailureCode.accountAlreadyExists,
      );
      expect(await harness.service.complete(_veterinarianDetails), isFalse);
      harness.accounts.registerFailure = null;
      harness.accounts.currentAccountFailure = const AuthFailure(
        AuthFailureCode.network,
      );

      expect(await harness.service.reconcile(), isFalse);
      expect(harness.service.needsReconciliation, isTrue);
      expect(harness.service.status, RegistrationStatus.awaitingVerification);
      expect(harness.service.error?.code, AuthFailureCode.network);
      expect(harness.accounts.registerCalls, 1);
      expect(harness.accounts.currentAccountCalls, 1);

      harness.accounts.currentAccountFailure = null;
      expect(await harness.service.reconcile(), isTrue);
      expect(harness.accounts.registerCalls, 1);
      expect(harness.accounts.currentAccountCalls, 2);
      expect(harness.service.needsReconciliation, isFalse);
      harness.dispose();
    },
  );

  test(
    'definitive registration rejection permits a corrected explicit retry',
    () async {
      final harness = _Harness(initialUser: syntheticRegistrationUser)
        ..verifyOnReload();
      await harness.service.initialize();
      harness.accounts.registerFailure = const AuthFailure(
        AuthFailureCode.registrationRejected,
      );

      expect(await harness.service.complete(_veterinarianDetails), isFalse);
      expect(harness.service.needsReconciliation, isFalse);
      harness.accounts.registerFailure = null;
      expect(await harness.service.complete(_veterinarianDetails), isTrue);
      expect(harness.accounts.registerCalls, 2);
      harness.dispose();
    },
  );

  test(
    'mismatched creation response requires explicit safe reconciliation',
    () async {
      final mismatchedAccount = IamAccount(
        id: 'wrong-account-id',
        email: 'someone-else@example.test',
        role: AccountRole.veterinarian,
        status: 'PendingVerification',
      );
      final harness = _Harness(
        initialUser: syntheticRegistrationUser,
        result: AccountRegistrationResult(account: mismatchedAccount),
      )..verifyOnReload();
      await harness.service.initialize();

      expect(await harness.service.complete(_veterinarianDetails), isFalse);
      expect(harness.service.account, isNull);
      expect(harness.service.error?.code, AuthFailureCode.invalidResponse);
      expect(harness.service.needsReconciliation, isTrue);
      // The second explicit submit performs GET reconciliation. A matching
      // server account may now be acknowledged without replaying creation.
      expect(await harness.service.complete(_veterinarianDetails), isTrue);
      expect(harness.accounts.registerCalls, 1);
      expect(harness.accounts.currentAccountCalls, 1);
      harness.dispose();
    },
  );

  test(
    'reconciliation rejects an account whose email differs from identity',
    () async {
      final harness = _Harness(initialUser: syntheticRegistrationUser)
        ..verifyOnReload();
      await harness.service.initialize();
      harness.accounts.registerFailure = const AuthFailure(
        AuthFailureCode.accountAlreadyExists,
      );
      expect(await harness.service.complete(_veterinarianDetails), isFalse);
      harness.accounts.registerFailure = null;
      harness.accounts.account = const IamAccount(
        id: 'mismatched-existing-account',
        email: 'another@example.test',
        role: AccountRole.ranchManager,
        status: 'Active',
      );

      expect(await harness.service.reconcile(), isFalse);
      expect(harness.service.account, isNull);
      expect(harness.service.error?.code, AuthFailureCode.invalidResponse);
      expect(harness.service.needsReconciliation, isTrue);
      expect(harness.accounts.registerCalls, 1);
      expect(harness.accounts.currentAccountCalls, 1);
      expect(harness.identity.signOutCalls, 0);
      harness.dispose();
    },
  );

  test(
    'sign-out failure preserves the created account and cancel retries cleanup',
    () async {
      final harness = _Harness(initialUser: syntheticRegistrationUser)
        ..verifyOnReload()
        ..identity.signOutFailure = StateError('private sign-out detail');
      await harness.service.initialize();

      expect(await harness.service.complete(_veterinarianDetails), isFalse);
      expect(harness.service.status, RegistrationStatus.unavailable);
      expect(harness.service.error?.code, AuthFailureCode.signOutFailed);
      expect(harness.service.requiresSignOut, isTrue);
      expect(harness.service.account, syntheticRegistrationAccount);
      expect(harness.accounts.registerCalls, 1);

      harness.identity.signOutFailure = null;
      expect(await harness.service.cancel(), isTrue);
      expect(harness.service.status, RegistrationStatus.completed);
      expect(harness.service.account, syntheticRegistrationAccount);
      expect(harness.service.requiresSignOut, isFalse);
      expect(harness.accounts.registerCalls, 1);
      expect(harness.identity.user, isNull);
      harness.dispose();
    },
  );

  test(
    'cancel during create suppresses the late identity and backend work',
    () async {
      final harness = _Harness()
        ..identity.createUserCompleter = Completer<AuthUser>();
      await harness.service.initialize();

      final registering = harness.service.register(
        'registration@example.test',
        'password',
      );
      await Future<void>.delayed(Duration.zero);
      await harness.identity.createUserCallStarted.single.future;
      expect(await harness.service.cancel(), isTrue);
      harness.identity.createUserCompleter!.complete(syntheticRegistrationUser);

      expect(await registering, isFalse);
      expect(harness.identity.user, isNull);
      expect(harness.accounts.registerCalls, 0);
      expect(harness.service.user, isNull);
      expect(harness.service.status, RegistrationStatus.idle);
      harness.dispose();
    },
  );

  test(
    'cancel during verification mail suppresses the late send result',
    () async {
      final harness = _Harness()
        ..identity.sendVerificationCompleter = Completer<void>();
      await harness.service.initialize();
      final registering = harness.service.register(
        'registration@example.test',
        'password',
      );
      await Future<void>.delayed(Duration.zero);
      await harness.identity.sendVerificationCallStarted.single.future;

      expect(await harness.service.cancel(), isTrue);
      harness.identity.sendVerificationCompleter!.complete();

      expect(await registering, isFalse);
      expect(harness.service.status, RegistrationStatus.idle);
      expect(harness.service.user, isNull);
      expect(harness.accounts.registerCalls, 0);
      harness.dispose();
    },
  );

  test('cancel during reload prevents the backend POST', () async {
    final harness = _Harness(initialUser: syntheticRegistrationUser)
      ..identity.reloadUserCompleter = Completer<AuthUser?>();
    await harness.service.initialize();
    final completing = harness.service.complete(_veterinarianDetails);
    await Future<void>.delayed(Duration.zero);
    await harness.identity.reloadUserCallStarted.single.future;

    expect(await harness.service.cancel(), isTrue);
    harness.identity.reloadUserCompleter!.complete(_verifiedUser);

    expect(await completing, isFalse);
    expect(harness.accounts.registerCalls, 0);
    expect(harness.service.status, RegistrationStatus.idle);
    expect(harness.service.user, isNull);
    harness.dispose();
  });

  test('cancel during an uncertain POST ignores the late response', () async {
    final harness = _Harness(initialUser: syntheticRegistrationUser)
      ..verifyOnReload()
      ..accounts.registerCompleter = Completer<AccountRegistrationResult>();
    await harness.service.initialize();
    final completing = harness.service.complete(_veterinarianDetails);
    await Future<void>.delayed(Duration.zero);
    await harness.accounts.registerCallStarted.single.future;

    expect(harness.service.needsReconciliation, isTrue);
    expect(await harness.service.cancel(), isTrue);
    harness.accounts.registerCompleter!.complete(syntheticRegistrationResult);

    expect(await completing, isFalse);
    expect(harness.service.account, isNull);
    expect(harness.service.status, RegistrationStatus.idle);
    expect(harness.service.needsReconciliation, isTrue);
    expect(harness.accounts.registerCalls, 1);
    // Resuming this same UID still reconciles rather than replaying creation.
    harness.identity.signInUser = _verifiedUser;
    expect(
      await harness.service.resume('registration@example.test', 'password'),
      isTrue,
    );
    expect(harness.service.needsReconciliation, isTrue);
    expect(harness.accounts.registerCalls, 1);
    harness.dispose();
  });

  test(
    'dispose during native create retains lifecycle cleanup for late identity',
    () async {
      final harness = _Harness()
        ..identity.createUserCompleter = Completer<AuthUser>();
      await harness.service.initialize();
      final registering = harness.service.register(
        'registration@example.test',
        'password',
      );
      await Future<void>.delayed(Duration.zero);
      await harness.identity.createUserCallStarted.single.future;

      harness.service.dispose();
      harness.identity.createUserCompleter!.complete(syntheticRegistrationUser);

      expect(await registering, isFalse);
      expect(harness.identity.user, isNull);
      expect(harness.accounts.registerCalls, 0);
      harness.lifecycle.dispose();
      await harness.identity.close();
    },
  );

  test('dispose during POST cannot publish a late backend response', () async {
    final harness = _Harness(initialUser: syntheticRegistrationUser)
      ..verifyOnReload()
      ..accounts.registerCompleter = Completer<AccountRegistrationResult>();
    await harness.service.initialize();
    final completing = harness.service.complete(_veterinarianDetails);
    await Future<void>.delayed(Duration.zero);
    await harness.accounts.registerCallStarted.single.future;

    harness.service.dispose();
    harness.accounts.registerCompleter!.complete(syntheticRegistrationResult);

    expect(await completing, isFalse);
    expect(harness.service.account, isNull);
    expect(harness.accounts.registerCalls, 1);
    harness.lifecycle.dispose();
    await harness.identity.close();
  });

  test(
    'an uncertain registration cannot lock a different identity out of creation',
    () async {
      final harness = _Harness(initialUser: _verifiedUser);
      await harness.service.initialize();
      harness.accounts.registerFailure = const AuthFailure(
        AuthFailureCode.network,
      );
      expect(await harness.service.complete(_veterinarianDetails), isFalse);
      expect(await harness.service.cancel(), isTrue);
      const secondUser = AuthUser(
        uid: 'second-uid',
        email: 'second@example.test',
        emailVerified: true,
      );
      harness.identity.signInUser = secondUser;
      expect(
        await harness.service.resume(secondUser.email, 'password'),
        isTrue,
      );
      expect(harness.service.needsReconciliation, isFalse);
      harness.accounts
        ..registerFailure = null
        ..result = const AccountRegistrationResult(
          account: IamAccount(
            id: 'second-account',
            email: 'second@example.test',
            role: AccountRole.veterinarian,
            status: 'PendingVerification',
          ),
        );
      expect(await harness.service.complete(_veterinarianDetails), isTrue);
      expect(harness.accounts.registerCalls, 2);
      expect(harness.accounts.currentAccountCalls, 0);
      expect(harness.service.account?.email, secondUser.email);
      harness.dispose();
    },
  );

  test(
    'returning to the original UID preserves its own unresolved POST',
    () async {
      final harness = _Harness(initialUser: _verifiedUser);
      await harness.service.initialize();
      harness.accounts.registerFailure = const AuthFailure(
        AuthFailureCode.network,
      );
      expect(await harness.service.complete(_veterinarianDetails), isFalse);
      expect(await harness.service.cancel(), isTrue);
      const secondUser = AuthUser(
        uid: 'second-uid',
        email: 'second@example.test',
        emailVerified: true,
      );
      harness.identity.signInUser = secondUser;
      expect(
        await harness.service.resume(secondUser.email, 'password'),
        isTrue,
      );
      expect(harness.service.needsReconciliation, isFalse);
      expect(await harness.service.cancel(), isTrue);
      harness.identity.signInUser = _verifiedUser;
      expect(
        await harness.service.resume(_verifiedUser.email, 'password'),
        isTrue,
      );
      expect(harness.service.needsReconciliation, isTrue);
      expect(await harness.service.reconcile(), isTrue);
      expect(harness.accounts.registerCalls, 1);
      expect(harness.accounts.currentAccountCalls, 1);
      harness.dispose();
    },
  );
}

const RegistrationDetails _veterinarianDetails = RegistrationDetails(
  role: AccountRole.veterinarian,
);

const RegistrationDetails _fieldOperatorDetails = RegistrationDetails(
  role: AccountRole.fieldOperator,
);

final AuthUser _verifiedUser = AuthUser(
  uid: syntheticRegistrationUser.uid,
  email: syntheticRegistrationUser.email,
  emailVerified: true,
  displayName: syntheticRegistrationUser.displayName,
);

final class _Harness {
  _Harness({
    AuthUser? initialUser,
    AccountRegistrationResult result = syntheticRegistrationResult,
    IamAccount account = syntheticRegistrationAccount,
  }) : identity = FakeIdentityRegistrationRepository() {
    identity.user = initialUser;
    accounts = FakeAccountRegistrationRepository()
      ..result = result
      ..account = account;
    lifecycle = AuthenticationLifecycle(identity);
    service = RegistrationService(
      authentication: lifecycle,
      accounts: accounts,
    );
  }

  final FakeIdentityRegistrationRepository identity;
  late final FakeAccountRegistrationRepository accounts;
  late final AuthenticationLifecycle lifecycle;
  late final RegistrationService service;

  void verifyOnReload() {
    identity
      ..overrideReloadUserResult = true
      ..reloadUserResult = _verifiedUser;
  }

  void dispose() {
    service.dispose();
    lifecycle.dispose();
    unawaited(identity.close());
  }
}
