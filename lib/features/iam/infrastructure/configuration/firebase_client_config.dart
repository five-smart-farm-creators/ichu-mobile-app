import 'package:firebase_core/firebase_core.dart';

enum FirebaseNativePlatform { android, ios, unsupported }

/// Compile-time Firebase options for the supported native application targets.
///
/// Values are supplied through `--dart-define`; this type deliberately avoids
/// including them in its string representation.
final class FirebaseClientConfig {
  FirebaseClientConfig._({
    required this.platform,
    required this._apiKey,
    required this._projectId,
    required this._messagingSenderId,
    required this._androidAppId,
    required this._iosAppId,
    required this._iosBundleId,
  });

  factory FirebaseClientConfig.fromValues({
    required FirebaseNativePlatform platform,
    String apiKey = '',
    String projectId = '',
    String messagingSenderId = '',
    String androidAppId = '',
    String iosAppId = '',
    String iosBundleId = '',
  }) {
    return FirebaseClientConfig._(
      platform: platform,
      apiKey: apiKey,
      projectId: projectId,
      messagingSenderId: messagingSenderId,
      androidAppId: androidAppId,
      iosAppId: iosAppId,
      iosBundleId: iosBundleId,
    );
  }

  factory FirebaseClientConfig.fromEnvironment(
    FirebaseNativePlatform platform,
  ) {
    const apiKey = String.fromEnvironment('ICHU_FIREBASE_API_KEY');
    const projectId = String.fromEnvironment('ICHU_FIREBASE_PROJECT_ID');
    const messagingSenderId = String.fromEnvironment(
      'ICHU_FIREBASE_MESSAGING_SENDER_ID',
    );
    const androidAppId = String.fromEnvironment('ICHU_FIREBASE_ANDROID_APP_ID');
    const iosAppId = String.fromEnvironment('ICHU_FIREBASE_IOS_APP_ID');
    const iosBundleId = String.fromEnvironment('ICHU_FIREBASE_IOS_BUNDLE_ID');

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

  final FirebaseNativePlatform platform;
  final String _apiKey;
  final String _projectId;
  final String _messagingSenderId;
  final String _androidAppId;
  final String _iosAppId;
  final String _iosBundleId;

  bool get isConfigured {
    if (platform == FirebaseNativePlatform.unsupported ||
        !_hasValue(_apiKey) ||
        !_hasValue(_projectId) ||
        !_hasValue(_messagingSenderId)) {
      return false;
    }

    return switch (platform) {
      FirebaseNativePlatform.android => _hasNativeAppId(
        _androidAppId,
        'android',
      ),
      FirebaseNativePlatform.ios =>
        _hasNativeAppId(_iosAppId, 'ios') && _hasValue(_iosBundleId),
      FirebaseNativePlatform.unsupported => false,
    };
  }

  /// Returns null unless all options required by this native target are valid.
  FirebaseOptions? get options {
    if (!isConfigured) return null;

    return FirebaseOptions(
      apiKey: _apiKey,
      appId: switch (platform) {
        FirebaseNativePlatform.android => _androidAppId,
        FirebaseNativePlatform.ios => _iosAppId,
        FirebaseNativePlatform.unsupported => '',
      },
      messagingSenderId: _messagingSenderId,
      projectId: _projectId,
      iosBundleId: platform == FirebaseNativePlatform.ios ? _iosBundleId : null,
    );
  }

  bool _hasNativeAppId(String appId, String expectedPlatform) {
    if (!_hasValue(appId)) return false;

    final parts = appId.split(':');
    return parts.length == 4 &&
        parts[0] == '1' &&
        parts[1] == _messagingSenderId &&
        parts[2] == expectedPlatform &&
        _hasValue(parts[3]);
  }

  static bool _hasValue(String value) =>
      value.isNotEmpty && !value.contains(RegExp(r'\s'));

  @override
  String toString() => 'FirebaseClientConfig(configured: $isConfigured)';
}
