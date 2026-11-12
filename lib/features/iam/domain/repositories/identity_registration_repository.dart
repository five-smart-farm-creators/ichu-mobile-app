import '../model/auth_user.dart';
import 'authentication_repository.dart';

/// Uses an isolated identity session so onboarding cannot replace a workspace.
abstract interface class IdentityRegistrationRepository
    implements AuthenticationRepository {
  Future<AuthUser> createUser(String email, String password);
  Future<void> sendEmailVerification();
}
