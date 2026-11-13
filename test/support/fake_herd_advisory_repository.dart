import 'package:ichu_mobile_app/features/iam/domain/model/herd_advisory.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_access.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_summary.dart';
import 'package:ichu_mobile_app/features/iam/domain/repositories/herd_advisory_repository.dart';

/// In-memory test fixture; it does not represent a live ICHU service.
final class FakeHerdAdvisoryRepository implements HerdAdvisoryRepository {
  FakeHerdAdvisoryRepository({
    this.isConfigured = true,
    this.ranchResult,
    this.requestResult,
    List<HerdAdvisory> advisories = const <HerdAdvisory>[],
  }) : advisories = List<HerdAdvisory>.of(advisories);

  @override
  bool isConfigured;

  RanchSummary? ranchResult;
  HerdAdvisory? requestResult;
  List<HerdAdvisory> advisories;
  Object? failure;
  String? lastAccessCode;
  String? lastRanchId;
  String? lastReason;
  String? lastAdvisoryId;
  String? lastVeterinarianId;
  HerdAdvisoryDecision? lastDecision;
  AccessScope? lastScope;
  DateTime? lastExpiresAt;
  int lookupCalls = 0;
  int requestCalls = 0;
  int listCalls = 0;
  int decisionCalls = 0;
  int directGrantCalls = 0;

  @override
  Future<RanchSummary> findRanchByAccessCode(String accessCode) async {
    lookupCalls++;
    lastAccessCode = accessCode;
    _throwFailure();
    final result = ranchResult;
    if (result == null) throw StateError('No ranch fixture was configured.');
    return result;
  }

  @override
  Future<HerdAdvisory> requestAccess({
    required String ranchId,
    required String reason,
  }) async {
    requestCalls++;
    lastRanchId = ranchId;
    lastReason = reason;
    _throwFailure();
    final result = requestResult;
    if (result == null) {
      throw StateError('No advisory fixture was configured.');
    }
    return result;
  }

  @override
  Future<List<HerdAdvisory>> advisoriesForRanch(String ranchId) async {
    listCalls++;
    lastRanchId = ranchId;
    _throwFailure();
    return List<HerdAdvisory>.unmodifiable(advisories);
  }

  @override
  Future<HerdAdvisory> decide({
    required String ranchId,
    required String advisoryId,
    required HerdAdvisoryDecision decision,
    AccessScope? scope,
    DateTime? expiresAt,
  }) async {
    decisionCalls++;
    lastRanchId = ranchId;
    lastAdvisoryId = advisoryId;
    lastDecision = decision;
    lastScope = scope;
    lastExpiresAt = expiresAt;
    _throwFailure();
    final result = requestResult;
    if (result == null) {
      throw StateError('No advisory fixture was configured.');
    }
    return result;
  }

  @override
  Future<HerdAdvisory> grantDirectly({
    required String ranchId,
    required String veterinarianId,
    required AccessScope scope,
    required DateTime expiresAt,
  }) async {
    directGrantCalls++;
    lastRanchId = ranchId;
    lastVeterinarianId = veterinarianId;
    lastScope = scope;
    lastExpiresAt = expiresAt;
    _throwFailure();
    final result = requestResult;
    if (result == null) {
      throw StateError('No advisory fixture was configured.');
    }
    return result;
  }

  void _throwFailure() {
    final error = failure;
    if (error != null) throw error;
  }
}
