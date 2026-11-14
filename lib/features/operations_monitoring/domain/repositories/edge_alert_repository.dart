import '../model/edge_alert.dart';

abstract interface class EdgeAlertRepository {
  static const int pageSize = 20;

  bool get isConfigured;

  Future<EdgeAlertPage> page(String ranchId, int page);
}
