import 'package:ichu_mobile_app/features/operations_monitoring/domain/repositories/notified_alert_repository.dart';

/// In-memory test fixture; production storage uses the platform preferences adapter.
final class MemoryNotifiedAlertRepository implements NotifiedAlertRepository {
  final Map<String, List<String>> _ids = <String, List<String>>{};

  @override
  Future<List<String>> read(String ranchId) async =>
      List<String>.of(_ids[ranchId] ?? const <String>[]);

  @override
  Future<void> write(String ranchId, List<String> alertIds) async {
    _ids[ranchId] = List<String>.of(alertIds);
  }
}
