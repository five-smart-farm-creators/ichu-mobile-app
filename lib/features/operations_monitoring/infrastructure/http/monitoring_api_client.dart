import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../iam/application/facades/authorized_ranch_session.dart';
import '../../domain/model/alert_acknowledgement.dart';
import '../../domain/model/alert_search.dart';
import '../../domain/model/field_record.dart';
import '../../domain/model/field_record_sync.dart';
import '../../domain/repositories/field_record_sync_repository.dart';
import '../../domain/model/ranch_alert.dart';
import '../../domain/model/monitoring_failure.dart';
import '../../domain/model/telemetry_history_query.dart';

/// Sends authorized ranch-scoped Operations Monitoring requests.
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

  /// Sends one selected-ranch batch, never replaying it automatically.
  Future<Object?> synchronizeFieldRecords({
    required String accountId,
    required String ranchId,
    required List<FieldRecord> records,
  }) async {
    final batch = List<FieldRecord>.unmodifiable(records);
    if (batch.isEmpty ||
        batch.length > FieldRecordSyncRepository.batchSize ||
        batch.any((record) => !_sameUuid(record.ranchId, ranchId)) ||
        batch.map((record) => record.operationId).toSet().length !=
            batch.length) {
      throw const FieldRecordSyncFailure(
        FieldRecordSyncFailureCode.invalidBatch,
      );
    }
    _validateRanchId(ranchId);
    final context = _requireContext(ranchId);
    if (!_sameUuid(context.accountId, accountId)) {
      throw const MonitoringFailure(MonitoringFailureCode.contextUnavailable);
    }
    if (!context.canManage) {
      throw const MonitoringFailure(MonitoringFailureCode.forbidden);
    }
    final response = await _requestJson(
      context,
      'POST',
      'mobile-sync/batch',
      body: {
        'operations': batch
            .map(
              (record) => <String, Object?>{
                'operationId': record.operationId,
                'cattleId': record.cattleId,
                'type': switch (record.type) {
                  FieldRecordType.healthEvent => 'HealthEvent',
                  FieldRecordType.birth => 'Birth',
                  FieldRecordType.naturalMating => 'NaturalMating',
                  FieldRecordType.abortion => 'Abortion',
                  FieldRecordType.heatObserved => 'HeatObserved',
                },
                'occurredAt': record.occurredAt.toUtc().toIso8601String(),
                if (record.observation != null)
                  'observation': record.observation,
                if (record.sireReference != null)
                  'sireReference': record.sireReference,
              },
            )
            .toList(growable: false),
      },
    );
    if (response.statusCode == 400) {
      throw const FieldRecordSyncFailure(
        FieldRecordSyncFailureCode.invalidBatch,
      );
    }
    if (response.statusCode != 200) {
      throw _failureForStatus(response.statusCode);
    }
    return response.payload;
  }

  Future<Object?> latest(String ranchId, String cattleId) async {
    _validateRanchId(ranchId);
    if (!_isNonzeroUuid(cattleId)) {
      throw const MonitoringFailure(MonitoringFailureCode.notFound);
    }
    final context = _requireContext(ranchId);
    final path = 'ranches/$ranchId/cattle/$cattleId/telemetry/latest';
    return _get(context, path);
  }

  Future<Object?> history(
    String ranchId,
    String cattleId,
    TelemetryHistoryQuery query,
  ) async {
    _validateRanchId(ranchId);
    if (!_isNonzeroUuid(cattleId)) {
      throw const MonitoringFailure(MonitoringFailureCode.notFound);
    }
    if (!query.isValid) {
      throw const MonitoringFailure(MonitoringFailureCode.invalidHistoryQuery);
    }
    final context = _requireContext(ranchId);
    final path = 'ranches/$ranchId/cattle/$cattleId/telemetry';
    return _get(
      context,
      path,
      queryParameters: <String, String>{
        'from': query.from.toUtc().toIso8601String(),
        'to': query.to.toUtc().toIso8601String(),
        'page': query.page.toString(),
        'pageSize': query.pageSize.toString(),
      },
      isTelemetryHistory: true,
    );
  }

  Future<Object?> alerts(String ranchId, AlertSearch query) async {
    _validateRanchId(ranchId);
    if (!query.isValid) {
      throw const MonitoringFailure(MonitoringFailureCode.invalidSearch);
    }
    final context = _requireContext(ranchId);
    final queryParameters = <String, String>{
      'page': query.page.toString(),
      'pageSize': query.pageSize.toString(),
      if (query.status != null)
        'status': switch (query.status!) {
          AlertStatus.pending => 'Pending',
          AlertStatus.acknowledged => 'Acknowledged',
        },
    };
    return _get(
      context,
      'ranches/$ranchId/alerts',
      queryParameters: queryParameters,
      isAlertList: true,
    );
  }

  Future<({int statusCode, Object? payload})> acknowledgeAlert(
    String ranchId,
    AlertAcknowledgement acknowledgement,
  ) async {
    _validateRanchId(ranchId);
    if (!_isNonzeroUuid(acknowledgement.alertId) ||
        !_isNonzeroUuid(acknowledgement.operationId) ||
        acknowledgement.expectedVersion < 1 ||
        acknowledgement.expectedVersion > AlertSearch.maximumInt32 ||
        acknowledgement.finding.trim().isEmpty ||
        acknowledgement.finding.length > 400 ||
        (acknowledgement.action?.length ?? 0) > 400) {
      throw const MonitoringFailure(
        MonitoringFailureCode.invalidAcknowledgement,
      );
    }
    final context = _requireContext(ranchId);
    final response = await _requestJson(
      context,
      'PATCH',
      'ranches/$ranchId/alerts/${acknowledgement.alertId}',
      body: <String, Object?>{
        'status': 'Acknowledged',
        'finding': acknowledgement.finding,
        if (acknowledgement.action != null) 'action': acknowledgement.action,
        'operationId': acknowledgement.operationId,
        'expectedVersion': acknowledgement.expectedVersion,
      },
    );
    if (response.statusCode == 200 || response.statusCode == 409) {
      return response;
    }
    throw _failureForStatus(response.statusCode, isAcknowledgement: true);
  }

  Future<Object?> _get(
    AuthorizedRanchContext context,
    String path, {
    Map<String, String>? queryParameters,
    bool isAlertList = false,
    bool isTelemetryHistory = false,
  }) async {
    final response = await _requestJson(
      context,
      'GET',
      path,
      queryParameters: queryParameters,
    );
    if (response.statusCode != 200) {
      throw _failureForStatus(
        response.statusCode,
        isAlertList: isAlertList,
        isTelemetryHistory: isTelemetryHistory,
      );
    }
    final payload = response.payload;
    if (payload == null) {
      throw const MonitoringFailure(MonitoringFailureCode.invalidResponse);
    }
    return payload;
  }

  Future<({int statusCode, Object? payload})> _requestJson(
    AuthorizedRanchContext context,
    String method,
    String path, {
    Map<String, String>? queryParameters,
    Map<String, Object?>? body,
  }) async {
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

    final Uri uri;
    try {
      uri = _baseUri.replace(
        path: '${_baseUri.path}/$path',
        queryParameters: queryParameters,
      );
    } catch (_) {
      throw const MonitoringFailure(MonitoringFailureCode.unknown);
    }
    if (!_isSameOriginUri(uri, path, queryParameters)) {
      throw const MonitoringFailure(MonitoringFailureCode.unknown);
    }

    final token = await _tokenFor(context);
    if (token.trim().isEmpty || token.contains(RegExp(r'\s'))) {
      throw const MonitoringFailure(MonitoringFailureCode.unknown);
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

    _ensureCurrent(context);
    final response = await _sendAndRead(request);
    _ensureCurrent(context);
    final bytes = response.body;
    if (response.statusCode != 200 && response.statusCode != 409) {
      return (statusCode: response.statusCode, payload: null);
    }
    if (bytes == null) {
      if (response.statusCode == 409) {
        return (statusCode: response.statusCode, payload: null);
      }
      throw const MonitoringFailure(MonitoringFailureCode.invalidResponse);
    }
    try {
      return (
        statusCode: response.statusCode,
        payload: jsonDecode(utf8.decode(bytes)),
      );
    } on FormatException {
      if (response.statusCode == 409) {
        return (statusCode: response.statusCode, payload: null);
      }
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
      _hasExactQuery(uri, queryParameters) &&
      !uri.hasFragment;

  bool _hasExactQuery(Uri uri, Map<String, String>? expected) {
    if (expected == null) return !uri.hasQuery;
    final actual = uri.queryParameters;
    if (actual.length != expected.length) return false;
    for (final entry in expected.entries) {
      if (actual[entry.key] != entry.value) return false;
    }
    return true;
  }

  MonitoringFailure _failureForStatus(
    int statusCode, {
    bool isAlertList = false,
    bool isTelemetryHistory = false,
    bool isAcknowledgement = false,
  }) => switch (statusCode) {
    400 when isAlertList => const MonitoringFailure(
      MonitoringFailureCode.invalidSearch,
    ),
    400 when isAcknowledgement => const MonitoringFailure(
      MonitoringFailureCode.invalidAcknowledgement,
    ),
    400 when isTelemetryHistory => const MonitoringFailure(
      MonitoringFailureCode.invalidHistoryQuery,
    ),
    400 => const MonitoringFailure(MonitoringFailureCode.unknown),
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
