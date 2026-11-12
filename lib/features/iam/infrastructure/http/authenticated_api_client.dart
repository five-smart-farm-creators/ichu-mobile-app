import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../domain/model/auth_failure.dart';
import '../../domain/repositories/authentication_repository.dart';

/// Sends authenticated, same-origin GET requests to the configured API.
final class AuthenticatedApiClient {
  AuthenticatedApiClient({
    required Uri baseUri,
    required this._client,
    required this._authentication,
    required this._languageTag,
    this._timeout = const Duration(seconds: 15),
  }) : _baseUri = _validateBaseUri(baseUri) {
    if (_timeout <= Duration.zero) {
      throw const AuthFailure(AuthFailureCode.configuration);
    }
  }

  static const _maxResponseBytes = 1024 * 1024;

  final Uri _baseUri;
  final http.Client _client;
  final AuthenticationRepository _authentication;
  final String Function() _languageTag;
  final Duration _timeout;

  /// Fetches one JSON resource without retaining or retrying an identity token.
  Future<Object?> getJson(String path) async {
    try {
      return await _getJson(path);
    } on AuthFailure {
      rethrow;
    } on TimeoutException {
      throw const AuthFailure(AuthFailureCode.network);
    } on http.ClientException {
      throw const AuthFailure(AuthFailureCode.network);
    } on IOException {
      throw const AuthFailure(AuthFailureCode.network);
    } catch (_) {
      throw const AuthFailure(AuthFailureCode.unknown);
    }
  }

  Future<Object?> _getJson(String path) async {
    final uri = _buildUri(path);
    if (!_authentication.isConfigured) {
      throw const AuthFailure(AuthFailureCode.configuration);
    }

    final identity = _authentication.currentUser;
    if (identity == null || identity.uid.isEmpty) {
      throw const AuthFailure(AuthFailureCode.accountUnavailable);
    }

    // Deliberately fetch on every call: Firebase handles refresh and a 401 is
    // an account/API rejection, not a signal to retry with another token.
    final token = await _authentication.idToken();
    if (_authentication.currentUser?.uid != identity.uid) {
      throw const AuthFailure(AuthFailureCode.accountUnavailable);
    }
    if (token.trim().isEmpty || token.contains(RegExp(r'\s'))) {
      throw const AuthFailure(AuthFailureCode.unknown);
    }

    final languageTag = _languageTag();
    if (languageTag.contains('\r') || languageTag.contains('\n')) {
      throw const AuthFailure(AuthFailureCode.unknown);
    }

    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'application/json'
      ..headers['Accept-Language'] = languageTag;

    if (_authentication.currentUser?.uid != identity.uid) {
      throw const AuthFailure(AuthFailureCode.accountUnavailable);
    }

    final response = await _sendAndRead(request);
    if (_authentication.currentUser?.uid != identity.uid) {
      throw const AuthFailure(AuthFailureCode.accountUnavailable);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _failureForResponse(response);
    }
    final bytes = response.body;
    if (bytes == null) {
      throw const AuthFailure(AuthFailureCode.invalidResponse);
    }

    try {
      return jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const AuthFailure(AuthFailureCode.invalidResponse);
    }
  }

  Future<_FetchedResponse> _sendAndRead(http.Request request) async {
    final stopwatch = Stopwatch()..start();
    final response = await _client.send(request).timeout(_timeout);

    List<int>? body;
    try {
      body = await _readBody(response.stream, stopwatch);
    } on _ResponseBodyTooLarge {
      // A known HTTP status still maps to its stable failure category. A
      // successful response without a bounded body is invalid.
      body = null;
    }

    return _FetchedResponse(statusCode: response.statusCode, body: body);
  }

  Future<List<int>> _readBody(
    Stream<List<int>> stream,
    Stopwatch stopwatch,
  ) async {
    final iterator = StreamIterator<List<int>>(stream);
    final bytes = BytesBuilder(copy: false);
    var length = 0;

    try {
      while (await iterator.moveNext().timeout(_remainingTimeout(stopwatch))) {
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

  Duration _remainingTimeout(Stopwatch stopwatch) {
    final remaining = _timeout - stopwatch.elapsed;
    if (remaining <= Duration.zero) throw TimeoutException('');
    return remaining;
  }

  AuthFailure _failureForResponse(_FetchedResponse response) {
    final statusCode = response.statusCode;
    if (statusCode == 401) {
      return AuthFailure(
        response.body != null && _isEmailNotVerified(response.body!)
            ? AuthFailureCode.emailNotVerified
            : AuthFailureCode.accountUnavailable,
      );
    }
    if (statusCode == 403) {
      return const AuthFailure(AuthFailureCode.forbidden);
    }
    if (statusCode == 429) {
      return const AuthFailure(AuthFailureCode.serviceUnavailable);
    }
    if (statusCode == 503 &&
        response.body != null &&
        _isIdentityProviderNotConfigured(response.body!)) {
      return const AuthFailure(AuthFailureCode.configuration);
    }
    if (statusCode >= 500 && statusCode <= 599) {
      return const AuthFailure(AuthFailureCode.serviceUnavailable);
    }
    return const AuthFailure(AuthFailureCode.unknown);
  }

  bool _isIdentityProviderNotConfigured(List<int> body) {
    try {
      final payload = jsonDecode(utf8.decode(body));
      return payload is Map<String, dynamic> &&
          payload['code'] == 'Iam.IdentityProviderNotConfigured';
    } catch (_) {
      return false;
    }
  }

  bool _isEmailNotVerified(List<int> body) {
    try {
      final payload = jsonDecode(utf8.decode(body));
      if (payload is! Map<String, dynamic>) return false;

      final candidates = <Object?>[
        payload['code'],
        payload['errorCode'],
        payload['error_code'],
      ];
      final error = payload['error'];
      if (error is String) {
        candidates.add(error);
      } else if (error is Map<String, dynamic>) {
        candidates
          ..add(error['code'])
          ..add(error['errorCode'])
          ..add(error['error_code']);
      }

      return candidates.any((candidate) {
        if (candidate is! String) return false;
        final normalized = candidate.toLowerCase().replaceAll('_', '-');
        return normalized == 'email-not-verified' ||
            normalized == 'emailnotverified';
      });
    } catch (_) {
      return false;
    }
  }

  Uri _buildUri(String path) {
    if (path.isEmpty ||
        path.startsWith('/') ||
        path.endsWith('/') ||
        path
            .split('/')
            .any((segment) => !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(segment))) {
      throw const AuthFailure(AuthFailureCode.unknown);
    }

    final uri = _baseUri.replace(path: '${_baseUri.path}/$path');
    if (uri.scheme != _baseUri.scheme ||
        uri.host != _baseUri.host ||
        uri.port != _baseUri.port ||
        uri.userInfo.isNotEmpty ||
        uri.path != '${_baseUri.path}/$path' ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const AuthFailure(AuthFailureCode.unknown);
    }
    return uri;
  }

  static Uri _validateBaseUri(Uri uri) {
    final host = uri.host.toLowerCase();
    final isDevelopmentLoopback =
        host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host == '10.0.2.2';
    if (!uri.hasAuthority ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        (uri.scheme == 'http' && !isDevelopmentLoopback) ||
        uri.authority.contains('@') ||
        uri.path != '/api/v1' ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const AuthFailure(AuthFailureCode.configuration);
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
