import '../../domain/model/latest_telemetry.dart';
import '../../domain/model/monitoring_failure.dart';
import '../../domain/repositories/monitoring_repository.dart';
import '../http/monitoring_api_client.dart';
import 'monitoring_mapping.dart';

/// REST adapter for the implemented read-only Operations Monitoring summary.
final class RestMonitoringRepository implements MonitoringRepository {
  const RestMonitoringRepository({required this._api});

  final MonitoringApiClient? _api;

  @override
  bool get isConfigured => _api?.isConfigured ?? false;

  @override
  Future<LatestTelemetry> latest(String ranchId, String cattleId) async {
    final api = _api;
    if (api == null) {
      throw const MonitoringFailure(MonitoringFailureCode.configuration);
    }
    final payload = await api.latest(ranchId, cattleId);
    return MonitoringMapping.latestTelemetryFromPayload(
      payload,
      cattleId: cattleId,
    );
  }
}
