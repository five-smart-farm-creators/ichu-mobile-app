/// The authenticated account's professional details, owned by IAM.
final class ProfessionalProfile {
  const ProfessionalProfile({
    required this.specialty,
    required this.licenseNumber,
    required this.yearsOfExperience,
  });

  final String specialty;
  final String licenseNumber;
  final int yearsOfExperience;

  bool get isValid =>
      specialty.trim().isNotEmpty &&
      specialty.trim().length <= 120 &&
      licenseNumber.trim().isNotEmpty &&
      licenseNumber.trim().length <= 80 &&
      yearsOfExperience >= 0 &&
      yearsOfExperience <= 2147483647;

  ProfessionalProfile normalized() => ProfessionalProfile(
    specialty: specialty.trim(),
    licenseNumber: licenseNumber.trim().toUpperCase(),
    yearsOfExperience: yearsOfExperience,
  );

  @override
  bool operator ==(Object other) =>
      other is ProfessionalProfile &&
      specialty == other.specialty &&
      licenseNumber == other.licenseNumber &&
      yearsOfExperience == other.yearsOfExperience;

  @override
  int get hashCode => Object.hash(specialty, licenseNumber, yearsOfExperience);
}
