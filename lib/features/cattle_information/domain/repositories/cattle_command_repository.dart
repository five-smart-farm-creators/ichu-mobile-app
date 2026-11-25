import '../model/cattle.dart';
import '../model/cattle_commands.dart';

abstract interface class CattleCommandRepository {
  bool get isConfigured;
  Future<Cattle> register(String ranchId, CattleRegistration registration);
  Future<Cattle> correct(
    String ranchId,
    String cattleId,
    String expectedVersion,
    CattleCorrection correction,
  );
  Future<Cattle> changeStage(
    String ranchId,
    String cattleId,
    String expectedVersion,
    CattleStageChange change,
  );
  Future<Cattle> deactivate(
    String ranchId,
    String cattleId,
    String expectedVersion,
    CattleExit exit,
  );
}
