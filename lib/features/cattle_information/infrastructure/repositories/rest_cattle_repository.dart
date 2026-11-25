import '../../domain/model/cattle.dart';
import '../../domain/model/cattle_failure.dart';
import '../../domain/model/cattle_search.dart';
import '../../domain/repositories/cattle_repository.dart';
import '../http/cattle_api_client.dart';
import 'cattle_mapping.dart';

/// REST adapter for ranch-scoped Cattle Information reads.
final class RestCattleRepository implements CattleRepository {
  const RestCattleRepository({required this._api});

  final CattleApiClient? _api;

  @override
  bool get isConfigured => _api?.isConfigured ?? false;

  @override
  Future<List<Cattle>> search(String ranchId, CattleSearch query) async {
    if (!query.isValid) {
      throw const CattleFailure(CattleFailureCode.invalidSearch);
    }
    final api = _requireApi();
    final payload = await api.search(ranchId, query);
    return CattleMapping.cattleListFromPayload(
      payload,
      ranchId: ranchId,
      maximumCount: query.pageSize,
    );
  }

  @override
  Future<CattleProfile> profile(String ranchId, String cattleId) async {
    final api = _requireApi();
    final payload = await api.profile(ranchId, cattleId);
    return CattleMapping.profileFromPayload(
      payload,
      ranchId: ranchId,
      cattleId: cattleId,
    );
  }

  CattleApiClient _requireApi() {
    final api = _api;
    if (api == null) {
      throw const CattleFailure(CattleFailureCode.configuration);
    }
    return api;
  }
}
