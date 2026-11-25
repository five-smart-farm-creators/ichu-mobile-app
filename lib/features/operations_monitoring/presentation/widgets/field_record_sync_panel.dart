import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';
import '../../application/services/field_record_service.dart';
import '../../domain/model/field_record_sync.dart';

/// Explicit foreground synchronization; failures never disable local capture.
final class FieldRecordSyncPanel extends StatelessWidget {
  const FieldRecordSyncPanel({super.key, required this.records});

  final FieldRecordService records;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.fieldSyncTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(strings.fieldSyncLead),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('field-sync-send'),
          onPressed: records.canSynchronize
              ? () => unawaited(records.synchronize())
              : null,
          icon: const Icon(Icons.sync),
          label: Text(
            records.synchronizing
                ? strings.fieldSyncSending
                : strings.fieldSyncSend,
          ),
        ),
        if (records.lastSyncConfirmed case final count?) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(strings.fieldSyncConfirmed(count)),
          ),
        ],
        if (records.syncError case final failure?) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(_failureMessage(strings, failure.code)),
          ),
        ],
        if (records.syncIssues.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(strings.fieldSyncReviewNotice),
        ],
      ],
    );
  }

  String _failureMessage(
    AppLocalizations strings,
    FieldRecordSyncFailureCode code,
  ) => switch (code) {
    FieldRecordSyncFailureCode.contextUnavailable =>
      strings.fieldSyncContextError,
    FieldRecordSyncFailureCode.permissionRequired =>
      strings.fieldSyncPermissionError,
    FieldRecordSyncFailureCode.storageUnavailable =>
      strings.fieldSyncStorageError,
    FieldRecordSyncFailureCode.network ||
    FieldRecordSyncFailureCode.serviceUnavailable =>
      strings.fieldSyncConnectionError,
    FieldRecordSyncFailureCode.invalidResponse =>
      strings.fieldSyncResponseError,
    _ => strings.fieldSyncUnavailable,
  };
}
