import '../../domain/model/auth_failure.dart';
import '../../domain/model/iam_account.dart';
import '../../domain/model/ranch_access.dart';
import '../../domain/repositories/account_repository.dart';
import '../http/authenticated_api_client.dart';
import 'iam_account_mapping.dart';

/// Maps authenticated account API responses into IAM domain models.
final class IamAccountRepository implements AccountRepository {
  const IamAccountRepository({required this._api});

  final AuthenticatedApiClient? _api;

  @override
  bool get isConfigured => _api != null;

  @override
  Future<IamAccount> currentAccount() async {
    final payload = await _requireApi().getJson('accounts/me');
    return IamAccountMapping.accountFromPayload(payload);
  }

  @override
  Future<List<RanchAccess>> ranchAccess() async {
    final payload = await _requireApi().getJson('accounts/me/ranches');
    if (payload is! List<Object?>) _invalidResponse();

    return payload
        .map((item) {
          final dto = IamAccountMapping.objectFromPayload(item);
          final ranchId = IamAccountMapping.requiredString(dto, 'ranchId');
          if (!IamAccountMapping.isUuid(ranchId)) _invalidResponse();

          final scope = switch (IamAccountMapping.requiredString(
            dto,
            'scope',
          )) {
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

  Never _invalidResponse() =>
      throw const AuthFailure(AuthFailureCode.invalidResponse);
}
