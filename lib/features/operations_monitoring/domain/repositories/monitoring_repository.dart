import '../model/latest_telemetry.dart';
import '../model/telemetry_history.dart';
import '../model/telemetry_history_query.dart';

abstract interface class MonitoringRepository {
  bool get isConfigured;
  Future<LatestTelemetry> latest(String ranchId, String cattleId);
  Future<TelemetryHistoryPage> history(
    String ranchId,
    String cattleId,
    TelemetryHistoryQuery query,
  );
}
