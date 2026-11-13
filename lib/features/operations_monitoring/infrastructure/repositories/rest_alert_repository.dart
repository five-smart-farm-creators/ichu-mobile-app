import '../../domain/model/alert_search.dart';
import '../../domain/model/monitoring_failure.dart';
import '../../domain/model/ranch_alert.dart';
import '../../domain/repositories/alert_repository.dart';
import '../http/monitoring_api_client.dart';
import 'alert_mapping.dart';

/// REST adapter for the implemented read-only ranch alert list.
final class RestAlertRepository implements AlertRepository {
  const RestAlertRepository({required this._api});

  final MonitoringApiClient? _api;

  @override
  bool get isConfigured => _api?.isConfigured ?? false;

  @override
  Future<AlertPage> search(String ranchId, AlertSearch query) async {
    if (!query.isValid) {
      throw const MonitoringFailure(MonitoringFailureCode.invalidSearch);
    }
    final api = _api;
    if (api == null) {
      throw const MonitoringFailure(MonitoringFailureCode.configuration);
    }
    final payload = await api.alerts(ranchId, query);
    return AlertMapping.pageFromPayload(
      payload,
      ranchId: ranchId,
      query: query,
    );
  }
}
