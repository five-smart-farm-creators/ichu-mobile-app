import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ichu_mobile_app/features/iam/application/facades/authorized_ranch_session.dart';
import 'package:ichu_mobile_app/features/iam/application/services/auth_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/authentication_lifecycle.dart';
import 'package:ichu_mobile_app/features/iam/application/services/ranch_selection_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_user.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_access.dart';
import 'package:ichu_mobile_app/features/iam/domain/repositories/authentication_repository.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/latest_telemetry.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/monitoring_failure.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/telemetry_history_query.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/infrastructure/http/monitoring_api_client.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/infrastructure/repositories/rest_monitoring_repository.dart';

import '../../../support/fake_iam_repositories.dart';

void main() {
  group('RestMonitoringRepository', () {
    late _Harness harness;

    setUp(() async {
      harness = _Harness();
      await harness.initialize();
    });
    tearDown(() => harness.dispose());

    test('maps an empty summary as unavailable values, not an error', () async {
      final repository = _repository(
        harness,
        MockClient(
          (_) async => http.Response(jsonEncode(_emptySummary()), 200),
        ),
      );

      final latest = await repository.latest(_ranchA, _cattleId);

      expect(latest.cattleId, _cattleId);
      expect(latest.origin, TelemetryOrigin.edgeGateway);
      expect(latest.lastReadingRecordedAt, isNull);
      expect(latest.bodyTemperature.isAvailable, isFalse);
      expect(latest.bodyTemperature.unit, TelemetryUnit.celsius);
      expect(latest.bodyTemperature.value, isNull);
      expect(latest.bodyTemperature.recordedAt, isNull);
      expect(latest.bodyTemperature.isStale, isNull);
      expect(latest.activityIndex.isAvailable, isFalse);
      expect(latest.ruminationMinutes.isAvailable, isFalse);
      expect(latest.lastKnownPosition.isAvailable, isFalse);
      expect(repository.isConfigured, isTrue);
    });

    test(
      'accepts a case-insensitive matching cattle UUID and unknown extra fields',
      () async {
        final payload = _emptySummary()
          ..['cattleId'] = _cattleId.toUpperCase()
          ..['futureField'] = <String, Object?>{'ignored': true};
        final repository = _repository(
          harness,
          MockClient((_) async => http.Response(jsonEncode(payload), 200)),
        );

        final latest = await repository.latest(_ranchA, _cattleId);

        expect(latest.cattleId, _cattleId.toUpperCase());
        expect(latest.origin, TelemetryOrigin.edgeGateway);
      },
    );

    test(
      'maps independent readings, UTC timestamps, stale flags and numeric bounds',
      () async {
        final payload = _emptySummary()
          ..['lastReadingRecordedAt'] = '2026-11-12T11:55:00.1234567+02:00'
          ..['bodyTemperature'] = <String, Object?>{
            'status': 'Available',
            'value': -273.15,
            'unit': 'celsius',
            'recordedAt': '2026-11-12T10:00:00-05:00',
            'isStale': true,
          }
          ..['activityIndex'] = <String, Object?>{
            'status': 'Available',
            'value': 0.125,
            'unit': 'index',
            'recordedAt': '2026-11-12T12:00:00Z',
            'isStale': false,
          }
          ..['ruminationMinutes'] = <String, Object?>{
            'status': 'Available',
            'value': 42.5,
            'unit': 'minutes',
            'recordedAt': '2026-11-12T11:00:00Z',
            'isStale': false,
          }
          ..['lastKnownPosition'] = <String, Object?>{
            'status': 'Available',
            'latitude': -90,
            'longitude': 180,
            'accuracyMeters': 0,
            'recordedAt': '2026-11-10T11:00:00.0000001Z',
            'isStale': true,
          };
        final repository = _repository(
          harness,
          MockClient((_) async => http.Response(jsonEncode(payload), 200)),
        );

        final latest = await repository.latest(_ranchA, _cattleId);

        expect(latest.evaluatedAt, DateTime.utc(2026, 11, 12, 12));
        expect(
          latest.lastReadingRecordedAt,
          DateTime.utc(2026, 11, 12, 9, 55, 0, 123, 456),
        );
        expect(latest.bodyTemperature.value, -273.15);
        expect(
          latest.bodyTemperature.recordedAt,
          DateTime.utc(2026, 11, 12, 15),
        );
        expect(latest.bodyTemperature.isStale, isTrue);
        expect(latest.activityIndex.value, 0.125);
        expect(latest.ruminationMinutes.value, 42.5);
        expect(latest.lastKnownPosition.latitude, -90);
        expect(latest.lastKnownPosition.longitude, 180);
        expect(latest.lastKnownPosition.accuracyMeters, 0);
        expect(latest.lastKnownPosition.isStale, isTrue);
      },
    );

    test(
      'allows available observations when the overall latest-reading time is null',
      () async {
        final payload = _emptySummary()
          ..['bodyTemperature'] = <String, Object?>{
            'status': 'Available',
            'value': 0,
            'unit': 'celsius',
            'recordedAt': '2026-11-12T12:00:00Z',
            'isStale': false,
          };
        final repository = _repository(
          harness,
          MockClient((_) async => http.Response(jsonEncode(payload), 200)),
        );

        final latest = await repository.latest(_ranchA, _cattleId);

        expect(latest.lastReadingRecordedAt, isNull);
        expect(latest.bodyTemperature.value, 0);
        expect(latest.bodyTemperature.isAvailable, isTrue);
      },
    );

    test('accepts both inclusive GPS coordinate endpoints', () async {
      final payload = _emptySummary()
        ..['lastKnownPosition'] = <String, Object?>{
          'status': 'Available',
          'latitude': 90,
          'longitude': -180,
          'accuracyMeters': 0,
          'recordedAt': '2026-11-12T12:00:00Z',
          'isStale': false,
        };
      final repository = _repository(
        harness,
        MockClient((_) async => http.Response(jsonEncode(payload), 200)),
      );

      final latest = await repository.latest(_ranchA, _cattleId);

      expect(latest.lastKnownPosition.latitude, 90);
      expect(latest.lastKnownPosition.longitude, -180);
    });

    test(
      'requires exact status, units, nullable fields and valid finite values',
      () async {
        final invalidBodies = <Map<String, Object?> Function()>[
          () => _emptySummary()..remove('lastReadingRecordedAt'),
          () => _emptySummary()..['origin'] = 'Collar',
          () => _emptySummary()..['cattleId'] = _otherCattleId,
          () => _emptySummary()..['evaluatedAt'] = '2026-02-30T00:00:00Z',
          () => _emptySummary()..['evaluatedAt'] = '2026-11-12T00:00:00',
          () => _emptySummary()..['evaluatedAt'] = '2026-11-12T00:00:00+14:01',
          () => _emptySummary()..['evaluatedAt'] = '2026-11-12T00:00:00+15:00',
          () => _emptySummary()
            ..['bodyTemperature'] = <String, Object?>{
              'status': 'Available',
              'value': 38.0,
              'unit': 'celsius',
              'recordedAt': null,
              'isStale': false,
            },
          () => _emptySummary()
            ..['bodyTemperature'] = <String, Object?>{
              'status': 'Fresh',
              'value': 38.0,
              'unit': 'celsius',
              'recordedAt': '2026-11-12T00:00:00Z',
              'isStale': false,
            },
          () => _emptySummary()
            ..['bodyTemperature'] = <String, Object?>{
              'status': 'Available',
              'value': 38.0,
              'unit': 'celsius',
              'recordedAt': '2026-11-12T00:00:00Z',
              'isStale': 0,
            },
          () => _emptySummary()
            ..['bodyTemperature'] = <String, Object?>{
              'status': 'Available',
              'value': 38.0,
              'unit': 'celsius',
              'isStale': false,
            },
          () => _emptySummary()
            ..['bodyTemperature'] = <String, Object?>{
              'status': 'Available',
              'value': 38.0,
              'unit': 'Celsius',
              'recordedAt': '2026-11-12T00:00:00Z',
              'isStale': false,
            },
          () => _emptySummary()
            ..['activityIndex'] = <String, Object?>{
              'status': 'Available',
              'value': -0.1,
              'unit': 'index',
              'recordedAt': '2026-11-12T00:00:00Z',
              'isStale': false,
            },
          () => _emptySummary()
            ..['ruminationMinutes'] = <String, Object?>{
              'status': 'Available',
              'value': -1,
              'unit': 'minutes',
              'recordedAt': '2026-11-12T00:00:00Z',
              'isStale': false,
            },
          () => _emptySummary()
            ..['bodyTemperature'] = <String, Object?>{
              'status': 'Available',
              'value': '38',
              'unit': 'celsius',
              'recordedAt': '2026-11-12T00:00:00Z',
              'isStale': false,
            },
          () => _emptySummary()
            ..['bodyTemperature'] = <String, Object?>{
              'status': 'Unavailable',
              'value': null,
              'unit': 'celsius',
              'recordedAt': null,
              'isStale': true,
            },
          () => _emptySummary()
            ..['lastKnownPosition'] = <String, Object?>{
              'status': 'Available',
              'latitude': 90.01,
              'longitude': 0,
              'accuracyMeters': 1,
              'recordedAt': '2026-11-12T00:00:00Z',
              'isStale': false,
            },
          () => _emptySummary()
            ..['lastKnownPosition'] = <String, Object?>{
              'status': 'Available',
              'latitude': 0,
              'longitude': -180.01,
              'accuracyMeters': 1,
              'recordedAt': '2026-11-12T00:00:00Z',
              'isStale': false,
            },
          () => _emptySummary()
            ..['lastKnownPosition'] = <String, Object?>{
              'status': 'Available',
              'latitude': 0,
              'longitude': 0,
              'accuracyMeters': -0.01,
              'recordedAt': '2026-11-12T00:00:00Z',
              'isStale': false,
            },
          () => _emptySummary()
            ..['lastKnownPosition'] = <String, Object?>{
              'status': 'Unavailable',
              'latitude': 0,
              'longitude': null,
              'accuracyMeters': null,
              'recordedAt': null,
              'isStale': null,
            },
          () => _emptySummary()
            ..['lastKnownPosition'] = <String, Object?>{
              'status': 'Available',
              'latitude': 90,
              'longitude': -180,
              'accuracyMeters': 0,
              'isStale': false,
            },
        ];

        for (final buildBody in invalidBodies) {
          final repository = _repository(
            harness,
            MockClient(
              (_) async => http.Response(jsonEncode(buildBody()), 200),
            ),
          );
          await _expectFailure(
            repository.latest(_ranchA, _cattleId),
            MonitoringFailureCode.invalidResponse,
          );
        }
      },
    );

    test(
      'sends only the fixed authenticated GET and fetches a fresh token each time',
      () async {
        final requests = <http.Request>[];
        final repository = _repository(
          harness,
          MockClient((request) async {
            requests.add(request);
            return http.Response(jsonEncode(_emptySummary()), 200);
          }),
        );

        await repository.latest(_ranchA, _cattleId);
        await repository.latest(_ranchA, _cattleId);

        expect(harness.identity.idTokenCalls, 2);
        expect(requests, hasLength(2));
        for (final request in requests) {
          expect(request.method, 'GET');
          expect(
            request.url.path,
            '/api/v1/ranches/$_ranchA/cattle/$_cattleId/telemetry/latest',
          );
          expect(request.url.hasQuery, isFalse);
          expect(request.body, isEmpty);
          expect(request.followRedirects, isFalse);
          expect(request.maxRedirects, 0);
          expect(request.headers['Authorization'], 'Bearer synthetic-token');
          expect(request.headers['Accept'], 'application/json');
          expect(request.headers['Accept-Language'], 'es-419');
          expect(request.headers.containsKey('Content-Type'), isFalse);
        }
      },
    );

    test(
      'sends the bounded authorized history query and maps its page',
      () async {
        final from = DateTime.utc(2026, 11, 12, 10);
        final to = DateTime.utc(2026, 11, 13, 10);
        final query = TelemetryHistoryQuery(
          from: from,
          to: to,
          page: 2,
          pageSize: 10,
        );
        http.Request? captured;
        final repository = _repository(
          harness,
          MockClient((request) async {
            captured = request;
            return http.Response(
              jsonEncode(
                _historyPayload(from: from, to: to, page: 2, pageSize: 10),
              ),
              200,
            );
          }),
        );

        final page = await repository.history(_ranchA, _cattleId, query);

        expect(captured!.method, 'GET');
        expect(
          captured!.url.path,
          '/api/v1/ranches/$_ranchA/cattle/$_cattleId/telemetry',
        );
        expect(captured!.url.queryParameters, <String, String>{
          'from': from.toIso8601String(),
          'to': to.toIso8601String(),
          'page': '2',
          'pageSize': '10',
        });
        expect(captured!.headers['Authorization'], 'Bearer synthetic-token');
        expect(captured!.headers['Accept-Language'], 'es-419');
        expect(page.cattleId, _cattleId);
        expect(page.from, from);
        expect(page.to, to);
        expect(page.page, 2);
        expect(page.pageSize, 10);
        expect(page.totalCount, 11);
        expect(page.items.single.bodyTemperature.value, 38.6);
        expect(page.items.single.batteryLevel.status.name, 'absent');
        expect(page.items.single.position.latitude, -13.5);
      },
    );

    test(
      'maps invalid backend history query status to a safe failure',
      () async {
        final from = DateTime.utc(2026, 11, 12);
        final to = DateTime.utc(2026, 11, 13);
        final repository = _repository(
          harness,
          MockClient((_) async => http.Response('', 400)),
        );

        await _expectFailure(
          repository.history(
            _ranchA,
            _cattleId,
            TelemetryHistoryQuery(from: from, to: to),
          ),
          MonitoringFailureCode.invalidHistoryQuery,
        );
      },
    );

    test(
      'rejects invalid IDs and ranch scope before token or HTTP access',
      () async {
        var requestCount = 0;
        final repository = _repository(
          harness,
          MockClient((_) async {
            requestCount++;
            return http.Response(jsonEncode(_emptySummary()), 200);
          }),
        );
        final tokensBefore = harness.identity.idTokenCalls;

        await _expectFailure(
          repository.latest('bad-ranch', _cattleId),
          MonitoringFailureCode.contextUnavailable,
        );
        await _expectFailure(
          repository.latest(_ranchA, 'bad-cattle'),
          MonitoringFailureCode.notFound,
        );
        await _expectFailure(
          repository.latest(_ranchB, _cattleId),
          MonitoringFailureCode.contextUnavailable,
        );
        final historyQuery = TelemetryHistoryQuery(
          from: DateTime.utc(2026, 11, 12),
          to: DateTime.utc(2026, 11, 13),
        );
        await _expectFailure(
          repository.history('bad-ranch', _cattleId, historyQuery),
          MonitoringFailureCode.contextUnavailable,
        );
        await _expectFailure(
          repository.history(_ranchA, 'bad-cattle', historyQuery),
          MonitoringFailureCode.notFound,
        );
        await _expectFailure(
          repository.history(_ranchB, _cattleId, historyQuery),
          MonitoringFailureCode.contextUnavailable,
        );
        expect(requestCount, 0);
        expect(harness.identity.idTokenCalls, tokensBefore);

        final unconfigured = RestMonitoringRepository(api: null);
        expect(unconfigured.isConfigured, isFalse);
        await _expectFailure(
          unconfigured.latest(_ranchA, _cattleId),
          MonitoringFailureCode.configuration,
        );

        expect(
          () => MonitoringApiClient(
            baseUri: Uri.parse('http://api.example.test/api/v1'),
            client: MockClient((_) async => http.Response('', 200)),
            session: harness.facade,
            languageTag: () => 'en-US',
          ),
          throwsA(
            isA<MonitoringFailure>().having(
              (failure) => failure.code,
              'code',
              MonitoringFailureCode.configuration,
            ),
          ),
        );
      },
    );

    test(
      'maps HTTP statuses without reading private error details or retrying',
      () async {
        for (final (status, code) in <(int, MonitoringFailureCode)>[
          (400, MonitoringFailureCode.unknown),
          (401, MonitoringFailureCode.unauthenticated),
          (403, MonitoringFailureCode.forbidden),
          (404, MonitoringFailureCode.notFound),
          (429, MonitoringFailureCode.serviceUnavailable),
          (503, MonitoringFailureCode.serviceUnavailable),
          (302, MonitoringFailureCode.unknown),
        ]) {
          var requestCount = 0;
          final repository = _repository(
            harness,
            MockClient((request) async {
              requestCount++;
              expect(request.followRedirects, isFalse);
              return http.Response(
                '{"title":"private backend detail"}',
                status,
                headers: <String, String>{
                  if (status == 302) 'location': 'https://evil.example/collect',
                },
              );
            }),
          );
          await _expectFailure(repository.latest(_ranchA, _cattleId), code);
          expect(requestCount, 1);
        }
      },
    );

    test('invalidates A-to-B-to-A selection during the response', () async {
      final responseStarted = Completer<void>();
      final pendingResponse = Completer<http.Response>();
      final repository = _repository(
        harness,
        MockClient((_) {
          responseStarted.complete();
          return pendingResponse.future;
        }),
      );

      final result = repository.latest(_ranchA, _cattleId);
      await responseStarted.future;
      expect(harness.selection.select(_ranchB), isTrue);
      expect(harness.selection.select(_ranchA), isTrue);
      pendingResponse.complete(http.Response(jsonEncode(_emptySummary()), 200));

      await _expectFailure(result, MonitoringFailureCode.contextUnavailable);
    });

    test(
      'does not send a token if scope changes while the token is fetched',
      () async {
        final pendingToken = Completer<String>();
        harness.authentication.tokenCompleter = pendingToken;
        var requestCount = 0;
        final repository = _repository(
          harness,
          MockClient((_) async {
            requestCount++;
            return http.Response(jsonEncode(_emptySummary()), 200);
          }),
        );

        final result = repository.latest(_ranchA, _cattleId);
        await Future<void>.delayed(Duration.zero);
        expect(harness.selection.select(_ranchB), isTrue);
        pendingToken.complete('sensitive-token');

        await _expectFailure(result, MonitoringFailureCode.contextUnavailable);
        expect(requestCount, 0);
      },
    );

    test(
      'does not send a token if the SDK identity drifts during token fetch',
      () async {
        final pendingToken = Completer<String>();
        harness.authentication.tokenCompleter = pendingToken;
        var requestCount = 0;
        final repository = _repository(
          harness,
          MockClient((_) async {
            requestCount++;
            return http.Response(jsonEncode(_emptySummary()), 200);
          }),
        );

        final result = repository.latest(_ranchA, _cattleId);
        await Future<void>.delayed(Duration.zero);
        harness.identity.emit(
          const AuthUser(
            uid: 'different-synthetic-uid',
            email: 'user@example.test',
            emailVerified: true,
          ),
        );
        pendingToken.complete('sensitive-token');

        await _expectFailure(result, MonitoringFailureCode.contextUnavailable);
        expect(requestCount, 0);
      },
    );

    test(
      'rejects malformed JSON, invalid UTF-8 and bodies larger than one MiB',
      () async {
        final invalidResponses = <http.Response>[
          http.Response('{broken', 200),
          http.Response.bytes(<int>[0xff, 0xfe], 200),
          http.Response(List<String>.filled(1024 * 1024 + 1, ' ').join(), 200),
        ];
        for (final response in invalidResponses) {
          final repository = _repository(
            harness,
            MockClient((_) async => response),
          );
          await _expectFailure(
            repository.latest(_ranchA, _cattleId),
            MonitoringFailureCode.invalidResponse,
          );
        }

        final nonFiniteNumber = _repository(
          harness,
          MockClient(
            (_) async => http.Response(
              '{"cattleId":"$_cattleId","evaluatedAt":"2026-11-12T12:00:00Z",'
              '"lastReadingRecordedAt":null,"origin":"EdgeGateway",'
              '"bodyTemperature":{"status":"Available","value":1e999,'
              '"unit":"celsius","recordedAt":"2026-11-12T12:00:00Z","isStale":false},'
              '"activityIndex":{"status":"Unavailable","value":null,"unit":"index",'
              '"recordedAt":null,"isStale":null},"ruminationMinutes":{"status":"Unavailable",'
              '"value":null,"unit":"minutes","recordedAt":null,"isStale":null},'
              '"lastKnownPosition":{"status":"Unavailable","latitude":null,"longitude":null,'
              '"accuracyMeters":null,"recordedAt":null,"isStale":null}}',
              200,
            ),
          ),
        );
        await _expectFailure(
          nonFiniteNumber.latest(_ranchA, _cattleId),
          MonitoringFailureCode.invalidResponse,
        );
      },
    );

    test(
      'response timeout does not await stalled stream cancellation',
      () async {
        final cleanup = Completer<void>();
        final subscribed = Completer<void>();
        final body = StreamController<List<int>>(
          onListen: subscribed.complete,
          onCancel: () => cleanup.future,
        );
        final repository = RestMonitoringRepository(
          api: MonitoringApiClient(
            baseUri: _baseUri,
            client: _StreamClient(
              (_) async => http.StreamedResponse(body.stream, 200),
            ),
            session: harness.facade,
            languageTag: () => 'en-US',
            timeout: const Duration(milliseconds: 20),
          ),
        );
        try {
          final request = repository.latest(_ranchA, _cattleId);
          await subscribed.future;
          await _expectFailure(
            request.timeout(const Duration(seconds: 1)),
            MonitoringFailureCode.network,
          );
          expect(cleanup.isCompleted, isFalse);
        } finally {
          cleanup.complete();
          await body.close();
        }
      },
    );

    test(
      'bounds request and response waits and maps transport errors safely',
      () async {
        final neverCompletes = Completer<http.StreamedResponse>();
        final requestTimeout = RestMonitoringRepository(
          api: MonitoringApiClient(
            baseUri: _baseUri,
            client: _StreamClient((_) => neverCompletes.future),
            session: harness.facade,
            languageTag: () => 'en-US',
            timeout: const Duration(milliseconds: 20),
          ),
        );
        await _expectFailure(
          requestTimeout.latest(_ranchA, _cattleId),
          MonitoringFailureCode.network,
        );
        neverCompletes.complete(
          http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode('{}')),
            200,
          ),
        );

        final bodySubscribed = Completer<void>();
        final body = StreamController<List<int>>(
          onListen: bodySubscribed.complete,
        );
        final bodyTimeout = RestMonitoringRepository(
          api: MonitoringApiClient(
            baseUri: _baseUri,
            client: _StreamClient(
              (_) async => http.StreamedResponse(body.stream, 200),
            ),
            session: harness.facade,
            languageTag: () => 'en-US',
            timeout: const Duration(milliseconds: 20),
          ),
        );
        final pendingResult = bodyTimeout.latest(_ranchA, _cattleId);
        await bodySubscribed.future;
        await _expectFailure(pendingResult, MonitoringFailureCode.network);
        await body.close();

        final transportFailure = _repository(
          harness,
          MockClient((_) async => throw http.ClientException('private detail')),
        );
        await _expectFailure(
          transportFailure.latest(_ranchA, _cattleId),
          MonitoringFailureCode.network,
        );
      },
    );
  });
}

const String _ranchA = '11111111-1111-4111-8111-111111111111';
const String _ranchB = '22222222-2222-4222-8222-222222222222';
const String _cattleId = '33333333-3333-4333-8333-333333333333';
const String _otherCattleId = '44444444-4444-4444-8444-444444444444';
final Uri _baseUri = Uri.parse('https://api.example.test/api/v1');

Map<String, Object?> _historyPayload({
  required DateTime from,
  required DateTime to,
  int page = 1,
  int pageSize = 20,
}) => <String, Object?>{
  'cattleId': _cattleId,
  'from': from.toIso8601String(),
  'to': to.toIso8601String(),
  'oldestRetainedRecordedAt': '2026-10-01T00:00:00Z',
  'page': page,
  'pageSize': pageSize,
  'totalCount': 11,
  'items': <Object?>[
    <String, Object?>{
      'readingId': '55555555-5555-4555-8555-555555555555',
      'deviceId': '66666666-6666-4666-8666-666666666666',
      'cattleId': _cattleId,
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

Map<String, Object?> _emptySummary() => <String, Object?>{
  'cattleId': _cattleId,
  'evaluatedAt': '2026-11-12T12:00:00Z',
  'lastReadingRecordedAt': null,
  'origin': 'EdgeGateway',
  'bodyTemperature': <String, Object?>{
    'status': 'Unavailable',
    'value': null,
    'unit': 'celsius',
    'recordedAt': null,
    'isStale': null,
  },
  'activityIndex': <String, Object?>{
    'status': 'Unavailable',
    'value': null,
    'unit': 'index',
    'recordedAt': null,
    'isStale': null,
  },
  'ruminationMinutes': <String, Object?>{
    'status': 'Unavailable',
    'value': null,
    'unit': 'minutes',
    'recordedAt': null,
    'isStale': null,
  },
  'lastKnownPosition': <String, Object?>{
    'status': 'Unavailable',
    'latitude': null,
    'longitude': null,
    'accuracyMeters': null,
    'recordedAt': null,
    'isStale': null,
  },
};

RestMonitoringRepository _repository(_Harness harness, http.Client client) =>
    RestMonitoringRepository(
      api: MonitoringApiClient(
        baseUri: _baseUri,
        client: client,
        session: harness.facade,
        languageTag: () => 'es-419',
        timeout: const Duration(seconds: 1),
      ),
    );

Future<void> _expectFailure(
  Future<Object?> operation,
  MonitoringFailureCode code,
) async {
  await expectLater(
    operation,
    throwsA(
      isA<MonitoringFailure>().having((failure) => failure.code, 'code', code),
    ),
  );
}

RanchAccess _ranch(String id) => RanchAccess(
  ranchId: id,
  scope: AccessScope.read,
  name: 'Ranch $id',
  region: 'Synthetic region',
  district: 'Synthetic district',
);

final class _Harness {
  _Harness()
    : identity = FakeAuthenticationRepository(),
      accounts = FakeAccountRepository(
        account: const IamAccount(
          id: '99999999-9999-4999-8999-999999999999',
          email: 'user@example.test',
          role: AccountRole.ranchManager,
          status: 'Active',
        ),
        ranches: <RanchAccess>[_ranch(_ranchA), _ranch(_ranchB)],
      ) {
    lifecycle = AuthenticationLifecycle(identity);
    auth = AuthService(authentication: lifecycle, accounts: accounts);
    selection = RanchSelectionService(session: auth);
    authentication = _TokenAuthentication(identity);
    facade = AuthorizedRanchSession(
      session: auth,
      selection: selection,
      authentication: authentication,
    );
  }

  final FakeAuthenticationRepository identity;
  final FakeAccountRepository accounts;
  late final AuthenticationLifecycle lifecycle;
  late final AuthService auth;
  late final RanchSelectionService selection;
  late final _TokenAuthentication authentication;
  late final AuthorizedRanchSession facade;

  Future<void> initialize() async {
    await auth.initialize();
    expect(selection.select(_ranchA), isTrue);
    expect(facade.context?.ranchId, _ranchA);
  }

  void dispose() {
    facade.dispose();
    selection.dispose();
    auth.dispose();
    lifecycle.dispose();
    unawaited(identity.close());
  }
}

final class _TokenAuthentication implements AuthenticationRepository {
  _TokenAuthentication(this._delegate);

  final AuthenticationRepository _delegate;
  Completer<String>? tokenCompleter;

  @override
  bool get isConfigured => _delegate.isConfigured;

  @override
  AuthUser? get currentUser => _delegate.currentUser;

  @override
  Stream<AuthUser?> observeAuthState() => _delegate.observeAuthState();

  @override
  Future<AuthUser> signIn(String email, String password) =>
      _delegate.signIn(email, password);

  @override
  Future<AuthUser?> reloadUser() => _delegate.reloadUser();

  @override
  Future<String> idToken({bool forceRefresh = false}) =>
      tokenCompleter?.future ?? _delegate.idToken(forceRefresh: forceRefresh);

  @override
  Future<void> sendPasswordReset(String email) =>
      _delegate.sendPasswordReset(email);

  @override
  Future<void> signOut() => _delegate.signOut();
}

final class _StreamClient extends http.BaseClient {
  _StreamClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _handler(request);
}
