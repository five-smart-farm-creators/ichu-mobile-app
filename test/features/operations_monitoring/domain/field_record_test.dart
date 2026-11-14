import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/field_record.dart';

const _ranchId = '11111111-1111-4111-8111-111111111111';
const _cattleId = '22222222-2222-4222-8222-222222222222';
const _operationId = '33333333-3333-4333-8333-333333333333';

void main() {
  group('FieldRecord', () {
    test(
      'normalizes optional values and event time without losing identity',
      () {
        final occurredAt = DateTime(2020, 11, 13, 10, 30);
        final record = FieldRecord(
          operationId: _operationId,
          ranchId: _ranchId,
          cattleId: _cattleId,
          cattleEarTag: ' TAG-7 ',
          type: FieldRecordType.naturalMating,
          occurredAt: occurredAt,
          observation: '  Observed in the east pasture  ',
          sireReference: '  Bull 4  ',
        );

        expect(record.operationId, _operationId);
        expect(record.ranchId, _ranchId);
        expect(record.cattleId, _cattleId);
        expect(record.cattleEarTag, 'TAG-7');
        expect(record.occurredAt, occurredAt.toUtc());
        expect(record.observation, 'Observed in the east pasture');
        expect(record.sireReference, 'Bull 4');
      },
    );

    test('accepts only supported field event details', () {
      expect(
        () => _record(observation: List<String>.filled(501, 'x').join()),
        throwsArgumentError,
      );
      expect(
        () => _record(type: FieldRecordType.healthEvent, sireReference: 'Bull'),
        throwsArgumentError,
      );
      expect(
        () => _record(
          type: FieldRecordType.naturalMating,
          sireReference: List<String>.filled(81, 'x').join(),
        ),
        throwsArgumentError,
      );
    });

    test('generates unique UUID version 4 operation identifiers', () {
      final first = FieldRecord.newOperationId();
      final second = FieldRecord.newOperationId();

      expect(
        first,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(second, isNot(first));
    });
  });
}

FieldRecord _record({
  FieldRecordType type = FieldRecordType.healthEvent,
  String? observation,
  String? sireReference,
  DateTime? occurredAt,
}) => FieldRecord(
  operationId: _operationId,
  ranchId: _ranchId,
  cattleId: _cattleId,
  cattleEarTag: 'TAG-7',
  type: type,
  occurredAt: occurredAt ?? DateTime.utc(2020, 11, 13),
  observation: observation,
  sireReference: sireReference,
);
