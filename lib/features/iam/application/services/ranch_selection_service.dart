import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/model/auth_user.dart';
import '../../domain/model/iam_account.dart';
import '../../domain/model/ranch_access.dart';
import 'auth_service.dart';

/// Coordinates selection from the ranches in the validated auth snapshot.
///
/// Selection is only a client-side context; protected operations must still be
/// authorized by the server for the selected ranch.
final class RanchSelectionService extends ChangeNotifier {
  RanchSelectionService({required this._session, DateTime Function()? now})
    : _now = now ?? DateTime.now {
    _session.addListener(_onSessionChanged);
    _synchronizeSession(notify: false);
  }

  final AuthService _session;
  final DateTime Function() _now;

  _SessionScope? _observedScope;
  List<RanchAccess>? _observedRanches;
  RanchAccess? _selectedRanch;
  _SessionScope? _selectionScope;
  List<RanchAccess>? _selectionRanches;
  Timer? _expiryTimer;
  bool _disposed = false;

  /// Whether the current session may inspect its authorized ranch snapshot.
  bool get canSelect => !_disposed && _visibleSnapshot != null;

  /// Current server-authorized ranches, excluding locally expired grants.
  List<RanchAccess> get ranches {
    final snapshot = _visibleSnapshot;
    if (_disposed || snapshot == null) return const <RanchAccess>[];
    return List<RanchAccess>.unmodifiable(_availableRanches(snapshot.ranches));
  }

  /// The canonical selected grant, if it remains in the current valid snapshot.
  RanchAccess? get selectedRanch {
    final snapshot = _visibleSnapshot;
    final selected = _selectedRanch;
    if (_disposed ||
        snapshot == null ||
        selected == null ||
        _selectionScope != snapshot.scope ||
        !identical(_selectionRanches, snapshot.ranches)) {
      return null;
    }
    final matches = _availableRanches(snapshot.ranches)
        .where((ranch) => ranch.ranchId == selected.ranchId)
        .toList(growable: false);
    return matches.length == 1 && identical(matches.single, selected)
        ? selected
        : null;
  }

  /// Selects a ranch by ID, retaining the grant object from the auth snapshot.
  bool select(String ranchId) {
    if (_disposed) return false;
    _synchronizeSession();
    final snapshot = _visibleSnapshot;
    if (snapshot == null || ranchId.trim().isEmpty) return false;

    final allMatches = snapshot.ranches
        .where((ranch) => ranch.ranchId == ranchId)
        .toList(growable: false);
    if (allMatches.length != 1) return false;
    final candidate = allMatches.single;
    if (!_availableRanches(snapshot.ranches).contains(candidate)) return false;

    _selectedRanch = candidate;
    _selectionScope = snapshot.scope;
    _selectionRanches = snapshot.ranches;
    _notify();
    return true;
  }

  void clearSelection() {
    if (_disposed || _selectedRanch == null) return;
    _clearSelectedRanch();
    _notify();
  }

  /// Explicitly revalidates the session using AuthService's existing flow.
  Future<void> refresh() async {
    if (_disposed) return;
    _synchronizeSession();
    if (_visibleScope == null ||
        _session.status != SessionStatus.authenticated) {
      return;
    }
    await _session.refresh();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _session.removeListener(_onSessionChanged);
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _clearSelectedRanch();
    _observedScope = null;
    _observedRanches = null;
    super.dispose();
  }

  _SessionScope? get _visibleScope {
    if (_disposed || _session.status != SessionStatus.authenticated) {
      return null;
    }
    final user = _session.user;
    final account = _session.account;
    if (user == null || account == null || !_isValidSession(user, account)) {
      return null;
    }
    return _SessionScope(
      uid: user.uid,
      accountId: account.id,
      email: user.email.trim().toLowerCase(),
      role: account.role,
    );
  }

  _SessionSnapshot? get _visibleSnapshot {
    final scope = _visibleScope;
    final ranches = _session.ranches;
    if (scope == null ||
        !_session.canSignIn ||
        scope != _observedScope ||
        !identical(ranches, _observedRanches)) {
      return null;
    }
    return _SessionSnapshot(scope: scope, ranches: ranches);
  }

  void _onSessionChanged() {
    if (!_disposed) _synchronizeSession();
  }

  void _synchronizeSession({bool notify = true}) {
    if (_disposed) return;
    final scope = _visibleScope;
    final ranches = scope == null || !_session.canSignIn
        ? null
        : _session.ranches;
    final previousScope = _observedScope;
    final previousRanches = _observedRanches;
    final sameSnapshot =
        scope != null &&
        scope == previousScope &&
        ranches != null &&
        identical(ranches, previousRanches);

    if (sameSnapshot) return;

    final changed =
        scope != previousScope ||
        !identical(ranches, previousRanches) ||
        _selectedRanch != null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _clearSelectedRanch();
    _observedScope = scope;
    _observedRanches = ranches;
    if (ranches != null) _scheduleExpiry(ranches);

    if (notify && changed) _notify();
  }

  void _scheduleExpiry(List<RanchAccess> ranches) {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    final now = _now().toUtc();
    DateTime? nearestExpiry;
    for (final ranch in ranches) {
      final expiry = ranch.expiresAt?.toUtc();
      if (expiry != null &&
          expiry.isAfter(now) &&
          (nearestExpiry == null || expiry.isBefore(nearestExpiry))) {
        nearestExpiry = expiry;
      }
    }
    if (nearestExpiry == null) return;
    _expiryTimer = Timer(nearestExpiry.difference(now), () {
      _expiryTimer = null;
      if (_disposed) return;
      final selected = _selectedRanch;
      final currentRanches = _observedRanches;
      if (selected != null &&
          currentRanches != null &&
          !_availableRanches(
            currentRanches,
          ).any((ranch) => identical(ranch, selected))) {
        _clearSelectedRanch();
      }
      if (currentRanches != null) _scheduleExpiry(currentRanches);
      _notify();
    });
  }

  List<RanchAccess> _availableRanches(List<RanchAccess> ranches) {
    final now = _now().toUtc();
    final counts = <String, int>{};
    for (final ranch in ranches) {
      final id = ranch.ranchId.toLowerCase();
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return ranches
        .where(
          (ranch) =>
              ranch.ranchId.trim().isNotEmpty &&
              counts[ranch.ranchId.toLowerCase()] == 1 &&
              (ranch.expiresAt?.toUtc().isAfter(now) ?? true),
        )
        .toList(growable: false);
  }

  bool _isValidSession(AuthUser? user, IamAccount? account) =>
      user != null &&
      account != null &&
      user.emailVerified &&
      user.uid.isNotEmpty &&
      user.uid == user.uid.trim() &&
      user.email.trim().isNotEmpty &&
      account.id.trim().isNotEmpty &&
      account.id == account.id.trim() &&
      account.matchesEmail(user.email);

  void _clearSelectedRanch() {
    _selectedRanch = null;
    _selectionScope = null;
    _selectionRanches = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

final class _SessionSnapshot {
  const _SessionSnapshot({required this.scope, required this.ranches});

  final _SessionScope scope;
  final List<RanchAccess> ranches;
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
