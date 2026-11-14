import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/layout/public_shell.dart';
import '../../../../shared/application/services/language_service.dart';
import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';
import '../../application/services/field_record_service.dart';
import '../../domain/model/field_record.dart';
import '../../domain/repositories/field_cattle_directory.dart';

final class FieldRecordsPage extends StatefulWidget {
  const FieldRecordsPage({
    super.key,
    required this.language,
    required this.records,
    required this.cattleDirectory,
    required this.onBack,
  });

  final LanguageService language;
  final FieldRecordService records;
  final FieldCattleDirectory cattleDirectory;
  final VoidCallback onBack;

  @override
  State<FieldRecordsPage> createState() => _FieldRecordsPageState();
}

final class _FieldRecordsPageState extends State<FieldRecordsPage> {
  final _formKey = GlobalKey<FormState>();
  final _earTag = TextEditingController();
  final _observation = TextEditingController();
  final _sireReference = TextEditingController();
  FieldCattleOption? _selectedCattle;
  FieldRecordType _type = FieldRecordType.healthEvent;
  DateTime _occurredAt = DateTime.now();
  String? _cattleError;
  bool _findingCattle = false;
  bool _contextChanged = false;
  int _revision = -1;

  @override
  void initState() {
    super.initState();
    _revision = widget.records.revision;
    widget.records.addListener(_onRecordServiceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.records.context != null &&
          widget.records.status == FieldRecordLoadStatus.idle) {
        unawaited(widget.records.load());
      }
    });
  }

  void _onRecordServiceChanged() {
    if (!mounted || _revision == widget.records.revision) return;
    final hadDraft =
        _selectedCattle != null ||
        _earTag.text.isNotEmpty ||
        _observation.text.isNotEmpty ||
        _sireReference.text.isNotEmpty;
    setState(() {
      _revision = widget.records.revision;
      _selectedCattle = null;
      _earTag.clear();
      _observation.clear();
      _sireReference.clear();
      _type = FieldRecordType.healthEvent;
      _occurredAt = DateTime.now();
      _cattleError = null;
      _findingCattle = false;
      _contextChanged = hadDraft;
    });
  }

  Future<void> _findCattle() async {
    final sessionContext = widget.records.context;
    if (sessionContext == null) {
      setState(
        () => _cattleError = AppLocalizations.of(
          context,
        ).fieldRecordContextUnavailable,
      );
      return;
    }
    final tag = _earTag.text.trim();
    if (tag.isEmpty || tag.length > FieldRecord.maximumCattleEarTagLength) {
      setState(
        () => _cattleError = AppLocalizations.of(
          context,
        ).fieldRecordCattleTagInvalid,
      );
      return;
    }
    setState(() {
      _findingCattle = true;
      _cattleError = null;
      _selectedCattle = null;
      _contextChanged = false;
    });

    final cached = widget.records.cattleOptions
        .where((option) => option.earTag == tag)
        .toList(growable: false);
    if (cached.length == 1) {
      if (mounted) setState(() => _selectedCattle = cached.single);
      if (mounted) setState(() => _findingCattle = false);
      return;
    }

    try {
      final found = await widget.cattleDirectory.findByExactEarTag(
        accountId: sessionContext.accountId,
        ranchId: sessionContext.ranchId,
        earTag: tag,
      );
      if (!mounted || !widget.records.isCurrent(sessionContext)) return;
      final matching = found
          .where(
            (option) =>
                option.earTag == tag &&
                option.ranchId.toLowerCase() ==
                    sessionContext.ranchId.toLowerCase(),
          )
          .toList(growable: false);
      if (matching.length == 1) {
        final selected = matching.single;
        await widget.records.cacheCattleOptions(<FieldCattleOption>[selected]);
        if (!mounted || !widget.records.isCurrent(sessionContext)) return;
        setState(() {
          _findingCattle = false;
          _selectedCattle = selected;
          if (widget.records.error != null) {
            _cattleError = AppLocalizations.of(context).fieldRecordStorageError;
          }
        });
      } else {
        setState(() {
          _findingCattle = false;
          _cattleError = AppLocalizations.of(context).fieldRecordCattleNotFound;
        });
      }
    } catch (_) {
      if (!mounted || !widget.records.isCurrent(sessionContext)) return;
      setState(() {
        _findingCattle = false;
        _cattleError = AppLocalizations.of(context).fieldRecordCattleLoadError;
      });
    }
  }

  Future<void> _chooseOccurredAt() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year, now.month, now.day),
      helpText: AppLocalizations.of(context).fieldRecordChooseDate,
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
      helpText: AppLocalizations.of(context).fieldRecordChooseTime,
    );
    if (!mounted || time == null) return;
    final selectedAt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (selectedAt.isAfter(
      DateTime.now().add(FieldRecord.maximumFutureOccurrenceOffset),
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).fieldRecordFutureDate),
        ),
      );
      return;
    }
    setState(() {
      _occurredAt = selectedAt;
      _contextChanged = false;
    });
  }

  Future<void> _save() async {
    final strings = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;
    final selected = _selectedCattle;
    final sessionContext = widget.records.context;
    if (selected == null || sessionContext == null) {
      setState(() => _cattleError = strings.fieldRecordCattleRequired);
      return;
    }

    try {
      await widget.records.save(
        cattleId: selected.cattleId,
        cattleEarTag: selected.earTag,
        type: _type,
        occurredAt: _occurredAt,
        observation: _observation.text,
        sireReference: _type == FieldRecordType.naturalMating
            ? _sireReference.text
            : null,
      );
      if (!mounted) return;
      if (!widget.records.isCurrent(sessionContext)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.fieldRecordSavedPreviousContext)),
        );
        return;
      }
      _observation.clear();
      _sireReference.clear();
      _selectedCattle = null;
      _earTag.clear();
      _occurredAt = DateTime.now();
      setState(() => _contextChanged = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.fieldRecordSaved)));
    } on FieldRecordFailure catch (failure) {
      if (!mounted) return;
      final message = switch (failure.code) {
        FieldRecordFailureCode.contextUnavailable =>
          strings.fieldRecordContextUnavailable,
        FieldRecordFailureCode.permissionRequired =>
          strings.fieldRecordPermissionRequired,
        FieldRecordFailureCode.operationInProgress =>
          strings.fieldRecordSaveInProgress,
        FieldRecordFailureCode.invalidRecord => strings.fieldRecordInvalid,
        FieldRecordFailureCode.storageUnavailable =>
          strings.fieldRecordStorageError,
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  void dispose() {
    widget.records.removeListener(_onRecordServiceChanged);
    _earTag.dispose();
    _observation.dispose();
    _sireReference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.records,
    builder: (context, _) {
      final strings = AppLocalizations.of(context);
      final theme = Theme.of(context);
      final currentContext = widget.records.context;
      final isLoading = widget.records.status == FieldRecordLoadStatus.loading;
      return PublicShell(
        language: widget.language,
        showBackButton: true,
        onBack: widget.onBack,
        backLabel: strings.fieldRecordBack,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                strings.fieldRecordTitle,
                style: theme.textTheme.headlineLarge,
              ),
            ),
            const SizedBox(height: 8),
            Text(strings.fieldRecordLead),
            const SizedBox(height: 20),
            if (_contextChanged) ...[
              _notice(context, strings.fieldRecordDraftCleared),
              const SizedBox(height: 16),
            ],
            if (currentContext == null) ...[
              _notice(context, strings.fieldRecordContextUnavailable),
              const SizedBox(height: 16),
            ] else ...[
              Text(
                currentContext.ranchName,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              if (isLoading)
                const Center(child: CircularProgressIndicator())
              else if (widget.records.status ==
                  FieldRecordLoadStatus.unavailable)
                _storageFailure(strings)
              else ...[
                if (widget.records.error != null) ...[
                  _notice(context, strings.fieldRecordStorageError),
                  const SizedBox(height: 8),
                  _retryStorage(strings),
                  const SizedBox(height: 12),
                ],
                _buildForm(strings),
                const SizedBox(height: 24),
                _buildPendingRecords(strings, theme),
              ],
            ],
          ],
        ),
      );
    },
  );

  Widget _buildForm(AppLocalizations strings) {
    final theme = Theme.of(context);
    final canCreate = widget.records.canCreate;
    final dateLabel = DateFormat.yMMMd(
      strings.localeName,
    ).add_Hm().format(_occurredAt.toLocal());
    final cattleChoices = widget.records.cattleOptions;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.fieldRecordCreateTitle,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (widget.records.context?.canManage != true) ...[
            _notice(context, strings.fieldRecordPermissionRequired),
            const SizedBox(height: 12),
          ],
          TextFormField(
            key: const Key('field-record-cattle-tag'),
            controller: _earTag,
            enabled: canCreate && !_findingCattle,
            textInputAction: TextInputAction.search,
            maxLength: FieldRecord.maximumCattleEarTagLength,
            decoration: InputDecoration(
              labelText: strings.fieldRecordCattleTag,
              helperText: strings.fieldRecordCattleTagHelp,
              errorText: _cattleError,
              suffixIcon: IconButton(
                tooltip: strings.fieldRecordFindCattle,
                onPressed: canCreate && !_findingCattle ? _findCattle : null,
                icon: _findingCattle
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
              ),
            ),
            onFieldSubmitted: (_) => unawaited(_findCattle()),
            onChanged: (_) => setState(() {
              _selectedCattle = null;
              _cattleError = null;
              _contextChanged = false;
            }),
          ),
          if (_selectedCattle != null) ...[
            const SizedBox(height: 4),
            Semantics(
              label: strings.fieldRecordSelectedCattle(_selectedCattle!.earTag),
              child: Chip(
                avatar: const Icon(Icons.pets, size: 18),
                label: Text(
                  strings.fieldRecordSelectedCattle(_selectedCattle!.earTag),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ] else if (cattleChoices.isEmpty && !_findingCattle) ...[
            const SizedBox(height: 4),
            Text(strings.fieldRecordCattleOfflineHelp),
            const SizedBox(height: 8),
          ],
          DropdownButtonFormField<FieldRecordType>(
            initialValue: _type,
            isExpanded: true,
            decoration: InputDecoration(labelText: strings.fieldRecordType),
            items: FieldRecordType.values
                .map(
                  (type) => DropdownMenuItem<FieldRecordType>(
                    value: type,
                    child: Text(_typeLabel(strings, type)),
                  ),
                )
                .toList(growable: false),
            onChanged: canCreate
                ? (type) => setState(() {
                    if (type != null) _type = type;
                    if (_type != FieldRecordType.naturalMating) {
                      _sireReference.clear();
                    }
                    _contextChanged = false;
                  })
                : null,
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(strings.fieldRecordOccurredAt),
            subtitle: Text(dateLabel),
            trailing: const Icon(Icons.calendar_month),
            onTap: canCreate ? _chooseOccurredAt : null,
          ),
          if (_type == FieldRecordType.naturalMating) ...[
            TextFormField(
              controller: _sireReference,
              enabled: canCreate,
              maxLength: FieldRecord.maximumSireReferenceLength,
              decoration: InputDecoration(
                labelText: strings.fieldRecordSireReference,
              ),
              onChanged: (_) => setState(() => _contextChanged = false),
            ),
          ],
          TextFormField(
            key: const Key('field-record-observation'),
            controller: _observation,
            enabled: canCreate,
            maxLength: FieldRecord.maximumObservationLength,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: strings.fieldRecordObservation,
              alignLabelWithHint: true,
            ),
            onChanged: (_) => setState(() => _contextChanged = false),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('field-record-save'),
            onPressed: canCreate && _selectedCattle != null ? _save : null,
            icon: const Icon(Icons.save_outlined),
            label: Text(
              widget.records.saving
                  ? strings.fieldRecordSaving
                  : strings.fieldRecordSave,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingRecords(AppLocalizations strings, ThemeData theme) {
    final records = widget.records.records;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.fieldRecordPendingTitle,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(strings.fieldRecordPendingLead),
        const SizedBox(height: 8),
        if (records.isEmpty)
          Text(strings.fieldRecordEmpty)
        else
          ...records.map((record) {
            final occurredAt = DateFormat.yMMMd(
              strings.localeName,
            ).add_Hm().format(record.occurredAt.toLocal());
            return Card(
              child: ListTile(
                leading: const Icon(Icons.cloud_off_outlined),
                title: Text(
                  '${_typeLabel(strings, record.type)} · ${record.cattleEarTag}',
                ),
                subtitle: Text(
                  record.observation == null
                      ? strings.fieldRecordPendingAt(occurredAt)
                      : '${strings.fieldRecordPendingAt(occurredAt)}\n${record.observation}',
                ),
                isThreeLine: record.observation != null,
              ),
            );
          }),
      ],
    );
  }

  Widget _storageFailure(AppLocalizations strings) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _notice(context, strings.fieldRecordStorageError),
      const SizedBox(height: 8),
      _retryStorage(strings),
    ],
  );

  Widget _retryStorage(AppLocalizations strings) => OutlinedButton.icon(
    onPressed: widget.records.status == FieldRecordLoadStatus.loading
        ? null
        : () => unawaited(widget.records.load()),
    icon: const Icon(Icons.refresh),
    label: Text(strings.fieldRecordRetry),
  );

  Widget _notice(BuildContext context, String message) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(message),
  );

  String _typeLabel(AppLocalizations strings, FieldRecordType type) =>
      switch (type) {
        FieldRecordType.healthEvent => strings.fieldRecordTypeHealthEvent,
        FieldRecordType.birth => strings.fieldRecordTypeBirth,
        FieldRecordType.naturalMating => strings.fieldRecordTypeNaturalMating,
        FieldRecordType.abortion => strings.fieldRecordTypeAbortion,
        FieldRecordType.heatObserved => strings.fieldRecordTypeHeatObserved,
      };
}
