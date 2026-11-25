import 'dart:async';

import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/field_record.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/field_record_sync.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/repositories/field_record_sync_repository.dart';

/// Synthetic server decisions only; no live synchronization occurs in tests.
final class FakeFieldRecordSyncRepository implements FieldRecordSyncRepository {
  @override
  bool isConfigured = true;
  Object? failure;
  Completer<void>? entered;
  Completer<List<FieldRecordSyncResult>>? pending;
  List<FieldRecordSyncResult> Function(List<FieldRecord> records)? respond;
  final requests =
      <({String accountId, String ranchId, List<FieldRecord> records})>[];

  @override
  Future<List<FieldRecordSyncResult>> synchronize({
    required String accountId,
    required String ranchId,
    required List<FieldRecord> records,
  }) async {
    requests.add((
      accountId: accountId,
      ranchId: ranchId,
      records: List.unmodifiable(records),
    ));
    entered?.complete();
    if (failure case final error?) throw error;
    if (pending case final response?) return response.future;
    return respond?.call(records) ?? confirmedFieldRecords(records);
  }
}

List<FieldRecordSyncResult> confirmedFieldRecords(List<FieldRecord> records) =>
    [
      for (final record in records)
        FieldRecordSyncResult(
          operationId: record.operationId,
          status: FieldRecordSyncStatus.accepted,
        ),
    ];
