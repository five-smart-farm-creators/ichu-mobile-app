/// A version-checked, idempotent cloud acknowledgement request.
final class AlertAcknowledgement {
  const AlertAcknowledgement({
    required this.alertId,
    required this.operationId,
    required this.finding,
    required this.expectedVersion,
    this.action,
  });

  final String alertId;
  final String operationId;
  final String finding;
  final String? action;
  final int expectedVersion;
}
