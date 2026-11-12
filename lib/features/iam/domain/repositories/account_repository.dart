import '../model/iam_account.dart';
import '../model/ranch_access.dart';

/// Account operations use the authenticated identity, never a client account ID.
abstract interface class AccountRepository {
  bool get isConfigured;
  Future<IamAccount> currentAccount();
  Future<List<RanchAccess>> ranchAccess();
}
