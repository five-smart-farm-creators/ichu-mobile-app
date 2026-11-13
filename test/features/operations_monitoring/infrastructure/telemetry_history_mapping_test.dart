import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/monitoring_failure.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/telemetry_history.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/telemetry_history_query.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/infrastructure/repositories/telemetry_history_mapping.dart';

void main() {
  const cattleId = '33333333-3333-4333-8333-333333333333';
  const otherCattleId = '44444444-4444-4444-8444-444444444444';
  final from = DateTime.utc(2026, 11, 12);
  final to = DateTime.utc(2026, 11, 13);
  final query = TelemetryHistoryQuery(from: from, to: to, pageSize: 10);

  test('maps a page with independent valid, invalid and absent captures', () {
    final page = TelemetryHistoryMapping.pageFromPayload(
      _payload(cattleId: cattleId, from: from, to: to),
      cattleId: cattleId,
      query: query,
    );

    expect(page.cattleId, cattleId);
    expect(page.from, from);
    expect(page.to, to);
    expect(page.oldestRetainedRecordedAt, DateTime.utc(2026, 10, 1));
    expect(page.page, 1);
    expect(page.pageSize, 10);
    expect(page.totalCount, 1);
    expect(page.items, hasLength(1));
    final reading = page.items.single;
    expect(reading.recordedAt, DateTime.utc(2026, 11, 12, 1));
    expect(reading.receivedAt, DateTime.utc(2026, 11, 12, 1, 0, 2));
    expect(reading.bodyTemperature.value, 38.6);
    expect(reading.activityIndex.status, HistoricalMeasurementStatus.absent);
    expect(
      reading.ruminationMinutes.status,
      HistoricalMeasurementStatus.invalid,
    );
    expect(reading.batteryLevel.status, HistoricalMeasurementStatus.absent);
    expect(reading.position.latitude, -13.5);
    expect(reading.position.accuracyMeters, 5);
  });

  test('maps an empty page without treating it as an unavailable response', () {
    final payload = _payload(cattleId: cattleId, from: from, to: to)
      ..['totalCount'] = 0
      ..['items'] = <Object?>[]
      ..['oldestRetainedRecordedAt'] = null;

    final page = TelemetryHistoryMapping.pageFromPayload(
      payload,
      cattleId: cattleId,
      query: query,
    );

    expect(page.totalCount, 0);
    expect(page.items, isEmpty);
    expect(page.oldestRetainedRecordedAt, isNull);
  });

  test('rejects a page for another cattle or a different requested period', () {
    final wrongCattle = _payload(cattleId: otherCattleId, from: from, to: to);
    final wrongPeriod = _payload(cattleId: cattleId, from: from, to: to)
      ..['to'] = DateTime.utc(2026, 11, 14).toIso8601String();

    for (final payload in [wrongCattle, wrongPeriod]) {
      expect(
        () => TelemetryHistoryMapping.pageFromPayload(
          payload,
          cattleId: cattleId,
          query: query,
        ),
        throwsA(
          isA<MonitoringFailure>().having(
            (failure) => failure.code,
            'code',
            MonitoringFailureCode.invalidResponse,
          ),
        ),
      );
    }
  });

  test(
    'rejects malformed readings and the exclusive upper period boundary',
    () {
      final valid = _payload(cattleId: cattleId, from: from, to: to);
      final outsideRange = _payload(cattleId: cattleId, from: from, to: to);
      ((outsideRange['items'] as List<Object?>).single
          as Map<String, Object?>)['recordedAt'] = to
          .toIso8601String();
      final invalidMeasurement = _payload(
        cattleId: cattleId,
        from: from,
        to: to,
      );
      (((invalidMeasurement['items'] as List<Object?>).single
                  as Map<String, Object?>)['bodyTemperature']
              as Map<String, Object?>)['status'] =
          'Available';

      for (final payload in [valid, outsideRange, invalidMeasurement].skip(1)) {
        expect(
          () => TelemetryHistoryMapping.pageFromPayload(
            payload,
            cattleId: cattleId,
            query: query,
          ),
          throwsA(
            isA<MonitoringFailure>().having(
              (failure) => failure.code,
              'code',
              MonitoringFailureCode.invalidResponse,
            ),
          ),
        );
      }
    },
  );
}

Map<String, Object?> _payload({
  required String cattleId,
  required DateTime from,
  required DateTime to,
}) => <String, Object?>{
  'cattleId': cattleId,
  'from': from.toIso8601String(),
  'to': to.toIso8601String(),
  'oldestRetainedRecordedAt': '2026-10-01T00:00:00Z',
  'page': 1,
  'pageSize': 10,
  'totalCount': 1,
  'items': <Object?>[
    <String, Object?>{
      'readingId': '55555555-5555-4555-8555-555555555555',
      'deviceId': '66666666-6666-4666-8666-666666666666',
      'cattleId': cattleId,
      'gatewayId': '77777777-7777-4777-8777-777777777777',
      'origin': 'EdgeGateway',
      'recordedAt': from.add(const Duration(hours: 1)).toIso8601String(),
      'receivedAt': from
          .add(const Duration(hours: 1, seconds: 2))
          .toIso8601String(),
      'bodyTemperature': <String, Object?>{
        'value': 38.6,
        'unit': 'celsius',
        'status': 'Valid',
        'invalidReason': null,
      },
      'activityIndex': <String, Object?>{
        'value': null,
        'unit': 'index',
        'status': 'Absent',
        'invalidReason': null,
      },
      'ruminationMinutes': <String, Object?>{
        'value': null,
        'unit': 'minutes',
        'status': 'Invalid',
        'invalidReason': 'sensor-error',
      },
      'batteryLevel': <String, Object?>{
        'value': null,
        'unit': 'percent',
        'status': 'Absent',
        'invalidReason': null,
      },
      'position': <String, Object?>{
        'latitude': -13.5,
        'longitude': -72.3,
        'accuracyMeters': 5,
        'status': 'Valid',
        'invalidReason': null,
      },
    },
  ],
};
