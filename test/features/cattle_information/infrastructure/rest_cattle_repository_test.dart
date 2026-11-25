import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle_failure.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle_search.dart';
import 'package:ichu_mobile_app/features/cattle_information/infrastructure/http/cattle_api_client.dart';
import 'package:ichu_mobile_app/features/cattle_information/infrastructure/repositories/rest_cattle_repository.dart';
import 'package:ichu_mobile_app/features/iam/application/facades/authorized_ranch_session.dart';
import 'package:ichu_mobile_app/features/iam/application/services/auth_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/authentication_lifecycle.dart';
import 'package:ichu_mobile_app/features/iam/application/services/ranch_selection_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_user.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_access.dart';
import 'package:ichu_mobile_app/features/iam/domain/repositories/authentication_repository.dart';

import '../../../support/fake_iam_repositories.dart';

void main() {
  group('RestCattleRepository', () {
    late _Harness harness;

    setUp(() async {
      harness = _Harness();
      await harness.initialize();
    });
    tearDown(() => harness.dispose());

    test(
      'searches one ranch with encoded exact filters using GET only',
      () async {
        final requests = <http.Request>[];
        final repository = RestCattleRepository(
          api: _api(
            harness,
            MockClient((request) async {
              requests.add(request);
              return http.Response(jsonEncode(<Object?>[_activeCattle()]), 200);
            }),
          ),
        );

        final cattle = await repository.search(
          _ranchA,
          const CattleSearch(
            earTag: '  PE&A? #1  ',
            status: CattleStatus.inactive,
            page: 2,
            pageSize: 3,
          ),
        );

        expect(cattle, hasLength(1));
        expect(cattle.single.earTag, 'PE-0001');
        final request = requests.single;
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/ranches/$_ranchA/cattle');
        expect(request.url.queryParameters, <String, String>{
          'earTag': 'PE&A? #1',
          'status': 'Inactive',
          'page': '2',
          'pageSize': '3',
        });
        expect(request.body, isEmpty);
        expect(request.followRedirects, isFalse);
        expect(request.headers['Authorization'], 'Bearer synthetic-token');
        expect(request.headers['Accept'], 'application/json');
        expect(request.headers['Accept-Language'], 'es-419');
        expect(request.headers.containsKey('Content-Type'), isFalse);
        expect(repository.isConfigured, isTrue);
      },
    );

    test(
      'maps a full detail snapshot, enum names, date-only values and UTC offset',
      () async {
        final requests = <http.Request>[];
        final repository = RestCattleRepository(
          api: _api(
            harness,
            MockClient((request) async {
              requests.add(request);
              return http.Response(
                jsonEncode(<String, Object?>{
                  'cattle': _inactiveCattle(),
                  'device': <String, Object?>{
                    'isAvailable': true,
                    'collarId': _collarId,
                    'lastReadingReceivedAt': '2026-11-12T11:05:06.123-05:00',
                  },
                }),
                200,
              );
            }),
          ),
        );

        final profile = await repository.profile(_ranchA, _cattleId);

        expect(requests.single.method, 'GET');
        expect(
          requests.single.url.path,
          '/api/v1/ranches/$_ranchA/cattle/$_cattleId',
        );
        expect(profile.cattle.breed, CattleBreed.crossbred);
        expect(profile.cattle.sex, CattleSex.male);
        expect(profile.cattle.currentStage, CattleStage.fatteningBull);
        expect(profile.cattle.status, CattleStatus.inactive);
        expect(profile.cattle.exitReason, CattleExitReason.culling);
        expect(profile.cattle.birthDate.year, 2020);
        expect(profile.cattle.stagePeriods, hasLength(2));
        expect(
          profile.cattle.stagePeriods.first.validTo,
          profile.cattle.stagePeriods.first.validFrom,
        );
        expect(profile.cattle.stagePeriods.last.validTo, isNotNull);
        expect(
          profile.cattle.stagePeriods.last.stage,
          CattleStage.fatteningBull,
        );
        expect(profile.device.isAvailable, isTrue);
        expect(profile.device.collarId, _collarId);
        expect(profile.device.lastReadingReceivedAt!.isUtc, isTrue);
        expect(
          profile.device.lastReadingReceivedAt,
          DateTime.utc(2026, 11, 12, 16, 5, 6, 123),
        );
      },
    );

    test('maps a confirmed no-collar profile and open active stage', () async {
      final repository = RestCattleRepository(
        api: _api(
          harness,
          MockClient(
            (_) async => http.Response(
              jsonEncode(<String, Object?>{
                'cattle': _activeCattle(),
                'device': <String, Object?>{
                  'isAvailable': true,
                  'collarId': null,
                  'lastReadingReceivedAt': null,
                },
              }),
              200,
            ),
          ),
        ),
      );

      final profile = await repository.profile(_ranchA, _cattleId);

      expect(profile.cattle.status, CattleStatus.active);
      expect(profile.cattle.exitReason, isNull);
      expect(profile.cattle.exitDate, isNull);
      expect(profile.cattle.stagePeriods.single.validTo, isNull);
      expect(profile.device.isAvailable, isTrue);
      expect(profile.device.collarId, isNull);
      expect(profile.device.lastReadingReceivedAt, isNull);

      final unavailableRepository = RestCattleRepository(
        api: _api(
          harness,
          MockClient(
            (_) async => http.Response(
              jsonEncode(<String, Object?>{
                'cattle': _activeCattle(),
                'device': <String, Object?>{
                  'isAvailable': false,
                  'collarId': null,
                  'lastReadingReceivedAt': null,
                },
              }),
              200,
            ),
          ),
        ),
      );
      final unavailable = await unavailableRepository.profile(
        _ranchA,
        _cattleId,
      );
      expect(unavailable.device.isAvailable, isFalse);
      expect(unavailable.device.collarId, isNull);
      expect(unavailable.device.lastReadingReceivedAt, isNull);
    });

    test(
      'accepts every implemented breed, sex, stage and exit-reason name',
      () async {
        final cattle = <Map<String, Object?>>[];
        const breeds = <String>[
          'BrownSwiss',
          'Fleckvieh',
          'Criollo',
          'Crossbred',
        ];
        const sexes = <String>['Female', 'Male'];
        const stages = <String>[
          'Calf',
          'Heifer',
          'MilkingCow',
          'FatteningBull',
        ];
        for (var index = 0; index < breeds.length; index++) {
          final item = _activeCattle()
            ..['id'] = _uuidFor(index + 10)
            ..['breed'] = breeds[index]
            ..['sex'] = sexes[index % sexes.length]
            ..['currentStage'] = stages[index];
          ((item['stagePeriods'] as List<Object?>).single
                  as Map<String, Object?>)['lifeStage'] =
              stages[index];
          item['earTag'] = 'PE-${(index + 10).toString().padLeft(4, '0')}';
          cattle.add(item);
        }
        final listRepository = RestCattleRepository(
          api: _api(
            harness,
            MockClient((_) async => http.Response(jsonEncode(cattle), 200)),
          ),
        );

        final mapped = await listRepository.search(
          _ranchA,
          const CattleSearch(pageSize: 4),
        );

        expect(mapped.map((item) => item.breed).toList(), <CattleBreed>[
          CattleBreed.brownSwiss,
          CattleBreed.fleckvieh,
          CattleBreed.criollo,
          CattleBreed.crossbred,
        ]);
        expect(mapped.map((item) => item.currentStage).toList(), <CattleStage>[
          CattleStage.calf,
          CattleStage.heifer,
          CattleStage.milkingCow,
          CattleStage.fatteningBull,
        ]);
        expect(mapped.map((item) => item.sex).toList(), <CattleSex>[
          CattleSex.female,
          CattleSex.male,
          CattleSex.female,
          CattleSex.male,
        ]);
        expect(() => mapped.clear(), throwsUnsupportedError);

        for (final reason in <String>['Death', 'Sale', 'Theft', 'Culling']) {
          final item = _inactiveCattle()..['exitReason'] = reason;
          final repository = RestCattleRepository(
            api: _api(
              harness,
              MockClient(
                (_) async => http.Response(
                  jsonEncode(<String, Object?>{
                    'cattle': item,
                    'device': _noDevice(),
                  }),
                  200,
                ),
              ),
            ),
          );
          final profile = await repository.profile(_ranchA, _cattleId);
          expect(
            profile.cattle.exitReason?.name.toLowerCase(),
            reason.toLowerCase(),
          );
        }
      },
    );

    test(
      'rejects a response ranch mismatch, detail id mismatch and oversized list',
      () async {
        final wrongRanch = RestCattleRepository(
          api: _api(
            harness,
            MockClient(
              (_) async => http.Response(
                jsonEncode(<Object?>[_activeCattle()..['ranchId'] = _ranchB]),
                200,
              ),
            ),
          ),
        );
        await _expectFailure(
          wrongRanch.search(_ranchA, const CattleSearch()),
          CattleFailureCode.invalidResponse,
        );

        final wrongDetail = RestCattleRepository(
          api: _api(
            harness,
            MockClient(
              (_) async => http.Response(
                jsonEncode(<String, Object?>{
                  'cattle': _activeCattle()..['id'] = _otherCattleId,
                  'device': _noDevice(),
                }),
                200,
              ),
            ),
          ),
        );
        await _expectFailure(
          wrongDetail.profile(_ranchA, _cattleId),
          CattleFailureCode.invalidResponse,
        );

        final tooMany = RestCattleRepository(
          api: _api(
            harness,
            MockClient(
              (_) async => http.Response(
                jsonEncode(<Object?>[
                  _activeCattle(),
                  _activeCattle()..['id'] = _otherCattleId,
                ]),
                200,
              ),
            ),
          ),
        );
        await _expectFailure(
          tooMany.search(_ranchA, const CattleSearch(pageSize: 1)),
          CattleFailureCode.invalidResponse,
        );
      },
    );

    test('rejects malformed enum, date, lifecycle and device fields', () async {
      final invalidBodies = <Map<String, Object?>>[
        <String, Object?>{
          'cattle': _activeCattle()..['breed'] = 'OtherBreed',
          'device': _noDevice(),
        },
        <String, Object?>{
          'cattle': _activeCattle()..['birthDate'] = '2026-02-30',
          'device': _noDevice(),
        },
        <String, Object?>{
          'cattle': _activeCattle()..['exitReason'] = 'Sale',
          'device': _noDevice(),
        },
        <String, Object?>{
          'cattle': _activeCattle(),
          'device': <String, Object?>{
            'isAvailable': false,
            'collarId': _collarId,
            'lastReadingReceivedAt': null,
          },
        },
        <String, Object?>{
          'cattle': _activeCattle(),
          'device': <String, Object?>{
            'isAvailable': true,
            'collarId': null,
            'lastReadingReceivedAt': '2026-11-12T11:05:06',
          },
        },
      ];

      for (final body in invalidBodies) {
        final repository = RestCattleRepository(
          api: _api(
            harness,
            MockClient((_) async => http.Response(jsonEncode(body), 200)),
          ),
        );
        await _expectFailure(
          repository.profile(_ranchA, _cattleId),
          CattleFailureCode.invalidResponse,
        );
      }
    });

    test(
      'maps HTTP failures without exposing problem titles or retrying',
      () async {
        for (final (status, code) in <(int, CattleFailureCode)>[
          (400, CattleFailureCode.invalidSearch),
          (401, CattleFailureCode.unauthenticated),
          (403, CattleFailureCode.forbidden),
          (404, CattleFailureCode.notFound),
          (429, CattleFailureCode.serviceUnavailable),
          (503, CattleFailureCode.serviceUnavailable),
          (302, CattleFailureCode.unknown),
        ]) {
          var requestCount = 0;
          final repository = RestCattleRepository(
            api: _api(
              harness,
              MockClient((request) async {
                requestCount++;
                expect(request.followRedirects, isFalse);
                return http.Response(
                  '{"title":"private backend detail"}',
                  status,
                  headers: <String, String>{
                    if (status == 302)
                      'location': 'https://evil.example/collect',
                  },
                );
              }),
            ),
          );
          try {
            await repository.search(_ranchA, const CattleSearch());
            fail('Expected CattleFailure($code)');
          } on CattleFailure catch (failure) {
            expect(failure.code, code);
            expect(
              failure.toString(),
              isNot(contains('private backend detail')),
            );
          }
          expect(requestCount, 1);
        }
      },
    );

    test(
      'rejects selection changes during the response, including A to B to A',
      () async {
        final responseStarted = Completer<void>();
        final pendingResponse = Completer<http.Response>();
        final repository = RestCattleRepository(
          api: _api(
            harness,
            MockClient((_) {
              responseStarted.complete();
              return pendingResponse.future;
            }),
          ),
        );

        final result = repository.search(_ranchA, const CattleSearch());
        await responseStarted.future;
        expect(harness.selection.select(_ranchB), isTrue);
        expect(harness.selection.select(_ranchA), isTrue);
        pendingResponse.complete(
          http.Response(jsonEncode(<Object?>[_activeCattle()]), 200),
        );

        await _expectFailure(result, CattleFailureCode.contextUnavailable);
      },
    );

    test(
      'does not send a token if the selected context changes during token fetch',
      () async {
        var requestCount = 0;
        final pendingToken = Completer<String>();
        harness.authentication.tokenCompleter = pendingToken;
        final repository = RestCattleRepository(
          api: _api(
            harness,
            MockClient((_) async {
              requestCount++;
              return http.Response('[]', 200);
            }),
          ),
        );

        final result = repository.search(_ranchA, const CattleSearch());
        await Future<void>.delayed(Duration.zero);
        expect(harness.selection.select(_ranchB), isTrue);
        pendingToken.complete('sensitive-token');

        await _expectFailure(result, CattleFailureCode.contextUnavailable);
        expect(requestCount, 0);
      },
    );

    test('fetches a fresh token for every GET', () async {
      final requests = <http.Request>[];
      final repository = RestCattleRepository(
        api: _api(
          harness,
          MockClient((request) async {
            requests.add(request);
            return http.Response('[]', 200);
          }),
        ),
      );

      await repository.search(_ranchA, const CattleSearch());
      await repository.search(_ranchA, const CattleSearch(page: 2));

      expect(harness.identity.idTokenCalls, 2);
      expect(requests.map((request) => request.headers['Authorization']), [
        'Bearer synthetic-token',
        'Bearer synthetic-token',
      ]);
      expect(requests.map((request) => request.method), everyElement('GET'));
    });

    test(
      'maps a transport failure without exposing details or retrying',
      () async {
        var requestCount = 0;
        final repository = RestCattleRepository(
          api: _api(
            harness,
            MockClient((_) async {
              requestCount++;
              throw http.ClientException('private transport detail');
            }),
          ),
        );

        try {
          await repository.search(_ranchA, const CattleSearch());
          fail('Expected a network failure');
        } on CattleFailure catch (failure) {
          expect(failure.code, CattleFailureCode.network);
          expect(
            failure.toString(),
            isNot(contains('private transport detail')),
          );
        }
        expect(requestCount, 1);
      },
    );

    test(
      'rejects invalid inputs and absent configuration before HTTP or token access',
      () async {
        var requestCount = 0;
        final api = _api(
          harness,
          MockClient((_) async {
            requestCount++;
            return http.Response('[]', 200);
          }),
        );
        final repository = RestCattleRepository(api: api);
        final tokenRequestsBefore = harness.identity.idTokenCalls;

        await _expectFailure(
          repository.search(_ranchA, const CattleSearch(page: 0)),
          CattleFailureCode.invalidSearch,
        );
        await _expectFailure(
          repository.profile(_ranchA, 'not-a-uuid'),
          CattleFailureCode.notFound,
        );
        await _expectFailure(
          repository.search(_ranchB, const CattleSearch()),
          CattleFailureCode.contextUnavailable,
        );
        expect(requestCount, 0);
        expect(harness.identity.idTokenCalls, tokenRequestsBefore);

        final unconfigured = RestCattleRepository(api: null);
        expect(unconfigured.isConfigured, isFalse);
        await _expectFailure(
          unconfigured.search(_ranchA, const CattleSearch()),
          CattleFailureCode.configuration,
        );
        await _expectFailure(
          unconfigured.profile(_ranchA, _cattleId),
          CattleFailureCode.configuration,
        );
        expect(requestCount, 0);
      },
    );

    test(
      'rejects a payload that is not the implemented full-array contract',
      () async {
        final repository = RestCattleRepository(
          api: _api(
            harness,
            MockClient((_) async => http.Response('{"items":[]}', 200)),
          ),
        );

        await _expectFailure(
          repository.search(_ranchA, const CattleSearch()),
          CattleFailureCode.invalidResponse,
        );
      },
    );

    test(
      'rejects malformed and oversized successful response bodies',
      () async {
        final malformed = RestCattleRepository(
          api: _api(
            harness,
            MockClient((_) async => http.Response('{broken', 200)),
          ),
        );
        await _expectFailure(
          malformed.search(_ranchA, const CattleSearch()),
          CattleFailureCode.invalidResponse,
        );

        final oversized = RestCattleRepository(
          api: _api(
            harness,
            MockClient(
              (_) async => http.Response(
                List<int>.filled(1024 * 1024 + 1, 32).join(),
                200,
              ),
            ),
          ),
        );
        await _expectFailure(
          oversized.search(_ranchA, const CattleSearch()),
          CattleFailureCode.invalidResponse,
        );
      },
    );

    test(
      'bounds request and response waits and maps timeout to network',
      () async {
        final neverCompletes = Completer<http.StreamedResponse>();
        final repository = RestCattleRepository(
          api: CattleApiClient(
            baseUri: Uri.parse('https://api.example.test/api/v1'),
            client: _StreamClient((_) => neverCompletes.future),
            session: harness.facade,
            languageTag: () => 'en-US',
            timeout: const Duration(milliseconds: 20),
          ),
        );

        await _expectFailure(
          repository.search(_ranchA, const CattleSearch()),
          CattleFailureCode.network,
        );
        neverCompletes.complete(
          http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode('[]')),
            200,
          ),
        );

        final bodySubscribed = Completer<void>();
        final bodyStream = StreamController<List<int>>(
          onListen: bodySubscribed.complete,
        );
        final bodyRepository = RestCattleRepository(
          api: CattleApiClient(
            baseUri: Uri.parse('https://api.example.test/api/v1'),
            client: _StreamClient(
              (_) async => http.StreamedResponse(bodyStream.stream, 200),
            ),
            session: harness.facade,
            languageTag: () => 'en-US',
            timeout: const Duration(milliseconds: 20),
          ),
        );
        final bodyResult = bodyRepository.search(_ranchA, const CattleSearch());
        await bodySubscribed.future;
        await _expectFailure(bodyResult, CattleFailureCode.network);
        await bodyStream.close();
      },
    );
  });
}

const String _ranchA = '11111111-1111-4111-8111-111111111111';
const String _ranchB = '22222222-2222-4222-8222-222222222222';
const String _cattleId = '33333333-3333-4333-8333-333333333333';
const String _otherCattleId = '44444444-4444-4444-8444-444444444444';
const String _periodOne = '55555555-5555-4555-8555-555555555555';
const String _periodTwo = '66666666-6666-4666-8666-666666666666';
const String _collarId = '77777777-7777-4777-8777-777777777777';

String _uuidFor(int value) =>
    '${value.toRadixString(16).padLeft(8, '0')}-1111-4111-8111-111111111111';

Map<String, Object?> _activeCattle() => <String, Object?>{
  'id': _cattleId,
  'ranchId': _ranchA,
  'earTag': 'PE-0001',
  'breed': 'BrownSwiss',
  'sex': 'Female',
  'birthDate': '2024-03-01',
  'currentStage': 'Heifer',
  'status': 'Active',
  'exitReason': null,
  'exitDate': null,
  'version': '88888888-8888-4888-8888-888888888888',
  'stagePeriods': <Object?>[
    <String, Object?>{
      'id': _periodOne,
      'lifeStage': 'Heifer',
      'validFrom': '2026-01-01',
      'validTo': null,
    },
  ],
};

Map<String, Object?> _inactiveCattle() => <String, Object?>{
  'id': _cattleId,
  'ranchId': _ranchA,
  'earTag': 'PE-0002',
  'breed': 'Crossbred',
  'sex': 'Male',
  'birthDate': '2020-02-29',
  'currentStage': 'FatteningBull',
  'status': 'Inactive',
  'exitReason': 'Culling',
  'exitDate': '2026-03-04',
  'version': '88888888-8888-4888-8888-888888888888',
  'stagePeriods': <Object?>[
    <String, Object?>{
      'id': _periodOne,
      'lifeStage': 'Calf',
      'validFrom': '2020-02-29',
      'validTo': '2020-02-29',
    },
    <String, Object?>{
      'id': _periodTwo,
      'lifeStage': 'FatteningBull',
      'validFrom': '2020-02-29',
      'validTo': '2026-03-04',
    },
  ],
};

Map<String, Object?> _noDevice() => <String, Object?>{
  'isAvailable': true,
  'collarId': null,
  'lastReadingReceivedAt': null,
};

CattleApiClient _api(_Harness harness, http.Client client) => CattleApiClient(
  baseUri: Uri.parse('https://api.example.test/api/v1'),
  client: client,
  session: harness.facade,
  languageTag: () => 'es-419',
  timeout: const Duration(seconds: 1),
);

Future<void> _expectFailure(
  Future<Object?> operation,
  CattleFailureCode code,
) async {
  await expectLater(
    operation,
    throwsA(
      isA<CattleFailure>().having((failure) => failure.code, 'code', code),
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
          id: '33333333-3333-4333-8333-333333333333',
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

  Completer<String>? tokenCompleter;

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
