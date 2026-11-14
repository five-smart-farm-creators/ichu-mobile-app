import '../../domain/model/alert_search.dart';
import '../../domain/model/edge_alert.dart';
import '../../domain/model/monitoring_failure.dart';
import '../../domain/model/ranch_alert.dart';
import '../../domain/repositories/alert_repository.dart';
import '../../domain/repositories/edge_alert_repository.dart';

/// Adapts authorized, synchronized EdgeGateway-origin alert records.
final class RestEdgeAlertRepository implements EdgeAlertRepository {
  const RestEdgeAlertRepository({required this._alerts});

  final AlertRepository _alerts;

  @override
  bool get isConfigured => _alerts.isConfigured;

  @override
  Future<EdgeAlertPage> page(String ranchId, int page) async {
    if (page < 1 || page > AlertSearch.maximumInt32) {
      throw const MonitoringFailure(MonitoringFailureCode.invalidSearch);
    }

    final result = await _alerts.search(
      ranchId,
      AlertSearch(page: page, pageSize: EdgeAlertRepository.pageSize),
    );
    if (result.page != page ||
        result.pageSize != EdgeAlertRepository.pageSize ||
        result.totalCount < 0 ||
        result.items.length > result.pageSize) {
      throw const MonitoringFailure(MonitoringFailureCode.invalidResponse);
    }

    final items = <EdgeAlert>[];
    for (final alert in result.items) {
      if (alert.origin != AlertOrigin.edgeGateway ||
          !_sameUuid(alert.ranchId, ranchId)) {
        throw const MonitoringFailure(MonitoringFailureCode.invalidResponse);
      }
      items.add(_map(alert));
    }

    return EdgeAlertPage(
      page: result.page,
      pageSize: result.pageSize,
      totalCount: result.totalCount,
      items: items,
    );
  }

  EdgeAlert _map(RanchAlert alert) => EdgeAlert(
    alertId: alert.alertId,
    ranchId: alert.ranchId,
    cattleId: alert.cattleId,
    deviceId: alert.deviceId,
    gatewayId: alert.gatewayId,
    type: switch (alert.type) {
      AlertType.temperature => EdgeAlertType.temperature,
      AlertType.activity => EdgeAlertType.activity,
      AlertType.geofence => EdgeAlertType.geofence,
    },
    severity: switch (alert.severity) {
      AlertSeverity.informative => EdgeAlertSeverity.informative,
      AlertSeverity.warning => EdgeAlertSeverity.warning,
      AlertSeverity.critical => EdgeAlertSeverity.critical,
    },
    raisedAt: alert.raisedAt,
    receivedAt: alert.receivedAt,
    detectedValue: alert.detectedValue,
    unit: alert.unit,
    thresholdMinValue: alert.thresholdMinValue,
    thresholdMaxValue: alert.thresholdMaxValue,
    configurationRevision: alert.configurationRevision,
    geofenceId: alert.geofenceId,
    latitude: alert.latitude,
    longitude: alert.longitude,
    distanceToBoundaryMeters: alert.distanceToBoundaryMeters,
    clearedAt: alert.clearedAt,
    exitDurationSeconds: alert.exitDurationSeconds,
    readingIds: alert.readingIds,
  );

  bool _sameUuid(String left, String right) =>
      left.toLowerCase() == right.toLowerCase();
}
