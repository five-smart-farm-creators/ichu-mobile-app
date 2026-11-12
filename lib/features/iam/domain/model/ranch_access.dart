enum AccessScope { read, clinicalWrite, manage }

/// A server-issued access snapshot; the server still authorizes each operation.
final class RanchAccess {
  const RanchAccess({
    required this.ranchId,
    required this.scope,
    this.name,
    this.expiresAt,
  });

  final String ranchId;
  final AccessScope scope;
  final String? name;
  final DateTime? expiresAt;
}
