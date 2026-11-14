import '../../domain/model/field_record.dart';
import '../../domain/model/field_record_sync.dart';
import '../../domain/model/monitoring_failure.dart';
import '../../domain/repositories/field_record_sync_repository.dart';
import '../http/monitoring_api_client.dart';

/// Maps the mobile batch contract, not Edge synchronization or cattle caches.
final class RestFieldRecordSyncRepository implements FieldRecordSyncRepository {
  const RestFieldRecordSyncRepository({required this.api});

  final MonitoringApiClient? api;

  @override
  bool get isConfigured => api?.isConfigured ?? false;

  @override
  Future<List<FieldRecordSyncResult>> synchronize({
    required String accountId,
    required String ranchId,
    required List<FieldRecord> records,
  }) async {
    final client = api;
    if (client == null || !client.isConfigured) {
      throw const FieldRecordSyncFailure(
        FieldRecordSyncFailureCode.configuration,
      );
    }
    final batch = List<FieldRecord>.unmodifiable(records);
    try {
      final payload = await client.synchronizeFieldRecords(
        accountId: accountId,
        ranchId: ranchId,
        records: batch,
      );
      if (payload is! Map<String, dynamic> ||
          payload['results'] is! List<dynamic>) {
        throw const FormatException('Missing mobile batch results.');
      }
      final results = (payload['results'] as List<dynamic>)
          .map(_mapResult)
          .toList(growable: false);
      validateFieldRecordSyncResults(batch, results);
      return List<FieldRecordSyncResult>.unmodifiable(results);
    } on FieldRecordSyncFailure {
      rethrow;
    } on MonitoringFailure catch (failure) {
      throw FieldRecordSyncFailure(switch (failure.code) {
        MonitoringFailureCode.configuration =>
          FieldRecordSyncFailureCode.configuration,
        MonitoringFailureCode.contextUnavailable ||
        MonitoringFailureCode.unauthenticated =>
          FieldRecordSyncFailureCode.contextUnavailable,
        MonitoringFailureCode.forbidden =>
          FieldRecordSyncFailureCode.permissionRequired,
        MonitoringFailureCode.network => FieldRecordSyncFailureCode.network,
        MonitoringFailureCode.serviceUnavailable =>
          FieldRecordSyncFailureCode.serviceUnavailable,
        MonitoringFailureCode.invalidResponse =>
          FieldRecordSyncFailureCode.invalidResponse,
        _ => FieldRecordSyncFailureCode.unknown,
      });
    } on FormatException {
      throw const FieldRecordSyncFailure(
        FieldRecordSyncFailureCode.invalidResponse,
      );
    }
  }

  FieldRecordSyncResult _mapResult(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['kind'] != 'LivestockOperation' ||
        value['id'] is! String ||
        value['relatedAlertId'] != null ||
        (value['reason'] != null && value['reason'] is! String)) {
      throw const FormatException('Invalid mobile batch entry.');
    }
    final status = switch (value['status']) {
      'Accepted' => FieldRecordSyncStatus.accepted,
      'Duplicate' => FieldRecordSyncStatus.duplicate,
      'Rejected' => FieldRecordSyncStatus.rejected,
      'Conflict' => FieldRecordSyncStatus.conflict,
      _ => throw const FormatException('Unknown mobile batch decision.'),
    };
    return FieldRecordSyncResult(
      operationId: (value['id'] as String).toLowerCase(),
      status: status,
      reason: value['reason'] as String?,
    );
  }
}
