enum MonitoringFailureCode {
  configuration,
  contextUnavailable,
  unauthenticated,
  forbidden,
  notFound,
  network,
  serviceUnavailable,
  invalidResponse,
  invalidSearch,
  unknown,
}

/// Stable presentation categories without server bodies, tokens, or SDK details.
final class MonitoringFailure implements Exception {
  const MonitoringFailure(this.code);

  final MonitoringFailureCode code;

  @override
  String toString() => 'MonitoringFailure(${code.name})';
}
