import 'cattle_date.dart';

enum CattleBreed { brownSwiss, fleckvieh, criollo, crossbred }

enum CattleSex { female, male }

enum CattleStage { calf, heifer, milkingCow, fatteningBull }

enum CattleStatus { active, inactive }

enum CattleExitReason { death, sale, theft, culling }

final class CattleStagePeriod {
  const CattleStagePeriod({
    required this.id,
    required this.stage,
    required this.validFrom,
    this.validTo,
  });

  final String id;
  final CattleStage stage;
  final CattleDate validFrom;
  final CattleDate? validTo;
}

/// A server snapshot within one ranch; identifiers never select authorization.
final class Cattle {
  Cattle({
    required this.id,
    required this.ranchId,
    required this.earTag,
    required this.breed,
    required this.sex,
    required this.birthDate,
    required this.currentStage,
    required this.status,
    required this.version,
    required List<CattleStagePeriod> stagePeriods,
    this.exitReason,
    this.exitDate,
  }) : stagePeriods = List.unmodifiable(stagePeriods);

  final String id;
  final String ranchId;
  final String earTag;
  final CattleBreed breed;
  final CattleSex sex;
  final CattleDate birthDate;
  final CattleStage currentStage;
  final CattleStatus status;
  final String version;
  final List<CattleStagePeriod> stagePeriods;
  final CattleExitReason? exitReason;
  final CattleDate? exitDate;
}

/// Composed integration data, not captured telemetry or a live location.
final class CattleDevice {
  const CattleDevice({
    required this.isAvailable,
    this.collarId,
    this.lastReadingReceivedAt,
  });

  final bool isAvailable;
  final String? collarId;
  final DateTime? lastReadingReceivedAt;
}

final class CattleProfile {
  const CattleProfile({required this.cattle, required this.device});

  final Cattle cattle;
  final CattleDevice device;
}
