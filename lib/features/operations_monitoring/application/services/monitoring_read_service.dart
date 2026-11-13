import 'package:flutter/foundation.dart';

import '../../../iam/application/facades/authorized_ranch_session.dart';
import '../../domain/model/latest_telemetry.dart';
import '../../domain/model/monitoring_failure.dart';
import '../../domain/repositories/monitoring_repository.dart';

enum MonitoringLoadStatus { idle, loading, ready, unavailable }

/// Coordinates explicit, ranch-authorized reads of one cattle monitoring summary.
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
  int get revision => _revision;

  bool get _visible =>
      !_disposed &&
      _requestContext != null &&
      _access.isCurrent(_requestContext!) &&
      identical(_requestContext, _access.context);

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
      notifyListeners();
      return Future<bool>.value(false);
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
    super.dispose();
  }
}
