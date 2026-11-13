import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../iam/application/facades/authorized_ranch_session.dart';
import '../../domain/model/monitoring_failure.dart';

/// Sends the authorized ranch-scoped Operations Monitoring read request.
final class MonitoringApiClient {
  MonitoringApiClient({
    required Uri baseUri,
    required this._client,
    required this._session,
    required this._languageTag,
    this._timeout = const Duration(seconds: 15),
  }) : _baseUri = _validateBaseUri(baseUri) {
    if (_timeout <= Duration.zero) {
      throw const MonitoringFailure(MonitoringFailureCode.configuration);
    }
  }

  static const int _maxResponseBytes = 1024 * 1024;
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  final Uri _baseUri;
  final http.Client _client;
  final AuthorizedRanchSession _session;
  final String Function() _languageTag;
  final Duration _timeout;

  bool get isConfigured => _session.isConfigured;

  Future<Object?> latest(String ranchId, String cattleId) async {
    _validateRanchId(ranchId);
    if (!_isNonzeroUuid(cattleId)) {
      throw const MonitoringFailure(MonitoringFailureCode.notFound);
    }
    final context = _requireContext(ranchId);
    if (!_session.isConfigured) {
      throw const MonitoringFailure(MonitoringFailureCode.configuration);
    }
    _ensureCurrent(context);

    final String language;
    try {
      language = _languageTag();
    } catch (_) {
      throw const MonitoringFailure(MonitoringFailureCode.unknown);
    }
    if (language.isEmpty ||
        language.contains('\r') ||
        language.contains('\n')) {
      throw const MonitoringFailure(MonitoringFailureCode.unknown);
    }

    final path = 'ranches/$ranchId/cattle/$cattleId/telemetry/latest';
    final Uri uri;
    try {
      uri = _baseUri.replace(path: '${_baseUri.path}/$path');
    } catch (_) {
      throw const MonitoringFailure(MonitoringFailureCode.unknown);
    }
    if (!_isSameOriginUri(uri, path)) {
      throw const MonitoringFailure(MonitoringFailureCode.unknown);
    }

    final token = await _tokenFor(context);
    if (token.trim().isEmpty || token.contains(RegExp(r'\s'))) {
      throw const MonitoringFailure(MonitoringFailureCode.unknown);
    }
    _ensureCurrent(context);

    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..maxRedirects = 0
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'application/json'
      ..headers['Accept-Language'] = language;

    _ensureCurrent(context);
    final response = await _sendAndRead(request);
    _ensureCurrent(context);
    if (response.statusCode != 200) {
      throw _failureForStatus(response.statusCode);
    }
    final bytes = response.body;
    if (bytes == null) {
      throw const MonitoringFailure(MonitoringFailureCode.invalidResponse);
    }
    try {
      return jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const MonitoringFailure(MonitoringFailureCode.invalidResponse);
    }
  }

  Future<String> _tokenFor(AuthorizedRanchContext context) async {
    try {
      return await _session.idTokenFor(context);
    } on RanchSessionFailure catch (failure) {
      throw MonitoringFailure(switch (failure.code) {
        RanchSessionFailureCode.configuration =>
          MonitoringFailureCode.configuration,
        RanchSessionFailureCode.unavailable =>
          MonitoringFailureCode.contextUnavailable,
        RanchSessionFailureCode.network => MonitoringFailureCode.network,
        RanchSessionFailureCode.serviceUnavailable =>
          MonitoringFailureCode.serviceUnavailable,
      });
    } catch (_) {
      throw const MonitoringFailure(MonitoringFailureCode.unknown);
    }
  }

  Future<_FetchedResponse> _sendAndRead(http.Request request) async {
    final stopwatch = Stopwatch()..start();
    try {
      final streamed = await _client
          .send(request)
          .timeout(_remaining(stopwatch));
      List<int>? body;
      try {
        body = await _readBody(streamed.stream, stopwatch);
      } on _ResponseBodyTooLarge {
        body = null;
      }
      return _FetchedResponse(statusCode: streamed.statusCode, body: body);
    } on TimeoutException {
      throw const MonitoringFailure(MonitoringFailureCode.network);
    } on http.ClientException {
      throw const MonitoringFailure(MonitoringFailureCode.network);
    } on IOException {
      throw const MonitoringFailure(MonitoringFailureCode.network);
    } on MonitoringFailure {
      rethrow;
    } catch (_) {
      throw const MonitoringFailure(MonitoringFailureCode.unknown);
    }
  }

  Future<List<int>> _readBody(
    Stream<List<int>> stream,
    Stopwatch stopwatch,
  ) async {
    final iterator = StreamIterator<List<int>>(stream);
    final bytes = BytesBuilder(copy: false);
    var length = 0;
    try {
      while (await iterator.moveNext().timeout(_remaining(stopwatch))) {
        final chunk = iterator.current;
        if (chunk.length > _maxResponseBytes - length) {
          throw const _ResponseBodyTooLarge();
        }
        length += chunk.length;
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } catch (_) {
      // Cleanup must not extend the request deadline or mask its safe failure.
      unawaited(
        iterator.cancel().then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        ),
      );
      rethrow;
    }
  }

  Duration _remaining(Stopwatch stopwatch) {
    final remaining = _timeout - stopwatch.elapsed;
    if (remaining <= Duration.zero) throw TimeoutException('');
    return remaining;
  }

  void _validateRanchId(String value) {
    if (!_isNonzeroUuid(value)) {
      throw const MonitoringFailure(MonitoringFailureCode.contextUnavailable);
    }
  }

  AuthorizedRanchContext _requireContext(String ranchId) {
    if (!_session.isConfigured) {
      throw const MonitoringFailure(MonitoringFailureCode.configuration);
    }
    final context = _session.context;
    if (context == null ||
        !_isNonzeroUuid(context.ranchId) ||
        !_sameUuid(context.ranchId, ranchId) ||
        !_session.isCurrent(context)) {
      throw const MonitoringFailure(MonitoringFailureCode.contextUnavailable);
    }
    return context;
  }

  void _ensureCurrent(AuthorizedRanchContext context) {
    if (!_session.isCurrent(context)) {
      throw const MonitoringFailure(MonitoringFailureCode.contextUnavailable);
    }
  }

  bool _isSameOriginUri(Uri uri, String path) =>
      uri.scheme == _baseUri.scheme &&
      uri.host == _baseUri.host &&
      uri.port == _baseUri.port &&
      uri.userInfo.isEmpty &&
      uri.path == '${_baseUri.path}/$path' &&
      !uri.hasQuery &&
      !uri.hasFragment;

  MonitoringFailure _failureForStatus(int statusCode) => switch (statusCode) {
    401 => const MonitoringFailure(MonitoringFailureCode.unauthenticated),
    403 => const MonitoringFailure(MonitoringFailureCode.forbidden),
    404 => const MonitoringFailure(MonitoringFailureCode.notFound),
    429 => const MonitoringFailure(MonitoringFailureCode.serviceUnavailable),
    >= 500 && <= 599 => const MonitoringFailure(
      MonitoringFailureCode.serviceUnavailable,
    ),
    _ => const MonitoringFailure(MonitoringFailureCode.unknown),
  };

  bool _isNonzeroUuid(String value) =>
      _uuidPattern.hasMatch(value) &&
      value.replaceAll('-', '').replaceAll('0', '').isNotEmpty;

  bool _sameUuid(String left, String right) =>
      _uuidPattern.hasMatch(right) && left.toLowerCase() == right.toLowerCase();

  static Uri _validateBaseUri(Uri uri) {
    final host = uri.host.toLowerCase();
    final isDevelopmentLoopback =
        host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host == '10.0.2.2';
    if (!uri.hasAuthority ||
        host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        (uri.scheme == 'http' && !isDevelopmentLoopback) ||
        uri.authority.contains('@') ||
        uri.path != '/api/v1' ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const MonitoringFailure(MonitoringFailureCode.configuration);
    }
    return uri;
  }
}

final class _FetchedResponse {
  const _FetchedResponse({required this.statusCode, required this.body});

  final int statusCode;
  final List<int>? body;
}

final class _ResponseBodyTooLarge implements Exception {
  const _ResponseBodyTooLarge();
}
