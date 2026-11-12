import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/account_registration_result.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_failure.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_user.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/registration_details.dart';
import 'package:ichu_mobile_app/features/iam/domain/repositories/authentication_repository.dart';
import 'package:ichu_mobile_app/features/iam/infrastructure/http/authenticated_api_client.dart';
import 'package:ichu_mobile_app/features/iam/infrastructure/repositories/iam_account_registration_repository.dart';

const _accountId = '123e4567-e89b-12d3-a456-426614174000';
const _ranchId = '223e4567-e89b-12d3-a456-426614174000';

void main() {
  group('IamAccountRegistrationRepository.registerAccount', () {
    test(
      'does not request tokens or POST when identity configuration is absent',
      () async {
        final auth = _FakeAuthenticationRepository(
          user: _identity(),
          configured: false,
        );
        var requests = 0;
        final repository = _repository(
          auth,
          MockClient((_) async {
            requests++;
            return http.Response('{}', 201);
          }),
        );
        final failure = await _captureFailure(
          repository.registerAccount(
            email: 'vet@example.test',
            details: const RegistrationDetails(role: AccountRole.veterinarian),
          ),
        );
        expect(failure.code, AuthFailureCode.configuration);
        expect(auth.tokenRequests, 0);
        expect(requests, 0);
      },
    );

    test(
      'posts the exact veterinarian contract and maps the nested account',
      () async {
        final auth = _FakeAuthenticationRepository(user: _identity());
        late http.Request request;
        final repository = _repository(
          auth,
          MockClient((incoming) async {
            request = incoming;
            return http.Response(
              jsonEncode(
                _registrationResponse(
                  role: 'Veterinarian',
                  email: 'vet@example.test',
                  ranchId: null,
                ),
              ),
              201,
            );
          }),
        );

        final result = await repository.registerAccount(
          email: ' Vet@Example.Test ',
          details: const RegistrationDetails(role: AccountRole.veterinarian),
        );

        expect(repository.isConfigured, isTrue);
        expect(request.method, 'POST');
        expect(
          request.url.toString(),
          'https://api.example.test/api/v1/accounts',
        );
        expect(request.followRedirects, isFalse);
        expect(
          _header(request, 'authorization'),
          'Bearer synthetic-id-token-1',
        );
        expect(_header(request, 'accept'), 'application/json');
        expect(_header(request, 'accept-language'), 'es-419');
        expect(_header(request, 'content-type'), 'application/json');
        expect(jsonDecode(request.body), <String, Object?>{
          'role': 'Veterinarian',
        });
        expect(request.body, isNot(contains('email')));
        expect(request.body, isNot(contains('password')));
        expect(request.body, isNot(contains('uid')));
        expect(result, isA<AccountRegistrationResult>());
        expect(result.account.id, _accountId);
        expect(result.account.email, 'vet@example.test');
        expect(result.account.role, AccountRole.veterinarian);
        expect(result.account.status, 'PendingVerification');
        expect(result.ranchId, isNull);
      },
    );

    test(
      'trims manager ranch details and requires the returned ranch UUID',
      () async {
        final auth = _FakeAuthenticationRepository(user: _identity());
        late http.Request request;
        final repository = _repository(
          auth,
          MockClient((incoming) async {
            request = incoming;
            return http.Response(
              jsonEncode(
                _registrationResponse(
                  role: 'RanchManager',
                  email: 'vet@example.test',
                  ranchId: _ranchId,
                ),
              ),
              201,
            );
          }),
        );

        final result = await repository.registerAccount(
          email: 'vet@example.test',
          details: const RegistrationDetails(
            role: AccountRole.ranchManager,
            ranch: RanchRegistration(
              name: ' Los Andes ',
              region: ' Cusco ',
              district: ' Urubamba ',
              estimatedHeadCount: 120,
            ),
          ),
        );

        expect(jsonDecode(request.body), <String, Object?>{
          'role': 'RanchManager',
          'ranchName': 'Los Andes',
          'region': 'Cusco',
          'district': 'Urubamba',
          'estimatedHeadCount': 120,
        });
        expect(result.account.role, AccountRole.ranchManager);
        expect(result.account.status, 'PendingVerification');
        expect(result.ranchId, _ranchId);
      },
    );

    test(
      'rejects unsupported roles and missing manager details before HTTP',
      () async {
        var requestCount = 0;
        final repository = _repository(
          _FakeAuthenticationRepository(user: _identity()),
          MockClient((_) async {
            requestCount++;
            return http.Response('{}', 201);
          }),
        );

        await _expectFailure(
          repository.registerAccount(
            email: 'vet@example.test',
            details: const RegistrationDetails(role: AccountRole.fieldOperator),
          ),
          AuthFailureCode.registrationRejected,
        );
        await _expectFailure(
          repository.registerAccount(
            email: 'vet@example.test',
            details: const RegistrationDetails(role: AccountRole.ranchManager),
          ),
          AuthFailureCode.registrationRejected,
        );
        expect(requestCount, 0);
      },
    );

    test('rejects ranch values outside backend bounds before HTTP', () async {
      var requestCount = 0;
      final repository = _repository(
        _FakeAuthenticationRepository(user: _identity()),
        MockClient((_) async {
          requestCount++;
          return http.Response('{}', 201);
        }),
      );
      final invalidRanches = <RanchRegistration>[
        RanchRegistration(
          name: List<String>.filled(161, 'R').join(),
          region: 'Region',
          district: 'District',
          estimatedHeadCount: 1,
        ),
        RanchRegistration(
          name: 'Ranch',
          region: List<String>.filled(121, 'G').join(),
          district: 'District',
          estimatedHeadCount: 1,
        ),
        RanchRegistration(
          name: 'Ranch',
          region: 'Region',
          district: List<String>.filled(121, 'D').join(),
          estimatedHeadCount: 1,
        ),
        const RanchRegistration(
          name: 'Ranch',
          region: 'Region',
          district: 'District',
          estimatedHeadCount: -1,
        ),
        const RanchRegistration(
          name: 'Ranch',
          region: 'Region',
          district: 'District',
          estimatedHeadCount: 2147483648,
        ),
      ];

      for (final ranch in invalidRanches) {
        await _expectFailure(
          repository.registerAccount(
            email: 'vet@example.test',
            details: RegistrationDetails(
              role: AccountRole.ranchManager,
              ranch: ranch,
            ),
          ),
          AuthFailureCode.registrationRejected,
        );
      }
      expect(requestCount, 0);
    });

    test(
      'rejects a response whose normalized email differs from the SDK email',
      () async {
        var requestCount = 0;
        final repository = _repository(
          _FakeAuthenticationRepository(user: _identity()),
          MockClient((_) async {
            requestCount++;
            return http.Response(
              jsonEncode(
                _registrationResponse(
                  role: 'Veterinarian',
                  email: 'other@example.test',
                  ranchId: null,
                ),
              ),
              201,
            );
          }),
        );

        await _expectFailure(
          repository.registerAccount(
            email: 'vet@example.test',
            details: const RegistrationDetails(role: AccountRole.veterinarian),
          ),
          AuthFailureCode.invalidResponse,
        );
        expect(requestCount, 1);
      },
    );

    test(
      'rejects malformed registration resources and unexpected ranch IDs',
      () async {
        final invalidManager = _repository(
          _FakeAuthenticationRepository(user: _identity()),
          MockClient(
            (_) async => http.Response(
              jsonEncode(
                _registrationResponse(
                  role: 'RanchManager',
                  email: 'vet@example.test',
                  ranchId: null,
                ),
              ),
              201,
            ),
          ),
        );
        await _expectFailure(
          invalidManager.registerAccount(
            email: 'vet@example.test',
            details: const RegistrationDetails(
              role: AccountRole.ranchManager,
              ranch: RanchRegistration(
                name: 'Ranch',
                region: 'Region',
                district: 'District',
                estimatedHeadCount: 1,
              ),
            ),
          ),
          AuthFailureCode.invalidResponse,
        );

        final invalidVeterinarian = _repository(
          _FakeAuthenticationRepository(user: _identity()),
          MockClient(
            (_) async => http.Response(
              jsonEncode(
                _registrationResponse(
                  role: 'Veterinarian',
                  email: 'vet@example.test',
                  ranchId: _ranchId,
                ),
              ),
              201,
            ),
          ),
        );
        await _expectFailure(
          invalidVeterinarian.registerAccount(
            email: 'vet@example.test',
            details: const RegistrationDetails(role: AccountRole.veterinarian),
          ),
          AuthFailureCode.invalidResponse,
        );

        final wrongStatus = _repository(
          _FakeAuthenticationRepository(user: _identity()),
          MockClient(
            (_) async => http.Response(
              jsonEncode(
                _registrationResponse(
                  role: 'Veterinarian',
                  email: 'vet@example.test',
                  ranchId: null,
                  status: 'Active',
                ),
              ),
              201,
            ),
          ),
        );
        await _expectFailure(
          wrongStatus.registerAccount(
            email: 'vet@example.test',
            details: const RegistrationDetails(role: AccountRole.veterinarian),
          ),
          AuthFailureCode.invalidResponse,
        );

        final malformedRanchId = _repository(
          _FakeAuthenticationRepository(user: _identity()),
          MockClient(
            (_) async => http.Response(
              jsonEncode(
                _registrationResponse(
                  role: 'RanchManager',
                  email: 'vet@example.test',
                  ranchId: 'not-a-uuid',
                ),
              ),
              201,
            ),
          ),
        );
        await _expectFailure(
          malformedRanchId.registerAccount(
            email: 'vet@example.test',
            details: const RegistrationDetails(
              role: AccountRole.ranchManager,
              ranch: RanchRegistration(
                name: 'Ranch',
                region: 'Region',
                district: 'District',
                estimatedHeadCount: 1,
              ),
            ),
          ),
          AuthFailureCode.invalidResponse,
        );
      },
    );

    test(
      'maps registration errors to safe stable failures without retrying',
      () async {
        final cases = <(int, String, AuthFailureCode)>[
          (
            400,
            '{"title":"private validation detail"}',
            AuthFailureCode.registrationRejected,
          ),
          (
            409,
            '{"code":"Iam.AccountAlreadyExists","title":"private title"}',
            AuthFailureCode.accountAlreadyExists,
          ),
          (
            409,
            '{"code":"some.other.code","title":"private title"}',
            AuthFailureCode.unknown,
          ),
          (
            401,
            '{"title":"private title"}',
            AuthFailureCode.accountUnavailable,
          ),
          (
            429,
            '{"title":"private title"}',
            AuthFailureCode.serviceUnavailable,
          ),
          (
            503,
            '{"title":"private title"}',
            AuthFailureCode.serviceUnavailable,
          ),
          (
            503,
            '{"code":"Iam.IdentityProviderNotConfigured",'
                '"title":"private title"}',
            AuthFailureCode.configuration,
          ),
        ];

        for (final (status, body, code) in cases) {
          var requestCount = 0;
          final repository = _repository(
            _FakeAuthenticationRepository(user: _identity()),
            MockClient((_) async {
              requestCount++;
              return http.Response(body, status);
            }),
          );

          final failure = await _captureFailure(
            repository.registerAccount(
              email: 'vet@example.test',
              details: const RegistrationDetails(
                role: AccountRole.veterinarian,
              ),
            ),
          );
          expect(failure.code, code);
          expect(failure.toString(), isNot(contains('private')));
          expect(requestCount, 1);
        }
      },
    );

    test('does not retry a timed-out registration POST', () async {
      final pending = Completer<http.Response>();
      var requestCount = 0;
      final repository = _repository(
        _FakeAuthenticationRepository(user: _identity()),
        MockClient((_) {
          requestCount++;
          return pending.future;
        }),
        timeout: const Duration(milliseconds: 20),
      );

      await _expectFailure(
        repository.registerAccount(
          email: 'vet@example.test',
          details: const RegistrationDetails(role: AccountRole.veterinarian),
        ),
        AuthFailureCode.network,
      );
      expect(requestCount, 1);
      pending.complete(http.Response('{}', 201));
    });

    test(
      'rejects a changed identity before sending the registration request',
      () async {
        final auth = _FakeAuthenticationRepository(user: _identity());
        auth.beforeToken = () async {
          auth.user = _identity('another-uid');
        };
        var requestCount = 0;
        final repository = _repository(
          auth,
          MockClient((_) async {
            requestCount++;
            return http.Response('{}', 201);
          }),
        );

        await _expectFailure(
          repository.registerAccount(
            email: 'vet@example.test',
            details: const RegistrationDetails(role: AccountRole.veterinarian),
          ),
          AuthFailureCode.accountUnavailable,
        );
        expect(requestCount, 0);
        expect(auth.tokenRequests, 1);
      },
    );

    test(
      'requires a current identity and fetches a fresh token for each request',
      () async {
        final auth = _FakeAuthenticationRepository(user: _identity());
        final requests = <http.Request>[];
        final repository = _repository(
          auth,
          MockClient((request) async {
            requests.add(request);
            if (request.method == 'GET') {
              return http.Response(
                jsonEncode(<String, Object?>{
                  'id': _accountId,
                  'email': 'vet@example.test',
                  'role': 'Veterinarian',
                  'status': 'Active',
                }),
                200,
              );
            }
            return http.Response(
              jsonEncode(
                _registrationResponse(
                  role: 'Veterinarian',
                  email: 'vet@example.test',
                  ranchId: null,
                ),
              ),
              201,
            );
          }),
        );

        await repository.currentAccount();
        await repository.registerAccount(
          email: 'vet@example.test',
          details: const RegistrationDetails(role: AccountRole.veterinarian),
        );

        expect(auth.tokenRequests, 2);
        expect(
          requests.map((request) => _header(request, 'authorization')),
          <String>[
            'Bearer synthetic-id-token-1',
            'Bearer synthetic-id-token-2',
          ],
        );
        expect(requests.last.method, 'POST');
      },
    );

    test(
      'does not fetch a token or send POST without a current identity',
      () async {
        final auth = _FakeAuthenticationRepository();
        var requestCount = 0;
        final repository = _repository(
          auth,
          MockClient((_) async {
            requestCount++;
            return http.Response('{}', 201);
          }),
        );

        await _expectFailure(
          repository.registerAccount(
            email: 'vet@example.test',
            details: const RegistrationDetails(role: AccountRole.veterinarian),
          ),
          AuthFailureCode.accountUnavailable,
        );
        expect(auth.tokenRequests, 0);
        expect(requestCount, 0);
      },
    );

    test(
      'rejects a response if the identity changes while POST is in flight',
      () async {
        final auth = _FakeAuthenticationRepository(user: _identity());
        final requestSeen = Completer<void>();
        final response = Completer<http.Response>();
        final repository = _repository(
          auth,
          MockClient((_) {
            requestSeen.complete();
            return response.future;
          }),
        );

        final registration = repository.registerAccount(
          email: 'vet@example.test',
          details: const RegistrationDetails(role: AccountRole.veterinarian),
        );
        await requestSeen.future;
        auth.user = _identity('another-uid');
        response.complete(
          http.Response(
            jsonEncode(
              _registrationResponse(
                role: 'Veterinarian',
                email: 'vet@example.test',
                ranchId: null,
              ),
            ),
            201,
          ),
        );

        await _expectFailure(registration, AuthFailureCode.accountUnavailable);
        expect(auth.tokenRequests, 1);
      },
    );

    test(
      'currentAccount reconciles via GET only and uses the shared account mapper',
      () async {
        final auth = _FakeAuthenticationRepository(user: _identity());
        final requests = <http.Request>[];
        final repository = _repository(
          auth,
          MockClient((request) async {
            requests.add(request);
            return http.Response(
              jsonEncode(<String, Object?>{
                'id': _accountId,
                'email': 'vet@example.test',
                'role': 'Veterinarian',
                'status': 'Active',
                'profile': null,
              }),
              200,
            );
          }),
        );

        final account = await repository.currentAccount();

        expect(account.id, _accountId);
        expect(account.email, 'vet@example.test');
        expect(account.role, AccountRole.veterinarian);
        expect(account.status, 'Active');
        expect(requests, hasLength(1));
        expect(requests.single.method, 'GET');
        expect(requests.single.url.path, '/api/v1/accounts/me');
        expect(requests.single.body, isEmpty);
        expect(auth.tokenRequests, 1);
      },
    );

    test(
      'reports configuration when API is absent and makes no request',
      () async {
        final repository = IamAccountRegistrationRepository(api: null);

        expect(repository.isConfigured, isFalse);
        await _expectFailure(
          repository.currentAccount(),
          AuthFailureCode.configuration,
        );
      },
    );
  });

  test(
    'the constrained client rejects identity fields in a registration body',
    () async {
      var requestCount = 0;
      final api = _api(
        _FakeAuthenticationRepository(user: _identity()),
        MockClient((_) async {
          requestCount++;
          return http.Response('{}', 201);
        }),
      );

      await _expectFailure(
        api.postAccountRegistration(<String, Object?>{
          'role': 'Veterinarian',
          'email': 'vet@example.test',
        }),
        AuthFailureCode.registrationRejected,
      );
      expect(requestCount, 0);
    },
  );

  test('the constrained POST does not follow an external redirect', () async {
    var requestCount = 0;
    final api = _api(
      _FakeAuthenticationRepository(user: _identity()),
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

    await _expectFailure(
      api.postAccountRegistration(const <String, Object?>{
        'role': 'Veterinarian',
      }),
      AuthFailureCode.unknown,
    );
    expect(requestCount, 1);
  });
}

Map<String, Object?> _registrationResponse({
  required String role,
  required String email,
  required String? ranchId,
  String status = 'PendingVerification',
}) => <String, Object?>{
  'account': <String, Object?>{
    'id': _accountId,
    'email': email,
    'role': role,
    'status': status,
    'profile': null,
  },
  'ranchId': ranchId,
};

IamAccountRegistrationRepository _repository(
  _FakeAuthenticationRepository authentication,
  http.Client client, {
  Duration timeout = const Duration(seconds: 1),
}) => IamAccountRegistrationRepository(
  api: _api(authentication, client, timeout: timeout),
);

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

AuthUser _identity([String uid = 'synthetic-uid']) =>
    AuthUser(uid: uid, email: 'vet@example.test', emailVerified: true);

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

Future<AuthFailure> _captureFailure(Future<Object?> operation) async {
  try {
    await operation;
  } on AuthFailure catch (failure) {
    return failure;
  }
  throw StateError('Expected an AuthFailure.');
}

final class _FakeAuthenticationRepository implements AuthenticationRepository {
  _FakeAuthenticationRepository({this.user, this.configured = true});

  AuthUser? user;
  final bool configured;
  int tokenRequests = 0;
  Future<void> Function()? beforeToken;

  @override
  bool get isConfigured => configured;

  @override
  AuthUser? get currentUser => user;

  @override
  Stream<AuthUser?> observeAuthState() => const Stream<AuthUser?>.empty();

  @override
  Future<AuthUser> signIn(String email, String password) async =>
      throw UnimplementedError();

  @override
  Future<AuthUser?> reloadUser() async => user;

  @override
  Future<String> idToken({bool forceRefresh = false}) async {
    tokenRequests++;
    await beforeToken?.call();
    return 'synthetic-id-token-$tokenRequests';
  }

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> signOut() async {
    user = null;
  }
}
