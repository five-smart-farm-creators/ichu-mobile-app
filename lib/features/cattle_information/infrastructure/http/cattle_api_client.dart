import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../iam/application/facades/authorized_ranch_session.dart';
import '../../domain/model/cattle.dart';
import '../../domain/model/cattle_commands.dart';
import '../../domain/model/cattle_date.dart';
import '../../domain/model/cattle_failure.dart';
import '../../domain/model/cattle_search.dart';

/// Sends ranch-scoped Cattle Information requests; writes are never retried.
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

    return _run(
      method: 'GET',
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
    return _run(
      method: 'GET',
      context: context,
      path: 'ranches/$ranchId/cattle/$cattleId',
    );
  }

  Future<Object?> register(
    String ranchId,
    CattleRegistration registration,
  ) async {
    _validateRanchId(ranchId);
    final context = _requireContext(ranchId);
    return _run(
      method: 'POST',
      context: context,
      path: 'ranches/$ranchId/cattle',
      body: <String, Object?>{
        'earTag': registration.normalizedEarTag,
        'breed': _breedName(registration.breed),
        'sex': _sexName(registration.sex),
        'birthDate': _dateText(registration.birthDate),
        'lifeStage': _stageName(registration.lifeStage),
      },
      expectedStatus: 201,
    );
  }

  Future<Object?> correct(
    String ranchId,
    String cattleId,
    String expectedVersion,
    CattleCorrection correction,
  ) async {
    _validateRanchId(ranchId);
    _validateWriteTarget(cattleId, expectedVersion);
    final context = _requireContext(ranchId);
    return _run(
      method: 'PUT',
      context: context,
      path: 'ranches/$ranchId/cattle/$cattleId',
      body: <String, Object?>{
        'earTag': correction.normalizedEarTag,
        'breed': _breedName(correction.breed),
        'sex': _sexName(correction.sex),
        'birthDate': _dateText(correction.birthDate),
        'expectedVersion': expectedVersion,
      },
    );
  }

  Future<Object?> changeStage(
    String ranchId,
    String cattleId,
    String expectedVersion,
    CattleStageChange change,
  ) async {
    _validateRanchId(ranchId);
    _validateWriteTarget(cattleId, expectedVersion);
    final context = _requireContext(ranchId);
    return _run(
      method: 'PATCH',
      context: context,
      path: 'ranches/$ranchId/cattle/$cattleId/life-stage',
      body: <String, Object?>{
        'lifeStage': _stageName(change.stage),
        'validFrom': _dateText(change.validFrom),
        'expectedVersion': expectedVersion,
      },
    );
  }

  Future<Object?> deactivate(
    String ranchId,
    String cattleId,
    String expectedVersion,
    CattleExit exit,
  ) async {
    _validateRanchId(ranchId);
    _validateWriteTarget(cattleId, expectedVersion);
    final context = _requireContext(ranchId);
    return _run(
      method: 'POST',
      context: context,
      path: 'ranches/$ranchId/cattle/$cattleId/deactivations',
      body: <String, Object?>{
        'reason': _exitReasonName(exit.reason),
        'exitDate': _dateText(exit.exitDate),
        'expectedVersion': expectedVersion,
      },
    );
  }

  Future<Object?> _run({
    required AuthorizedRanchContext context,
    required String method,
    required String path,
    Map<String, String>? queryParameters,
    Map<String, Object?>? body,
    int expectedStatus = 200,
  }) async {
    // Writes are never retried because the API has no idempotency key.
    final isWrite = method != 'GET';
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

    final request = http.Request(method, uri)
      ..followRedirects = false
      ..maxRedirects = 0
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'application/json'
      ..headers['Accept-Language'] = language;
    if (body != null) {
      request
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
    }

    // The session is rechecked immediately before handing the bearer request
    // to the HTTP client, and again after its entire response body is read.
    _ensureCurrent(context);
    final response = await _sendAndRead(request, isWrite: isWrite);
    _ensureCurrent(context);
    if (response.statusCode != expectedStatus) {
      throw isWrite
          ? _failureForWrite(response)
          : _failureForStatus(response.statusCode);
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

  Future<_FetchedResponse> _sendAndRead(
    http.Request request, {
    required bool isWrite,
  }) async {
    final stopwatch = Stopwatch()..start();
    // Once a write is handed to the client the server may already have applied it.
    final transportFailure = isWrite
        ? CattleFailureCode.outcomeUnknown
        : CattleFailureCode.network;
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
      throw CattleFailure(transportFailure);
    } on http.ClientException {
      throw CattleFailure(transportFailure);
    } on IOException {
      throw CattleFailure(transportFailure);
    } on CattleFailure {
      rethrow;
    } catch (_) {
      throw CattleFailure(
        isWrite ? CattleFailureCode.outcomeUnknown : CattleFailureCode.unknown,
      );
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

  void _validateWriteTarget(String cattleId, String expectedVersion) {
    if (!_isNonzeroUuid(cattleId)) {
      throw const CattleFailure(CattleFailureCode.notFound);
    }
    if (!_isNonzeroUuid(expectedVersion)) {
      throw const CattleFailure(CattleFailureCode.invalidInput);
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

  CattleFailure _failureForWrite(_FetchedResponse response) {
    final statusCode = response.statusCode;
    if (statusCode >= 200 && statusCode <= 299) {
      return const CattleFailure(CattleFailureCode.invalidResponse);
    }
    if (statusCode == 400) {
      return const CattleFailure(CattleFailureCode.invalidInput);
    }
    if (statusCode == 409) {
      return CattleFailure(_conflictCode(response.body));
    }
    return _failureForStatus(statusCode);
  }

  /// Only the stable codes listed here change the message; other conflicts mean the snapshot is stale.
  CattleFailureCode _conflictCode(List<int>? body) {
    if (body == null) return CattleFailureCode.versionConflict;
    final Object? payload;
    try {
      payload = jsonDecode(utf8.decode(body));
    } on FormatException {
      return CattleFailureCode.versionConflict;
    }
    if (payload is! Map<String, dynamic>) {
      return CattleFailureCode.versionConflict;
    }
    return switch (payload['code']) {
      'CattleInformation.DuplicateEarTag' => CattleFailureCode.duplicateEarTag,
      'CattleInformation.CattleInactive' => CattleFailureCode.inactive,
      'CattleInformation.LifeStageAlreadyCurrent' =>
        CattleFailureCode.stageAlreadyCurrent,
      _ => CattleFailureCode.versionConflict,
    };
  }

  String _breedName(CattleBreed value) => switch (value) {
    CattleBreed.brownSwiss => 'BrownSwiss',
    CattleBreed.fleckvieh => 'Fleckvieh',
    CattleBreed.criollo => 'Criollo',
    CattleBreed.crossbred => 'Crossbred',
  };

  String _sexName(CattleSex value) => switch (value) {
    CattleSex.female => 'Female',
    CattleSex.male => 'Male',
  };

  String _stageName(CattleStage value) => switch (value) {
    CattleStage.calf => 'Calf',
    CattleStage.heifer => 'Heifer',
    CattleStage.milkingCow => 'MilkingCow',
    CattleStage.fatteningBull => 'FatteningBull',
  };

  String _exitReasonName(CattleExitReason value) => switch (value) {
    CattleExitReason.death => 'Death',
    CattleExitReason.sale => 'Sale',
    CattleExitReason.theft => 'Theft',
    CattleExitReason.culling => 'Culling',
  };

  String _dateText(CattleDate value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

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
