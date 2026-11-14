import 'package:flutter/foundation.dart';

import '../../../iam/application/facades/authorized_ranch_session.dart';
import '../../domain/model/edge_alert.dart';
import '../../domain/model/monitoring_failure.dart';
import '../../domain/repositories/edge_alert_repository.dart';

enum EdgeAlertLoadStatus { idle, loading, ready, stale, unavailable }

/// Coordinates read-only access to synchronized Edge-origin alerts.
final class EdgeAlertReadService extends ChangeNotifier {
  EdgeAlertReadService({required this.access, required this.edgeAlerts}) {
    access.addListener(_onAccessChanged);
    _observedContext = access.context;
  }

  final AuthorizedRanchSession access;
  final EdgeAlertRepository edgeAlerts;
  AuthorizedRanchContext? _observedContext;
  AuthorizedRanchContext? _requestContext;
  EdgeAlertPage? _page;
  MonitoringFailure? _error;
  DateTime? _lastLoadedAt;
  EdgeAlertLoadStatus _status = EdgeAlertLoadStatus.idle;
  Future<bool>? _pending;
  int? _pendingPage;
  int _requestedPage = 1;
  int _generation = 0;
  int _revision = 0;
  bool _disposed = false;

  EdgeAlertLoadStatus get status =>
      _visible ? _status : EdgeAlertLoadStatus.idle;
  bool get hasContext => !_disposed && access.context != null;
  bool get canLoad => hasContext && status != EdgeAlertLoadStatus.loading;
  String? get ranchName => _visible ? _requestContext?.ranchName : null;
  EdgeAlertPage? get page => _visible ? _page : null;
  List<EdgeAlert> get alerts => page?.items ?? const <EdgeAlert>[];
  MonitoringFailure? get error => _visible ? _error : null;
  DateTime? get lastLoadedAt => _visible ? _lastLoadedAt : null;
  int get revision => _revision;

  bool get canGoNext {
    final current = page;
    if (status != EdgeAlertLoadStatus.ready || current == null) return false;
    return current.page <= current.totalCount ~/ current.pageSize &&
        current.page * current.pageSize < current.totalCount;
  }

  bool get canGoPrevious =>
      status == EdgeAlertLoadStatus.ready && (page?.page ?? 1) > 1;

  Future<bool> load({int? page}) {
    if (_disposed) return Future<bool>.value(false);
    final context = access.context;
    if (context == null) {
      _beginUnavailable(
        const MonitoringFailure(MonitoringFailureCode.contextUnavailable),
      );
      return Future<bool>.value(false);
    }

    final requestedPage = page ?? _page?.page ?? _requestedPage;
    if (requestedPage < 1 || requestedPage > 2147483647) {
      _requestContext = context;
      _page = null;
      _lastLoadedAt = null;
      _error = const MonitoringFailure(MonitoringFailureCode.invalidSearch);
      _status = EdgeAlertLoadStatus.unavailable;
      ++_generation;
      _pending = null;
      _pendingPage = null;
      notifyListeners();
      return Future<bool>.value(false);
    }

    if (_pending != null &&
        identical(_requestContext, context) &&
        _pendingPage == requestedPage) {
      return _pending!;
    }

    final generation = ++_generation;
    _requestContext = context;
    _requestedPage = requestedPage;
    _error = null;
    _status = EdgeAlertLoadStatus.loading;
    _pendingPage = requestedPage;
    final future = Future<bool>.microtask(
      () => _performLoad(context, requestedPage, generation),
    );
    _pending = future;
    notifyListeners();
    return future;
  }

  Future<bool> refresh() => load(page: _page?.page ?? _requestedPage);

  Future<bool> retry() => load(page: _requestedPage);

  Future<bool> nextPage() =>
      canGoNext ? load(page: page!.page + 1) : Future<bool>.value(false);

  Future<bool> previousPage() =>
      canGoPrevious ? load(page: page!.page - 1) : Future<bool>.value(false);

  Future<bool> _performLoad(
    AuthorizedRanchContext context,
    int requestedPage,
    int generation,
  ) async {
    try {
      if (!_isCurrent(context, generation)) return false;
      if (!edgeAlerts.isConfigured) {
        _fail(
          context,
          generation,
          const MonitoringFailure(MonitoringFailureCode.configuration),
        );
        return false;
      }
      final result = await edgeAlerts.page(context.ranchId, requestedPage);
      if (!_isCurrent(context, generation)) return false;
      if (!_isValidPage(result, context, requestedPage)) {
        _fail(
          context,
          generation,
          const MonitoringFailure(MonitoringFailureCode.invalidResponse),
        );
        return false;
      }
      _page = result;
      _lastLoadedAt = DateTime.now();
      _requestedPage = requestedPage;
      _error = null;
      _status = EdgeAlertLoadStatus.ready;
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
        _pendingPage = null;
      }
    }
  }

  bool _isValidPage(
    EdgeAlertPage result,
    AuthorizedRanchContext context,
    int requestedPage,
  ) {
    if (result.page != requestedPage ||
        result.pageSize != EdgeAlertRepository.pageSize ||
        result.totalCount < 0 ||
        result.totalCount > 2147483647 ||
        result.items.length > result.pageSize) {
      return false;
    }
    final ids = <String>{};
    for (final alert in result.items) {
      final id = alert.alertId.trim();
      if (alert.ranchId.toLowerCase() != context.ranchId.toLowerCase() ||
          id.isEmpty ||
          !ids.add(id.toLowerCase())) {
        return false;
      }
    }
    return true;
  }

  bool _isCurrent(AuthorizedRanchContext context, int generation) =>
      !_disposed &&
      generation == _generation &&
      access.isCurrent(context) &&
      identical(_requestContext, context);

  bool get _visible =>
      !_disposed &&
      _requestContext != null &&
      access.isCurrent(_requestContext!) &&
      identical(_requestContext, access.context);

  void _fail(
    AuthorizedRanchContext context,
    int generation,
    MonitoringFailure failure,
  ) {
    if (!_isCurrent(context, generation)) return;
    _error = failure;
    if (_requiresClearing(failure.code)) {
      _page = null;
      _lastLoadedAt = null;
      _status = EdgeAlertLoadStatus.unavailable;
    } else if (_page != null) {
      _status = EdgeAlertLoadStatus.stale;
    } else {
      _status = EdgeAlertLoadStatus.unavailable;
    }
    notifyListeners();
  }

  bool _requiresClearing(MonitoringFailureCode code) => switch (code) {
    MonitoringFailureCode.contextUnavailable ||
    MonitoringFailureCode.unauthenticated ||
    MonitoringFailureCode.forbidden ||
    MonitoringFailureCode.notFound => true,
    _ => false,
  };

  void _beginUnavailable(MonitoringFailure failure) {
    ++_generation;
    _requestContext = null;
    _page = null;
    _lastLoadedAt = null;
    _error = failure;
    _status = EdgeAlertLoadStatus.unavailable;
    _pending = null;
    _pendingPage = null;
    notifyListeners();
  }

  void clear() {
    if (_disposed) return;
    ++_generation;
    _requestContext = null;
    _page = null;
    _lastLoadedAt = null;
    _error = null;
    _status = EdgeAlertLoadStatus.idle;
    _pending = null;
    _pendingPage = null;
    _requestedPage = 1;
    notifyListeners();
  }

  void _onAccessChanged() {
    if (_disposed) return;
    final next = access.context;
    if (identical(next, _observedContext)) return;
    _observedContext = next;
    ++_generation;
    _requestContext = null;
    _page = null;
    _lastLoadedAt = null;
    _error = null;
    _status = EdgeAlertLoadStatus.idle;
    _pending = null;
    _pendingPage = null;
    _requestedPage = 1;
    ++_revision;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    access.removeListener(_onAccessChanged);
    _requestContext = null;
    _page = null;
    _lastLoadedAt = null;
    _error = null;
    _pending = null;
    _pendingPage = null;
    super.dispose();
  }
}
