import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/iam/application/services/auth_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/authentication_lifecycle.dart';
import 'package:ichu_mobile_app/features/iam/application/services/professional_profile_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_failure.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_user.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/professional_profile.dart';

import '../../../support/fake_iam_repositories.dart';
import '../../../support/fake_professional_profile_repository.dart';

void main() {
  test(
    'explicit GET accepts nullable profiles for each verified role',
    () async {
      for (final role in AccountRole.values) {
        final account = _account(role: role, profile: null);
        final harness = _Harness(
          profileAccount: account,
          sessionAccount: account,
        );
        await harness.initialize();

        expect(await harness.service.load(), isTrue);
        expect(harness.profiles.loadCalls, 1);
        expect(harness.service.status, ProfessionalProfileStatus.ready);
        expect(harness.service.canView, isTrue);
        expect(harness.service.account, account);
        expect(harness.service.profile, isNull);
        expect(harness.service.canReload, isTrue);
        harness.dispose();
      }
    },
  );

  test('same-scope explicit GETs share one in-flight request', () async {
    final response = Completer<IamAccount>();
    final harness = _Harness()..profiles.loadCompleter = response;
    await harness.initialize();

    final firstLoad = harness.service.load();
    await harness.profiles.firstLoad.future;
    final secondLoad = harness.service.load();
    expect(harness.service.busy, isTrue);
    expect(harness.service.canView, isFalse);
    expect(harness.profiles.loadCalls, 1);

    response.complete(syntheticVeterinarianAccount);
    expect(await firstLoad, isTrue);
    expect(await secondLoad, isTrue);
    expect(harness.service.profile, syntheticProfessionalProfile);
    harness.dispose();
  });

  test(
    'failed refresh hides the previous profile and permits another GET',
    () async {
      final harness = _Harness();
      await harness.initialize();
      expect(await harness.service.load(), isTrue);
      expect(harness.service.canView, isTrue);

      harness.profiles.loadFailure = const AuthFailure(AuthFailureCode.network);
      expect(await harness.service.load(), isFalse);
      expect(harness.service.canView, isFalse);
      expect(harness.service.account, isNull);
      expect(harness.service.profile, isNull);
      expect(harness.service.status, ProfessionalProfileStatus.unavailable);
      expect(harness.service.error?.code, AuthFailureCode.network);

      harness.service.clearError();
      expect(harness.service.error, isNull);
      harness.profiles.loadFailure = null;
      expect(await harness.service.load(), isTrue);
      expect(harness.service.profile, syntheticProfessionalProfile);
      harness.dispose();
    },
  );

  for (final failureCode in <AuthFailureCode>[
    AuthFailureCode.forbidden,
    AuthFailureCode.accountUnavailable,
    AuthFailureCode.emailNotVerified,
  ]) {
    test(
      '$failureCode fails closed but allows explicit authorized recovery',
      () async {
        final harness = _Harness();
        await harness.initialize();
        await harness.service.load();
        harness.profiles.loadFailure = AuthFailure(failureCode);

        expect(await harness.service.load(), isFalse);
        expect(harness.service.canView, isFalse);
        expect(harness.service.account, isNull);
        expect(harness.service.profile, isNull);
        expect(harness.service.canReload, isTrue);
        expect(harness.service.error?.code, failureCode);

        harness.profiles.loadFailure = null;
        expect(await harness.service.load(), isTrue);
        expect(harness.service.canView, isTrue);
        expect(harness.profiles.loadCalls, 3);
        harness.dispose();
      },
    );
  }

  test(
    'fresh response must match account and email and have a valid profile',
    () async {
      for (final invalidResponse in <IamAccount>[
        _account(id: 'another-account'),
        _account(email: 'another@example.test'),
        _account(
          profile: const ProfessionalProfile(
            specialty: ' ',
            licenseNumber: 'CMVP-42',
            yearsOfExperience: 4,
          ),
        ),
      ]) {
        final harness = _Harness(profileAccount: invalidResponse);
        await harness.initialize();

        expect(await harness.service.load(), isFalse);
        expect(harness.service.status, ProfessionalProfileStatus.unavailable);
        expect(harness.service.error?.code, AuthFailureCode.invalidResponse);
        expect(harness.service.canView, isFalse);
        expect(harness.service.account, isNull);
        harness.dispose();
      }
    },
  );

  test(
    'auth revalidation clears data without automatically fetching a profile',
    () async {
      final harness = _Harness();
      await harness.initialize();
      await harness.service.load();
      expect(harness.profiles.loadCalls, 1);

      await harness.auth.refresh();
      expect(harness.service.canView, isFalse);
      expect(harness.service.account, isNull);
      expect(harness.profiles.loadCalls, 1);

      expect(await harness.service.load(), isTrue);
      expect(harness.profiles.loadCalls, 2);
      harness.dispose();
    },
  );

  test('late GET after logout cannot restore data', () async {
    final response = Completer<IamAccount>();
    final harness = _Harness()..profiles.loadCompleter = response;
    await harness.initialize();
    final load = harness.service.load();
    await harness.profiles.firstLoad.future;

    expect(await harness.auth.signOut(), isTrue);
    expect(harness.service.canView, isFalse);
    expect(harness.service.account, isNull);
    response.complete(syntheticVeterinarianAccount);
    expect(await load, isFalse);
    expect(harness.service.profile, isNull);
    harness.dispose();
  });

  test(
    'account or role change invalidates the old scope and does not fetch',
    () async {
      final harness = _Harness();
      await harness.initialize();
      await harness.service.load();
      final changed = _account(role: AccountRole.ranchManager);
      harness.accounts.account = changed;

      await harness.auth.refresh();
      expect(harness.service.canView, isFalse);
      expect(harness.service.account, isNull);
      expect(harness.profiles.loadCalls, 1);
      harness.profiles.account = changed;
      expect(await harness.service.load(), isTrue);
      expect(harness.service.account?.role, AccountRole.ranchManager);
      expect(harness.profiles.loadCalls, 2);
      harness.dispose();
    },
  );

  test(
    'dispose invalidates a pending GET and prevents late notification',
    () async {
      final response = Completer<IamAccount>();
      final harness = _Harness()..profiles.loadCompleter = response;
      await harness.initialize();
      var notifications = 0;
      harness.service.addListener(() => notifications++);
      final load = harness.service.load();
      await harness.profiles.firstLoad.future;
      final notificationsAtDispose = notifications;

      harness.service.dispose();
      response.complete(syntheticVeterinarianAccount);
      expect(await load, isFalse);
      expect(harness.service.profile, isNull);
      expect(notifications, notificationsAtDispose);
      harness.dispose();
    },
  );

  for (final changedAccount in [
    _account(id: 'a14116ee-27b2-416e-b2a3-f5cafed50f99'),
    _account(role: AccountRole.ranchManager),
    _account(),
  ]) {
    test(
      'pending GET cannot outlive same-UID revalidation to ${changedAccount.id}/${changedAccount.role.name}',
      () async {
        final response = Completer<IamAccount>();
        final harness = _Harness()..profiles.loadCompleter = response;
        await harness.initialize();
        final oldLoad = harness.service.load();
        await harness.profiles.firstLoad.future;

        harness.accounts.account = changedAccount;
        await harness.auth.refresh();
        expect(harness.service.canView, isFalse);
        harness.profiles
          ..loadCompleter = null
          ..account = changedAccount;
        expect(await harness.service.load(), isTrue);
        response.complete(syntheticVeterinarianAccount);
        expect(await oldLoad, isFalse);
        expect(harness.service.account, same(changedAccount));
        expect(harness.profiles.loadCalls, 2);
        harness.dispose();
      },
    );
  }

  test('missing session and unconfigured repository make no GET', () async {
    final noSession = _Harness(initialUser: null);
    await noSession.initialize();
    expect(await noSession.service.load(), isFalse);
    expect(noSession.profiles.loadCalls, 0);
    noSession.dispose();

    final unconfigured = _Harness()..profiles.isConfigured = false;
    await unconfigured.initialize();
    expect(await unconfigured.service.load(), isFalse);
    expect(unconfigured.service.error?.code, AuthFailureCode.configuration);
    expect(unconfigured.service.canReload, isFalse);
    expect(unconfigured.profiles.loadCalls, 0);
    unconfigured.dispose();
  });
}

IamAccount _account({
  String id = '8b3e7f19-42d6-4f31-9a50-6c0d82a314e7',
  String email = 'user@example.test',
  AccountRole role = AccountRole.veterinarian,
  ProfessionalProfile? profile = syntheticProfessionalProfile,
}) => IamAccount(
  id: id,
  email: email,
  role: role,
  status: 'TemporarilyBlocked',
  profile: profile,
);

final class _Harness {
  _Harness({
    AuthUser? initialUser = syntheticAuthUser,
    IamAccount? profileAccount,
    IamAccount? sessionAccount,
  }) : identity = FakeAuthenticationRepository(user: initialUser) {
    final initialAccount = sessionAccount ?? syntheticVeterinarianAccount;
    accounts = FakeAccountRepository(account: initialAccount);
    lifecycle = AuthenticationLifecycle(identity);
    auth = AuthService(authentication: lifecycle, accounts: accounts);
    profiles = FakeProfessionalProfileRepository(
      account: profileAccount ?? syntheticVeterinarianAccount,
    );
    service = ProfessionalProfileService(session: auth, profiles: profiles);
  }

  final FakeAuthenticationRepository identity;
  late final FakeAccountRepository accounts;
  late final AuthenticationLifecycle lifecycle;
  late final AuthService auth;
  late final FakeProfessionalProfileRepository profiles;
  late final ProfessionalProfileService service;

  Future<void> initialize() => auth.initialize();

  void dispose() {
    service.dispose();
    auth.dispose();
    lifecycle.dispose();
    unawaited(identity.close());
  }
}
