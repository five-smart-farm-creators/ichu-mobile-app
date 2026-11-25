import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/model/auth_failure.dart';
import '../../domain/model/auth_user.dart';
import '../../domain/model/iam_account.dart';
import '../../domain/model/ranch_access.dart';
import '../../domain/repositories/authentication_repository.dart';
import '../services/auth_service.dart';
import '../services/ranch_selection_service.dart';

/// Minimal application-facing description of the currently selected ranch.
final class AuthorizedRanchContext {
  const AuthorizedRanchContext._({
    required this.accountId,
    required this.ranchId,
    required this.ranchName,
    required this.canManage,
  });

  /// Stable server account identifier for account-scoped local data.
  final String accountId;
  final String ranchId;
  final String ranchName;

  /// Server-issued grant hint for showing actions; the server still authorizes each request.
  final bool canManage;
}

enum RanchSessionFailureCode {
  configuration,
  unavailable,
  network,
  serviceUnavailable,
}

/// A stable failure category that never includes SDK-provided details.
final class RanchSessionFailure implements Exception {
  const RanchSessionFailure(this.code);

  final RanchSessionFailureCode code;

  @override
  String toString() => 'RanchSessionFailure(${code.name})';
}

/// Explicit IAM application boundary for consumers operating on one ranch.
final class AuthorizedRanchSession extends ChangeNotifier {
  AuthorizedRanchSession({
    required this._session,
    required this._selection,
    required this._authentication,
  }) {
    _session.addListener(_onChanged);
    _selection.addListener(_onChanged);
    _signature = _currentSignature;
    _grant = _currentGrant;
    if (_signature != null && _grant != null) _installContext(notify: false);
  }

  final AuthService _session;
  final RanchSelectionService _selection;
  final AuthenticationRepository _authentication;
  _PrincipalSignature? _signature;
  RanchAccess? _grant;
  AuthorizedRanchContext? _context;
  bool _disposed = false;

  /// Current context, provided that the live SDK identity still matches.
  AuthorizedRanchContext? get context {
    if (_disposed || _context == null || !_isLive(_signature, _grant)) {
      return null;
    }
    return _context;
  }

  bool get isConfigured =>
      !_disposed && _session.canSignIn && _authentication.isConfigured;

  /// Whether [candidate] is this exact live session and selection instance.
  bool isCurrent(AuthorizedRanchContext candidate) =>
      identical(context, candidate);

  /// Fetches a fresh SDK token for this context; tokens are never cached.
  Future<String> idTokenFor(AuthorizedRanchContext candidate) async {
    final active = context;
    if (!isConfigured) {
      throw const RanchSessionFailure(RanchSessionFailureCode.configuration);
    }
    if (active == null || !identical(active, candidate)) {
      throw const RanchSessionFailure(RanchSessionFailureCode.unavailable);
    }

    final beforeUid = _liveUid;
    if (beforeUid == null || !_isLive(_signature, _grant)) {
      throw const RanchSessionFailure(RanchSessionFailureCode.unavailable);
    }

    late final String token;
    try {
      token = await _authentication.idToken().timeout(
        const Duration(seconds: 15),
      );
    } on TimeoutException {
      throw const RanchSessionFailure(RanchSessionFailureCode.network);
    } catch (error) {
      throw _mapFailure(error);
    }

    if (_disposed ||
        !identical(_context, candidate) ||
        !_isLive(_signature, _grant) ||
        _liveUid != beforeUid) {
      throw const RanchSessionFailure(RanchSessionFailureCode.unavailable);
    }
    if (token.trim().isEmpty || token.contains(RegExp(r'\s'))) {
      throw const RanchSessionFailure(RanchSessionFailureCode.unavailable);
    }
    return token;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _session.removeListener(_onChanged);
    _selection.removeListener(_onChanged);
    _signature = null;
    _grant = null;
    _context = null;
    super.dispose();
  }

  String? get _liveUid {
    try {
      final uid = _authentication.currentUser?.uid;
      return uid == null || uid.trim().isEmpty || uid != uid.trim()
          ? null
          : uid;
    } catch (_) {
      return null;
    }
  }

  _PrincipalSignature? get _currentSignature {
    if (_disposed ||
        _session.status != SessionStatus.authenticated ||
        !_session.canSignIn) {
      return null;
    }
    final AuthUser? user = _session.user;
    final IamAccount? account = _session.account;
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
    return _PrincipalSignature(
      uid: user.uid,
      accountId: account.id,
      email: user.email.trim().toLowerCase(),
      role: account.role,
    );
  }

  RanchAccess? get _currentGrant {
    final signature = _currentSignature;
    if (signature == null || _liveUid != signature.uid) return null;
    try {
      final identity = _authentication.currentUser;
      if (identity == null ||
          !identity.emailVerified ||
          identity.email.trim().toLowerCase() != signature.email) {
        return null;
      }
    } catch (_) {
      return null;
    }
    final selected = _selection.selectedRanch;
    if (selected == null ||
        !_session.ranches.any((ranch) => identical(ranch, selected))) {
      return null;
    }
    return selected;
  }

  bool _isLive(_PrincipalSignature? signature, RanchAccess? grant) {
    if (_disposed ||
        signature == null ||
        grant == null ||
        _currentSignature != signature ||
        _liveUid != signature.uid ||
        !identical(_currentGrant, grant)) {
      return false;
    }
    return true;
  }

  void _onChanged() {
    if (_disposed) return;
    final nextSignature = _currentSignature;
    final nextGrant = nextSignature == null ? null : _currentGrant;
    if (nextSignature == _signature && identical(nextGrant, _grant)) {
      if (_context == null && nextSignature != null && nextGrant != null) {
        _installContext(notify: true);
      }
      return;
    }

    final hadContext = _context != null;
    _signature = nextSignature;
    _grant = nextGrant;
    _context = null;
    if (nextSignature != null && nextGrant != null) {
      _installContext(notify: false);
    }
    if (hadContext || _context != null) notifyListeners();
  }

  void _installContext({required bool notify}) {
    final grant = _grant;
    if (grant == null) return;
    _context = AuthorizedRanchContext._(
      accountId: _signature!.accountId,
      ranchId: grant.ranchId,
      ranchName: grant.name,
      canManage: grant.scope == AccessScope.manage,
    );
    if (notify && !_disposed) notifyListeners();
  }

  RanchSessionFailure _mapFailure(Object error) {
    if (error is AuthFailure) {
      return RanchSessionFailure(switch (error.code) {
        AuthFailureCode.configuration => RanchSessionFailureCode.configuration,
        AuthFailureCode.network => RanchSessionFailureCode.network,
        AuthFailureCode.serviceUnavailable =>
          RanchSessionFailureCode.serviceUnavailable,
        _ => RanchSessionFailureCode.unavailable,
      });
    }
    return const RanchSessionFailure(
      RanchSessionFailureCode.serviceUnavailable,
    );
  }
}

final class _PrincipalSignature {
  const _PrincipalSignature({
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
      other is _PrincipalSignature &&
      uid == other.uid &&
      accountId == other.accountId &&
      email == other.email &&
      role == other.role;

  @override
  int get hashCode => Object.hash(uid, accountId, email, role);
}
