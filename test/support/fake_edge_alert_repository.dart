import 'dart:async';

import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/edge_alert.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/repositories/edge_alert_repository.dart';

final class FakeEdgeAlertRepository implements EdgeAlertRepository {
  bool configured = true;
  EdgeAlertPage? pageResult;
  Object? failure;
  Completer<EdgeAlertPage>? completer;
  final requests = <({String ranchId, int page})>[];

  @override
  bool get isConfigured => configured;

  @override
  Future<EdgeAlertPage> page(String ranchId, int page) {
    requests.add((ranchId: ranchId, page: page));
    final pending = completer;
    if (pending != null) return pending.future;
    final error = failure;
    if (error != null) return Future<EdgeAlertPage>.error(error);
    final result = pageResult;
    if (result != null) return Future<EdgeAlertPage>.value(result);
    return Future<EdgeAlertPage>.error(StateError('Missing test page'));
  }
}
