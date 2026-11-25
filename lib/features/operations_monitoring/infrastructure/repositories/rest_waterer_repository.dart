import '../../domain/model/waterer.dart';
import '../../domain/model/water_history_query.dart';
import '../../domain/model/monitoring_failure.dart';
import '../../domain/repositories/waterer_repository.dart';
import '../http/monitoring_api_client.dart';
import 'waterer_mapping.dart';

final class RestWatererRepository implements WatererRepository {
  const RestWatererRepository({required this._api});
  final MonitoringApiClient? _api;

  @override
  bool get isConfigured => _api?.isConfigured ?? false;

  MonitoringApiClient get _configuredApi =>
      _api ??
      (throw const MonitoringFailure(MonitoringFailureCode.configuration));

  @override
  Future<List<WatererStatus>> list(String ranchId) async =>
      WatererMapping.list(await _configuredApi.waterers(ranchId), ranchId);

  @override
  Future<WatererStatus> detail(String ranchId, String waterTroughId) async =>
      WatererMapping.detail(
        await _configuredApi.waterer(ranchId, waterTroughId),
        ranchId,
        waterTroughId,
      );

  @override
  Future<WaterHistoryPage> history(
    String ranchId,
    String controllerId,
    WaterHistoryQuery query,
  ) async => WatererMapping.history(
    await _configuredApi.waterHistory(ranchId, controllerId, query),
    ranchId,
    controllerId,
    query,
  );
}
