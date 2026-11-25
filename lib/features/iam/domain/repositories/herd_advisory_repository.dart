import '../model/herd_advisory.dart';
import '../model/ranch_summary.dart';
import '../model/ranch_access.dart';

abstract interface class HerdAdvisoryRepository {
  bool get isConfigured;

  Future<RanchSummary> findRanchByAccessCode(String accessCode);

  Future<HerdAdvisory> requestAccess({
    required String ranchId,
    required String reason,
  });

  Future<List<HerdAdvisory>> advisoriesForRanch(String ranchId);

  Future<HerdAdvisory> decide({
    required String ranchId,
    required String advisoryId,
    required HerdAdvisoryDecision decision,
    AccessScope? scope,
    DateTime? expiresAt,
  });

  Future<HerdAdvisory> grantDirectly({
    required String ranchId,
    required String veterinarianId,
    required AccessScope scope,
    required DateTime expiresAt,
  });
}
