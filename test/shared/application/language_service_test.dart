import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/shared/application/services/language_service.dart';
import 'package:ichu_mobile_app/shared/domain/model/app_language.dart';
import 'package:ichu_mobile_app/shared/domain/repositories/language_preference_repository.dart';

import '../../support/memory_language_preferences.dart';

void main() {
  testWidgets('timed-out writes cannot overwrite a later language selection', (
    tester,
  ) async {
    final preferences = _DelayedLanguagePreferences();
    final service = LanguageService(preferences);
    final first = service.select(AppLanguage.spanish);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(await first, isFalse);

    final second = service.select(AppLanguage.english);
    await tester.pump();
    expect(preferences.writes, hasLength(1));
    preferences.writes.first.complete();
    await tester.pump();
    expect(preferences.writes, hasLength(2));
    preferences.writes.last.complete();
    await tester.pump();

    expect(await second, isTrue);
    expect(preferences.language, AppLanguage.english);
    expect(service.current, AppLanguage.english);
    service.dispose();
  });

  test('unknown language codes are not treated as supported preferences', () {
    expect(AppLanguage.fromCode(null), isNull);
    expect(AppLanguage.fromCode('fr'), isNull);
    expect(AppLanguage.fromCode('es'), AppLanguage.spanish);
    expect(AppLanguage.fromCode('en'), AppLanguage.english);
  });

  test('English is used without a saved language', () async {
    final service = LanguageService(MemoryLanguagePreferences());
    addTearDown(service.dispose);
    await service.initialize();
    expect(service.current, AppLanguage.english);
  });

  test('a saved language is restored before the first screen', () async {
    final service = LanguageService(
      MemoryLanguagePreferences(language: AppLanguage.spanish),
    );
    addTearDown(service.dispose);
    await service.initialize();
    expect(service.current, AppLanguage.spanish);
  });

  test('storage read failures fall back to English', () async {
    final preferences = MemoryLanguagePreferences()..failRead = true;
    final service = LanguageService(preferences);
    addTearDown(service.dispose);
    await service.initialize();
    expect(service.current, AppLanguage.english);
  });

  test(
    'selection notifies listeners and persists across service instances',
    () async {
      final preferences = MemoryLanguagePreferences();
      final service = LanguageService(preferences);
      addTearDown(service.dispose);
      var notifications = 0;
      service.addListener(() => notifications++);

      expect(await service.select(AppLanguage.spanish), isTrue);
      expect(service.current, AppLanguage.spanish);
      expect(notifications, 2);
      expect(preferences.writes, 1);
      expect(service.saving, isFalse);

      final restored = LanguageService(preferences);
      addTearDown(restored.dispose);
      await restored.initialize();
      expect(restored.current, AppLanguage.spanish);
    },
  );

  test(
    'selection failures retain the language for the current session',
    () async {
      final preferences = MemoryLanguagePreferences()..failWrite = true;
      final service = LanguageService(preferences);
      addTearDown(service.dispose);
      expect(await service.select(AppLanguage.spanish), isFalse);
      expect(service.current, AppLanguage.spanish);
      expect(service.saving, isFalse);
    },
  );

  test('selecting the current language does not write to storage', () async {
    final preferences = MemoryLanguagePreferences();
    final service = LanguageService(preferences);
    addTearDown(service.dispose);
    expect(await service.select(AppLanguage.english), isTrue);
    expect(preferences.writes, 0);
  });
}

final class _DelayedLanguagePreferences
    implements LanguagePreferenceRepository {
  AppLanguage? language;
  final writes = <Completer<void>>[];

  @override
  Future<AppLanguage?> read() async => language;

  @override
  Future<void> save(AppLanguage value) async {
    final write = Completer<void>();
    writes.add(write);
    await write.future;
    language = value;
  }
}
