import '../model/latest_telemetry.dart';

abstract interface class MonitoringRepository {
  bool get isConfigured;
  Future<LatestTelemetry> latest(String ranchId, String cattleId);
}
