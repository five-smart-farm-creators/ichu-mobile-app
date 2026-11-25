import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle_commands.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle_date.dart';

import '../../../support/fake_cattle_repository.dart';

const _today = CattleDate(2026, 11, 13);
const _ranchId = '11111111-1111-4111-8111-111111111111';

void main() {
  test('CattleDate.utcDateOf uses the UTC calendar day', () {
    final local = DateTime.parse('2026-11-13T23:30:00-05:00');
    expect(CattleDate.utcDateOf(local), const CattleDate(2026, 11, 14));
  });

  group('CattleRegistration', () {
    CattleRegistration registration({
      String earTag = 'PE-0001',
      CattleDate birthDate = const CattleDate(2024, 3, 1),
    }) => CattleRegistration(
      earTag: earTag,
      breed: CattleBreed.brownSwiss,
      sex: CattleSex.female,
      birthDate: birthDate,
      lifeStage: CattleStage.calf,
    );

    test('trims the ear tag and accepts exactly thirty characters', () {
      final padded = '  ${'A' * 30}  ';
      expect(registration(earTag: padded).normalizedEarTag, 'A' * 30);
      expect(registration(earTag: padded).issuesOn(_today), isEmpty);
    });

    test('rejects blank and over-length ear tags after trimming', () {
      expect(registration(earTag: '   ').issuesOn(_today), {
        CattleInputIssue.earTag,
      });
      expect(registration(earTag: 'A' * 31).issuesOn(_today), {
        CattleInputIssue.earTag,
      });
    });

    test('allows the UTC day and rejects future or impossible birth dates', () {
      expect(registration(birthDate: _today).issuesOn(_today), isEmpty);
      expect(
        registration(
          birthDate: const CattleDate(2026, 11, 14),
        ).issuesOn(_today),
        {CattleInputIssue.birthDate},
      );
      expect(
        registration(birthDate: const CattleDate(2026, 2, 30)).issuesOn(_today),
        {CattleInputIssue.birthDate},
      );
    });
  });

  group('CattleCorrection', () {
    test('blocks birth dates after an existing stage and inactive animals', () {
      final active = syntheticCattle(ranchId: _ranchId, id: 'active');
      final inactive = syntheticCattle(
        ranchId: _ranchId,
        id: 'inactive',
        status: CattleStatus.inactive,
      );
      CattleCorrection correction(CattleDate birthDate) => CattleCorrection(
        earTag: 'TAG-1',
        breed: CattleBreed.crossbred,
        sex: CattleSex.female,
        birthDate: birthDate,
      );

      expect(
        correction(const CattleDate(2021, 1, 2)).issuesFor(active, _today),
        {CattleInputIssue.birthDateAfterStage},
      );
      expect(
        correction(const CattleDate(2021, 1, 1)).issuesFor(active, _today),
        isEmpty,
      );
      expect(
        correction(const CattleDate(2021, 1, 1)).issuesFor(inactive, _today),
        {CattleInputIssue.inactive},
      );
      expect(
        CattleCorrection(
          earTag: '  ',
          breed: CattleBreed.crossbred,
          sex: CattleSex.female,
          birthDate: const CattleDate(2021, 1, 1),
        ).issuesFor(active, _today),
        {CattleInputIssue.earTag},
      );
    });
  });

  group('stage changes and exits', () {
    final active = syntheticCattle(ranchId: _ranchId, id: 'active');
    final inactive = syntheticCattle(
      ranchId: _ranchId,
      id: 'inactive',
      status: CattleStatus.inactive,
    );

    test('earliest change date is the later of birth and the open stage', () {
      expect(
        CattleDateRules.earliestChangeDate(active),
        const CattleDate(2021, 1, 1),
      );
      expect(
        CattleDateRules.earliestChangeDate(inactive),
        const CattleDate(2020, 1, 2),
      );
    });

    test('stage changes reject the current stage and dates outside bounds', () {
      CattleStageChange change(CattleDate validFrom) => CattleStageChange(
        stage: CattleStage.milkingCow,
        validFrom: validFrom,
      );

      expect(
        CattleStageChange(
          stage: CattleStage.heifer,
          validFrom: _today,
        ).issuesFor(active, _today),
        {CattleInputIssue.stageAlreadyCurrent},
      );
      expect(change(const CattleDate(2020, 12, 31)).issuesFor(active, _today), {
        CattleInputIssue.stageDate,
      });
      expect(
        change(const CattleDate(2021, 1, 1)).issuesFor(active, _today),
        isEmpty,
      );
      expect(change(_today).issuesFor(active, _today), isEmpty);
      expect(change(const CattleDate(2026, 11, 14)).issuesFor(active, _today), {
        CattleInputIssue.stageDate,
      });
      expect(change(_today).issuesFor(inactive, _today), {
        CattleInputIssue.inactive,
      });
    });

    test('exits bound the exit date by the open stage and today', () {
      CattleExit exit(CattleDate exitDate) =>
          CattleExit(reason: CattleExitReason.sale, exitDate: exitDate);

      expect(
        exit(const CattleDate(2021, 1, 1)).issuesFor(active, _today),
        isEmpty,
      );
      expect(exit(const CattleDate(2020, 12, 31)).issuesFor(active, _today), {
        CattleInputIssue.exitDate,
      });
      expect(exit(const CattleDate(2026, 11, 14)).issuesFor(active, _today), {
        CattleInputIssue.exitDate,
      });
      expect(exit(const CattleDate(2021, 1, 1)).issuesFor(inactive, _today), {
        CattleInputIssue.inactive,
      });
    });
  });
}
