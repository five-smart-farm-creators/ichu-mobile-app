import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/layout/public_shell.dart';
import '../../../../shared/application/services/language_service.dart';
import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';
import '../../application/services/ranch_selection_service.dart';
import '../../domain/model/ranch_access.dart';

/// Lets an authenticated user choose among the ranches already authorized by
/// the server. Choosing a ranch does not grant or expand access.
final class RanchSelectionPage extends StatelessWidget {
  const RanchSelectionPage({
    super.key,
    required this.language,
    required this.selection,
    required this.onBack,
  });

  final LanguageService language;
  final RanchSelectionService selection;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: selection,
    builder: (context, _) {
      final strings = AppLocalizations.of(context);
      final theme = Theme.of(context);
      final available = selection.canSelect;
      final selected = selection.selectedRanch;

      return PublicShell(
        language: language,
        showBackButton: true,
        onBack: onBack,
        backLabel: strings.iamRanchesBack,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                strings.iamRanchesTitle,
                style: theme.textTheme.headlineLarge,
              ),
            ),
            const SizedBox(height: 8),
            Text(strings.iamRanchesLead),
            const SizedBox(height: 20),
            if (!available) ...[
              Semantics(
                liveRegion: true,
                child: Text(strings.iamRanchesUnavailable),
              ),
            ] else ...[
              Semantics(
                liveRegion: true,
                child: selected == null
                    ? Text(strings.iamNoRanchSelected)
                    : _SelectedRanchSummary(ranch: selected, strings: strings),
              ),
              const SizedBox(height: 16),
              if (selection.ranches.isEmpty)
                Text(strings.iamNoRanches)
              else
                for (final ranch in selection.ranches) ...[
                  _RanchCard(
                    ranch: ranch,
                    selected: selected?.ranchId == ranch.ranchId,
                    selection: selection,
                    strings: strings,
                  ),
                  const SizedBox(height: 12),
                ],
              if (selected != null)
                TextButton(
                  key: const Key('ranch-clear'),
                  onPressed: selection.clearSelection,
                  child: Text(strings.iamClearRanchSelection),
                ),
              const SizedBox(height: 8),
              Text(strings.iamRanchSelectionNotice),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('ranches-refresh'),
              onPressed: available
                  ? () => unawaited(selection.refresh())
                  : null,
              icon: const Icon(Icons.refresh),
              label: Text(strings.iamRefreshRanches),
            ),
          ],
        ),
      );
    },
  );
}

final class _SelectedRanchSummary extends StatelessWidget {
  const _SelectedRanchSummary({required this.ranch, required this.strings});

  final RanchAccess ranch;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('ranch-selected'),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.iamSelectedRanch),
          const SizedBox(height: 6),
          Text(ranch.name, style: Theme.of(context).textTheme.titleMedium),
          Text(strings.iamRanchSelected),
        ],
      ),
    ),
  );
}

final class _RanchCard extends StatelessWidget {
  const _RanchCard({
    required this.ranch,
    required this.selected,
    required this.selection,
    required this.strings,
  });

  final RanchAccess ranch;
  final bool selected;
  final RanchSelectionService selection;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final scope = switch (ranch.scope) {
      AccessScope.read => strings.iamRanchScopeRead,
      AccessScope.clinicalWrite => strings.iamRanchScopeClinicalWrite,
      AccessScope.manage => strings.iamRanchScopeManage,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(ranch.name, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('${ranch.region} · ${ranch.district}'),
            const SizedBox(height: 8),
            Text('${strings.iamRanchScope}: $scope'),
            if (ranch.expiresAt case final expiresAt?) ...[
              const SizedBox(height: 8),
              Text(
                strings.iamRanchExpires(
                  DateFormat.yMMMd(locale).add_jm().format(expiresAt.toLocal()),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(strings.iamRanchIdentifier(ranch.ranchId)),
            const SizedBox(height: 12),
            FilledButton(
              key: Key('ranch-select-${ranch.ranchId}'),
              onPressed: selected
                  ? null
                  : () => selection.select(ranch.ranchId),
              child: Text(
                selected ? strings.iamRanchSelected : strings.iamSelectRanch,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
