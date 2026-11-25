import 'professional_profile.dart';
import 'ranch_access.dart';

enum HerdAdvisoryStatus { pending, granted, rejected, revoked, expired }

enum HerdAdvisoryDecision { grant, reject, revoke }

/// A veterinarian's request or time-bounded authorization for one ranch.
final class HerdAdvisory {
  const HerdAdvisory({
    required this.id,
    required this.veterinarianId,
    required this.ranchId,
    required this.reason,
    required this.status,
    required this.scope,
    required this.requestedAt,
    this.grantedAt,
    this.expiresAt,
    this.endedAt,
    this.veterinarianProfile,
  });

  final String id;
  final String veterinarianId;
  final String ranchId;
  final String reason;
  final HerdAdvisoryStatus status;
  final AccessScope scope;
  final DateTime requestedAt;
  final DateTime? grantedAt;
  final DateTime? expiresAt;
  final DateTime? endedAt;
  final ProfessionalProfile? veterinarianProfile;
}
