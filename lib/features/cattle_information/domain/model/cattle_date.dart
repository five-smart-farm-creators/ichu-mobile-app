/// A calendar date, not an instant to convert between time zones.
final class CattleDate implements Comparable<CattleDate> {
  const CattleDate(this.year, this.month, this.day);

  /// Birth and exit rules compare against the server's UTC day, not the device's day.
  factory CattleDate.utcDateOf(DateTime instant) {
    final utc = instant.toUtc();
    return CattleDate(utc.year, utc.month, utc.day);
  }

  final int year;
  final int month;
  final int day;

  bool get isValid =>
      year >= 1 &&
      year <= 9999 &&
      month >= 1 &&
      month <= 12 &&
      day >= 1 &&
      day <= DateTime.utc(year, month + 1, 0).day;

  /// Used only for localized calendar formatting, without conversion to local time.
  DateTime get asUtcDate => DateTime.utc(year, month, day);

  @override
  int compareTo(CattleDate other) => asUtcDate.compareTo(other.asUtcDate);

  @override
  bool operator ==(Object other) =>
      other is CattleDate &&
      year == other.year &&
      month == other.month &&
      day == other.day;

  @override
  int get hashCode => Object.hash(year, month, day);
}
