import 'dart:async';

import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/latest_telemetry.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/monitoring_failure.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/telemetry_history.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/telemetry_history_query.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/repositories/monitoring_repository.dart';

final class FakeMonitoringRepository implements MonitoringRepository {
  bool configured = true;
  LatestTelemetry? latestResult;
  TelemetryHistoryPage? historyResult;
  TelemetryHistoryPage Function(
    String ranchId,
    String cattleId,
    TelemetryHistoryQuery query,
  )?
  historyBuilder;
  Object? failure;
  Completer<LatestTelemetry>? completer;
  Completer<TelemetryHistoryPage>? historyCompleter;
  final requests = <({String ranchId, String cattleId})>[];
  final historyRequests =
      <({String ranchId, String cattleId, TelemetryHistoryQuery query})>[];
  int get calls => requests.length;
  int get historyCalls => historyRequests.length;

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

  @override
  Future<TelemetryHistoryPage> history(
    String ranchId,
    String cattleId,
    TelemetryHistoryQuery query,
  ) {
    historyRequests.add((ranchId: ranchId, cattleId: cattleId, query: query));
    final pending = historyCompleter;
    if (pending != null) return pending.future;
    final error = failure;
    if (error != null) return Future<TelemetryHistoryPage>.error(error);
    final result = historyResult;
    if (result != null) return Future<TelemetryHistoryPage>.value(result);
    final builder = historyBuilder;
    if (builder != null) {
      return Future<TelemetryHistoryPage>.value(
        builder(ranchId, cattleId, query),
      );
    }
    return Future<TelemetryHistoryPage>.error(
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

TelemetryHistoryPage syntheticTelemetryHistory({
  required String cattleId,
  required DateTime from,
  required DateTime to,
  int page = 1,
  int pageSize = TelemetryHistoryQuery.defaultPageSize,
  int? totalCount,
  DateTime? oldestRetainedRecordedAt,
  List<TelemetryReading> items = const <TelemetryReading>[],
}) => TelemetryHistoryPage(
  cattleId: cattleId,
  from: from,
  to: to,
  oldestRetainedRecordedAt: oldestRetainedRecordedAt,
  page: page,
  pageSize: pageSize,
  totalCount: totalCount ?? items.length,
  items: items,
);

TelemetryReading syntheticTelemetryReading({
  required String readingId,
  required String cattleId,
  required DateTime recordedAt,
  DateTime? receivedAt,
  HistoricalMeasurement? bodyTemperature,
  HistoricalMeasurement? activityIndex,
  HistoricalMeasurement? ruminationMinutes,
  HistoricalMeasurement? batteryLevel,
  HistoricalPosition? position,
}) => TelemetryReading(
  readingId: readingId,
  deviceId: '11111111-1111-4111-8111-111111111111',
  cattleId: cattleId,
  gatewayId: '22222222-2222-4222-8222-222222222222',
  recordedAt: recordedAt,
  receivedAt: receivedAt ?? recordedAt.add(const Duration(seconds: 2)),
  bodyTemperature:
      bodyTemperature ??
      const HistoricalMeasurement(
        value: null,
        unit: 'celsius',
        status: HistoricalMeasurementStatus.absent,
        invalidReason: null,
      ),
  activityIndex:
      activityIndex ??
      const HistoricalMeasurement(
        value: null,
        unit: 'index',
        status: HistoricalMeasurementStatus.absent,
        invalidReason: null,
      ),
  ruminationMinutes:
      ruminationMinutes ??
      const HistoricalMeasurement(
        value: null,
        unit: 'minutes',
        status: HistoricalMeasurementStatus.absent,
        invalidReason: null,
      ),
  batteryLevel:
      batteryLevel ??
      const HistoricalMeasurement(
        value: null,
        unit: 'percent',
        status: HistoricalMeasurementStatus.absent,
        invalidReason: null,
      ),
  position:
      position ??
      const HistoricalPosition(
        latitude: null,
        longitude: null,
        accuracyMeters: null,
        status: HistoricalMeasurementStatus.absent,
        invalidReason: null,
      ),
);
