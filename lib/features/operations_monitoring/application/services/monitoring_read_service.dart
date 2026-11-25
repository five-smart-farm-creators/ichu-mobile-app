import 'package:flutter/foundation.dart';

import '../../../iam/application/facades/authorized_ranch_session.dart';
import '../../domain/model/latest_telemetry.dart';
import '../../domain/model/monitoring_failure.dart';
import '../../domain/model/telemetry_history.dart';
import '../../domain/model/telemetry_history_query.dart';
import '../../domain/repositories/monitoring_repository.dart';

enum MonitoringLoadStatus { idle, loading, ready, unavailable }

enum TelemetryHistoryLoadStatus { idle, loading, ready, unavailable }

/// Coordinates ranch-authorized monitoring reads for one current cattle context.
final class MonitoringReadService extends ChangeNotifier {
  MonitoringReadService({required this._access, required this._monitoring}) {
    _access.addListener(_onAccessChanged);
    _observedContext = _access.context;
  }

  final AuthorizedRanchSession _access;
  final MonitoringRepository _monitoring;
  AuthorizedRanchContext? _observedContext;
  AuthorizedRanchContext? _requestContext;
  String? _requestedCattleId;
  LatestTelemetry? _snapshot;
  MonitoringFailure? _error;
  MonitoringLoadStatus _status = MonitoringLoadStatus.idle;
  Future<bool>? _pending;
  int _generation = 0;
  AuthorizedRanchContext? _historyContext;
  String? _historyCattleId;
  TelemetryHistoryQuery? _historyQuery;
  TelemetryHistoryPage? _historyPage;
  MonitoringFailure? _historyError;
  TelemetryHistoryLoadStatus _historyStatus = TelemetryHistoryLoadStatus.idle;
  Future<bool>? _historyPending;
  TelemetryHistoryQuery? _historyPendingQuery;
  int _historyGeneration = 0;
  int _revision = 0;
  bool _disposed = false;

  MonitoringLoadStatus get status =>
      _visible ? _status : MonitoringLoadStatus.idle;
  bool get hasContext => !_disposed && _access.context != null;
  bool get canLoad =>
      hasContext &&
      _monitoring.isConfigured &&
      status != MonitoringLoadStatus.loading;
  String? get ranchName => _visible ? _requestContext?.ranchName : null;
  String? get cattleId => _visible ? _requestedCattleId : null;
  LatestTelemetry? get snapshot => _visible ? _snapshot : null;
  MonitoringFailure? get error => _visible ? _error : null;
  TelemetryHistoryLoadStatus get historyStatus =>
      _historyVisible ? _historyStatus : TelemetryHistoryLoadStatus.idle;
  TelemetryHistoryPage? get historyPage =>
      _historyVisible ? _historyPage : null;
  TelemetryHistoryQuery? get historyQuery =>
      _historyVisible ? _historyQuery : null;
  MonitoringFailure? get historyError => _historyVisible ? _historyError : null;
  bool get canLoadHistory =>
      hasContext &&
      _monitoring.isConfigured &&
      historyStatus != TelemetryHistoryLoadStatus.loading;
  bool get canGoNextHistoryPage {
    final query = historyQuery;
    final page = historyPage;
    return query != null &&
        page != null &&
        historyStatus == TelemetryHistoryLoadStatus.ready &&
        query.page * query.pageSize < page.totalCount;
  }

  bool get canGoPreviousHistoryPage =>
      historyQuery != null &&
      historyStatus != TelemetryHistoryLoadStatus.loading &&
      historyQuery!.page > 1;
  int get revision => _revision;

  bool get _visible =>
      !_disposed &&
      _requestContext != null &&
      _access.isCurrent(_requestContext!) &&
      identical(_requestContext, _access.context);

  bool get _historyVisible =>
      !_disposed &&
      _historyContext != null &&
      _access.isCurrent(_historyContext!) &&
      identical(_historyContext, _access.context);

  /// Performs an explicit load; configuration and permission recovery require retry.
  Future<bool> load(String cattleId) {
    if (_disposed) return Future<bool>.value(false);
    final context = _access.context;
    if (context == null) {
      _beginUnavailable(
        const MonitoringFailure(MonitoringFailureCode.contextUnavailable),
      );
      return Future<bool>.value(false);
    }
    final id = cattleId;
    if (!_isUuid(id)) {
      ++_generation;
      _requestContext = context;
      _requestedCattleId = id.isEmpty ? null : id;
      _snapshot = null;
      _error = const MonitoringFailure(MonitoringFailureCode.notFound);
      _status = MonitoringLoadStatus.unavailable;
      _pending = null;
      _resetHistory();
      notifyListeners();
      return Future<bool>.value(false);
    }
    if (_historyCattleId != null &&
        _historyCattleId!.toLowerCase() != id.toLowerCase()) {
      _resetHistory();
    }
    if (_pending != null &&
        identical(_requestContext, context) &&
        _requestedCattleId!.toLowerCase() == id.toLowerCase()) {
      return _pending!;
    }

    final generation = ++_generation;
    _requestContext = context;
    _requestedCattleId = id;
    _snapshot = null;
    _error = null;
    _status = MonitoringLoadStatus.loading;
    // Install pending intent before observers can synchronously request it again.
    final future = Future<bool>.microtask(
      () => _performLoad(context, id, generation),
    );
    _pending = future;
    notifyListeners();
    return future;
  }

  /// Loads one explicit half-open period page for the current authorized ranch.
  Future<bool> loadHistory(String cattleId, TelemetryHistoryQuery query) {
    if (_disposed) return Future<bool>.value(false);
    final context = _access.context;
    if (context == null) {
      _beginHistoryUnavailable(
        const MonitoringFailure(MonitoringFailureCode.contextUnavailable),
      );
      return Future<bool>.value(false);
    }
    if (!_isUuid(cattleId) || !query.isValid) {
      ++_historyGeneration;
      _historyContext = context;
      _historyCattleId = _isUuid(cattleId) ? cattleId : null;
      _historyQuery = query;
      _historyPage = null;
      _historyError = MonitoringFailure(
        _isUuid(cattleId)
            ? MonitoringFailureCode.invalidHistoryQuery
            : MonitoringFailureCode.notFound,
      );
      _historyStatus = TelemetryHistoryLoadStatus.unavailable;
      _historyPending = null;
      _historyPendingQuery = null;
      notifyListeners();
      return Future<bool>.value(false);
    }
    if (_historyPending != null &&
        identical(_historyContext, context) &&
        _historyCattleId!.toLowerCase() == cattleId.toLowerCase() &&
        _historyPendingQuery == query) {
      return _historyPending!;
    }

    final generation = ++_historyGeneration;
    _historyContext = context;
    _historyCattleId = cattleId;
    _historyQuery = query;
    _historyPage = null;
    _historyError = null;
    _historyStatus = TelemetryHistoryLoadStatus.loading;
    _historyPendingQuery = query;
    final future = Future<bool>.microtask(
      () => _performHistoryLoad(context, cattleId, query, generation),
    );
    _historyPending = future;
    notifyListeners();
    return future;
  }

  Future<bool> nextHistoryPage() {
    final query = historyQuery;
    return canGoNextHistoryPage && query != null
        ? loadHistory(_historyCattleId!, query.atPage(query.page + 1))
        : Future<bool>.value(false);
  }

  Future<bool> previousHistoryPage() {
    final query = historyQuery;
    return canGoPreviousHistoryPage && query != null
        ? loadHistory(_historyCattleId!, query.atPage(query.page - 1))
        : Future<bool>.value(false);
  }

  Future<bool> reloadHistory() {
    final query = historyQuery;
    return query == null
        ? Future<bool>.value(false)
        : loadHistory(_historyCattleId!, query);
  }

  Future<bool> _performHistoryLoad(
    AuthorizedRanchContext context,
    String cattleId,
    TelemetryHistoryQuery query,
    int generation,
  ) async {
    try {
      if (!_isCurrentHistory(context, generation)) return false;
      if (!_monitoring.isConfigured) {
        _failHistory(
          context,
          generation,
          const MonitoringFailure(MonitoringFailureCode.configuration),
        );
        return false;
      }
      final result = await _monitoring.history(
        context.ranchId,
        cattleId,
        query,
      );
      if (!_isCurrentHistory(context, generation)) return false;
      if (result.cattleId.toLowerCase() != cattleId.toLowerCase() ||
          !result.matches(query)) {
        _failHistory(
          context,
          generation,
          const MonitoringFailure(MonitoringFailureCode.invalidResponse),
        );
        return false;
      }
      _historyPage = result;
      _historyError = null;
      _historyStatus = TelemetryHistoryLoadStatus.ready;
      notifyListeners();
      return true;
    } on MonitoringFailure catch (failure) {
      _failHistory(context, generation, failure);
      return false;
    } catch (_) {
      _failHistory(
        context,
        generation,
        const MonitoringFailure(MonitoringFailureCode.unknown),
      );
      return false;
    } finally {
      if (generation == _historyGeneration) {
        _historyPending = null;
        _historyPendingQuery = null;
      }
    }
  }

  bool _isCurrentHistory(AuthorizedRanchContext context, int generation) =>
      !_disposed &&
      generation == _historyGeneration &&
      _access.isCurrent(context) &&
      identical(_access.context, context);

  void _failHistory(
    AuthorizedRanchContext context,
    int generation,
    MonitoringFailure failure,
  ) {
    if (!_isCurrentHistory(context, generation)) return;
    _historyPage = null;
    _historyError = failure;
    _historyStatus = TelemetryHistoryLoadStatus.unavailable;
    notifyListeners();
  }

  void _beginHistoryUnavailable(MonitoringFailure failure) {
    ++_historyGeneration;
    _historyContext = null;
    _historyCattleId = null;
    _historyPage = null;
    _historyError = failure;
    _historyStatus = TelemetryHistoryLoadStatus.unavailable;
    _historyPending = null;
    _historyPendingQuery = null;
  }

  void _resetHistory() {
    ++_historyGeneration;
    _historyContext = null;
    _historyCattleId = null;
    _historyQuery = null;
    _historyPage = null;
    _historyError = null;
    _historyStatus = TelemetryHistoryLoadStatus.idle;
    _historyPending = null;
    _historyPendingQuery = null;
  }

  Future<bool> _performLoad(
    AuthorizedRanchContext context,
    String id,
    int generation,
  ) async {
    try {
      if (!_isCurrent(context, generation)) return false;
      if (!_monitoring.isConfigured) {
        _fail(
          context,
          generation,
          const MonitoringFailure(MonitoringFailureCode.configuration),
        );
        return false;
      }
      final result = await _monitoring.latest(context.ranchId, id);
      if (!_isCurrent(context, generation)) return false;
      if (result.cattleId.toLowerCase() != id.toLowerCase()) {
        _fail(
          context,
          generation,
          const MonitoringFailure(MonitoringFailureCode.invalidResponse),
        );
        return false;
      }
      _snapshot = result;
      _error = null;
      _status = MonitoringLoadStatus.ready;
      notifyListeners();
      return true;
    } on MonitoringFailure catch (failure) {
      _fail(context, generation, failure);
      return false;
    } catch (_) {
      _fail(
        context,
        generation,
        const MonitoringFailure(MonitoringFailureCode.unknown),
      );
      return false;
    } finally {
      if (generation == _generation) _pending = null;
    }
  }

  bool _isCurrent(AuthorizedRanchContext context, int generation) =>
      !_disposed && generation == _generation && _access.isCurrent(context);

  void _fail(
    AuthorizedRanchContext context,
    int generation,
    MonitoringFailure failure,
  ) {
    if (!_isCurrent(context, generation)) return;
    _snapshot = null;
    _error = failure;
    _status = MonitoringLoadStatus.unavailable;
    notifyListeners();
  }

  void _beginUnavailable(MonitoringFailure failure) {
    ++_generation;
    _requestContext = null;
    _requestedCattleId = null;
    _snapshot = null;
    _error = failure;
    _status = MonitoringLoadStatus.unavailable;
    _pending = null;
    _resetHistory();
    notifyListeners();
  }

  void clear() {
    if (_disposed) return;
    ++_generation;
    _requestContext = null;
    _requestedCattleId = null;
    _snapshot = null;
    _error = null;
    _status = MonitoringLoadStatus.idle;
    _pending = null;
    _resetHistory();
    notifyListeners();
  }

  void _onAccessChanged() {
    if (_disposed) return;
    final next = _access.context;
    if (identical(next, _observedContext)) return;
    _observedContext = next;
    ++_generation;
    _requestContext = null;
    _requestedCattleId = null;
    _snapshot = null;
    _error = null;
    _status = MonitoringLoadStatus.idle;
    _pending = null;
    _resetHistory();
    _revision++;
    notifyListeners();
  }

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$',
  );
  bool _isUuid(String value) =>
      _uuid.hasMatch(value) &&
      value.replaceAll('-', '').replaceAll('0', '').isNotEmpty;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    _access.removeListener(_onAccessChanged);
    _requestContext = null;
    _snapshot = null;
    _pending = null;
    _resetHistory();
    super.dispose();
  }
}
