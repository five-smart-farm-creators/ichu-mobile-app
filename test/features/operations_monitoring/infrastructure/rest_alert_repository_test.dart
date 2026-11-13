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
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/alert_search.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/monitoring_failure.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/ranch_alert.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/infrastructure/http/monitoring_api_client.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/infrastructure/repositories/rest_alert_repository.dart';

import '../../../support/fake_iam_repositories.dart';

void main() {
  group('RestAlertRepository', () {
    late _Harness harness;

    setUp(() async {
      harness = _Harness();
      await harness.initialize();
    });
    tearDown(() => harness.dispose());

    test(
      'sends a fixed ranch-scoped GET with canonical paging and status',
      () async {
        final requests = <http.Request>[];
        final repository = _repository(
          harness,
          MockClient((request) async {
            requests.add(request);
            return http.Response(
              jsonEncode(
                _page(<Map<String, Object?>>[], page: 2, pageSize: 30),
              ),
              200,
            );
          }),
        );

        final page = await repository.search(
          _ranchA,
          const AlertSearch(
            status: AlertStatus.acknowledged,
            page: 2,
            pageSize: 30,
          ),
        );
        await repository.search(
          _ranchA,
          const AlertSearch(
            status: AlertStatus.acknowledged,
            page: 2,
            pageSize: 30,
          ),
        );

        expect(repository.isConfigured, isTrue);
        expect(page.items, isEmpty);
        expect(requests, hasLength(2));
        expect(harness.identity.idTokenCalls, 2);
        for (final request in requests) {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/ranches/$_ranchA/alerts');
          expect(request.url.queryParameters, <String, String>{
            'status': 'Acknowledged',
            'page': '2',
            'pageSize': '30',
          });
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

    test('omits a null status and accepts an empty first page', () async {
      late http.Request request;
      final repository = _repository(
        harness,
        MockClient((incoming) async {
          request = incoming;
          return http.Response(
            jsonEncode(_page(<Map<String, Object?>>[])),
            200,
          );
        }),
      );

      final page = await repository.search(_ranchA, const AlertSearch());

      expect(request.url.queryParameters, <String, String>{
        'page': '1',
        'pageSize': '20',
      });
      expect(request.url.query, isNot(contains('status')));
      expect(page.page, 1);
      expect(page.pageSize, 20);
      expect(page.totalCount, 0);
      expect(page.items, isEmpty);
      expect(() => page.items.add(_alertModel()), throwsUnsupportedError);
    });

    test(
      'maps exact enum values, all alert types, nullable data and real zeroes',
      () async {
        final temperature = _alert()
          ..['raisedAt'] = '9999-12-31T23:59:59.1234567+00:00'
          ..['receivedAt'] = '9999-12-31T23:59:59.1234567Z'
          ..['futureField'] = 'ignored';
        final activity =
            _alert(id: _alertId2, type: 'Activity', severity: 'Informative')
              ..['unit'] = 'index'
              ..['detectedValue'] = 1.2
              ..['thresholdMinValue'] = 0.5
              ..['thresholdMaxValue'] = 1;
        final geofence =
            _alert(id: _alertId3, type: 'Geofence', severity: 'Critical')
              ..['unit'] = null
              ..['detectedValue'] = null
              ..['thresholdMinValue'] = null
              ..['thresholdMaxValue'] = null
              ..['geofenceId'] = _geofenceId
              ..['latitude'] = 0
              ..['longitude'] = 0
              ..['distanceToBoundaryMeters'] = 0
              ..['clearedAt'] = '2026-11-12T10:00:00Z'
              ..['exitDurationSeconds'] = 0;
        final repository = _repository(
          harness,
          MockClient(
            (_) async => http.Response(
              jsonEncode(_page([temperature, activity, geofence], pageSize: 3)),
              200,
            ),
          ),
        );

        final page = await repository.search(
          _ranchA,
          const AlertSearch(pageSize: 3),
        );

        expect(page.totalCount, 3);
        expect(page.items[0].type, AlertType.temperature);
        expect(page.items[0].severity, AlertSeverity.warning);
        expect(page.items[0].status, AlertStatus.pending);
        expect(page.items[0].origin, AlertOrigin.edgeGateway);
        expect(page.items[0].detectedValue, 40.2);
        expect(page.items[0].raisedAt.year, 9999);
        expect(page.items[0].raisedAt.isUtc, isTrue);
        expect(page.items[0].configurationRevision, 2);
        expect(page.items[1].type, AlertType.activity);
        expect(page.items[1].unit, 'index');
        expect(page.items[1].detectedValue, 1.2);
        expect(page.items[1].thresholdMinValue, 0.5);
        expect(page.items[1].thresholdMaxValue, 1);
        expect(page.items[2].type, AlertType.geofence);
        expect(page.items[2].unit, isNull);
        expect(page.items[2].latitude, 0);
        expect(page.items[2].longitude, 0);
        expect(page.items[2].distanceToBoundaryMeters, 0);
        expect(page.items[2].clearedAt, DateTime.utc(2026, 11, 12, 10));
        expect(page.items[2].exitDurationSeconds, 0);
        expect(page.items[2].acknowledgedAt, isNull);
        expect(page.items[2].acknowledgedBy, isNull);
        expect(page.items[2].finding, isNull);
        expect(page.items[2].action, isNull);
      },
    );

    test(
      'maps acknowledged metadata and the Int64 configuration boundary',
      () async {
        final payloadAlert = _alert()
          ..['status'] = 'Acknowledged'
          ..['acknowledgedAt'] = '2026-11-12T10:00:00-05:00'
          ..['acknowledgedBy'] = _authorId
          ..['finding'] = 'Checked'
          ..['action'] = null
          ..['responseTimeSeconds'] = 18000
          ..['configurationRevision'] = 9223372036854775807
          ..['version'] = 2;
        final repository = _repository(
          harness,
          MockClient(
            (_) async => http.Response(jsonEncode(_page([payloadAlert])), 200),
          ),
        );

        final alert = (await repository.search(
          _ranchA,
          const AlertSearch(),
        )).items.single;

        expect(alert.status, AlertStatus.acknowledged);
        expect(alert.acknowledgedAt, DateTime.utc(2026, 11, 12, 15));
        expect(alert.acknowledgedBy, _authorId);
        expect(alert.finding, 'Checked');
        expect(alert.action, isNull);
        expect(alert.responseTimeSeconds, 18000);
        expect(alert.configurationRevision, 9223372036854775807);
        expect(alert.version, 2);
        expect(alert.readingIds, <String>[_readingId]);
        expect(() => alert.readingIds.add(_readingId2), throwsUnsupportedError);
      },
    );

    test(
      'accepts concurrent count changes without fabricating count consistency',
      () async {
        final repository = _repository(
          harness,
          MockClient((_) async {
            final body = _page([_alert(), _alert(id: _alertId2)], pageSize: 2)
              ..['totalCount'] = 1;
            return http.Response(jsonEncode(body), 200);
          }),
        );

        final page = await repository.search(
          _ranchA,
          const AlertSearch(pageSize: 2),
        );

        expect(page.totalCount, 1);
        expect(page.items, hasLength(2));
      },
    );

    test(
      'preserves repeated evidence IDs because their device identities are not in the DTO',
      () async {
        final repository = _repository(
          harness,
          MockClient(
            (_) async => http.Response(
              jsonEncode(
                _page([
                  _alert()
                    ..['readingIds'] = [_readingId, _readingId.toUpperCase()],
                ]),
              ),
              200,
            ),
          ),
        );
        final result = await repository.search(_ranchA, const AlertSearch());
        expect(result.items.single.readingIds, [
          _readingId,
          _readingId.toUpperCase(),
        ]);
      },
    );

    test(
      'rejects malformed, cross-ranch, duplicate and internally inconsistent DTOs',
      () async {
        final invalidPayloads = <Map<String, Object?> Function()>[
          () => _page([_alert()], pageSize: 2)..remove('totalCount'),
          () => _page([_alert()], pageSize: 2)..['page'] = '1',
          () => _page([_alert()], pageSize: 2)..['page'] = 2,
          () => _page([_alert()], pageSize: 2)..['pageSize'] = 21,
          () => _page([_alert()], pageSize: 2)..['items'] = <String, Object?>{},
          () => _page([_alert(), _alert(id: _alertId)], pageSize: 2),
          () => _page([_alert()..['ranchId'] = _ranchB], pageSize: 2),
          () => _page([_alert()..remove('clearedAt')], pageSize: 2),
          () => _page([_alert()..['type'] = 'temperature'], pageSize: 2),
          () => _page([_alert()..['severity'] = 'Warning '], pageSize: 2),
          () => _page([_alert()..['status'] = 'pending'], pageSize: 2),
          () => _page([_alert()..['origin'] = 'Telemetry'], pageSize: 2),
          () => _page([_alert()..['unit'] = 'Celsius'], pageSize: 2),
          () => _page([_alert()..['alertId'] = _zeroUuid], pageSize: 2),
          () => _page([_alert()..['deviceId'] = null], pageSize: 2),
          () => _page([_alert()..['configurationRevision'] = 0], pageSize: 2),
          () => _page([
            _alert()..['configurationRevision'] = 9223372036854775808.0,
          ], pageSize: 2),
          () => _page([_alert()..['version'] = 2147483648], pageSize: 2),
          () => _page([
            _alert()..['detectedValue'] = 'not-a-number',
          ], pageSize: 2),
          () => _page([
            _alert()..['raisedAt'] = '2026-02-30T00:00:00Z',
          ], pageSize: 2),
          () => _page([
            _alert()..['raisedAt'] = '2026-11-12T00:00:00',
          ], pageSize: 2),
          () => _page([
            _alert()..['raisedAt'] = '2026-11-12T00:00:00+14:01',
          ], pageSize: 2),
          () => _page([_alert()..['readingIds'] = <String>[]], pageSize: 2),
          () => _page([_alert(), _alert(id: _alertId2)], pageSize: 1),
          () => _page([_alert()..['geofenceId'] = _geofenceId], pageSize: 2),
          () => _page([
            _alert(type: 'Geofence')
              ..['unit'] = null
              ..['detectedValue'] = null
              ..['thresholdMinValue'] = null
              ..['thresholdMaxValue'] = null,
          ], pageSize: 2),
          () => _page([
            _alert()
              ..['status'] = 'Acknowledged'
              ..['acknowledgedAt'] = '2026-11-12T11:00:00Z',
          ], pageSize: 2),
        ];

        for (final buildPayload in invalidPayloads) {
          final repository = _repository(
            harness,
            MockClient(
              (_) async => http.Response(jsonEncode(buildPayload()), 200),
            ),
          );
          await _expectFailure(
            repository.search(_ranchA, const AlertSearch(pageSize: 2)),
            MonitoringFailureCode.invalidResponse,
          );
        }
      },
    );

    test(
      'maps safe HTTP failures and does not retry or follow redirects',
      () async {
        for (final (status, code) in <(int, MonitoringFailureCode)>[
          (400, MonitoringFailureCode.invalidSearch),
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
              expect(request.method, 'GET');
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
          await _expectFailure(
            repository.search(_ranchA, const AlertSearch()),
            code,
          );
          expect(requestCount, 1);
        }
      },
    );

    test(
      'rejects invalid local query and scope before token or HTTP access',
      () async {
        var requestCount = 0;
        final repository = _repository(
          harness,
          MockClient((_) async {
            requestCount++;
            return http.Response(
              jsonEncode(_page(<Map<String, Object?>>[])),
              200,
            );
          }),
        );
        final tokensBefore = harness.identity.idTokenCalls;

        await _expectFailure(
          repository.search(_ranchA, const AlertSearch(page: 0)),
          MonitoringFailureCode.invalidSearch,
        );
        await _expectFailure(
          repository.search(_ranchA, const AlertSearch(pageSize: 101)),
          MonitoringFailureCode.invalidSearch,
        );
        await _expectFailure(
          repository.search(_ranchB, const AlertSearch()),
          MonitoringFailureCode.contextUnavailable,
        );
        await _expectFailure(
          repository.search('bad-ranch', const AlertSearch()),
          MonitoringFailureCode.contextUnavailable,
        );
        expect(requestCount, 0);
        expect(harness.identity.idTokenCalls, tokensBefore);

        final unconfigured = RestAlertRepository(api: null);
        expect(unconfigured.isConfigured, isFalse);
        await _expectFailure(
          unconfigured.search(_ranchA, const AlertSearch()),
          MonitoringFailureCode.configuration,
        );
      },
    );

    test(
      'invalidates an A-to-B-to-A selection while the response is pending',
      () async {
        final responseStarted = Completer<void>();
        final pendingResponse = Completer<http.Response>();
        final repository = _repository(
          harness,
          MockClient((_) {
            responseStarted.complete();
            return pendingResponse.future;
          }),
        );

        final result = repository.search(_ranchA, const AlertSearch());
        await responseStarted.future;
        expect(harness.selection.select(_ranchB), isTrue);
        expect(harness.selection.select(_ranchA), isTrue);
        pendingResponse.complete(
          http.Response(jsonEncode(_page(<Map<String, Object?>>[])), 200),
        );

        await _expectFailure(result, MonitoringFailureCode.contextUnavailable);
      },
    );

    test(
      'does not send an old token if the ranch changes while it is fetched',
      () async {
        final pendingToken = Completer<String>();
        harness.authentication.tokenCompleter = pendingToken;
        var requestCount = 0;
        final repository = _repository(
          harness,
          MockClient((_) async {
            requestCount++;
            return http.Response(
              jsonEncode(_page(<Map<String, Object?>>[])),
              200,
            );
          }),
        );

        final result = repository.search(_ranchA, const AlertSearch());
        await Future<void>.delayed(Duration.zero);
        expect(harness.selection.select(_ranchB), isTrue);
        pendingToken.complete('sensitive-token');

        await _expectFailure(result, MonitoringFailureCode.contextUnavailable);
        expect(requestCount, 0);
      },
    );

    test(
      'does not send a token if the SDK identity changes while it is fetched',
      () async {
        final pendingToken = Completer<String>();
        harness.authentication.tokenCompleter = pendingToken;
        var requestCount = 0;
        final repository = _repository(
          harness,
          MockClient((_) async {
            requestCount++;
            return http.Response(
              jsonEncode(_page(<Map<String, Object?>>[])),
              200,
            );
          }),
        );

        final result = repository.search(_ranchA, const AlertSearch());
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

    test('uses the shared bounded response reader for alert lists', () async {
      final repository = _repository(
        harness,
        MockClient(
          (_) async => http.Response(
            List<String>.filled(1024 * 1024 + 1, ' ').join(),
            200,
          ),
        ),
      );

      await _expectFailure(
        repository.search(_ranchA, const AlertSearch()),
        MonitoringFailureCode.invalidResponse,
      );
    });

    test('rejects a non-finite JSON number from the shared decoder', () async {
      final body =
          '''
        {"page":1,"pageSize":20,"totalCount":1,"items":[{
          "alertId":"$_alertId","ranchId":"$_ranchA",
          "cattleId":"$_cattleId","deviceId":"$_deviceId",
          "gatewayId":"$_gatewayId","type":"Temperature",
          "severity":"Warning","status":"Pending",
          "origin":"EdgeGateway","raisedAt":"2026-11-12T10:00:00Z",
          "receivedAt":"2026-11-12T10:00:08Z","detectedValue":1e999,
          "unit":"celsius","thresholdMinValue":37.5,
          "thresholdMaxValue":39.5,"configurationRevision":2,
          "geofenceId":null,"latitude":null,"longitude":null,
          "distanceToBoundaryMeters":null,"clearedAt":null,
          "exitDurationSeconds":null,"acknowledgedAt":null,
          "acknowledgedBy":null,"finding":null,"action":null,
          "responseTimeSeconds":null,"version":1,
          "readingIds":["$_readingId"]}]}
        ''';
      final repository = _repository(
        harness,
        MockClient((_) async => http.Response(body, 200)),
      );

      await _expectFailure(
        repository.search(_ranchA, const AlertSearch()),
        MonitoringFailureCode.invalidResponse,
      );
    });
  });
}

const String _ranchA = '11111111-1111-4111-8111-111111111111';
const String _ranchB = '22222222-2222-4222-8222-222222222222';
const String _cattleId = '33333333-3333-4333-8333-333333333333';
const String _deviceId = '44444444-4444-4444-8444-444444444444';
const String _gatewayId = '55555555-5555-4555-8555-555555555555';
const String _alertId = '66666666-6666-4666-8666-666666666666';
const String _alertId2 = '77777777-7777-4777-8777-777777777777';
const String _alertId3 = '88888888-8888-4888-8888-888888888888';
const String _readingId = '99999999-9999-4999-8999-999999999999';
const String _readingId2 = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const String _geofenceId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const String _authorId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const String _zeroUuid = '00000000-0000-0000-0000-000000000000';
final Uri _baseUri = Uri.parse('https://api.example.test/api/v1');

Map<String, Object?> _page(
  List<Map<String, Object?>> items, {
  int page = 1,
  int? pageSize,
}) => <String, Object?>{
  'page': page,
  'pageSize': pageSize ?? 20,
  'totalCount': items.length,
  'items': items,
};

Map<String, Object?> _alert({
  String id = _alertId,
  String type = 'Temperature',
  String severity = 'Warning',
}) => <String, Object?>{
  'alertId': id,
  'ranchId': _ranchA,
  'cattleId': _cattleId,
  'deviceId': _deviceId,
  'type': type,
  'severity': severity,
  'status': 'Pending',
  'origin': 'EdgeGateway',
  'gatewayId': _gatewayId,
  'raisedAt': '2026-11-12T10:00:00Z',
  'receivedAt': '2026-11-12T10:00:08Z',
  'detectedValue': 40.2,
  'unit': 'celsius',
  'thresholdMinValue': 37.5,
  'thresholdMaxValue': 39.5,
  'configurationRevision': 2,
  'geofenceId': null,
  'latitude': null,
  'longitude': null,
  'distanceToBoundaryMeters': null,
  'clearedAt': null,
  'exitDurationSeconds': null,
  'acknowledgedAt': null,
  'acknowledgedBy': null,
  'finding': null,
  'action': null,
  'responseTimeSeconds': null,
  'version': 1,
  'readingIds': <String>[_readingId],
};

RanchAlert _alertModel() => RanchAlert(
  alertId: _alertId,
  ranchId: _ranchA,
  cattleId: _cattleId,
  deviceId: _deviceId,
  gatewayId: _gatewayId,
  type: AlertType.temperature,
  severity: AlertSeverity.warning,
  status: AlertStatus.pending,
  origin: AlertOrigin.edgeGateway,
  raisedAt: DateTime.utc(2026),
  receivedAt: DateTime.utc(2026),
  configurationRevision: 1,
  version: 1,
  readingIds: <String>[_readingId],
);

RestAlertRepository _repository(_Harness harness, http.Client client) =>
    RestAlertRepository(
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
          id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
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
