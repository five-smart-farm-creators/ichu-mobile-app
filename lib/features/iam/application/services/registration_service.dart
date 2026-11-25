import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/model/auth_failure.dart';
import '../../domain/model/auth_user.dart';
import '../../domain/model/iam_account.dart';
import '../../domain/model/registration_details.dart';
import '../../domain/repositories/account_registration_repository.dart';
import 'authentication_lifecycle.dart';

enum RegistrationStatus {
  initializing,
  idle,
  creating,
  awaitingVerification,
  completing,
  completed,
  cancelling,
  unavailable,
}

/// Coordinates isolated identity onboarding and backend account registration.
/// It never creates an authenticated workspace session.
final class RegistrationService extends ChangeNotifier {
  RegistrationService({
    required this._authentication,
    required this._accounts,
  }) {
    _authentication.addListener(_onAuthenticationChanged);
  }

  final AuthenticationLifecycle _authentication;
  final AccountRegistrationRepository _accounts;
  RegistrationStatus _status = RegistrationStatus.initializing;
  AuthFailure? _error;
  AuthUser? _user;
  IamAccount? _account;
  StreamSubscription<AuthUser?>? _subscription;
  Future<void>? _initializationFuture;
  Completer<void>? _initializationCompleter;
  int _generation = 0;
  int? _observerSuppressedBy;
  bool _hasObservedInitialState = false;
  bool _operationInProgress = false;
  bool _verificationSent = false;
  bool _signOutFailed = false;
  final Set<String> _uncertainRegistrationUids = <String>{};
  String? _lastRegistrationUid;
  bool _disposed = false;

  RegistrationStatus get status => _status;

  bool get busy =>
      _status == RegistrationStatus.initializing ||
      _status == RegistrationStatus.creating ||
      _status == RegistrationStatus.completing ||
      _status == RegistrationStatus.cancelling ||
      _operationInProgress ||
      _authentication.busy;

  bool get canRegister => _authentication.canRegister && _accounts.isConfigured;

  bool get canResume => _authentication.canRegister;

  AuthFailure? get error => _error;

  AuthUser? get user => _user;

  IamAccount? get account => _account;

  bool get verificationSent => _verificationSent;

  bool get needsReconciliation => _uncertainRegistrationUids.contains(
    _user?.uid ?? _currentUser?.uid ?? _lastRegistrationUid,
  );

  bool get requiresSignOut =>
      _signOutFailed || _authentication.cleanupFailure != null;

  /// Completes after the isolated identity provider's initial state is seen.
  Future<void> initialize() {
    if (_disposed) return Future<void>.value();
    final existing = _initializationFuture;
    if (existing != null) return existing;

    final completer = Completer<void>();
    _initializationFuture = completer.future;
    _initializationCompleter = completer;
    _status = RegistrationStatus.initializing;
    _notify();

    try {
      _subscription = _authentication.observeAuthState().listen(
        _onAuthStateChanged,
        onError: _onAuthStateError,
        onDone: _onAuthStateDone,
      );
    } catch (_) {
      _hasObservedInitialState = true;
      _setUnavailable(const AuthFailure(AuthFailureCode.network));
      completer.complete();
    }

    return completer.future;
  }

  /// Creates an isolated identity and sends its initial verification email.
  /// The backend account is not created until [complete] is explicitly called.
  Future<bool> register(String email, String password) async {
    await initialize();
    if (!_canStartCommand() || !canRegister) {
      _rejectConfigurationIfNeeded(canRegister);
      return false;
    }
    if (_account != null || _user != null || _currentUser != null) {
      _setError(const AuthFailure(AuthFailureCode.accountUnavailable));
      return false;
    }

    final generation = _beginOperation(RegistrationStatus.creating);
    try {
      final createdIdentity = await _authentication.createUser(
        email.trim(),
        password,
      );
      if (!_isCurrent(generation)) return false;
      if (!_isCurrentIdentity(createdIdentity) ||
          !_sameEmail(createdIdentity.email, email.trim())) {
        _setUnavailable(const AuthFailure(AuthFailureCode.invalidResponse));
        return false;
      }

      _user = createdIdentity;
      _status = RegistrationStatus.awaitingVerification;
      _verificationSent = false;
      _error = null;
      _notify();

      try {
        await _authentication.sendEmailVerification();
      } catch (error) {
        if (!_isCurrent(generation)) return false;
        if (requiresSignOut) {
          _setUnavailable(const AuthFailure(AuthFailureCode.signOutFailed));
          return false;
        }
        if (!_isCurrentIdentity(createdIdentity)) {
          _clearIdentity();
          _setUnavailable(
            const AuthFailure(AuthFailureCode.accountUnavailable),
          );
          return false;
        }
        _status = RegistrationStatus.awaitingVerification;
        _error = _safeFailure(error);
        _notify();
        return false;
      }

      if (!_isCurrent(generation)) return false;
      if (!_isCurrentIdentity(createdIdentity)) {
        _clearIdentity();
        _setUnavailable(const AuthFailure(AuthFailureCode.accountUnavailable));
        return false;
      }
      _verificationSent = true;
      _error = null;
      _notify();
      return true;
    } catch (error) {
      if (!_isCurrent(generation)) return false;
      if (requiresSignOut) {
        _setUnavailable(const AuthFailure(AuthFailureCode.signOutFailed));
        return false;
      }
      final currentIdentity = _currentUser;
      if (currentIdentity != null &&
          _sameEmail(currentIdentity.email, email.trim())) {
        _user = currentIdentity;
        _status = RegistrationStatus.awaitingVerification;
      } else if (currentIdentity != null) {
        _clearIdentity();
        _setUnavailable(const AuthFailure(AuthFailureCode.accountUnavailable));
        return false;
      } else {
        _status = RegistrationStatus.idle;
      }
      _error = _safeFailure(error);
      _notify();
      return false;
    } finally {
      _endOperation(generation);
    }
  }

  /// Signs in to an existing isolated identity without automatically resending
  /// verification mail. Verified identities still use the explicit completion
  /// step so the backend request remains user initiated.
  Future<bool> resume(String email, String password) async {
    await initialize();
    if (!_canStartCommand() || !canResume) {
      _rejectConfigurationIfNeeded(canResume);
      return false;
    }
    if (_account != null ||
        (_user != null && !_sameEmail(_user!.email, email))) {
      _setError(const AuthFailure(AuthFailureCode.accountUnavailable));
      return false;
    }

    final generation = _beginOperation(RegistrationStatus.creating);
    try {
      final identity = await _authentication.signIn(email.trim(), password);
      if (!_isCurrent(generation)) return false;
      if (!_isCurrentIdentity(identity) ||
          !_sameEmail(identity.email, email.trim())) {
        _clearIdentity();
        _setUnavailable(const AuthFailure(AuthFailureCode.invalidResponse));
        return false;
      }

      _user = identity;
      _verificationSent = false;
      _status = RegistrationStatus.awaitingVerification;
      _error = null;
      _notify();
      return true;
    } catch (error) {
      if (!_isCurrent(generation)) return false;
      if (requiresSignOut) {
        _setUnavailable(const AuthFailure(AuthFailureCode.signOutFailed));
        return false;
      }
      final currentIdentity = _currentUser;
      if (currentIdentity != null &&
          !_sameEmail(currentIdentity.email, email.trim())) {
        _clearIdentity();
        _setUnavailable(const AuthFailure(AuthFailureCode.accountUnavailable));
        return false;
      }
      if (currentIdentity != null) _user = currentIdentity;
      if (currentIdentity == null) _clearIdentity();
      _status = _user == null
          ? RegistrationStatus.idle
          : RegistrationStatus.awaitingVerification;
      _error = _safeFailure(error);
      _notify();
      return false;
    } finally {
      _endOperation(generation);
    }
  }

  /// Explicitly sends another verification email for the current identity.
  Future<bool> resendVerification() async {
    await initialize();
    if (!_canStartCommand() || !canResume) {
      _rejectConfigurationIfNeeded(canResume);
      return false;
    }
    final identity = _user;
    if (identity == null || !_isCurrentIdentity(identity)) {
      _setError(const AuthFailure(AuthFailureCode.accountUnavailable));
      return false;
    }

    final generation = _beginOperation(RegistrationStatus.awaitingVerification);
    try {
      await _authentication.sendEmailVerification();
      if (!_isCurrent(generation)) return false;
      if (!_isCurrentIdentity(identity)) {
        _clearIdentity();
        _setUnavailable(const AuthFailure(AuthFailureCode.accountUnavailable));
        return false;
      }
      _verificationSent = true;
      _error = null;
      _notify();
      return true;
    } catch (error) {
      if (!_isCurrent(generation)) return false;
      if (requiresSignOut) {
        _setUnavailable(const AuthFailure(AuthFailureCode.signOutFailed));
        return false;
      }
      _status = RegistrationStatus.awaitingVerification;
      _error = _safeFailure(error);
      _notify();
      return false;
    } finally {
      _endOperation(generation);
    }
  }

  /// Refreshes verification before registering the account. Verification is
  /// an intentional UX gate; the backend also permits unverified identities.
  /// The returned account role is authoritative.
  Future<bool> complete(RegistrationDetails details) async {
    await initialize();
    if (!_canStartCommand()) return false;
    if (needsReconciliation) return reconcile();
    if (requiresSignOut || _account != null) {
      _setUnavailable(const AuthFailure(AuthFailureCode.signOutFailed));
      return false;
    }
    if (!details.isValid) {
      _setError(const AuthFailure(AuthFailureCode.registrationRejected));
      return false;
    }
    if (!_authentication.isConfigured || !_accounts.isConfigured) {
      _setUnavailable(const AuthFailure(AuthFailureCode.configuration));
      return false;
    }

    final identity = _user;
    if (identity == null || !_isCurrentIdentity(identity)) {
      _setError(const AuthFailure(AuthFailureCode.accountUnavailable));
      return false;
    }

    final generation = _beginOperation(RegistrationStatus.completing);
    try {
      final refreshed = await _authentication.reloadUser();
      if (!_isCurrent(generation)) return false;
      if (refreshed == null ||
          refreshed.uid.isEmpty ||
          refreshed.uid != identity.uid ||
          refreshed.email.trim().isEmpty ||
          !_sameEmail(refreshed.email, identity.email) ||
          _currentUser?.uid != identity.uid) {
        _restoreAwaiting(
          identity,
          generation,
          const AuthFailure(AuthFailureCode.invalidResponse),
        );
        return false;
      }

      _user = refreshed;
      if (!refreshed.emailVerified) {
        _status = RegistrationStatus.awaitingVerification;
        _error = const AuthFailure(AuthFailureCode.emailNotVerified);
        _notify();
        return false;
      }
      if (!_accounts.isConfigured) {
        _restoreAwaiting(
          refreshed,
          generation,
          const AuthFailure(AuthFailureCode.configuration),
        );
        return false;
      }

      // A failed response can have an unknown outcome. Mark it before sending
      // so subsequent creation submits cannot replay a non-idempotent POST.
      _uncertainRegistrationUids.add(refreshed.uid);
      _lastRegistrationUid = refreshed.uid;
      _notify();
      final registrationResult = await _accounts.registerAccount(
        email: refreshed.email,
        details: details,
      );
      if (!_isCurrent(generation)) return false;
      if (_currentUser?.uid != refreshed.uid) {
        _restoreAwaiting(
          refreshed,
          generation,
          const AuthFailure(AuthFailureCode.accountUnavailable),
        );
        return false;
      }
      final registeredAccount = registrationResult.account;
      if (registeredAccount.id.trim().isEmpty ||
          !registeredAccount.matchesEmail(refreshed.email)) {
        _restoreAwaiting(
          refreshed,
          generation,
          const AuthFailure(AuthFailureCode.invalidResponse),
        );
        return false;
      }

      // Record the backend fact before sign-out, preventing a duplicate POST
      // if the isolated identity provider requires cleanup retry.
      return await _finishKnownAccount(registeredAccount, generation);
    } catch (error) {
      if (!_isCurrent(generation)) return false;
      if (error is AuthFailure &&
          error.code == AuthFailureCode.registrationRejected) {
        _uncertainRegistrationUids.remove(identity.uid);
      }
      _restoreAwaiting(identity, generation, _safeFailure(error));
      return false;
    } finally {
      _endOperation(generation);
    }
  }

  /// Explicitly checks whether a previous uncertain creation already exists.
  /// This performs only the safe current-account GET, never another POST.
  Future<bool> reconcile() async {
    await initialize();
    if (!_canStartCommand() || !needsReconciliation) return false;
    if (requiresSignOut || _account != null) {
      _setUnavailable(const AuthFailure(AuthFailureCode.signOutFailed));
      return false;
    }
    if (!_authentication.isConfigured || !_accounts.isConfigured) {
      _setUnavailable(const AuthFailure(AuthFailureCode.configuration));
      return false;
    }

    final identity = _user;
    if (identity == null || !_isCurrentIdentity(identity)) {
      _setError(const AuthFailure(AuthFailureCode.accountUnavailable));
      return false;
    }

    final generation = _beginOperation(RegistrationStatus.completing);
    try {
      final refreshed = await _authentication.reloadUser();
      if (!_isCurrent(generation)) return false;
      if (refreshed == null ||
          refreshed.uid.isEmpty ||
          refreshed.uid != identity.uid ||
          refreshed.email.trim().isEmpty ||
          !_sameEmail(refreshed.email, identity.email) ||
          _currentUser?.uid != identity.uid) {
        _restoreAwaiting(
          identity,
          generation,
          const AuthFailure(AuthFailureCode.invalidResponse),
        );
        return false;
      }
      _user = refreshed;
      if (!refreshed.emailVerified) {
        _status = RegistrationStatus.awaitingVerification;
        _error = const AuthFailure(AuthFailureCode.emailNotVerified);
        _notify();
        return false;
      }

      final registeredAccount = await _accounts.currentAccount();
      if (!_isCurrent(generation)) return false;
      if (_currentUser?.uid != refreshed.uid) {
        _restoreAwaiting(
          refreshed,
          generation,
          const AuthFailure(AuthFailureCode.accountUnavailable),
        );
        return false;
      }
      if (registeredAccount.id.trim().isEmpty ||
          !registeredAccount.matchesEmail(refreshed.email)) {
        _restoreAwaiting(
          refreshed,
          generation,
          const AuthFailure(AuthFailureCode.invalidResponse),
        );
        return false;
      }

      return await _finishKnownAccount(registeredAccount, generation);
    } catch (error) {
      if (!_isCurrent(generation)) return false;
      _restoreAwaiting(identity, generation, _safeFailure(error));
      return false;
    } finally {
      _endOperation(generation);
    }
  }

  /// Cancels onboarding and signs out only the isolated registration identity.
  /// If the backend already created the account, cleanup preserves that fact.
  Future<bool> cancel() async {
    if (_disposed || _status == RegistrationStatus.cancelling) return false;
    _lastRegistrationUid =
        _user?.uid ?? _currentUser?.uid ?? _lastRegistrationUid;
    final hadAccount = _account != null;
    final generation = ++_generation;
    _observerSuppressedBy = generation;
    _operationInProgress = true;
    _status = RegistrationStatus.cancelling;
    _error = null;
    _notify();

    try {
      if (_currentUser != null || _authentication.busy || requiresSignOut) {
        await _authentication.signOut();
        if (!_isCurrent(generation)) return false;
        if (_currentUser != null) {
          throw const AuthFailure(AuthFailureCode.signOutFailed);
        }
      }

      _signOutFailed = false;
      _user = null;
      _verificationSent = false;
      _error = null;
      _status = hadAccount
          ? RegistrationStatus.completed
          : RegistrationStatus.idle;
      _notify();
      return true;
    } catch (_) {
      if (!_isCurrent(generation)) return false;
      _signOutFailed = true;
      _status = RegistrationStatus.unavailable;
      _error = const AuthFailure(AuthFailureCode.signOutFailed);
      _notify();
      return false;
    } finally {
      if (_observerSuppressedBy == generation) _observerSuppressedBy = null;
      if (_generation == generation) _operationInProgress = false;
      _notify();
    }
  }

  Future<bool> _finishKnownAccount(
    IamAccount registeredAccount,
    int generation,
  ) async {
    if (!_isCurrent(generation)) return false;
    _account = registeredAccount;
    _uncertainRegistrationUids.remove(_user?.uid ?? _currentUser?.uid);
    _notify();
    try {
      await _authentication.signOut();
      if (!_isCurrent(generation)) return false;
      if (_currentUser != null) {
        throw const AuthFailure(AuthFailureCode.signOutFailed);
      }
    } catch (_) {
      if (!_isCurrent(generation)) return false;
      _signOutFailed = true;
      _status = RegistrationStatus.unavailable;
      _error = const AuthFailure(AuthFailureCode.signOutFailed);
      _notify();
      return false;
    }

    _signOutFailed = false;
    _user = null;
    _verificationSent = false;
    _status = RegistrationStatus.completed;
    _error = null;
    _notify();
    return true;
  }

  void clearError() {
    if (_disposed || requiresSignOut || _error == null) return;
    _error = null;
    _notify();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    _observerSuppressedBy = null;
    _operationInProgress = false;
    _authentication.removeListener(_onAuthenticationChanged);
    _completeInitialization();
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(_cancelSubscription(subscription));

    // AuthenticationLifecycle owns native cleanup and remains alive after
    // this service is disposed. Never delete the external identity.
    if (_currentUser != null || _authentication.busy || requiresSignOut) {
      unawaited(_bestEffortSignOut());
    }
    super.dispose();
  }

  Future<void> _bestEffortSignOut() async {
    try {
      await _authentication.signOut();
    } catch (_) {
      // Lifecycle keeps its UID-checked cleanup intent alive after disposal.
    }
  }

  Future<void> _cancelSubscription(
    StreamSubscription<AuthUser?> subscription,
  ) async {
    try {
      await subscription.cancel();
    } catch (_) {
      // Observer teardown is best-effort during service disposal.
    }
  }

  bool _canStartCommand() =>
      !_disposed &&
      !_operationInProgress &&
      _status != RegistrationStatus.unavailable &&
      _status != RegistrationStatus.completed &&
      !_authentication.busy;

  void _rejectConfigurationIfNeeded(bool isConfigured) {
    if (_disposed) return;
    if (!isConfigured) {
      _setUnavailable(const AuthFailure(AuthFailureCode.configuration));
    }
  }

  int _beginOperation(RegistrationStatus status) {
    final generation = ++_generation;
    _observerSuppressedBy = generation;
    _operationInProgress = true;
    _status = status;
    _error = null;
    _notify();
    return generation;
  }

  void _endOperation(int generation) {
    if (_generation != generation) return;
    if (_observerSuppressedBy == generation) _observerSuppressedBy = null;
    _operationInProgress = false;
    _notify();
  }

  bool _isCurrent(int generation) => !_disposed && _generation == generation;

  AuthUser? get _currentUser {
    try {
      return _authentication.currentUser;
    } catch (_) {
      return null;
    }
  }

  bool _isCurrentIdentity(AuthUser identity) =>
      identity.uid.isNotEmpty &&
      identity.email.trim().isNotEmpty &&
      _currentUser?.uid == identity.uid;

  void _onAuthStateChanged(AuthUser? observedUser) {
    if (_disposed) return;
    final isInitial = !_hasObservedInitialState;
    _hasObservedInitialState = true;
    if (isInitial) _completeInitialization();
    if (_observerSuppressedBy != null || _operationInProgress) return;
    if (_status == RegistrationStatus.completed && _account != null) return;

    if (observedUser == null && _currentUser != null) {
      // An SDK event emitted while the lifecycle mutation gate was closed can
      // arrive after the operation returns. Do not discard the current user.
      return;
    }
    if (observedUser == null) {
      if (_status == RegistrationStatus.completed) {
        _notify();
        return;
      }
      if (requiresSignOut) {
        _setUnavailable(const AuthFailure(AuthFailureCode.signOutFailed));
        return;
      }
      _user = null;
      _verificationSent = false;
      _status = RegistrationStatus.idle;
      _error = null;
      _notify();
      return;
    }

    if (!_isCurrentIdentity(observedUser)) return;
    _user = observedUser;
    _verificationSent = false;
    _status = RegistrationStatus.awaitingVerification;
    _error = null;
    _notify();
  }

  void _onAuthStateError(Object error, StackTrace _) {
    if (_disposed) return;
    _hasObservedInitialState = true;
    _setUnavailable(
      error is AuthFailure ? error : const AuthFailure(AuthFailureCode.network),
    );
    _completeInitialization();
  }

  void _onAuthStateDone() {
    if (_disposed) return;
    if (!_hasObservedInitialState) {
      _hasObservedInitialState = true;
      _setUnavailable(const AuthFailure(AuthFailureCode.serviceUnavailable));
    }
    _completeInitialization();
  }

  void _onAuthenticationChanged() {
    if (_disposed) return;
    if (_authentication.cleanupFailure != null) {
      _signOutFailed = true;
      if (_status != RegistrationStatus.cancelling &&
          _status != RegistrationStatus.completing) {
        _setUnavailable(const AuthFailure(AuthFailureCode.signOutFailed));
      } else {
        _notify();
      }
      return;
    }
    _notify();
  }

  void _restoreAwaiting(
    AuthUser identity,
    int generation,
    AuthFailure failure,
  ) {
    if (!_isCurrent(generation)) return;
    if (requiresSignOut) {
      _setUnavailable(const AuthFailure(AuthFailureCode.signOutFailed));
      return;
    }
    if (_currentUser?.uid != identity.uid) {
      _clearIdentity();
      _setUnavailable(const AuthFailure(AuthFailureCode.accountUnavailable));
      return;
    }
    _user = identity;
    _status = RegistrationStatus.awaitingVerification;
    _error = failure;
    _notify();
  }

  void _clearIdentity() {
    _user = null;
    _verificationSent = false;
    _account = null;
  }

  void _setError(AuthFailure failure) {
    _error = failure;
    _notify();
  }

  void _setUnavailable(AuthFailure failure) {
    _status = RegistrationStatus.unavailable;
    _error = failure;
    _notify();
  }

  void _completeInitialization() {
    final completer = _initializationCompleter;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  AuthFailure _safeFailure(Object error) => error is AuthFailure
      ? error
      : const AuthFailure(AuthFailureCode.serviceUnavailable);

  bool _sameEmail(String first, String second) =>
      first.trim().toLowerCase() == second.trim().toLowerCase();

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
