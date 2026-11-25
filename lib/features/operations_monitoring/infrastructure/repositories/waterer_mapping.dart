import '../../domain/model/monitoring_failure.dart';
import '../../domain/model/waterer.dart';
import '../../domain/model/water_history_query.dart';

/// Validates transport identity and shape; status evaluation belongs to the API.
abstract final class WatererMapping {
  static List<WatererStatus> list(Object? payload, String ranchId) {
    final json = _object(payload);
    if (!_same(_uuid(json['ranchId']), ranchId)) _invalid();
    final items = _array(json['items']);
    final result = items.map((item) => _status(item, ranchId)).toList();
    if (result.map((item) => item.waterTroughId.toLowerCase()).toSet().length !=
        result.length) {
      _invalid();
    }
    return List.unmodifiable(result);
  }

  static WatererStatus detail(
    Object? payload,
    String ranchId,
    String waterTroughId,
  ) {
    final result = _status(payload, ranchId);
    if (!_same(result.waterTroughId, waterTroughId)) _invalid();
    return result;
  }

  static WaterHistoryPage history(
    Object? payload,
    String ranchId,
    String controllerId,
    WaterHistoryQuery query,
  ) {
    final json = _object(payload);
    final controller = _uuid(json['controllerId']);
    final from = _timestamp(json['from']);
    final to = _timestamp(json['to']);
    final page = _integer(json['page']);
    final pageSize = _integer(json['pageSize']);
    final total = _integer(json['totalCount']);
    final items = _array(json['items']);
    if (!_same(controller, controllerId) ||
        !from.isAtSameMomentAs(query.from) ||
        !to.isAtSameMomentAs(query.to) ||
        page != query.page ||
        pageSize != query.pageSize ||
        items.length > pageSize) {
      _invalid();
    }
    final readings = items.map((item) => _reading(item, ranchId)).toList();
    final ids = <String>{};
    final readingIds = <String>{};
    for (var index = 0; index < readings.length; index++) {
      final reading = readings[index];
      if (!_same(reading.controllerId, controllerId) ||
          reading.capturedAt.isBefore(from) ||
          !reading.capturedAt.isBefore(to) ||
          !ids.add(reading.id.toLowerCase()) ||
          !readingIds.add(reading.readingId.toLowerCase())) {
        _invalid();
      }
      if (index > 0) {
        final previous = readings[index - 1];
        final order = previous.capturedAt.compareTo(reading.capturedAt);
        if (order > 0 ||
            (order == 0 &&
                previous.readingId.toLowerCase().compareTo(
                      reading.readingId.toLowerCase(),
                    ) >=
                    0)) {
          _invalid();
        }
      }
    }
    return WaterHistoryPage(
      controllerId: controller,
      from: from,
      to: to,
      page: page,
      pageSize: pageSize,
      totalCount: total,
      items: readings,
    );
  }

  static WatererStatus _status(Object? payload, String ranchId) {
    final json = _object(payload);
    final trough = _uuid(json['waterTroughId']);
    final minimum = _nullableNumber(json, 'minimumCelsius');
    final maximum = _nullableNumber(json, 'maximumCelsius');
    if ((minimum == null) != (maximum == null) ||
        (minimum != null && minimum > maximum!)) {
      _invalid();
    }
    if (!json.containsKey('latestReading')) _invalid();
    final latest = json['latestReading'] == null
        ? null
        : _reading(json['latestReading'], ranchId);
    if (latest != null && !_same(latest.waterTroughId, trough)) _invalid();
    return WatererStatus(
      waterTroughId: trough,
      name: _string(json['name']),
      lotId: _nullableUuid(json, 'lotId'),
      minimumCelsius: minimum,
      maximumCelsius: maximum,
      controllerStatus: switch (json['controllerStatus']) {
        'NoController' => WaterControllerStatus.noController,
        'NoReadings' => WaterControllerStatus.noReadings,
        'Communicating' => WaterControllerStatus.communicating,
        'NoCommunication' => WaterControllerStatus.noCommunication,
        _ => _invalid(),
      },
      controllerId: _nullableUuid(json, 'controllerId'),
      controllerAssignedAt: _nullableTimestamp(json, 'controllerAssignedAt'),
      lastCommunicationAt: _nullableTimestamp(json, 'lastCommunicationAt'),
      measurementStatus: switch (json['measurementStatus']) {
        'Unavailable' => WaterMeasurementStatus.unavailable,
        'Invalid' => WaterMeasurementStatus.invalid,
        'Valid' => WaterMeasurementStatus.valid,
        _ => _invalid(),
      },
      rangeStatus: switch (json['rangeStatus']) {
        'NotConfigured' => WaterRangeStatus.notConfigured,
        'Unavailable' => WaterRangeStatus.unavailable,
        'BelowRange' => WaterRangeStatus.belowRange,
        'WithinRange' => WaterRangeStatus.withinRange,
        'AboveRange' => WaterRangeStatus.aboveRange,
        _ => _invalid(),
      },
      latestReading: latest,
      evaluatedAt: _timestamp(json['evaluatedAt']),
    );
  }

  static WaterReading _reading(Object? payload, String ranchId) {
    final json = _object(payload);
    final ranch = _uuid(json['ranchId']);
    if (!_same(ranch, ranchId) ||
        json['temperatureUnit'] != 'Celsius' ||
        json['origin'] != 'EdgeGateway' ||
        json['isValid'] is! bool) {
      _invalid();
    }
    return WaterReading(
      id: _uuid(json['id']),
      readingId: _uuid(json['readingId']),
      controllerId: _uuid(json['controllerId']),
      waterTroughId: _uuid(json['waterTroughId']),
      ranchId: ranch,
      gatewayId: _uuid(json['gatewayId']),
      temperatureCelsius: _number(json['temperature']),
      isValid: json['isValid'] as bool,
      heaterState: switch (json['heaterState']) {
        'Off' => WaterHeaterState.off,
        'On' => WaterHeaterState.on,
        _ => _invalid(),
      },
      capturedAt: _timestamp(json['capturedAt']),
      receivedAt: _timestamp(json['receivedAt']),
    );
  }

  static Map<String, Object?> _object(Object? value) {
    if (value is! Map<String, Object?>) _invalid();
    return value;
  }

  static List<Object?> _array(Object? value) {
    if (value is! List) _invalid();
    return value;
  }

  static String _string(Object? value) {
    if (value is! String || value.trim().isEmpty) _invalid();
    return value;
  }

  static String _uuid(Object? value) {
    final id = _string(value);
    if (!RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(id) ||
        id.replaceAll('-', '').replaceAll('0', '').isEmpty) {
      _invalid();
    }
    return id;
  }

  static String? _nullableUuid(Map<String, Object?> json, String key) {
    if (!json.containsKey(key)) _invalid();
    return json[key] == null ? null : _uuid(json[key]);
  }

  static double _number(Object? value) {
    if (value is! num || !value.toDouble().isFinite) _invalid();
    return value.toDouble();
  }

  static double? _nullableNumber(Map<String, Object?> json, String key) {
    if (!json.containsKey(key)) _invalid();
    return json[key] == null ? null : _number(json[key]);
  }

  static int _integer(Object? value) {
    if (value is! int || value < 0 || value > WaterHistoryQuery.maximumInt32) {
      _invalid();
    }
    return value;
  }

  static DateTime? _nullableTimestamp(Map<String, Object?> json, String key) {
    if (!json.containsKey(key)) _invalid();
    return json[key] == null ? null : _timestamp(json[key]);
  }

  static DateTime _timestamp(Object? value) {
    if (value is! String) _invalid();
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,7})?(Z|[+-]\d{2}:\d{2})$',
    ).firstMatch(value);
    if (match == null) _invalid();
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (year < 1 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > DateTime.utc(year, month + 1, 0).day ||
        int.parse(match.group(4)!) > 23 ||
        int.parse(match.group(5)!) > 59 ||
        int.parse(match.group(6)!) > 59) {
      _invalid();
    }
    final offset = match.group(7)!;
    if (offset != 'Z') {
      final hours = int.parse(offset.substring(1, 3));
      final minutes = int.parse(offset.substring(4, 6));
      if (hours > 14 || minutes > 59 || (hours == 14 && minutes != 0)) {
        _invalid();
      }
    }
    final parsed = DateTime.tryParse(value)?.toUtc();
    if (parsed == null || parsed.year < 1 || parsed.year > 9999) _invalid();
    return parsed;
  }

  static bool _same(String left, String right) =>
      left.toLowerCase() == right.toLowerCase();
  static Never _invalid() =>
      throw const MonitoringFailure(MonitoringFailureCode.invalidResponse);
}
