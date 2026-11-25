import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../iam/application/facades/authorized_ranch_session.dart';
import '../../domain/model/field_record.dart';
import '../../domain/model/field_record_sync.dart';
import '../../domain/repositories/field_record_repository.dart';
import '../../domain/repositories/field_record_sync_repository.dart';

enum FieldRecordLoadStatus { idle, loading, ready, unavailable }

enum FieldRecordFailureCode {
  contextUnavailable,
  permissionRequired,
  operationInProgress,
  invalidRecord,
  storageUnavailable,
}

final class FieldRecordFailure implements Exception {
  const FieldRecordFailure(this.code);

  final FieldRecordFailureCode code;
}

/// Coordinates an account- and ranch-scoped offline queue without discarding it
/// when the authorized context changes.
final class FieldRecordService extends ChangeNotifier {
  FieldRecordService({
    required AuthorizedRanchSession access,
    required this.repository,
    this.syncRepository,
  }) : _access = access,
       _observedContext = access.context,
       _requestContext = access.context {
    _access.addListener(_onAccessChanged);
  }

  final AuthorizedRanchSession _access;
  final FieldRecordRepository repository;
  final FieldRecordSyncRepository? syncRepository;
  AuthorizedRanchContext? _observedContext;
  AuthorizedRanchContext? _requestContext;
  List<FieldRecord> _records = const <FieldRecord>[];
  List<FieldCattleOption> _cattleOptions = const <FieldCattleOption>[];
  FieldRecordLoadStatus _status = FieldRecordLoadStatus.idle;
  FieldRecordFailure? _error;
  Future<bool>? _pendingLoad;
  int _generation = 0;
  int _revision = 0;
  bool _saving = false;
  bool _disposed = false;
  Future<bool>? _pendingSync;
  AuthorizedRanchContext? _syncContext;
  FieldRecordSyncFailure? _syncError;
  List<FieldRecordSyncResult> _syncIssues = const [];
  int? _lastSyncConfirmed;

  AuthorizedRanchContext? get context => _visible ? _requestContext : null;
  FieldRecordLoadStatus get status =>
      _visible ? _status : FieldRecordLoadStatus.idle;
  List<FieldRecord> get records => _visible ? _records : const <FieldRecord>[];
  List<FieldCattleOption> get cattleOptions =>
      _visible ? _cattleOptions : const <FieldCattleOption>[];
  FieldRecordFailure? get error => _visible ? _error : null;
  bool get saving => _visible && _saving;
  bool get canCreate =>
      _visible &&
      _requestContext!.canManage &&
      _status == FieldRecordLoadStatus.ready &&
      _error == null &&
      !_saving;
  int get revision => _revision;
  bool get synchronizing => _visible && _pendingSync != null;
  bool get canSynchronize =>
      canCreate &&
      syncRepository?.isConfigured == true &&
      _records.isNotEmpty &&
      _pendingSync == null;
  FieldRecordSyncFailure? get syncError => _visible ? _syncError : null;
  List<FieldRecordSyncResult> get syncIssues =>
      _visible ? _syncIssues : const [];
  int? get lastSyncConfirmed => _visible ? _lastSyncConfirmed : null;

  /// Synchronizes a fixed snapshot on explicit intent. New captures wait for the
  /// next request; uncertain deliveries retain their original identifiers.
  Future<bool> synchronize() {
    if (_pendingSync != null) {
      return identical(context, _syncContext)
          ? _pendingSync!
          : Future.value(false);
    }
    if (!canSynchronize) return Future.value(false);
    final current = context!;
    final generation = _generation;
    final snapshot = List<FieldRecord>.unmodifiable(_records);
    _syncContext = current;
    _syncError = null;
    _lastSyncConfirmed = 0;
    final pending = Future<bool>.microtask(
      () => _performSync(current, generation, snapshot),
    );
    _pendingSync = pending;
    notifyListeners();
    return pending;
  }

  Future<bool> _performSync(
    AuthorizedRanchContext current,
    int generation,
    List<FieldRecord> snapshot,
  ) async {
    try {
      for (
        var offset = 0;
        offset < snapshot.length;
        offset += FieldRecordSyncRepository.batchSize
      ) {
        if (!_isCurrent(current, generation)) return false;
        final batch = snapshot
            .skip(offset)
            .take(FieldRecordSyncRepository.batchSize)
            .toList(growable: false);
        final results = await syncRepository!.synchronize(
          accountId: current.accountId,
          ranchId: current.ranchId,
          records: batch,
        );
        if (!_isCurrent(current, generation)) return false;
        validateFieldRecordSyncResults(batch, results);
        try {
          await repository.applySyncResults(
            accountId: current.accountId,
            ranchId: current.ranchId,
            submitted: batch,
            results: results,
          );
        } catch (_) {
          throw const FieldRecordSyncFailure(
            FieldRecordSyncFailureCode.storageUnavailable,
          );
        }
        if (!_isCurrent(current, generation)) return false;
        final confirmed = results
            .where((result) => result.confirmed)
            .map((result) => result.operationId.toLowerCase())
            .toSet();
        _records = List<FieldRecord>.unmodifiable(
          _records.where((record) => !confirmed.contains(record.operationId)),
        );
        final issues = {
          for (final issue in _syncIssues) issue.operationId: issue,
        };
        for (final result in results) {
          final id = result.operationId.toLowerCase();
          if (result.confirmed) {
            issues.remove(id);
          } else {
            issues[id] = result;
          }
        }
        _syncIssues = List<FieldRecordSyncResult>.unmodifiable(issues.values);
        _lastSyncConfirmed = (_lastSyncConfirmed ?? 0) + confirmed.length;
        notifyListeners();
      }
      return true;
    } on FieldRecordSyncFailure catch (failure) {
      if (_isCurrent(current, generation)) _syncError = failure;
      return false;
    } catch (_) {
      if (_isCurrent(current, generation)) {
        _syncError = const FieldRecordSyncFailure(
          FieldRecordSyncFailureCode.unknown,
        );
      }
      return false;
    } finally {
      _pendingSync = null;
      _syncContext = null;
      if (!_disposed) {
        if (_status == FieldRecordLoadStatus.idle && context != null) {
          unawaited(load());
        } else {
          notifyListeners();
        }
      }
    }
  }

  Future<bool> load() {
    if (_disposed) return Future<bool>.value(false);
    if (_pendingSync != null) return Future<bool>.value(false);
    final context = _access.context;
    if (context == null) {
      _beginUnavailable(
        const FieldRecordFailure(FieldRecordFailureCode.contextUnavailable),
      );
      return Future<bool>.value(false);
    }
    if (_pendingLoad != null && identical(_requestContext, context)) {
      return _pendingLoad!;
    }

    final generation = ++_generation;
    _requestContext = context;
    _records = const <FieldRecord>[];
    _cattleOptions = const <FieldCattleOption>[];
    _error = null;
    _status = FieldRecordLoadStatus.loading;
    final future = Future<bool>.microtask(
      () => _performLoad(context, generation),
    );
    _pendingLoad = future;
    notifyListeners();
    return future;
  }

  Future<void> save({
    required String cattleId,
    required String cattleEarTag,
    required FieldRecordType type,
    required DateTime occurredAt,
    String? observation,
    String? sireReference,
  }) async {
    final context = _access.context;
    if (_disposed || context == null || !_access.isCurrent(context)) {
      throw const FieldRecordFailure(FieldRecordFailureCode.contextUnavailable);
    }
    if (!context.canManage) {
      throw const FieldRecordFailure(FieldRecordFailureCode.permissionRequired);
    }
    if (_status != FieldRecordLoadStatus.ready || !_visible) {
      throw const FieldRecordFailure(FieldRecordFailureCode.contextUnavailable);
    }
    if (_saving) {
      throw const FieldRecordFailure(
        FieldRecordFailureCode.operationInProgress,
      );
    }
    final cattleChoice = _cattleOptions.where(
      (option) =>
          _sameId(option.cattleId, cattleId) &&
          option.earTag == cattleEarTag &&
          _sameId(option.ranchId, context.ranchId),
    );
    if (cattleChoice.length != 1) {
      throw const FieldRecordFailure(FieldRecordFailureCode.invalidRecord);
    }
    if (occurredAt.isAfter(
      DateTime.now().add(FieldRecord.maximumFutureOccurrenceOffset),
    )) {
      throw const FieldRecordFailure(FieldRecordFailureCode.invalidRecord);
    }

    late final FieldRecord record;
    try {
      record = FieldRecord(
        operationId: FieldRecord.newOperationId(),
        ranchId: context.ranchId,
        cattleId: cattleId,
        cattleEarTag: cattleEarTag,
        type: type,
        occurredAt: occurredAt,
        observation: observation,
        sireReference: sireReference,
      );
    } on ArgumentError {
      throw const FieldRecordFailure(FieldRecordFailureCode.invalidRecord);
    }

    _saving = true;
    notifyListeners();
    try {
      await repository.appendPending(
        accountId: context.accountId,
        ranchId: context.ranchId,
        record: record,
      );
      if (!_isCurrent(context, _generation)) return;
      _records = List<FieldRecord>.unmodifiable(<FieldRecord>[
        record,
        ..._records,
      ]);
      _status = FieldRecordLoadStatus.ready;
      _error = null;
    } catch (_) {
      if (_isCurrent(context, _generation)) {
        _error = const FieldRecordFailure(
          FieldRecordFailureCode.storageUnavailable,
        );
      }
      throw const FieldRecordFailure(FieldRecordFailureCode.storageUnavailable);
    } finally {
      if (_isCurrent(context, _generation)) {
        _saving = false;
        notifyListeners();
      }
    }
  }

  Future<void> cacheCattleOptions(List<FieldCattleOption> options) async {
    final context = _access.context;
    if (context == null || !_access.isCurrent(context) || options.isEmpty) {
      return;
    }
    final valid = options
        .where((option) => _sameId(option.ranchId, context.ranchId))
        .toList(growable: false);
    if (valid.isEmpty) return;
    try {
      await repository.cacheCattleOptions(
        accountId: context.accountId,
        ranchId: context.ranchId,
        options: valid,
      );
      if (!_isCurrent(context, _generation)) return;
      final byId = <String, FieldCattleOption>{
        for (final option in _cattleOptions)
          option.cattleId.toLowerCase(): option,
        for (final option in valid) option.cattleId.toLowerCase(): option,
      };
      _cattleOptions = List<FieldCattleOption>.unmodifiable(byId.values);
      notifyListeners();
    } catch (_) {
      if (_isCurrent(context, _generation)) {
        _error = const FieldRecordFailure(
          FieldRecordFailureCode.storageUnavailable,
        );
        notifyListeners();
      }
    }
  }

  bool isCurrent(AuthorizedRanchContext context) =>
      !_disposed && _access.isCurrent(context);

  Future<bool> _performLoad(
    AuthorizedRanchContext context,
    int generation,
  ) async {
    try {
      final records = await repository.readPending(
        accountId: context.accountId,
        ranchId: context.ranchId,
      );
      final cattleOptions = await repository.readCattleOptions(
        accountId: context.accountId,
        ranchId: context.ranchId,
      );
      final issues = await repository.readSyncIssues(
        accountId: context.accountId,
        ranchId: context.ranchId,
      );
      if (!_isCurrent(context, generation)) return false;
      if (records.any((record) => !_sameId(record.ranchId, context.ranchId)) ||
          cattleOptions.any(
            (option) => !_sameId(option.ranchId, context.ranchId),
          )) {
        throw const FieldRecordFailure(
          FieldRecordFailureCode.storageUnavailable,
        );
      }
      _records = List<FieldRecord>.unmodifiable(records);
      _syncIssues = List<FieldRecordSyncResult>.unmodifiable(issues);
      final optionsById = <String, FieldCattleOption>{
        for (final option in _cattleOptions)
          option.cattleId.toLowerCase(): option,
        for (final option in cattleOptions)
          option.cattleId.toLowerCase(): option,
      };
      _cattleOptions = List<FieldCattleOption>.unmodifiable(optionsById.values);
      _error = null;
      _status = FieldRecordLoadStatus.ready;
      notifyListeners();
      return true;
    } catch (_) {
      if (!_isCurrent(context, generation)) return false;
      _records = const <FieldRecord>[];
      _cattleOptions = const <FieldCattleOption>[];
      _error = const FieldRecordFailure(
        FieldRecordFailureCode.storageUnavailable,
      );
      _status = FieldRecordLoadStatus.unavailable;
      notifyListeners();
      return false;
    } finally {
      if (_generation == generation) _pendingLoad = null;
    }
  }

  bool get _visible =>
      !_disposed &&
      _requestContext != null &&
      _access.isCurrent(_requestContext!) &&
      identical(_access.context, _requestContext);

  bool _isCurrent(AuthorizedRanchContext context, int generation) =>
      !_disposed &&
      generation == _generation &&
      identical(_requestContext, context) &&
      _access.isCurrent(context);

  bool _sameId(String left, String right) =>
      left.toLowerCase() == right.toLowerCase();

  void _onAccessChanged() {
    if (_disposed) return;
    final next = _access.context;
    if (identical(next, _observedContext)) return;
    _observedContext = next;
    ++_generation;
    _requestContext = next;
    _records = const <FieldRecord>[];
    _cattleOptions = const <FieldCattleOption>[];
    _error = null;
    _status = FieldRecordLoadStatus.idle;
    _pendingLoad = null;
    _saving = false;
    _revision++;
    _syncError = null;
    _syncIssues = const [];
    _lastSyncConfirmed = null;
    notifyListeners();
    if (next != null) unawaited(load());
  }

  void _beginUnavailable(FieldRecordFailure failure) {
    ++_generation;
    _requestContext = null;
    _records = const <FieldRecord>[];
    _cattleOptions = const <FieldCattleOption>[];
    _error = failure;
    _status = FieldRecordLoadStatus.unavailable;
    _pendingLoad = null;
    _saving = false;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    _access.removeListener(_onAccessChanged);
    _requestContext = null;
    _records = const <FieldRecord>[];
    _cattleOptions = const <FieldCattleOption>[];
    _pendingLoad = null;
    _saving = false;
    super.dispose();
  }
}
