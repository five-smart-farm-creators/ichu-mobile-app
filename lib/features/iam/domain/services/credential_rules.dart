/// Input bounds shared by sign-in and recovery. Passwords are never normalized.
abstract final class CredentialRules {
  static bool validEmail(String value) {
    final email = value.trim();
    return email.length <= 120 &&
        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
  }

  static bool validPassword(String value) =>
      value.length >= 8 && value.length <= 128;
}
