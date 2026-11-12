import '../model/iam_account.dart';

/// Reads the authenticated caller's profile without selecting an account ID.
abstract interface class ProfessionalProfileRepository {
  bool get isConfigured;
  Future<IamAccount> currentAccount();
}
