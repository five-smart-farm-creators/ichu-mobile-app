import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/ranch_alert.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/repositories/alert_notifier.dart';

/// Records what the device would have announced; no platform plugin is involved.
final class FakeAlertNotifier implements AlertNotifier {
  bool initialized = false;
  Object? showFailure;
  final shown = <RanchAlert>[];

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<void> show(RanchAlert alert) async {
    final failure = showFailure;
    if (failure != null) throw failure;
    shown.add(alert);
  }

  @override
  Stream<void> get taps => const Stream<void>.empty();
}
