import '../model/alert_search.dart';
import '../model/ranch_alert.dart';

abstract interface class AlertRepository {
  bool get isConfigured;

  Future<AlertPage> search(String ranchId, AlertSearch query);
}
