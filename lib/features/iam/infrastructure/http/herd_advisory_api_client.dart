import '../../application/facades/authorized_ranch_session.dart';
import '../../domain/model/auth_failure.dart';
import '../http/authenticated_api_client.dart';

/// Sends veterinarian advisory requests and authorized ranch advisory calls.
final class HerdAdvisoryApiClient {
  const HerdAdvisoryApiClient({
    required AuthenticatedApiClient? api,
    required AuthorizedRanchSession session,
  }) : _api = api,
       _session = session;

  final AuthenticatedApiClient? _api;
  final AuthorizedRanchSession _session;

  bool get isConfigured =>
      (_api?.isConfigured ?? false) && _session.isConfigured;

  Future<Object?> findRanchByAccessCode(String accessCode) =>
      _requireApi().getJson(
        'ranches',
        queryParameters: <String, String>{'accessCode': accessCode},
      );

  Future<Object?> requestAccess({
    required String ranchId,
    required String reason,
  }) => _requireApi().postJson(
    'ranches/$ranchId/herd-advisories',
    <String, Object?>{'reason': reason},
  );

  Future<Object?> advisoriesForRanch(String ranchId) {
    final context = _requireContext(ranchId);
    return _requireApi().getJson(
      'ranches/$ranchId/herd-advisories',
      tokenProvider: () => _tokenFor(context),
      isContextCurrent: () => _session.isCurrent(context),
    );
  }

  Future<Object?> decide({
    required String ranchId,
    required String advisoryId,
    required String decision,
    String? scope,
    DateTime? expiresAt,
  }) {
    final context = _requireContext(ranchId);
    return _requireApi().patchJson(
      'ranches/$ranchId/herd-advisories/$advisoryId',
      <String, Object?>{
        'decision': decision,
        if (scope != null) 'scope': scope,
        if (expiresAt != null) 'expiresAt': expiresAt.toUtc().toIso8601String(),
      },
      tokenProvider: () => _tokenFor(context),
      isContextCurrent: () => _session.isCurrent(context),
    );
  }

  Future<Object?> grantDirectly({
    required String ranchId,
    required String veterinarianId,
    required String scope,
    required DateTime expiresAt,
  }) {
    final context = _requireContext(ranchId);
    return _requireApi().postJson(
      'ranches/$ranchId/herd-advisories/grants',
      <String, Object?>{
        'veterinarianId': veterinarianId,
        'scope': scope,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
      },
      tokenProvider: () => _tokenFor(context),
      isContextCurrent: () => _session.isCurrent(context),
    );
  }

  AuthenticatedApiClient _requireApi() {
    final api = _api;
    if (api == null) {
      throw const AuthFailure(AuthFailureCode.configuration);
    }
    return api;
  }

  AuthorizedRanchContext _requireContext(String ranchId) {
    if (!_isNonzeroUuid(ranchId)) {
      throw const AuthFailure(AuthFailureCode.accountUnavailable);
    }
    final context = _session.context;
    if (!_session.isConfigured ||
        context == null ||
        !_sameUuid(context.ranchId, ranchId) ||
        !_session.isCurrent(context)) {
      throw const AuthFailure(AuthFailureCode.accountUnavailable);
    }
    return context;
  }

  Future<String> _tokenFor(AuthorizedRanchContext context) async {
    try {
      return await _session.idTokenFor(context);
    } on RanchSessionFailure catch (failure) {
      throw AuthFailure(switch (failure.code) {
        RanchSessionFailureCode.configuration => AuthFailureCode.configuration,
        RanchSessionFailureCode.unavailable =>
          AuthFailureCode.accountUnavailable,
        RanchSessionFailureCode.network => AuthFailureCode.network,
        RanchSessionFailureCode.serviceUnavailable =>
          AuthFailureCode.serviceUnavailable,
      });
    }
  }

  bool _isNonzeroUuid(String value) =>
      RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(value) &&
      value.replaceAll('-', '').replaceAll('0', '').isNotEmpty;

  bool _sameUuid(String left, String right) =>
      _isNonzeroUuid(right) && left.toLowerCase() == right.toLowerCase();
}
