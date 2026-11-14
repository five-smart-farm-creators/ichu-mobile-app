import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/water_history_query.dart';

void main() {
  final from = DateTime.utc(2026, 1, 1);
  final to = DateTime.utc(2026, 1, 2);
  test('accepts documented bounds, long periods and maximum page size', () {
    expect(
      WaterHistoryQuery(
        from: DateTime.utc(1),
        to: DateTime.utc(9999),
        pageSize: 500,
      ).isValid,
      isTrue,
    );
    expect(WaterHistoryQuery(from: from, to: to).atPage(2).page, 2);
  });
  test('rejects empty or reversed periods and invalid page offsets', () {
    for (final query in [
      WaterHistoryQuery(from: from, to: from),
      WaterHistoryQuery(from: to, to: from),
      WaterHistoryQuery(from: from, to: to, page: 0),
      WaterHistoryQuery(from: from, to: to, pageSize: 0),
      WaterHistoryQuery(from: from, to: to, pageSize: 501),
      WaterHistoryQuery(from: from, to: to, page: 2147483647, pageSize: 500),
    ]) {
      expect(query.isValid, isFalse);
    }
  });
}
