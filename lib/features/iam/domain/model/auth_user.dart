/// Firebase identity as understood by IAM, without SDK or token fields.
final class AuthUser {
  const AuthUser({
    required this.uid,
    required this.email,
    required this.emailVerified,
    this.displayName,
  });

  final String uid;
  final String email;
  final bool emailVerified;
  final String? displayName;
}
