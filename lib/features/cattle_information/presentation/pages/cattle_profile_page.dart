import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/layout/public_shell.dart';
import '../../../../shared/application/services/language_service.dart';
import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';
import '../../application/services/cattle_read_service.dart';
import '../widgets/cattle_failure_notice.dart';
import '../widgets/cattle_labels.dart';

final class CattleProfilePage extends StatefulWidget {
  const CattleProfilePage({
    super.key,
    required this.language,
    required this.service,
    required this.cattleId,
    required this.onBack,
    required this.onOpenRanches,
    this.onOpenMonitoring,
  });

  final LanguageService language;
  final CattleReadService service;
  final String cattleId;
  final VoidCallback onBack;
  final VoidCallback onOpenRanches;
  final ValueChanged<String>? onOpenMonitoring;

  @override
  State<CattleProfilePage> createState() => _CattleProfilePageState();
}

final class _CattleProfilePageState extends State<CattleProfilePage> {
  @override
  void initState() {
    super.initState();
    _loadAfterBuild();
  }

  @override
  void didUpdateWidget(covariant CattleProfilePage oldWidget) {
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
      unawaited(service.loadProfile(id));
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.service,
    builder: (context, _) {
      final service = widget.service;
      final strings = AppLocalizations.of(context);
      final theme = Theme.of(context);
      final profile = service.profile;
      final ready =
          service.profileStatus == CattleLoadStatus.ready &&
          profile != null &&
          profile.cattle.id.toLowerCase() == widget.cattleId.toLowerCase();
      return PublicShell(
        language: widget.language,
        showBackButton: true,
        onBack: widget.onBack,
        backLabel: strings.cattleBackList,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                strings.cattleProfileTitle,
                style: theme.textTheme.headlineLarge,
              ),
            ),
            const SizedBox(height: 12),
            Text(strings.cattleProfileLead),
            const SizedBox(height: 20),
            if (!service.hasContext) ...[
              Text(strings.cattleChooseRanch),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: widget.onOpenRanches,
                child: Text(strings.iamOpenRanches),
              ),
            ] else ...[
              Text(service.ranchName ?? '', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              if (service.profileStatus == CattleLoadStatus.loading)
                Semantics(
                  liveRegion: true,
                  child: Text(strings.cattleProfileLoading),
                ),
              if (service.profileError case final error?)
                CattleFailureNotice(failure: error),
              if (ready) ...[
                if (widget.onOpenMonitoring case final openMonitoring?) ...[
                  OutlinedButton.icon(
                    key: const Key('cattle-open-monitoring'),
                    onPressed: () => openMonitoring(profile.cattle.id),
                    icon: const Icon(Icons.monitor_heart_outlined),
                    label: Text(strings.monitoringOpen),
                  ),
                  const SizedBox(height: 16),
                ],
                Card(
                  key: const Key('cattle-profile-data'),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Value(
                          label: strings.cattleEarTag,
                          value: profile.cattle.earTag,
                        ),
                        _Value(
                          label: strings.cattleBreed,
                          value: CattleLabels.breed(
                            strings,
                            profile.cattle.breed,
                          ),
                        ),
                        _Value(
                          label: strings.cattleSex,
                          value: CattleLabels.sex(strings, profile.cattle.sex),
                        ),
                        _Value(
                          label: strings.cattleBirthDate,
                          value: CattleLabels.date(
                            strings,
                            profile.cattle.birthDate,
                          ),
                        ),
                        _Value(
                          label: strings.cattleStage,
                          value: CattleLabels.stage(
                            strings,
                            profile.cattle.currentStage,
                          ),
                        ),
                        _Value(
                          label: strings.cattleStatus,
                          value: CattleLabels.status(
                            strings,
                            profile.cattle.status,
                          ),
                        ),
                        if (profile.cattle.exitReason case final reason?)
                          _Value(
                            label: strings.cattleExitReason,
                            value: CattleLabels.exitReason(strings, reason),
                          ),
                        if (profile.cattle.exitDate case final date?)
                          _Value(
                            label: strings.cattleExitDate,
                            value: CattleLabels.date(strings, date),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Semantics(
                  header: true,
                  child: Text(
                    strings.cattleCollar,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 12),
                if (!profile.device.isAvailable)
                  Text(strings.cattleDeviceUnavailable)
                else if (profile.device.collarId == null)
                  Text(strings.cattleNoCollar)
                else ...[
                  _Value(
                    label: strings.cattleCollarId,
                    value: profile.device.collarId!,
                  ),
                  _Value(
                    label: strings.cattleLastReceived,
                    value: profile.device.lastReadingReceivedAt == null
                        ? strings.cattleNoCommunication
                        : DateFormat.yMMMd(strings.localeName).add_jm().format(
                            profile.device.lastReadingReceivedAt!.toLocal(),
                          ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(strings.cattleReceptionNote),
                const SizedBox(height: 20),
                Semantics(
                  header: true,
                  child: Text(
                    strings.cattleStageHistory,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                for (final period in profile.cattle.stagePeriods)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              CattleLabels.stage(strings, period.stage),
                              style: theme.textTheme.titleMedium,
                            ),
                            Text(
                              '${strings.cattlePeriodFrom}: ${CattleLabels.date(strings, period.validFrom)}',
                            ),
                            Text(
                              period.validTo == null
                                  ? strings.cattlePeriodOpen
                                  : '${strings.cattlePeriodUntil}: ${CattleLabels.date(strings, period.validTo!)}',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              OutlinedButton.icon(
                key: const Key('cattle-profile-reload'),
                onPressed:
                    service.canLoad &&
                        service.profileStatus != CattleLoadStatus.loading
                    ? () => unawaited(service.loadProfile(widget.cattleId))
                    : null,
                icon: const Icon(Icons.refresh),
                label: Text(strings.cattleReloadProfile),
              ),
            ],
          ],
        ),
      );
    },
  );
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
