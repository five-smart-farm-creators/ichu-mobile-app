import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ichu_mobile_app/features/iam/application/facades/authorized_ranch_session.dart';
import 'package:ichu_mobile_app/features/iam/application/services/auth_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/authentication_lifecycle.dart';
import 'package:ichu_mobile_app/features/iam/application/services/ranch_selection_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/herd_advisory.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/herd_advisory_failure.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_access.dart';
import 'package:ichu_mobile_app/features/iam/infrastructure/http/authenticated_api_client.dart';
import 'package:ichu_mobile_app/features/iam/infrastructure/http/herd_advisory_api_client.dart';
import 'package:ichu_mobile_app/features/iam/infrastructure/repositories/rest_herd_advisory_repository.dart';

import '../../../support/fake_iam_repositories.dart';

const _ranchId = '11111111-1111-4111-8111-111111111111';
const _advisoryId = '22222222-2222-4222-8222-222222222222';
const _veterinarianId = '33333333-3333-4333-8333-333333333333';
const _owner = IamAccount(
  id: '44444444-4444-4444-8444-444444444444',
  email: 'user@example.test',
  role: AccountRole.ranchManager,
  status: 'Active',
);
const _ranch = RanchAccess(
  ranchId: _ranchId,
  scope: AccessScope.manage,
  name: 'North ranch',
  region: 'Cusco',
  district: 'Anta',
);

void main() {
  test('maps all advisory operations to the backend REST contract', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/api/v1/ranches') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'ranchId': _ranchId,
            'name': 'North ranch',
            'region': 'Cusco',
            'district': 'Anta',
            'accessCode': 'not-retained',
          }),
          200,
        );
      }
      if (request.method == 'GET') {
        return http.Response('[]', 200);
      }
      final isGrant =
          request.method == 'PATCH' || request.url.path.endsWith('/grants');
      final status = isGrant ? 'Granted' : 'Pending';
      final scope = request.url.path.endsWith('/grants')
          ? 'Read'
          : 'ClinicalWrite';
      return http.Response(
        jsonEncode(_advisoryPayload(status: status, scope: scope)),
        request.method == 'PATCH' ? 200 : 201,
      );
    });
    final fixture = await _Fixture.create(client);
    addTearDown(fixture.dispose);

    final ranch = await fixture.repository.findRanchByAccessCode('A&B Code');
    final requested = await fixture.repository.requestAccess(
      ranchId: _ranchId,
      reason: 'Herd health review',
    );
    final history = await fixture.repository.advisoriesForRanch(_ranchId);
    final decided = await fixture.repository.decide(
      ranchId: _ranchId,
      advisoryId: _advisoryId,
      decision: HerdAdvisoryDecision.grant,
      scope: AccessScope.clinicalWrite,
      expiresAt: DateTime.utc(2027, 1, 2, 23, 59, 59),
    );
    final directGrant = await fixture.repository.grantDirectly(
      ranchId: _ranchId,
      veterinarianId: _veterinarianId,
      scope: AccessScope.read,
      expiresAt: DateTime.utc(2027, 2, 3, 23, 59, 59),
    );

    expect(ranch.ranchId, _ranchId);
    expect(requested.status, HerdAdvisoryStatus.pending);
    expect(history, isEmpty);
    expect(decided.status, HerdAdvisoryStatus.granted);
    expect(directGrant.status, HerdAdvisoryStatus.granted);
    expect(directGrant.scope, AccessScope.read);
    expect(requests.map((request) => request.method), <String>[
      'GET',
      'POST',
      'GET',
      'PATCH',
      'POST',
    ]);
    expect(requests.map((request) => request.url.path), <String>[
      '/api/v1/ranches',
      '/api/v1/ranches/$_ranchId/herd-advisories',
      '/api/v1/ranches/$_ranchId/herd-advisories',
      '/api/v1/ranches/$_ranchId/herd-advisories/$_advisoryId',
      '/api/v1/ranches/$_ranchId/herd-advisories/grants',
    ]);
    expect(requests.first.url.queryParameters, <String, String>{
      'accessCode': 'A&B Code',
    });
    expect(jsonDecode(requests[1].body), <String, Object?>{
      'reason': 'Herd health review',
    });
    expect(jsonDecode(requests[3].body), <String, Object?>{
      'decision': 'grant',
      'scope': 'ClinicalWrite',
      'expiresAt': '2027-01-02T23:59:59.000Z',
    });
    expect(jsonDecode(requests[4].body), <String, Object?>{
      'veterinarianId': _veterinarianId,
      'scope': 'Read',
      'expiresAt': '2027-02-03T23:59:59.000Z',
    });
    expect(
      requests.every(
        (request) =>
            request.headers['authorization'] == 'Bearer synthetic-token' &&
            !request.followRedirects,
      ),
      isTrue,
    );
  });

  test('maps forbidden responses safely without retrying', () async {
    var requestCount = 0;
    final client = MockClient((_) async {
      requestCount++;
      return http.Response('private server detail', 403);
    });
    final fixture = await _Fixture.create(client);
    addTearDown(fixture.dispose);

    await expectLater(
      fixture.repository.advisoriesForRanch(_ranchId),
      throwsA(
        isA<HerdAdvisoryFailure>().having(
          (failure) => failure.code,
          'code',
          HerdAdvisoryFailureCode.forbidden,
        ),
      ),
    );
    expect(requestCount, 1);
    expect(fixture.identity.idTokenCalls, 1);
  });
}

Map<String, Object?> _advisoryPayload({
  required String status,
  required String scope,
}) => <String, Object?>{
  'id': _advisoryId,
  'veterinarianId': _veterinarianId,
  'ranchId': _ranchId,
  'reason': 'Herd health review',
  'status': status,
  'scope': scope,
  'requestedAt': '2026-11-13T12:00:00Z',
  'grantedAt': status == 'Granted' ? '2026-11-13T12:05:00Z' : null,
  'expiresAt': status == 'Granted' ? '2027-01-02T23:59:59Z' : null,
  'endedAt': null,
};

final class _Fixture {
  _Fixture({
    required this.client,
    required this.identity,
    required this.lifecycle,
    required this.authentication,
    required this.selection,
    required this.ranchSession,
    required this.repository,
  });

  final http.Client client;
  final FakeAuthenticationRepository identity;
  final AuthenticationLifecycle lifecycle;
  final AuthService authentication;
  final RanchSelectionService selection;
  final AuthorizedRanchSession ranchSession;
  final RestHerdAdvisoryRepository repository;

  static Future<_Fixture> create(http.Client client) async {
    final identity = FakeAuthenticationRepository();
    final lifecycle = AuthenticationLifecycle(identity);
    final authentication = AuthService(
      authentication: lifecycle,
      accounts: FakeAccountRepository(account: _owner, ranches: const [_ranch]),
    );
    await authentication.initialize();
    final selection = RanchSelectionService(session: authentication);
    selection.select(_ranchId);
    final ranchSession = AuthorizedRanchSession(
      session: authentication,
      selection: selection,
      authentication: lifecycle,
    );
    final api = AuthenticatedApiClient(
      baseUri: Uri.parse('https://api.example.test/api/v1'),
      client: client,
      authentication: lifecycle,
      languageTag: () => 'en-US',
    );
    final repository = RestHerdAdvisoryRepository(
      api: HerdAdvisoryApiClient(api: api, session: ranchSession),
    );
    return _Fixture(
      client: client,
      identity: identity,
      lifecycle: lifecycle,
      authentication: authentication,
      selection: selection,
      ranchSession: ranchSession,
      repository: repository,
    );
  }

  Future<void> dispose() async {
    ranchSession.dispose();
    selection.dispose();
    authentication.dispose();
    lifecycle.dispose();
    client.close();
    await identity.close();
  }
}
