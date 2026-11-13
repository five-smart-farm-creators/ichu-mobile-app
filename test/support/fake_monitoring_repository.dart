import 'dart:async';

import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/latest_telemetry.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/monitoring_failure.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/repositories/monitoring_repository.dart';

final class FakeMonitoringRepository implements MonitoringRepository {
  bool configured = true;
  LatestTelemetry? latestResult;
  Object? failure;
  Completer<LatestTelemetry>? completer;
  final requests = <({String ranchId, String cattleId})>[];
  int get calls => requests.length;

  @override
  bool get isConfigured => configured;

  @override
  Future<LatestTelemetry> latest(String ranchId, String cattleId) {
    requests.add((ranchId: ranchId, cattleId: cattleId));
    final pending = completer;
    if (pending != null) return pending.future;
    final error = failure;
    if (error != null) return Future<LatestTelemetry>.error(error);
    final result = latestResult;
    if (result != null) return Future<LatestTelemetry>.value(result);
    return Future<LatestTelemetry>.error(
      const MonitoringFailure(MonitoringFailureCode.notFound),
    );
  }
}

/// Creates explicit test data; defaults describe unavailable measurements, not zero.
LatestTelemetry syntheticLatestTelemetry({
  required String cattleId,
  DateTime? evaluatedAt,
  LatestIndicator? bodyTemperature,
  LatestIndicator? activityIndex,
  LatestIndicator? ruminationMinutes,
  LastKnownPosition? lastKnownPosition,
}) {
  final evaluated = evaluatedAt ?? DateTime.utc(2026, 1, 1);
  return LatestTelemetry(
    cattleId: cattleId,
    evaluatedAt: evaluated,
    origin: TelemetryOrigin.edgeGateway,
    bodyTemperature:
        bodyTemperature ??
        const LatestIndicator.unavailable(unit: TelemetryUnit.celsius),
    activityIndex:
        activityIndex ??
        const LatestIndicator.unavailable(unit: TelemetryUnit.activityIndex),
    ruminationMinutes:
        ruminationMinutes ??
        const LatestIndicator.unavailable(unit: TelemetryUnit.minutes),
    lastKnownPosition:
        lastKnownPosition ?? const LastKnownPosition.unavailable(),
  );
}
