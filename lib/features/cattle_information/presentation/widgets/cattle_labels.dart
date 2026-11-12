import 'package:intl/intl.dart';

import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';
import '../../domain/model/cattle.dart';
import '../../domain/model/cattle_date.dart';

abstract final class CattleLabels {
  static String breed(AppLocalizations strings, CattleBreed value) =>
      switch (value) {
        CattleBreed.brownSwiss => strings.cattleBreedBrownSwiss,
        CattleBreed.fleckvieh => strings.cattleBreedFleckvieh,
        CattleBreed.criollo => strings.cattleBreedCriollo,
        CattleBreed.crossbred => strings.cattleBreedCrossbred,
      };

  static String sex(AppLocalizations strings, CattleSex value) =>
      switch (value) {
        CattleSex.female => strings.cattleSexFemale,
        CattleSex.male => strings.cattleSexMale,
      };

  static String stage(AppLocalizations strings, CattleStage value) =>
      switch (value) {
        CattleStage.calf => strings.cattleStageCalf,
        CattleStage.heifer => strings.cattleStageHeifer,
        CattleStage.milkingCow => strings.cattleStageMilkingCow,
        CattleStage.fatteningBull => strings.cattleStageFatteningBull,
      };

  static String status(AppLocalizations strings, CattleStatus value) =>
      switch (value) {
        CattleStatus.active => strings.cattleStatusActive,
        CattleStatus.inactive => strings.cattleStatusInactive,
      };

  static String exitReason(AppLocalizations strings, CattleExitReason value) =>
      switch (value) {
        CattleExitReason.death => strings.cattleExitDeath,
        CattleExitReason.sale => strings.cattleExitSale,
        CattleExitReason.theft => strings.cattleExitTheft,
        CattleExitReason.culling => strings.cattleExitCulling,
      };

  static String date(AppLocalizations strings, CattleDate value) =>
      DateFormat.yMMMd(strings.localeName).format(value.asUtcDate);
}
