/// Input bounds shared by sign-in and recovery. Passwords are never normalized.
abstract final class CredentialRules {
  static bool validEmail(String value) {
    final email = value.trim();
    return email.length <= 254 &&
        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
  }

  static bool validPassword(String value) =>
      value.trim().isNotEmpty && value.length >= 8 && value.length <= 128;

  // Existing Firebase identities must not be rejected by a new-account rule.
  static bool validSignInPassword(String value) =>
      value.trim().isNotEmpty && value.length <= 128;
}
