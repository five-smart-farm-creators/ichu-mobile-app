import 'package:flutter/foundation.dart';

import '../../../iam/application/facades/authorized_ranch_session.dart';
import '../../domain/model/cattle.dart';
import '../../domain/model/cattle_commands.dart';
import '../../domain/model/cattle_date.dart';
import '../../domain/model/cattle_failure.dart';
import '../../domain/repositories/cattle_command_repository.dart';

/// Runs one version-checked animal write at a time, fenced to the ranch context that started it.
final class CattleManagementService extends ChangeNotifier {
  CattleManagementService({
    required AuthorizedRanchSession access,
    required this._commands,
    this._clock = DateTime.now,
  }) : _access = access,
       _observedContext = access.context {
    _access.addListener(_onAccessChanged);
  }

  final AuthorizedRanchSession _access;
  final CattleCommandRepository _commands;
  final DateTime Function() _clock;
  AuthorizedRanchContext? _observedContext;
  AuthorizedRanchContext? _writeContext;
  bool _isSaving = false;
  CattleFailure? _error;
  int _generation = 0;
  bool _disposed = false;

  bool get canManage =>
      !_disposed &&
      _commands.isConfigured &&
      _access.context?.canManage == true;
  CattleDate get today => CattleDate.utcDateOf(_clock());
  bool get isSaving => _visible && _isSaving;
  CattleFailure? get error => _visible ? _error : null;

  /// After these failures the loaded snapshot is stale or the write may have been applied.
  bool get requiresReload => switch (error?.code) {
    CattleFailureCode.versionConflict ||
    CattleFailureCode.inactive ||
    CattleFailureCode.stageAlreadyCurrent ||
    CattleFailureCode.outcomeUnknown ||
    CattleFailureCode.invalidResponse => true,
    _ => false,
  };

  bool get _visible {
    final stored = _writeContext;
    return !_disposed && stored != null && _access.isCurrent(stored);
  }

  Future<Cattle?> register(CattleRegistration registration) => _write(
    issues: registration.issuesOn(today),
    send: (context) => _commands.register(context.ranchId, registration),
  );

  Future<Cattle?> correct(Cattle current, CattleCorrection correction) =>
      _write(
        current: current,
        issues: correction.issuesFor(current, today),
        send: (context) => _commands.correct(
          context.ranchId,
          current.id,
          current.version,
          correction,
        ),
      );

  Future<Cattle?> changeStage(Cattle current, CattleStageChange change) =>
      _write(
        current: current,
        issues: change.issuesFor(current, today),
        send: (context) => _commands.changeStage(
          context.ranchId,
          current.id,
          current.version,
          change,
        ),
      );

  Future<Cattle?> deactivate(Cattle current, CattleExit exit) => _write(
    current: current,
    issues: exit.issuesFor(current, today),
    send: (context) => _commands.deactivate(
      context.ranchId,
      current.id,
      current.version,
      exit,
    ),
  );

  void clearError() {
    if (_disposed || _error == null) return;
    _error = null;
    _notify();
  }

  Future<Cattle?> _write({
    Cattle? current,
    required Set<CattleInputIssue> issues,
    required Future<Cattle> Function(AuthorizedRanchContext context) send,
  }) async {
    if (_disposed || _isSaving) return null;
    final context = _access.context;
    if (context == null || !canManage) {
      _reject(context, CattleFailureCode.forbidden);
      return null;
    }
    if (current != null &&
        current.ranchId.toLowerCase() != context.ranchId.toLowerCase()) {
      _reject(context, CattleFailureCode.contextUnavailable);
      return null;
    }
    if (issues.isNotEmpty) {
      _reject(context, CattleFailureCode.invalidInput);
      return null;
    }

    final generation = ++_generation;
    _writeContext = context;
    _isSaving = true;
    _error = null;
    _notify();
    try {
      final cattle = await send(context);
      if (!_isCurrentWrite(context, generation)) return null;
      return cattle;
    } catch (error) {
      if (!_isCurrentWrite(context, generation)) return null;
      _error = error is CattleFailure
          ? error
          : const CattleFailure(CattleFailureCode.unknown);
      return null;
    } finally {
      // A grant can expire without a notification, so the flag is released here too.
      if (generation == _generation) {
        _isSaving = false;
        _notify();
      }
    }
  }

  void _reject(AuthorizedRanchContext? context, CattleFailureCode code) {
    _writeContext = context;
    _error = CattleFailure(code);
    _notify();
  }

  bool _isCurrentWrite(AuthorizedRanchContext context, int generation) =>
      !_disposed && generation == _generation && _access.isCurrent(context);

  void _onAccessChanged() {
    if (_disposed) return;
    final next = _access.context;
    if (identical(next, _observedContext)) return;
    _observedContext = next;
    _generation++;
    _isSaving = false;
    _writeContext = null;
    _error = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _access.removeListener(_onAccessChanged);
    super.dispose();
  }
}
