enum AccountRole { ranchManager, veterinarian, fieldOperator }

/// The application's account is distinct from its external identity.
final class IamAccount {
  const IamAccount({
    required this.id,
    required this.email,
    required this.role,
    required this.status,
  });

  final String id;
  final String email;
  final AccountRole role;
  final String status;

  bool get isActive => status.trim().toLowerCase() == 'active';

  bool matchesEmail(String identityEmail) =>
      email.trim().toLowerCase() == identityEmail.trim().toLowerCase();
}
