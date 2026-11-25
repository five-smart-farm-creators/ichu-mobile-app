import '../model/app_language.dart';

/// Persists only a non-sensitive interface preference, never session data.
abstract interface class LanguagePreferenceRepository {
  Future<AppLanguage?> read();
  Future<void> save(AppLanguage language);
}
