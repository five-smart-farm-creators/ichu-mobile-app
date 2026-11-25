import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/field_record.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/field_record_sync.dart';

void main() {
  final record = FieldRecord(
    operationId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    ranchId: '11111111-1111-4111-8111-111111111111',
    cattleId: '22222222-2222-4222-8222-222222222222',
    cattleEarTag: 'SYNTHETIC',
    type: FieldRecordType.birth,
    occurredAt: DateTime.utc(2020),
  );
  test('only accepted and duplicate results confirm delivery', () {
    for (final status in FieldRecordSyncStatus.values) {
      final result = FieldRecordSyncResult(
        operationId: record.operationId,
        status: status,
      );
      expect(
        result.confirmed,
        status == FieldRecordSyncStatus.accepted ||
            status == FieldRecordSyncStatus.duplicate,
      );
      validateFieldRecordSyncResults([record], [result]);
    }
  });
  test(
    'requires each submitted operation exactly once, regardless of UUID case',
    () {
      final result = FieldRecordSyncResult(
        operationId: record.operationId.toUpperCase(),
        status: FieldRecordSyncStatus.accepted,
      );
      validateFieldRecordSyncResults([record], [result]);
      for (final results in <List<FieldRecordSyncResult>>[
        [],
        [result, result],
        [
          const FieldRecordSyncResult(
            operationId: 'foreign',
            status: FieldRecordSyncStatus.accepted,
          ),
        ],
      ]) {
        expect(
          () => validateFieldRecordSyncResults([record], results),
          throwsA(isA<FieldRecordSyncFailure>()),
        );
      }
    },
  );
}
