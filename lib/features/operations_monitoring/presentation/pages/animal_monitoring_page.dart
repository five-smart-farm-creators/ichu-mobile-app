import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/layout/public_shell.dart';
import '../../../../shared/application/services/language_service.dart';
import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';
import '../../application/services/monitoring_read_service.dart';
import '../../domain/model/latest_telemetry.dart';
import '../../domain/model/monitoring_failure.dart';
import '../../domain/model/telemetry_history.dart';
import '../../domain/model/telemetry_history_query.dart';
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
  late DateTimeRange _historyRange;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _historyRange = DateTimeRange(
      start: now.subtract(const Duration(hours: 24)),
      end: now,
    );
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

  void _loadHistoryRange(DateTimeRange range) {
    setState(() => _historyRange = range);
    unawaited(
      widget.service.loadHistory(
        widget.cattleId,
        TelemetryHistoryQuery(from: range.start, to: range.end),
      ),
    );
  }

  void _loadHistoryPreset(Duration duration) {
    final end = DateTime.now();
    _loadHistoryRange(DateTimeRange(start: end.subtract(duration), end: end));
  }

  Future<void> _chooseHistoryDates(BuildContext context) async {
    final now = DateTime.now();
    final lastDate = DateUtils.dateOnly(now);
    final currentStart = DateUtils.dateOnly(_historyRange.start);
    final currentEnd = DateUtils.dateOnly(_historyRange.end);
    final start = currentStart.isAfter(lastDate) ? lastDate : currentStart;
    final end = currentEnd.isAfter(lastDate) ? lastDate : currentEnd;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1),
      lastDate: lastDate,
      initialDateRange: DateTimeRange(
        start: start,
        end: end.isBefore(start) ? start : end,
      ),
    );
    if (!mounted || range == null) return;
    final from = DateTime(range.start.year, range.start.month, range.start.day);
    final to = DateTime(range.end.year, range.end.month, range.end.day + 1);
    _loadHistoryRange(DateTimeRange(start: from, end: to));
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
              const SizedBox(height: 8),
              _historySection(context, strings),
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

  Widget _historySection(BuildContext context, AppLocalizations strings) {
    final theme = Theme.of(context);
    final service = widget.service;
    final page = service.historyPage;
    final query = service.historyQuery;
    final selectedPeriod = strings.monitoringHistorySelectedDates(
      MonitoringFormat.instant(strings, _historyRange.start),
      MonitoringFormat.instant(strings, _historyRange.end),
    );
    final pageCount = page == null || page.totalCount == 0
        ? 0
        : ((page.totalCount - 1) ~/ page.pageSize) + 1;

    return Card(
      key: const Key('monitoring-history'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                strings.monitoringHistoryTitle,
                style: theme.textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 8),
            Text(strings.monitoringHistoryLead),
            const SizedBox(height: 12),
            Text(selectedPeriod),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  key: const Key('monitoring-history-24-hours'),
                  onPressed: () =>
                      _loadHistoryPreset(const Duration(hours: 24)),
                  child: Text(strings.monitoringHistoryLast24Hours),
                ),
                TextButton(
                  key: const Key('monitoring-history-7-days'),
                  onPressed: () => _loadHistoryPreset(const Duration(days: 7)),
                  child: Text(strings.monitoringHistoryLast7Days),
                ),
                TextButton(
                  key: const Key('monitoring-history-choose-dates'),
                  onPressed: () => unawaited(_chooseHistoryDates(context)),
                  child: Text(strings.monitoringHistoryChooseDates),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  key: const Key('monitoring-history-load'),
                  onPressed: service.canLoadHistory
                      ? () => unawaited(
                          service.loadHistory(
                            widget.cattleId,
                            TelemetryHistoryQuery(
                              from: _historyRange.start,
                              to: _historyRange.end,
                            ),
                          ),
                        )
                      : null,
                  child: Text(strings.monitoringHistoryLoad),
                ),
                if (query != null &&
                    service.historyStatus == TelemetryHistoryLoadStatus.ready)
                  OutlinedButton.icon(
                    key: const Key('monitoring-history-reload'),
                    onPressed: service.canLoadHistory
                        ? () => unawaited(service.reloadHistory())
                        : null,
                    icon: const Icon(Icons.refresh),
                    label: Text(strings.monitoringReload),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (service.historyStatus == TelemetryHistoryLoadStatus.loading)
              Semantics(
                liveRegion: true,
                child: Text(strings.monitoringHistoryLoading),
              ),
            if (service.historyError case final failure?)
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _failureText(strings, failure.code),
                    key: const Key('monitoring-history-error'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ),
            if (page != null &&
                service.historyStatus == TelemetryHistoryLoadStatus.ready) ...[
              Text(strings.monitoringHistoryCount(page.totalCount)),
              if (page.oldestRetainedRecordedAt case final oldest?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    strings.monitoringHistoryOldestAvailable(
                      MonitoringFormat.instant(strings, oldest),
                    ),
                  ),
                ),
              if (page.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    strings.monitoringHistoryEmpty,
                    key: const Key('monitoring-history-empty'),
                  ),
                )
              else ...[
                const SizedBox(height: 12),
                for (final reading in page.items)
                  _HistoryReadingCard(reading: reading),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('monitoring-history-previous'),
                        onPressed: service.canGoPreviousHistoryPage
                            ? () => unawaited(service.previousHistoryPage())
                            : null,
                        child: Text(strings.monitoringHistoryPrevious),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.monitoringHistoryPage(page.page, pageCount),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('monitoring-history-next'),
                        onPressed: service.canGoNextHistoryPage
                            ? () => unawaited(service.nextHistoryPage())
                            : null,
                        child: Text(strings.monitoringHistoryNext),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

final class _HistoryReadingCard extends StatelessWidget {
  const _HistoryReadingCard({required this.reading});

  final TelemetryReading reading;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Card(
      key: Key('monitoring-history-reading-${reading.readingId}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Value(
              label: strings.monitoringHistoryCaptured,
              value: MonitoringFormat.instant(strings, reading.recordedAt),
            ),
            _Value(
              label: strings.monitoringHistoryReceived,
              value: MonitoringFormat.instant(strings, reading.receivedAt),
            ),
            _HistoricalMetric(
              label: strings.monitoringHistoryTemperature,
              measurement: reading.bodyTemperature,
            ),
            _HistoricalMetric(
              label: strings.monitoringHistoryActivity,
              measurement: reading.activityIndex,
            ),
            _HistoricalMetric(
              label: strings.monitoringHistoryRumination,
              measurement: reading.ruminationMinutes,
            ),
            _HistoricalMetric(
              label: strings.monitoringHistoryBattery,
              measurement: reading.batteryLevel,
            ),
            Semantics(
              header: true,
              child: Text(
                strings.monitoringHistoryPosition,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            const SizedBox(height: 4),
            if (!reading.position.isValid)
              Text(
                reading.position.status == HistoricalMeasurementStatus.invalid
                    ? strings.monitoringHistoryValueInvalid
                    : strings.monitoringHistoryPositionUnavailable,
              )
            else
              Text(
                '${MonitoringFormat.number(strings, reading.position.latitude!)}°, '
                '${MonitoringFormat.number(strings, reading.position.longitude!)}° · '
                '${strings.monitoringMeters(MonitoringFormat.number(strings, reading.position.accuracyMeters!))}',
              ),
          ],
        ),
      ),
    );
  }
}

final class _HistoricalMetric extends StatelessWidget {
  const _HistoricalMetric({required this.label, required this.measurement});

  final String label;
  final HistoricalMeasurement measurement;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final value = switch (measurement.status) {
      HistoricalMeasurementStatus.absent =>
        strings.monitoringHistoryValueAbsent,
      HistoricalMeasurementStatus.invalid =>
        strings.monitoringHistoryValueInvalid,
      HistoricalMeasurementStatus.valid =>
        '${MonitoringFormat.number(strings, measurement.value!)} ${_unit(strings, measurement.unit)}',
    };
    return _Value(label: label, value: value);
  }

  String _unit(AppLocalizations strings, String unit) => switch (unit) {
    'celsius' => strings.monitoringUnitCelsius,
    'index' => strings.monitoringUnitIndex,
    'minutes' => strings.monitoringUnitMinutes,
    'percent' => '%',
    _ => unit,
  };
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
      MonitoringFailureCode.invalidHistoryQuery =>
        strings.monitoringErrorHistoryQuery,
      MonitoringFailureCode.invalidAcknowledgement =>
        strings.monitoringErrorUnknown,
      MonitoringFailureCode.unknown => strings.monitoringErrorUnknown,
    };
