import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/layout/public_shell.dart';
import '../../../../shared/application/services/language_service.dart';
import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';
import '../../application/services/monitoring_read_service.dart';
import '../../domain/model/latest_telemetry.dart';
import '../../domain/model/monitoring_failure.dart';
import '../widgets/monitoring_format.dart';

/// Presents a server-evaluated snapshot, not a live or clinical assessment.
final class AnimalMonitoringPage extends StatefulWidget {
  const AnimalMonitoringPage({
    super.key,
    required this.language,
    required this.service,
    required this.cattleId,
    required this.onBack,
    required this.onOpenRanches,
  });

  final LanguageService language;
  final MonitoringReadService service;
  final String cattleId;
  final VoidCallback onBack;
  final VoidCallback onOpenRanches;

  @override
  State<AnimalMonitoringPage> createState() => _AnimalMonitoringPageState();
}

final class _AnimalMonitoringPageState extends State<AnimalMonitoringPage> {
  @override
  void initState() {
    super.initState();
    _loadAfterBuild();
  }

  @override
  void didUpdateWidget(covariant AnimalMonitoringPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service ||
        oldWidget.cattleId != widget.cattleId) {
      _loadAfterBuild();
    }
  }

  void _loadAfterBuild() {
    final service = widget.service;
    final id = widget.cattleId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !identical(widget.service, service) ||
          widget.cattleId != id) {
        return;
      }
      unawaited(service.load(id));
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.service,
    builder: (context, _) {
      final strings = AppLocalizations.of(context);
      final theme = Theme.of(context);
      final service = widget.service;
      final snapshot = service.snapshot;
      final ready =
          service.status == MonitoringLoadStatus.ready &&
          snapshot != null &&
          snapshot.cattleId.toLowerCase() == widget.cattleId.toLowerCase();
      return PublicShell(
        language: widget.language,
        showBackButton: true,
        onBack: widget.onBack,
        backLabel: strings.monitoringBackAnimal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                strings.monitoringTitle,
                style: theme.textTheme.headlineLarge,
              ),
            ),
            const SizedBox(height: 12),
            Text(strings.monitoringLead),
            const SizedBox(height: 20),
            if (!service.hasContext) ...[
              Text(strings.cattleChooseRanch),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('monitoring-choose-ranch'),
                onPressed: widget.onOpenRanches,
                child: Text(strings.iamOpenRanches),
              ),
            ] else ...[
              Text(service.ranchName ?? '', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              if (service.status == MonitoringLoadStatus.loading)
                Semantics(
                  liveRegion: true,
                  child: Text(strings.monitoringLoading),
                ),
              if (service.error case final failure?)
                Semantics(
                  liveRegion: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      _failureText(strings, failure.code),
                      key: const Key('monitoring-error'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ),
              if (ready) ...[
                Card(
                  key: const Key('monitoring-snapshot'),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Value(
                          label: strings.monitoringAnimalId,
                          value: snapshot.cattleId,
                        ),
                        _Value(
                          label: strings.monitoringEvaluatedAt,
                          value: MonitoringFormat.instant(
                            strings,
                            snapshot.evaluatedAt,
                          ),
                        ),
                        _Value(
                          label: strings.monitoringOrigin,
                          value: switch (snapshot.origin) {
                            TelemetryOrigin.edgeGateway =>
                              strings.monitoringOriginGateway,
                          },
                        ),
                        _Value(
                          label: strings.monitoringLastCapture,
                          value: snapshot.lastReadingRecordedAt == null
                              ? strings.monitoringNoCapture
                              : MonitoringFormat.instant(
                                  strings,
                                  snapshot.lastReadingRecordedAt!,
                                ),
                        ),
                        Text(strings.monitoringSnapshotNote),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _Indicator(
                  key: const Key('monitoring-temperature'),
                  title: strings.monitoringTemperature,
                  indicator: snapshot.bodyTemperature,
                ),
                _Indicator(
                  key: const Key('monitoring-activity'),
                  title: strings.monitoringActivity,
                  indicator: snapshot.activityIndex,
                ),
                _Indicator(
                  key: const Key('monitoring-rumination'),
                  title: strings.monitoringRumination,
                  indicator: snapshot.ruminationMinutes,
                ),
                Card(
                  key: const Key('monitoring-position'),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            strings.monitoringPosition,
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(strings.monitoringPositionNote),
                        const SizedBox(height: 12),
                        if (!snapshot.lastKnownPosition.isAvailable)
                          Text(strings.monitoringPositionUnavailable)
                        else ...[
                          _Value(
                            label: strings.monitoringLatitude,
                            value: MonitoringFormat.number(
                              strings,
                              snapshot.lastKnownPosition.latitude!,
                            ),
                          ),
                          _Value(
                            label: strings.monitoringLongitude,
                            value: MonitoringFormat.number(
                              strings,
                              snapshot.lastKnownPosition.longitude!,
                            ),
                          ),
                          _Value(
                            label: strings.monitoringAccuracy,
                            value: strings.monitoringMeters(
                              MonitoringFormat.number(
                                strings,
                                snapshot.lastKnownPosition.accuracyMeters!,
                              ),
                            ),
                          ),
                          _Capture(
                            recordedAt: snapshot.lastKnownPosition.recordedAt!,
                            isStale: snapshot.lastKnownPosition.isStale!,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              OutlinedButton.icon(
                key: const Key('monitoring-reload'),
                onPressed: service.canLoad
                    ? () => unawaited(service.load(widget.cattleId))
                    : null,
                icon: const Icon(Icons.refresh),
                label: Text(strings.monitoringReload),
              ),
            ],
          ],
        ),
      );
    },
  );
}

final class _Indicator extends StatelessWidget {
  const _Indicator({super.key, required this.title, required this.indicator});
  final String title;
  final LatestIndicator indicator;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final unit = switch (indicator.unit) {
      TelemetryUnit.celsius => strings.monitoringUnitCelsius,
      TelemetryUnit.activityIndex => strings.monitoringUnitIndex,
      TelemetryUnit.minutes => strings.monitoringUnitMinutes,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 12),
              if (!indicator.isAvailable)
                Text(strings.monitoringIndicatorUnavailable)
              else ...[
                Text(
                  '${MonitoringFormat.number(strings, indicator.value!)} $unit',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                _Capture(
                  recordedAt: indicator.recordedAt!,
                  isStale: indicator.isStale!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

final class _Capture extends StatelessWidget {
  const _Capture({required this.recordedAt, required this.isStale});
  final DateTime recordedAt;
  final bool isStale;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Value(
          label: strings.monitoringCapturedAt,
          value: MonitoringFormat.instant(strings, recordedAt),
        ),
        Text(isStale ? strings.monitoringStale : strings.monitoringNotStale),
      ],
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

String _failureText(AppLocalizations strings, MonitoringFailureCode code) =>
    switch (code) {
      MonitoringFailureCode.configuration =>
        strings.monitoringErrorConfiguration,
      MonitoringFailureCode.contextUnavailable => strings.cattleChooseRanch,
      MonitoringFailureCode.unauthenticated =>
        strings.monitoringErrorUnauthenticated,
      MonitoringFailureCode.forbidden => strings.monitoringErrorForbidden,
      MonitoringFailureCode.notFound => strings.monitoringErrorNotFound,
      MonitoringFailureCode.network => strings.monitoringErrorNetwork,
      MonitoringFailureCode.serviceUnavailable =>
        strings.monitoringErrorUnavailable,
      MonitoringFailureCode.invalidResponse => strings.monitoringErrorResponse,
      MonitoringFailureCode.invalidSearch => strings.monitoringErrorUnknown,
      MonitoringFailureCode.invalidAcknowledgement =>
        strings.monitoringErrorUnknown,
      MonitoringFailureCode.unknown => strings.monitoringErrorUnknown,
    };
