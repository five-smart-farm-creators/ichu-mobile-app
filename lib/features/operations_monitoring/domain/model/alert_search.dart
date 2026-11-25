import 'ranch_alert.dart';

/// A bounded alert-list query; it deliberately has no animal or detail filter.
final class AlertSearch {
  const AlertSearch({this.status, this.page = 1, this.pageSize = 20});

  static const int maximumInt32 = 2147483647;
  static const int maximumMobilePageSize = 100;

  final AlertStatus? status;
  final int page;
  final int pageSize;

  bool get isValid {
    if (page < 1 ||
        page > maximumInt32 ||
        pageSize < 1 ||
        pageSize > maximumMobilePageSize) {
      return false;
    }
    return page - 1 <= maximumInt32 ~/ pageSize;
  }

  AlertSearch atPage(int value) =>
      AlertSearch(status: status, page: value, pageSize: pageSize);

  @override
  bool operator ==(Object other) =>
      other is AlertSearch &&
      other.status == status &&
      other.page == page &&
      other.pageSize == pageSize;

  @override
  int get hashCode => Object.hash(status, page, pageSize);
}
