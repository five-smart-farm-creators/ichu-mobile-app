import 'dart:async';

import 'package:ichu_mobile_app/features/iam/domain/model/account_registration_result.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_user.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/registration_details.dart';
import 'package:ichu_mobile_app/features/iam/domain/repositories/account_registration_repository.dart';
import 'package:ichu_mobile_app/features/iam/domain/repositories/identity_registration_repository.dart';

/// Synthetic, unverified onboarding identity; never a live application user.
const AuthUser syntheticRegistrationUser = AuthUser(
  uid: 'synthetic-registration-uid',
  email: 'registration@example.test',
  emailVerified: false,
  displayName: 'Registration Test User',
);

/// Synthetic backend account used only by registration-service tests.
const IamAccount syntheticRegistrationAccount = IamAccount(
  id: 'synthetic-registration-account',
  email: 'registration@example.test',
  role: AccountRole.veterinarian,
  status: 'PendingVerification',
);

const AccountRegistrationResult syntheticRegistrationResult =
    AccountRegistrationResult(
      account: syntheticRegistrationAccount,
      ranchId: null,
    );

/// Controllable identity adapter for tests; no Firebase SDK is involved.
final class FakeIdentityRegistrationRepository
    implements IdentityRegistrationRepository {
  @override
  bool isConfigured = true;
  AuthUser? user;
  AuthUser createUserResult = syntheticRegistrationUser;
  AuthUser signInUser = syntheticRegistrationUser;
  AuthUser? reloadUserResult;
  bool overrideReloadUserResult = false;
  Object? observationFailure;

  Object? createUserFailure;
  Object? signInFailure;
  Object? sendVerificationFailure;
  Object? reloadUserFailure;
  Object? signOutFailure;

  Completer<AuthUser>? createUserCompleter;
  Completer<AuthUser>? signInCompleter;
  Completer<void>? sendVerificationCompleter;
  Completer<AuthUser?>? reloadUserCompleter;
  Completer<void>? signOutCompleter;

  int createUserCalls = 0;
  int signInCalls = 0;
  int sendVerificationCalls = 0;
  int reloadUserCalls = 0;
  int signOutCalls = 0;
  String? lastCreateEmail;
  String? lastCreatePassword;
  String? lastSignInEmail;
  String? lastSignInPassword;

  final List<Completer<void>> createUserCallStarted = <Completer<void>>[];
  final List<Completer<void>> signInCallStarted = <Completer<void>>[];
  final List<Completer<void>> sendVerificationCallStarted = <Completer<void>>[];
  final List<Completer<void>> reloadUserCallStarted = <Completer<void>>[];
  final StreamController<AuthUser?> _events =
      StreamController<AuthUser?>.broadcast(sync: true);

  @override
  AuthUser? get currentUser => user;

  @override
  Stream<AuthUser?> observeAuthState() async* {
    final failure = observationFailure;
    if (failure != null) throw failure;
    yield user;
    yield* _events.stream;
  }

  void emit(AuthUser? nextUser) {
    user = nextUser;
    _events.add(nextUser);
  }

  @override
  Future<AuthUser> createUser(String email, String password) async {
    createUserCalls++;
    lastCreateEmail = email;
    lastCreatePassword = password;
    _signal(createUserCallStarted);
    final failure = createUserFailure;
    if (failure != null) throw failure;
    final deferred = createUserCompleter;
    final created = deferred == null ? createUserResult : await deferred.future;
    user = created;
    _events.add(created);
    return created;
  }

  @override
  Future<AuthUser> signIn(String email, String password) async {
    signInCalls++;
    lastSignInEmail = email;
    lastSignInPassword = password;
    _signal(signInCallStarted);
    final failure = signInFailure;
    if (failure != null) throw failure;
    final deferred = signInCompleter;
    final signedIn = deferred == null ? signInUser : await deferred.future;
    user = signedIn;
    _events.add(signedIn);
    return signedIn;
  }

  @override
  Future<void> sendEmailVerification() async {
    sendVerificationCalls++;
    _signal(sendVerificationCallStarted);
    final deferred = sendVerificationCompleter;
    if (deferred != null) await deferred.future;
    final failure = sendVerificationFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<AuthUser?> reloadUser() async {
    reloadUserCalls++;
    _signal(reloadUserCallStarted);
    final failure = reloadUserFailure;
    if (failure != null) throw failure;
    final deferred = reloadUserCompleter;
    final refreshed = deferred != null
        ? await deferred.future
        : overrideReloadUserResult
        ? reloadUserResult
        : user;
    return refreshed;
  }

  @override
  Future<String> idToken({bool forceRefresh = false}) async =>
      'synthetic-registration-token';

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> signOut() async {
    signOutCalls++;
    final deferred = signOutCompleter;
    if (deferred != null) await deferred.future;
    final failure = signOutFailure;
    if (failure != null) throw failure;
    user = null;
    _events.add(null);
  }

  Future<void> close() => _events.close();

  void _signal(List<Completer<void>> signals) {
    final signal = Completer<void>();
    signals.add(signal);
    signal.complete();
  }
}

/// Controllable backend adapter that records the exact create and GET calls.
final class FakeAccountRegistrationRepository
    implements AccountRegistrationRepository {
  @override
  bool isConfigured = true;
  AccountRegistrationResult result = syntheticRegistrationResult;
  IamAccount account = syntheticRegistrationAccount;
  Object? registerFailure;
  Object? currentAccountFailure;
  Completer<AccountRegistrationResult>? registerCompleter;
  Completer<IamAccount>? currentAccountCompleter;

  int registerCalls = 0;
  int currentAccountCalls = 0;
  final List<({String email, RegistrationDetails details})> requests =
      <({String email, RegistrationDetails details})>[];
  final List<Completer<void>> registerCallStarted = <Completer<void>>[];
  final List<Completer<void>> currentAccountCallStarted = <Completer<void>>[];

  @override
  Future<AccountRegistrationResult> registerAccount({
    required String email,
    required RegistrationDetails details,
  }) async {
    registerCalls++;
    requests.add((email: email, details: details));
    _signal(registerCallStarted);
    final deferred = registerCompleter;
    final response = deferred == null ? result : await deferred.future;
    final failure = registerFailure;
    if (failure != null) throw failure;
    return response;
  }

  @override
  Future<IamAccount> currentAccount() async {
    currentAccountCalls++;
    _signal(currentAccountCallStarted);
    final deferred = currentAccountCompleter;
    if (deferred != null) return deferred.future;
    final failure = currentAccountFailure;
    if (failure != null) throw failure;
    return account;
  }

  void _signal(List<Completer<void>> signals) {
    final signal = Completer<void>();
    signals.add(signal);
    signal.complete();
  }
}
