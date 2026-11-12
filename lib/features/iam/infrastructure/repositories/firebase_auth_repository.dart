import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_core/firebase_core.dart';

import '../../domain/model/auth_failure.dart';
import '../../domain/model/auth_user.dart';
import '../../domain/repositories/authentication_repository.dart';
import '../configuration/firebase_client_config.dart';

final class FirebaseAuthRepository implements AuthenticationRepository {
  FirebaseAuthRepository({required this._auth});

  static const _appName = 'ichu-iam-mobile';

  final firebase_auth.FirebaseAuth? _auth;

  /// Initializes only this IAM named app, reusing it only when its options
  /// exactly match the supplied configuration.
  static Future<FirebaseAuthRepository> initialize(
    FirebaseClientConfig config,
  ) async {
    final options = config.options;
    if (options == null) {
      return FirebaseAuthRepository(auth: null);
    }

    try {
      FirebaseApp? existingApp;
      for (final candidate in Firebase.apps) {
        if (candidate.name == _appName) {
          existingApp = candidate;
          break;
        }
      }

      late final FirebaseApp app;
      if (existingApp != null) {
        if (existingApp.options != options) {
          return FirebaseAuthRepository(auth: null);
        }
        app = existingApp;
      } else {
        app = await Firebase.initializeApp(name: _appName, options: options);
      }

      return FirebaseAuthRepository(
        auth: firebase_auth.FirebaseAuth.instanceFor(app: app),
      );
    } on Object {
      // Initialization failures are intentionally not exposed or logged.
      return FirebaseAuthRepository(auth: null);
    }
  }

  @override
  bool get isConfigured => _auth != null;

  @override
  AuthUser? get currentUser {
    try {
      final user = _auth?.currentUser;
      return user == null ? null : _mapUser(user);
    } on Object catch (error) {
      throw _mapFailure(error);
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
          handleData: (user, sink) => sink.add(_mapUserOrNull(user)),
          handleError: (error, stackTrace, sink) =>
              sink.addError(_mapFailure(error), stackTrace),
        ),
      );
    } on Object catch (error) {
      return Stream<AuthUser?>.error(_mapFailure(error));
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
      return _mapUser(user);
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
      return _mapUser(refreshedUser);
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
      if (_normalizedCode(error) == 'user-not-found') return;
      throw _mapFailure(error);
    } on Object catch (error) {
      throw _mapFailure(error);
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
      throw _mapFailure(error, fallback: fallback);
    }
  }

  static AuthUser? _mapUserOrNull(firebase_auth.User? user) =>
      user == null ? null : _mapUser(user);

  static AuthUser _mapUser(firebase_auth.User user) {
    return AuthUser(
      uid: user.uid,
      email: user.email ?? '',
      emailVerified: user.emailVerified,
      displayName: user.displayName,
    );
  }

  static AuthFailure _mapFailure(
    Object error, {
    AuthFailureCode fallback = AuthFailureCode.unknown,
  }) {
    if (error is AuthFailure) return error;
    if (error is! firebase_auth.FirebaseAuthException) {
      return AuthFailure(fallback);
    }

    final code = _normalizedCode(error);
    final failureCode = switch (code) {
      'invalid-credential' ||
      'invalid-login-credentials' ||
      'invalid-email' ||
      'user-not-found' ||
      'wrong-password' => AuthFailureCode.invalidCredentials,
      'user-disabled' => AuthFailureCode.accountUnavailable,
      'network-request-failed' => AuthFailureCode.network,
      'too-many-requests' => AuthFailureCode.serviceUnavailable,
      'invalid-api-key' ||
      'api-key-not-valid' ||
      'app-not-authorized' ||
      'invalid-app-id' ||
      'project-not-found' ||
      'operation-not-allowed' ||
      'configuration-not-found' ||
      'missing-ios-bundle-id' => AuthFailureCode.configuration,
      _ => fallback,
    };

    return AuthFailure(failureCode);
  }

  static String _normalizedCode(firebase_auth.FirebaseAuthException error) {
    final parts = error.code.toLowerCase().split('/');
    return parts.last;
  }
}
