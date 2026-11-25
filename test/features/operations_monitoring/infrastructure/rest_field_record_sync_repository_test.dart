import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ichu_mobile_app/features/iam/application/facades/authorized_ranch_session.dart';
import 'package:ichu_mobile_app/features/iam/application/services/auth_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/authentication_lifecycle.dart';
import 'package:ichu_mobile_app/features/iam/application/services/ranch_selection_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_access.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/field_record.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/field_record_sync.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/infrastructure/http/monitoring_api_client.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/infrastructure/repositories/rest_field_record_sync_repository.dart';

import '../../../support/fake_iam_repositories.dart';

const _account = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _ranch = '11111111-1111-4111-8111-111111111111';
const _otherRanch = '22222222-2222-4222-8222-222222222222';

void main() {
  late FakeAuthenticationRepository identity;
  late AuthenticationLifecycle lifecycle;
  late AuthService auth;
  late RanchSelectionService selection;
  late AuthorizedRanchSession access;
  late FakeAccountRepository accounts;
  setUp(() async {
    identity = FakeAuthenticationRepository();
    accounts = FakeAccountRepository(
      account: const IamAccount(
        id: _account,
        email: 'user@example.test',
        role: AccountRole.ranchManager,
        status: 'active',
      ),
      ranches: [_grant(_ranch), _grant(_otherRanch)],
    );
    lifecycle = AuthenticationLifecycle(identity);
    auth = AuthService(authentication: lifecycle, accounts: accounts);
    selection = RanchSelectionService(session: auth);
    access = AuthorizedRanchSession(
      session: auth,
      selection: selection,
      authentication: lifecycle,
    );
    await auth.initialize();
    expect(selection.select(_ranch), isTrue);
  });
  tearDown(() async {
    access.dispose();
    selection.dispose();
    auth.dispose();
    lifecycle.dispose();
    await identity.close();
  });

  RestFieldRecordSyncRepository repository(
    http.Client client, {
    Duration timeout = const Duration(seconds: 15),
  }) {
    addTearDown(client.close);
    return RestFieldRecordSyncRepository(
      api: MonitoringApiClient(
        baseUri: Uri.parse('https://api.example.test/api/v1'),
        client: client,
        session: access,
        languageTag: () => 'es-419',
        timeout: timeout,
      ),
    );
  }

  Future<List<FieldRecordSyncResult>> send(
    RestFieldRecordSyncRepository remote,
    List<FieldRecord> records, {
    String accountId = _account,
    String ranchId = _ranch,
  }) => remote.synchronize(
    accountId: accountId,
    ranchId: ranchId,
    records: records,
  );

  test(
    'sends the exact mobile payload and maps each decision without cache data',
    () async {
      final records = [
        for (final type in FieldRecordType.values) _record(type: type),
      ];
      final remote = repository(
        MockClient((request) async {
          expect(request.method, 'POST');
          expect(
            request.url.toString(),
            'https://api.example.test/api/v1/mobile-sync/batch',
          );
          expect(request.followRedirects, isFalse);
          expect(request.headers['Authorization'], 'Bearer synthetic-token');
          expect(request.headers['Accept-Language'], 'es-419');
          expect(jsonDecode(request.body), {
            'operations': [
              for (final record in records)
                {
                  'operationId': record.operationId,
                  'cattleId': record.cattleId,
                  'type': switch (record.type) {
                    FieldRecordType.healthEvent => 'HealthEvent',
                    FieldRecordType.birth => 'Birth',
                    FieldRecordType.naturalMating => 'NaturalMating',
                    FieldRecordType.abortion => 'Abortion',
                    FieldRecordType.heatObserved => 'HeatObserved',
                  },
                  'occurredAt': record.occurredAt.toIso8601String(),
                  'observation': 'Synthetic field event',
                  if (record.type == FieldRecordType.naturalMating)
                    'sireReference': 'Synthetic sire',
                },
            ],
          });
          return http.Response(
            jsonEncode({
              'results': List.generate(
                records.length,
                (i) => _result(
                  records[i],
                  [
                    'Accepted',
                    'Duplicate',
                    'Rejected',
                    'Conflict',
                    'Accepted',
                  ][i],
                ),
              ),
            }),
            200,
          );
        }),
      );
      final results = await send(remote, records);
      expect(results.map((result) => result.status), [
        FieldRecordSyncStatus.accepted,
        FieldRecordSyncStatus.duplicate,
        FieldRecordSyncStatus.rejected,
        FieldRecordSyncStatus.conflict,
        FieldRecordSyncStatus.accepted,
      ]);
    },
  );

  test(
    'does not send empty, oversized, duplicate, cross-ranch or wrong-account batches',
    () async {
      var calls = 0;
      final remote = repository(
        MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      final record = _record();
      for (final batch in <List<FieldRecord>>[
        [],
        List.generate(51, (_) => _record()),
        [record, record],
        [_record(ranchId: _otherRanch)],
      ]) {
        await _failure(
          send(remote, batch),
          FieldRecordSyncFailureCode.invalidBatch,
        );
      }
      await _failure(
        send(remote, [record], accountId: _otherRanch),
        FieldRecordSyncFailureCode.contextUnavailable,
      );
      accounts.ranches = [_grant(_ranch, scope: AccessScope.read)];
      await auth.refresh();
      selection.select(_ranch);
      await _failure(
        send(remote, [record]),
        FieldRecordSyncFailureCode.permissionRequired,
      );
      expect(calls, 0);
    },
  );

  test('discards responses after a ranch changes away and back', () async {
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final record = _record();
    final remote = repository(
      MockClient((_) {
        started.complete();
        return response.future;
      }),
    );
    final pending = send(remote, [record]);
    await started.future;
    selection.select(_otherRanch);
    selection.select(_ranch);
    response.complete(
      http.Response(
        jsonEncode({
          'results': [_result(record, 'Accepted')],
        }),
        200,
      ),
    );
    await _failure(pending, FieldRecordSyncFailureCode.contextUnavailable);
  });

  test('does not send a token fetched for a replaced context', () async {
    var calls = 0;
    final remote = repository(
      MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    final pending = send(remote, [_record()]);
    selection.select(_otherRanch);
    await _failure(pending, FieldRecordSyncFailureCode.contextUnavailable);
    expect(calls, 0);
  });

  test(
    'rejects missing, duplicate, foreign and malformed results atomically',
    () async {
      final record = _record();
      for (final payload in <Object?>[
        null,
        {},
        {'results': []},
        {
          'results': [_result(record, 'accepted')],
        },
        {
          'results': [_result(_record(), 'Accepted')],
        },
        {
          'results': [_result(record, 'Accepted'), _result(record, 'Accepted')],
        },
        {
          'results': [
            _result(record, 'Accepted')..['kind'] = 'TelemetryReading',
          ],
        },
        {
          'results': [_result(record, 'Accepted')..['reason'] = 42],
        },
        {
          'results': [_result(record, 'Accepted')..['relatedAlertId'] = _ranch],
        },
      ]) {
        final remote = repository(
          MockClient((_) async => http.Response(jsonEncode(payload), 200)),
        );
        await _failure(
          send(remote, [record]),
          FieldRecordSyncFailureCode.invalidResponse,
        );
      }
    },
  );

  test('explicit retry preserves the same operation ID and content', () async {
    final requests = <String>[];
    final record = _record();
    final remote = repository(
      MockClient((request) async {
        requests.add(request.body);
        if (requests.length == 1) {
          throw http.ClientException('Synthetic uncertain delivery');
        }
        return http.Response(
          jsonEncode({
            'results': [_result(record, 'Duplicate')],
          }),
          200,
        );
      }),
    );
    await _failure(send(remote, [record]), FieldRecordSyncFailureCode.network);
    expect(requests, hasLength(1));
    expect(
      (await send(remote, [record])).single.status,
      FieldRecordSyncStatus.duplicate,
    );
    expect(requests[0], requests[1]);
  });

  test(
    'bounds response decoding and maps failures without replay or private errors',
    () async {
      for (final (status, code) in [
        (400, FieldRecordSyncFailureCode.invalidBatch),
        (401, FieldRecordSyncFailureCode.contextUnavailable),
        (403, FieldRecordSyncFailureCode.permissionRequired),
        (429, FieldRecordSyncFailureCode.serviceUnavailable),
        (503, FieldRecordSyncFailureCode.serviceUnavailable),
        (302, FieldRecordSyncFailureCode.unknown),
      ]) {
        var calls = 0;
        final remote = repository(
          MockClient((_) async {
            calls++;
            return http.Response('Private response', status);
          }),
        );
        await _failure(send(remote, [_record()]), code);
        expect(calls, 1);
      }
      for (final body in ['{invalid', 'x' * (1024 * 1024 + 1)]) {
        await _failure(
          send(repository(MockClient((_) async => http.Response(body, 200))), [
            _record(),
          ]),
          FieldRecordSyncFailureCode.invalidResponse,
        );
      }
      final remote = repository(
        MockClient((_) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 20),
      );
      await _failure(
        send(remote, [_record()]),
        FieldRecordSyncFailureCode.network,
      );
    },
  );
}

Future<void> _failure(
  Future<Object?> pending,
  FieldRecordSyncFailureCode code,
) => expectLater(
  pending,
  throwsA(
    isA<FieldRecordSyncFailure>().having(
      (failure) => failure.code,
      'code',
      code,
    ),
  ),
);

Map<String, Object?> _result(FieldRecord record, String status) => {
  'kind': 'LivestockOperation',
  'id': record.operationId,
  'status': status,
  'reason': status == 'Rejected' || status == 'Conflict'
      ? 'Synthetic diagnostic'
      : null,
  'relatedAlertId': null,
};

RanchAccess _grant(String id, {AccessScope scope = AccessScope.manage}) =>
    RanchAccess(
      ranchId: id,
      scope: scope,
      name: 'Synthetic ranch',
      region: 'Region',
      district: 'District',
    );

FieldRecord _record({
  FieldRecordType type = FieldRecordType.healthEvent,
  String ranchId = _ranch,
}) => FieldRecord(
  operationId: FieldRecord.newOperationId(),
  ranchId: ranchId,
  cattleId: '33333333-3333-4333-8333-333333333333',
  cattleEarTag: 'SYNTHETIC',
  type: type,
  occurredAt: DateTime.utc(2020),
  observation: 'Synthetic field event',
  sireReference: type == FieldRecordType.naturalMating
      ? 'Synthetic sire'
      : null,
);
