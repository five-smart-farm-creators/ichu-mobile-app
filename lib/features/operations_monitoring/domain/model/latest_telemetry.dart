enum TelemetryUnit { celsius, activityIndex, minutes }

enum TelemetryOrigin { edgeGateway }

/// Availability describes a measurement, not an animal's health.
final class LatestIndicator {
  const LatestIndicator.unavailable({required this.unit})
    : value = null,
      recordedAt = null,
      isStale = null;

  const LatestIndicator.available({
    required double this.value,
    required this.unit,
    required DateTime this.recordedAt,
    required bool this.isStale,
  });

  final double? value;
  final TelemetryUnit unit;
  final DateTime? recordedAt;

  /// Server decision at the summary's evaluation instant, not at device time.
  final bool? isStale;

  bool get isAvailable => value != null;
}

/// A historical GPS observation, never an inferred or live position.
final class LastKnownPosition {
  const LastKnownPosition.unavailable()
    : latitude = null,
      longitude = null,
      accuracyMeters = null,
      recordedAt = null,
      isStale = null;

  const LastKnownPosition.available({
    required double this.latitude,
    required double this.longitude,
    required double this.accuracyMeters,
    required DateTime this.recordedAt,
    required bool this.isStale,
  });

  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final DateTime? recordedAt;
  final bool? isStale;

  bool get isAvailable => latitude != null;
}

/// Independent latest valid observations, which may have different capture times.
final class LatestTelemetry {
  const LatestTelemetry({
    required this.cattleId,
    required this.evaluatedAt,
    required this.origin,
    required this.bodyTemperature,
    required this.activityIndex,
    required this.ruminationMinutes,
    required this.lastKnownPosition,
    this.lastReadingRecordedAt,
  });

  final String cattleId;
  final DateTime evaluatedAt;
  final DateTime? lastReadingRecordedAt;
  final TelemetryOrigin origin;
  final LatestIndicator bodyTemperature;
  final LatestIndicator activityIndex;
  final LatestIndicator ruminationMinutes;
  final LastKnownPosition lastKnownPosition;
}
