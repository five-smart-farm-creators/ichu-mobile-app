import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_failure.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_user.dart';
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

  group('FirebaseAuthRepository with a fake Firebase SDK client', () {
    test('forwards exact credentials and returns a domain user', () async {
      final sdkUser = _FakeFirebaseUser(
        uid: 'synthetic-uid',
        email: 'user@example.test',
        emailVerified: true,
        displayName: 'Synthetic User',
      );
      final auth = _FakeFirebaseAuth(credential: _FakeUserCredential(sdkUser));
      final repository = FirebaseAuthRepository(auth: auth);

      final user = await repository.signIn(
        '  user@example.test  ',
        '  synthetic-only-password  ',
      );

      expect(auth.lastSignInEmail, '  user@example.test  ');
      expect(auth.lastSignInPassword, '  synthetic-only-password  ');
      expect(user, isA<AuthUser>());
      expect(user.uid, 'synthetic-uid');
      expect(user.email, 'user@example.test');
      expect(user.emailVerified, isTrue);
      expect(user.displayName, 'Synthetic User');
      expect(user, isNot(same(sdkUser)));
    });

    test('maps current SDK user to a domain user', () {
      final sdkUser = _FakeFirebaseUser(
        uid: 'synthetic-uid',
        email: 'user@example.test',
        emailVerified: false,
        displayName: 'Synthetic User',
      );
      final repository = FirebaseAuthRepository(
        auth: _FakeFirebaseAuth(currentUserValue: sdkUser),
      );

      final user = repository.currentUser;

      expect(user, isA<AuthUser>());
      expect(user?.uid, 'synthetic-uid');
      expect(user?.email, 'user@example.test');
      expect(user?.emailVerified, isFalse);
      expect(user?.displayName, 'Synthetic User');
      expect(user, isNot(same(sdkUser)));
    });

    test(
      'reloads the user before refreshing the token on the fresh user',
      () async {
        final events = <String>[];
        final auth = _FakeFirebaseAuth();
        late final _FakeFirebaseUser refreshedUser;
        final originalUser =
            _FakeFirebaseUser(
                uid: 'synthetic-uid',
                email: 'user@example.test',
                emailVerified: false,
              )
              ..onReload = () async {
                events.add('reload-original');
                auth.currentUserValue = refreshedUser;
              };
        refreshedUser = _FakeFirebaseUser(
          uid: 'synthetic-uid',
          email: 'user@example.test',
          emailVerified: true,
          onGetIdToken: (forceRefresh) async {
            events.add('token-fresh:$forceRefresh');
            return 'synthetic-refreshed-token';
          },
        );
        auth.currentUserValue = originalUser;
        final repository = FirebaseAuthRepository(auth: auth);

        final user = await repository.reloadUser();

        expect(events, <String>['reload-original', 'token-fresh:true']);
        expect(refreshedUser.idTokenForceRefreshArguments, <bool>[true]);
        expect(user?.emailVerified, isTrue);
        expect(user?.uid, 'synthetic-uid');
      },
    );

    test(
      'fetches a token on every call and forwards the force-refresh flag',
      () async {
        var tokenNumber = 0;
        final sdkUser = _FakeFirebaseUser(
          uid: 'synthetic-uid',
          onGetIdToken: (_) async => 'synthetic-token-${++tokenNumber}',
        );
        final repository = FirebaseAuthRepository(
          auth: _FakeFirebaseAuth(currentUserValue: sdkUser),
        );

        expect(await repository.idToken(), 'synthetic-token-1');
        expect(
          await repository.idToken(forceRefresh: true),
          'synthetic-token-2',
        );

        expect(sdkUser.idTokenForceRefreshArguments, <bool>[false, true]);
        expect(tokenNumber, 2);
      },
    );

    test(
      'missing current user and empty token fail as account unavailable',
      () async {
        final noUserRepository = FirebaseAuthRepository(
          auth: _FakeFirebaseAuth(),
        );
        await _expectFailure(
          noUserRepository.idToken(),
          AuthFailureCode.accountUnavailable,
        );

        final emptyTokenRepository = FirebaseAuthRepository(
          auth: _FakeFirebaseAuth(
            currentUserValue: _FakeFirebaseUser(
              uid: 'synthetic-uid',
              idToken: '',
            ),
          ),
        );
        await _expectFailure(
          emptyTokenRepository.idToken(),
          AuthFailureCode.accountUnavailable,
        );
      },
    );

    test('password reset treats user-not-found as a normal response', () async {
      final auth = _FakeFirebaseAuth(
        passwordResetFailure: _FakeFirebaseAuthException(
          code: 'auth/user-not-found',
          message: 'synthetic private SDK detail',
        ),
      );
      final repository = FirebaseAuthRepository(auth: auth);

      await repository.sendPasswordReset('user@example.test');

      expect(auth.lastPasswordResetEmail, 'user@example.test');
    });

    test(
      'maps SDK failures to stable categories without leaking messages',
      () async {
        final cases = <(String, AuthFailureCode)>[
          ('wrong-password', AuthFailureCode.invalidCredentials),
          ('network-request-failed', AuthFailureCode.network),
          ('too-many-requests', AuthFailureCode.serviceUnavailable),
          ('invalid-api-key', AuthFailureCode.configuration),
        ];

        for (final (sdkCode, expectedCode) in cases) {
          final repository = FirebaseAuthRepository(
            auth: _FakeFirebaseAuth(
              signInFailure: _FakeFirebaseAuthException(
                code: 'auth/$sdkCode',
                message: 'synthetic private SDK detail',
              ),
            ),
          );

          await _expectFailure(
            repository.signIn('user@example.test', 'synthetic-password'),
            expectedCode,
          );
        }
      },
    );

    test('sign-out calls the SDK and clears its current user', () async {
      final auth = _FakeFirebaseAuth(
        currentUserValue: _FakeFirebaseUser(uid: 'synthetic-uid'),
      );
      final repository = FirebaseAuthRepository(auth: auth);
      expect(repository.currentUser, isNotNull);

      await repository.signOut();

      expect(auth.signOutCalls, 1);
      expect(auth.currentUserValue, isNull);
      expect(repository.currentUser, isNull);
    });

    test('converts observed SDK stream errors to safe failures', () async {
      final repository = FirebaseAuthRepository(
        auth: _FakeFirebaseAuth(
          authEvents: Stream<firebase_auth.User?>.error(
            _FakeFirebaseAuthException(
              code: 'network-request-failed',
              message: 'synthetic private SDK detail',
            ),
          ),
        ),
      );

      await expectLater(
        repository.observeAuthState(),
        emitsError(_failure(AuthFailureCode.network)),
      );
    });
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

Matcher _configurationFailure() => _failure(AuthFailureCode.configuration);

Matcher _failure(AuthFailureCode code) => isA<AuthFailure>()
    .having((failure) => failure.code, 'code', code)
    .having(
      (failure) => failure.toString(),
      'safe error without raw details',
      'AuthFailure(${code.name})',
    );

Future<void> _expectFailure<T>(
  Future<T> operation,
  AuthFailureCode code,
) async {
  await expectLater(operation, throwsA(_failure(code)));
}

final class _FakeFirebaseAuth extends Fake
    implements firebase_auth.FirebaseAuth {
  _FakeFirebaseAuth({
    this.currentUserValue,
    this.credential,
    this.authEvents = const Stream<firebase_auth.User?>.empty(),
    this.signInFailure,
    this.passwordResetFailure,
  });

  firebase_auth.User? currentUserValue;
  final firebase_auth.UserCredential? credential;
  final Stream<firebase_auth.User?> authEvents;
  final Object? signInFailure;
  final Object? passwordResetFailure;
  String? lastSignInEmail;
  String? lastSignInPassword;
  String? lastPasswordResetEmail;
  int signOutCalls = 0;

  @override
  firebase_auth.User? get currentUser => currentUserValue;

  @override
  Stream<firebase_auth.User?> authStateChanges() => authEvents;

  @override
  Future<firebase_auth.UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    lastSignInEmail = email;
    lastSignInPassword = password;
    if (signInFailure != null) throw signInFailure!;
    return credential!;
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    firebase_auth.ActionCodeSettings? actionCodeSettings,
  }) async {
    lastPasswordResetEmail = email;
    if (passwordResetFailure != null) throw passwordResetFailure!;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    currentUserValue = null;
  }
}

final class _FakeFirebaseUser extends Fake implements firebase_auth.User {
  _FakeFirebaseUser({
    required this.uid,
    this.email,
    this.emailVerified = false,
    this.displayName,
    this.idToken = 'synthetic-id-token',
    this.onGetIdToken,
  });

  @override
  final String uid;

  @override
  final String? email;

  @override
  bool emailVerified;

  @override
  final String? displayName;

  final String? idToken;
  Future<void> Function()? onReload;
  final Future<String?> Function(bool forceRefresh)? onGetIdToken;
  final List<bool> idTokenForceRefreshArguments = <bool>[];

  @override
  Future<void> reload() async {
    await onReload?.call();
  }

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    idTokenForceRefreshArguments.add(forceRefresh);
    final handler = onGetIdToken;
    if (handler != null) return handler(forceRefresh);
    return idToken;
  }
}

final class _FakeUserCredential extends Fake
    implements firebase_auth.UserCredential {
  _FakeUserCredential(this.user);

  @override
  final firebase_auth.User? user;
}

final class _FakeFirebaseAuthException
    extends firebase_auth.FirebaseAuthException {
  _FakeFirebaseAuthException({required super.code, required super.message});
}
