import 'package:flutter_test/flutter_test.dart';

import 'package:ichu_mobile_app/core/config/app_config.dart';

void main() {
  group('AppConfig.fromValues', () {
    final cases =
        <
          ({
            String description,
            String environment,
            String apiBaseUrl,
            AppEnvironment expectedEnvironment,
            String? expectedUri,
            AppConfigIssue? expectedIssue,
          })
        >[
          (
            description: 'reports a missing API URL',
            environment: 'development',
            apiBaseUrl: '',
            expectedEnvironment: AppEnvironment.development,
            expectedUri: null,
            expectedIssue: AppConfigIssue.missingApiUrl,
          ),
          (
            description:
                'rejects an invalid environment without retaining input',
            environment: 'production;secret=value',
            apiBaseUrl: 'https://api.example.test',
            expectedEnvironment: AppEnvironment.development,
            expectedUri: null,
            expectedIssue: AppConfigIssue.invalidEnvironment,
          ),
          (
            description: 'normalizes an HTTPS URL with the versioned path',
            environment: 'production',
            apiBaseUrl: 'https://api.example.test/api/v1/',
            expectedEnvironment: AppEnvironment.production,
            expectedUri: 'https://api.example.test/api/v1',
            expectedIssue: null,
          ),
          (
            description: 'adds the versioned path to an unversioned HTTPS URL',
            environment: 'staging',
            apiBaseUrl: 'https://api.example.test',
            expectedEnvironment: AppEnvironment.staging,
            expectedUri: 'https://api.example.test/api/v1',
            expectedIssue: null,
          ),
          (
            description: 'adds the versioned path to an HTTPS host root',
            environment: 'production',
            apiBaseUrl: 'https://api.example.test/',
            expectedEnvironment: AppEnvironment.production,
            expectedUri: 'https://api.example.test/api/v1',
            expectedIssue: null,
          ),
          (
            description: 'rejects an arbitrary path',
            environment: 'development',
            apiBaseUrl: 'https://api.example.test/custom',
            expectedEnvironment: AppEnvironment.development,
            expectedUri: null,
            expectedIssue: AppConfigIssue.invalidApiUrl,
          ),
          (
            description: 'rejects repeated version paths',
            environment: 'development',
            apiBaseUrl: 'https://api.example.test/api/v1/api/v1',
            expectedEnvironment: AppEnvironment.development,
            expectedUri: null,
            expectedIssue: AppConfigIssue.invalidApiUrl,
          ),
          (
            description: 'rejects repeated interior slashes',
            environment: 'development',
            apiBaseUrl: 'https://api.example.test/api//v1',
            expectedEnvironment: AppEnvironment.development,
            expectedUri: null,
            expectedIssue: AppConfigIssue.invalidApiUrl,
          ),
          (
            description: 'rejects a malformed URL',
            environment: 'development',
            apiBaseUrl: 'https://[invalid',
            expectedEnvironment: AppEnvironment.development,
            expectedUri: null,
            expectedIssue: AppConfigIssue.invalidApiUrl,
          ),
          (
            description: 'rejects a malformed port without exposing its value',
            environment: 'development',
            apiBaseUrl: 'https://api.example.test:secret-port',
            expectedEnvironment: AppEnvironment.development,
            expectedUri: null,
            expectedIssue: AppConfigIssue.invalidApiUrl,
          ),
          (
            description: 'rejects a URL without a host',
            environment: 'development',
            apiBaseUrl: 'https:///api/v1',
            expectedEnvironment: AppEnvironment.development,
            expectedUri: null,
            expectedIssue: AppConfigIssue.invalidApiUrl,
          ),
          (
            description: 'rejects URL credentials',
            environment: 'development',
            apiBaseUrl: 'https://user:secret@api.example.test',
            expectedEnvironment: AppEnvironment.development,
            expectedUri: null,
            expectedIssue: AppConfigIssue.invalidApiUrl,
          ),
          (
            description: 'rejects even empty user information',
            environment: 'development',
            apiBaseUrl: 'https://@api.example.test',
            expectedEnvironment: AppEnvironment.development,
            expectedUri: null,
            expectedIssue: AppConfigIssue.invalidApiUrl,
          ),
          (
            description: 'rejects a query and secret query values',
            environment: 'development',
            apiBaseUrl: 'https://api.example.test?token=secret',
            expectedEnvironment: AppEnvironment.development,
            expectedUri: null,
            expectedIssue: AppConfigIssue.invalidApiUrl,
          ),
          (
            description: 'rejects an empty query delimiter',
            environment: 'development',
            apiBaseUrl: 'https://api.example.test?',
            expectedEnvironment: AppEnvironment.development,
            expectedUri: null,
            expectedIssue: AppConfigIssue.invalidApiUrl,
          ),
          (
            description: 'rejects a fragment',
            environment: 'development',
            apiBaseUrl: 'https://api.example.test#secret',
            expectedEnvironment: AppEnvironment.development,
            expectedUri: null,
            expectedIssue: AppConfigIssue.invalidApiUrl,
          ),
          (
            description: 'rejects an empty fragment delimiter',
            environment: 'development',
            apiBaseUrl: 'https://api.example.test#',
            expectedEnvironment: AppEnvironment.development,
            expectedUri: null,
            expectedIssue: AppConfigIssue.invalidApiUrl,
          ),
          (
            description: 'allows development HTTP on localhost',
            environment: 'development',
            apiBaseUrl: 'http://localhost:8080',
            expectedEnvironment: AppEnvironment.development,
            expectedUri: 'http://localhost:8080/api/v1',
            expectedIssue: null,
          ),
          (
            description: 'allows development HTTP on IPv4 loopback',
            environment: 'development',
            apiBaseUrl: 'http://127.0.0.1:8080',
            expectedEnvironment: AppEnvironment.development,
            expectedUri: 'http://127.0.0.1:8080/api/v1',
            expectedIssue: null,
          ),
          (
            description: 'allows development HTTP on IPv6 loopback',
            environment: 'development',
            apiBaseUrl: 'http://[::1]:8080',
            expectedEnvironment: AppEnvironment.development,
            expectedUri: 'http://[::1]:8080/api/v1',
            expectedIssue: null,
          ),
          (
            description: 'allows development HTTP on the Android emulator host',
            environment: 'development',
            apiBaseUrl: 'http://10.0.2.2:8080/api/v1',
            expectedEnvironment: AppEnvironment.development,
            expectedUri: 'http://10.0.2.2:8080/api/v1',
            expectedIssue: null,
          ),
          (
            description: 'rejects remote HTTP in development',
            environment: 'development',
            apiBaseUrl: 'http://api.example.test',
            expectedEnvironment: AppEnvironment.development,
            expectedUri: null,
            expectedIssue: AppConfigIssue.invalidApiUrl,
          ),
          (
            description: 'rejects loopback HTTP in staging',
            environment: 'staging',
            apiBaseUrl: 'http://localhost:8080',
            expectedEnvironment: AppEnvironment.staging,
            expectedUri: null,
            expectedIssue: AppConfigIssue.invalidApiUrl,
          ),
          (
            description: 'rejects loopback HTTP in production',
            environment: 'production',
            apiBaseUrl: 'http://127.0.0.1:8080',
            expectedEnvironment: AppEnvironment.production,
            expectedUri: null,
            expectedIssue: AppConfigIssue.invalidApiUrl,
          ),
        ];

    for (final testCase in cases) {
      test(testCase.description, () {
        final config = AppConfig.fromValues(
          environment: testCase.environment,
          apiBaseUrl: testCase.apiBaseUrl,
        );

        expect(config.environment, testCase.expectedEnvironment);
        expect(config.apiBaseUri?.toString(), testCase.expectedUri);
        expect(config.issue, testCase.expectedIssue);
        expect(config.isApiConfigured, testCase.expectedUri != null);
      });
    }
  });

  test('fromEnvironment forwards compile-time values and defaults', () {
    const expectedDefaultEnvironment = bool.fromEnvironment('dart.vm.product')
        ? 'production'
        : 'development';
    const environment = String.fromEnvironment(
      'APP_ENV',
      defaultValue: expectedDefaultEnvironment,
    );
    const apiBaseUrl = String.fromEnvironment(
      'ICHU_API_BASE_URL',
      defaultValue: '',
    );

    final config = AppConfig.fromEnvironment();
    final expected = AppConfig.fromValues(
      environment: environment,
      apiBaseUrl: apiBaseUrl,
    );

    expect(config.environment, expected.environment);
    expect(config.apiBaseUri?.toString(), expected.apiBaseUri?.toString());
    expect(config.issue, expected.issue);
  });
}
