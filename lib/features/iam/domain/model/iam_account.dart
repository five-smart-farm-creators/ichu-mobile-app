import 'professional_profile.dart';

enum AccountRole { ranchManager, veterinarian, fieldOperator }

/// The application's account is distinct from its external identity.
final class IamAccount {
  const IamAccount({
    required this.id,
    required this.email,
    required this.role,
    required this.status,
    this.profile,
  });

  final String id;
  final String email;
  final AccountRole role;
  final ProfessionalProfile? profile;

  /// Stored server label, not an authorization decision or a local lock timer.
  final String status;

  bool matchesEmail(String identityEmail) =>
      email.trim().toLowerCase() == identityEmail.trim().toLowerCase();
}
