/// Supported product languages, independent of platform locale detection.
enum AppLanguage {
  english('en'),
  spanish('es');

  const AppLanguage(this.code);

  final String code;

  /// Unknown or obsolete stored values are ignored by the preference adapter.
  static AppLanguage? fromCode(String? code) {
    for (final language in values) {
      if (language.code == code) return language;
    }
    return null;
  }
}
