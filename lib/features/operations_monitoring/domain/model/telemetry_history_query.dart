/// Bounded, half-open time range and page for an authorized telemetry read.
final class TelemetryHistoryQuery {
  const TelemetryHistoryQuery({
    required this.from,
    required this.to,
    this.page = 1,
    this.pageSize = defaultPageSize,
  });

  static const int maximumInt32 = 2147483647;
  static const int defaultPageSize = 20;
  static const int maximumMobilePageSize = 100;

  final DateTime from;
  final DateTime to;
  final int page;
  final int pageSize;

  bool get isValid =>
      from.isBefore(to) &&
      page >= 1 &&
      page <= maximumInt32 &&
      pageSize >= 1 &&
      pageSize <= maximumMobilePageSize &&
      page - 1 <= maximumInt32 ~/ pageSize;

  TelemetryHistoryQuery atPage(int value) => TelemetryHistoryQuery(
    from: from,
    to: to,
    page: value,
    pageSize: pageSize,
  );

  bool hasSamePeriod(TelemetryHistoryQuery other) =>
      from.isAtSameMomentAs(other.from) && to.isAtSameMomentAs(other.to);

  @override
  bool operator ==(Object other) =>
      other is TelemetryHistoryQuery &&
      hasSamePeriod(other) &&
      page == other.page &&
      pageSize == other.pageSize;

  @override
  int get hashCode => Object.hash(
    from.toUtc().millisecondsSinceEpoch,
    to.toUtc().millisecondsSinceEpoch,
    page,
    pageSize,
  );
}
