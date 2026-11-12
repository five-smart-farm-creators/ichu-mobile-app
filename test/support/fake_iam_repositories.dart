import 'dart:async';

import 'package:ichu_mobile_app/features/iam/domain/model/auth_user.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_access.dart';
import 'package:ichu_mobile_app/features/iam/domain/repositories/account_repository.dart';
import 'package:ichu_mobile_app/features/iam/domain/repositories/authentication_repository.dart';

/// Synthetic verified fixture only; this is not a live application identity.
const AuthUser syntheticAuthUser = AuthUser(
  uid: 'synthetic-uid',
  email: 'user@example.test',
  emailVerified: true,
  displayName: 'Test User',
);

/// Synthetic account fixture paired with [syntheticAuthUser].
const IamAccount syntheticIamAccount = IamAccount(
  id: 'accountUUID',
  email: 'user@example.test',
  role: AccountRole.ranchManager,
  status: 'active',
);

final class FakeAuthenticationRepository implements AuthenticationRepository {
  FakeAuthenticationRepository({
    this.isConfigured = true,
    AuthUser? user = syntheticAuthUser,
    AuthUser? signInUser,
  }) : user = user,
       signInUser = signInUser ?? user ?? syntheticAuthUser;

  @override
  bool isConfigured;

  AuthUser? user;
  AuthUser signInUser;
  AuthUser? reloadUserResult;
  bool overrideReloadUserResult = false;
  bool emitSignInEvents = true;
  bool emitSignOutEvents = true;
  bool emitInitialState = true;
  Object? signInFailure;
  Object? reloadFailure;
  Object? passwordResetFailure;
  Object? signOutFailure;
  Completer<void>? passwordResetCompleter;
  Completer<void>? signOutCompleter;

  int signInCalls = 0;
  int reloadUserCalls = 0;
  int passwordResetCalls = 0;
  int signOutCalls = 0;
  int idTokenCalls = 0;
  String? lastSignInEmail;
  String? lastSignInPassword;
  String? lastPasswordResetEmail;
  final List<Completer<AuthUser>> deferredSignInResponses =
      <Completer<AuthUser>>[];
  final List<Completer<void>> signInCallStarted = <Completer<void>>[];

  final StreamController<AuthUser?> _events =
      StreamController<AuthUser?>.broadcast(sync: true);

  @override
  AuthUser? get currentUser => user;

  @override
  Stream<AuthUser?> observeAuthState() async* {
    if (emitInitialState) yield user;
    yield* _events.stream;
  }

  void emit(AuthUser? nextUser) {
    user = nextUser;
    _events.add(nextUser);
  }

  void emitError(Object error) => _events.addError(error);

  @override
  Future<AuthUser> signIn(String email, String password) async {
    signInCalls++;
    lastSignInEmail = email;
    lastSignInPassword = password;
    final started = Completer<void>();
    signInCallStarted.add(started);
    started.complete();
    final failure = signInFailure;
    if (failure != null) throw failure;
    final deferredResponse = deferredSignInResponses.isEmpty
        ? null
        : deferredSignInResponses.removeAt(0);
    user = deferredResponse == null
        ? signInUser
        : await deferredResponse.future;
    if (emitSignInEvents) _events.add(user);
    return user!;
  }

  @override
  Future<AuthUser?> reloadUser() async {
    reloadUserCalls++;
    final failure = reloadFailure;
    if (failure != null) throw failure;
    return overrideReloadUserResult ? reloadUserResult : user;
  }

  @override
  Future<String> idToken({bool forceRefresh = false}) async {
    idTokenCalls++;
    return 'synthetic-token';
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    passwordResetCalls++;
    lastPasswordResetEmail = email;
    final completer = passwordResetCompleter;
    if (completer != null) await completer.future;
    final failure = passwordResetFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    final completer = signOutCompleter;
    if (completer != null) await completer.future;
    final failure = signOutFailure;
    if (failure != null) throw failure;
    user = null;
    if (emitSignOutEvents) _events.add(null);
  }

  Future<void> close() => _events.close();
}

final class FakeAccountRepository implements AccountRepository {
  FakeAccountRepository({
    this.isConfigured = true,
    this.account = syntheticIamAccount,
    List<RanchAccess> ranches = const <RanchAccess>[],
  }) : ranches = List<RanchAccess>.of(ranches);

  @override
  bool isConfigured;

  IamAccount account;
  List<RanchAccess> ranches;
  Object? currentAccountFailure;
  Object? ranchAccessFailure;
  Completer<IamAccount>? currentAccountCompleter;
  Completer<List<RanchAccess>>? ranchAccessCompleter;

  int currentAccountCalls = 0;
  int ranchAccessCalls = 0;
  final List<String> calls = <String>[];
  final Completer<void> firstCurrentAccountCall = Completer<void>();
  final Completer<void> secondCurrentAccountCall = Completer<void>();

  @override
  Future<IamAccount> currentAccount() async {
    currentAccountCalls++;
    calls.add('currentAccount');
    if (currentAccountCalls == 1 && !firstCurrentAccountCall.isCompleted) {
      firstCurrentAccountCall.complete();
    } else if (currentAccountCalls == 2 &&
        !secondCurrentAccountCall.isCompleted) {
      secondCurrentAccountCall.complete();
    }
    final failure = currentAccountFailure;
    if (failure != null) throw failure;
    final completer = currentAccountCompleter;
    if (completer != null) return completer.future;
    return account;
  }

  @override
  Future<List<RanchAccess>> ranchAccess() async {
    ranchAccessCalls++;
    calls.add('ranchAccess');
    final failure = ranchAccessFailure;
    if (failure != null) throw failure;
    final completer = ranchAccessCompleter;
    if (completer != null) return completer.future;
    return ranches;
  }
}
