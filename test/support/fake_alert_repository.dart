import 'dart:async';

import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/alert_search.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/alert_acknowledgement.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/alert_acknowledgement_result.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/monitoring_failure.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/ranch_alert.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/repositories/alert_repository.dart';

final class FakeAlertRepository implements AlertRepository {
  bool configured = true;
  AlertPage? pageResult;
  Object? failure;
  Completer<AlertPage>? completer;
  AlertAcknowledgementResult? acknowledgementResult;
  Completer<AlertAcknowledgementResult>? acknowledgementCompleter;
  Object? acknowledgementFailure;
  final requests = <({String ranchId, AlertSearch query})>[];
  final acknowledgements = <({String ranchId, AlertAcknowledgement request})>[];

  int get calls => requests.length;

  @override
  bool get isConfigured => configured;

  @override
  Future<AlertPage> search(String ranchId, AlertSearch query) {
    requests.add((ranchId: ranchId, query: query));
    final pending = completer;
    if (pending != null) return pending.future;
    final error = failure;
    if (error != null) return Future<AlertPage>.error(error);
    final result = pageResult;
    if (result != null) return Future<AlertPage>.value(result);
    return Future<AlertPage>.error(
      const MonitoringFailure(MonitoringFailureCode.invalidResponse),
    );
  }

  @override
  Future<AlertAcknowledgementResult> acknowledge(
    String ranchId,
    AlertAcknowledgement request,
  ) {
    acknowledgements.add((ranchId: ranchId, request: request));
    final pending = acknowledgementCompleter;
    if (pending != null) return pending.future;
    final error = acknowledgementFailure;
    if (error != null) {
      return Future<AlertAcknowledgementResult>.error(error);
    }
    final result = acknowledgementResult;
    if (result != null) return Future<AlertAcknowledgementResult>.value(result);
    return Future<AlertAcknowledgementResult>.error(
      const MonitoringFailure(MonitoringFailureCode.invalidResponse),
    );
  }
}

/// Creates explicit, valid synthetic alert data for application tests.
RanchAlert syntheticRanchAlert({
  required String ranchId,
  required String alertId,
  AlertStatus status = AlertStatus.pending,
}) {
  final acknowledged = status == AlertStatus.acknowledged;
  return RanchAlert(
    alertId: alertId,
    ranchId: ranchId,
    cattleId: 'c3333333-3333-4333-8333-333333333333',
    deviceId: 'd4444444-4444-4444-8444-444444444444',
    gatewayId: 'e5555555-5555-4555-8555-555555555555',
    type: AlertType.temperature,
    severity: AlertSeverity.warning,
    status: status,
    origin: AlertOrigin.edgeGateway,
    raisedAt: DateTime.utc(2026, 1, 1),
    receivedAt: DateTime.utc(2026, 1, 1, 0, 0, 1),
    detectedValue: 40.2,
    unit: 'celsius',
    thresholdMinValue: 37.5,
    thresholdMaxValue: 39.5,
    configurationRevision: 1,
    geofenceId: null,
    latitude: null,
    longitude: null,
    distanceToBoundaryMeters: null,
    clearedAt: null,
    exitDurationSeconds: null,
    acknowledgedAt: acknowledged ? DateTime.utc(2026, 1, 1, 1) : null,
    acknowledgedBy: acknowledged
        ? 'f6666666-6666-4666-8666-666666666666'
        : null,
    finding: acknowledged ? 'Synthetic observation' : null,
    action: null,
    responseTimeSeconds: acknowledged ? 3600 : null,
    version: acknowledged ? 2 : 1,
    readingIds: const <String>['a7777777-7777-4777-8777-777777777777'],
  );
}
