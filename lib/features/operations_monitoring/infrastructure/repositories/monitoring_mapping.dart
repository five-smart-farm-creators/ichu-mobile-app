import '../../domain/model/latest_telemetry.dart';
import '../../domain/model/monitoring_failure.dart';

/// Validates the implemented latest-telemetry JSON contract.
abstract final class MonitoringMapping {
  static LatestTelemetry latestTelemetryFromPayload(
    Object? payload, {
    required String cattleId,
  }) {
    final json = _object(payload);
    final responseCattleId = _string(json['cattleId']);
    if (!_sameUuid(responseCattleId, cattleId)) _invalid();

    final evaluatedAt = _timestamp(json['evaluatedAt']);
    final lastReadingRecordedAt = _nullableTimestamp(
      json,
      'lastReadingRecordedAt',
    );
    if (_string(json['origin']) != 'EdgeGateway') _invalid();

    return LatestTelemetry(
      cattleId: responseCattleId,
      evaluatedAt: evaluatedAt,
      lastReadingRecordedAt: lastReadingRecordedAt,
      origin: TelemetryOrigin.edgeGateway,
      bodyTemperature: _indicator(
        json['bodyTemperature'],
        unit: 'celsius',
        telemetryUnit: TelemetryUnit.celsius,
      ),
      activityIndex: _indicator(
        json['activityIndex'],
        unit: 'index',
        telemetryUnit: TelemetryUnit.activityIndex,
      ),
      ruminationMinutes: _indicator(
        json['ruminationMinutes'],
        unit: 'minutes',
        telemetryUnit: TelemetryUnit.minutes,
      ),
      lastKnownPosition: _position(json['lastKnownPosition']),
    );
  }

  static LatestIndicator _indicator(
    Object? payload, {
    required String unit,
    required TelemetryUnit telemetryUnit,
  }) {
    final json = _object(payload);
    if (_string(json['unit']) != unit) _invalid();
    final status = _string(json['status']);
    final value = _nullableFiniteNumber(json, 'value');
    final recordedAt = _nullableTimestamp(json, 'recordedAt');
    final isStale = _nullableBoolean(json, 'isStale');

    if (status == 'Unavailable') {
      if (value != null || recordedAt != null || isStale != null) _invalid();
      return LatestIndicator.unavailable(unit: telemetryUnit);
    }
    if (status != 'Available' ||
        value == null ||
        recordedAt == null ||
        isStale == null) {
      _invalid();
    }
    if ((telemetryUnit == TelemetryUnit.activityIndex ||
            telemetryUnit == TelemetryUnit.minutes) &&
        value < 0) {
      _invalid();
    }
    return LatestIndicator.available(
      value: value,
      unit: telemetryUnit,
      recordedAt: recordedAt,
      isStale: isStale,
    );
  }

  static LastKnownPosition _position(Object? payload) {
    final json = _object(payload);
    final status = _string(json['status']);
    final latitude = _nullableFiniteNumber(json, 'latitude');
    final longitude = _nullableFiniteNumber(json, 'longitude');
    final accuracyMeters = _nullableFiniteNumber(json, 'accuracyMeters');
    final recordedAt = _nullableTimestamp(json, 'recordedAt');
    final isStale = _nullableBoolean(json, 'isStale');

    if (status == 'Unavailable') {
      if (latitude != null ||
          longitude != null ||
          accuracyMeters != null ||
          recordedAt != null ||
          isStale != null) {
        _invalid();
      }
      return const LastKnownPosition.unavailable();
    }
    if (status != 'Available' ||
        latitude == null ||
        longitude == null ||
        accuracyMeters == null ||
        recordedAt == null ||
        isStale == null ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180 ||
        accuracyMeters < 0) {
      _invalid();
    }
    return LastKnownPosition.available(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
      recordedAt: recordedAt,
      isStale: isStale,
    );
  }

  static Map<String, Object?> _object(Object? value) {
    if (value is! Map) _invalid();
    try {
      return Map<String, Object?>.from(value);
    } on TypeError {
      _invalid();
    }
  }

  static String _string(Object? value) {
    if (value is! String || value.isEmpty) _invalid();
    return value;
  }

  static double? _nullableFiniteNumber(Map<String, Object?> json, String key) {
    if (!json.containsKey(key)) _invalid();
    final value = json[key];
    if (value == null) return null;
    if (value is! num || !value.toDouble().isFinite) _invalid();
    return value.toDouble();
  }

  static bool? _nullableBoolean(Map<String, Object?> json, String key) {
    if (!json.containsKey(key)) _invalid();
    final value = json[key];
    if (value == null) return null;
    if (value is! bool) _invalid();
    return value;
  }

  static DateTime? _nullableTimestamp(Map<String, Object?> json, String key) {
    if (!json.containsKey(key)) _invalid();
    final value = json[key];
    return value == null ? null : _timestamp(value);
  }

  static DateTime _timestamp(Object? value) {
    if (value is! String) _invalid();
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,7})?(Z|([+-])(\d{2}):(\d{2}))$',
    ).firstMatch(value);
    if (match == null) _invalid();
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final second = int.parse(match.group(6)!);
    if (year < 1 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > DateTime.utc(year, month + 1, 0).day ||
        hour > 23 ||
        minute > 59 ||
        second > 59) {
      _invalid();
    }
    if (match.group(7) != 'Z') {
      final offsetHour = int.parse(match.group(9)!);
      final offsetMinute = int.parse(match.group(10)!);
      if (offsetHour > 14 ||
          offsetMinute > 59 ||
          (offsetHour == 14 && offsetMinute != 0)) {
        _invalid();
      }
    }
    try {
      final parsed = DateTime.parse(value).toUtc();
      if (parsed.year < 1 || parsed.year > 9999) _invalid();
      return parsed;
    } on FormatException {
      _invalid();
    } on RangeError {
      _invalid();
    }
  }

  static bool _sameUuid(String left, String right) =>
      _isNonzeroUuid(left) &&
      _isNonzeroUuid(right) &&
      left.toLowerCase() == right.toLowerCase();

  static bool _isNonzeroUuid(String value) =>
      RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(value) &&
      value.replaceAll('-', '').replaceAll('0', '').isNotEmpty;

  static Never _invalid() =>
      throw const MonitoringFailure(MonitoringFailureCode.invalidResponse);
}
