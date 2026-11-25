import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/model/app_language.dart';
import '../../domain/repositories/language_preference_repository.dart';

/// Stores a language code using the platform's non-sensitive preferences API.
final class DeviceLanguagePreferenceRepository
    implements LanguagePreferenceRepository {
  DeviceLanguagePreferenceRepository(this._preferences);

  static const _key = 'ichu.language';
  final SharedPreferencesAsync _preferences;

  @override
  Future<AppLanguage?> read() async =>
      AppLanguage.fromCode(await _preferences.getString(_key));

  @override
  Future<void> save(AppLanguage language) =>
      _preferences.setString(_key, language.code);
}
