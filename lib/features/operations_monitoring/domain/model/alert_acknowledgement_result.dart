import 'ranch_alert.dart';

enum AlertAcknowledgementOutcome { acknowledged, conflict }

/// A server-confirmed acknowledgement or a version conflict to reconcile.
final class AlertAcknowledgementResult {
  const AlertAcknowledgementResult({required this.outcome, this.currentAlert});

  const AlertAcknowledgementResult.acknowledged(RanchAlert alert)
    : outcome = AlertAcknowledgementOutcome.acknowledged,
      currentAlert = alert;

  const AlertAcknowledgementResult.conflict({this.currentAlert})
    : outcome = AlertAcknowledgementOutcome.conflict;

  final AlertAcknowledgementOutcome outcome;
  final RanchAlert? currentAlert;
}
