/// Remembers which cloud alerts were already announced, separately for each ranch.
abstract interface class NotifiedAlertRepository {
  /// Returns the stored alert IDs, oldest first.
  Future<List<String>> read(String ranchId);

  Future<void> write(String ranchId, List<String> alertIds);
}
