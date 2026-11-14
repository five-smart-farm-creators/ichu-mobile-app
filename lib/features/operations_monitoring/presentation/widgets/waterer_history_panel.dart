import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';
import '../../application/services/waterer_read_service.dart';
import '../../domain/model/water_history_query.dart';
import 'monitoring_format.dart';
import 'waterer_status_view.dart';

final class WatererHistoryPanel extends StatefulWidget {
  const WatererHistoryPanel({super.key, required this.service});
  final WatererReadService service;

  @override
  State<WatererHistoryPanel> createState() => _WatererHistoryPanelState();
}

final class _WatererHistoryPanelState extends State<WatererHistoryPanel> {
  late DateTime _from;
  late DateTime _to;
  int _requestedPage = 1;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _to = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    _from = _to.subtract(const Duration(days: 1));
  }

  Future<void> _chooseBound(bool start) async {
    final revision = widget.service.revision;
    final initial = start ? _from : _to;
    final strings = AppLocalizations.of(context);
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
      helpText: start ? strings.watererFrom : strings.watererTo,
    );
    if (!mounted || revision != widget.service.revision || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (!mounted || revision != widget.service.revision || time == null) return;
    final instant = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (start) {
        _from = instant;
      } else {
        _to = instant;
      }
      _requestedPage = 1;
    });
    widget.service.clearHistory();
  }

  void _load(int page) {
    _requestedPage = page;
    unawaited(
      widget.service.loadHistory(
        WaterHistoryQuery(from: _from, to: _to, page: page),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final service = widget.service;
    final busy = service.historyStatus == WatererLoadStatus.loading;
    final page = service.history;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            strings.watererHistoryTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 12),
        Text(strings.watererHistoryLead),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const Key('waterer-history-from'),
          onPressed: busy ? null : () => _chooseBound(true),
          child: Text(
            '${strings.watererFrom}: ${MonitoringFormat.instant(strings, _from)}',
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('waterer-history-to'),
          onPressed: busy ? null : () => _chooseBound(false),
          child: Text(
            '${strings.watererTo}: ${MonitoringFormat.instant(strings, _to)}',
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          key: const Key('waterer-history-load'),
          onPressed: busy
              ? null
              : () => _load(service.historyError == null ? 1 : _requestedPage),
          child: Text(
            service.historyError == null
                ? strings.watererLoadHistory
                : strings.watererRetry,
          ),
        ),
        if (busy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
          Text(strings.watererLoading),
        ],
        if (service.historyError case final failure?)
          WatererFailureNotice(failure: failure),
        if (page != null) ...[
          const SizedBox(height: 12),
          Text(strings.watererHistoryPage(page.page, page.totalCount)),
          if (page.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(strings.watererHistoryEmpty),
            ),
          for (final reading in page.items)
            Card(
              key: ValueKey('waterer-reading-${reading.id}'),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: WatererReadingView(reading: reading),
              ),
            ),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              TextButton.icon(
                key: const Key('waterer-history-previous'),
                onPressed: !busy && page.page > 1
                    ? () => _load(page.page - 1)
                    : null,
                icon: const Icon(Icons.chevron_left),
                label: Text(strings.watererPrevious),
              ),
              TextButton.icon(
                key: const Key('waterer-history-next'),
                onPressed: !busy && page.page * page.pageSize < page.totalCount
                    ? () => _load(page.page + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
                label: Text(strings.watererNext),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
