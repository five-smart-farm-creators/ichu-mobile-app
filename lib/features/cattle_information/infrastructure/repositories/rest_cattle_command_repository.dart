import '../../domain/model/cattle.dart';
import '../../domain/model/cattle_commands.dart';
import '../../domain/model/cattle_failure.dart';
import '../../domain/repositories/cattle_command_repository.dart';
import '../http/cattle_api_client.dart';
import 'cattle_mapping.dart';

/// REST adapter for version-checked animal writes; a response must describe the request.
final class RestCattleCommandRepository implements CattleCommandRepository {
  const RestCattleCommandRepository({required this._api});

  final CattleApiClient? _api;

  @override
  bool get isConfigured => _api?.isConfigured ?? false;

  @override
  Future<Cattle> register(
    String ranchId,
    CattleRegistration registration,
  ) async {
    final payload = await _requireApi().register(ranchId, registration);
    final cattle = CattleMapping.cattleFromPayload(payload, ranchId: ranchId);
    _requireAccepted(
      cattle.earTag == registration.normalizedEarTag &&
          cattle.status == CattleStatus.active,
    );
    return cattle;
  }

  @override
  Future<Cattle> correct(
    String ranchId,
    String cattleId,
    String expectedVersion,
    CattleCorrection correction,
  ) async {
    final payload = await _requireApi().correct(
      ranchId,
      cattleId,
      expectedVersion,
      correction,
    );
    final cattle = CattleMapping.cattleFromPayload(
      payload,
      ranchId: ranchId,
      cattleId: cattleId,
    );
    _requireAccepted(
      cattle.earTag == correction.normalizedEarTag &&
          cattle.status == CattleStatus.active &&
          _isNewVersion(cattle, expectedVersion),
    );
    return cattle;
  }

  @override
  Future<Cattle> changeStage(
    String ranchId,
    String cattleId,
    String expectedVersion,
    CattleStageChange change,
  ) async {
    final payload = await _requireApi().changeStage(
      ranchId,
      cattleId,
      expectedVersion,
      change,
    );
    final cattle = CattleMapping.cattleFromPayload(
      payload,
      ranchId: ranchId,
      cattleId: cattleId,
    );
    _requireAccepted(
      cattle.status == CattleStatus.active &&
          cattle.currentStage == change.stage &&
          _isNewVersion(cattle, expectedVersion),
    );
    return cattle;
  }

  @override
  Future<Cattle> deactivate(
    String ranchId,
    String cattleId,
    String expectedVersion,
    CattleExit exit,
  ) async {
    final payload = await _requireApi().deactivate(
      ranchId,
      cattleId,
      expectedVersion,
      exit,
    );
    final cattle = CattleMapping.cattleFromPayload(
      payload,
      ranchId: ranchId,
      cattleId: cattleId,
    );
    _requireAccepted(
      cattle.status == CattleStatus.inactive &&
          cattle.exitReason == exit.reason &&
          cattle.exitDate == exit.exitDate &&
          _isNewVersion(cattle, expectedVersion),
    );
    return cattle;
  }

  bool _isNewVersion(Cattle cattle, String expectedVersion) =>
      cattle.version.toLowerCase() != expectedVersion.toLowerCase();

  void _requireAccepted(bool accepted) {
    if (!accepted) {
      throw const CattleFailure(CattleFailureCode.invalidResponse);
    }
  }

  CattleApiClient _requireApi() {
    final api = _api;
    if (api == null) {
      throw const CattleFailure(CattleFailureCode.configuration);
    }
    return api;
  }
}
