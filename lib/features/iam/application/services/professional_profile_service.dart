import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/model/auth_failure.dart';
import '../../domain/model/auth_user.dart';
import '../../domain/model/iam_account.dart';
import '../../domain/model/professional_profile.dart';
import '../../domain/repositories/professional_profile_repository.dart';
import 'auth_service.dart';

enum ProfessionalProfileStatus { idle, loading, ready, unavailable }

/// Coordinates explicit reads of the authenticated account's profile.
final class ProfessionalProfileService extends ChangeNotifier {
  ProfessionalProfileService({
    required this._session,
    required this._profiles,
  }) {
    _session.addListener(_onSessionChanged);
    _synchronizeSession(notify: false);
  }

  final AuthService _session;
  final ProfessionalProfileRepository _profiles;

  ProfessionalProfileStatus _status = ProfessionalProfileStatus.idle;
  AuthFailure? _error;
  IamAccount? _account;
  ProfessionalProfile? _profile;
  _SessionScope? _observedScope;
  _SessionScope? _dataScope;
  _LoadOperation? _loadOperation;
  bool _disposed = false;
  int _generation = 0;

  ProfessionalProfileStatus get status => _status;

  bool get busy => _status == ProfessionalProfileStatus.loading;

  bool get canView {
    final scope = _visibleSessionScope;
    return scope != null && _dataScope == scope && _account != null;
  }

  bool get canReload =>
      !_disposed && _visibleSessionScope != null && _profiles.isConfigured;

  IamAccount? get account => canView ? _account : null;

  ProfessionalProfile? get profile => canView ? _profile : null;

  AuthFailure? get error => _visibleSessionScope == null ? null : _error;

  /// Explicitly fetches the current authenticated account's server profile.
  Future<bool> load() {
    if (_disposed) return Future<bool>.value(false);
    _synchronizeSession();

    final scope = _visibleSessionScope;
    if (scope == null) return Future<bool>.value(false);

    final currentLoad = _loadOperation;
    if (currentLoad != null &&
        currentLoad.generation == _generation &&
        currentLoad.scope == scope) {
      return currentLoad.completer.future;
    }

    // Do not show an earlier snapshot while a refresh is in progress.
    _clearData();
    _error = null;
    if (!_profiles.isConfigured) {
      _status = ProfessionalProfileStatus.unavailable;
      _error = const AuthFailure(AuthFailureCode.configuration);
      _notify();
      return Future<bool>.value(false);
    }

    final operation = _LoadOperation(scope: scope, generation: _generation);
    _loadOperation = operation;
    _status = ProfessionalProfileStatus.loading;
    _notify();
    unawaited(_runLoad(operation));
    return operation.completer.future;
  }

  void clearError() {
    if (_disposed) return;
    _synchronizeSession();
    if (_error == null) return;
    _error = null;
    _notify();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _session.removeListener(_onSessionChanged);
    _generation++;
    _loadOperation = null;
    _clearData();
    _error = null;
    _observedScope = null;
    _status = ProfessionalProfileStatus.idle;
    super.dispose();
  }

  Future<void> _runLoad(_LoadOperation operation) async {
    var succeeded = false;
    try {
      if (!_isCurrent(operation.scope, operation.generation)) return;
      if (!_profiles.isConfigured) {
        _handleLoadFailure(
          operation,
          const AuthFailure(AuthFailureCode.configuration),
        );
        return;
      }

      final response = await _profiles.currentAccount();
      if (!_isCurrent(operation.scope, operation.generation)) return;
      if (response.id != operation.scope.accountId ||
          !response.matchesEmail(operation.scope.email) ||
          (response.profile != null && !response.profile!.isValid)) {
        _handleLoadFailure(
          operation,
          const AuthFailure(AuthFailureCode.invalidResponse),
        );
        return;
      }

      _account = response;
      _profile = response.profile;
      _dataScope = operation.scope;
      _status = ProfessionalProfileStatus.ready;
      _error = null;
      _notify();
      succeeded = true;
    } catch (error) {
      if (!_isCurrent(operation.scope, operation.generation)) return;
      _handleLoadFailure(operation, _asFailure(error));
    } finally {
      if (identical(_loadOperation, operation)) _loadOperation = null;
      if (!operation.completer.isCompleted) {
        operation.completer.complete(succeeded);
      }
    }
  }

  void _handleLoadFailure(_LoadOperation operation, AuthFailure failure) {
    if (!_isCurrent(operation.scope, operation.generation)) return;
    _clearData();
    _status = ProfessionalProfileStatus.unavailable;
    _error = failure;
    _notify();
  }

  void _onSessionChanged() {
    if (!_disposed) _synchronizeSession();
  }

  void _synchronizeSession({bool notify = true}) {
    final next = _readSessionScope();
    final previous = _observedScope;

    if (next == null) {
      if (previous != null || _hasSessionData) {
        _invalidateSession();
        if (notify) _notify();
      }
      _observedScope = null;
      return;
    }

    if ((previous != null && previous != next) ||
        (_dataScope != null && _dataScope != next)) {
      _invalidateSession();
      _observedScope = next;
      if (notify) _notify();
      return;
    }

    final scopeWasUnknown = previous == null;
    _observedScope = next;
    if (scopeWasUnknown && notify) _notify();
  }

  void _invalidateSession() {
    _generation++;
    _loadOperation = null;
    _clearData();
    _error = null;
    _status = ProfessionalProfileStatus.idle;
  }

  bool get _hasSessionData =>
      _account != null ||
      _profile != null ||
      _error != null ||
      _loadOperation != null ||
      _status != ProfessionalProfileStatus.idle;

  void _clearData() {
    _account = null;
    _profile = null;
    _dataScope = null;
  }

  _SessionScope? get _visibleSessionScope {
    final scope = _readSessionScope();
    if (scope == null || scope != _observedScope) return null;
    return scope;
  }

  _SessionScope? _readSessionScope() {
    if (_session.status != SessionStatus.authenticated) return null;
    final AuthUser? user = _session.user;
    final account = _session.account;
    if (user == null ||
        account == null ||
        !user.emailVerified ||
        user.uid.trim().isEmpty ||
        user.uid != user.uid.trim() ||
        user.email.trim().isEmpty ||
        account.id.trim().isEmpty ||
        account.id != account.id.trim() ||
        !account.matchesEmail(user.email)) {
      return null;
    }
    return _SessionScope(
      uid: user.uid,
      accountId: account.id,
      email: user.email.trim().toLowerCase(),
      role: account.role,
    );
  }

  bool _isCurrent(_SessionScope scope, int generation) {
    if (_disposed || generation != _generation) return false;
    _synchronizeSession();
    return generation == _generation &&
        _readSessionScope() == scope &&
        _observedScope == scope;
  }

  AuthFailure _asFailure(Object error) => error is AuthFailure
      ? error
      : const AuthFailure(AuthFailureCode.serviceUnavailable);

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

final class _SessionScope {
  const _SessionScope({
    required this.uid,
    required this.accountId,
    required this.email,
    required this.role,
  });

  final String uid;
  final String accountId;
  final String email;
  final AccountRole role;

  @override
  bool operator ==(Object other) =>
      other is _SessionScope &&
      uid == other.uid &&
      accountId == other.accountId &&
      email == other.email &&
      role == other.role;

  @override
  int get hashCode => Object.hash(uid, accountId, email, role);
}

final class _LoadOperation {
  _LoadOperation({required this.scope, required this.generation});

  final _SessionScope scope;
  final int generation;
  final Completer<bool> completer = Completer<bool>();
}
