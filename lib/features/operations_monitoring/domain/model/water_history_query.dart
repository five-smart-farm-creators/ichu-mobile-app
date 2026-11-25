/// Controller history uses a half-open interval and offset-based pagination.
final class WaterHistoryQuery {
  const WaterHistoryQuery({
    required this.from,
    required this.to,
    this.page = 1,
    this.pageSize = 20,
  });

  static const maximumInt32 = 2147483647;
  final DateTime from;
  final DateTime to;
  final int page;
  final int pageSize;

  bool get isValid =>
      from.toUtc().year >= 1 &&
      from.toUtc().year <= 9999 &&
      to.toUtc().year >= 1 &&
      to.toUtc().year <= 9999 &&
      from.isBefore(to) &&
      page >= 1 &&
      page <= maximumInt32 &&
      pageSize >= 1 &&
      pageSize <= 500 &&
      page - 1 <= maximumInt32 ~/ pageSize;

  WaterHistoryQuery atPage(int value) =>
      WaterHistoryQuery(from: from, to: to, page: value, pageSize: pageSize);
}
