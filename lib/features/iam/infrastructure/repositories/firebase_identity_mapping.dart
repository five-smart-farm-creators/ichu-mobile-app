import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

import '../../domain/model/auth_failure.dart';
import '../../domain/model/auth_user.dart';

abstract final class FirebaseIdentityMapping {
  static AuthUser? mapUserOrNull(firebase_auth.User? user) =>
      user == null ? null : mapUser(user);

  static AuthUser mapUser(firebase_auth.User user) {
    return AuthUser(
      uid: user.uid,
      email: user.email ?? '',
      emailVerified: user.emailVerified,
      displayName: user.displayName,
    );
  }

  static AuthFailure mapFailure(
    Object error, {
    AuthFailureCode fallback = AuthFailureCode.unknown,
  }) {
    if (error is AuthFailure) return error;
    if (error is! firebase_auth.FirebaseAuthException) {
      return AuthFailure(fallback);
    }

    final code = normalizedCode(error);
    final failureCode = switch (code) {
      'invalid-credential' ||
      'invalid-login-credentials' ||
      'invalid-email' ||
      'user-not-found' ||
      'wrong-password' => AuthFailureCode.invalidCredentials,
      'email-already-in-use' ||
      'weak-password' => AuthFailureCode.registrationRejected,
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

  static String normalizedCode(firebase_auth.FirebaseAuthException error) {
    final parts = error.code.toLowerCase().split('/');
    return parts.last;
  }
}
