import '../model/alert_search.dart';
import '../model/alert_acknowledgement.dart';
import '../model/alert_acknowledgement_result.dart';
import '../model/ranch_alert.dart';

abstract interface class AlertRepository {
  bool get isConfigured;

  Future<AlertPage> search(String ranchId, AlertSearch query);

  Future<AlertAcknowledgementResult> acknowledge(
    String ranchId,
    AlertAcknowledgement request,
  );
}
