import '../../domain/model/herd_advisory.dart';
import '../../domain/model/herd_advisory_failure.dart';
import '../../domain/model/ranch_access.dart';
import '../../domain/model/ranch_summary.dart';
import '../../domain/repositories/herd_advisory_repository.dart';
import 'ranch_selection_service.dart';

/// Coordinates veterinarian requests and ranch-scoped advisory management.
final class HerdAdvisoryService {
  HerdAdvisoryService({
    required HerdAdvisoryRepository advisories,
    required RanchSelectionService selection,
    DateTime Function()? now,
  }) : _advisories = advisories,
       _selection = selection,
       _now = now ?? DateTime.now;

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  final HerdAdvisoryRepository _advisories;
  final RanchSelectionService _selection;
  final DateTime Function() _now;

  bool get isConfigured => _advisories.isConfigured;

  Future<RanchSummary> findRanchByAccessCode(String accessCode) async {
    final suppliedCode = accessCode.trim();
    if (suppliedCode.isEmpty) {
      throw const HerdAdvisoryFailure(HerdAdvisoryFailureCode.invalidRequest);
    }
    return _advisories.findRanchByAccessCode(suppliedCode);
  }

  Future<HerdAdvisory> requestAccess({
    required String ranchId,
    required String reason,
  }) async {
    final normalizedReason = reason.trim();
    if (!_isNonzeroUuid(ranchId) ||
        normalizedReason.isEmpty ||
        normalizedReason.length > 1000) {
      throw const HerdAdvisoryFailure(HerdAdvisoryFailureCode.invalidRequest);
    }
    return _advisories.requestAccess(
      ranchId: ranchId,
      reason: normalizedReason,
    );
  }

  Future<List<HerdAdvisory>> advisoriesForSelectedRanch() {
    final ranchId = _selectedRanchId();
    return _advisories.advisoriesForRanch(ranchId);
  }

  Future<HerdAdvisory> decideForSelectedRanch({
    required String advisoryId,
    required HerdAdvisoryDecision decision,
    AccessScope? scope,
    DateTime? expiresAt,
  }) {
    final ranchId = _selectedRanchId();
    if (!_isNonzeroUuid(advisoryId)) {
      throw const HerdAdvisoryFailure(HerdAdvisoryFailureCode.invalidRequest);
    }
    if (decision == HerdAdvisoryDecision.grant) {
      if (!_isAdvisoryScope(scope) ||
          expiresAt == null ||
          expiresAt <= _now()) {
        throw const HerdAdvisoryFailure(HerdAdvisoryFailureCode.invalidRequest);
      }
    } else if (scope != null || expiresAt != null) {
      throw const HerdAdvisoryFailure(HerdAdvisoryFailureCode.invalidRequest);
    }
    return _advisories.decide(
      ranchId: ranchId,
      advisoryId: advisoryId,
      decision: decision,
      scope: scope,
      expiresAt: expiresAt,
    );
  }

  Future<HerdAdvisory> grantDirectly({
    required String veterinarianId,
    required AccessScope scope,
    required DateTime expiresAt,
  }) {
    final ranchId = _selectedRanchId();
    if (!_isNonzeroUuid(veterinarianId) ||
        !_isAdvisoryScope(scope) ||
        expiresAt <= _now()) {
      throw const HerdAdvisoryFailure(HerdAdvisoryFailureCode.invalidRequest);
    }
    return _advisories.grantDirectly(
      ranchId: ranchId,
      veterinarianId: veterinarianId,
      scope: scope,
      expiresAt: expiresAt,
    );
  }

  String _selectedRanchId() {
    final ranch = _selection.selectedRanch;
    if (ranch == null || !_isNonzeroUuid(ranch.ranchId)) {
      throw const HerdAdvisoryFailure(
        HerdAdvisoryFailureCode.contextUnavailable,
      );
    }
    return ranch.ranchId;
  }

  bool _isAdvisoryScope(AccessScope? scope) =>
      scope == AccessScope.read || scope == AccessScope.clinicalWrite;

  bool _isNonzeroUuid(String value) =>
      _uuidPattern.hasMatch(value) &&
      value.replaceAll('-', '').replaceAll('0', '').isNotEmpty;
}
