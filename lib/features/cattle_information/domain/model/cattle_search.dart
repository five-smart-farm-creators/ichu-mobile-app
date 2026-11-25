import 'cattle.dart';

/// Ear tags match exactly and case-sensitively within the selected ranch.
final class CattleSearch {
  const CattleSearch({
    this.earTag = '',
    this.status,
    this.page = 1,
    this.pageSize = 20,
  });

  final String earTag;
  final CattleStatus? status;
  final int page;
  final int pageSize;

  bool get isValid =>
      earTag.trim().length <= 30 &&
      page >= 1 &&
      pageSize >= 1 &&
      pageSize <= 100 &&
      page <= 2147483647 &&
      page <= (2147483647 ~/ pageSize) + 1;

  CattleSearch atPage(int nextPage) => CattleSearch(
    earTag: earTag,
    status: status,
    page: nextPage,
    pageSize: pageSize,
  );

  @override
  bool operator ==(Object other) =>
      other is CattleSearch &&
      earTag == other.earTag &&
      status == other.status &&
      page == other.page &&
      pageSize == other.pageSize;

  @override
  int get hashCode => Object.hash(earTag, status, page, pageSize);
}
