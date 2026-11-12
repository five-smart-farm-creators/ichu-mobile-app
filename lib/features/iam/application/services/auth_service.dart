import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/model/auth_failure.dart';
import '../../domain/model/auth_user.dart';
import '../../domain/model/iam_account.dart';
import '../../domain/model/ranch_access.dart';
import '../../domain/repositories/account_repository.dart';
import 'authentication_lifecycle.dart';

enum SessionStatus {
  checking,
  signedOut,
  signingIn,
  authenticated,
  signingOut,
  unavailable,
}

final class AuthService extends ChangeNotifier {
  AuthService({required this._authentication, required this._accounts}) {
    _authentication.addListener(_onAuthenticationLifecycleChanged);
  }

  final AuthenticationLifecycle _authentication;
  final AccountRepository _accounts;
  final Set<String> _suppressedUids = <String>{};
  final Completer<void> _disposedCompleter = Completer<void>();

  SessionStatus _status = SessionStatus.checking;
  AuthFailure? _error;
  AuthUser? _user;
  IamAccount? _account;
  List<RanchAccess> _ranches = const <RanchAccess>[];

  StreamSubscription<AuthUser?>? _subscription;
  Completer<void>? _initializationCompleter;
  Future<void>? _initializationFuture;
  int _generation = 0;
  int? _observerSuppressedBy;
  String? _validatingUid;
  int? _validatingGeneration;
  bool _hasObservedInitialState = false;
  bool _passwordResetInProgress = false;
  bool _nativeSignOutInProgress = false;
  bool _suppressNextSignOutNullEvent = false;
  bool _disposed = false;

  SessionStatus get status => _status;

  bool get busy =>
      _status == SessionStatus.checking ||
      _status == SessionStatus.signingIn ||
      _status == SessionStatus.signingOut ||
      _authentication.busy;

  bool get requiresSignOut => _authentication.cleanupFailure != null;

  bool get canSignIn => _authentication.isConfigured && _accounts.isConfigured;

  bool get canRecover => _authentication.isConfigured;

  AuthFailure? get error => _error;

  AuthUser? get user => _user;

  IamAccount? get account => _account;

  List<RanchAccess> get ranches => _ranches;

  /// Subscribes once and completes after the first auth event is validated.
  Future<void> initialize() {
    if (_disposed) return Future<void>.value();
    final existing = _initializationFuture;
    if (existing != null) return existing;

    final completer = Completer<void>();
    _initializationCompleter = completer;
    _initializationFuture = completer.future;

    try {
      _subscription = _authentication.observeAuthState().listen(
        _onAuthStateChanged,
        onError: _onAuthStateError,
        onDone: _onAuthStateDone,
      );
    } catch (error) {
      _handleObserverFailure(error);
      _completeInitialization();
    }

    return _initializationFuture!;
  }

  Future<bool> signIn(String email, String password) async {
    if (_disposed || _isCommandInProgress) return false;
    if (requiresSignOut) {
      _setUnavailable(const AuthFailure(AuthFailureCode.signOutFailed));
      return false;
    }
    if (!canSignIn) {
      final rejectedUid = _validatingUid ?? _user?.uid ?? _currentUid;
      if (rejectedUid != null) _suppressedUids.add(rejectedUid);
      ++_generation;
      _validatingUid = null;
      _validatingGeneration = null;
      _setUnavailable(const AuthFailure(AuthFailureCode.configuration));
      if (_hasObservedInitialState) _completeInitialization();
      return false;
    }

    final previousUid = _user?.uid ?? _currentUid;
    final generation = _beginCommand(SessionStatus.signingIn);
    if (previousUid != null) _suppressedUids.add(previousUid);
    AuthUser? identity;

    try {
      identity = await _authentication.signIn(email.trim(), password);
      if (!_isCurrent(generation)) return false;

      final snapshot = await Future.any<_SessionSnapshot?>([
        _loadAuthorizedSession(identity, generation: generation),
        _disposedCompleter.future.then<_SessionSnapshot?>((_) => null),
      ]);
      if (snapshot == null || !_isCurrent(generation)) return false;

      _suppressedUids.remove(identity.uid);
      _setAuthenticated(snapshot);
      return true;
    } catch (error) {
      if (!_isCurrent(generation)) return false;
      final failure = _failure(error, AuthFailureCode.unknown);
      if (identity == null) {
        _setUnavailable(failure);
      } else {
        await _rejectIdentity(identity.uid, generation, failure);
      }
      return false;
    } finally {
      _endCommand(generation);
      _notify();
    }
  }

  Future<bool> sendPasswordReset(String email) async {
    if (_disposed || _isCommandInProgress || _passwordResetInProgress) {
      return false;
    }
    if (!canRecover) {
      _setError(const AuthFailure(AuthFailureCode.configuration));
      return false;
    }

    final generation = _generation;
    _passwordResetInProgress = true;
    _setError(null);
    try {
      await Future.any<void>([
        _authentication.sendPasswordReset(email.trim()),
        _disposedCompleter.future,
      ]);
      if (_disposed || _generation != generation) return false;
      return true;
    } catch (error) {
      // Keep reset errors indistinguishable so callers cannot enumerate users.
      if (_disposed || _generation != generation) return false;
      if (error is AuthFailure &&
          error.code == AuthFailureCode.invalidCredentials) {
        return true;
      }
      if (_disposed) return false;
      _setError(const AuthFailure(AuthFailureCode.serviceUnavailable));
      return false;
    } finally {
      _passwordResetInProgress = false;
    }
  }

  Future<bool> signOut() async {
    if (_disposed ||
        _status == SessionStatus.signingOut ||
        _nativeSignOutInProgress) {
      return false;
    }

    final previousUid = _user?.uid ?? _currentUid;
    final generation = _beginCommand(SessionStatus.signingOut);
    if (previousUid != null) _suppressedUids.add(previousUid);

    if (!_authentication.isConfigured) {
      _setUnavailable(const AuthFailure(AuthFailureCode.configuration));
      _endCommand(generation);
      return false;
    }

    try {
      _suppressNextSignOutNullEvent = true;
      await _authentication.signOut();
      if (!_isCurrent(generation)) return false;
      _setStatus(SessionStatus.signedOut, error: null);
      return true;
    } catch (_) {
      if (!_isCurrent(generation)) return false;
      _suppressNextSignOutNullEvent = true;
      if (previousUid != null) _suppressedUids.add(previousUid);
      _setUnavailable(const AuthFailure(AuthFailureCode.signOutFailed));
      return false;
    } finally {
      _endCommand(generation);
    }
  }

  /// Revalidates only the identity currently held by the authentication SDK.
  Future<void> refresh() async {
    if (_disposed || _status != SessionStatus.authenticated || _user == null) {
      return;
    }

    final identity = _user!;
    final generation = ++_generation;
    _validatingUid = identity.uid;
    _validatingGeneration = generation;
    _setChecking();
    try {
      final snapshot = await Future.any<_SessionSnapshot?>([
        _loadAuthorizedSession(identity, generation: generation),
        _disposedCompleter.future.then<_SessionSnapshot?>((_) => null),
      ]);
      if (snapshot == null || !_isCurrent(generation)) return;
      _setAuthenticated(snapshot);
    } catch (error) {
      if (!_isCurrent(generation)) return;
      await _rejectIdentity(
        identity.uid,
        generation,
        _failure(error, AuthFailureCode.serviceUnavailable),
      );
    } finally {
      if (_validatingGeneration == generation) {
        _validatingUid = null;
        _validatingGeneration = null;
      }
    }
  }

  void clearError() {
    if (_disposed || _error == null || requiresSignOut) return;
    _error = null;
    _notify();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _authentication.removeListener(_onAuthenticationLifecycleChanged);
    ++_generation;
    _disposedCompleter.complete();
    _completeInitialization();
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(_cancelSubscription(subscription));
    super.dispose();
  }

  bool get _isCommandInProgress =>
      _status == SessionStatus.signingIn ||
      _status == SessionStatus.signingOut ||
      _observerSuppressedBy != null ||
      _nativeSignOutInProgress ||
      _authentication.busy;

  String? get _currentUid {
    try {
      return _authentication.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  int _beginCommand(SessionStatus status) {
    final generation = ++_generation;
    _observerSuppressedBy = generation;
    _validatingUid = null;
    _validatingGeneration = null;
    _clearSession();
    _error = null;
    _status = status;
    _notify();
    return generation;
  }

  void _endCommand(int generation) {
    if (_observerSuppressedBy != generation) return;
    _observerSuppressedBy = null;
    if (_hasObservedInitialState) _completeInitialization();
  }

  bool _isCurrent(int generation) => !_disposed && _generation == generation;

  void _onAuthStateChanged(AuthUser? observedUser) {
    if (_disposed) return;
    final isInitial = !_hasObservedInitialState;
    _hasObservedInitialState = true;

    if (requiresSignOut) {
      _setUnavailable(const AuthFailure(AuthFailureCode.signOutFailed));
      _completeInitialization();
      return;
    }

    if (observedUser == null && _suppressNextSignOutNullEvent) {
      _suppressNextSignOutNullEvent = false;
      if (isInitial) _completeInitialization();
      return;
    }
    if (observedUser != null &&
        !_suppressedUids.contains(observedUser.uid) &&
        _observerSuppressedBy == null &&
        !_authentication.busy) {
      _suppressNextSignOutNullEvent = false;
    }

    if (_observerSuppressedBy != null || _authentication.busy) {
      return;
    }

    final processing = _handleObservedUser(observedUser);
    unawaited(_completeAfter(processing));
  }

  Future<bool> _handleObservedUser(AuthUser? observedUser) async {
    if (_disposed) return false;

    if (observedUser == null) {
      if (_status == SessionStatus.signedOut && _error == null) return true;
      ++_generation;
      _validatingUid = null;
      _validatingGeneration = null;
      _clearSession();
      _setStatus(SessionStatus.signedOut, error: null);
      return true;
    }

    if (_suppressedUids.contains(observedUser.uid)) {
      if (_status == SessionStatus.checking && _user == null) {
        _setUnavailable(
          _error ?? const AuthFailure(AuthFailureCode.invalidResponse),
        );
      }
      return true;
    }
    if (_status == SessionStatus.authenticated &&
        _user?.uid == observedUser.uid) {
      return true;
    }
    if (_validatingUid == observedUser.uid) return false;

    final generation = ++_generation;
    _validatingUid = observedUser.uid;
    _validatingGeneration = generation;
    _setChecking();
    try {
      final snapshot = await Future.any<_SessionSnapshot?>([
        _loadAuthorizedSession(observedUser, generation: generation),
        _disposedCompleter.future.then<_SessionSnapshot?>((_) => null),
      ]);
      if (snapshot == null || !_isCurrent(generation)) return false;
      _suppressedUids.remove(observedUser.uid);
      _setAuthenticated(snapshot);
      return true;
    } catch (error) {
      if (!_isCurrent(generation)) return false;
      await _rejectIdentity(
        observedUser.uid,
        generation,
        _failure(error, AuthFailureCode.serviceUnavailable),
      );
      return true;
    } finally {
      if (_validatingGeneration == generation) {
        _validatingUid = null;
        _validatingGeneration = null;
      }
    }
  }

  Future<_SessionSnapshot?> _loadAuthorizedSession(
    AuthUser observedIdentity, {
    required int generation,
  }) async {
    if (!_authentication.isConfigured || !_accounts.isConfigured) {
      throw const AuthFailure(AuthFailureCode.configuration);
    }

    final refreshed = await _authentication.reloadUser();
    if (!_isCurrent(generation)) return null;
    if (refreshed == null ||
        refreshed.uid.isEmpty ||
        refreshed.uid != observedIdentity.uid ||
        refreshed.email.trim().isEmpty) {
      throw const AuthFailure(AuthFailureCode.invalidResponse);
    }
    if (_currentUid != refreshed.uid) {
      throw const AuthFailure(AuthFailureCode.invalidResponse);
    }
    if (!refreshed.emailVerified) {
      throw const AuthFailure(AuthFailureCode.emailNotVerified);
    }

    final account = await _accounts.currentAccount();
    if (!_isCurrent(generation)) return null;
    if (_currentUid != refreshed.uid) {
      throw const AuthFailure(AuthFailureCode.invalidResponse);
    }
    if (!account.matchesEmail(refreshed.email)) {
      throw const AuthFailure(AuthFailureCode.accountUnavailable);
    }

    // The backend evaluates verification and time-based blocks. A historical
    // TemporarilyBlocked status can be returned after expiry; both protected
    // endpoints must succeed, rather than duplicating server policy locally.
    final ranches = await _accounts.ranchAccess();
    if (!_isCurrent(generation)) return null;
    if (_currentUid != refreshed.uid) {
      throw const AuthFailure(AuthFailureCode.invalidResponse);
    }

    return _SessionSnapshot(
      user: refreshed,
      account: account,
      ranches: List<RanchAccess>.unmodifiable(ranches),
    );
  }

  Future<void> _rejectIdentity(
    String uid,
    int generation,
    AuthFailure failure,
  ) async {
    if (!_isCurrent(generation)) return;

    _suppressedUids.add(uid);
    final ownsObserverSuppression = _observerSuppressedBy == null;
    if (ownsObserverSuppression) _observerSuppressedBy = generation;
    _suppressNextSignOutNullEvent = true;
    _setUnavailable(failure);
    try {
      if (!_authentication.isConfigured ||
          !_isCurrent(generation) ||
          _currentUid != uid) {
        return;
      }
      _nativeSignOutInProgress = true;
      await _authentication.signOut();
    } catch (_) {
      // Rejection remains fail-closed if best-effort SDK sign-out fails.
    } finally {
      _nativeSignOutInProgress = false;
      if (ownsObserverSuppression && _observerSuppressedBy == generation) {
        _observerSuppressedBy = null;
      }
    }
  }

  void _onAuthenticationLifecycleChanged() {
    if (_disposed) return;
    final failure = _authentication.cleanupFailure;
    if (failure != null && !_authentication.busy) {
      _setUnavailable(failure);
      _completeInitialization();
    } else if (!_authentication.busy &&
        _observerSuppressedBy == null &&
        _hasObservedInitialState) {
      _onAuthStateChanged(_authentication.currentUser);
    } else {
      _notify();
    }
  }

  void _onAuthStateError(Object error, StackTrace stackTrace) {
    if (_disposed) return;
    _hasObservedInitialState = true;
    if (_observerSuppressedBy == null) _handleObserverFailure(error);
    _completeInitialization();
  }

  void _onAuthStateDone() {
    if (_disposed) return;
    _hasObservedInitialState = true;
    if (_observerSuppressedBy == null) {
      _handleObserverFailure(
        const AuthFailure(AuthFailureCode.serviceUnavailable),
      );
    }
    _completeInitialization();
  }

  void _handleObserverFailure(Object error) {
    final uid = _user?.uid ?? _currentUid;
    if (uid != null) _suppressedUids.add(uid);
    ++_generation;
    _validatingUid = null;
    _validatingGeneration = null;
    _setUnavailable(_failure(error, AuthFailureCode.network));
  }

  Future<void> _completeAfter(Future<bool> processing) async {
    try {
      if (await processing) _completeInitialization();
    } catch (_) {
      // Observer work must never escape through the stream listener.
    }
  }

  void _completeInitialization() {
    final completer = _initializationCompleter;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  Future<void> _cancelSubscription(
    StreamSubscription<AuthUser?> subscription,
  ) async {
    try {
      await subscription.cancel();
    } catch (_) {
      // Cancellation during disposal is best-effort.
    }
  }

  void _setAuthenticated(_SessionSnapshot snapshot) {
    _status = SessionStatus.authenticated;
    _error = null;
    _suppressNextSignOutNullEvent = false;
    _user = snapshot.user;
    _account = snapshot.account;
    _ranches = snapshot.ranches;
    _notify();
  }

  void _setChecking() {
    _status = SessionStatus.checking;
    _error = null;
    _clearSession();
    _notify();
  }

  void _setUnavailable(AuthFailure failure) {
    _clearSession();
    _setStatus(SessionStatus.unavailable, error: failure);
  }

  void _setStatus(SessionStatus status, {required AuthFailure? error}) {
    _status = status;
    _error = error;
    _notify();
  }

  void _setError(AuthFailure? error) {
    _error = error;
    _notify();
  }

  void _clearSession() {
    _user = null;
    _account = null;
    _ranches = const <RanchAccess>[];
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  AuthFailure _failure(Object error, AuthFailureCode fallback) =>
      error is AuthFailure ? error : AuthFailure(fallback);
}

final class _SessionSnapshot {
  const _SessionSnapshot({
    required this.user,
    required this.account,
    required this.ranches,
  });

  final AuthUser user;
  final IamAccount account;
  final List<RanchAccess> ranches;
}
