import 'package:flutter/foundation.dart';

import '../../../iam/application/facades/authorized_ranch_session.dart';
import '../../domain/model/alert_search.dart';
import '../../domain/model/monitoring_failure.dart';
import '../../domain/model/ranch_alert.dart';
import '../../domain/repositories/alert_repository.dart';

enum AlertLoadStatus { idle, loading, ready, unavailable }

/// Coordinates explicit, ranch-authorized reads of a paged alert list.
final class AlertReadService extends ChangeNotifier {
  AlertReadService({required this._access, required this._alerts}) {
    _access.addListener(_onAccessChanged);
    _observedContext = _access.context;
  }

  final AuthorizedRanchSession _access;
  final AlertRepository _alerts;
  AuthorizedRanchContext? _observedContext;
  AuthorizedRanchContext? _requestContext;
  AlertSearch _query = const AlertSearch();
  List<RanchAlert> _items = const <RanchAlert>[];
  int? _totalCount;
  MonitoringFailure? _error;
  AlertLoadStatus _status = AlertLoadStatus.idle;
  Future<bool>? _pending;
  AlertSearch? _pendingQuery;
  int _generation = 0;
  int _revision = 0;
  bool _disposed = false;

  AlertLoadStatus get status => _visible ? _status : AlertLoadStatus.idle;
  bool get hasContext => !_disposed && _access.context != null;
  bool get canLoad =>
      hasContext && _alerts.isConfigured && status != AlertLoadStatus.loading;
  String? get ranchName => _visible ? _requestContext?.ranchName : null;
  AlertSearch get query => _visible ? _query : const AlertSearch();
  List<RanchAlert> get alerts => _visible && _status == AlertLoadStatus.ready
      ? _items
      : const <RanchAlert>[];
  int? get totalCount =>
      _visible && _status == AlertLoadStatus.ready ? _totalCount : null;
  MonitoringFailure? get error => _visible ? _error : null;
  int get revision => _revision;

  bool get canGoNext {
    if (!_visible || _status != AlertLoadStatus.ready || _totalCount == null) {
      return false;
    }
    final next = _query.page + 1;
    final nextQuery = _query.atPage(next);
    return nextQuery.isValid &&
        _query.page <= AlertSearch.maximumInt32 ~/ _query.pageSize &&
        _query.page * _query.pageSize < _totalCount!;
  }

  bool get canGoPrevious =>
      hasContext && status != AlertLoadStatus.loading && _query.page > 1;

  /// Loads the selected page explicitly; no read starts during construction.
  Future<bool> load({AlertSearch? query}) {
    if (_disposed) return Future<bool>.value(false);
    final requested = query ?? _query;
    final context = _access.context;
    if (context == null) {
      _beginUnavailable(
        const MonitoringFailure(MonitoringFailureCode.contextUnavailable),
      );
      return Future<bool>.value(false);
    }
    if (!requested.isValid) {
      ++_generation;
      _requestContext = context;
      _query = requested;
      _clearPage();
      _error = const MonitoringFailure(MonitoringFailureCode.invalidSearch);
      _status = AlertLoadStatus.unavailable;
      _pending = null;
      _pendingQuery = null;
      notifyListeners();
      return Future<bool>.value(false);
    }
    if (_pending != null &&
        identical(_requestContext, context) &&
        _pendingQuery == requested) {
      return _pending!;
    }

    final generation = ++_generation;
    _requestContext = context;
    _query = requested;
    _clearPage();
    _error = null;
    _status = AlertLoadStatus.loading;
    _pendingQuery = requested;
    // Schedule the port call so pending intent exists before listeners reenter.
    final future = Future<bool>.microtask(
      () => _performLoad(context, requested, generation),
    );
    _pending = future;
    notifyListeners();
    return future;
  }

  Future<bool> nextPage() => canGoNext
      ? load(query: _query.atPage(_query.page + 1))
      : Future<bool>.value(false);

  Future<bool> previousPage() => canGoPrevious
      ? load(query: _query.atPage(_query.page - 1))
      : Future<bool>.value(false);

  Future<bool> _performLoad(
    AuthorizedRanchContext context,
    AlertSearch query,
    int generation,
  ) async {
    try {
      if (!_isCurrent(context, generation)) return false;
      final alerts = _alerts;
      if (!alerts.isConfigured) {
        _fail(
          context,
          generation,
          const MonitoringFailure(MonitoringFailureCode.configuration),
        );
        return false;
      }
      final result = await alerts.search(context.ranchId, query);
      if (!_isCurrent(context, generation)) return false;
      if (!_isValidResponse(result, context, query)) {
        _fail(
          context,
          generation,
          const MonitoringFailure(MonitoringFailureCode.invalidResponse),
        );
        return false;
      }
      _items = List<RanchAlert>.unmodifiable(result.items);
      _totalCount = result.totalCount;
      _error = null;
      _status = AlertLoadStatus.ready;
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
      if (generation == _generation) {
        _pending = null;
        _pendingQuery = null;
      }
    }
  }

  bool _isValidResponse(
    AlertPage page,
    AuthorizedRanchContext context,
    AlertSearch query,
  ) {
    if (page.page != query.page ||
        page.pageSize != query.pageSize ||
        page.items.length > query.pageSize ||
        page.totalCount < 0 ||
        page.totalCount > AlertSearch.maximumInt32) {
      return false;
    }
    final ids = <String>{};
    for (final item in page.items) {
      final id = item.alertId.trim();
      if (item.ranchId.toLowerCase() != context.ranchId.toLowerCase() ||
          id.isEmpty ||
          !ids.add(id.toLowerCase()) ||
          (query.status != null && item.status != query.status)) {
        return false;
      }
    }
    return true;
  }

  bool _isCurrent(AuthorizedRanchContext context, int generation) =>
      !_disposed &&
      generation == _generation &&
      _access.isCurrent(context) &&
      identical(_requestContext, context);

  bool get _visible =>
      !_disposed &&
      _requestContext != null &&
      _access.isCurrent(_requestContext!) &&
      identical(_requestContext, _access.context);

  void _fail(
    AuthorizedRanchContext context,
    int generation,
    MonitoringFailure failure,
  ) {
    if (!_isCurrent(context, generation)) return;
    _clearPage();
    _error = failure;
    _status = AlertLoadStatus.unavailable;
    notifyListeners();
  }

  void _beginUnavailable(MonitoringFailure failure) {
    ++_generation;
    _requestContext = null;
    _query = const AlertSearch();
    _clearPage();
    _error = failure;
    _status = AlertLoadStatus.unavailable;
    _pending = null;
    _pendingQuery = null;
    notifyListeners();
  }

  void _clearPage() {
    _items = const <RanchAlert>[];
    _totalCount = null;
  }

  void clear() {
    if (_disposed) return;
    ++_generation;
    _requestContext = null;
    _query = const AlertSearch();
    _clearPage();
    _error = null;
    _status = AlertLoadStatus.idle;
    _pending = null;
    _pendingQuery = null;
    notifyListeners();
  }

  void _onAccessChanged() {
    if (_disposed) return;
    final next = _access.context;
    if (identical(next, _observedContext)) return;
    _observedContext = next;
    ++_generation;
    _requestContext = null;
    _query = const AlertSearch();
    _clearPage();
    _error = null;
    _status = AlertLoadStatus.idle;
    _pending = null;
    _pendingQuery = null;
    _revision++;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    _access.removeListener(_onAccessChanged);
    _requestContext = null;
    _clearPage();
    _error = null;
    _pending = null;
    _pendingQuery = null;
    super.dispose();
  }
}
