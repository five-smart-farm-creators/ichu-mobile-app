import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/alert_search.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/ranch_alert.dart';

void main() {
  group('AlertSearch', () {
    test('defaults to the first bounded page without a status filter', () {
      const query = AlertSearch();

      expect(query.page, 1);
      expect(query.pageSize, 20);
      expect(query.status, isNull);
      expect(query.isValid, isTrue);
    });

    test('validates page, mobile page size and Int32 offset independently', () {
      expect(const AlertSearch(page: 0).isValid, isFalse);
      expect(const AlertSearch(page: 2147483648).isValid, isFalse);
      expect(const AlertSearch(pageSize: 0).isValid, isFalse);
      expect(const AlertSearch(pageSize: 101).isValid, isFalse);
      expect(const AlertSearch(pageSize: 100).isValid, isTrue);

      expect(const AlertSearch(page: 21474837, pageSize: 100).isValid, isTrue);
      expect(const AlertSearch(page: 21474838, pageSize: 100).isValid, isFalse);
      expect(const AlertSearch(page: 2147483647, pageSize: 1).isValid, isTrue);
    });

    test(
      'atPage preserves filter and size, and queries have value equality',
      () {
        const query = AlertSearch(
          status: AlertStatus.acknowledged,
          page: 2,
          pageSize: 30,
        );
        const equalQuery = AlertSearch(
          status: AlertStatus.acknowledged,
          page: 2,
          pageSize: 30,
        );
        final nextPage = query.atPage(3);

        expect(query, equalQuery);
        expect(query.hashCode, equalQuery.hashCode);
        expect(nextPage.status, AlertStatus.acknowledged);
        expect(nextPage.page, 3);
        expect(nextPage.pageSize, 30);
        expect(nextPage, isNot(query));
      },
    );
  });
}
