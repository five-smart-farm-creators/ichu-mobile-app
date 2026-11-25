import 'package:ichu_mobile_app/shared/domain/model/app_language.dart';
import 'package:ichu_mobile_app/shared/domain/repositories/language_preference_repository.dart';

/// A test fixture, never a substitute for the platform adapter in production.
final class MemoryLanguagePreferences implements LanguagePreferenceRepository {
  MemoryLanguagePreferences({this.language});

  AppLanguage? language;
  bool failRead = false;
  bool failWrite = false;
  int writes = 0;

  @override
  Future<AppLanguage?> read() async {
    if (failRead) throw StateError('Preference read failed');
    return language;
  }

  @override
  Future<void> save(AppLanguage value) async {
    if (failWrite) throw StateError('Preference write failed');
    writes++;
    language = value;
  }
}
