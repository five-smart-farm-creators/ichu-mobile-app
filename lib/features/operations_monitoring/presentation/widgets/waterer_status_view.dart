import 'package:flutter/material.dart';

import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';
import '../../domain/model/monitoring_failure.dart';
import '../../domain/model/waterer.dart';
import 'monitoring_format.dart';

final class WatererStatusView extends StatelessWidget {
  const WatererStatusView({
    super.key,
    required this.status,
    this.detailed = false,
  });
  final WatererStatus status;
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final controller = switch (status.controllerStatus) {
      WaterControllerStatus.noController => strings.watererNoController,
      WaterControllerStatus.noReadings => strings.watererNoReadings,
      WaterControllerStatus.communicating => strings.watererCommunicating,
      WaterControllerStatus.noCommunication => strings.watererNoCommunication,
    };
    final measurement = switch (status.measurementStatus) {
      WaterMeasurementStatus.unavailable => strings.watererUnavailable,
      WaterMeasurementStatus.invalid => strings.watererInvalid,
      WaterMeasurementStatus.valid => strings.watererValid,
    };
    final range = switch (status.rangeStatus) {
      WaterRangeStatus.notConfigured => strings.watererNotConfigured,
      WaterRangeStatus.unavailable => strings.watererUnavailable,
      WaterRangeStatus.belowRange => strings.watererBelowRange,
      WaterRangeStatus.withinRange => strings.watererWithinRange,
      WaterRangeStatus.aboveRange => strings.watererAboveRange,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WatererValue(label: strings.watererControllerStatus, value: controller),
        WatererValue(
          label: strings.watererMeasurementStatus,
          value: measurement,
        ),
        WatererValue(label: strings.watererRangeStatus, value: range),
        WatererValue(
          label: strings.watererEvaluatedAt,
          value: MonitoringFormat.instant(strings, status.evaluatedAt),
        ),
        if (detailed) ...[
          WatererValue(
            label: strings.watererIdentifier,
            value: status.waterTroughId,
          ),
          if (status.lotId case final lot?)
            WatererValue(label: strings.watererLot, value: lot),
          WatererValue(
            label: strings.watererConfiguredRange,
            value: status.minimumCelsius == null
                ? strings.watererNotConfigured
                : '${MonitoringFormat.number(strings, status.minimumCelsius!)} – ${MonitoringFormat.number(strings, status.maximumCelsius!)} °C',
          ),
          WatererValue(
            label: strings.watererController,
            value: status.controllerId ?? strings.watererNoController,
          ),
          WatererValue(
            label: strings.watererAssignedAt,
            value: status.controllerAssignedAt == null
                ? strings.watererUnavailable
                : MonitoringFormat.instant(
                    strings,
                    status.controllerAssignedAt!,
                  ),
          ),
          WatererValue(
            label: strings.watererLastCommunication,
            value: status.lastCommunicationAt == null
                ? strings.watererUnavailable
                : MonitoringFormat.instant(
                    strings,
                    status.lastCommunicationAt!,
                  ),
          ),
          Text(
            strings.watererLatestReading,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (status.latestReading case final reading?)
            WatererReadingView(reading: reading)
          else
            Text(strings.watererNoMeasurement),
        ],
      ],
    );
  }
}

final class WatererReadingView extends StatelessWidget {
  const WatererReadingView({super.key, required this.reading});
  final WaterReading reading;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final temperature =
        '${MonitoringFormat.number(strings, reading.temperatureCelsius)} °C';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WatererValue(
          label: strings.watererTemperature,
          value: reading.isValid
              ? temperature
              : strings.watererInvalidTemperature(temperature),
        ),
        WatererValue(
          label: strings.watererCapturedAt,
          value: MonitoringFormat.instant(strings, reading.capturedAt),
        ),
        WatererValue(
          label: strings.watererReceivedAt,
          value: MonitoringFormat.instant(strings, reading.receivedAt),
        ),
        WatererValue(
          label: strings.watererHeater,
          value: reading.heaterState == WaterHeaterState.on
              ? strings.watererHeaterOn
              : strings.watererHeaterOff,
        ),
        WatererValue(
          label: strings.watererIdentifier,
          value: reading.waterTroughId,
        ),
        WatererValue(
          label: strings.watererReadingIdentifier,
          value: reading.readingId,
        ),
      ],
    );
  }
}

final class WatererValue extends StatelessWidget {
  const WatererValue({super.key, required this.label, required this.value});
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

final class WatererFailureNotice extends StatelessWidget {
  const WatererFailureNotice({super.key, required this.failure});
  final MonitoringFailure failure;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final message = switch (failure.code) {
      MonitoringFailureCode.configuration => strings.watererErrorConfiguration,
      MonitoringFailureCode.contextUnavailable => strings.watererErrorContext,
      MonitoringFailureCode.unauthenticated =>
        strings.watererErrorUnauthenticated,
      MonitoringFailureCode.forbidden => strings.watererErrorForbidden,
      MonitoringFailureCode.notFound => strings.watererErrorNotFound,
      MonitoringFailureCode.network ||
      MonitoringFailureCode.serviceUnavailable =>
        strings.watererErrorConnection,
      MonitoringFailureCode.invalidHistoryQuery => strings.watererErrorPeriod,
      MonitoringFailureCode.invalidResponse => strings.watererErrorResponse,
      _ => strings.watererErrorUnknown,
    };
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          message,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}
