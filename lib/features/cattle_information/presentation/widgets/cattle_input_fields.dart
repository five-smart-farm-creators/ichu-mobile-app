import 'package:flutter/material.dart';

import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';
import '../../domain/model/cattle_commands.dart';
import '../../domain/model/cattle_date.dart';
import 'cattle_labels.dart';

/// A choice rendered in an input decoration, so its error sits where text fields show theirs.
final class CattleChoiceField<T> extends StatelessWidget {
  const CattleChoiceField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.errorText,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration: InputDecoration(labelText: label, errorText: errorText),
    isEmpty: value == null,
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        items: items,
        onChanged: onChanged,
      ),
    ),
  );
}

/// Calendar day picker bounded by the server's rules; a null [onChanged] disables editing.
final class CattleDateField extends StatelessWidget {
  const CattleDateField({
    super.key,
    required this.label,
    required this.value,
    required this.firstDate,
    required this.lastDate,
    required this.onChanged,
    this.errorText,
  });

  final String label;
  final CattleDate? value;
  final CattleDate firstDate;
  final CattleDate lastDate;
  final ValueChanged<CattleDate>? onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final current = value;
    return InputDecorator(
      decoration: InputDecoration(labelText: label, errorText: errorText),
      isEmpty: current == null,
      child: InkWell(
        onTap: onChanged == null ? null : () => _pick(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            current == null
                ? strings.cattleManageSelectDate
                : CattleLabels.date(strings, current),
          ),
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    var initial = value ?? lastDate;
    if (initial.compareTo(lastDate) > 0) initial = lastDate;
    if (initial.compareTo(firstDate) < 0) initial = firstDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.asUtcDate,
      firstDate: firstDate.asUtcDate,
      lastDate: lastDate.asUtcDate,
    );
    if (picked != null) {
      onChanged?.call(CattleDate(picked.year, picked.month, picked.day));
    }
  }
}

/// Lists every rule that blocked a write, so the user sees all corrections at once.
final class CattleIssueList extends StatelessWidget {
  const CattleIssueList({super.key, required this.issues});

  final Set<CattleInputIssue> issues;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) return const SizedBox.shrink();
    final strings = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme.error;
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final issue in CattleInputIssue.values)
              if (issues.contains(issue))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    CattleLabels.issue(strings, issue),
                    style: TextStyle(color: color),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
