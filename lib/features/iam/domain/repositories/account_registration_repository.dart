import '../model/iam_account.dart';
import '../model/registration_details.dart';
import '../model/account_registration_result.dart';

/// Creates an ICHU account from the current verified external identity.
abstract interface class AccountRegistrationRepository {
  bool get isConfigured;
  Future<AccountRegistrationResult> registerAccount({
    required String email,
    required RegistrationDetails details,
  });
  Future<IamAccount> currentAccount();
}
