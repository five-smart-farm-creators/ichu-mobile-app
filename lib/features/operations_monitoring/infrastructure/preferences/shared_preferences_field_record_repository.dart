import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/model/field_record.dart';
import '../../domain/repositories/field_record_repository.dart';

/// Stores pending field events and cattle choices in account/ranch-scoped keys.
final class SharedPreferencesFieldRecordRepository
    implements FieldRecordRepository {
  static const _schemaVersion = 1;
  static const _keyPrefix = 'ichu.fieldRecord.v1';
  final Future<String?> Function(String key) _readString;
  final Future<void> Function(String key, String value) _writeString;
  Future<void> _operationQueue = Future<void>.value();

  SharedPreferencesFieldRecordRepository(SharedPreferencesAsync preferences)
    : _readString = preferences.getString,
      _writeString = preferences.setString;

  SharedPreferencesFieldRecordRepository.withAccess({
    required Future<String?> Function(String key) readString,
    required Future<void> Function(String key, String value) writeString,
  }) : _readString = readString,
       _writeString = writeString;

  @override
  Future<List<FieldRecord>> readPending({
    required String accountId,
    required String ranchId,
  }) => _withScope(accountId, ranchId, (key) async {
    final data = await _readData(key);
    return List<FieldRecord>.unmodifiable(data.records);
  });

  @override
  Future<void> appendPending({
    required String accountId,
    required String ranchId,
    required FieldRecord record,
  }) => _withScope(accountId, ranchId, (key) async {
    if (!_sameId(record.ranchId, ranchId)) {
      throw ArgumentError('The field record belongs to a different ranch.');
    }
    final data = await _readData(key);
    final existing = data.records.where(
      (item) => _sameId(item.operationId, record.operationId),
    );
    if (existing.isNotEmpty) {
      if (existing.single == record) return;
      throw StateError(
        'A field record identifier already has different content.',
      );
    }
    final updated = _FieldRecordData(
      records: <FieldRecord>[record, ...data.records],
      cattleOptions: data.cattleOptions,
    );
    await _writeData(key, updated);
  });

  @override
  Future<List<FieldCattleOption>> readCattleOptions({
    required String accountId,
    required String ranchId,
  }) => _withScope(accountId, ranchId, (key) async {
    final data = await _readData(key);
    return List<FieldCattleOption>.unmodifiable(data.cattleOptions);
  });

  @override
  Future<void> cacheCattleOptions({
    required String accountId,
    required String ranchId,
    required List<FieldCattleOption> options,
  }) => _withScope(accountId, ranchId, (key) async {
    if (options.any((option) => !_sameId(option.ranchId, ranchId))) {
      throw ArgumentError(
        'A cached cattle choice belongs to a different ranch.',
      );
    }
    final data = await _readData(key);
    final byId = <String, FieldCattleOption>{
      for (final option in data.cattleOptions)
        option.cattleId.toLowerCase(): option,
      for (final option in options) option.cattleId.toLowerCase(): option,
    };
    await _writeData(
      key,
      _FieldRecordData(
        records: data.records,
        cattleOptions: byId.values.toList(growable: false),
      ),
    );
  });

  Future<T> _withScope<T>(
    String accountId,
    String ranchId,
    Future<T> Function(String key) operation,
  ) {
    final key = _storageKey(accountId, ranchId);
    final result = _operationQueue.then((_) => operation(key));
    _operationQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  Future<_FieldRecordData> _readData(String key) async {
    final encoded = await _readString(key);
    if (encoded == null) return const _FieldRecordData.empty();
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic> ||
          decoded['schemaVersion'] != _schemaVersion ||
          decoded['records'] is! List<dynamic> ||
          decoded['cattleOptions'] is! List<dynamic>) {
        throw const FormatException('Unknown local field record format.');
      }
      final records = (decoded['records'] as List<dynamic>)
          .map(_decodeRecord)
          .toList(growable: false);
      final options = (decoded['cattleOptions'] as List<dynamic>)
          .map(_decodeCattleOption)
          .toList(growable: false);
      _ensureUnique(records.map((record) => record.operationId));
      _ensureUnique(options.map((option) => option.cattleId));
      return _FieldRecordData(records: records, cattleOptions: options);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Stored field records could not be read.');
    }
  }

  Future<void> _writeData(String key, _FieldRecordData data) => _writeString(
    key,
    jsonEncode(<String, Object?>{
      'schemaVersion': _schemaVersion,
      'records': data.records.map(_encodeRecord).toList(growable: false),
      'cattleOptions': data.cattleOptions
          .map(_encodeCattleOption)
          .toList(growable: false),
    }),
  );

  Map<String, Object?> _encodeRecord(FieldRecord record) => <String, Object?>{
    'operationId': record.operationId,
    'ranchId': record.ranchId,
    'cattleId': record.cattleId,
    'cattleEarTag': record.cattleEarTag,
    'type': record.type.name,
    'occurredAt': record.occurredAt.toIso8601String(),
    'observation': record.observation,
    'sireReference': record.sireReference,
  };

  FieldRecord _decodeRecord(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid stored field record.');
    }
    try {
      return FieldRecord(
        operationId: _requiredString(value, 'operationId'),
        ranchId: _requiredString(value, 'ranchId'),
        cattleId: _requiredString(value, 'cattleId'),
        cattleEarTag: _requiredString(value, 'cattleEarTag'),
        type: FieldRecordType.values.byName(_requiredString(value, 'type')),
        occurredAt: DateTime.parse(_requiredString(value, 'occurredAt')),
        observation: _optionalString(value, 'observation'),
        sireReference: _optionalString(value, 'sireReference'),
      );
    } catch (_) {
      throw const FormatException('Invalid stored field record.');
    }
  }

  Map<String, Object?> _encodeCattleOption(FieldCattleOption option) =>
      <String, Object?>{
        'cattleId': option.cattleId,
        'ranchId': option.ranchId,
        'earTag': option.earTag,
      };

  FieldCattleOption _decodeCattleOption(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid cached cattle choice.');
    }
    try {
      return FieldCattleOption(
        cattleId: _requiredString(value, 'cattleId'),
        ranchId: _requiredString(value, 'ranchId'),
        earTag: _requiredString(value, 'earTag'),
      );
    } catch (_) {
      throw const FormatException('Invalid cached cattle choice.');
    }
  }

  String _requiredString(Map<String, dynamic> value, String key) {
    final item = value[key];
    if (item is! String || item.trim().isEmpty) {
      throw const FormatException('A stored field is missing.');
    }
    return item;
  }

  String? _optionalString(Map<String, dynamic> value, String key) {
    final item = value[key];
    if (item != null && item is! String) {
      throw const FormatException('A stored field has an invalid type.');
    }
    return item as String?;
  }

  void _ensureUnique(Iterable<String> ids) {
    final unique = <String>{};
    for (final id in ids) {
      if (!unique.add(id.toLowerCase())) {
        throw const FormatException('Stored field identifiers are repeated.');
      }
    }
  }

  String _storageKey(String accountId, String ranchId) {
    if (!_isUuid(accountId) || !_isUuid(ranchId)) {
      throw ArgumentError('A valid account and ranch are required.');
    }
    final accountKey = base64Url.encode(utf8.encode(accountId.toLowerCase()));
    final ranchKey = base64Url.encode(utf8.encode(ranchId.toLowerCase()));
    return '$_keyPrefix.$accountKey.$ranchKey';
  }

  bool _sameId(String left, String right) =>
      left.toLowerCase() == right.toLowerCase();

  bool _isUuid(String value) =>
      RegExp(
        r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$',
      ).hasMatch(value) &&
      value.replaceAll('-', '').replaceAll('0', '').isNotEmpty;
}

final class _FieldRecordData {
  const _FieldRecordData({required this.records, required this.cattleOptions});

  const _FieldRecordData.empty()
    : records = const <FieldRecord>[],
      cattleOptions = const <FieldCattleOption>[];

  final List<FieldRecord> records;
  final List<FieldCattleOption> cattleOptions;
}
