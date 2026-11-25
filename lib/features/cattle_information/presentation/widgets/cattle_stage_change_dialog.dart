import 'package:flutter/material.dart';

import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';
import '../../application/services/cattle_management_service.dart';
import '../../domain/model/cattle.dart';
import '../../domain/model/cattle_commands.dart';
import '../../domain/model/cattle_date.dart';
import 'cattle_failure_notice.dart';
import 'cattle_input_fields.dart';
import 'cattle_labels.dart';

/// Records a new productive stage; the dialog closes with the saved animal on success.
final class CattleStageChangeDialog extends StatefulWidget {
  const CattleStageChangeDialog({
    super.key,
    required this.management,
    required this.cattle,
  });

  final CattleManagementService management;
  final Cattle cattle;

  @override
  State<CattleStageChangeDialog> createState() =>
      _CattleStageChangeDialogState();
}

final class _CattleStageChangeDialogState
    extends State<CattleStageChangeDialog> {
  CattleStage? _stage;
  CattleDate? _date;
  Set<CattleInputIssue> _issues = const <CattleInputIssue>{};
  bool _showRequired = false;

  Future<void> _save() async {
    final management = widget.management;
    if (management.isSaving) return;
    final stage = _stage;
    final date = _date;
    if (stage == null || date == null) {
      setState(() {
        _showRequired = true;
        _issues = const <CattleInputIssue>{};
      });
      return;
    }
    final change = CattleStageChange(stage: stage, validFrom: date);
    final issues = change.issuesFor(widget.cattle, management.today);
    if (issues.isNotEmpty) {
      setState(() {
        _showRequired = false;
        _issues = issues;
      });
      return;
    }
    final result = await management.changeStage(widget.cattle, change);
    if (!mounted) return;
    if (result != null) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.management,
    builder: (context, _) {
      final strings = AppLocalizations.of(context);
      final management = widget.management;
      final busy = management.isSaving;
      final error = management.error;
      final blocked = busy || management.requiresReload;
      final requiredText = _showRequired ? strings.cattleManageRequired : null;
      return PopScope(
        canPop: !busy,
        child: AlertDialog(
          title: Text(strings.cattleManageStageDialogTitle),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(strings.cattleManageStageNotice),
              const SizedBox(height: 16),
              CattleChoiceField<CattleStage>(
                key: const Key('cattle-manage-stage-value'),
                label: strings.cattleManageNewStage,
                value: _stage,
                errorText: _stage == null ? requiredText : null,
                onChanged: busy
                    ? null
                    : (value) => setState(() => _stage = value),
                items: [
                  for (final stage in CattleStage.values)
                    if (stage != widget.cattle.currentStage)
                      DropdownMenuItem(
                        value: stage,
                        child: Text(CattleLabels.stage(strings, stage)),
                      ),
                ],
              ),
              const SizedBox(height: 12),
              CattleDateField(
                key: const Key('cattle-manage-stage-date'),
                label: strings.cattleManageStageDate,
                value: _date,
                firstDate: CattleDateRules.earliestChangeDate(widget.cattle),
                lastDate: management.today,
                errorText: _date == null ? requiredText : null,
                onChanged: busy
                    ? null
                    : (value) => setState(() => _date = value),
              ),
              CattleIssueList(issues: _issues),
              if (busy)
                Semantics(
                  liveRegion: true,
                  child: Text(strings.cattleManageSaving),
                ),
              if (error != null)
                CattleFailureNotice(failure: error, isWrite: true),
            ],
          ),
          actions: [
            TextButton(
              key: const Key('cattle-manage-stage-cancel'),
              onPressed: busy ? null : () => Navigator.of(context).pop(),
              child: Text(strings.cattleManageCancel),
            ),
            FilledButton(
              key: const Key('cattle-manage-stage-save'),
              onPressed: blocked ? null : _save,
              child: Text(strings.cattleManageStageConfirm),
            ),
          ],
        ),
      );
    },
  );
}
