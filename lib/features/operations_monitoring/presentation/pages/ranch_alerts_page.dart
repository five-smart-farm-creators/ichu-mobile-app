import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/layout/public_shell.dart';
import '../../../../shared/application/services/language_service.dart';
import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';
import '../../application/services/alert_read_service.dart';
import '../../domain/model/alert_search.dart';
import '../../domain/model/alert_acknowledgement_result.dart';
import '../../domain/model/monitoring_failure.dart';
import '../../domain/model/ranch_alert.dart';
import '../widgets/monitoring_format.dart';
import '../widgets/alert_acknowledgement_dialog.dart';

/// Reads cloud events and records version-checked cloud acknowledgements.
final class RanchAlertsPage extends StatefulWidget {
  const RanchAlertsPage({
    super.key,
    required this.language,
    required this.service,
    required this.onBack,
    required this.onOpenRanches,
  });

  final LanguageService language;
  final AlertReadService service;
  final VoidCallback onBack;
  final VoidCallback onOpenRanches;

  @override
  State<RanchAlertsPage> createState() => _RanchAlertsPageState();
}

final class _RanchAlertsPageState extends State<RanchAlertsPage> {
  AlertStatus? _status;
  int _revision = -1;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    final service = widget.service;
    _status = service.query.status;
    _revision = service.revision;
    service.addListener(_onScopeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(widget.service, service)) return;
      if (service.hasContext && service.status != AlertLoadStatus.ready) {
        unawaited(service.load());
      }
    });
  }

  void _onScopeChanged() {
    if (!mounted || _revision == widget.service.revision) return;
    setState(() {
      _revision = widget.service.revision;
      _status = widget.service.query.status;
    });
  }

  Future<void> _acknowledge(RanchAlert alert) async {
    final outcome = await showDialog<AlertAcknowledgementOutcome>(
      context: context,
      builder: (context) =>
          AlertAcknowledgementDialog(service: widget.service, alert: alert),
    );
    if (!mounted || outcome == null) return;
    final strings = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          outcome == AlertAcknowledgementOutcome.acknowledged
              ? strings.alertAcknowledgementSaved
              : strings.alertAcknowledgementConflict,
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant RanchAlertsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      oldWidget.service.removeListener(_onScopeChanged);
      _bind();
    }
  }

  @override
  void dispose() {
    widget.service.removeListener(_onScopeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.service,
    builder: (context, _) {
      final strings = AppLocalizations.of(context);
      final service = widget.service;
      final theme = Theme.of(context);
      final busy = service.status == AlertLoadStatus.loading;
      final draftChanged = _status != service.query.status;
      return PublicShell(
        language: widget.language,
        showBackButton: true,
        onBack: widget.onBack,
        backLabel: strings.cattleBackAccount,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                strings.alertTitle,
                style: theme.textTheme.headlineLarge,
              ),
            ),
            const SizedBox(height: 12),
            Text(strings.alertActionLead),
            const SizedBox(height: 16),
            Text(strings.alertCloudNote),
            const SizedBox(height: 20),
            if (!service.hasContext) ...[
              Text(strings.cattleChooseRanch),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('alerts-choose-ranch'),
                onPressed: widget.onOpenRanches,
                child: Text(strings.iamOpenRanches),
              ),
            ] else ...[
              Text(service.ranchName ?? '', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              DropdownButtonFormField<AlertStatus>(
                key: ValueKey('alerts-status-$_status-$_revision'),
                initialValue: _status,
                isExpanded: true,
                decoration: InputDecoration(labelText: strings.alertStatus),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(strings.alertAllStatuses),
                  ),
                  for (final status in AlertStatus.values)
                    DropdownMenuItem(
                      value: status,
                      child: Text(_statusText(strings, status)),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (value) => setState(() => _status = value),
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('alerts-apply'),
                onPressed: service.canLoad
                    ? () => unawaited(
                        service.load(query: AlertSearch(status: _status)),
                      )
                    : null,
                child: Text(strings.alertApply),
              ),
              TextButton.icon(
                key: const Key('alerts-reload'),
                onPressed: service.canLoad && !draftChanged
                    ? () => unawaited(service.load())
                    : null,
                icon: const Icon(Icons.refresh),
                label: Text(strings.alertReload),
              ),
              if (busy)
                Semantics(liveRegion: true, child: Text(strings.alertLoading)),
              if (service.error case final error?)
                Semantics(
                  liveRegion: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      _failureText(strings, error.code),
                      key: const Key('alerts-error'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ),
              if (service.status == AlertLoadStatus.ready) ...[
                const SizedBox(height: 16),
                Text(
                  strings.alertPage(service.query.page),
                  style: theme.textTheme.titleMedium,
                ),
                if (service.totalCount case final count?)
                  Text(strings.alertTotal(count)),
                const SizedBox(height: 12),
                if (service.alerts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(strings.alertEmpty),
                  ),
                for (final alert in service.alerts)
                  Padding(
                    key: ValueKey(
                      'alert-row-$_revision-${service.query.page}-${alert.alertId}',
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: _AlertCard(
                      alert: alert,
                      isAcknowledging: service.isAcknowledging,
                      onAcknowledge: () => unawaited(_acknowledge(alert)),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  TextButton.icon(
                    key: const Key('alerts-previous'),
                    onPressed: !draftChanged && service.canGoPrevious
                        ? () => unawaited(service.previousPage())
                        : null,
                    icon: const Icon(Icons.chevron_left),
                    label: Text(strings.cattlePrevious),
                  ),
                  TextButton.icon(
                    key: const Key('alerts-next'),
                    onPressed: !draftChanged && service.canGoNext
                        ? () => unawaited(service.nextPage())
                        : null,
                    icon: const Icon(Icons.chevron_right),
                    label: Text(strings.cattleNext),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    },
  );
}

final class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.alert,
    required this.isAcknowledging,
    required this.onAcknowledge,
  });
  final RanchAlert alert;
  final bool isAcknowledging;
  final VoidCallback onAcknowledge;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final unit = switch (alert.unit) {
      'celsius' => strings.monitoringUnitCelsius,
      'index' => strings.monitoringUnitIndex,
      'meters' => strings.alertUnitMeters,
      null => strings.alertNotProvided,
      final value => value,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      _typeText(strings, alert.type),
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${strings.alertSeverity}: ${_severityText(strings, alert.severity)}',
                  ),
                  Text(
                    '${strings.alertStatus}: ${_statusText(strings, alert.status)}',
                  ),
                  const SizedBox(height: 8),
                  _Value(
                    label: strings.monitoringAnimalId,
                    value: alert.cattleId,
                  ),
                  _Value(
                    label: strings.alertRaisedAt,
                    value: MonitoringFormat.instant(strings, alert.raisedAt),
                  ),
                ],
              ),
            ),
            if (alert.status == AlertStatus.pending)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  key: Key('alert-acknowledge-${alert.alertId}'),
                  onPressed: isAcknowledging ? null : onAcknowledge,
                  icon: const Icon(Icons.cloud_done_outlined),
                  label: Text(strings.alertAcknowledgeCloud),
                ),
              ),
            ExpansionTile(
              key: Key('alert-details-${alert.alertId}'),
              title: Text(strings.alertDetails),
              childrenPadding: const EdgeInsets.all(8),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(strings.alertEventSnapshotNote),
                const SizedBox(height: 16),
                _Value(label: strings.alertId, value: alert.alertId),
                _Value(
                  label: strings.alertReceivedAt,
                  value: MonitoringFormat.instant(strings, alert.receivedAt),
                ),
                _Value(
                  label: strings.monitoringOrigin,
                  value: switch (alert.origin) {
                    AlertOrigin.edgeGateway => strings.monitoringOriginGateway,
                  },
                ),
                _Value(label: strings.alertDeviceId, value: alert.deviceId),
                _Value(label: strings.alertGatewayId, value: alert.gatewayId),
                if (alert.type != AlertType.geofence) ...[
                  _Value(
                    label: strings.alertDetectedValue,
                    value: _nullableNumber(strings, alert.detectedValue),
                  ),
                  _Value(label: strings.alertUnit, value: unit),
                  _Value(
                    label: strings.alertThresholdMin,
                    value: _nullableNumber(strings, alert.thresholdMinValue),
                  ),
                  _Value(
                    label: strings.alertThresholdMax,
                    value: _nullableNumber(strings, alert.thresholdMaxValue),
                  ),
                ] else ...[
                  Text(strings.alertGeofenceNote),
                  const SizedBox(height: 12),
                  _Value(
                    label: strings.alertGeofenceId,
                    value: alert.geofenceId ?? strings.alertNotProvided,
                  ),
                  _Value(
                    label: strings.monitoringLatitude,
                    value: _nullableNumber(strings, alert.latitude),
                  ),
                  _Value(
                    label: strings.monitoringLongitude,
                    value: _nullableNumber(strings, alert.longitude),
                  ),
                  _Value(
                    label: strings.alertBoundaryDistance,
                    value: _nullableNumber(
                      strings,
                      alert.distanceToBoundaryMeters,
                    ),
                  ),
                  _Value(
                    label: strings.alertClearedAt,
                    value: _nullableTime(strings, alert.clearedAt),
                  ),
                  _Value(
                    label: strings.alertExitDuration,
                    value: _nullableNumber(strings, alert.exitDurationSeconds),
                  ),
                ],
                _Value(
                  label: strings.alertRevision,
                  value: alert.configurationRevision.toString(),
                ),
                _Value(
                  label: strings.alertVersion,
                  value: alert.version.toString(),
                ),
                Semantics(
                  header: true,
                  child: Text(
                    strings.alertAcknowledgement,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 12),
                Text(strings.alertWorkflowNote),
                const SizedBox(height: 12),
                _Value(
                  label: strings.alertAcknowledgedAt,
                  value: _nullableTime(strings, alert.acknowledgedAt),
                ),
                _Value(
                  label: strings.alertAcknowledgedBy,
                  value: alert.acknowledgedBy ?? strings.alertNotProvided,
                ),
                _Value(
                  label: strings.alertFinding,
                  value: alert.finding ?? strings.alertNotProvided,
                ),
                _Value(
                  label: strings.alertAction,
                  value: alert.action ?? strings.alertNotProvided,
                ),
                _Value(
                  label: strings.alertResponseTime,
                  value: _nullableNumber(strings, alert.responseTimeSeconds),
                ),
                _Value(
                  label: strings.alertReadingIds,
                  value: alert.readingIds.isEmpty
                      ? strings.alertNotProvided
                      : alert.readingIds.take(10).join('\n'),
                ),
                if (alert.readingIds.length > 10)
                  Text(
                    strings.alertReadingIdsMore(10, alert.readingIds.length),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final class _Value extends StatelessWidget {
  const _Value({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(value),
      ],
    ),
  );
}

String _nullableNumber(AppLocalizations strings, double? value) => value == null
    ? strings.alertNotProvided
    : MonitoringFormat.number(strings, value);
String _nullableTime(AppLocalizations strings, DateTime? value) => value == null
    ? strings.alertNotProvided
    : MonitoringFormat.instant(strings, value);
String _typeText(AppLocalizations strings, AlertType type) => switch (type) {
  AlertType.temperature => strings.alertTypeTemperature,
  AlertType.activity => strings.alertTypeActivity,
  AlertType.geofence => strings.alertTypeGeofence,
};
String _severityText(AppLocalizations strings, AlertSeverity severity) =>
    switch (severity) {
      AlertSeverity.informative => strings.alertSeverityInformative,
      AlertSeverity.warning => strings.alertSeverityWarning,
      AlertSeverity.critical => strings.alertSeverityCritical,
    };
String _statusText(AppLocalizations strings, AlertStatus status) =>
    switch (status) {
      AlertStatus.pending => strings.alertPending,
      AlertStatus.acknowledged => strings.alertAcknowledged,
    };
String _failureText(AppLocalizations strings, MonitoringFailureCode code) =>
    switch (code) {
      MonitoringFailureCode.configuration => strings.alertErrorConfiguration,
      MonitoringFailureCode.contextUnavailable => strings.cattleChooseRanch,
      MonitoringFailureCode.invalidSearch => strings.alertErrorSearch,
      MonitoringFailureCode.invalidAcknowledgement =>
        strings.alertAcknowledgementErrorInvalid,
      MonitoringFailureCode.unauthenticated =>
        strings.monitoringErrorUnauthenticated,
      MonitoringFailureCode.forbidden => strings.alertErrorForbidden,
      MonitoringFailureCode.notFound => strings.alertErrorNotFound,
      MonitoringFailureCode.network => strings.alertErrorNetwork,
      MonitoringFailureCode.serviceUnavailable => strings.alertErrorUnavailable,
      MonitoringFailureCode.invalidResponse => strings.alertErrorResponse,
      MonitoringFailureCode.unknown => strings.alertErrorUnknown,
    };
