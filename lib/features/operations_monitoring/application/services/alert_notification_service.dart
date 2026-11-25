import 'dart:async';

import '../../../iam/application/facades/authorized_ranch_session.dart';
import '../../domain/model/alert_search.dart';
import '../../domain/model/ranch_alert.dart';
import '../../domain/repositories/alert_notifier.dart';
import '../../domain/repositories/alert_repository.dart';
import '../../domain/repositories/notified_alert_repository.dart';

/// Announces each new pending alert once, while the app is open and a ranch is selected.
final class AlertNotificationService {
  AlertNotificationService({
    required this._access,
    required this._alerts,
    required this._notifier,
    required this._notified,
  }) {
    _access.addListener(_onAccessChanged);
    _onAccessChanged();
  }

  static const _pollInterval = Duration(seconds: 30);
  static const _pendingPage = AlertSearch(
    status: AlertStatus.pending,
    pageSize: 20,
  );
  // Bounds local storage; an old alert is announced again only if it is still pending.
  static const _rememberedLimit = 200;

  final AuthorizedRanchSession _access;
  final AlertRepository _alerts;
  final AlertNotifier _notifier;
  final NotifiedAlertRepository _notified;
  ({String accountId, String ranchId})? _scope;
  Timer? _timer;
  bool _active = true;
  bool _polling = false;
  bool _seeded = false;
  int _generation = 0;
  bool _disposed = false;

  /// Emits when the user taps a notification posted by this app.
  Stream<void> get taps => _notifier.taps;

  /// Polling pauses in the background; alerts raised meanwhile are announced on resume.
  void setActive(bool active) {
    if (_disposed || active == _active) return;
    _active = active;
    if (active) {
      _startPolling();
    } else {
      _stopPolling();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _access.removeListener(_onAccessChanged);
    _stopPolling();
  }

  void _onAccessChanged() {
    if (_disposed) return;
    final context = _access.context;
    final next = context == null
        ? null
        : (accountId: context.accountId, ranchId: context.ranchId);
    // Revalidating the same account and ranch keeps the timer and the seeded state.
    if (next == _scope) return;
    _scope = next;
    _seeded = false;
    _stopPolling();
    _startPolling();
  }

  void _startPolling() {
    if (_disposed ||
        !_active ||
        _scope == null ||
        _timer != null ||
        !_alerts.isConfigured) {
      return;
    }
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(_poll()));
    unawaited(_poll());
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
    // Responses to requests started before this point must never notify.
    ++_generation;
  }

  Future<void> _poll() async {
    final scope = _scope;
    if (_polling || scope == null) return;
    final generation = _generation;
    _polling = true;
    try {
      await _notifier.initialize();
      final page = await _alerts.search(scope.ranchId, _pendingPage);
      final remembered = await _notified.read(scope.ranchId);
      if (!_isCurrent(generation)) return;
      if (!_seeded) {
        // The first poll of a ranch context records existing alerts without announcing them.
        await _remember(scope.ranchId, remembered, page.items.map(_idOf));
        if (_isCurrent(generation)) _seeded = true;
        return;
      }
      final known = remembered.toSet();
      final announced = <String>[];
      for (final alert in page.items) {
        if (!known.add(_idOf(alert))) continue;
        if (!_isCurrent(generation)) break;
        try {
          await _notifier.show(alert);
          announced.add(_idOf(alert));
        } catch (_) {
          // An alert that failed to show stays unrecorded, so the next tick retries it.
        }
      }
      if (announced.isNotEmpty) {
        await _remember(scope.ranchId, remembered, announced);
      }
    } catch (_) {
      // A failed tick changes nothing; the next tick starts again from stored state.
    } finally {
      _polling = false;
    }
  }

  Future<void> _remember(
    String ranchId,
    List<String> remembered,
    Iterable<String> added,
  ) {
    final ids = {...remembered, ...added}.toList();
    final bounded = ids.length > _rememberedLimit
        ? ids.sublist(ids.length - _rememberedLimit)
        : ids;
    return _notified.write(ranchId, bounded);
  }

  bool _isCurrent(int generation) =>
      !_disposed && _active && generation == _generation;

  static String _idOf(RanchAlert alert) => alert.alertId.toLowerCase();
}
