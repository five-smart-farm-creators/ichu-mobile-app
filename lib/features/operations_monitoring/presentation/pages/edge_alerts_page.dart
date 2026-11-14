import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/layout/public_shell.dart';
import '../../../../shared/application/services/language_service.dart';
import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';
import '../../application/services/edge_alert_read_service.dart';
import '../../domain/model/edge_alert.dart';
import '../../domain/model/monitoring_failure.dart';
import '../widgets/monitoring_format.dart';

/// Reads synchronized Edge Gateway-origin records without cloud acknowledgements.
final class EdgeAlertsPage extends StatefulWidget {
  const EdgeAlertsPage({
    super.key,
    required this.language,
    required this.service,
    required this.onBack,
    required this.onOpenRanches,
  });

  final LanguageService language;
  final EdgeAlertReadService service;
  final VoidCallback onBack;
  final VoidCallback onOpenRanches;

  @override
  State<EdgeAlertsPage> createState() => _EdgeAlertsPageState();
}

final class _EdgeAlertsPageState extends State<EdgeAlertsPage> {
  @override
  void initState() {
    super.initState();
    _loadInitialPage(widget.service);
  }

  @override
  void didUpdateWidget(covariant EdgeAlertsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      _loadInitialPage(widget.service);
    }
  }

  void _loadInitialPage(EdgeAlertReadService service) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(widget.service, service)) return;
      if (service.hasContext && service.status == EdgeAlertLoadStatus.idle) {
        unawaited(service.load(page: 1));
      }
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.service,
    builder: (context, _) {
      final strings = AppLocalizations.of(context);
      final service = widget.service;
      final theme = Theme.of(context);
      final page = service.page;
      final busy = service.status == EdgeAlertLoadStatus.loading;
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
                strings.edgeAlertTitle,
                style: theme.textTheme.headlineLarge,
              ),
            ),
            const SizedBox(height: 12),
            Text(strings.edgeAlertLead),
            const SizedBox(height: 12),
            Text(strings.edgeAlertSyncedNote),
            const SizedBox(height: 20),
            if (!service.hasContext) ...[
              Text(strings.edgeAlertErrorContext),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('edge-alerts-choose-ranch'),
                onPressed: widget.onOpenRanches,
                child: Text(strings.iamOpenRanches),
              ),
            ] else ...[
              Text(service.ranchName ?? '', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              if (busy) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(strings.edgeAlertLoading),
                ),
              ],
              if (service.status == EdgeAlertLoadStatus.unavailable)
                _Notice(
                  key: const Key('edge-alerts-unavailable'),
                  message: service.error == null
                      ? strings.edgeAlertUnavailable
                      : _failureText(strings, service.error!.code),
                  isError: true,
                ),
              if (service.status == EdgeAlertLoadStatus.stale) ...[
                _Notice(
                  key: const Key('edge-alerts-stale'),
                  message: strings.edgeAlertStale,
                  isError: true,
                ),
                if (service.lastLoadedAt case final timestamp?)
                  Text(
                    strings.edgeAlertLastUpdated(
                      MonitoringFormat.instant(strings, timestamp),
                    ),
                  ),
              ],
              if (service.error != null &&
                  service.status != EdgeAlertLoadStatus.unavailable &&
                  service.status != EdgeAlertLoadStatus.stale)
                _Notice(
                  key: const Key('edge-alerts-error'),
                  message: _failureText(strings, service.error!.code),
                  isError: true,
                ),
              if (page != null) ...[
                const SizedBox(height: 16),
                Text(
                  strings.edgeAlertPage(page.page),
                  style: theme.textTheme.titleMedium,
                ),
                Text(strings.edgeAlertTotal(page.totalCount)),
                const SizedBox(height: 12),
                if (page.items.isEmpty &&
                    service.status == EdgeAlertLoadStatus.ready)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(strings.edgeAlertEmpty),
                  ),
                for (final alert in page.items)
                  Padding(
                    key: ValueKey(
                      'edge-alert-${service.revision}-${page.page}-${alert.alertId}',
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: _EdgeAlertCard(alert: alert),
                  ),
                if (service.status == EdgeAlertLoadStatus.stale &&
                    page.items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(strings.edgeAlertEmpty),
                  ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  TextButton.icon(
                    key: const Key('edge-alerts-refresh'),
                    onPressed: service.canLoad
                        ? () => unawaited(service.refresh())
                        : null,
                    icon: const Icon(Icons.refresh),
                    label: Text(
                      service.status == EdgeAlertLoadStatus.stale ||
                              service.status == EdgeAlertLoadStatus.unavailable
                          ? strings.edgeAlertRetry
                          : strings.edgeAlertRefresh,
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('edge-alerts-previous'),
                    onPressed: service.canGoPrevious
                        ? () => unawaited(service.previousPage())
                        : null,
                    icon: const Icon(Icons.chevron_left),
                    label: Text(strings.edgeAlertPrevious),
                  ),
                  TextButton.icon(
                    key: const Key('edge-alerts-next'),
                    onPressed: service.canGoNext
                        ? () => unawaited(service.nextPage())
                        : null,
                    icon: const Icon(Icons.chevron_right),
                    label: Text(strings.edgeAlertNext),
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

final class _EdgeAlertCard extends StatelessWidget {
  const _EdgeAlertCard({required this.alert});

  final EdgeAlert alert;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final unit = switch (alert.unit) {
      'celsius' => strings.monitoringUnitCelsius,
      'index' => strings.monitoringUnitIndex,
      'meters' => strings.alertUnitMeters,
      null => strings.edgeAlertNotProvided,
      final value => value,
    };
    final type = switch (alert.type) {
      EdgeAlertType.temperature => strings.alertTypeTemperature,
      EdgeAlertType.activity => strings.alertTypeActivity,
      EdgeAlertType.geofence => strings.alertTypeGeofence,
    };
    final severity = switch (alert.severity) {
      EdgeAlertSeverity.informative => strings.alertSeverityInformative,
      EdgeAlertSeverity.warning => strings.alertSeverityWarning,
      EdgeAlertSeverity.critical => strings.alertSeverityCritical,
    };
    return Card(
      child: ExpansionTile(
        key: Key('edge-alert-details-${alert.alertId}'),
        title: Text('$type · $severity'),
        subtitle: Text(strings.edgeAlertCattle(alert.cattleId)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Value(
            label: strings.edgeAlertRaisedAt,
            value: MonitoringFormat.instant(strings, alert.raisedAt),
          ),
          _Value(
            label: strings.edgeAlertReceivedAt,
            value: MonitoringFormat.instant(strings, alert.receivedAt),
          ),
          _Value(label: strings.edgeAlertGateway, value: alert.gatewayId),
          _Value(label: strings.edgeAlertDevice, value: alert.deviceId),
          if (alert.detectedValue case final value?)
            _Value(
              label: strings.edgeAlertDetectedValue,
              value: '${MonitoringFormat.number(strings, value)} $unit',
            ),
          if (alert.thresholdMinValue case final minimum?)
            if (alert.thresholdMaxValue case final maximum?)
              _Value(
                label: strings.edgeAlertThreshold,
                value:
                    '${MonitoringFormat.number(strings, minimum)}–${MonitoringFormat.number(strings, maximum)} $unit',
              ),
          if (alert.latitude case final latitude?)
            if (alert.longitude case final longitude?)
              _Value(
                label: strings.edgeAlertCoordinates,
                value:
                    '${MonitoringFormat.number(strings, latitude)}, ${MonitoringFormat.number(strings, longitude)}',
              ),
          if (alert.distanceToBoundaryMeters case final distance?)
            _Value(
              label: strings.edgeAlertDistance,
              value:
                  '${MonitoringFormat.number(strings, distance)} ${strings.alertUnitMeters}',
            ),
          if (alert.clearedAt case final clearedAt?)
            _Value(
              label: strings.edgeAlertClearedAt,
              value: MonitoringFormat.instant(strings, clearedAt),
            ),
          _Value(
            label: strings.edgeAlertConfigurationRevision,
            value: alert.configurationRevision.toString(),
          ),
          _Value(
            label: strings.edgeAlertEvidenceCount,
            value: strings.edgeAlertEvidence(alert.readingIds.length),
          ),
        ],
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
        SelectableText(value),
      ],
    ),
  );
}

final class _Notice extends StatelessWidget {
  const _Notice({super.key, required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          message,
          style: TextStyle(
            color: isError
                ? theme.colorScheme.error
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

String _failureText(
  AppLocalizations strings,
  MonitoringFailureCode code,
) => switch (code) {
  MonitoringFailureCode.configuration => strings.edgeAlertErrorConfiguration,
  MonitoringFailureCode.contextUnavailable => strings.edgeAlertErrorContext,
  MonitoringFailureCode.unauthenticated =>
    strings.edgeAlertErrorUnauthenticated,
  MonitoringFailureCode.forbidden => strings.edgeAlertErrorForbidden,
  MonitoringFailureCode.notFound => strings.edgeAlertErrorNotFound,
  MonitoringFailureCode.network ||
  MonitoringFailureCode.serviceUnavailable => strings.edgeAlertErrorUnavailable,
  MonitoringFailureCode.invalidSearch => strings.edgeAlertErrorSearch,
  MonitoringFailureCode.invalidResponse => strings.edgeAlertErrorResponse,
  MonitoringFailureCode.invalidHistoryQuery ||
  MonitoringFailureCode.invalidAcknowledgement ||
  MonitoringFailureCode.unknown => strings.edgeAlertErrorUnknown,
};
