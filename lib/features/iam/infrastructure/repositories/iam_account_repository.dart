import '../../domain/model/auth_failure.dart';
import '../../domain/model/iam_account.dart';
import '../../domain/model/ranch_access.dart';
import '../../domain/repositories/account_repository.dart';
import '../http/authenticated_api_client.dart';

/// Maps authenticated account API responses into IAM domain models.
final class IamAccountRepository implements AccountRepository {
  const IamAccountRepository({required this._api});

  final AuthenticatedApiClient? _api;

  @override
  bool get isConfigured => _api != null;

  @override
  Future<IamAccount> currentAccount() async {
    final payload = await _requireApi().getJson('accounts/me');
    final dto = _asObject(payload);

    final id = _requiredString(dto, 'id');
    if (!_isUuid(id)) _invalidResponse();
    final email = _requiredString(dto, 'email');
    final status = _requiredString(dto, 'status');
    final role = switch (_requiredString(dto, 'role')) {
      'RanchManager' => AccountRole.ranchManager,
      'Veterinarian' => AccountRole.veterinarian,
      'FieldOperator' => AccountRole.fieldOperator,
      _ => _invalidResponse(),
    };

    return IamAccount(id: id, email: email, role: role, status: status);
  }

  @override
  Future<List<RanchAccess>> ranchAccess() async {
    final payload = await _requireApi().getJson('accounts/me/ranches');
    if (payload is! List<Object?>) _invalidResponse();

    return payload
        .map((item) {
          final dto = _asObject(item);
          final ranchId = _requiredString(dto, 'ranchId');
          if (!_isUuid(ranchId)) _invalidResponse();

          final scope = switch (_requiredString(dto, 'scope')) {
            'Read' => AccessScope.read,
            'ClinicalWrite' => AccessScope.clinicalWrite,
            'Manage' => AccessScope.manage,
            _ => _invalidResponse(),
          };

          final name = _optionalString(dto, 'name');
          final expiresAt = _optionalDateTime(dto, 'expiresAt');
          return RanchAccess(
            ranchId: ranchId,
            scope: scope,
            name: name,
            expiresAt: expiresAt,
          );
        })
        .toList(growable: false);
  }

  AuthenticatedApiClient _requireApi() {
    final api = _api;
    if (api == null) {
      throw const AuthFailure(AuthFailureCode.configuration);
    }
    return api;
  }

  Map<String, dynamic> _asObject(Object? value) {
    if (value is! Map<String, dynamic>) _invalidResponse();
    return value;
  }

  String _requiredString(Map<String, dynamic> dto, String key) {
    final value = dto[key];
    if (value is! String || value.trim().isEmpty) _invalidResponse();
    return value;
  }

  String? _optionalString(Map<String, dynamic> dto, String key) {
    final value = dto[key];
    if (value == null) return null;
    if (value is! String) _invalidResponse();
    return value;
  }

  DateTime? _optionalDateTime(Map<String, dynamic> dto, String key) {
    final value = dto[key];
    if (value == null) return null;
    if (value is! String) _invalidResponse();
    if (!RegExp(
      r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:\d{2})$',
    ).hasMatch(value)) {
      _invalidResponse();
    }
    final date = DateTime.tryParse(value);
    if (date == null) _invalidResponse();
    return date;
  }

  bool _isUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);

  Never _invalidResponse() =>
      throw const AuthFailure(AuthFailureCode.invalidResponse);
}
