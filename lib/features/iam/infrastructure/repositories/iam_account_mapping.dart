import '../../domain/model/auth_failure.dart';
import '../../domain/model/iam_account.dart';
import '../../domain/model/professional_profile.dart';

/// Maps account resources shared by current-account, registration, and profile flows.
abstract final class IamAccountMapping {
  static IamAccount accountFromPayload(Object? payload) {
    final dto = objectFromPayload(payload);
    final id = requiredString(dto, 'id');
    if (!isUuid(id)) _invalidResponse();

    final role = switch (requiredString(dto, 'role')) {
      'RanchManager' => AccountRole.ranchManager,
      'Veterinarian' => AccountRole.veterinarian,
      'FieldOperator' => AccountRole.fieldOperator,
      _ => _invalidResponse(),
    };
    final profile = optionalProfileFromPayload(dto);

    return IamAccount(
      id: id,
      email: requiredString(dto, 'email'),
      role: role,
      status: requiredString(dto, 'status'),
      profile: profile,
    );
  }

  static ProfessionalProfile? optionalProfileFromPayload(
    Map<String, dynamic> account,
  ) {
    final value = account['profile'];
    if (value == null) return null;

    final dto = objectFromPayload(value);
    final yearsOfExperience = dto['yearsOfExperience'];
    if (yearsOfExperience is! int ||
        yearsOfExperience < 0 ||
        yearsOfExperience > 2147483647) {
      _invalidResponse();
    }

    final profile = ProfessionalProfile(
      specialty: requiredString(dto, 'specialty'),
      licenseNumber: requiredString(dto, 'licenseNumber'),
      yearsOfExperience: yearsOfExperience,
    ).normalized();
    if (!profile.isValid) _invalidResponse();
    return profile;
  }

  static Map<String, dynamic> objectFromPayload(Object? value) {
    if (value is! Map<String, dynamic>) _invalidResponse();
    return value;
  }

  static String requiredString(Map<String, dynamic> dto, String key) {
    final value = dto[key];
    if (value is! String || value.trim().isEmpty) _invalidResponse();
    return value;
  }

  static bool isUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);

  static Never _invalidResponse() =>
      throw const AuthFailure(AuthFailureCode.invalidResponse);
}
