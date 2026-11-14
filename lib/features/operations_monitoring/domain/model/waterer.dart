/// Server-evaluated states are preserved without inferring device connectivity.
enum WaterControllerStatus {
  noController,
  noReadings,
  communicating,
  noCommunication,
}

enum WaterMeasurementStatus { unavailable, invalid, valid }

enum WaterRangeStatus {
  notConfigured,
  unavailable,
  belowRange,
  withinRange,
  aboveRange,
}

enum WaterHeaterState { off, on }

final class WaterReading {
  const WaterReading({
    required this.id,
    required this.readingId,
    required this.controllerId,
    required this.waterTroughId,
    required this.ranchId,
    required this.gatewayId,
    required this.temperatureCelsius,
    required this.isValid,
    required this.heaterState,
    required this.capturedAt,
    required this.receivedAt,
  });

  final String id;
  final String readingId;
  final String controllerId;
  final String waterTroughId;
  final String ranchId;
  final String gatewayId;
  final double temperatureCelsius;
  final bool isValid;
  final WaterHeaterState heaterState;
  final DateTime capturedAt;
  final DateTime receivedAt;
}

final class WatererStatus {
  const WatererStatus({
    required this.waterTroughId,
    required this.name,
    required this.lotId,
    required this.minimumCelsius,
    required this.maximumCelsius,
    required this.controllerStatus,
    required this.controllerId,
    required this.controllerAssignedAt,
    required this.lastCommunicationAt,
    required this.measurementStatus,
    required this.rangeStatus,
    required this.latestReading,
    required this.evaluatedAt,
  });

  final String waterTroughId;
  final String name;
  final String? lotId;
  final double? minimumCelsius;
  final double? maximumCelsius;
  final WaterControllerStatus controllerStatus;
  final String? controllerId;
  final DateTime? controllerAssignedAt;
  final DateTime? lastCommunicationAt;
  final WaterMeasurementStatus measurementStatus;
  final WaterRangeStatus rangeStatus;
  final WaterReading? latestReading;
  final DateTime evaluatedAt;
}

final class WaterHistoryPage {
  WaterHistoryPage({
    required this.controllerId,
    required this.from,
    required this.to,
    required this.page,
    required this.pageSize,
    required this.totalCount,
    required List<WaterReading> items,
  }) : items = List.unmodifiable(items);

  final String controllerId;
  final DateTime from;
  final DateTime to;
  final int page;
  final int pageSize;
  final int totalCount;
  final List<WaterReading> items;
}
