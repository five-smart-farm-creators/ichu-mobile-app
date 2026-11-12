import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../iam/application/facades/authorized_ranch_session.dart';
import '../../domain/model/cattle.dart';
import '../../domain/model/cattle_failure.dart';
import '../../domain/model/cattle_search.dart';

/// Sends only the ranch-scoped Cattle Information GET requests.
final class CattleApiClient {
  CattleApiClient({
    required Uri baseUri,
    required this._client,
    required this._session,
    required this._languageTag,
    this._timeout = const Duration(seconds: 15),
  }) : _baseUri = _validateBaseUri(baseUri) {
    if (_timeout <= Duration.zero) {
      throw const CattleFailure(CattleFailureCode.configuration);
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

  Future<Object?> search(String ranchId, CattleSearch query) async {
    if (!query.isValid) {
      throw const CattleFailure(CattleFailureCode.invalidSearch);
    }
    _validateRanchId(ranchId);
    final context = _requireContext(ranchId);
    final queryParameters = <String, String>{
      'page': query.page.toString(),
      'pageSize': query.pageSize.toString(),
    };
    final earTag = query.earTag.trim();
    if (earTag.isNotEmpty) queryParameters['earTag'] = earTag;
    final status = query.status;
    if (status != null) queryParameters['status'] = _statusName(status);

    return _runGet(
      context: context,
      path: 'ranches/$ranchId/cattle',
      queryParameters: queryParameters,
    );
  }

  Future<Object?> profile(String ranchId, String cattleId) async {
    _validateRanchId(ranchId);
    if (!_isNonzeroUuid(cattleId)) {
      throw const CattleFailure(CattleFailureCode.notFound);
    }
    final context = _requireContext(ranchId);
    return _runGet(context: context, path: 'ranches/$ranchId/cattle/$cattleId');
  }

  Future<Object?> _runGet({
    required AuthorizedRanchContext context,
    required String path,
    Map<String, String>? queryParameters,
  }) async {
    if (!_session.isConfigured) {
      throw const CattleFailure(CattleFailureCode.configuration);
    }
    _ensureCurrent(context);

    final String language;
    try {
      language = _languageTag();
    } catch (_) {
      throw const CattleFailure(CattleFailureCode.unknown);
    }
    if (language.isEmpty ||
        language.contains('\r') ||
        language.contains('\n')) {
      throw const CattleFailure(CattleFailureCode.unknown);
    }

    final Uri uri;
    try {
      uri = _baseUri.replace(
        path: '${_baseUri.path}/$path',
        queryParameters: queryParameters,
      );
    } catch (_) {
      throw const CattleFailure(CattleFailureCode.unknown);
    }
    if (!_isSameOriginUri(uri, path, queryParameters)) {
      throw const CattleFailure(CattleFailureCode.unknown);
    }

    final token = await _tokenFor(context);
    if (token.trim().isEmpty || token.contains(RegExp(r'\s'))) {
      throw const CattleFailure(CattleFailureCode.unknown);
    }
    _ensureCurrent(context);

    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..maxRedirects = 0
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'application/json'
      ..headers['Accept-Language'] = language;

    // The session is rechecked immediately before handing the bearer request
    // to the HTTP client, and again after its entire response body is read.
    _ensureCurrent(context);
    final response = await _sendAndRead(request);
    _ensureCurrent(context);
    if (response.statusCode != 200) {
      throw _failureForStatus(response.statusCode);
    }
    final bytes = response.body;
    if (bytes == null) {
      throw const CattleFailure(CattleFailureCode.invalidResponse);
    }
    try {
      return jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const CattleFailure(CattleFailureCode.invalidResponse);
    }
  }

  Future<String> _tokenFor(AuthorizedRanchContext context) async {
    try {
      return await _session.idTokenFor(context);
    } on RanchSessionFailure catch (failure) {
      throw CattleFailure(switch (failure.code) {
        RanchSessionFailureCode.configuration =>
          CattleFailureCode.configuration,
        RanchSessionFailureCode.unavailable =>
          CattleFailureCode.contextUnavailable,
        RanchSessionFailureCode.network => CattleFailureCode.network,
        RanchSessionFailureCode.serviceUnavailable =>
          CattleFailureCode.serviceUnavailable,
      });
    } catch (_) {
      throw const CattleFailure(CattleFailureCode.unknown);
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
      throw const CattleFailure(CattleFailureCode.network);
    } on http.ClientException {
      throw const CattleFailure(CattleFailureCode.network);
    } on IOException {
      throw const CattleFailure(CattleFailureCode.network);
    } on CattleFailure {
      rethrow;
    } catch (_) {
      throw const CattleFailure(CattleFailureCode.unknown);
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
      await iterator.cancel();
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
      throw const CattleFailure(CattleFailureCode.contextUnavailable);
    }
  }

  AuthorizedRanchContext _requireContext(String ranchId) {
    if (!_session.isConfigured) {
      throw const CattleFailure(CattleFailureCode.configuration);
    }
    final context = _session.context;
    if (context == null ||
        !_isNonzeroUuid(context.ranchId) ||
        !_sameUuid(context.ranchId, ranchId) ||
        !_session.isCurrent(context)) {
      throw const CattleFailure(CattleFailureCode.contextUnavailable);
    }
    return context;
  }

  void _ensureCurrent(AuthorizedRanchContext context) {
    if (!_session.isCurrent(context)) {
      throw const CattleFailure(CattleFailureCode.contextUnavailable);
    }
  }

  bool _isSameOriginUri(
    Uri uri,
    String path,
    Map<String, String>? queryParameters,
  ) =>
      uri.scheme == _baseUri.scheme &&
      uri.host == _baseUri.host &&
      uri.port == _baseUri.port &&
      uri.userInfo.isEmpty &&
      uri.path == '${_baseUri.path}/$path' &&
      uri.hasFragment == false &&
      (queryParameters == null
          ? !uri.hasQuery
          : uri.queryParametersAll.length == queryParameters.length &&
                queryParameters.entries.every(
                  (entry) =>
                      uri.queryParametersAll[entry.key]?.length == 1 &&
                      uri.queryParametersAll[entry.key]!.single == entry.value,
                ));

  CattleFailure _failureForStatus(int statusCode) => switch (statusCode) {
    400 => const CattleFailure(CattleFailureCode.invalidSearch),
    401 => const CattleFailure(CattleFailureCode.unauthenticated),
    403 => const CattleFailure(CattleFailureCode.forbidden),
    404 => const CattleFailure(CattleFailureCode.notFound),
    429 => const CattleFailure(CattleFailureCode.serviceUnavailable),
    >= 500 && <= 599 => const CattleFailure(
      CattleFailureCode.serviceUnavailable,
    ),
    _ => const CattleFailure(CattleFailureCode.unknown),
  };

  String _statusName(CattleStatus status) => switch (status) {
    CattleStatus.active => 'Active',
    CattleStatus.inactive => 'Inactive',
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
      throw const CattleFailure(CattleFailureCode.configuration);
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
