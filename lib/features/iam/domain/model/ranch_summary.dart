/// Public ranch details returned after an authenticated veterinarian lookup.
final class RanchSummary {
  const RanchSummary({
    required this.ranchId,
    required this.name,
    required this.region,
    required this.district,
  });

  final String ranchId;
  final String name;
  final String region;
  final String district;
}
