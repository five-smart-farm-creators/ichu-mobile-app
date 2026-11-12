import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_failure.dart';
import 'package:ichu_mobile_app/features/iam/infrastructure/configuration/firebase_client_config.dart';
import 'package:ichu_mobile_app/features/iam/infrastructure/repositories/firebase_auth_repository.dart';

void main() {
  group('FirebaseAuthRepository without Firebase configuration', () {
    test('an explicit null auth client fails safely', () async {
      final repository = FirebaseAuthRepository(auth: null);

      await _expectUnconfigured(repository);
    });

    final configurations = <(String, FirebaseClientConfig)>[
      (
        'missing native settings',
        FirebaseClientConfig.fromValues(
          platform: FirebaseNativePlatform.android,
        ),
      ),
      (
        'unsupported platform',
        FirebaseClientConfig.fromValues(
          platform: FirebaseNativePlatform.unsupported,
        ),
      ),
    ];

    for (final (description, config) in configurations) {
      test('initialize skips Firebase SDK setup for $description', () async {
        expect(config.isConfigured, isFalse);
        expect(config.options, isNull);

        final repository = await FirebaseAuthRepository.initialize(config);

        await _expectUnconfigured(repository);
      });
    }
  });
}

Future<void> _expectUnconfigured(FirebaseAuthRepository repository) async {
  expect(repository.isConfigured, isFalse);
  expect(repository.currentUser, isNull);

  await expectLater(
    repository.observeAuthState(),
    emitsError(_configurationFailure()),
  );
  await _expectConfigurationFailure(
    repository.signIn('user@example.test', 'synthetic-test-password'),
  );
  await _expectConfigurationFailure(repository.reloadUser());
  await _expectConfigurationFailure(repository.idToken());
  await _expectConfigurationFailure(
    repository.sendPasswordReset('user@example.test'),
  );
  await _expectConfigurationFailure(repository.signOut());
}

Future<void> _expectConfigurationFailure<T>(Future<T> operation) async {
  await expectLater(operation, throwsA(_configurationFailure()));
}

Matcher _configurationFailure() => isA<AuthFailure>()
    .having((failure) => failure.code, 'code', AuthFailureCode.configuration)
    .having(
      (failure) => failure.toString(),
      'safe error without raw details',
      'AuthFailure(configuration)',
    );
