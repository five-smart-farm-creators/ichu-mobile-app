enum AlertType { temperature, activity, geofence }

enum AlertSeverity { informative, warning, critical }

enum AlertStatus { pending, acknowledged }

enum AlertOrigin { edgeGateway }

/// One persisted, ranch-scoped alert returned by Operations Monitoring.
final class RanchAlert {
  RanchAlert({
    required this.alertId,
    required this.ranchId,
    required this.cattleId,
    required this.deviceId,
    required this.gatewayId,
    required this.type,
    required this.severity,
    required this.status,
    required this.origin,
    required this.raisedAt,
    required this.receivedAt,
    required this.configurationRevision,
    required this.version,
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
    this.acknowledgedAt,
    this.acknowledgedBy,
    this.finding,
    this.action,
    this.responseTimeSeconds,
  }) : readingIds = List<String>.unmodifiable(readingIds);

  final String alertId;
  final String ranchId;
  final String cattleId;
  final String deviceId;
  final String gatewayId;
  final AlertType type;
  final AlertSeverity severity;
  final AlertStatus status;
  final AlertOrigin origin;
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
  final DateTime? acknowledgedAt;
  final String? acknowledgedBy;
  final String? finding;
  final String? action;
  final double? responseTimeSeconds;
  final int version;
  final List<String> readingIds;
}

/// A single page of the backend's ranch alert list.
final class AlertPage {
  AlertPage({
    required this.page,
    required this.pageSize,
    required this.totalCount,
    required List<RanchAlert> items,
  }) : items = List<RanchAlert>.unmodifiable(items);

  final int page;
  final int pageSize;
  final int totalCount;
  final List<RanchAlert> items;
}
