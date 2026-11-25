import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/latest_telemetry.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/monitoring_failure.dart';

void main() {
  test(
    'unavailable observations contain no substitute values or freshness',
    () {
      const indicator = LatestIndicator.unavailable(
        unit: TelemetryUnit.activityIndex,
      );
      const position = LastKnownPosition.unavailable();
      expect(indicator.isAvailable, isFalse);
      expect(indicator.value, isNull);
      expect(indicator.recordedAt, isNull);
      expect(indicator.isStale, isNull);
      expect(position.isAvailable, isFalse);
      expect(position.latitude, isNull);
      expect(position.longitude, isNull);
      expect(position.accuracyMeters, isNull);
      expect(position.recordedAt, isNull);
      expect(position.isStale, isNull);
    },
  );

  test(
    'real zero is available and preserves the server freshness decision',
    () {
      final time = DateTime.utc(2026, 11, 12);
      final indicator = LatestIndicator.available(
        value: 0,
        unit: TelemetryUnit.minutes,
        recordedAt: time,
        isStale: true,
      );
      final position = LastKnownPosition.available(
        latitude: 0,
        longitude: 0,
        accuracyMeters: 0,
        recordedAt: time,
        isStale: false,
      );
      expect(indicator.isAvailable, isTrue);
      expect(indicator.value, 0);
      expect(indicator.isStale, isTrue);
      expect(position.isAvailable, isTrue);
      expect(position.latitude, 0);
      expect(position.recordedAt, same(time));
      expect(position.isStale, isFalse);
    },
  );

  test('failure messages contain only stable categories', () {
    expect(
      const MonitoringFailure(MonitoringFailureCode.network).toString(),
      'MonitoringFailure(network)',
    );
  });
}
