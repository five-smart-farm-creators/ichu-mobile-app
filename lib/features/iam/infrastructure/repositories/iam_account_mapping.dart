import '../../domain/model/auth_failure.dart';
import '../../domain/model/iam_account.dart';

/// Maps account resources shared by current-account and registration flows.
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

    return IamAccount(
      id: id,
      email: requiredString(dto, 'email'),
      role: role,
      status: requiredString(dto, 'status'),
    );
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
