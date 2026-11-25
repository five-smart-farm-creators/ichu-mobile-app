import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

import '../../domain/model/auth_failure.dart';
import '../../domain/model/auth_user.dart';
import '../../domain/repositories/authentication_repository.dart';
import '../configuration/firebase_client_config.dart';
import '../configuration/firebase_client_initializer.dart';
import 'firebase_identity_mapping.dart';

final class FirebaseAuthRepository implements AuthenticationRepository {
  FirebaseAuthRepository({required this._auth});

  static const _appName = 'ichu-iam-mobile';

  final firebase_auth.FirebaseAuth? _auth;

  /// Initializes only this IAM named app, reusing it only when its options
  /// exactly match the supplied configuration.
  static Future<FirebaseAuthRepository> initialize(
    FirebaseClientConfig config,
  ) async {
    final auth = await FirebaseClientInitializer.initialize(
      config,
      name: _appName,
    );
    return FirebaseAuthRepository(auth: auth);
  }

  @override
  bool get isConfigured => _auth != null;

  @override
  AuthUser? get currentUser {
    try {
      final user = _auth?.currentUser;
      return FirebaseIdentityMapping.mapUserOrNull(user);
    } on Object catch (error) {
      throw FirebaseIdentityMapping.mapFailure(error);
    }
  }

  @override
  Stream<AuthUser?> observeAuthState() {
    final auth = _auth;
    if (auth == null) {
      return Stream<AuthUser?>.error(
        const AuthFailure(AuthFailureCode.configuration),
      );
    }

    try {
      return auth.authStateChanges().transform(
        StreamTransformer<firebase_auth.User?, AuthUser?>.fromHandlers(
          handleData: (user, sink) =>
              sink.add(FirebaseIdentityMapping.mapUserOrNull(user)),
          handleError: (error, stackTrace, sink) => sink.addError(
            FirebaseIdentityMapping.mapFailure(error),
            stackTrace,
          ),
        ),
      );
    } on Object catch (error) {
      return Stream<AuthUser?>.error(FirebaseIdentityMapping.mapFailure(error));
    }
  }

  @override
  Future<AuthUser> signIn(String email, String password) {
    return _run((auth) async {
      final credential = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const AuthFailure(AuthFailureCode.invalidResponse);
      }
      return FirebaseIdentityMapping.mapUser(user);
    });
  }

  @override
  Future<AuthUser?> reloadUser() {
    return _run((auth) async {
      final user = auth.currentUser;
      if (user == null) return null;

      await user.reload();
      final refreshedUser = auth.currentUser;
      if (refreshedUser == null) return null;

      await refreshedUser.getIdToken(true);
      return FirebaseIdentityMapping.mapUser(refreshedUser);
    });
  }

  @override
  Future<String> idToken({bool forceRefresh = false}) {
    return _run((auth) async {
      final user = auth.currentUser;
      if (user == null) {
        throw const AuthFailure(AuthFailureCode.accountUnavailable);
      }

      final token = await user.getIdToken(forceRefresh);
      if (token == null || token.isEmpty) {
        throw const AuthFailure(AuthFailureCode.accountUnavailable);
      }
      return token;
    });
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    final auth = _auth;
    if (auth == null) {
      throw const AuthFailure(AuthFailureCode.configuration);
    }

    try {
      await auth.sendPasswordResetEmail(email: email);
    } on firebase_auth.FirebaseAuthException catch (error) {
      if (FirebaseIdentityMapping.normalizedCode(error) == 'user-not-found') {
        return;
      }
      throw FirebaseIdentityMapping.mapFailure(error);
    } on Object catch (error) {
      throw FirebaseIdentityMapping.mapFailure(error);
    }
  }

  @override
  Future<void> signOut() {
    return _run(
      (auth) => auth.signOut(),
      fallback: AuthFailureCode.signOutFailed,
    );
  }

  Future<T> _run<T>(
    Future<T> Function(firebase_auth.FirebaseAuth auth) operation, {
    AuthFailureCode fallback = AuthFailureCode.unknown,
  }) async {
    final auth = _auth;
    if (auth == null) {
      throw const AuthFailure(AuthFailureCode.configuration);
    }

    try {
      return await operation(auth);
    } on AuthFailure {
      rethrow;
    } on Object catch (error) {
      throw FirebaseIdentityMapping.mapFailure(error, fallback: fallback);
    }
  }
}
