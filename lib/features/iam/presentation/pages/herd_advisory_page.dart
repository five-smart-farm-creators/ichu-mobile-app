import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/layout/public_shell.dart';
import '../../../../shared/application/services/language_service.dart';
import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';
import '../../application/services/herd_advisory_service.dart';
import '../../application/services/ranch_selection_service.dart';
import '../../domain/model/herd_advisory.dart';
import '../../domain/model/herd_advisory_failure.dart';
import '../../domain/model/iam_account.dart';
import '../../domain/model/ranch_access.dart';
import '../../domain/model/ranch_summary.dart';

final class HerdAdvisoryPage extends StatefulWidget {
  const HerdAdvisoryPage({
    super.key,
    required this.language,
    required this.service,
    required this.selection,
    required this.onBack,
  });

  final LanguageService language;
  final HerdAdvisoryService service;
  final RanchSelectionService selection;
  final VoidCallback onBack;

  @override
  State<HerdAdvisoryPage> createState() => _HerdAdvisoryPageState();
}

final class _HerdAdvisoryPageState extends State<HerdAdvisoryPage> {
  final TextEditingController _accessCode = TextEditingController();
  final TextEditingController _reason = TextEditingController();
  final TextEditingController _veterinarianId = TextEditingController();
  RanchSummary? _foundRanch;
  HerdAdvisory? _submittedRequest;
  List<HerdAdvisory> _advisories = const <HerdAdvisory>[];
  HerdAdvisoryFailure? _requestFailure;
  HerdAdvisoryFailure? _historyFailure;
  DateTime? _directGrantExpiry;
  AccessScope? _directGrantScope;
  _LoadStatus _historyStatus = _LoadStatus.idle;
  bool _lookingUp = false;
  bool _submittingRequest = false;
  bool _submittingDirectGrant = false;
  bool _actionInProgress = false;
  int _historyGeneration = 0;

  @override
  void initState() {
    super.initState();
    widget.selection.addListener(_onSelectionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadAdvisories());
    });
  }

  @override
  void didUpdateWidget(covariant HerdAdvisoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selection != widget.selection) {
      oldWidget.selection.removeListener(_onSelectionChanged);
      widget.selection.addListener(_onSelectionChanged);
      unawaited(_loadAdvisories());
    }
  }

  @override
  void dispose() {
    widget.selection.removeListener(_onSelectionChanged);
    _accessCode.dispose();
    _reason.dispose();
    _veterinarianId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final selected = widget.selection.selectedRanch;
    return PublicShell(
      language: widget.language,
      showBackButton: true,
      onBack: widget.onBack,
      backLabel: strings.iamAdvisoryBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              strings.iamAdvisoryTitle,
              style: theme.textTheme.headlineLarge,
            ),
          ),
          const SizedBox(height: 8),
          Text(strings.iamAdvisoryLead),
          const SizedBox(height: 24),
          if (widget.selection.accountRole == AccountRole.veterinarian) ...[
            _buildRequestSection(context, strings, theme),
            const SizedBox(height: 28),
          ],
          _buildHistorySection(context, strings, theme, selected),
        ],
      ),
    );
  }

  Widget _buildRequestSection(
    BuildContext context,
    AppLocalizations strings,
    ThemeData theme,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.iamAdvisoryRequestTitle,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(strings.iamAdvisoryRequestLead),
          const SizedBox(height: 16),
          TextField(
            key: const Key('advisory-access-code'),
            controller: _accessCode,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            enabled: !_lookingUp && !_submittingRequest,
            onChanged: _onAccessCodeChanged,
            decoration: InputDecoration(
              labelText: strings.iamAdvisoryAccessCode,
              helperText: strings.iamAdvisoryAccessCodeHelp,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('advisory-lookup'),
            onPressed: _lookingUp || _submittingRequest ? null : _lookupRanch,
            icon: _lookingUp
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            label: Text(
              _lookingUp
                  ? strings.iamAdvisoryLookingUp
                  : strings.iamAdvisoryLookup,
            ),
          ),
          if (_requestFailure != null)
            _failureNotice(_requestFailure!, strings),
          if (_foundRanch case final ranch?) ...[
            const SizedBox(height: 16),
            _RanchSummaryCard(ranch: ranch, strings: strings),
            const SizedBox(height: 16),
            TextField(
              key: const Key('advisory-request-reason'),
              controller: _reason,
              enabled: !_submittingRequest,
              minLines: 3,
              maxLines: 5,
              maxLength: 1000,
              decoration: InputDecoration(
                labelText: strings.iamAdvisoryReason,
                alignLabelWithHint: true,
              ),
            ),
            FilledButton.icon(
              key: const Key('advisory-submit-request'),
              onPressed: _submittingRequest || _lookingUp
                  ? null
                  : _submitRequest,
              icon: _submittingRequest
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: Text(
                _submittingRequest
                    ? strings.iamAdvisorySubmitting
                    : strings.iamAdvisorySubmitRequest,
              ),
            ),
          ],
          if (_submittedRequest case final advisory?) ...[
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Text(strings.iamAdvisoryRequestSubmitted),
            ),
            _AdvisoryStatusLine(advisory: advisory, strings: strings),
          ],
        ],
      ),
    ),
  );

  Widget _buildHistorySection(
    BuildContext context,
    AppLocalizations strings,
    ThemeData theme,
    RanchAccess? selected,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(strings.iamAdvisoryHistoryTitle, style: theme.textTheme.titleLarge),
      const SizedBox(height: 8),
      if (selected == null)
        Text(strings.iamAdvisoryChooseRanch)
      else ...[
        Text(strings.iamAdvisorySelectedRanch(selected.name)),
        const SizedBox(height: 12),
        if (selected.scope == AccessScope.manage)
          _buildDirectGrantForm(strings, theme),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('advisory-history-refresh'),
            onPressed: _historyStatus == _LoadStatus.loading
                ? null
                : _loadAdvisories,
            icon: const Icon(Icons.refresh),
            label: Text(strings.iamAdvisoryReload),
          ),
        ),
        if (_historyStatus == _LoadStatus.loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_historyFailure case final failure?)
          _failureNotice(failure, strings)
        else if (_historyStatus == _LoadStatus.ready && _advisories.isEmpty)
          Text(strings.iamAdvisoryEmpty)
        else
          for (final advisory in _advisories) ...[
            _AdvisoryCard(
              advisory: advisory,
              strings: strings,
              canManage: selected.scope == AccessScope.manage,
              actionInProgress: _actionInProgress,
              onGrant: (scope) => _grant(advisory, scope),
              onReject: () => _end(advisory, HerdAdvisoryDecision.reject),
              onRevoke: () => _end(advisory, HerdAdvisoryDecision.revoke),
            ),
            const SizedBox(height: 12),
          ],
      ],
    ],
  );

  Widget _buildDirectGrantForm(AppLocalizations strings, ThemeData theme) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.iamAdvisoryDirectGrantTitle,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(strings.iamAdvisoryDirectGrantLead),
              const SizedBox(height: 16),
              TextField(
                key: const Key('advisory-veterinarian-id'),
                controller: _veterinarianId,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: strings.iamAdvisoryVeterinarianId,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AccessScope>(
                key: const Key('advisory-direct-scope'),
                initialValue: _directGrantScope,
                decoration: InputDecoration(
                  labelText: strings.iamAdvisoryScope,
                ),
                items: [
                  DropdownMenuItem(
                    value: AccessScope.read,
                    child: Text(strings.iamRanchScopeRead),
                  ),
                  DropdownMenuItem(
                    value: AccessScope.clinicalWrite,
                    child: Text(strings.iamRanchScopeClinicalWrite),
                  ),
                ],
                onChanged: _submittingDirectGrant
                    ? null
                    : (scope) => setState(() => _directGrantScope = scope),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('advisory-direct-expiry'),
                onPressed: _submittingDirectGrant ? null : _selectDirectExpiry,
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  _directGrantExpiry == null
                      ? strings.iamAdvisorySelectExpiry
                      : strings.iamAdvisoryExpiresOn(
                          _formatDate(context, _directGrantExpiry!),
                        ),
                ),
              ),
              FilledButton.icon(
                key: const Key('advisory-direct-grant'),
                onPressed:
                    _submittingDirectGrant ||
                        _directGrantScope == null ||
                        _directGrantExpiry == null ||
                        _veterinarianId.text.trim().isEmpty
                    ? null
                    : _submitDirectGrant,
                icon: _submittingDirectGrant
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add_alt_1_outlined),
                label: Text(
                  _submittingDirectGrant
                      ? strings.iamAdvisorySubmitting
                      : strings.iamAdvisorySubmitDirectGrant,
                ),
              ),
            ],
          ),
        ),
      );

  Future<void> _lookupRanch() async {
    setState(() {
      _lookingUp = true;
      _requestFailure = null;
      _foundRanch = null;
      _submittedRequest = null;
    });
    try {
      final ranch = await widget.service.findRanchByAccessCode(
        _accessCode.text,
      );
      if (!mounted) return;
      setState(() => _foundRanch = ranch);
    } on HerdAdvisoryFailure catch (failure) {
      if (!mounted) return;
      setState(() => _requestFailure = failure);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _requestFailure = const HerdAdvisoryFailure(
          HerdAdvisoryFailureCode.unknown,
        ),
      );
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  void _onAccessCodeChanged(String _) {
    if (_foundRanch == null && _submittedRequest == null) return;
    setState(() {
      _foundRanch = null;
      _submittedRequest = null;
      _requestFailure = null;
    });
  }

  Future<void> _submitRequest() async {
    final ranch = _foundRanch;
    if (ranch == null) return;
    setState(() {
      _submittingRequest = true;
      _requestFailure = null;
      _submittedRequest = null;
    });
    try {
      final advisory = await widget.service.requestAccess(
        ranchId: ranch.ranchId,
        reason: _reason.text,
      );
      if (!mounted) return;
      setState(() => _submittedRequest = advisory);
    } on HerdAdvisoryFailure catch (failure) {
      if (!mounted) return;
      setState(() => _requestFailure = failure);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _requestFailure = const HerdAdvisoryFailure(
          HerdAdvisoryFailureCode.unknown,
        ),
      );
    } finally {
      if (mounted) setState(() => _submittingRequest = false);
    }
  }

  Future<void> _loadAdvisories() async {
    final ranch = widget.selection.selectedRanch;
    final generation = ++_historyGeneration;
    if (ranch == null) {
      if (!mounted) return;
      setState(() {
        _historyStatus = _LoadStatus.idle;
        _historyFailure = null;
        _advisories = const <HerdAdvisory>[];
      });
      return;
    }
    setState(() {
      _historyStatus = _LoadStatus.loading;
      _historyFailure = null;
      _advisories = const <HerdAdvisory>[];
    });
    try {
      final advisories = await widget.service.advisoriesForSelectedRanch();
      if (!mounted || generation != _historyGeneration) return;
      setState(() {
        _advisories = advisories;
        _historyStatus = _LoadStatus.ready;
      });
    } on HerdAdvisoryFailure catch (failure) {
      if (!mounted || generation != _historyGeneration) return;
      setState(() {
        _historyFailure = failure;
        _historyStatus = _LoadStatus.unavailable;
      });
    } catch (_) {
      if (!mounted || generation != _historyGeneration) return;
      setState(() {
        _historyFailure = const HerdAdvisoryFailure(
          HerdAdvisoryFailureCode.unknown,
        );
        _historyStatus = _LoadStatus.unavailable;
      });
    }
  }

  Future<void> _grant(HerdAdvisory advisory, AccessScope scope) async {
    final strings = AppLocalizations.of(context);
    final selectedDate = await _pickDate(
      initialDate: null,
      helpText: strings.iamAdvisorySelectExpiry,
    );
    if (selectedDate == null || !mounted) return;
    final expiresAt = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      23,
      59,
      59,
    );
    await _writeAction(
      () => widget.service.decideForSelectedRanch(
        advisoryId: advisory.id,
        decision: HerdAdvisoryDecision.grant,
        scope: scope,
        expiresAt: expiresAt,
      ),
    );
  }

  Future<void> _end(
    HerdAdvisory advisory,
    HerdAdvisoryDecision decision,
  ) async {
    final strings = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          decision == HerdAdvisoryDecision.reject
              ? strings.iamAdvisoryReject
              : strings.iamAdvisoryRevoke,
        ),
        content: Text(
          decision == HerdAdvisoryDecision.reject
              ? strings.iamAdvisoryConfirmReject
              : strings.iamAdvisoryConfirmRevoke,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.iamAdvisoryCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              decision == HerdAdvisoryDecision.reject
                  ? strings.iamAdvisoryReject
                  : strings.iamAdvisoryRevoke,
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _writeAction(
      () => widget.service.decideForSelectedRanch(
        advisoryId: advisory.id,
        decision: decision,
      ),
    );
  }

  Future<void> _submitDirectGrant() async {
    final scope = _directGrantScope;
    final date = _directGrantExpiry;
    if (scope == null || date == null) return;
    setState(() {
      _submittingDirectGrant = true;
      _historyFailure = null;
    });
    try {
      await widget.service.grantDirectly(
        veterinarianId: _veterinarianId.text.trim(),
        scope: scope,
        expiresAt: DateTime(date.year, date.month, date.day, 23, 59, 59),
      );
      if (!mounted) return;
      _veterinarianId.clear();
      setState(() {
        _directGrantScope = null;
        _directGrantExpiry = null;
      });
      await _loadAdvisories();
    } on HerdAdvisoryFailure catch (failure) {
      if (mounted) setState(() => _historyFailure = failure);
    } catch (_) {
      if (mounted) {
        setState(
          () => _historyFailure = const HerdAdvisoryFailure(
            HerdAdvisoryFailureCode.unknown,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submittingDirectGrant = false);
    }
  }

  Future<void> _writeAction(Future<HerdAdvisory> Function() operation) async {
    setState(() {
      _actionInProgress = true;
      _historyFailure = null;
    });
    try {
      await operation();
      if (mounted) await _loadAdvisories();
    } on HerdAdvisoryFailure catch (failure) {
      if (mounted) setState(() => _historyFailure = failure);
    } catch (_) {
      if (mounted) {
        setState(
          () => _historyFailure = const HerdAdvisoryFailure(
            HerdAdvisoryFailureCode.unknown,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _selectDirectExpiry() async {
    final strings = AppLocalizations.of(context);
    final date = await _pickDate(
      initialDate: _directGrantExpiry,
      helpText: strings.iamAdvisorySelectExpiry,
    );
    if (date != null && mounted) setState(() => _directGrantExpiry = date);
  }

  Future<DateTime?> _pickDate({
    required DateTime? initialDate,
    required String helpText,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = initialDate ?? today.add(const Duration(days: 1));
    return showDatePicker(
      context: context,
      initialDate: initial.isBefore(today) ? today : initial,
      firstDate: today,
      lastDate: DateTime(today.year + 10),
      helpText: helpText,
    );
  }

  void _onSelectionChanged() {
    if (!mounted) return;
    _veterinarianId.clear();
    setState(() {
      _directGrantScope = null;
      _directGrantExpiry = null;
    });
    unawaited(_loadAdvisories());
  }

  Widget _failureNotice(HerdAdvisoryFailure failure, AppLocalizations strings) {
    final message = switch (failure.code) {
      HerdAdvisoryFailureCode.configuration =>
        strings.iamAdvisoryErrorConfiguration,
      HerdAdvisoryFailureCode.contextUnavailable =>
        strings.iamAdvisoryChooseRanch,
      HerdAdvisoryFailureCode.invalidRequest => strings.iamAdvisoryErrorInvalid,
      HerdAdvisoryFailureCode.unauthenticated =>
        strings.iamAdvisoryErrorUnauthenticated,
      HerdAdvisoryFailureCode.forbidden => strings.iamAdvisoryErrorForbidden,
      HerdAdvisoryFailureCode.notFound => strings.iamAdvisoryErrorNotFound,
      HerdAdvisoryFailureCode.network => strings.iamAdvisoryErrorNetwork,
      HerdAdvisoryFailureCode.serviceUnavailable =>
        strings.iamAdvisoryErrorUnavailable,
      HerdAdvisoryFailureCode.invalidResponse =>
        strings.iamAdvisoryErrorResponse,
      HerdAdvisoryFailureCode.unknown => strings.iamAdvisoryErrorUnknown,
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

  String _formatDate(BuildContext context, DateTime date) =>
      MaterialLocalizations.of(context).formatMediumDate(date.toLocal());
}

final class _RanchSummaryCard extends StatelessWidget {
  const _RanchSummaryCard({required this.ranch, required this.strings});

  final RanchSummary ranch;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('advisory-found-ranch'),
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ranch.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('${ranch.region} · ${ranch.district}'),
          const SizedBox(height: 4),
          Text(strings.iamRanchIdentifier(ranch.ranchId)),
        ],
      ),
    ),
  );
}

final class _AdvisoryCard extends StatelessWidget {
  const _AdvisoryCard({
    required this.advisory,
    required this.strings,
    required this.canManage,
    required this.actionInProgress,
    required this.onGrant,
    required this.onReject,
    required this.onRevoke,
  });

  final HerdAdvisory advisory;
  final AppLocalizations strings;
  final bool canManage;
  final bool actionInProgress;
  final ValueChanged<AccessScope> onGrant;
  final VoidCallback onReject;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final profile = advisory.veterinarianProfile;
    return Card(
      key: ValueKey<String>('advisory-${advisory.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AdvisoryStatusLine(advisory: advisory, strings: strings),
            const SizedBox(height: 8),
            Text(strings.iamAdvisoryReason),
            Text(advisory.reason),
            const SizedBox(height: 8),
            Text(strings.iamAdvisoryVeterinarian),
            Text(
              profile == null
                  ? advisory.veterinarianId
                  : '${profile.specialty} · ${profile.licenseNumber}',
            ),
            if (advisory.expiresAt case final expiresAt?)
              Text(
                strings.iamAdvisoryExpiresOn(
                  MaterialLocalizations.of(
                    context,
                  ).formatMediumDate(expiresAt.toLocal()),
                ),
              ),
            if (canManage && advisory.status == HerdAdvisoryStatus.pending) ...[
              const SizedBox(height: 12),
              Text(strings.iamAdvisoryGrantScope),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: actionInProgress
                        ? null
                        : () => onGrant(AccessScope.read),
                    child: Text(strings.iamAdvisoryGrantRead),
                  ),
                  OutlinedButton(
                    onPressed: actionInProgress
                        ? null
                        : () => onGrant(AccessScope.clinicalWrite),
                    child: Text(strings.iamAdvisoryGrantClinicalWrite),
                  ),
                  TextButton(
                    onPressed: actionInProgress ? null : onReject,
                    child: Text(strings.iamAdvisoryReject),
                  ),
                ],
              ),
            ],
            if (canManage && advisory.status == HerdAdvisoryStatus.granted) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: actionInProgress ? null : onRevoke,
                child: Text(strings.iamAdvisoryRevoke),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final class _AdvisoryStatusLine extends StatelessWidget {
  const _AdvisoryStatusLine({required this.advisory, required this.strings});

  final HerdAdvisory advisory;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    final status = switch (advisory.status) {
      HerdAdvisoryStatus.pending => strings.iamAdvisoryStatusPending,
      HerdAdvisoryStatus.granted => strings.iamAdvisoryStatusGranted,
      HerdAdvisoryStatus.rejected => strings.iamAdvisoryStatusRejected,
      HerdAdvisoryStatus.revoked => strings.iamAdvisoryStatusRevoked,
      HerdAdvisoryStatus.expired => strings.iamAdvisoryStatusExpired,
    };
    final scope = switch (advisory.scope) {
      AccessScope.read => strings.iamRanchScopeRead,
      AccessScope.clinicalWrite => strings.iamRanchScopeClinicalWrite,
      AccessScope.manage => strings.iamAdvisoryScopeUnavailable,
    };
    return Text(
      '${strings.iamAdvisoryStatus}: $status · ${strings.iamAdvisoryScope}: $scope',
      style: Theme.of(context).textTheme.titleSmall,
    );
  }
}

enum _LoadStatus { idle, loading, ready, unavailable }
