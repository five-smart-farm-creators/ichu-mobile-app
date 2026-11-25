import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';
import '../../application/services/alert_read_service.dart';
import '../../domain/model/alert_acknowledgement.dart';
import '../../domain/model/alert_acknowledgement_result.dart';
import '../../domain/model/monitoring_failure.dart';
import '../../domain/model/ranch_alert.dart';

final class AlertAcknowledgementDialog extends StatefulWidget {
  const AlertAcknowledgementDialog({
    required this.service,
    required this.alert,
    super.key,
  });

  final AlertReadService service;
  final RanchAlert alert;

  @override
  State<AlertAcknowledgementDialog> createState() =>
      _AlertAcknowledgementDialogState();
}

final class _AlertAcknowledgementDialogState
    extends State<AlertAcknowledgementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _findingController = TextEditingController();
  final _actionController = TextEditingController();
  AlertAcknowledgement? _request;
  MonitoringFailureCode? _failure;
  bool _busy = false;

  @override
  void dispose() {
    _findingController.dispose();
    _actionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_request == null && !_formKey.currentState!.validate()) return;

    final request =
        _request ??
        AlertAcknowledgement(
          alertId: widget.alert.alertId,
          operationId: _newOperationId(),
          finding: _findingController.text.trim(),
          action: _actionController.text.trim().isEmpty
              ? null
              : _actionController.text.trim(),
          expectedVersion: widget.alert.version,
        );
    setState(() {
      _request = request;
      _failure = null;
      _busy = true;
    });

    try {
      final result = await widget.service.acknowledge(widget.alert, request);
      if (!mounted) return;
      setState(() => _busy = false);
      Navigator.of(context).pop(result.outcome);
    } on MonitoringFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = failure.code;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = MonitoringFailureCode.unknown;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final retrying = _request != null;
    return PopScope<AlertAcknowledgementOutcome>(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(strings.alertAcknowledgementDialogTitle),
        scrollable: true,
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(strings.alertAcknowledgementNotice),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('alert-acknowledgement-finding'),
                controller: _findingController,
                readOnly: retrying,
                maxLength: 400,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: strings.alertFindingInput,
                  alignLabelWithHint: true,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? strings.alertFindingRequired
                    : value.length > 400
                    ? strings.alertTextTooLong
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('alert-acknowledgement-action'),
                controller: _actionController,
                readOnly: retrying,
                maxLength: 400,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: strings.alertActionInput,
                  alignLabelWithHint: true,
                ),
                validator: (value) => value != null && value.length > 400
                    ? strings.alertTextTooLong
                    : null,
              ),
              if (_failure case final failure?) ...[
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _failureText(strings, failure),
                    key: const Key('alert-acknowledgement-error'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
              if (retrying && _failure != null) ...[
                const SizedBox(height: 8),
                Text(strings.alertAcknowledgementRetryNote),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('alert-acknowledgement-cancel'),
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(strings.termsBack),
          ),
          FilledButton.icon(
            key: const Key('alert-acknowledgement-submit'),
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_outlined),
            label: Text(
              retrying
                  ? strings.alertRetryAcknowledgement
                  : strings.alertSubmitAcknowledgement,
            ),
          ),
        ],
      ),
    );
  }
}

String _failureText(
  AppLocalizations strings,
  MonitoringFailureCode code,
) => switch (code) {
  MonitoringFailureCode.configuration =>
    strings.alertAcknowledgementErrorConfiguration,
  MonitoringFailureCode.contextUnavailable => strings.cattleChooseRanch,
  MonitoringFailureCode.unauthenticated =>
    strings.alertAcknowledgementErrorUnauthenticated,
  MonitoringFailureCode.forbidden => strings.alertAcknowledgementErrorForbidden,
  MonitoringFailureCode.notFound => strings.alertAcknowledgementErrorNotFound,
  MonitoringFailureCode.network => strings.alertAcknowledgementErrorNetwork,
  MonitoringFailureCode.serviceUnavailable =>
    strings.alertAcknowledgementErrorUnavailable,
  MonitoringFailureCode.invalidResponse =>
    strings.alertAcknowledgementErrorResponse,
  MonitoringFailureCode.invalidSearch =>
    strings.alertAcknowledgementErrorUnknown,
  MonitoringFailureCode.invalidHistoryQuery =>
    strings.alertAcknowledgementErrorUnknown,
  MonitoringFailureCode.invalidAcknowledgement =>
    strings.alertAcknowledgementErrorInvalid,
  MonitoringFailureCode.unknown => strings.alertAcknowledgementErrorUnknown,
};

String _newOperationId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}
