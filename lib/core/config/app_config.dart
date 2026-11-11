/// The deployment environment used to validate API configuration.
enum AppEnvironment { development, staging, production }

/// A safe, non-sensitive reason that API configuration is unavailable.
enum AppConfigIssue { missingApiUrl, invalidApiUrl, invalidEnvironment }

/// Immutable compile-time configuration for the future API client.
class AppConfig {
  const AppConfig._({
    required this.environment,
    required this.apiBaseUri,
    required this.issue,
  });

  /// The selected environment, falling back to development when invalid.
  final AppEnvironment environment;

  /// The normalized API base URI, or null when configuration is unusable.
  final Uri? apiBaseUri;

  /// A safe reason configuration is unusable, or null when valid.
  final AppConfigIssue? issue;

  /// Whether a valid API base URI is available.
  bool get isApiConfigured => apiBaseUri != null && issue == null;

  /// Builds configuration from supplied environment and API URL values.
  factory AppConfig.fromValues({
    String environment = 'development',
    String apiBaseUrl = '',
  }) {
    final selectedEnvironment = switch (environment) {
      'development' => AppEnvironment.development,
      'staging' => AppEnvironment.staging,
      'production' => AppEnvironment.production,
      _ => null,
    };

    if (selectedEnvironment == null) {
      return const AppConfig._(
        environment: AppEnvironment.development,
        apiBaseUri: null,
        issue: AppConfigIssue.invalidEnvironment,
      );
    }

    if (apiBaseUrl.trim().isEmpty) {
      return AppConfig._(
        environment: selectedEnvironment,
        apiBaseUri: null,
        issue: AppConfigIssue.missingApiUrl,
      );
    }

    if (apiBaseUrl != apiBaseUrl.trim()) {
      return AppConfig._(
        environment: selectedEnvironment,
        apiBaseUri: null,
        issue: AppConfigIssue.invalidApiUrl,
      );
    }

    if (apiBaseUrl.contains('@')) {
      return AppConfig._(
        environment: selectedEnvironment,
        apiBaseUri: null,
        issue: AppConfigIssue.invalidApiUrl,
      );
    }

    final Uri parsedUri;
    try {
      parsedUri = Uri.parse(apiBaseUrl);
    } on FormatException {
      return AppConfig._(
        environment: selectedEnvironment,
        apiBaseUri: null,
        issue: AppConfigIssue.invalidApiUrl,
      );
    }

    final scheme = parsedUri.scheme.toLowerCase();
    final host = parsedUri.host.toLowerCase();
    final path = parsedUri.path;
    final isValidPath =
        path.isEmpty || path == '/' || path == '/api/v1' || path == '/api/v1/';
    final isDevelopmentLoopback =
        selectedEnvironment == AppEnvironment.development &&
        (host == 'localhost' ||
            host == '127.0.0.1' ||
            host == '::1' ||
            host == '10.0.2.2');

    if (!parsedUri.hasAuthority ||
        host.isEmpty ||
        (scheme != 'http' && scheme != 'https') ||
        parsedUri.authority.contains('@') ||
        parsedUri.hasQuery ||
        parsedUri.hasFragment ||
        path.contains('//') ||
        !isValidPath ||
        (scheme == 'http' && !isDevelopmentLoopback)) {
      return AppConfig._(
        environment: selectedEnvironment,
        apiBaseUri: null,
        issue: AppConfigIssue.invalidApiUrl,
      );
    }

    return AppConfig._(
      environment: selectedEnvironment,
      apiBaseUri: parsedUri.replace(path: '/api/v1'),
      issue: null,
    );
  }

  /// Reads configuration from compile-time `APP_ENV` and
  /// `ICHU_API_BASE_URL` declarations.
  factory AppConfig.fromEnvironment() => AppConfig.fromValues(
    environment: const String.fromEnvironment(
      'APP_ENV',
      defaultValue: bool.fromEnvironment('dart.vm.product')
          ? 'production'
          : 'development',
    ),
    apiBaseUrl: const String.fromEnvironment(
      'ICHU_API_BASE_URL',
      defaultValue: '',
    ),
  );
}
