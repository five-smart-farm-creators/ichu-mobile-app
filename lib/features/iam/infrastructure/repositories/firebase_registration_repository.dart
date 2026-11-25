import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

import '../../domain/model/auth_failure.dart';
import '../../domain/model/auth_user.dart';
import '../../domain/repositories/identity_registration_repository.dart';
import '../configuration/firebase_client_config.dart';
import '../configuration/firebase_client_initializer.dart';
import 'firebase_auth_repository.dart';
import 'firebase_identity_mapping.dart';

final class FirebaseRegistrationRepository
    implements IdentityRegistrationRepository {
  FirebaseRegistrationRepository({required firebase_auth.FirebaseAuth? auth})
    : _auth = auth,
      _authentication = FirebaseAuthRepository(auth: auth);

  static const _appName = 'ichu-registration-mobile';

  final firebase_auth.FirebaseAuth? _auth;
  final FirebaseAuthRepository _authentication;

  /// Initializes the isolated registration app, never the default IAM app.
  static Future<FirebaseRegistrationRepository> initialize(
    FirebaseClientConfig config,
  ) async {
    final auth = await FirebaseClientInitializer.initialize(
      config,
      name: _appName,
    );
    return FirebaseRegistrationRepository(auth: auth);
  }

  @override
  bool get isConfigured => _authentication.isConfigured;

  @override
  AuthUser? get currentUser => _authentication.currentUser;

  @override
  Stream<AuthUser?> observeAuthState() => _authentication.observeAuthState();

  @override
  Future<AuthUser> signIn(String email, String password) =>
      _authentication.signIn(email, password);

  @override
  Future<AuthUser?> reloadUser() => _authentication.reloadUser();

  @override
  Future<String> idToken({bool forceRefresh = false}) =>
      _authentication.idToken(forceRefresh: forceRefresh);

  @override
  Future<void> sendPasswordReset(String email) =>
      _authentication.sendPasswordReset(email);

  @override
  Future<void> signOut() => _authentication.signOut();

  @override
  Future<AuthUser> createUser(String email, String password) async {
    final auth = _auth;
    if (auth == null) {
      throw const AuthFailure(AuthFailureCode.configuration);
    }

    try {
      final credential = await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const AuthFailure(AuthFailureCode.invalidResponse);
      }
      return FirebaseIdentityMapping.mapUser(user);
    } on AuthFailure {
      rethrow;
    } on Object catch (error) {
      throw FirebaseIdentityMapping.mapFailure(error);
    }
  }

  @override
  Future<void> sendEmailVerification() async {
    final auth = _auth;
    if (auth == null) {
      throw const AuthFailure(AuthFailureCode.configuration);
    }

    try {
      final user = auth.currentUser;
      if (user == null) {
        throw const AuthFailure(AuthFailureCode.accountUnavailable);
      }
      await user.sendEmailVerification();
    } on AuthFailure {
      rethrow;
    } on Object catch (error) {
      throw FirebaseIdentityMapping.mapFailure(error);
    }
  }
}
