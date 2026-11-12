enum AccessScope { read, clinicalWrite, manage }

/// A server-issued access snapshot; the server still authorizes each operation.
final class RanchAccess {
  const RanchAccess({
    required this.ranchId,
    required this.scope,
    required this.name,
    required this.region,
    required this.district,
    this.expiresAt,
  });

  final String ranchId;
  final AccessScope scope;
  final String name;
  final String region;
  final String district;
  final DateTime? expiresAt;
}
