import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/monitoring_failure.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/waterer.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/water_history_query.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/infrastructure/http/monitoring_api_client.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/infrastructure/repositories/rest_waterer_repository.dart';

import '../../../support/waterer_test_support.dart';

final _query = WaterHistoryQuery(
  from: DateTime.utc(2026, 11, 14),
  to: DateTime.utc(2026, 11, 15),
);

void main() {
  late WatererTestSession session;
  setUp(() async {
    session = WatererTestSession();
    await session.initialize();
  });
  tearDown(() => session.dispose());

  for (final kind in ['list', 'detail', 'history']) {
    test(
      '$kind uses the documented GET, fresh bearer token and language header',
      () async {
        final repository = _repository(
          session,
          MockClient((request) async {
            expect(request.method, 'GET');
            expect(request.headers['Authorization'], 'Bearer synthetic-token');
            expect(request.headers['Accept-Language'], 'es-419');
            expect(request.followRedirects, isFalse);
            expect(request.body, isEmpty);
            expect(request.url.path, switch (kind) {
              'list' => '/api/v1/ranches/$watererRanchA/water-troughs/status',
              'detail' =>
                '/api/v1/ranches/$watererRanchA/water-troughs/$watererId/status',
              _ => '/api/v1/water-controllers/$watererControllerId/readings',
            });
            if (kind == 'history') {
              expect(request.url.queryParameters, {
                'from': _query.from.toIso8601String(),
                'to': _query.to.toIso8601String(),
                'page': '1',
                'pageSize': '20',
              });
            } else {
              expect(request.url.hasQuery, isFalse);
            }
            return http.Response(jsonEncode(_payload(kind)), 200);
          }),
        );
        await _call(repository, kind);
        await _call(repository, kind);
        expect(session.identity.idTokenCalls, 2);
      },
    );

    for (final (status, expected) in [
      (
        400,
        kind == 'history'
            ? MonitoringFailureCode.invalidHistoryQuery
            : MonitoringFailureCode.unknown,
      ),
      (401, MonitoringFailureCode.unauthenticated),
      (403, MonitoringFailureCode.forbidden),
      (404, MonitoringFailureCode.notFound),
      (429, MonitoringFailureCode.serviceUnavailable),
      (503, MonitoringFailureCode.serviceUnavailable),
      (302, MonitoringFailureCode.unknown),
    ]) {
      test(
        '$kind maps HTTP $status without exposing response bodies or retrying',
        () async {
          var calls = 0;
          final repository = _repository(
            session,
            MockClient((_) async {
              calls++;
              return http.Response(
                'sensitive server diagnostic',
                status,
                headers: {'location': 'https://other.example.test'},
              );
            }),
          );
          await expectLater(
            _call(repository, kind),
            throwsA(_failure(expected)),
          );
          expect(calls, 1);
        },
      );
    }

    test(
      '$kind rejects a ranch switch during token acquisition without sending',
      () async {
        var calls = 0;
        final repository = _repository(
          session,
          MockClient((_) async {
            calls++;
            return http.Response(jsonEncode(_payload(kind)), 200);
          }),
        );
        final future = _call(repository, kind);
        session.selection.select(watererRanchB);
        await expectLater(
          future,
          throwsA(_failure(MonitoringFailureCode.contextUnavailable)),
        );
        expect(calls, 0);
      },
    );

    test('$kind rejects a response after a ranch switch', () async {
      final response = Completer<http.Response>();
      final started = Completer<void>();
      final repository = _repository(
        session,
        MockClient((_) {
          started.complete();
          return response.future;
        }),
      );
      final pending = _call(repository, kind);
      await started.future;
      session.selection.select(watererRanchB);
      response.complete(http.Response(jsonEncode(_payload(kind)), 200));
      await expectLater(
        pending,
        throwsA(_failure(MonitoringFailureCode.contextUnavailable)),
      );
    });

    test('$kind sanitizes transport failures and malformed JSON', () async {
      final offline = _repository(
        session,
        MockClient(
          (_) async => throw http.ClientException('private network details'),
        ),
      );
      await expectLater(
        _call(offline, kind),
        throwsA(_failure(MonitoringFailureCode.network)),
      );
      final malformed = _repository(
        session,
        MockClient((_) async => http.Response('{bad json', 200)),
      );
      await expectLater(
        _call(malformed, kind),
        throwsA(_failure(MonitoringFailureCode.invalidResponse)),
      );
    });
  }

  test(
    'preserves every server status and separate capture, receipt and communication times',
    () async {
      for (final (wire, expected) in [
        ('NoController', WaterControllerStatus.noController),
        ('NoReadings', WaterControllerStatus.noReadings),
        ('Communicating', WaterControllerStatus.communicating),
        ('NoCommunication', WaterControllerStatus.noCommunication),
      ]) {
        final payload = _status()..['controllerStatus'] = wire;
        final result = await _repository(
          session,
          _json(payload),
        ).detail(watererRanchA, watererId);
        expect(result.controllerStatus, expected);
        expect(result.latestReading!.capturedAt, DateTime.utc(2026, 11, 14, 5));
        expect(
          result.latestReading!.receivedAt,
          DateTime.utc(2026, 11, 14, 11),
        );
        expect(result.lastCommunicationAt, DateTime.utc(2026, 11, 14, 12));
      }
      for (final (wire, expected) in [
        ('NotConfigured', WaterRangeStatus.notConfigured),
        ('Unavailable', WaterRangeStatus.unavailable),
        ('BelowRange', WaterRangeStatus.belowRange),
        ('WithinRange', WaterRangeStatus.withinRange),
        ('AboveRange', WaterRangeStatus.aboveRange),
      ]) {
        final result = await _repository(
          session,
          _json(_status()..['rangeStatus'] = wire),
        ).detail(watererRanchA, watererId);
        expect(result.rangeStatus, expected);
      }
      final invalid = _status()
        ..['measurementStatus'] = 'Invalid'
        ..['rangeStatus'] = 'Unavailable';
      (invalid['latestReading'] as Map<String, Object?>)['isValid'] = false;
      final result = await _repository(
        session,
        _json(invalid),
      ).detail(watererRanchA, watererId);
      expect(result.measurementStatus, WaterMeasurementStatus.invalid);
      expect(result.latestReading!.isValid, isFalse);
      expect(result.latestReading!.temperatureCelsius, 16.5);
    },
  );

  test(
    'preserves null measurements and historical readings without an assigned controller',
    () async {
      final absent = _status()
        ..['latestReading'] = null
        ..['measurementStatus'] = 'Unavailable'
        ..['controllerStatus'] = 'NoReadings'
        ..['rangeStatus'] = 'Unavailable'
        ..['lastCommunicationAt'] = null;
      expect(
        (await _repository(
          session,
          _json(absent),
        ).detail(watererRanchA, watererId)).latestReading,
        isNull,
      );
      final historical = _status()
        ..['controllerId'] = null
        ..['controllerAssignedAt'] = null
        ..['controllerStatus'] = 'NoController';
      final result = await _repository(
        session,
        _json(historical),
      ).detail(watererRanchA, watererId);
      expect(result.controllerId, isNull);
      expect(result.latestReading, isNotNull);
    },
  );

  test(
    'rejects foreign identities, duplicate troughs and undocumented enum values',
    () async {
      for (final payload in [
        {
          'ranchId': watererRanchB,
          'items': [_status()],
        },
        {
          'ranchId': watererRanchA,
          'items': [_status(), _status()],
        },
        {
          'ranchId': watererRanchA,
          'items': [_status()..['controllerStatus'] = 'Online'],
        },
        {
          'ranchId': watererRanchA,
          'items': [_status()..['measurementStatus'] = 'Estimated'],
        },
        {
          'ranchId': watererRanchA,
          'items': [_status()..['rangeStatus'] = 'Unknown'],
        },
      ]) {
        await expectLater(
          _repository(session, _json(payload)).list(watererRanchA),
          throwsA(_failure(MonitoringFailureCode.invalidResponse)),
        );
      }
      await expectLater(
        _repository(
          session,
          _json(_status()..['waterTroughId'] = watererRanchB),
        ).detail(watererRanchA, watererId),
        throwsA(_failure(MonitoringFailureCode.invalidResponse)),
      );
      final foreignReading = _status();
      (foreignReading['latestReading'] as Map<String, Object?>)['ranchId'] =
          watererRanchB;
      await expectLater(
        _repository(
          session,
          _json(foreignReading),
        ).detail(watererRanchA, watererId),
        throwsA(_failure(MonitoringFailureCode.invalidResponse)),
      );
    },
  );

  test(
    'history validates metadata, units, ordering, interval, controller and ranch',
    () async {
      for (final mutate in <void Function(Map<String, Object?>)>[
        (p) => p['controllerId'] = watererRanchB,
        (p) => p['page'] = 2,
        (p) => p['pageSize'] = 100,
        (p) => p['from'] = '2026-11-13T00:00:00Z',
        (p) => p['totalCount'] = -1,
        (p) => (p['items'] as List).first['ranchId'] = watererRanchB,
        (p) => (p['items'] as List).first['controllerId'] = watererRanchB,
        (p) => (p['items'] as List).first['capturedAt'] = _query.to
            .toIso8601String(),
        (p) =>
            (p['items'] as List).first['capturedAt'] = '2026-11-14T25:00:00Z',
        (p) => (p['items'] as List).first['capturedAt'] = '2026-11-14T05:00:00',
        (p) => (p['items'] as List).first['temperatureUnit'] = 'Fahrenheit',
        (p) => (p['items'] as List).first['heaterState'] = 'Unknown',
        (p) => (p['items'] as List).first['origin'] = 'Mobile',
        (p) => p['items'] = [_reading(), _reading()],
      ]) {
        final payload = _history();
        mutate(payload);
        await expectLater(
          _repository(
            session,
            _json(payload),
          ).history(watererRanchA, watererControllerId, _query),
          throwsA(_failure(MonitoringFailureCode.invalidResponse)),
        );
      }
    },
  );

  test(
    'controller history allows historical trough assignments and empty offset pages',
    () async {
      final payload = _history();
      (payload['items'] as List).first['waterTroughId'] = watererRanchB;
      final repository = _repository(session, _json(payload));
      expect(
        (await repository.history(
          watererRanchA,
          watererControllerId,
          _query,
        )).items.single.waterTroughId,
        watererRanchB,
      );
      final empty = _history()
        ..['page'] = 2
        ..['totalCount'] = 0
        ..['items'] = [];
      expect(
        (await _repository(
          session,
          _json(empty),
        ).history(watererRanchA, watererControllerId, _query.atPage(2))).items,
        isEmpty,
      );
    },
  );

  test(
    'validates query and identifiers before HTTP and fails closed for other ranches',
    () async {
      var calls = 0;
      final repository = _repository(
        session,
        MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      await expectLater(
        repository.list(watererRanchB),
        throwsA(_failure(MonitoringFailureCode.contextUnavailable)),
      );
      await expectLater(
        repository.detail(watererRanchA, '../other'),
        throwsA(_failure(MonitoringFailureCode.notFound)),
      );
      await expectLater(
        repository.history(
          watererRanchA,
          watererControllerId,
          _query.atPage(0),
        ),
        throwsA(_failure(MonitoringFailureCode.invalidHistoryQuery)),
      );
      await expectLater(
        const RestWatererRepository(api: null).list(watererRanchA),
        throwsA(_failure(MonitoringFailureCode.configuration)),
      );
      expect(calls, 0);
    },
  );
}

RestWatererRepository _repository(
  WatererTestSession session,
  http.Client client,
) => RestWatererRepository(
  api: MonitoringApiClient(
    baseUri: Uri.parse('https://api.example.test/api/v1'),
    client: client,
    session: session.access,
    languageTag: () => 'es-419',
  ),
);

Future<Object> _call(RestWatererRepository repository, String kind) async =>
    switch (kind) {
      'list' => repository.list(watererRanchA),
      'detail' => repository.detail(watererRanchA, watererId),
      _ => repository.history(watererRanchA, watererControllerId, _query),
    };

Matcher _failure(MonitoringFailureCode code) =>
    isA<MonitoringFailure>().having((failure) => failure.code, 'code', code);
MockClient _json(Object payload) =>
    MockClient((_) async => http.Response(jsonEncode(payload), 200));
Object _payload(String kind) => switch (kind) {
  'list' => {
    'ranchId': watererRanchA,
    'items': [_status()],
  },
  'detail' => _status(),
  _ => _history(),
};
Map<String, Object?> _status() => {
  'waterTroughId': watererId,
  'name': 'Synthetic trough',
  'lotId': null,
  'minimumCelsius': 10,
  'maximumCelsius': 20,
  'controllerStatus': 'Communicating',
  'controllerId': watererControllerId,
  'controllerAssignedAt': '2026-11-01T08:00:00Z',
  'lastCommunicationAt': '2026-11-14T12:00:00Z',
  'measurementStatus': 'Valid',
  'rangeStatus': 'WithinRange',
  'latestReading': _reading(),
  'evaluatedAt': '2026-11-14T12:00:00Z',
};
Map<String, Object?> _reading() => {
  'id': 'e5555555-5555-4555-8555-555555555555',
  'readingId': 'e5555555-5555-4555-8555-555555555555',
  'controllerId': watererControllerId,
  'waterTroughId': watererId,
  'ranchId': watererRanchA,
  'gatewayId': 'f6666666-6666-4666-8666-666666666666',
  'temperature': 16.5,
  'temperatureUnit': 'Celsius',
  'isValid': true,
  'heaterState': 'On',
  'capturedAt': '2026-11-14T05:00:00Z',
  'receivedAt': '2026-11-14T11:00:00Z',
  'origin': 'EdgeGateway',
};
Map<String, Object?> _history() => {
  'controllerId': watererControllerId,
  'from': _query.from.toIso8601String(),
  'to': _query.to.toIso8601String(),
  'page': 1,
  'pageSize': 20,
  'totalCount': 1,
  'items': [_reading()],
};
