import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_failure.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_user.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_access.dart';
import 'package:ichu_mobile_app/features/iam/domain/repositories/authentication_repository.dart';
import 'package:ichu_mobile_app/features/iam/infrastructure/http/authenticated_api_client.dart';
import 'package:ichu_mobile_app/features/iam/infrastructure/repositories/iam_account_repository.dart';

void main() {
  group('AuthenticatedApiClient', () {
    test(
      'sets authenticated JSON and language headers on every request',
      () async {
        final auth = _FakeAuthenticationRepository(user: _identity('uid-1'));
        final requests = <http.Request>[];
        var languageTag = 'es-419';
        final api = AuthenticatedApiClient(
          baseUri: Uri.parse('https://api.example.test/api/v1'),
          authentication: auth,
          languageTag: () => languageTag,
          client: MockClient((request) async {
            requests.add(request);
            return http.Response('{}', 200);
          }),
        );

        await api.getJson('accounts/me');
        languageTag = 'en-US';
        await api.getJson('accounts/me/ranches');

        expect(auth.tokenRequests, 2);
        expect(requests.map((request) => request.method), everyElement('GET'));
        expect(requests.map((request) => request.url.toString()), <String>[
          'https://api.example.test/api/v1/accounts/me',
          'https://api.example.test/api/v1/accounts/me/ranches',
        ]);
        expect(_header(requests[0], 'authorization'), 'Bearer token-1');
        expect(_header(requests[1], 'authorization'), 'Bearer token-2');
        expect(_header(requests[0], 'accept'), 'application/json');
        expect(_header(requests[1], 'accept'), 'application/json');
        expect(_header(requests[0], 'accept-language'), 'es-419');
        expect(_header(requests[1], 'accept-language'), 'en-US');
      },
    );

    test(
      'encodes advisory lookup codes only in the configured API query',
      () async {
        final auth = _FakeAuthenticationRepository(user: _identity('uid-1'));
        final requests = <http.Request>[];
        final api = _api(
          auth,
          MockClient((request) async {
            requests.add(request);
            return http.Response('{}', 200);
          }),
        );

        await api.getJson(
          'ranches',
          queryParameters: <String, String>{
            'accessCode': 'Case-Sensitive & code',
          },
        );

        expect(auth.tokenRequests, 1);
        expect(requests.single.url.origin, 'https://api.example.test');
        expect(requests.single.url.path, '/api/v1/ranches');
        expect(requests.single.url.queryParameters, <String, String>{
          'accessCode': 'Case-Sensitive & code',
        });
        expect(requests.single.followRedirects, isFalse);
      },
    );

    test('does not follow redirects with the bearer token attached', () async {
      var requestCount = 0;
      final api = _api(
        _FakeAuthenticationRepository(user: _identity('uid-1')),
        MockClient((request) async {
          requestCount++;
          expect(request.followRedirects, isFalse);
          expect(request.url.host, 'api.example.test');
          return http.Response(
            '',
            302,
            headers: {'location': 'https://other.example.test/collect'},
          );
        }),
      );

      await _expectFailure(api.getJson('accounts/me'), AuthFailureCode.unknown);
      expect(requestCount, 1);
    });

    test(
      'rejects absolute, traversal, query, and lookalike paths locally',
      () async {
        var requestCount = 0;
        final api = _api(
          _FakeAuthenticationRepository(user: _identity('uid-1')),
          MockClient((_) async {
            requestCount++;
            return http.Response('{}', 200);
          }),
        );

        for (final path in <String>[
          'https://evil.example/accounts/me',
          '//evil.example/accounts/me',
          '/accounts/me',
          '../accounts/me',
          'accounts/../me',
          'accounts/me?next=https://evil.example',
          'accounts/me#fragment',
          'accounts%2fme',
          'accounts/me/',
          'accounts/m.e',
        ]) {
          await _expectFailure(api.getJson(path), AuthFailureCode.unknown);
        }

        expect(requestCount, 0);
      },
    );

    test(
      'does not fetch a token or send HTTP without a current identity',
      () async {
        final auth = _FakeAuthenticationRepository();
        var requestCount = 0;
        final api = _api(
          auth,
          MockClient((_) async {
            requestCount++;
            return http.Response('{}', 200);
          }),
        );

        await _expectFailure(
          api.getJson('accounts/me'),
          AuthFailureCode.accountUnavailable,
        );
        expect(auth.tokenRequests, 0);
        expect(requestCount, 0);
      },
    );

    test('maps an unconfigured identity provider to configuration', () async {
      final auth = _FakeAuthenticationRepository(
        user: _identity('uid-1'),
        configured: false,
      );
      var requestCount = 0;
      final api = _api(
        auth,
        MockClient((_) async {
          requestCount++;
          return http.Response('{}', 200);
        }),
      );

      await _expectFailure(
        api.getJson('accounts/me'),
        AuthFailureCode.configuration,
      );
      expect(auth.tokenRequests, 0);
      expect(requestCount, 0);
    });

    test(
      'does not send a token if the identity changes during token fetch',
      () async {
        final auth = _FakeAuthenticationRepository(user: _identity('uid-1'));
        auth.onIdToken = () async {
          auth.user = _identity('uid-2');
        };
        var requestCount = 0;
        final api = _api(
          auth,
          MockClient((_) async {
            requestCount++;
            return http.Response('{}', 200);
          }),
        );

        await _expectFailure(
          api.getJson('accounts/me'),
          AuthFailureCode.accountUnavailable,
        );
        expect(requestCount, 0);
      },
    );

    test('rejects a response after the current identity changes', () async {
      final auth = _FakeAuthenticationRepository(user: _identity('uid-1'));
      final requestSeen = Completer<void>();
      final response = Completer<http.Response>();
      final api = _api(
        auth,
        MockClient((_) {
          requestSeen.complete();
          return response.future;
        }),
      );

      final result = api.getJson('accounts/me');
      await requestSeen.future;
      auth.user = _identity('uid-2');
      response.complete(http.Response('{}', 200));

      await _expectFailure(result, AuthFailureCode.accountUnavailable);
    });

    test('maps send and response-body timeouts to network failures', () async {
      final neverCompletes = Completer<http.Response>();
      final sendApi = _api(
        _FakeAuthenticationRepository(user: _identity('uid-1')),
        MockClient((_) => neverCompletes.future),
        timeout: const Duration(milliseconds: 20),
      );
      await _expectFailure(
        sendApi.getJson('accounts/me'),
        AuthFailureCode.network,
      );
      neverCompletes.complete(http.Response('{}', 200));

      final subscribed = Completer<void>();
      final bodyStream = StreamController<List<int>>(
        onListen: subscribed.complete,
      );
      final bodyApi = _api(
        _FakeAuthenticationRepository(user: _identity('uid-1')),
        _StreamClient(
          (_) async => http.StreamedResponse(bodyStream.stream, 200),
        ),
        timeout: const Duration(milliseconds: 20),
      );
      final bodyResult = bodyApi.getJson('accounts/me');
      await subscribed.future;
      await _expectFailure(bodyResult, AuthFailureCode.network);
      await bodyStream.close();
    });

    test(
      'maps malformed and oversized successful bodies to invalidResponse',
      () async {
        final malformedApi = _api(
          _FakeAuthenticationRepository(user: _identity('uid-1')),
          MockClient((_) async => http.Response('{broken', 200)),
        );
        await _expectFailure(
          malformedApi.getJson('accounts/me'),
          AuthFailureCode.invalidResponse,
        );

        final oversizedApi = _api(
          _FakeAuthenticationRepository(user: _identity('uid-1')),
          MockClient(
            (_) async => http.Response(
              String.fromCharCodes(List<int>.filled(1024 * 1024 + 1, 120)),
              200,
            ),
          ),
        );
        await _expectFailure(
          oversizedApi.getJson('accounts/me'),
          AuthFailureCode.invalidResponse,
        );
      },
    );

    test(
      'maps only stable status categories and recognized verification codes',
      () async {
        final cases = <(int, String, AuthFailureCode)>[
          (
            401,
            '{"code":"EMAIL_NOT_VERIFIED","title":"private"}',
            AuthFailureCode.emailNotVerified,
          ),
          (
            401,
            '{"title":"email not verified"}',
            AuthFailureCode.accountUnavailable,
          ),
          (403, '{"title":"private"}', AuthFailureCode.forbidden),
          (503, 'unavailable', AuthFailureCode.serviceUnavailable),
          (
            503,
            '{"title":"secret-backend-title"}',
            AuthFailureCode.serviceUnavailable,
          ),
          (429, '{"title":"rate limited"}', AuthFailureCode.serviceUnavailable),
          (500, '{"detail":"private"}', AuthFailureCode.serviceUnavailable),
          (404, '{"detail":"private"}', AuthFailureCode.unknown),
        ];

        for (final (status, body, code) in cases) {
          final api = _api(
            _FakeAuthenticationRepository(user: _identity('uid-1')),
            MockClient((_) async => http.Response(body, status)),
          );
          try {
            await api.getJson('accounts/me');
            fail('Expected AuthFailure($code)');
          } on AuthFailure catch (failure) {
            expect(failure.code, code);
            expect(failure.toString(), isNot(contains('private')));
            expect(failure.toString(), isNot(contains('secret-backend-title')));
          }
        }
      },
    );

    test(
      'maps the known 503 identity-provider code to configuration',
      () async {
        final api = _api(
          _FakeAuthenticationRepository(user: _identity('uid-1')),
          MockClient(
            (_) async => http.Response(
              '{"code":"Iam.IdentityProviderNotConfigured",'
              '"title":"do not expose this"}',
              503,
            ),
          ),
        );

        try {
          await api.getJson('accounts/me');
          fail('Expected a configuration failure');
        } on AuthFailure catch (failure) {
          expect(failure.code, AuthFailureCode.configuration);
          expect(failure.toString(), isNot(contains('do not expose this')));
        }
      },
    );

    test('does not retry a rate-limited request', () async {
      var requestCount = 0;
      final api = _api(
        _FakeAuthenticationRepository(user: _identity('uid-1')),
        MockClient((_) async {
          requestCount++;
          return http.Response('{}', 429);
        }),
      );

      await _expectFailure(
        api.getJson('accounts/me'),
        AuthFailureCode.serviceUnavailable,
      );
      expect(requestCount, 1);
    });

    test('does not retry an account rejection', () async {
      final auth = _FakeAuthenticationRepository(user: _identity('uid-1'));
      var requestCount = 0;
      final api = _api(
        auth,
        MockClient((_) async {
          requestCount++;
          return http.Response('{}', 401);
        }),
      );

      await _expectFailure(
        api.getJson('accounts/me'),
        AuthFailureCode.accountUnavailable,
      );
      expect(requestCount, 1);
      expect(auth.tokenRequests, 1);
    });

    test(
      'sends advisory POST and PATCH bodies once with a fresh token',
      () async {
        final auth = _FakeAuthenticationRepository(user: _identity('uid-1'));
        final requests = <http.Request>[];
        final api = _api(
          auth,
          MockClient((request) async {
            requests.add(request);
            return http.Response(
              '{"ok":true}',
              request.method == 'POST' ? 201 : 200,
            );
          }),
        );

        await api.postJson(
          'ranches/223e4567-e89b-12d3-a456-426614174000/herd-advisories',
          <String, Object?>{'reason': 'Herd health review'},
        );
        await api.patchJson(
          'ranches/223e4567-e89b-12d3-a456-426614174000/'
          'herd-advisories/323e4567-e89b-12d3-a456-426614174000',
          <String, Object?>{
            'decision': 'grant',
            'scope': 'Read',
            'expiresAt': '2027-01-02T23:59:59Z',
          },
        );

        expect(auth.tokenRequests, 2);
        expect(requests.map((request) => request.method), <String>[
          'POST',
          'PATCH',
        ]);
        expect(requests.map((request) => request.url.path), <String>[
          '/api/v1/ranches/223e4567-e89b-12d3-a456-426614174000/'
              'herd-advisories',
          '/api/v1/ranches/223e4567-e89b-12d3-a456-426614174000/'
              'herd-advisories/323e4567-e89b-12d3-a456-426614174000',
        ]);
        expect(jsonDecode(requests[0].body), <String, Object?>{
          'reason': 'Herd health review',
        });
        expect(jsonDecode(requests[1].body), <String, Object?>{
          'decision': 'grant',
          'scope': 'Read',
          'expiresAt': '2027-01-02T23:59:59Z',
        });
        expect(_header(requests[0], 'authorization'), 'Bearer token-1');
        expect(_header(requests[1], 'authorization'), 'Bearer token-2');
        expect(requests.every((request) => !request.followRedirects), isTrue);
      },
    );

    test('does not retry an advisory write rejected by the server', () async {
      final auth = _FakeAuthenticationRepository(user: _identity('uid-1'));
      var requestCount = 0;
      final api = _api(
        auth,
        MockClient((_) async {
          requestCount++;
          return http.Response('{}', 409);
        }),
      );

      await _expectFailure(
        api.postJson(
          'ranches/223e4567-e89b-12d3-a456-426614174000/'
          'herd-advisories',
          <String, Object?>{'reason': 'Review'},
        ),
        AuthFailureCode.unknown,
      );
      expect(requestCount, 1);
      expect(auth.tokenRequests, 1);
    });

    test('rejects a base URI outside the normalized API root', () {
      expect(
        () => AuthenticatedApiClient(
          baseUri: Uri.parse('https://api.example.test/api/v1/other'),
          client: MockClient((_) async => http.Response('{}', 200)),
          authentication: _FakeAuthenticationRepository(
            user: _identity('uid-1'),
          ),
          languageTag: () => 'en',
        ),
        throwsA(
          isA<AuthFailure>().having(
            (failure) => failure.code,
            'code',
            AuthFailureCode.configuration,
          ),
        ),
      );
    });
  });

  group('IamAccountRepository', () {
    test(
      'maps a valid account and tolerates extra profile properties',
      () async {
        final repository = IamAccountRepository(
          api: _api(
            _FakeAuthenticationRepository(user: _identity('uid-1')),
            MockClient((request) async {
              expect(request.url.path, '/api/v1/accounts/me');
              return http.Response(
                jsonEncode(<String, Object?>{
                  'id': '123e4567-e89b-12d3-a456-426614174000',
                  'email': 'vet@example.test',
                  'role': 'Veterinarian',
                  'status': 'Active',
                  'profile': <String, Object?>{
                    'specialty': 'Bovine health',
                    'licenseNumber': 'CMVP-123',
                    'yearsOfExperience': 5,
                    'displayLabel': 'Veterinary profile',
                  },
                }),
                200,
              );
            }),
          ),
        );

        final account = await repository.currentAccount();

        expect(repository.isConfigured, isTrue);
        expect(account.id, '123e4567-e89b-12d3-a456-426614174000');
        expect(account.email, 'vet@example.test');
        expect(account.role, AccountRole.veterinarian);
        expect(account.status, 'Active');
        expect(account.profile?.specialty, 'Bovine health');
        expect(account.profile?.licenseNumber, 'CMVP-123');
        expect(account.profile?.yearsOfExperience, 5);
      },
    );

    test('fails closed for malformed account and ranch DTOs', () async {
      final invalidAccount = IamAccountRepository(
        api: _api(
          _FakeAuthenticationRepository(user: _identity('uid-1')),
          MockClient(
            (_) async => http.Response(
              '{"id":"not-a-uuid","email":"a@example.test",'
              '"role":"RanchManager","status":"Active"}',
              200,
            ),
          ),
        ),
      );
      await _expectFailure(
        invalidAccount.currentAccount(),
        AuthFailureCode.invalidResponse,
      );

      final invalidRanches = IamAccountRepository(
        api: _api(
          _FakeAuthenticationRepository(user: _identity('uid-1')),
          MockClient(
            (_) async => http.Response(
              '[{"ranchId":"223e4567-e89b-12d3-a456-426614174000",'
              '"scope":"Admin"}]',
              200,
            ),
          ),
        ),
      );
      await _expectFailure(
        invalidRanches.ranchAccess(),
        AuthFailureCode.invalidResponse,
      );

      final invalidRanchId = IamAccountRepository(
        api: _api(
          _FakeAuthenticationRepository(user: _identity('uid-1')),
          MockClient(
            (_) async =>
                http.Response('[{"ranchId":"not-a-uuid","scope":"Read"}]', 200),
          ),
        ),
      );
      await _expectFailure(
        invalidRanchId.ranchAccess(),
        AuthFailureCode.invalidResponse,
      );

      final invalidExpiration = IamAccountRepository(
        api: _api(
          _FakeAuthenticationRepository(user: _identity('uid-1')),
          MockClient(
            (_) async => http.Response(
              '[{"ranchId":"223e4567-e89b-12d3-a456-426614174000",'
              '"scope":"Read","name":"North ranch","region":"Cusco",'
              '"district":"Anta","expiresAt":"2030-02-03T04:05:06"}]',
              200,
            ),
          ),
        ),
      );
      await _expectFailure(
        invalidExpiration.ranchAccess(),
        AuthFailureCode.invalidResponse,
      );
    });

    test(
      'returns an empty ranch list and maps required metadata and expiration',
      () async {
        final emptyRepository = IamAccountRepository(
          api: _api(
            _FakeAuthenticationRepository(user: _identity('uid-1')),
            MockClient((_) async => http.Response('[]', 200)),
          ),
        );
        expect(await emptyRepository.ranchAccess(), isEmpty);

        final repository = IamAccountRepository(
          api: _api(
            _FakeAuthenticationRepository(user: _identity('uid-1')),
            MockClient(
              (_) async => http.Response(
                '[{"ranchId":"223e4567-e89b-12d3-a456-426614174000",'
                '"scope":"ClinicalWrite","name":"North ranch",'
                '"region":"Cusco","district":"Anta",'
                '"expiresAt":"2030-02-03T04:05:06Z"}]',
                200,
              ),
            ),
          ),
        );

        final access = (await repository.ranchAccess()).single;
        expect(access.ranchId, '223e4567-e89b-12d3-a456-426614174000');
        expect(access.scope, AccessScope.clinicalWrite);
        expect(access.name, 'North ranch');
        expect(access.region, 'Cusco');
        expect(access.district, 'Anta');
        expect(access.expiresAt, DateTime.utc(2030, 2, 3, 4, 5, 6));
      },
    );

    test('reports configuration when no API client is provided', () async {
      final repository = IamAccountRepository(api: null);

      expect(repository.isConfigured, isFalse);
      await _expectFailure(
        repository.currentAccount(),
        AuthFailureCode.configuration,
      );
      await _expectFailure(
        repository.ranchAccess(),
        AuthFailureCode.configuration,
      );
    });

    test(
      'reads immutable authorized ranches without retaining access codes',
      () async {
        final requests = <http.Request>[];
        final repository = IamAccountRepository(
          api: _api(
            _FakeAuthenticationRepository(user: _identity('uid-1')),
            MockClient((request) async {
              requests.add(request);
              return http.Response(
                jsonEncode([
                  _ranchPayload()..addAll({
                    'scope': 'Manage',
                    'accessCode': 'synthetic-private-access-code',
                  }),
                ]),
                200,
              );
            }),
          ),
        );
        final ranches = await repository.ranchAccess();
        final request = requests.single;
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/accounts/me/ranches');
        expect(request.body, isEmpty);
        expect(request.followRedirects, isFalse);
        expect(ranches.single.scope, AccessScope.manage);
        expect(ranches.single.name, 'North ranch');
        expect(ranches.single.expiresAt, isNull);
        expect(() => ranches.clear(), throwsUnsupportedError);
        expect(
          ranches.single.toString(),
          isNot(contains('synthetic-private-access-code')),
        );
      },
    );

    test(
      'rejects missing or invalid required ranch metadata and duplicate IDs',
      () async {
        final invalid = <Object?>['not-a-ranch'];
        for (final (field, maxLength) in [
          ('name', 160),
          ('region', 120),
          ('district', 120),
        ]) {
          invalid.add(_ranchPayload()..remove(field));
          for (final value in <Object?>[null, ' ', 4, 'x' * (maxLength + 1)]) {
            invalid.add(_ranchPayload()..[field] = value);
          }
        }
        for (final payload in invalid) {
          final repository = IamAccountRepository(
            api: _api(
              _FakeAuthenticationRepository(user: _identity('uid-1')),
              MockClient(
                (_) async => http.Response(jsonEncode([payload]), 200),
              ),
            ),
          );
          await _expectFailure(
            repository.ranchAccess(),
            AuthFailureCode.invalidResponse,
          );
        }
        final duplicateRepository = IamAccountRepository(
          api: _api(
            _FakeAuthenticationRepository(user: _identity('uid-1')),
            MockClient(
              (_) async => http.Response(
                jsonEncode([
                  _ranchPayload(),
                  _ranchPayload()
                    ..['ranchId'] = '223E4567-E89B-12D3-A456-426614174000',
                ]),
                200,
              ),
            ),
          ),
        );
        await _expectFailure(
          duplicateRepository.ranchAccess(),
          AuthFailureCode.invalidResponse,
        );
      },
    );

    test(
      'keeps valid UTC and offset expiration instants and field bounds',
      () async {
        for (final expiration in [
          null,
          '2030-02-03T04:05:06Z',
          '2030-02-02T23:05:06-05:00',
          '2030-02-03T04:05:06.1234567+00:00',
        ]) {
          final repository = IamAccountRepository(
            api: _api(
              _FakeAuthenticationRepository(user: _identity('uid-1')),
              MockClient(
                (_) async => http.Response(
                  jsonEncode([
                    _ranchPayload()..addAll({
                      'name': 'n' * 160,
                      'region': 'r' * 120,
                      'district': 'd' * 120,
                      'expiresAt': expiration,
                    }),
                  ]),
                  200,
                ),
              ),
            ),
          );
          final access = (await repository.ranchAccess()).single;
          expect(access.name, 'n' * 160);
          expect(
            access.expiresAt,
            expiration == null ? null : DateTime.parse(expiration),
          );
          if (access.expiresAt != null) expect(access.expiresAt!.isUtc, isTrue);
        }
      },
    );

    test(
      'rejects ambiguous dates and calendar normalization in grants',
      () async {
        for (final expiration in <Object?>[
          '',
          5,
          '2030-02-03T04:05:06',
          '2030-02-30T04:05:06Z',
          '2030-13-01T04:05:06Z',
          '2030-02-03T24:05:06Z',
          '2030-02-03T04:60:06Z',
          '2030-02-03T04:05:60Z',
          '2030-02-03T04:05:06+15:00',
          '2030-02-03T04:05:06+14:01',
          '2030-02-03T04:05:06+02:99',
        ]) {
          final repository = IamAccountRepository(
            api: _api(
              _FakeAuthenticationRepository(user: _identity('uid-1')),
              MockClient(
                (_) async => http.Response(
                  jsonEncode([_ranchPayload()..['expiresAt'] = expiration]),
                  200,
                ),
              ),
            ),
          );
          await _expectFailure(
            repository.ranchAccess(),
            AuthFailureCode.invalidResponse,
          );
        }
      },
    );
  });
}

Map<String, Object?> _ranchPayload() => {
  'ranchId': '223e4567-e89b-12d3-a456-426614174000',
  'scope': 'Read',
  'name': 'North ranch',
  'region': 'Cusco',
  'district': 'Anta',
  'expiresAt': null,
};

AuthenticatedApiClient _api(
  _FakeAuthenticationRepository authentication,
  http.Client client, {
  Duration timeout = const Duration(seconds: 1),
}) => AuthenticatedApiClient(
  baseUri: Uri.parse('https://api.example.test/api/v1'),
  client: client,
  authentication: authentication,
  languageTag: () => 'es-419',
  timeout: timeout,
);

AuthUser _identity(String uid) =>
    AuthUser(uid: uid, email: '$uid@example.test', emailVerified: true);

String _header(http.Request request, String name) => request.headers.entries
    .firstWhere((entry) => entry.key.toLowerCase() == name)
    .value;

Future<void> _expectFailure(
  Future<Object?> operation,
  AuthFailureCode code,
) async {
  await expectLater(
    operation,
    throwsA(isA<AuthFailure>().having((failure) => failure.code, 'code', code)),
  );
}

final class _FakeAuthenticationRepository implements AuthenticationRepository {
  _FakeAuthenticationRepository({this.user, this.configured = true});

  AuthUser? user;
  final bool configured;
  int tokenRequests = 0;
  Future<void> Function()? onIdToken;

  @override
  bool get isConfigured => configured;

  @override
  AuthUser? get currentUser => user;

  @override
  Stream<AuthUser?> observeAuthState() => const Stream<AuthUser?>.empty();

  @override
  Future<AuthUser> signIn(String email, String password) async {
    return user ??= AuthUser(
      uid: 'signed-in',
      email: email,
      emailVerified: true,
    );
  }

  @override
  Future<AuthUser?> reloadUser() async => user;

  @override
  Future<String> idToken({bool forceRefresh = false}) async {
    tokenRequests++;
    await onIdToken?.call();
    return 'token-$tokenRequests';
  }

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> signOut() async {
    user = null;
  }
}

final class _StreamClient extends http.BaseClient {
  _StreamClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _handler(request);
}
