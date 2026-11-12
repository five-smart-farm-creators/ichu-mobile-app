import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/model/auth_failure.dart';
import '../../domain/model/auth_user.dart';
import '../../domain/repositories/authentication_repository.dart';

/// Owns native mutation/cleanup intent independently of a session service.
/// Share this instance with replacement services and the authenticated client.
final class AuthenticationLifecycle extends ChangeNotifier
    implements AuthenticationRepository {
  AuthenticationLifecycle(this._repository);

  final AuthenticationRepository _repository;
  final Set<String> _suppressedUids = <String>{};
  _NativeSignIn? _pendingSignIn;
  Future<void>? _nativeSignOut;
  AuthFailure? _cleanupFailure;
  bool _disposed = false;

  bool get busy => _pendingSignIn != null || _nativeSignOut != null;
  AuthFailure? get cleanupFailure => _cleanupFailure;

  @override
  bool get isConfigured => _repository.isConfigured;

  bool get _identityHidden =>
      _cleanupFailure != null ||
      _nativeSignOut != null ||
      (_pendingSignIn?.cancelled ?? false);

  @override
  AuthUser? get currentUser => _visibleUser(_repository.currentUser);

  AuthUser? _visibleUser(AuthUser? user) =>
      _identityHidden || _suppressedUids.contains(user?.uid) ? null : user;

  @override
  Stream<AuthUser?> observeAuthState() =>
      _repository.observeAuthState().map(_visibleUser);

  @override
  Future<AuthUser> signIn(String email, String password) async {
    if (_cleanupFailure != null) throw _cleanupFailure!;
    if (busy) throw const AuthFailure(AuthFailureCode.serviceUnavailable);

    final attempt = _NativeSignIn();
    _pendingSignIn = attempt;
    _notify();
    try {
      late final AuthUser user;
      try {
        user = await _repository.signIn(email, password);
      } catch (_) {
        if (attempt.cancelled) {
          await _finishCancelledSignIn(null);
        }
        rethrow;
      }
      if (attempt.cancelled) {
        await _finishCancelledSignIn(user.uid);
        throw const AuthFailure(AuthFailureCode.accountUnavailable);
      }
      _suppressedUids.remove(user.uid);
      return user;
    } finally {
      _pendingSignIn = null;
      _notify();
    }
  }

  @override
  Future<void> signOut() async {
    _pendingSignIn?.cancelled = true;
    try {
      final currentUid = _repository.currentUser?.uid;
      if (currentUid != null) _suppressedUids.add(currentUid);
    } catch (_) {
      // A failing identity getter must not prevent native sign-out.
    }
    await _signOutNative();
  }

  Future<void> _finishCancelledSignIn(String? uid) async {
    if (uid != null) _suppressedUids.add(uid);
    // The initial logout may still be in flight. Never let a later cleanup
    // overlap a new native sign-in or assume an earlier logout cleared it.
    final previousSignOut = _nativeSignOut;
    if (previousSignOut != null) {
      try {
        await previousSignOut;
      } catch (_) {
        // A UID-checked retry below may still clear the late identity.
      }
    }
    final String? currentUid;
    try {
      currentUid = _repository.currentUser?.uid;
    } catch (_) {
      _cleanupFailure = const AuthFailure(AuthFailureCode.signOutFailed);
      throw _cleanupFailure!;
    }
    if (currentUid == null) {
      _cleanupFailure = null;
      return;
    }
    if (uid == null || currentUid != uid) {
      _cleanupFailure = const AuthFailure(AuthFailureCode.signOutFailed);
      throw _cleanupFailure!;
    }
    await _signOutNative();
  }

  Future<void> _signOutNative() {
    final existing = _nativeSignOut;
    if (existing != null) return existing;
    final completion = Completer<void>();
    _nativeSignOut = completion.future;
    _notify();
    unawaited(_completeNativeSignOut(completion));
    return completion.future;
  }

  Future<void> _completeNativeSignOut(Completer<void> completion) async {
    try {
      await _repository.signOut();
      _cleanupFailure = null;
      completion.complete();
    } catch (_) {
      _cleanupFailure = const AuthFailure(AuthFailureCode.signOutFailed);
      completion.completeError(_cleanupFailure!);
    } finally {
      _nativeSignOut = null;
      _notify();
    }
  }

  @override
  Future<AuthUser?> reloadUser() async {
    if (currentUser == null) {
      throw _cleanupFailure ??
          const AuthFailure(AuthFailureCode.accountUnavailable);
    }
    return _repository.reloadUser();
  }

  @override
  Future<String> idToken({bool forceRefresh = false}) async {
    if (currentUser == null) {
      throw _cleanupFailure ??
          const AuthFailure(AuthFailureCode.accountUnavailable);
    }
    return _repository.idToken(forceRefresh: forceRefresh);
  }

  @override
  Future<void> sendPasswordReset(String email) =>
      _repository.sendPasswordReset(email);

  @override
  void dispose() {
    _disposed = true;
    // Native futures retain their cleanup intent even after notifications end.
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

final class _NativeSignIn {
  bool cancelled = false;
}
