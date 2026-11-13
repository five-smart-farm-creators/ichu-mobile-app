import '../../domain/model/alert_search.dart';
import '../../domain/model/alert_acknowledgement.dart';
import '../../domain/model/alert_acknowledgement_result.dart';
import '../../domain/model/monitoring_failure.dart';
import '../../domain/model/ranch_alert.dart';
import '../../domain/repositories/alert_repository.dart';
import '../http/monitoring_api_client.dart';
import 'alert_mapping.dart';

/// REST adapter for ranch-scoped cloud alerts.
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

  @override
  Future<AlertAcknowledgementResult> acknowledge(
    String ranchId,
    AlertAcknowledgement request,
  ) async {
    final api = _api;
    if (api == null) {
      throw const MonitoringFailure(MonitoringFailureCode.configuration);
    }
    final response = await api.acknowledgeAlert(ranchId, request);
    if (response.statusCode == 409) {
      RanchAlert? currentAlert;
      try {
        currentAlert = AlertMapping.alertFromPayload(
          response.payload,
          ranchId: ranchId,
          alertId: request.alertId,
        );
      } on MonitoringFailure {
        // A conflict may have no stored resource body; the service performs a fresh read.
      }
      return AlertAcknowledgementResult.conflict(currentAlert: currentAlert);
    }
    if (response.statusCode != 200) {
      throw const MonitoringFailure(MonitoringFailureCode.invalidResponse);
    }
    final alert = AlertMapping.alertFromPayload(
      response.payload,
      ranchId: ranchId,
      alertId: request.alertId,
    );
    return AlertAcknowledgementResult.acknowledged(alert);
  }
}
