import 'dart:async';

import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/professional_profile.dart';
import 'package:ichu_mobile_app/features/iam/domain/repositories/professional_profile_repository.dart';

const ProfessionalProfile syntheticProfessionalProfile = ProfessionalProfile(
  specialty: 'Bovine health',
  licenseNumber: 'CMVP-123',
  yearsOfExperience: 5,
);

const IamAccount syntheticVeterinarianAccount = IamAccount(
  id: '8b3e7f19-42d6-4f31-9a50-6c0d82a314e7',
  email: 'user@example.test',
  role: AccountRole.veterinarian,
  status: 'TemporarilyBlocked',
  profile: syntheticProfessionalProfile,
);

/// Mutable fake used by profile-service tests; fixtures are synthetic only.
final class FakeProfessionalProfileRepository
    implements ProfessionalProfileRepository {
  FakeProfessionalProfileRepository({
    this.isConfigured = true,
    this.account = syntheticVeterinarianAccount,
  });

  @override
  bool isConfigured;

  IamAccount account;
  Object? loadFailure;
  Completer<IamAccount>? loadCompleter;

  int loadCalls = 0;
  final Completer<void> firstLoad = Completer<void>();

  @override
  Future<IamAccount> currentAccount() async {
    loadCalls++;
    if (loadCalls == 1) firstLoad.complete();
    final completer = loadCompleter;
    if (completer != null) return completer.future;
    final failure = loadFailure;
    if (failure != null) throw failure;
    return account;
  }
}
