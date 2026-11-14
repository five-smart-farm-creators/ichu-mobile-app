import 'dart:math';

enum FieldRecordType {
  healthEvent,
  birth,
  naturalMating,
  abortion,
  heatObserved,
}

/// An unsynchronized field event captured for one account and ranch.
final class FieldRecord {
  factory FieldRecord({
    required String operationId,
    required String ranchId,
    required String cattleId,
    required String cattleEarTag,
    required FieldRecordType type,
    required DateTime occurredAt,
    String? observation,
    String? sireReference,
  }) {
    final normalizedObservation = _normalizeOptional(observation);
    final normalizedSireReference = _normalizeOptional(sireReference);
    if (!_isUuid(operationId) ||
        !_isUuid(ranchId) ||
        !_isUuid(cattleId) ||
        cattleEarTag.trim().isEmpty ||
        cattleEarTag.trim().length > maximumCattleEarTagLength ||
        (normalizedObservation?.length ?? 0) > maximumObservationLength ||
        (normalizedSireReference?.length ?? 0) > maximumSireReferenceLength ||
        (type != FieldRecordType.naturalMating &&
            normalizedSireReference != null)) {
      throw ArgumentError('Invalid field record.');
    }

    return FieldRecord._(
      operationId: operationId.toLowerCase(),
      ranchId: ranchId.toLowerCase(),
      cattleId: cattleId.toLowerCase(),
      cattleEarTag: cattleEarTag.trim(),
      type: type,
      occurredAt: occurredAt.toUtc(),
      observation: normalizedObservation,
      sireReference: normalizedSireReference,
    );
  }

  const FieldRecord._({
    required this.operationId,
    required this.ranchId,
    required this.cattleId,
    required this.cattleEarTag,
    required this.type,
    required this.occurredAt,
    required this.observation,
    required this.sireReference,
  });

  static const int maximumObservationLength = 500;
  static const int maximumSireReferenceLength = 80;
  static const int maximumCattleEarTagLength = 30;
  static const Duration maximumFutureOccurrenceOffset = Duration(minutes: 5);

  final String operationId;
  final String ranchId;
  final String cattleId;
  final String cattleEarTag;
  final FieldRecordType type;
  final DateTime occurredAt;
  final String? observation;
  final String? sireReference;

  static String newOperationId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0'));
    final value = hex.join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }

  static bool _isUuid(String value) =>
      RegExp(
        r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$',
      ).hasMatch(value) &&
      value.replaceAll('-', '').replaceAll('0', '').isNotEmpty;

  static String? _normalizeOptional(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  @override
  bool operator ==(Object other) =>
      other is FieldRecord &&
      operationId == other.operationId &&
      ranchId == other.ranchId &&
      cattleId == other.cattleId &&
      cattleEarTag == other.cattleEarTag &&
      type == other.type &&
      occurredAt == other.occurredAt &&
      observation == other.observation &&
      sireReference == other.sireReference;

  @override
  int get hashCode => Object.hash(
    operationId,
    ranchId,
    cattleId,
    cattleEarTag,
    type,
    occurredAt,
    observation,
    sireReference,
  );
}

/// A locally cached cattle choice that was returned by an authorized read.
final class FieldCattleOption {
  factory FieldCattleOption({
    required String cattleId,
    required String ranchId,
    required String earTag,
  }) {
    final normalizedEarTag = earTag.trim();
    if (!FieldRecord._isUuid(cattleId) ||
        !FieldRecord._isUuid(ranchId) ||
        normalizedEarTag.isEmpty ||
        normalizedEarTag.length > FieldRecord.maximumCattleEarTagLength) {
      throw ArgumentError('Invalid cached cattle choice.');
    }

    return FieldCattleOption._(
      cattleId: cattleId.toLowerCase(),
      ranchId: ranchId.toLowerCase(),
      earTag: normalizedEarTag,
    );
  }

  const FieldCattleOption._({
    required this.cattleId,
    required this.ranchId,
    required this.earTag,
  });

  final String cattleId;
  final String ranchId;
  final String earTag;

  @override
  bool operator ==(Object other) =>
      other is FieldCattleOption &&
      cattleId == other.cattleId &&
      ranchId == other.ranchId &&
      earTag == other.earTag;

  @override
  int get hashCode => Object.hash(cattleId, ranchId, earTag);
}
