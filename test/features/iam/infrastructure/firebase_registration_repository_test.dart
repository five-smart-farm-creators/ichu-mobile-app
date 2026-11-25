import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_failure.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_user.dart';
import 'package:ichu_mobile_app/features/iam/infrastructure/configuration/firebase_client_config.dart';
import 'package:ichu_mobile_app/features/iam/infrastructure/repositories/firebase_auth_repository.dart';
import 'package:ichu_mobile_app/features/iam/infrastructure/repositories/firebase_registration_repository.dart';

void main() {
  group('FirebaseRegistrationRepository without Firebase configuration', () {
    test(
      'initialization skips Firebase SDK setup when options are absent',
      () async {
        final config = FirebaseClientConfig.fromValues(
          platform: FirebaseNativePlatform.android,
        );

        final repository = await FirebaseRegistrationRepository.initialize(
          config,
        );

        await _expectUnconfigured(repository);
      },
    );

    test('an explicit null auth client fails safely', () async {
      await _expectUnconfigured(FirebaseRegistrationRepository(auth: null));
    });
  });

  group('FirebaseRegistrationRepository with fake Firebase SDK clients', () {
    test(
      'forwards exact registration credentials and maps the identity',
      () async {
        final sdkUser = _FakeFirebaseUser(
          uid: 'synthetic-registration-uid',
          email: 'new-user@example.test',
          emailVerified: false,
          displayName: 'Synthetic Registrant',
        );
        final auth = _FakeFirebaseAuth(
          createCredential: _FakeUserCredential(sdkUser),
        );
        final repository = FirebaseRegistrationRepository(auth: auth);

        final user = await repository.createUser(
          '  new-user@example.test  ',
          '  synthetic-only-password  ',
        );

        expect(auth.lastCreateEmail, '  new-user@example.test  ');
        expect(auth.lastCreatePassword, '  synthetic-only-password  ');
        expect(auth.currentUserValue, same(sdkUser));
        expect(user, isA<AuthUser>());
        expect(user.uid, 'synthetic-registration-uid');
        expect(user.email, 'new-user@example.test');
        expect(user.emailVerified, isFalse);
        expect(user.displayName, 'Synthetic Registrant');
        expect(user, isNot(same(sdkUser)));
      },
    );

    test(
      'resumes an existing identity through the isolated SDK client',
      () async {
        final user = _FakeFirebaseUser(
          uid: 'synthetic-resumed-uid',
          email: 'new-user@example.test',
        );
        final auth = _FakeFirebaseAuth(
          signInCredential: _FakeUserCredential(user),
        );
        final repository = FirebaseRegistrationRepository(auth: auth);
        final resumed = await repository.signIn(
          'new-user@example.test',
          'synthetic-password',
        );
        expect(resumed.uid, 'synthetic-resumed-uid');
        expect(repository.currentUser?.uid, resumed.uid);
      },
    );

    test('a null registration user fails as an invalid response', () async {
      final repository = FirebaseRegistrationRepository(
        auth: _FakeFirebaseAuth(createCredential: _FakeUserCredential(null)),
      );

      await _expectFailure(
        repository.createUser('new-user@example.test', 'synthetic-password'),
        AuthFailureCode.invalidResponse,
      );
    });

    test('maps registration SDK codes without exposing SDK messages', () async {
      final cases = <(String, AuthFailureCode)>[
        ('email-already-in-use', AuthFailureCode.registrationRejected),
        ('weak-password', AuthFailureCode.registrationRejected),
        ('network-request-failed', AuthFailureCode.network),
        ('unrecognized-registration-error', AuthFailureCode.unknown),
      ];

      for (final (sdkCode, expectedCode) in cases) {
        final repository = FirebaseRegistrationRepository(
          auth: _FakeFirebaseAuth(
            createFailure: _FakeFirebaseAuthException(
              code: 'auth/$sdkCode',
              message: 'synthetic private SDK detail',
            ),
          ),
        );

        await _expectFailure(
          repository.createUser('new-user@example.test', 'synthetic-password'),
          expectedCode,
        );
      }
    });

    test('sends email verification to its own current SDK user', () async {
      final sdkUser = _FakeFirebaseUser(uid: 'synthetic-registration-uid');
      final repository = FirebaseRegistrationRepository(
        auth: _FakeFirebaseAuth(currentUserValue: sdkUser),
      );

      await repository.sendEmailVerification();

      expect(sdkUser.sendEmailVerificationCalls, 1);
    });

    test(
      'email verification without a current user is account unavailable',
      () async {
        final repository = FirebaseRegistrationRepository(
          auth: _FakeFirebaseAuth(),
        );

        await _expectFailure(
          repository.sendEmailVerification(),
          AuthFailureCode.accountUnavailable,
        );
      },
    );

    test('delegated reload returns refreshed verification claims', () async {
      final auth = _FakeFirebaseAuth();
      late final _FakeFirebaseUser refreshedUser;
      final initialUser =
          _FakeFirebaseUser(
              uid: 'synthetic-registration-uid',
              email: 'new-user@example.test',
              emailVerified: false,
            )
            ..onReload = () async {
              auth.currentUserValue = refreshedUser;
            };
      refreshedUser = _FakeFirebaseUser(
        uid: 'synthetic-registration-uid',
        email: 'new-user@example.test',
        emailVerified: true,
        onGetIdToken: (forceRefresh) async => 'synthetic-refreshed-token',
      );
      auth.currentUserValue = initialUser;
      final repository = FirebaseRegistrationRepository(auth: auth);

      final user = await repository.reloadUser();

      expect(user?.uid, 'synthetic-registration-uid');
      expect(user?.emailVerified, isTrue);
      expect(refreshedUser.idTokenForceRefreshArguments, <bool>[true]);
    });

    test(
      'registration identity changes do not affect the primary auth client',
      () async {
        final primaryUser = _FakeFirebaseUser(
          uid: 'synthetic-primary-uid',
          email: 'primary@example.test',
        );
        final primaryAuth = _FakeFirebaseAuth(currentUserValue: primaryUser);
        final primaryRepository = FirebaseAuthRepository(auth: primaryAuth);
        final registrationUser = _FakeFirebaseUser(
          uid: 'synthetic-registration-uid',
          email: 'new-user@example.test',
        );
        final registrationAuth = _FakeFirebaseAuth(
          currentUserValue: null,
          createCredential: _FakeUserCredential(registrationUser),
        );
        final registrationRepository = FirebaseRegistrationRepository(
          auth: registrationAuth,
        );

        await registrationRepository.createUser(
          'new-user@example.test',
          'synthetic-password',
        );

        expect(
          registrationRepository.currentUser?.uid,
          'synthetic-registration-uid',
        );
        expect(primaryRepository.currentUser?.uid, 'synthetic-primary-uid');
        expect(primaryAuth.currentUserValue, same(primaryUser));
        expect(registrationAuth.currentUserValue, same(registrationUser));
      },
    );
  });
}

Future<void> _expectUnconfigured(
  FirebaseRegistrationRepository repository,
) async {
  expect(repository.isConfigured, isFalse);
  expect(repository.currentUser, isNull);
  await expectLater(
    repository.observeAuthState(),
    emitsError(_failure(AuthFailureCode.configuration)),
  );
  await _expectFailure(
    repository.createUser('new-user@example.test', 'synthetic-password'),
    AuthFailureCode.configuration,
  );
  await _expectFailure(
    repository.sendEmailVerification(),
    AuthFailureCode.configuration,
  );
  await _expectFailure(
    repository.signIn('user@example.test', 'synthetic-password'),
    AuthFailureCode.configuration,
  );
  await _expectFailure(repository.reloadUser(), AuthFailureCode.configuration);
  await _expectFailure(repository.idToken(), AuthFailureCode.configuration);
  await _expectFailure(
    repository.sendPasswordReset('user@example.test'),
    AuthFailureCode.configuration,
  );
  await _expectFailure(repository.signOut(), AuthFailureCode.configuration);
}

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
    this.createCredential,
    this.createFailure,
    this.signInCredential,
  });

  firebase_auth.User? currentUserValue;
  final firebase_auth.UserCredential? createCredential;
  final Object? createFailure;
  final firebase_auth.UserCredential? signInCredential;
  String? lastCreateEmail;
  String? lastCreatePassword;

  @override
  firebase_auth.User? get currentUser => currentUserValue;

  @override
  Stream<firebase_auth.User?> authStateChanges() =>
      Stream<firebase_auth.User?>.value(currentUserValue);

  @override
  Future<firebase_auth.UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    lastCreateEmail = email;
    lastCreatePassword = password;
    if (createFailure != null) throw createFailure!;
    final credential = createCredential!;
    currentUserValue = credential.user;
    return credential;
  }

  @override
  Future<firebase_auth.UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    currentUserValue = signInCredential!.user;
    return signInCredential!;
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    firebase_auth.ActionCodeSettings? actionCodeSettings,
  }) async {}

  @override
  Future<void> signOut() async {
    currentUserValue = null;
  }
}

final class _FakeFirebaseUser extends Fake implements firebase_auth.User {
  _FakeFirebaseUser({
    required this.uid,
    this.email,
    this.emailVerified = false,
    this.displayName,
    this.onGetIdToken,
  });

  @override
  final String uid;

  @override
  final String? email;

  @override
  final bool emailVerified;

  @override
  final String? displayName;

  final Future<String?> Function(bool forceRefresh)? onGetIdToken;
  final List<bool> idTokenForceRefreshArguments = <bool>[];
  int sendEmailVerificationCalls = 0;
  Future<void> Function()? onReload;

  @override
  Future<void> reload() async {
    await onReload?.call();
  }

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    idTokenForceRefreshArguments.add(forceRefresh);
    final handler = onGetIdToken;
    if (handler != null) return handler(forceRefresh);
    return 'synthetic-id-token';
  }

  @override
  Future<void> sendEmailVerification([
    firebase_auth.ActionCodeSettings? actionCodeSettings,
  ]) async {
    sendEmailVerificationCalls++;
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
