import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle_date.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle_search.dart';

void main() {
  test(
    'calendar dates reject normalization and compare without time-zone shifts',
    () {
      expect(const CattleDate(2024, 2, 29).isValid, isTrue);
      expect(const CattleDate(2023, 2, 29).isValid, isFalse);
      expect(const CattleDate(2024, 13, 1).isValid, isFalse);
      expect(const CattleDate(0, 1, 1).isValid, isFalse);
      expect(const CattleDate(2024, 3, 1), const CattleDate(2024, 3, 1));
      expect(const CattleDate(2024, 3, 1).asUtcDate, DateTime.utc(2024, 3, 1));
    },
  );
  test(
    'search follows exact tag and server paging bounds without integer overflow',
    () {
      expect(const CattleSearch().isValid, isTrue);
      expect(const CattleSearch(earTag: ' ').isValid, isTrue);
      expect(CattleSearch(earTag: 'x' * 30).isValid, isTrue);
      expect(CattleSearch(earTag: 'x' * 31).isValid, isFalse);
      expect(const CattleSearch(page: 0).isValid, isFalse);
      expect(const CattleSearch(pageSize: 0).isValid, isFalse);
      expect(const CattleSearch(pageSize: 101).isValid, isFalse);
      expect(const CattleSearch(page: 2147483647, pageSize: 1).isValid, isTrue);
      expect(
        const CattleSearch(page: 2147483648, pageSize: 1).isValid,
        isFalse,
      );
      expect(
        const CattleSearch(page: 2147483649, pageSize: 1).isValid,
        isFalse,
      );
      expect(
        const CattleSearch(page: 9223372036854775807, pageSize: 100).isValid,
        isFalse,
      );
      expect(
        const CattleSearch(earTag: 'PE-001').atPage(2),
        const CattleSearch(earTag: 'PE-001', page: 2),
      );
    },
  );
}
