import 'dart:async';

import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/field_record.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/field_record_sync.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/repositories/field_record_repository.dart';

/// In-memory test fixture; production storage uses the platform preferences adapter.
final class MemoryFieldRecordRepository implements FieldRecordRepository {
  final Map<String, List<FieldRecord>> _records = <String, List<FieldRecord>>{};
  final Map<String, List<FieldCattleOption>> _cattleOptions =
      <String, List<FieldCattleOption>>{};
  Completer<void>? appendEntered;
  Completer<void>? appendBarrier;
  Object? applyFailure;
  final Map<String, List<FieldRecordSyncResult>> _issues = {};

  @override
  Future<List<FieldRecordSyncResult>> readSyncIssues({
    required String accountId,
    required String ranchId,
  }) async => List<FieldRecordSyncResult>.unmodifiable(
    _issues[_key(accountId, ranchId)] ?? [],
  );

  @override
  Future<void> applySyncResults({
    required String accountId,
    required String ranchId,
    required List<FieldRecord> submitted,
    required List<FieldRecordSyncResult> results,
  }) async {
    if (applyFailure case final failure?) throw failure;
    validateFieldRecordSyncResults(submitted, results);
    final key = _key(accountId, ranchId);
    final confirmed = results
        .where((result) => result.confirmed)
        .map((result) => result.operationId)
        .toSet();
    _records[key] = (_records[key] ?? [])
        .where((record) => !confirmed.contains(record.operationId))
        .toList();
    final issues = {
      for (final issue in _issues[key] ?? <FieldRecordSyncResult>[])
        issue.operationId: issue,
    };
    for (final result in results) {
      if (result.confirmed) {
        issues.remove(result.operationId);
      } else {
        issues[result.operationId] = result;
      }
    }
    _issues[key] = issues.values.toList();
  }

  String _key(String accountId, String ranchId) =>
      '${accountId.toLowerCase()}|${ranchId.toLowerCase()}';

  @override
  Future<List<FieldRecord>> readPending({
    required String accountId,
    required String ranchId,
  }) async => List<FieldRecord>.unmodifiable(
    _records[_key(accountId, ranchId)] ?? const <FieldRecord>[],
  );

  @override
  Future<void> appendPending({
    required String accountId,
    required String ranchId,
    required FieldRecord record,
  }) async {
    appendEntered?.complete();
    await appendBarrier?.future;
    final key = _key(accountId, ranchId);
    _records[key] = <FieldRecord>[record, ...?_records[key]];
  }

  @override
  Future<List<FieldCattleOption>> readCattleOptions({
    required String accountId,
    required String ranchId,
  }) async => List<FieldCattleOption>.unmodifiable(
    _cattleOptions[_key(accountId, ranchId)] ?? const <FieldCattleOption>[],
  );

  @override
  Future<void> cacheCattleOptions({
    required String accountId,
    required String ranchId,
    required List<FieldCattleOption> options,
  }) async {
    final key = _key(accountId, ranchId);
    final byId = <String, FieldCattleOption>{
      for (final option in _cattleOptions[key] ?? const <FieldCattleOption>[])
        option.cattleId.toLowerCase(): option,
      for (final option in options) option.cattleId.toLowerCase(): option,
    };
    _cattleOptions[key] = byId.values.toList(growable: false);
  }
}
