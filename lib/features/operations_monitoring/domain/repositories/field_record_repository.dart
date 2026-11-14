import '../model/field_record.dart';

abstract interface class FieldRecordRepository {
  Future<List<FieldRecord>> readPending({
    required String accountId,
    required String ranchId,
  });

  Future<void> appendPending({
    required String accountId,
    required String ranchId,
    required FieldRecord record,
  });

  Future<List<FieldCattleOption>> readCattleOptions({
    required String accountId,
    required String ranchId,
  });

  Future<void> cacheCattleOptions({
    required String accountId,
    required String ranchId,
    required List<FieldCattleOption> options,
  });
}
