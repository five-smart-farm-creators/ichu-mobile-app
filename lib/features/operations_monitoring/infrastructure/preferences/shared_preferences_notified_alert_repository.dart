import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/repositories/notified_alert_repository.dart';

/// Stores announced alert IDs under one preferences key per ranch.
final class SharedPreferencesNotifiedAlertRepository
    implements NotifiedAlertRepository {
  SharedPreferencesNotifiedAlertRepository(SharedPreferencesAsync preferences)
    : _readString = preferences.getString,
      _writeString = preferences.setString;

  SharedPreferencesNotifiedAlertRepository.withAccess({
    required Future<String?> Function(String key) readString,
    required Future<void> Function(String key, String value) writeString,
  }) : _readString = readString,
       _writeString = writeString;

  static const _keyPrefix = 'ichu.notifiedAlerts.v1';
  final Future<String?> Function(String key) _readString;
  final Future<void> Function(String key, String value) _writeString;

  @override
  Future<List<String>> read(String ranchId) async {
    final stored = await _readString(_key(ranchId));
    if (stored == null) return const [];
    return List<String>.of(jsonDecode(stored) as List<dynamic>);
  }

  @override
  Future<void> write(String ranchId, List<String> alertIds) =>
      _writeString(_key(ranchId), jsonEncode(alertIds));

  String _key(String ranchId) => '$_keyPrefix.${ranchId.toLowerCase()}';
}
