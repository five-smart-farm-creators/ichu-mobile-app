import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/layout/public_shell.dart';
import '../../../../shared/application/services/language_service.dart';
import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';
import '../../application/services/cattle_management_service.dart';
import '../../application/services/cattle_read_service.dart';
import '../../domain/model/cattle.dart';
import '../../domain/model/cattle_search.dart';
import '../widgets/cattle_failure_notice.dart';
import '../widgets/cattle_labels.dart';
import 'cattle_details_form_page.dart';

final class CattleListPage extends StatefulWidget {
  const CattleListPage({
    super.key,
    required this.language,
    required this.service,
    required this.onBack,
    required this.onOpenRanches,
    required this.onOpenCattle,
    this.management,
  });

  final LanguageService language;
  final CattleReadService service;
  final VoidCallback onBack;
  final VoidCallback onOpenRanches;
  final ValueChanged<String> onOpenCattle;
  final CattleManagementService? management;

  @override
  State<CattleListPage> createState() => _CattleListPageState();
}

final class _CattleListPageState extends State<CattleListPage> {
  final _form = GlobalKey<FormState>();
  final _earTag = TextEditingController();
  CattleStatus? _status;
  int _revision = -1;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    _earTag.text = widget.service.query.earTag;
    _status = widget.service.query.status;
    _revision = widget.service.revision;
    widget.service.addListener(_onScopeChanged);
    final service = widget.service;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(widget.service, service)) return;
      if (service.hasContext && service.status != CattleLoadStatus.ready) {
        unawaited(service.load());
      }
    });
  }

  void _onScopeChanged() {
    if (!mounted || _revision == widget.service.revision) return;
    setState(() {
      _revision = widget.service.revision;
      _earTag.text = widget.service.query.earTag;
      _status = widget.service.query.status;
    });
  }

  @override
  void didUpdateWidget(covariant CattleListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      oldWidget.service.removeListener(_onScopeChanged);
      _bind();
    }
  }

  Future<void> _search() async {
    if (!widget.service.canLoad ||
        widget.service.status == CattleLoadStatus.loading ||
        !(_form.currentState?.validate() ?? false)) {
      return;
    }
    FocusScope.of(context).unfocus();
    await widget.service.load(
      query: CattleSearch(earTag: _earTag.text, status: _status),
    );
  }

  Future<void> _reset() async {
    _earTag.clear();
    setState(() => _status = null);
    _form.currentState?.reset();
    FocusScope.of(context).unfocus();
    await widget.service.load(query: const CattleSearch());
  }

  Future<void> _register(CattleManagementService management) async {
    final strings = AppLocalizations.of(context);
    final created = await Navigator.of(context).push<Cattle>(
      MaterialPageRoute<Cattle>(
        fullscreenDialog: true,
        builder: (_) => CattleDetailsFormPage(management: management),
      ),
    );
    if (!mounted) return;
    final reload = created != null || management.requiresReload;
    management.clearError();
    if (created != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.cattleManageRegistered)));
    }
    if (reload) unawaited(widget.service.load());
  }

  @override
  void dispose() {
    widget.service.removeListener(_onScopeChanged);
    _earTag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge(<Listenable>[
      widget.service,
      ?widget.management,
    ]),
    builder: (context, _) {
      final service = widget.service;
      final management = widget.management;
      final strings = AppLocalizations.of(context);
      final theme = Theme.of(context);
      final busy = service.status == CattleLoadStatus.loading;
      final draftChanged =
          _earTag.text.trim() != service.query.earTag ||
          _status != service.query.status;
      return PublicShell(
        language: widget.language,
        showBackButton: true,
        onBack: widget.onBack,
        backLabel: strings.cattleBackAccount,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                strings.cattleTitle,
                style: theme.textTheme.headlineLarge,
              ),
            ),
            const SizedBox(height: 12),
            Text(strings.cattleListLead),
            const SizedBox(height: 20),
            if (!service.hasContext) ...[
              Text(strings.cattleChooseRanch),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('cattle-choose-ranch'),
                onPressed: widget.onOpenRanches,
                child: Text(strings.iamOpenRanches),
              ),
            ] else ...[
              Text(service.ranchName ?? '', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              if (management != null && management.canManage) ...[
                FilledButton.icon(
                  key: const Key('cattle-manage-register'),
                  onPressed: () => unawaited(_register(management)),
                  icon: const Icon(Icons.add),
                  label: Text(strings.cattleManageRegister),
                ),
                const SizedBox(height: 16),
              ],
              Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      key: const Key('cattle-ear-tag'),
                      controller: _earTag,
                      enabled: !busy,
                      maxLength: 30,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.search,
                      onFieldSubmitted: (_) => _search(),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: strings.cattleExactEarTag,
                        errorMaxLines: 3,
                      ),
                      validator: (value) => (value ?? '').trim().length > 30
                          ? strings.cattleTagInvalid
                          : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<CattleStatus>(
                      key: ValueKey('cattle-status-$_status-$_revision'),
                      initialValue: _status,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: strings.cattleStatus,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(strings.cattleAllStatuses),
                        ),
                        for (final status in CattleStatus.values)
                          DropdownMenuItem(
                            value: status,
                            child: Text(CattleLabels.status(strings, status)),
                          ),
                      ],
                      onChanged: busy
                          ? null
                          : (value) => setState(() => _status = value),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const Key('cattle-search'),
                      onPressed: service.canLoad && !busy ? _search : null,
                      child: Text(strings.cattleSearch),
                    ),
                    TextButton(
                      key: const Key('cattle-reset'),
                      onPressed: service.canLoad && !busy ? _reset : null,
                      child: Text(strings.cattleReset),
                    ),
                  ],
                ),
              ),
              if (busy)
                Semantics(liveRegion: true, child: Text(strings.cattleLoading)),
              if (service.error case final error?)
                CattleFailureNotice(failure: error),
              if (service.status == CattleLoadStatus.ready) ...[
                const SizedBox(height: 12),
                Text(
                  strings.cattlePage(service.query.page),
                  style: theme.textTheme.titleMedium,
                ),
                if (service.animals.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(strings.cattleEmpty),
                  ),
                for (final animal in service.animals)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              animal.earTag,
                              style: theme.textTheme.titleLarge,
                            ),
                            Text(CattleLabels.breed(strings, animal.breed)),
                            Text(
                              '${CattleLabels.stage(strings, animal.currentStage)} · ${CattleLabels.status(strings, animal.status)}',
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              key: Key('cattle-open-${animal.id}'),
                              onPressed: () => widget.onOpenCattle(animal.id),
                              child: Text(strings.cattleView),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (service.canGoNext)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(strings.cattleMoreHint),
                  ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  TextButton.icon(
                    key: const Key('cattle-previous'),
                    onPressed: !draftChanged && service.canGoPrevious
                        ? () => unawaited(service.previousPage())
                        : null,
                    icon: const Icon(Icons.chevron_left),
                    label: Text(strings.cattlePrevious),
                  ),
                  TextButton.icon(
                    key: const Key('cattle-next'),
                    onPressed: !draftChanged && service.canGoNext
                        ? () => unawaited(service.nextPage())
                        : null,
                    icon: const Icon(Icons.chevron_right),
                    label: Text(strings.cattleNext),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    },
  );
}
