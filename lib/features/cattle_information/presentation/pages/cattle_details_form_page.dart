import 'package:flutter/material.dart';

import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';
import '../../application/services/cattle_management_service.dart';
import '../../domain/model/cattle.dart';
import '../../domain/model/cattle_commands.dart';
import '../../domain/model/cattle_date.dart';
import '../widgets/cattle_failure_notice.dart';
import '../widgets/cattle_input_fields.dart';
import '../widgets/cattle_labels.dart';

/// Registers an animal, or corrects its identification when [original] is given.
final class CattleDetailsFormPage extends StatefulWidget {
  const CattleDetailsFormPage({
    super.key,
    required this.management,
    this.original,
  });

  final CattleManagementService management;
  final Cattle? original;

  @override
  State<CattleDetailsFormPage> createState() => _CattleDetailsFormPageState();
}

final class _CattleDetailsFormPageState extends State<CattleDetailsFormPage> {
  static const _earliestBirthDate = CattleDate(1900, 1, 1);

  late final TextEditingController _earTag;
  CattleBreed? _breed;
  CattleSex? _sex;
  CattleStage? _stage;
  CattleDate? _birthDate;
  Set<CattleInputIssue> _issues = const <CattleInputIssue>{};
  bool _showRequired = false;

  @override
  void initState() {
    super.initState();
    final original = widget.original;
    _earTag = TextEditingController(text: original?.earTag ?? '');
    _breed = original?.breed;
    _sex = original?.sex;
    _birthDate = original?.birthDate;
  }

  @override
  void dispose() {
    _earTag.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final management = widget.management;
    if (management.isSaving) return;
    final original = widget.original;
    final breed = _breed;
    final sex = _sex;
    final birthDate = _birthDate;
    final stage = _stage;
    if (breed == null ||
        sex == null ||
        birthDate == null ||
        (original == null && stage == null)) {
      setState(() {
        _showRequired = true;
        _issues = const <CattleInputIssue>{};
      });
      return;
    }

    final today = management.today;
    final Cattle? result;
    if (original == null) {
      final registration = CattleRegistration(
        earTag: _earTag.text,
        breed: breed,
        sex: sex,
        birthDate: birthDate,
        lifeStage: stage!,
      );
      final issues = registration.issuesOn(today);
      if (issues.isNotEmpty) {
        _showIssues(issues);
        return;
      }
      _showIssues(const <CattleInputIssue>{});
      result = await management.register(registration);
    } else {
      final correction = CattleCorrection(
        earTag: _earTag.text,
        breed: breed,
        sex: sex,
        birthDate: birthDate,
      );
      final issues = correction.issuesFor(original, today);
      if (issues.isNotEmpty) {
        _showIssues(issues);
        return;
      }
      _showIssues(const <CattleInputIssue>{});
      result = await management.correct(original, correction);
    }
    if (!mounted) return;
    if (result != null) Navigator.of(context).pop(result);
  }

  void _showIssues(Set<CattleInputIssue> issues) => setState(() {
    _showRequired = false;
    _issues = issues;
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.management,
    builder: (context, _) {
      final strings = AppLocalizations.of(context);
      final management = widget.management;
      final original = widget.original;
      final busy = management.isSaving;
      final error = management.error;
      // A stale or unconfirmed write must be reloaded before another attempt.
      final blocked = busy || management.requiresReload;
      final today = management.today;
      final requiredText = _showRequired ? strings.cattleManageRequired : null;
      return PopScope(
        canPop: !busy,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              original == null
                  ? strings.cattleManageRegisterTitle
                  : strings.cattleManageEditTitle,
            ),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    original == null
                        ? strings.cattleManageRegisterLead
                        : strings.cattleManageEditLead,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    key: const Key('cattle-manage-form-ear-tag'),
                    controller: _earTag,
                    enabled: !busy,
                    maxLength: 30,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: strings.cattleEarTag,
                    ),
                  ),
                  const SizedBox(height: 12),
                  CattleChoiceField<CattleBreed>(
                    key: const Key('cattle-manage-form-breed'),
                    label: strings.cattleBreed,
                    value: _breed,
                    errorText: _breed == null ? requiredText : null,
                    onChanged: busy
                        ? null
                        : (value) => setState(() => _breed = value),
                    items: [
                      for (final breed in CattleBreed.values)
                        DropdownMenuItem(
                          value: breed,
                          child: Text(CattleLabels.breed(strings, breed)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  CattleChoiceField<CattleSex>(
                    key: const Key('cattle-manage-form-sex'),
                    label: strings.cattleSex,
                    value: _sex,
                    errorText: _sex == null ? requiredText : null,
                    onChanged: busy
                        ? null
                        : (value) => setState(() => _sex = value),
                    items: [
                      for (final sex in CattleSex.values)
                        DropdownMenuItem(
                          value: sex,
                          child: Text(CattleLabels.sex(strings, sex)),
                        ),
                    ],
                  ),
                  if (original == null) ...[
                    const SizedBox(height: 12),
                    CattleChoiceField<CattleStage>(
                      key: const Key('cattle-manage-form-stage'),
                      label: strings.cattleStage,
                      value: _stage,
                      errorText: _stage == null ? requiredText : null,
                      onChanged: busy
                          ? null
                          : (value) => setState(() => _stage = value),
                      items: [
                        for (final stage in CattleStage.values)
                          DropdownMenuItem(
                            value: stage,
                            child: Text(CattleLabels.stage(strings, stage)),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  CattleDateField(
                    key: const Key('cattle-manage-form-birth-date'),
                    label: strings.cattleBirthDate,
                    value: _birthDate,
                    firstDate: _earliestBirthDate,
                    lastDate: today,
                    errorText: _birthDate == null ? requiredText : null,
                    onChanged: busy
                        ? null
                        : (value) => setState(() => _birthDate = value),
                  ),
                  CattleIssueList(issues: _issues),
                  if (error != null)
                    CattleFailureNotice(failure: error, isWrite: true),
                  if (busy)
                    Semantics(
                      liveRegion: true,
                      child: Text(strings.cattleManageSaving),
                    ),
                  const SizedBox(height: 20),
                  FilledButton(
                    key: const Key('cattle-manage-form-save'),
                    onPressed: blocked ? null : _save,
                    child: Text(strings.cattleManageSave),
                  ),
                  TextButton(
                    key: const Key('cattle-manage-form-cancel'),
                    onPressed: busy ? null : () => Navigator.of(context).pop(),
                    child: Text(strings.cattleManageCancel),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
