import '../model/ranch_alert.dart';

/// Port for announcing cloud alerts on the device; platform details stay in infrastructure.
abstract interface class AlertNotifier {
  /// Prepares the platform plugin and asks for permission; calls after the first are no-ops.
  Future<void> initialize();

  Future<void> show(RanchAlert alert);

  /// Emits when the user taps a notification posted by this app.
  Stream<void> get taps;
}
