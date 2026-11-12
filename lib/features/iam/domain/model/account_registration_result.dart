import 'iam_account.dart';

/// Creation acknowledgement, never a validated workspace session.
final class AccountRegistrationResult {
  const AccountRegistrationResult({required this.account, this.ranchId});

  final IamAccount account;
  final String? ranchId;
}
