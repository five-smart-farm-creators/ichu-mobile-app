import 'package:flutter/foundation.dart';

import '../../domain/model/app_language.dart';
import '../../domain/repositories/language_preference_repository.dart';

/// Coordinates language selection without coupling widgets to device storage.
final class LanguageService extends ChangeNotifier {
  LanguageService(this._preferences);

  final LanguagePreferenceRepository _preferences;
  AppLanguage _current = AppLanguage.english;
  bool _saving = false;
  bool _disposed = false;
  Future<void> _writeQueue = Future<void>.value();

  AppLanguage get current => _current;
  bool get saving => _saving;

  /// A broken preference store must not prevent the application from opening.
  Future<void> initialize() async {
    try {
      final saved = await _preferences.read().timeout(
        const Duration(seconds: 3),
      );
      if (!_disposed) _current = saved ?? AppLanguage.english;
    } catch (_) {
      // English is the product default, not the device language.
    }
  }

  /// Returns false when the language changed but could not be persisted.
  Future<bool> select(AppLanguage language) async {
    if (_disposed || _saving || language == _current) return true;
    _current = language;
    _saving = true;
    notifyListeners();
    var saved = true;
    // A timeout cannot cancel platform I/O. Queue writes on their real
    // completion so an old slow write never overwrites a newer selection.
    final write = _writeQueue.then((_) => _preferences.save(language));
    _writeQueue = write.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    try {
      await write.timeout(const Duration(seconds: 3));
    } catch (_) {
      saved = false;
    } finally {
      _saving = false;
      if (!_disposed) notifyListeners();
    }
    return saved;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
