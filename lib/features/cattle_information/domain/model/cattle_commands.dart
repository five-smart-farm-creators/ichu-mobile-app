import 'cattle.dart';
import 'cattle_date.dart';

enum CattleInputIssue {
  earTag,
  birthDate,
  birthDateAfterStage,
  stageAlreadyCurrent,
  stageDate,
  exitDate,
  inactive,
}

/// Date bounds shared by stage changes and exits, mirroring the server's aggregate rules.
abstract final class CattleDateRules {
  /// The open stage cannot start before the animal was born, so the later of the two bounds applies.
  static CattleDate earliestChangeDate(Cattle cattle) {
    for (final period in cattle.stagePeriods) {
      if (period.validTo == null &&
          period.validFrom.compareTo(cattle.birthDate) > 0) {
        return period.validFrom;
      }
    }
    return cattle.birthDate;
  }

  static bool isAllowed(CattleDate date, Cattle cattle, CattleDate today) =>
      date.isValid &&
      date.compareTo(earliestChangeDate(cattle)) >= 0 &&
      date.compareTo(today) <= 0;
}

Set<CattleInputIssue> _identityIssues(
  String normalizedEarTag,
  CattleDate birthDate,
  CattleDate today,
) => {
  if (normalizedEarTag.isEmpty || normalizedEarTag.length > 30)
    CattleInputIssue.earTag,
  if (!birthDate.isValid || birthDate.compareTo(today) > 0)
    CattleInputIssue.birthDate,
};

final class CattleRegistration {
  const CattleRegistration({
    required this.earTag,
    required this.breed,
    required this.sex,
    required this.birthDate,
    required this.lifeStage,
  });

  final String earTag;
  final CattleBreed breed;
  final CattleSex sex;
  final CattleDate birthDate;
  final CattleStage lifeStage;

  String get normalizedEarTag => earTag.trim();

  Set<CattleInputIssue> issuesOn(CattleDate today) =>
      _identityIssues(normalizedEarTag, birthDate, today);
}

final class CattleCorrection {
  const CattleCorrection({
    required this.earTag,
    required this.breed,
    required this.sex,
    required this.birthDate,
  });

  final String earTag;
  final CattleBreed breed;
  final CattleSex sex;
  final CattleDate birthDate;

  String get normalizedEarTag => earTag.trim();

  Set<CattleInputIssue> issuesFor(Cattle current, CattleDate today) => {
    ..._identityIssues(normalizedEarTag, birthDate, today),
    if (current.status != CattleStatus.active) CattleInputIssue.inactive,
    if (current.stagePeriods.any(
      (period) => period.validFrom.compareTo(birthDate) < 0,
    ))
      CattleInputIssue.birthDateAfterStage,
  };
}

final class CattleStageChange {
  const CattleStageChange({required this.stage, required this.validFrom});

  final CattleStage stage;
  final CattleDate validFrom;

  Set<CattleInputIssue> issuesFor(Cattle current, CattleDate today) => {
    if (current.status != CattleStatus.active) CattleInputIssue.inactive,
    if (current.currentStage == stage) CattleInputIssue.stageAlreadyCurrent,
    if (!CattleDateRules.isAllowed(validFrom, current, today))
      CattleInputIssue.stageDate,
  };
}

final class CattleExit {
  const CattleExit({required this.reason, required this.exitDate});

  final CattleExitReason reason;
  final CattleDate exitDate;

  Set<CattleInputIssue> issuesFor(Cattle current, CattleDate today) => {
    if (current.status != CattleStatus.active) CattleInputIssue.inactive,
    if (!CattleDateRules.isAllowed(exitDate, current, today))
      CattleInputIssue.exitDate,
  };
}
