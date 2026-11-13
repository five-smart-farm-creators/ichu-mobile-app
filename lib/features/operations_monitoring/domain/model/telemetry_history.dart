import 'telemetry_history_query.dart';

enum HistoricalMeasurementStatus { valid, invalid, absent }

/// A measurement exactly as reported for one historical capture.
final class HistoricalMeasurement {
  const HistoricalMeasurement({
    required this.value,
    required this.unit,
    required this.status,
    required this.invalidReason,
  });

  final double? value;
  final String unit;
  final HistoricalMeasurementStatus status;
  final String? invalidReason;

  bool get isValid => status == HistoricalMeasurementStatus.valid;
}

/// A captured GPS position; it is not a live location.
final class HistoricalPosition {
  const HistoricalPosition({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.status,
    required this.invalidReason,
  });

  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final HistoricalMeasurementStatus status;
  final String? invalidReason;

  bool get isValid => status == HistoricalMeasurementStatus.valid;
}

final class TelemetryReading {
  const TelemetryReading({
    required this.readingId,
    required this.deviceId,
    required this.cattleId,
    required this.gatewayId,
    required this.recordedAt,
    required this.receivedAt,
    required this.bodyTemperature,
    required this.activityIndex,
    required this.ruminationMinutes,
    required this.batteryLevel,
    required this.position,
  });

  final String readingId;
  final String deviceId;
  final String cattleId;
  final String gatewayId;
  final DateTime recordedAt;
  final DateTime receivedAt;
  final HistoricalMeasurement bodyTemperature;
  final HistoricalMeasurement activityIndex;
  final HistoricalMeasurement ruminationMinutes;
  final HistoricalMeasurement batteryLevel;
  final HistoricalPosition position;
}

/// One immutable backend page and its retention boundary metadata.
final class TelemetryHistoryPage {
  TelemetryHistoryPage({
    required this.cattleId,
    required this.from,
    required this.to,
    required this.oldestRetainedRecordedAt,
    required this.page,
    required this.pageSize,
    required this.totalCount,
    required List<TelemetryReading> items,
  }) : items = List<TelemetryReading>.unmodifiable(items);

  final String cattleId;
  final DateTime from;
  final DateTime to;
  final DateTime? oldestRetainedRecordedAt;
  final int page;
  final int pageSize;
  final int totalCount;
  final List<TelemetryReading> items;

  bool matches(TelemetryHistoryQuery query) =>
      from.isAtSameMomentAs(query.from) &&
      to.isAtSameMomentAs(query.to) &&
      page == query.page &&
      pageSize == query.pageSize;
}
