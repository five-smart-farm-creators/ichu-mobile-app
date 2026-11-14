import '../model/field_record.dart';
import '../model/field_record_sync.dart';

abstract interface class FieldRecordRepository {
  Future<List<FieldRecordSyncResult>> readSyncIssues({
    required String accountId,
    required String ranchId,
  });

  /// Atomically removes confirmed records and retains failed decisions, without
  /// replacing records captured while the batch was in flight.
  Future<void> applySyncResults({
    required String accountId,
    required String ranchId,
    required List<FieldRecord> submitted,
    required List<FieldRecordSyncResult> results,
  });

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
