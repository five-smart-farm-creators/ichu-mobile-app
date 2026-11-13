import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle_commands.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle_date.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle_failure.dart';
import 'package:ichu_mobile_app/features/cattle_information/infrastructure/http/cattle_api_client.dart';
import 'package:ichu_mobile_app/features/cattle_information/infrastructure/repositories/rest_cattle_command_repository.dart';
import 'package:ichu_mobile_app/features/iam/application/facades/authorized_ranch_session.dart';
import 'package:ichu_mobile_app/features/iam/application/services/auth_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/authentication_lifecycle.dart';
import 'package:ichu_mobile_app/features/iam/application/services/ranch_selection_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_access.dart';

import '../../../support/fake_iam_repositories.dart';

void main() {
  group('RestCattleCommandRepository', () {
    late _Harness harness;

    setUp(() async {
      harness = _Harness();
      await harness.initialize();
    });
    tearDown(() => harness.dispose());

    test('registers with one POST and an exact trimmed JSON body', () async {
      final requests = <http.Request>[];
      final repository = RestCattleCommandRepository(
        api: _api(
          harness,
          MockClient((request) async {
            requests.add(request);
            return http.Response(jsonEncode(_activeCattle()), 201);
          }),
        ),
      );

      final cattle = await repository.register(
        _ranchA,
        CattleRegistration(
          earTag: ' PE-0001 ',
          breed: CattleBreed.brownSwiss,
          sex: CattleSex.female,
          birthDate: const CattleDate(2024, 3, 1),
          lifeStage: CattleStage.heifer,
        ),
      );

      expect(cattle.earTag, 'PE-0001');
      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/ranches/$_ranchA/cattle');
      expect(request.url.hasQuery, isFalse);
      expect(request.followRedirects, isFalse);
      expect(request.headers['Authorization'], 'Bearer synthetic-token');
      expect(request.headers['Content-Type'], 'application/json');
      expect(jsonDecode(request.body), <String, Object?>{
        'earTag': 'PE-0001',
        'breed': 'BrownSwiss',
        'sex': 'Female',
        'birthDate': '2024-03-01',
        'lifeStage': 'Heifer',
      });
    });

    test('corrects with PUT and sends the version it was read at', () async {
      final requests = <http.Request>[];
      final repository = RestCattleCommandRepository(
        api: _api(
          harness,
          MockClient((request) async {
            requests.add(request);
            return http.Response(jsonEncode(_activeCattle()), 200);
          }),
        ),
      );

      await repository.correct(
        _ranchA,
        _cattleId,
        _expectedVersion,
        CattleCorrection(
          earTag: 'PE-0001',
          breed: CattleBreed.brownSwiss,
          sex: CattleSex.female,
          birthDate: const CattleDate(2024, 3, 1),
        ),
      );

      final request = requests.single;
      expect(request.method, 'PUT');
      expect(request.url.path, '/api/v1/ranches/$_ranchA/cattle/$_cattleId');
      expect(jsonDecode(request.body), <String, Object?>{
        'earTag': 'PE-0001',
        'breed': 'BrownSwiss',
        'sex': 'Female',
        'birthDate': '2024-03-01',
        'expectedVersion': _expectedVersion,
      });
    });

    test('changes stage with PATCH and deactivates with POST', () async {
      final requests = <http.Request>[];
      final repository = RestCattleCommandRepository(
        api: _api(
          harness,
          MockClient((request) async {
            requests.add(request);
            final body = request.url.path.endsWith('/deactivations')
                ? _inactiveCattle()
                : _activeCattle();
            return http.Response(jsonEncode(body), 200);
          }),
        ),
      );

      await repository.changeStage(
        _ranchA,
        _cattleId,
        _expectedVersion,
        CattleStageChange(
          stage: CattleStage.heifer,
          validFrom: const CattleDate(2026, 1, 1),
        ),
      );
      await repository.deactivate(
        _ranchA,
        _cattleId,
        _expectedVersion,
        CattleExit(
          reason: CattleExitReason.culling,
          exitDate: const CattleDate(2026, 3, 4),
        ),
      );

      final stage = requests[0];
      expect(stage.method, 'PATCH');
      expect(
        stage.url.path,
        '/api/v1/ranches/$_ranchA/cattle/$_cattleId/life-stage',
      );
      expect(jsonDecode(stage.body), <String, Object?>{
        'lifeStage': 'Heifer',
        'validFrom': '2026-01-01',
        'expectedVersion': _expectedVersion,
      });
      final exit = requests[1];
      expect(exit.method, 'POST');
      expect(
        exit.url.path,
        '/api/v1/ranches/$_ranchA/cattle/$_cattleId/deactivations',
      );
      expect(jsonDecode(exit.body), <String, Object?>{
        'reason': 'Culling',
        'exitDate': '2026-03-04',
        'expectedVersion': _expectedVersion,
      });
    });

    test('maps each stable conflict and rejection without retrying', () async {
      for (final (status, body, code) in <(int, Object?, CattleFailureCode)>[
        (
          409,
          {'code': 'CattleInformation.DuplicateEarTag'},
          CattleFailureCode.duplicateEarTag,
        ),
        (
          409,
          {'code': 'CattleInformation.CattleInactive'},
          CattleFailureCode.inactive,
        ),
        (
          409,
          {'code': 'CattleInformation.LifeStageAlreadyCurrent'},
          CattleFailureCode.stageAlreadyCurrent,
        ),
        (
          409,
          {'code': 'CattleInformation.CattleVersionMismatch'},
          CattleFailureCode.versionConflict,
        ),
        (409, null, CattleFailureCode.versionConflict),
        (
          400,
          {'code': 'CattleInformation.InvalidEarTag'},
          CattleFailureCode.invalidInput,
        ),
        (403, null, CattleFailureCode.forbidden),
        (404, null, CattleFailureCode.notFound),
        (429, null, CattleFailureCode.serviceUnavailable),
        (503, null, CattleFailureCode.serviceUnavailable),
      ]) {
        final requests = <http.Request>[];
        final repository = RestCattleCommandRepository(
          api: _api(
            harness,
            MockClient((request) async {
              requests.add(request);
              return http.Response(
                body == null ? '' : jsonEncode(body),
                status,
              );
            }),
          ),
        );

        await _expectFailure(
          repository.deactivate(
            _ranchA,
            _cattleId,
            _expectedVersion,
            CattleExit(
              reason: CattleExitReason.sale,
              exitDate: const CattleDate(2026, 3, 4),
            ),
          ),
          code,
        );
        expect(requests, hasLength(1), reason: 'status $status');
      }
    });

    test(
      'a transport failure after sending is outcomeUnknown and not retried',
      () async {
        final requests = <http.Request>[];
        final repository = RestCattleCommandRepository(
          api: _api(
            harness,
            MockClient((request) async {
              requests.add(request);
              throw http.ClientException('synthetic network drop');
            }),
          ),
        );

        await _expectFailure(
          repository.register(_ranchA, _registration()),
          CattleFailureCode.outcomeUnknown,
        );
        expect(requests, hasLength(1));
      },
    );

    test('a timeout after sending is outcomeUnknown and not retried', () async {
      var requests = 0;
      final repository = RestCattleCommandRepository(
        api: CattleApiClient(
          baseUri: Uri.parse('https://api.example.test/api/v1'),
          client: _StreamClient((_) {
            requests++;
            return Completer<http.StreamedResponse>().future;
          }),
          session: harness.facade,
          languageTag: () => 'es-419',
          timeout: const Duration(milliseconds: 20),
        ),
      );

      await _expectFailure(
        repository.correct(_ranchA, _cattleId, _expectedVersion, _correction()),
        CattleFailureCode.outcomeUnknown,
      );
      expect(requests, 1);
    });

    test('rejects responses that do not describe the accepted write', () async {
      RestCattleCommandRepository withResponse(int status, Object? body) =>
          RestCattleCommandRepository(
            api: _api(
              harness,
              MockClient((_) async => http.Response(jsonEncode(body), status)),
            ),
          );

      await _expectFailure(
        withResponse(200, _activeCattle()).register(_ranchA, _registration()),
        CattleFailureCode.invalidResponse,
      );
      await _expectFailure(
        withResponse(
          201,
          _activeCattle()..['earTag'] = 'PE-9999',
        ).register(_ranchA, _registration()),
        CattleFailureCode.invalidResponse,
      );
      await _expectFailure(
        withResponse(
          201,
          _activeCattle()..['ranchId'] = _ranchB,
        ).register(_ranchA, _registration()),
        CattleFailureCode.invalidResponse,
      );
      await _expectFailure(
        withResponse(
          200,
          _activeCattle()..['version'] = _expectedVersion,
        ).correct(_ranchA, _cattleId, _expectedVersion, _correction()),
        CattleFailureCode.invalidResponse,
      );
      await _expectFailure(
        withResponse(200, _activeCattle()).changeStage(
          _ranchA,
          _cattleId,
          _expectedVersion,
          CattleStageChange(
            stage: CattleStage.fatteningBull,
            validFrom: const CattleDate(2026, 1, 1),
          ),
        ),
        CattleFailureCode.invalidResponse,
      );
      await _expectFailure(
        withResponse(200, _activeCattle()).deactivate(
          _ranchA,
          _cattleId,
          _expectedVersion,
          CattleExit(
            reason: CattleExitReason.death,
            exitDate: const CattleDate(2026, 3, 4),
          ),
        ),
        CattleFailureCode.invalidResponse,
      );
    });

    test('validates identifiers and ranch scope before any request', () async {
      var requests = 0;
      final repository = RestCattleCommandRepository(
        api: _api(
          harness,
          MockClient((_) async {
            requests++;
            return http.Response('{}', 200);
          }),
        ),
      );

      await _expectFailure(
        repository.correct(
          _ranchA,
          'not-a-uuid',
          _expectedVersion,
          _correction(),
        ),
        CattleFailureCode.notFound,
      );
      await _expectFailure(
        repository.correct(
          _ranchA,
          _cattleId,
          '00000000-0000-0000-0000-000000000000',
          _correction(),
        ),
        CattleFailureCode.invalidInput,
      );
      await _expectFailure(
        repository.register(_ranchB, _registration()),
        CattleFailureCode.contextUnavailable,
      );
      expect(requests, 0);
    });
  });
}

const String _ranchA = '11111111-1111-4111-8111-111111111111';
const String _ranchB = '22222222-2222-4222-8222-222222222222';
const String _cattleId = '33333333-3333-4333-8333-333333333333';
const String _periodOne = '55555555-5555-4555-8555-555555555555';
const String _periodTwo = '66666666-6666-4666-8666-666666666666';
const String _expectedVersion = '77777777-7777-4777-8777-777777777777';

CattleRegistration _registration() => CattleRegistration(
  earTag: 'PE-0001',
  breed: CattleBreed.brownSwiss,
  sex: CattleSex.female,
  birthDate: const CattleDate(2024, 3, 1),
  lifeStage: CattleStage.heifer,
);

CattleCorrection _correction() => CattleCorrection(
  earTag: 'PE-0001',
  breed: CattleBreed.brownSwiss,
  sex: CattleSex.female,
  birthDate: const CattleDate(2024, 3, 1),
);

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
  'earTag': 'PE-0001',
  'breed': 'BrownSwiss',
  'sex': 'Female',
  'birthDate': '2024-03-01',
  'currentStage': 'Heifer',
  'status': 'Inactive',
  'exitReason': 'Culling',
  'exitDate': '2026-03-04',
  'version': '88888888-8888-4888-8888-888888888888',
  'stagePeriods': <Object?>[
    <String, Object?>{
      'id': _periodOne,
      'lifeStage': 'Heifer',
      'validFrom': '2026-01-01',
      'validTo': '2026-03-04',
    },
    <String, Object?>{
      'id': _periodTwo,
      'lifeStage': 'Heifer',
      'validFrom': '2026-03-04',
      'validTo': '2026-03-04',
    },
  ],
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
  scope: AccessScope.manage,
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
    facade = AuthorizedRanchSession(
      session: auth,
      selection: selection,
      authentication: identity,
    );
  }

  final FakeAuthenticationRepository identity;
  final FakeAccountRepository accounts;
  late final AuthenticationLifecycle lifecycle;
  late final AuthService auth;
  late final RanchSelectionService selection;
  late final AuthorizedRanchSession facade;

  Future<void> initialize() async {
    await auth.initialize();
    expect(selection.select(_ranchA), isTrue);
  }

  void dispose() {
    facade.dispose();
    selection.dispose();
    auth.dispose();
    lifecycle.dispose();
    unawaited(identity.close());
  }
}

final class _StreamClient extends http.BaseClient {
  _StreamClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _handler(request);
}
