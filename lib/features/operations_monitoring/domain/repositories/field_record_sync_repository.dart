import '../model/field_record.dart';
import '../model/field_record_sync.dart';

abstract interface class FieldRecordSyncRepository {
  // A conservative mobile chunk below the backend's default 500-entry limit.
  static const int batchSize = 50;

  bool get isConfigured;

  Future<List<FieldRecordSyncResult>> synchronize({
    required String accountId,
    required String ranchId,
    required List<FieldRecord> records,
  });
}
