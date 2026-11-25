import 'package:flutter/foundation.dart';

import '../../../iam/application/facades/authorized_ranch_session.dart';
import '../../domain/model/monitoring_failure.dart';
import '../../domain/model/waterer.dart';
import '../../domain/model/water_history_query.dart';
import '../../domain/repositories/waterer_repository.dart';

enum WatererLoadStatus { idle, loading, ready, unavailable }

/// Online reads fenced by the exact IAM account, grant and ranch context.
final class WatererReadService extends ChangeNotifier {
  WatererReadService({required this.access, required this.waterers}) {
    _context = access.context;
    access.addListener(_onAccessChanged);
  }

  final AuthorizedRanchSession access;
  final WatererRepository waterers;
  AuthorizedRanchContext? _context;
  List<WatererStatus> _items = const [];
  WatererStatus? _detail;
  WaterHistoryPage? _history;
  WatererLoadStatus _listStatus = WatererLoadStatus.idle;
  WatererLoadStatus _detailStatus = WatererLoadStatus.idle;
  WatererLoadStatus _historyStatus = WatererLoadStatus.idle;
  MonitoringFailure? _listError;
  MonitoringFailure? _detailError;
  MonitoringFailure? _historyError;
  int _listGeneration = 0;
  int _detailGeneration = 0;
  int _historyGeneration = 0;
  int _revision = 0;
  bool _active = true;
  bool _disposed = false;

  bool get hasContext => !_disposed && _active && access.context != null;
  bool get _visible => hasContext && identical(access.context, _context);
  String? get ranchId => _visible ? _context?.ranchId : null;
  String? get ranchName => _visible ? _context?.ranchName : null;
  int get revision => _revision;
  List<WatererStatus> get items => _visible ? _items : const [];
  WatererStatus? get detail => _visible ? _detail : null;
  WaterHistoryPage? get history => _visible ? _history : null;
  WatererLoadStatus get listStatus =>
      _visible ? _listStatus : WatererLoadStatus.idle;
  WatererLoadStatus get detailStatus =>
      _visible ? _detailStatus : WatererLoadStatus.idle;
  WatererLoadStatus get historyStatus =>
      _visible ? _historyStatus : WatererLoadStatus.idle;
  MonitoringFailure? get listError => _visible ? _listError : null;
  MonitoringFailure? get detailError => _visible ? _detailError : null;
  MonitoringFailure? get historyError => _visible ? _historyError : null;

  Future<bool> loadList() async {
    final context = access.context;
    if (!hasContext || context == null) return false;
    final generation = ++_listGeneration;
    _items = const [];
    _listError = null;
    _listStatus = WatererLoadStatus.loading;
    notifyListeners();
    try {
      _requireConfiguration();
      final result = await waterers.list(context.ranchId);
      if (!_isCurrent(context) || generation != _listGeneration) return false;
      if (result
                  .map((item) => item.waterTroughId.toLowerCase())
                  .toSet()
                  .length !=
              result.length ||
          result.any((item) => !_belongsToRanch(item, context))) {
        throw const MonitoringFailure(MonitoringFailureCode.invalidResponse);
      }
      _items = List.unmodifiable(result);
      _listStatus = WatererLoadStatus.ready;
      notifyListeners();
      return true;
    } catch (error) {
      if (!_isCurrent(context) || generation != _listGeneration) return false;
      final failure = _failure(error);
      _clearOnConnectionFailure(failure);
      _listError = failure;
      _listStatus = WatererLoadStatus.unavailable;
      notifyListeners();
      return false;
    }
  }

  Future<bool> loadDetail(String waterTroughId) async {
    final context = access.context;
    if (!hasContext || context == null) return false;
    final generation = ++_detailGeneration;
    _detail = null;
    _detailError = null;
    _detailStatus = WatererLoadStatus.loading;
    _resetHistory();
    notifyListeners();
    try {
      _requireConfiguration();
      final result = await waterers.detail(context.ranchId, waterTroughId);
      if (!_isCurrent(context) || generation != _detailGeneration) return false;
      if (!_same(result.waterTroughId, waterTroughId) ||
          !_belongsToRanch(result, context)) {
        throw const MonitoringFailure(MonitoringFailureCode.invalidResponse);
      }
      _detail = result;
      _detailStatus = WatererLoadStatus.ready;
      notifyListeners();
      return true;
    } catch (error) {
      if (!_isCurrent(context) || generation != _detailGeneration) return false;
      final failure = _failure(error);
      _clearOnConnectionFailure(failure);
      _detailError = failure;
      _detailStatus = WatererLoadStatus.unavailable;
      notifyListeners();
      return false;
    }
  }

  Future<bool> loadHistory(WaterHistoryQuery query) async {
    final context = access.context;
    final status = detail;
    final controllerId = status?.controllerId;
    if (!hasContext || context == null || controllerId == null) return false;
    final generation = ++_historyGeneration;
    _history = null;
    _historyError = null;
    _historyStatus = WatererLoadStatus.loading;
    notifyListeners();
    try {
      if (!query.isValid) {
        throw const MonitoringFailure(
          MonitoringFailureCode.invalidHistoryQuery,
        );
      }
      _requireConfiguration();
      final result = await waterers.history(
        context.ranchId,
        controllerId,
        query,
      );
      if (!_isCurrent(context) ||
          generation != _historyGeneration ||
          !identical(status, _detail)) {
        return false;
      }
      if (!_same(result.controllerId, controllerId) ||
          !result.from.isAtSameMomentAs(query.from) ||
          !result.to.isAtSameMomentAs(query.to) ||
          result.page != query.page ||
          result.pageSize != query.pageSize ||
          result.totalCount < 0 ||
          result.items.length > query.pageSize ||
          result.items.any(
            (item) =>
                !_same(item.ranchId, context.ranchId) ||
                !_same(item.controllerId, controllerId),
          )) {
        throw const MonitoringFailure(MonitoringFailureCode.invalidResponse);
      }
      _history = result;
      _historyStatus = WatererLoadStatus.ready;
      notifyListeners();
      return true;
    } catch (error) {
      if (!_isCurrent(context) ||
          generation != _historyGeneration ||
          !identical(status, _detail)) {
        return false;
      }
      final failure = _failure(error);
      _clearOnConnectionFailure(failure);
      _historyError = failure;
      _historyStatus = WatererLoadStatus.unavailable;
      notifyListeners();
      return false;
    }
  }

  void clearHistory() {
    if (_disposed) return;
    _resetHistory();
    notifyListeners();
  }

  void clear() {
    if (_disposed) return;
    _reset();
    notifyListeners();
  }

  /// Background snapshots never become an offline cache when the app resumes.
  void setActive(bool active) {
    if (_disposed || active == _active) return;
    _active = active;
    _reset();
    ++_revision;
    notifyListeners();
  }

  bool _isCurrent(AuthorizedRanchContext context) =>
      !_disposed &&
      _active &&
      access.isCurrent(context) &&
      identical(context, _context);

  bool _belongsToRanch(WatererStatus item, AuthorizedRanchContext context) =>
      item.latestReading == null ||
      _same(item.latestReading!.ranchId, context.ranchId);

  bool _same(String left, String right) =>
      left.toLowerCase() == right.toLowerCase();

  void _requireConfiguration() {
    if (!waterers.isConfigured) {
      throw const MonitoringFailure(MonitoringFailureCode.configuration);
    }
  }

  MonitoringFailure _failure(Object error) => error is MonitoringFailure
      ? error
      : const MonitoringFailure(MonitoringFailureCode.unknown);

  void _clearOnConnectionFailure(MonitoringFailure failure) {
    switch (failure.code) {
      case MonitoringFailureCode.contextUnavailable:
      case MonitoringFailureCode.unauthenticated:
      case MonitoringFailureCode.forbidden:
      case MonitoringFailureCode.network:
      case MonitoringFailureCode.serviceUnavailable:
        _reset();
        _listStatus = _detailStatus = _historyStatus =
            WatererLoadStatus.unavailable;
        _listError = _detailError = _historyError = failure;
      default:
        break;
    }
  }

  void _resetHistory() {
    ++_historyGeneration;
    _history = null;
    _historyError = null;
    _historyStatus = WatererLoadStatus.idle;
  }

  void _reset() {
    ++_listGeneration;
    ++_detailGeneration;
    _items = const [];
    _detail = null;
    _listError = _detailError = null;
    _listStatus = _detailStatus = WatererLoadStatus.idle;
    _resetHistory();
  }

  void _onAccessChanged() {
    final next = access.context;
    if (_disposed || identical(next, _context)) return;
    _context = next;
    _reset();
    ++_revision;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    access.removeListener(_onAccessChanged);
    _reset();
    super.dispose();
  }
}
