import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/layout/public_shell.dart';
import '../../../../shared/application/services/language_service.dart';
import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';
import '../../application/services/waterer_read_service.dart';
import '../widgets/waterer_history_panel.dart';
import '../widgets/waterer_status_view.dart';

/// Ranch list or one fresh trough status, with optional controller history.
final class WaterersPage extends StatefulWidget {
  const WaterersPage({
    super.key,
    required this.language,
    required this.service,
    required this.onBack,
    required this.onOpenRanches,
    this.onOpenDetails,
    this.waterTroughId,
    this.ranchId,
  }) : assert(waterTroughId == null || ranchId != null);
  final LanguageService language;
  final WatererReadService service;
  final VoidCallback onBack;
  final VoidCallback onOpenRanches;
  final ValueChanged<String>? onOpenDetails;
  final String? waterTroughId;
  final String? ranchId;

  @override
  State<WaterersPage> createState() => _WaterersPageState();
}

final class _WaterersPageState extends State<WaterersPage> {
  late int _revision;

  @override
  void initState() {
    super.initState();
    _revision = widget.service.revision;
    widget.service.addListener(_onChanged);
    _scheduleLoad();
  }

  @override
  void didUpdateWidget(covariant WaterersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      oldWidget.service.removeListener(_onChanged);
      widget.service.addListener(_onChanged);
      _revision = widget.service.revision;
    }
    if (oldWidget.service != widget.service ||
        oldWidget.waterTroughId != widget.waterTroughId ||
        oldWidget.ranchId != widget.ranchId) {
      _scheduleLoad();
    }
  }

  void _onChanged() {
    if (_revision == widget.service.revision) return;
    _revision = widget.service.revision;
    _scheduleLoad();
  }

  void _scheduleLoad() {
    final service = widget.service;
    final id = widget.waterTroughId;
    final revision = service.revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          identical(service, widget.service) &&
          id == widget.waterTroughId &&
          revision == service.revision &&
          service.hasContext &&
          _matchesRanch) {
        _load();
      }
    });
  }

  bool get _matchesRanch =>
      widget.waterTroughId == null ||
      widget.ranchId?.toLowerCase() == widget.service.ranchId?.toLowerCase();

  void _load() {
    if (!_matchesRanch) return;
    unawaited(
      widget.waterTroughId == null
          ? widget.service.loadList()
          : widget.service.loadDetail(widget.waterTroughId!),
    );
  }

  @override
  void dispose() {
    widget.service.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.service,
    builder: (context, _) {
      final strings = AppLocalizations.of(context);
      final service = widget.service;
      final isDetail = widget.waterTroughId != null;
      final status = isDetail ? service.detailStatus : service.listStatus;
      final busy = status == WatererLoadStatus.loading;
      final error = isDetail ? service.detailError : service.listError;
      final detail = service.detail;
      return PublicShell(
        language: widget.language,
        showBackButton: true,
        onBack: widget.onBack,
        backLabel: isDetail
            ? strings.watererBackList
            : strings.watererBackAccount,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                isDetail ? strings.watererDetailsTitle : strings.watererTitle,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
            ),
            const SizedBox(height: 12),
            Text(strings.watererOnlineLead),
            if (!service.hasContext || !_matchesRanch) ...[
              const SizedBox(height: 12),
              Text(strings.watererErrorContext),
              FilledButton(
                onPressed: widget.onOpenRanches,
                child: Text(strings.iamOpenRanches),
              ),
            ] else ...[
              const SizedBox(height: 12),
              Text(
                service.ranchName ?? '',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                key: const Key('waterer-refresh'),
                onPressed: busy ? null : _load,
                icon: const Icon(Icons.refresh),
                label: Text(
                  error == null ? strings.watererRefresh : strings.watererRetry,
                ),
              ),
              if (busy) ...[
                const LinearProgressIndicator(),
                Semantics(
                  liveRegion: true,
                  child: Text(strings.watererLoading),
                ),
              ],
              if (error != null) WatererFailureNotice(failure: error),
              if (!isDetail && status == WatererLoadStatus.ready) ...[
                if (service.items.isEmpty) Text(strings.watererEmpty),
                for (final item in service.items)
                  Card(
                    key: ValueKey('waterer-${item.waterTroughId}'),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            item.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          WatererStatusView(status: item),
                          OutlinedButton(
                            onPressed: widget.onOpenDetails == null
                                ? null
                                : () =>
                                      widget.onOpenDetails!(item.waterTroughId),
                            child: Text(strings.watererViewDetails),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              if (isDetail &&
                  detail != null &&
                  detail.waterTroughId.toLowerCase() ==
                      widget.waterTroughId!.toLowerCase()) ...[
                Text(
                  detail.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                WatererStatusView(status: detail, detailed: true),
                const SizedBox(height: 24),
                if (detail.controllerId != null)
                  WatererHistoryPanel(
                    key: ValueKey(
                      '${service.revision}-${detail.waterTroughId}-${detail.controllerId}',
                    ),
                    service: service,
                  )
                else
                  Text(strings.watererHistoryNoController),
              ],
            ],
          ],
        ),
      );
    },
  );
}
