/// A synchronized alert whose authoritative origin is an Edge Gateway.
///
/// This read model intentionally excludes the cloud acknowledgement workflow.
final class EdgeAlert {
  EdgeAlert({
    required this.alertId,
    required this.ranchId,
    required this.cattleId,
    required this.deviceId,
    required this.gatewayId,
    required this.type,
    required this.severity,
    required this.raisedAt,
    required this.receivedAt,
    required this.configurationRevision,
    required List<String> readingIds,
    this.detectedValue,
    this.unit,
    this.thresholdMinValue,
    this.thresholdMaxValue,
    this.geofenceId,
    this.latitude,
    this.longitude,
    this.distanceToBoundaryMeters,
    this.clearedAt,
    this.exitDurationSeconds,
  }) : readingIds = List<String>.unmodifiable(readingIds);

  final String alertId;
  final String ranchId;
  final String cattleId;
  final String deviceId;
  final String gatewayId;
  final EdgeAlertType type;
  final EdgeAlertSeverity severity;
  final DateTime raisedAt;
  final DateTime receivedAt;
  final double? detectedValue;
  final String? unit;
  final double? thresholdMinValue;
  final double? thresholdMaxValue;
  final int configurationRevision;
  final String? geofenceId;
  final double? latitude;
  final double? longitude;
  final double? distanceToBoundaryMeters;
  final DateTime? clearedAt;
  final double? exitDurationSeconds;
  final List<String> readingIds;
}

enum EdgeAlertType { temperature, activity, geofence }

enum EdgeAlertSeverity { informative, warning, critical }

/// A page of synchronized Edge-origin records returned for one authorized ranch.
final class EdgeAlertPage {
  EdgeAlertPage({
    required this.page,
    required this.pageSize,
    required this.totalCount,
    required List<EdgeAlert> items,
  }) : items = List<EdgeAlert>.unmodifiable(items);

  final int page;
  final int pageSize;
  final int totalCount;
  final List<EdgeAlert> items;
}
