enum CattleFailureCode {
  configuration,
  contextUnavailable,
  invalidSearch,
  unauthenticated,
  forbidden,
  notFound,
  network,
  serviceUnavailable,
  invalidResponse,
  unknown,
  invalidInput,
  versionConflict,
  duplicateEarTag,
  inactive,
  stageAlreadyCurrent,
  outcomeUnknown,
}

/// Presentation maps these stable categories to localized, non-sensitive text.
final class CattleFailure implements Exception {
  const CattleFailure(this.code);
  final CattleFailureCode code;

  @override
  String toString() => 'CattleFailure(${code.name})';
}
