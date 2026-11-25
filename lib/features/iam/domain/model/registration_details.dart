import 'iam_account.dart';

/// Registration roles and ranch details accepted by the backend use case.
final class RegistrationDetails {
  const RegistrationDetails({required this.role, this.ranch});

  final AccountRole role;
  final RanchRegistration? ranch;

  bool get isValid => switch (role) {
    AccountRole.veterinarian => true,
    AccountRole.ranchManager => ranch?.isValid ?? false,
    AccountRole.fieldOperator => false,
  };
}

final class RanchRegistration {
  const RanchRegistration({
    required this.name,
    required this.region,
    required this.district,
    required this.estimatedHeadCount,
  });

  final String name;
  final String region;
  final String district;
  final int estimatedHeadCount;

  bool get isValid =>
      name.trim().isNotEmpty &&
      name.trim().length <= 160 &&
      region.trim().isNotEmpty &&
      region.trim().length <= 120 &&
      district.trim().isNotEmpty &&
      district.trim().length <= 120 &&
      estimatedHeadCount >= 0 &&
      // The request binds to a .NET Int32; this is a transport bound, not a
      // locally invented herd-size business limit.
      estimatedHeadCount <= 2147483647;
}
