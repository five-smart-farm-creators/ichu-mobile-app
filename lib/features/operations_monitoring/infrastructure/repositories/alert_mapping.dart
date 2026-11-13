import '../../domain/model/alert_search.dart';
import '../../domain/model/monitoring_failure.dart';
import '../../domain/model/ranch_alert.dart';

/// Validates the implemented ranch-scoped Operations Monitoring alert contract.
abstract final class AlertMapping {
  static AlertPage pageFromPayload(
    Object? payload, {
    required String ranchId,
    required AlertSearch query,
  }) {
    final json = _object(payload);
    final page = _int32(json, 'page', minimum: 1);
    final pageSize = _int32(json, 'pageSize', minimum: 1);
    final totalCount = _int32(json, 'totalCount', minimum: 0);
    if (page != query.page || pageSize != query.pageSize) _invalid();

    final payloadItems = json['items'];
    if (payloadItems is! List || payloadItems.length > pageSize) _invalid();
    final items = <RanchAlert>[];
    final alertIds = <String>{};
    for (final payloadItem in payloadItems) {
      final alert = _alert(payloadItem, ranchId);
      if (!alertIds.add(alert.alertId.toLowerCase())) _invalid();
      if (query.status != null && alert.status != query.status) _invalid();
      items.add(alert);
    }

    return AlertPage(
      page: page,
      pageSize: pageSize,
      totalCount: totalCount,
      items: items,
    );
  }

  static RanchAlert _alert(Object? payload, String expectedRanchId) {
    final json = _object(payload);
    final alertId = _uuid(json, 'alertId');
    final ranchId = _uuid(json, 'ranchId');
    if (!_sameUuid(ranchId, expectedRanchId)) _invalid();
    final cattleId = _uuid(json, 'cattleId');
    final deviceId = _uuid(json, 'deviceId');
    final gatewayId = _uuid(json, 'gatewayId');
    final type = _enumValue(json, 'type', AlertType.values);
    final severity = _enumValue(json, 'severity', AlertSeverity.values);
    final status = _enumValue(json, 'status', AlertStatus.values);
    if (_string(json, 'origin') != 'EdgeGateway') _invalid();

    final raisedAt = _timestamp(json, 'raisedAt');
    final receivedAt = _timestamp(json, 'receivedAt');
    final detectedValue = _nullableFiniteNumber(json, 'detectedValue');
    final unit = _nullableString(json, 'unit');
    final thresholdMinValue = _nullableFiniteNumber(json, 'thresholdMinValue');
    final thresholdMaxValue = _nullableFiniteNumber(json, 'thresholdMaxValue');
    final configurationRevision = _int64(json, 'configurationRevision');
    final geofenceId = _nullableUuid(json, 'geofenceId');
    final latitude = _nullableFiniteNumber(json, 'latitude');
    final longitude = _nullableFiniteNumber(json, 'longitude');
    final distance = _nullableFiniteNumber(json, 'distanceToBoundaryMeters');
    final clearedAt = _nullableTimestamp(json, 'clearedAt');
    final exitDuration = _nullableFiniteNumber(json, 'exitDurationSeconds');
    final acknowledgedAt = _nullableTimestamp(json, 'acknowledgedAt');
    final acknowledgedBy = _nullableUuid(json, 'acknowledgedBy');
    final finding = _nullableString(json, 'finding');
    final action = _nullableString(json, 'action');
    final responseTime = _nullableFiniteNumber(json, 'responseTimeSeconds');
    final version = _int32(json, 'version', minimum: 1);

    final payloadReadingIds = json['readingIds'];
    if (payloadReadingIds is! List || payloadReadingIds.isEmpty) _invalid();
    final readingIds = <String>[];
    for (final value in payloadReadingIds) {
      final readingId = _uuidValue(value);
      // Evidence is keyed by device + reading ID, but this DTO exposes only
      // reading IDs. Equal IDs from different devices must be preserved.
      readingIds.add(readingId);
    }

    if (type == AlertType.geofence) {
      if (unit != null ||
          detectedValue != null ||
          thresholdMinValue != null ||
          thresholdMaxValue != null ||
          geofenceId == null ||
          latitude == null ||
          longitude == null ||
          distance == null ||
          latitude < -90 ||
          latitude > 90 ||
          longitude < -180 ||
          longitude > 180 ||
          distance < 0) {
        _invalid();
      }
    } else {
      final expectedUnit = type == AlertType.temperature ? 'celsius' : 'index';
      if (unit != expectedUnit ||
          detectedValue == null ||
          thresholdMinValue == null ||
          thresholdMaxValue == null ||
          geofenceId != null ||
          latitude != null ||
          longitude != null ||
          distance != null) {
        _invalid();
      }
    }

    if (clearedAt == null) {
      if (exitDuration != null) _invalid();
    } else if (type != AlertType.geofence ||
        exitDuration == null ||
        exitDuration < 0 ||
        clearedAt.isBefore(raisedAt)) {
      _invalid();
    }

    if (acknowledgedAt == null) {
      if (acknowledgedBy != null ||
          finding != null ||
          action != null ||
          responseTime != null ||
          status == AlertStatus.acknowledged) {
        _invalid();
      }
    } else if (status != AlertStatus.acknowledged ||
        acknowledgedBy == null ||
        finding == null ||
        finding.trim().isEmpty ||
        finding.length > 400 ||
        (action?.length ?? 0) > 400 ||
        responseTime == null ||
        responseTime < 0 ||
        acknowledgedAt.isBefore(raisedAt)) {
      _invalid();
    }

    if (configurationRevision < 1) _invalid();
    return RanchAlert(
      alertId: alertId,
      ranchId: ranchId,
      cattleId: cattleId,
      deviceId: deviceId,
      gatewayId: gatewayId,
      type: type,
      severity: severity,
      status: status,
      origin: AlertOrigin.edgeGateway,
      raisedAt: raisedAt,
      receivedAt: receivedAt,
      detectedValue: detectedValue,
      unit: unit,
      thresholdMinValue: thresholdMinValue,
      thresholdMaxValue: thresholdMaxValue,
      configurationRevision: configurationRevision,
      geofenceId: geofenceId,
      latitude: latitude,
      longitude: longitude,
      distanceToBoundaryMeters: distance,
      clearedAt: clearedAt,
      exitDurationSeconds: exitDuration,
      acknowledgedAt: acknowledgedAt,
      acknowledgedBy: acknowledgedBy,
      finding: finding,
      action: action,
      responseTimeSeconds: responseTime,
      version: version,
      readingIds: readingIds,
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

  static String _string(Map<String, Object?> json, String key) {
    final value = json[key];
    if (!json.containsKey(key) || value is! String || value.isEmpty) _invalid();
    return value;
  }

  static String? _nullableString(Map<String, Object?> json, String key) {
    if (!json.containsKey(key)) _invalid();
    final value = json[key];
    if (value == null) return null;
    if (value is! String) _invalid();
    return value;
  }

  static String _uuid(Map<String, Object?> json, String key) =>
      _uuidValue(json[key], present: json.containsKey(key));

  static String? _nullableUuid(Map<String, Object?> json, String key) {
    if (!json.containsKey(key)) _invalid();
    final value = json[key];
    return value == null ? null : _uuidValue(value);
  }

  static String _uuidValue(Object? value, {bool present = true}) {
    if (!present || value is! String || !_isNonzeroUuid(value)) _invalid();
    return value;
  }

  static bool _isNonzeroUuid(String value) =>
      RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(value) &&
      value.replaceAll('-', '').replaceAll('0', '').isNotEmpty;

  static bool _sameUuid(String left, String right) =>
      _isNonzeroUuid(right) && left.toLowerCase() == right.toLowerCase();

  static T _enumValue<T extends Enum>(
    Map<String, Object?> json,
    String key,
    List<T> values,
  ) {
    final value = _string(json, key);
    for (final candidate in values) {
      if (_upperFirst(candidate.name) == value) return candidate;
    }
    _invalid();
  }

  static String _upperFirst(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

  static double? _nullableFiniteNumber(Map<String, Object?> json, String key) {
    if (!json.containsKey(key)) _invalid();
    final value = json[key];
    if (value == null) return null;
    if (value is! num || !value.toDouble().isFinite) _invalid();
    return value.toDouble();
  }

  static int _int32(
    Map<String, Object?> json,
    String key, {
    required int minimum,
  }) {
    final value = json[key];
    if (!json.containsKey(key) ||
        value is! int ||
        value < minimum ||
        value > 2147483647) {
      _invalid();
    }
    return value;
  }

  static int _int64(Map<String, Object?> json, String key) {
    final value = json[key];
    if (!json.containsKey(key) ||
        value is! int ||
        value < 1 ||
        value > 9223372036854775807) {
      _invalid();
    }
    return value;
  }

  static DateTime? _nullableTimestamp(Map<String, Object?> json, String key) {
    if (!json.containsKey(key)) _invalid();
    final value = json[key];
    return value == null ? null : _parseTimestamp(value);
  }

  static DateTime _timestamp(Map<String, Object?> json, String key) {
    if (!json.containsKey(key)) _invalid();
    return _parseTimestamp(json[key]);
  }

  static DateTime _parseTimestamp(Object? value) {
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

  static Never _invalid() =>
      throw const MonitoringFailure(MonitoringFailureCode.invalidResponse);
}
