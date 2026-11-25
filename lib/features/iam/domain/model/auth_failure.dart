/// Stable, non-sensitive categories. Presentation supplies localized wording.
enum AuthFailureCode {
  configuration,
  invalidCredentials,
  registrationRejected,
  accountAlreadyExists,
  emailNotVerified,
  accountUnavailable,
  forbidden,
  network,
  serviceUnavailable,
  invalidResponse,
  signOutFailed,
  unknown,
}

final class AuthFailure implements Exception {
  const AuthFailure(this.code);

  final AuthFailureCode code;

  @override
  String toString() => 'AuthFailure(${code.name})';
}
