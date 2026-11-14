import '../model/waterer.dart';
import '../model/water_history_query.dart';

abstract interface class WatererRepository {
  bool get isConfigured;
  Future<List<WatererStatus>> list(String ranchId);
  Future<WatererStatus> detail(String ranchId, String waterTroughId);
  Future<WaterHistoryPage> history(
    String ranchId,
    String controllerId,
    WaterHistoryQuery query,
  );
}
