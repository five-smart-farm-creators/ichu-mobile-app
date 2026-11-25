import '../../domain/model/auth_failure.dart';
import '../../domain/model/herd_advisory.dart';
import '../../domain/model/herd_advisory_failure.dart';
import '../../domain/model/ranch_access.dart';
import '../../domain/model/ranch_summary.dart';
import '../../domain/repositories/herd_advisory_repository.dart';
import '../http/herd_advisory_api_client.dart';
import 'herd_advisory_mapping.dart';

/// REST adapter for veterinarian requests and ranch advisory management.
final class RestHerdAdvisoryRepository implements HerdAdvisoryRepository {
  const RestHerdAdvisoryRepository({required this._api});

  final HerdAdvisoryApiClient? _api;

  @override
  bool get isConfigured => _api?.isConfigured ?? false;

  @override
  Future<RanchSummary> findRanchByAccessCode(String accessCode) async {
    final payload = await _run(
      () => _requireApi().findRanchByAccessCode(accessCode),
    );
    return HerdAdvisoryMapping.ranchFromPayload(payload);
  }

  @override
  Future<HerdAdvisory> requestAccess({
    required String ranchId,
    required String reason,
  }) async {
    final payload = await _run(
      () => _requireApi().requestAccess(ranchId: ranchId, reason: reason),
    );
    return HerdAdvisoryMapping.advisoryFromPayload(payload);
  }

  @override
  Future<List<HerdAdvisory>> advisoriesForRanch(String ranchId) async {
    final payload = await _run(() => _requireApi().advisoriesForRanch(ranchId));
    final advisories = HerdAdvisoryMapping.advisoriesFromPayload(payload);
    if (advisories.any(
      (advisory) => advisory.ranchId.toLowerCase() != ranchId.toLowerCase(),
    )) {
      throw const HerdAdvisoryFailure(HerdAdvisoryFailureCode.invalidResponse);
    }
    return advisories;
  }

  @override
  Future<HerdAdvisory> decide({
    required String ranchId,
    required String advisoryId,
    required HerdAdvisoryDecision decision,
    AccessScope? scope,
    DateTime? expiresAt,
  }) async {
    final payload = await _run(
      () => _requireApi().decide(
        ranchId: ranchId,
        advisoryId: advisoryId,
        decision: switch (decision) {
          HerdAdvisoryDecision.grant => 'grant',
          HerdAdvisoryDecision.reject => 'reject',
          HerdAdvisoryDecision.revoke => 'revoke',
        },
        scope: _scopeName(scope),
        expiresAt: expiresAt,
      ),
    );
    return HerdAdvisoryMapping.advisoryFromPayload(payload);
  }

  @override
  Future<HerdAdvisory> grantDirectly({
    required String ranchId,
    required String veterinarianId,
    required AccessScope scope,
    required DateTime expiresAt,
  }) async {
    final payload = await _run(
      () => _requireApi().grantDirectly(
        ranchId: ranchId,
        veterinarianId: veterinarianId,
        scope: _scopeName(scope)!,
        expiresAt: expiresAt,
      ),
    );
    return HerdAdvisoryMapping.advisoryFromPayload(payload);
  }

  HerdAdvisoryApiClient _requireApi() {
    final api = _api;
    if (api == null) {
      throw const HerdAdvisoryFailure(HerdAdvisoryFailureCode.configuration);
    }
    return api;
  }

  Future<T> _run<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on HerdAdvisoryFailure {
      rethrow;
    } on AuthFailure catch (failure) {
      throw HerdAdvisoryFailure(switch (failure.code) {
        AuthFailureCode.configuration => HerdAdvisoryFailureCode.configuration,
        AuthFailureCode.forbidden => HerdAdvisoryFailureCode.forbidden,
        AuthFailureCode.accountUnavailable =>
          HerdAdvisoryFailureCode.unauthenticated,
        AuthFailureCode.network => HerdAdvisoryFailureCode.network,
        AuthFailureCode.serviceUnavailable =>
          HerdAdvisoryFailureCode.serviceUnavailable,
        AuthFailureCode.invalidResponse =>
          HerdAdvisoryFailureCode.invalidResponse,
        _ => HerdAdvisoryFailureCode.unknown,
      });
    } catch (_) {
      throw const HerdAdvisoryFailure(HerdAdvisoryFailureCode.unknown);
    }
  }

  String? _scopeName(AccessScope? scope) => switch (scope) {
    AccessScope.read => 'Read',
    AccessScope.clinicalWrite => 'ClinicalWrite',
    AccessScope.manage || null => null,
  };
}
