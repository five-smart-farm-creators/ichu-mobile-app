import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/field_record.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/infrastructure/preferences/shared_preferences_field_record_repository.dart';

const _accountA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _accountB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _ranchA = '11111111-1111-4111-8111-111111111111';
const _ranchB = '22222222-2222-4222-8222-222222222222';
const _cattleA = '33333333-3333-4333-8333-333333333333';

void main() {
  group('SharedPreferencesFieldRecordRepository', () {
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

FieldRecord _record({String? observation = 'Health check'}) => FieldRecord(
  operationId: '44444444-4444-4444-8444-444444444444',
  ranchId: _ranchA,
  cattleId: _cattleA,
  cattleEarTag: 'TAG-3',
  type: FieldRecordType.healthEvent,
  occurredAt: DateTime.utc(2020, 11, 13, 10),
  observation: observation,
);

FieldCattleOption _option() =>
    FieldCattleOption(cattleId: _cattleA, ranchId: _ranchA, earTag: 'TAG-3');
