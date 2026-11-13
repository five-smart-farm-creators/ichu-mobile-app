enum HerdAdvisoryFailureCode {
  configuration,
  contextUnavailable,
  invalidRequest,
  unauthenticated,
  forbidden,
  notFound,
  network,
  serviceUnavailable,
  invalidResponse,
  unknown,
}

/// A stable failure category that excludes transport and identity details.
final class HerdAdvisoryFailure implements Exception {
  const HerdAdvisoryFailure(this.code);

  final HerdAdvisoryFailureCode code;

  @override
  String toString() => 'HerdAdvisoryFailure(${code.name})';
}
