import '../../domain/model/account_registration_result.dart';
import '../../domain/model/auth_failure.dart';
import '../../domain/model/iam_account.dart';
import '../../domain/model/registration_details.dart';
import '../../domain/repositories/account_registration_repository.dart';
import '../http/authenticated_api_client.dart';
import 'iam_account_mapping.dart';

/// Registers an account with the backend using the current Firebase identity.
final class IamAccountRegistrationRepository
    implements AccountRegistrationRepository {
  const IamAccountRegistrationRepository({required this._api});

  final AuthenticatedApiClient? _api;

  @override
  bool get isConfigured => _api != null;

  @override
  Future<AccountRegistrationResult> registerAccount({
    required String email,
    required RegistrationDetails details,
  }) async {
    final body = _registrationBody(details);
    final expectedEmail = _normalizedEmail(email);
    final payload = await _requireApi().postAccountRegistration(body);
    final wrapper = IamAccountMapping.objectFromPayload(payload);
    if (!wrapper.containsKey('ranchId')) _invalidResponse();

    final account = IamAccountMapping.accountFromPayload(wrapper['account']);
    if (account.role != details.role ||
        account.status != 'PendingVerification' ||
        account.email.trim().toLowerCase() != expectedEmail) {
      _invalidResponse();
    }

    final ranchIdValue = wrapper['ranchId'];
    final String? ranchId;
    if (details.role == AccountRole.ranchManager) {
      if (ranchIdValue is! String || !IamAccountMapping.isUuid(ranchIdValue)) {
        _invalidResponse();
      }
      ranchId = ranchIdValue;
    } else {
      if (ranchIdValue != null) _invalidResponse();
      ranchId = null;
    }

    return AccountRegistrationResult(account: account, ranchId: ranchId);
  }

  @override
  Future<IamAccount> currentAccount() async {
    final payload = await _requireApi().getJson('accounts/me');
    return IamAccountMapping.accountFromPayload(payload);
  }

  Map<String, Object?> _registrationBody(RegistrationDetails details) {
    if (!details.isValid) {
      throw const AuthFailure(AuthFailureCode.registrationRejected);
    }

    return switch (details.role) {
      AccountRole.veterinarian => const <String, Object?>{
        'role': 'Veterinarian',
      },
      AccountRole.ranchManager => _managerBody(details.ranch!),
      AccountRole.fieldOperator => throw const AuthFailure(
        AuthFailureCode.registrationRejected,
      ),
    };
  }

  Map<String, Object?> _managerBody(RanchRegistration ranch) =>
      <String, Object?>{
        'role': 'RanchManager',
        'ranchName': ranch.name.trim(),
        'region': ranch.region.trim(),
        'district': ranch.district.trim(),
        'estimatedHeadCount': ranch.estimatedHeadCount,
      };

  String _normalizedEmail(String email) {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty || normalized.length > 254) _invalidResponse();
    return normalized;
  }

  AuthenticatedApiClient _requireApi() {
    final api = _api;
    if (api == null) {
      throw const AuthFailure(AuthFailureCode.configuration);
    }
    return api;
  }

  Never _invalidResponse() =>
      throw const AuthFailure(AuthFailureCode.invalidResponse);
}
