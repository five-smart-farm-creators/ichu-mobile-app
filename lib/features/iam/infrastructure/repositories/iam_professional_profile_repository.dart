import '../../domain/model/auth_failure.dart';
import '../../domain/model/iam_account.dart';
import '../../domain/repositories/professional_profile_repository.dart';
import '../http/authenticated_api_client.dart';
import 'iam_account_mapping.dart';

/// Maps authenticated current-account profile requests to the IAM API.
final class IamProfessionalProfileRepository
    implements ProfessionalProfileRepository {
  const IamProfessionalProfileRepository({required this._api});

  final AuthenticatedApiClient? _api;

  @override
  bool get isConfigured => _api != null;

  @override
  Future<IamAccount> currentAccount() async {
    final payload = await _requireApi().getJson('profiles/me');
    return IamAccountMapping.accountFromPayload(payload);
  }

  AuthenticatedApiClient _requireApi() {
    final api = _api;
    if (api == null) {
      throw const AuthFailure(AuthFailureCode.configuration);
    }
    return api;
  }
}
