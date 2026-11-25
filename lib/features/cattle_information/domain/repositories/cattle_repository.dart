import '../model/cattle.dart';
import '../model/cattle_search.dart';

abstract interface class CattleRepository {
  bool get isConfigured;
  Future<List<Cattle>> search(String ranchId, CattleSearch query);
  Future<CattleProfile> profile(String ranchId, String cattleId);
}
