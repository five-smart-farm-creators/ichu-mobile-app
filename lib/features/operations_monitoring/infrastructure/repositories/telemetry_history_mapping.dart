import '../../domain/model/monitoring_failure.dart';
import '../../domain/model/telemetry_history.dart';
import '../../domain/model/telemetry_history_query.dart';

/// Validates the server's paged historical telemetry response.
abstract final class TelemetryHistoryMapping {
  static TelemetryHistoryPage pageFromPayload(
    Object? payload, {
    required String cattleId,
    required TelemetryHistoryQuery query,
  }) {
    final json = _object(payload);
    final responseCattleId = _uuid(json['cattleId']);
    if (!_sameUuid(responseCattleId, cattleId)) _invalid();

    final from = _timestamp(json['from']);
    final to = _timestamp(json['to']);
    if (!from.isAtSameMomentAs(query.from) || !to.isAtSameMomentAs(query.to)) {
      _invalid();
    }

    final page = _integer(json['page']);
    final pageSize = _integer(json['pageSize']);
    final totalCount = _integer(json['totalCount']);
    final itemsPayload = json['items'];
    if (page != query.page ||
        pageSize != query.pageSize ||
        totalCount < 0 ||
        itemsPayload is! List ||
        itemsPayload.length > pageSize ||
        itemsPayload.length > totalCount) {
      _invalid();
    }

    final items = itemsPayload
        .map(
          (item) =>
              _reading(item, cattleId: responseCattleId, from: from, to: to),
        )
        .toList(growable: false);
    for (var index = 1; index < items.length; index++) {
      if (items[index - 1].recordedAt.isAfter(items[index].recordedAt)) {
        _invalid();
      }
    }

    return TelemetryHistoryPage(
      cattleId: responseCattleId,
      from: from,
      to: to,
      oldestRetainedRecordedAt: _nullableTimestamp(
        json,
        'oldestRetainedRecordedAt',
      ),
      page: page,
      pageSize: pageSize,
      totalCount: totalCount,
      items: items,
    );
  }

  static TelemetryReading _reading(
    Object? payload, {
    required String cattleId,
    required DateTime from,
    required DateTime to,
  }) {
    final json = _object(payload);
    final readingCattleId = _uuid(json['cattleId']);
    final recordedAt = _timestamp(json['recordedAt']);
    if (!_sameUuid(readingCattleId, cattleId) ||
        _string(json['origin']) != 'EdgeGateway' ||
        recordedAt.isBefore(from) ||
        !recordedAt.isBefore(to)) {
      _invalid();
    }

    return TelemetryReading(
      readingId: _uuid(json['readingId']),
      deviceId: _uuid(json['deviceId']),
      cattleId: readingCattleId,
      gatewayId: _uuid(json['gatewayId']),
      recordedAt: recordedAt,
      receivedAt: _timestamp(json['receivedAt']),
      bodyTemperature: _measurement(json['bodyTemperature'], unit: 'celsius'),
      activityIndex: _measurement(json['activityIndex'], unit: 'index'),
      ruminationMinutes: _measurement(
        json['ruminationMinutes'],
        unit: 'minutes',
      ),
      batteryLevel: _measurement(
        json['batteryLevel'],
        unit: 'percent',
        minimum: 0,
        maximum: 100,
      ),
      position: _position(json['position']),
    );
  }

  static HistoricalMeasurement _measurement(
    Object? payload, {
    required String unit,
    double? minimum,
    double? maximum,
  }) {
    final json = _object(payload);
    final value = _nullableFiniteNumber(json, 'value');
    final invalidReason = _nullableString(json, 'invalidReason');
    final status = _status(json['status']);
    if (_string(json['unit']) != unit) _invalid();
    _validateMeasurement(status, value, invalidReason);
    if (value != null &&
        ((minimum != null && value < minimum) ||
            (maximum != null && value > maximum))) {
      _invalid();
    }
    return HistoricalMeasurement(
      value: value,
      unit: unit,
      status: status,
      invalidReason: invalidReason,
    );
  }

  static HistoricalPosition _position(Object? payload) {
    final json = _object(payload);
    final latitude = _nullableFiniteNumber(json, 'latitude');
    final longitude = _nullableFiniteNumber(json, 'longitude');
    final accuracyMeters = _nullableFiniteNumber(json, 'accuracyMeters');
    final invalidReason = _nullableString(json, 'invalidReason');
    final status = _status(json['status']);
    final hasPosition =
        latitude != null || longitude != null || accuracyMeters != null;
    if (status == HistoricalMeasurementStatus.valid) {
      if (latitude == null ||
          longitude == null ||
          accuracyMeters == null ||
          invalidReason != null ||
          latitude < -90 ||
          latitude > 90 ||
          longitude < -180 ||
          longitude > 180 ||
          accuracyMeters < 0) {
        _invalid();
      }
    } else if (hasPosition ||
        (status == HistoricalMeasurementStatus.invalid
            ? invalidReason == null || invalidReason.trim().isEmpty
            : invalidReason != null)) {
      _invalid();
    }
    return HistoricalPosition(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
      status: status,
      invalidReason: invalidReason,
    );
  }

  static void _validateMeasurement(
    HistoricalMeasurementStatus status,
    double? value,
    String? invalidReason,
  ) {
    switch (status) {
      case HistoricalMeasurementStatus.valid:
        if (value == null || invalidReason != null) _invalid();
        break;
      case HistoricalMeasurementStatus.invalid:
        if (value != null ||
            invalidReason == null ||
            invalidReason.trim().isEmpty) {
          _invalid();
        }
        break;
      case HistoricalMeasurementStatus.absent:
        if (value != null || invalidReason != null) _invalid();
        break;
    }
  }

  static HistoricalMeasurementStatus _status(Object? value) =>
      switch (_string(value)) {
        'Valid' => HistoricalMeasurementStatus.valid,
        'Invalid' => HistoricalMeasurementStatus.invalid,
        'Absent' => HistoricalMeasurementStatus.absent,
        _ => _invalid(),
      };

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

  static String _uuid(Object? value) {
    final id = _string(value);
    if (!_isNonzeroUuid(id)) _invalid();
    return id;
  }

  static int _integer(Object? value) {
    if (value is! int || value < 0) _invalid();
    return value;
  }

  static double? _nullableFiniteNumber(Map<String, Object?> json, String key) {
    if (!json.containsKey(key)) _invalid();
    final value = json[key];
    if (value == null) return null;
    if (value is! num || !value.toDouble().isFinite) _invalid();
    return value.toDouble();
  }

  static String? _nullableString(Map<String, Object?> json, String key) {
    if (!json.containsKey(key)) _invalid();
    final value = json[key];
    if (value == null) return null;
    if (value is! String || value.length > 200) _invalid();
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

  static bool _isNonzeroUuid(String value) =>
      RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(value) &&
      value.replaceAll('-', '').replaceAll('0', '').isNotEmpty;

  static bool _sameUuid(String left, String right) =>
      _isNonzeroUuid(left) &&
      _isNonzeroUuid(right) &&
      left.toLowerCase() == right.toLowerCase();

  static Never _invalid() =>
      throw const MonitoringFailure(MonitoringFailureCode.invalidResponse);
}
