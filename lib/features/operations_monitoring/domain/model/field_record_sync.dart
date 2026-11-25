import 'field_record.dart';

enum FieldRecordSyncStatus { accepted, duplicate, rejected, conflict }

enum FieldRecordSyncFailureCode {
  configuration,
  contextUnavailable,
  permissionRequired,
  invalidBatch,
  invalidResponse,
  network,
  serviceUnavailable,
  storageUnavailable,
  unknown,
}

final class FieldRecordSyncFailure implements Exception {
  const FieldRecordSyncFailure(this.code);

  final FieldRecordSyncFailureCode code;
}

/// One server decision. Only accepted and duplicate decisions confirm delivery.
final class FieldRecordSyncResult {
  const FieldRecordSyncResult({
    required this.operationId,
    required this.status,
    this.reason,
  });

  final String operationId;
  final FieldRecordSyncStatus status;

  /// Server diagnostic retained for review, not trusted user-facing copy.
  final String? reason;

  bool get confirmed =>
      status == FieldRecordSyncStatus.accepted ||
      status == FieldRecordSyncStatus.duplicate;
}

/// A complete response must match every submitted operation exactly once.
void validateFieldRecordSyncResults(
  List<FieldRecord> submitted,
  List<FieldRecordSyncResult> results,
) {
  final expected = submitted.map((record) => record.operationId).toSet();
  final received = <String>{};
  if (submitted.isEmpty ||
      expected.length != submitted.length ||
      results.length != submitted.length ||
      results.any(
        (result) =>
            !expected.contains(result.operationId.toLowerCase()) ||
            !received.add(result.operationId.toLowerCase()),
      )) {
    throw const FieldRecordSyncFailure(
      FieldRecordSyncFailureCode.invalidResponse,
    );
  }
}
