import '../model/iam_account.dart';
import '../model/professional_profile.dart';

/// Identity-bound profile operations never accept a client-selected account ID.
abstract interface class ProfessionalProfileRepository {
  bool get isConfigured;
  Future<IamAccount> currentAccount();
  Future<IamAccount> save(ProfessionalProfile profile);
}
