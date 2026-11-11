import '../model/auth_user.dart';

/// External identity operations. Credentials and tokens must never be persisted
/// by application services or forwarded to arbitrary HTTP destinations.
abstract interface class AuthenticationRepository {
  bool get isConfigured;
  AuthUser? get currentUser;
  Stream<AuthUser?> observeAuthState();
  Future<AuthUser> signIn(String email, String password);
  Future<AuthUser?> reloadUser();
  Future<String> idToken({bool forceRefresh = false});
  Future<void> sendPasswordReset(String email);
  Future<void> signOut();
}
