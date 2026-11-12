import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/iam/infrastructure/configuration/firebase_client_config.dart';

void main() {
  group('FirebaseClientConfig', () {
    test('does not configure Firebase when values are absent', () {
      final config = FirebaseClientConfig.fromValues(
        platform: FirebaseNativePlatform.android,
      );

      expect(config.isConfigured, isFalse);
      expect(config.options, isNull);
    });

    test('does not configure unsupported platforms', () {
      final config = _config(platform: FirebaseNativePlatform.unsupported);

      expect(config.isConfigured, isFalse);
      expect(config.options, isNull);
    });

    test('builds Android options from matching native app and sender IDs', () {
      final config = _config(platform: FirebaseNativePlatform.android);

      expect(config.isConfigured, isTrue);
      expect(config.options?.apiKey, 'test-api-key');
      expect(config.options?.projectId, 'test-project');
      expect(config.options?.messagingSenderId, '123456789');
      expect(config.options?.appId, '1:123456789:android:test-app');
      expect(config.options?.iosBundleId, isNull);
    });

    test('builds iOS options only with an explicit bundle ID', () {
      final config = _config(platform: FirebaseNativePlatform.ios);

      expect(config.isConfigured, isTrue);
      expect(config.options?.appId, '1:123456789:ios:test-app');
      expect(config.options?.iosBundleId, 'com.example.ichu.test');
    });

    test('rejects missing iOS bundle ID', () {
      final config = _config(
        platform: FirebaseNativePlatform.ios,
        iosBundleId: '',
      );

      expect(config.isConfigured, isFalse);
      expect(config.options, isNull);
    });

    test('rejects native app IDs for the other platform', () {
      final androidConfig = _config(
        platform: FirebaseNativePlatform.android,
        androidAppId: '1:123456789:ios:test-app',
      );
      final iosConfig = _config(
        platform: FirebaseNativePlatform.ios,
        iosAppId: '1:123456789:android:test-app',
      );

      expect(androidConfig.isConfigured, isFalse);
      expect(androidConfig.options, isNull);
      expect(iosConfig.isConfigured, isFalse);
      expect(iosConfig.options, isNull);
    });

    test('rejects app IDs with a mismatched sender ID', () {
      final config = _config(
        platform: FirebaseNativePlatform.android,
        androidAppId: '1:987654321:android:test-app',
      );

      expect(config.isConfigured, isFalse);
      expect(config.options, isNull);
    });

    test('rejects values containing whitespace', () {
      final config = _config(
        platform: FirebaseNativePlatform.android,
        apiKey: 'test api key',
      );

      expect(config.isConfigured, isFalse);
      expect(config.options, isNull);
    });

    test('does not include configuration values in its string form', () {
      final config = _config(platform: FirebaseNativePlatform.ios);

      expect(config.toString(), isNot(contains('test-api-key')));
      expect(config.toString(), isNot(contains('test-app')));
      expect(config.toString(), isNot(contains('123456789')));
      expect(config.toString(), isNot(contains('com.example')));
    });
  });
}

FirebaseClientConfig _config({
  required FirebaseNativePlatform platform,
  String apiKey = 'test-api-key',
  String projectId = 'test-project',
  String messagingSenderId = '123456789',
  String androidAppId = '1:123456789:android:test-app',
  String iosAppId = '1:123456789:ios:test-app',
  String iosBundleId = 'com.example.ichu.test',
}) {
  return FirebaseClientConfig.fromValues(
    platform: platform,
    apiKey: apiKey,
    projectId: projectId,
    messagingSenderId: messagingSenderId,
    androidAppId: androidAppId,
    iosAppId: iosAppId,
    iosBundleId: iosBundleId,
  );
}
