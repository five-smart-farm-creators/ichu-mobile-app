import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/field_record.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/field_record_sync.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/infrastructure/preferences/shared_preferences_field_record_repository.dart';

const _accountA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _accountB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _ranchA = '11111111-1111-4111-8111-111111111111';
const _ranchB = '22222222-2222-4222-8222-222222222222';
const _cattleA = '33333333-3333-4333-8333-333333333333';

void main() {
  group('SharedPreferencesFieldRecordRepository', () {
    test(
      'persists mixed decisions without losing new records or cattle choices',
      () async {
        final values = <String, String>{};
        final repository = _repository(values);
        final records = List.generate(
          5,
          (_) => _record(operationId: FieldRecord.newOperationId()),
        );
        for (final record in records) {
          await repository.appendPending(
            accountId: _accountA,
            ranchId: _ranchA,
            record: record,
          );
        }
        await repository.cacheCattleOptions(
          accountId: _accountA,
          ranchId: _ranchA,
          options: [_option()],
        );
        final results = List.generate(
          4,
          (index) => FieldRecordSyncResult(
            operationId: records[index].operationId,
            status: FieldRecordSyncStatus.values[index],
            reason: index >= 2 ? 'Synthetic review reason' : null,
          ),
        );
        await repository.applySyncResults(
          accountId: _accountA,
          ranchId: _ranchA,
          submitted: records.take(4).toList(),
          results: results,
        );
        final reopened = _repository(values);
        expect(
          await reopened.readPending(accountId: _accountA, ranchId: _ranchA),
          unorderedEquals(records.skip(2)),
        );
        final issues = await reopened.readSyncIssues(
          accountId: _accountA,
          ranchId: _ranchA,
        );
        expect(issues.map((issue) => issue.status), [
          FieldRecordSyncStatus.rejected,
          FieldRecordSyncStatus.conflict,
        ]);
        expect(issues.first.reason, 'Synthetic review reason');
        expect(
          await reopened.readCattleOptions(
            accountId: _accountA,
            ranchId: _ranchA,
          ),
          [_option()],
        );
        expect(
          await reopened.readSyncIssues(accountId: _accountB, ranchId: _ranchA),
          isEmpty,
        );
        expect(
          await reopened.readSyncIssues(accountId: _accountA, ranchId: _ranchB),
          isEmpty,
        );
      },
    );

    test(
      'does not remove pending data when confirmation cannot be written',
      () async {
        final values = <String, String>{};
        final first = _repository(values);
        final record = _record();
        await first.appendPending(
          accountId: _accountA,
          ranchId: _ranchA,
          record: record,
        );
        final failing = SharedPreferencesFieldRecordRepository.withAccess(
          readString: (key) async => values[key],
          writeString: (key, value) async =>
              throw StateError('Synthetic storage failure'),
        );
        await expectLater(
          failing.applySyncResults(
            accountId: _accountA,
            ranchId: _ranchA,
            submitted: [record],
            results: [
              FieldRecordSyncResult(
                operationId: record.operationId,
                status: FieldRecordSyncStatus.accepted,
              ),
            ],
          ),
          throwsStateError,
        );
        expect(
          await first.readPending(accountId: _accountA, ranchId: _ranchA),
          [record],
        );
      },
    );

    test(
      'rejects incomplete or foreign confirmations without rewriting data',
      () async {
        final values = <String, String>{};
        final repository = _repository(values);
        final record = _record();
        await repository.appendPending(
          accountId: _accountA,
          ranchId: _ranchA,
          record: record,
        );
        final encoded = values.values.single;
        expect(
          () => repository.applySyncResults(
            accountId: _accountA,
            ranchId: _ranchA,
            submitted: [record],
            results: [],
          ),
          throwsA(isA<FieldRecordSyncFailure>()),
        );
        expect(
          () => repository.applySyncResults(
            accountId: _accountA,
            ranchId: _ranchB,
            submitted: [record],
            results: [
              FieldRecordSyncResult(
                operationId: record.operationId,
                status: FieldRecordSyncStatus.accepted,
              ),
            ],
          ),
          throwsArgumentError,
        );
        expect(values.values.single, encoded);
      },
    );

    test(
      'reads the previous v1 format without synchronization issues',
      () async {
        final values = <String, String>{};
        final repository = _repository(values);
        await repository.appendPending(
          accountId: _accountA,
          ranchId: _ranchA,
          record: _record(),
        );
        final data = jsonDecode(values.values.single) as Map<String, dynamic>;
        data.remove('syncIssues');
        values[values.keys.single] = jsonEncode(data);
        expect(
          await repository.readSyncIssues(
            accountId: _accountA,
            ranchId: _ranchA,
          ),
          isEmpty,
        );
        expect(
          await repository.readPending(accountId: _accountA, ranchId: _ranchA),
          [_record()],
        );
      },
    );
    test(
      'records and cattle choices survive a new repository instance',
      () async {
        final values = <String, String>{};
        final first = _repository(values);
        final record = _record();
        final option = _option();
        await first.appendPending(
          accountId: _accountA,
          ranchId: _ranchA,
          record: record,
        );
        await first.cacheCattleOptions(
          accountId: _accountA,
          ranchId: _ranchA,
          options: <FieldCattleOption>[option],
        );

        final reopened = _repository(values);
        expect(
          await reopened.readPending(accountId: _accountA, ranchId: _ranchA),
          <FieldRecord>[record],
        );
        expect(
          await reopened.readCattleOptions(
            accountId: _accountA,
            ranchId: _ranchA,
          ),
          <FieldCattleOption>[option],
        );
      },
    );

    test('isolates saved records between accounts and ranches', () async {
      final repository = _repository(<String, String>{});
      await repository.appendPending(
        accountId: _accountA,
        ranchId: _ranchA,
        record: _record(),
      );

      expect(
        await repository.readPending(accountId: _accountB, ranchId: _ranchA),
        isEmpty,
      );
      expect(
        await repository.readPending(accountId: _accountA, ranchId: _ranchB),
        isEmpty,
      );
    });

    test(
      'same operation retries are idempotent and content changes conflict',
      () async {
        final repository = _repository(<String, String>{});
        final record = _record();
        await repository.appendPending(
          accountId: _accountA,
          ranchId: _ranchA,
          record: record,
        );
        await repository.appendPending(
          accountId: _accountA,
          ranchId: _ranchA,
          record: record,
        );

        expect(
          await repository.readPending(accountId: _accountA, ranchId: _ranchA),
          hasLength(1),
        );
        await expectLater(
          repository.appendPending(
            accountId: _accountA,
            ranchId: _ranchA,
            record: _record(observation: 'Different content'),
          ),
          throwsStateError,
        );
        expect(
          (await repository.readPending(
            accountId: _accountA,
            ranchId: _ranchA,
          )).single.observation,
          'Health check',
        );
      },
    );

    test('invalid stored data fails closed without deleting it', () async {
      final key =
          'ichu.fieldRecord.v1.'
          '${base64Url.encode(utf8.encode(_accountA))}.'
          '${base64Url.encode(utf8.encode(_ranchA))}';
      const encoded = '{"schemaVersion":2,"records":[],"cattleOptions":[]}';
      final values = <String, String>{key: encoded};
      final repository = _repository(values);

      await expectLater(
        repository.readPending(accountId: _accountA, ranchId: _ranchA),
        throwsFormatException,
      );
      expect(values[key], encoded);
    });
  });
}

SharedPreferencesFieldRecordRepository _repository(
  Map<String, String> values,
) => SharedPreferencesFieldRecordRepository.withAccess(
  readString: (key) async => values[key],
  writeString: (key, value) async {
    values[key] = value;
  },
);

FieldRecord _record({
  String? observation = 'Health check',
  String operationId = '44444444-4444-4444-8444-444444444444',
}) => FieldRecord(
  operationId: operationId,
  ranchId: _ranchA,
  cattleId: _cattleA,
  cattleEarTag: 'TAG-3',
  type: FieldRecordType.healthEvent,
  occurredAt: DateTime.utc(2020, 11, 13, 10),
  observation: observation,
);

FieldCattleOption _option() =>
    FieldCattleOption(cattleId: _cattleA, ranchId: _ranchA, earTag: 'TAG-3');
