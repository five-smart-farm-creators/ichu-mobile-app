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

    final seenRanchIds = <String>{};
    return List<RanchAccess>.unmodifiable(
      payload.map((item) {
        final dto = IamAccountMapping.objectFromPayload(item);
        final ranchId = IamAccountMapping.requiredString(dto, 'ranchId');
        if (!IamAccountMapping.isUuid(ranchId) ||
            !seenRanchIds.add(ranchId.toLowerCase())) {
          _invalidResponse();
        }

        final scope = switch (IamAccountMapping.requiredString(dto, 'scope')) {
          'Read' => AccessScope.read,
          'ClinicalWrite' => AccessScope.clinicalWrite,
          'Manage' => AccessScope.manage,
          _ => _invalidResponse(),
        };

        final name = _ranchText(dto, 'name', 160);
        final region = _ranchText(dto, 'region', 120);
        final district = _ranchText(dto, 'district', 120);
        final expiresAt = _optionalDateTime(dto, 'expiresAt');
        return RanchAccess(
          ranchId: ranchId,
          scope: scope,
          name: name,
          region: region,
          district: district,
          expiresAt: expiresAt,
        );
      }),
    );
  }

  AuthenticatedApiClient _requireApi() {
    final api = _api;
    if (api == null) {
      throw const AuthFailure(AuthFailureCode.configuration);
    }
    return api;
  }

  String _ranchText(Map<String, dynamic> dto, String key, int maxLength) {
    final value = IamAccountMapping.requiredString(dto, key).trim();
    if (value.length > maxLength) _invalidResponse();
    return value;
  }

  DateTime? _optionalDateTime(Map<String, dynamic> dto, String key) {
    final value = dto[key];
    if (value == null) return null;
    if (value is! String) _invalidResponse();
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,7})?(?:Z|[+-](\d{2}):(\d{2}))$',
    ).firstMatch(value);
    if (match == null) {
      _invalidResponse();
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final second = int.parse(match.group(6)!);
    final offsetHour = int.parse(match.group(7) ?? '0');
    final offsetMinute = int.parse(match.group(8) ?? '0');
    if (year == 0 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > DateTime.utc(year, month + 1, 0).day ||
        hour > 23 ||
        minute > 59 ||
        second > 59 ||
        offsetHour > 14 ||
        offsetMinute > 59 ||
        (offsetHour == 14 && offsetMinute != 0)) {
      _invalidResponse();
    }
    final date = DateTime.tryParse(value);
    if (date == null) _invalidResponse();
    return date;
  }

  Never _invalidResponse() =>
      throw const AuthFailure(AuthFailureCode.invalidResponse);
}
