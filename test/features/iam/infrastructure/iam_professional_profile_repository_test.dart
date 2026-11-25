import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_failure.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_user.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/repositories/authentication_repository.dart';
import 'package:ichu_mobile_app/features/iam/infrastructure/http/authenticated_api_client.dart';
import 'package:ichu_mobile_app/features/iam/infrastructure/repositories/iam_professional_profile_repository.dart';

const _user = AuthUser(
  uid: 'synthetic-vet',
  email: 'vet@example.test',
  emailVerified: true,
);
const _profile = <String, Object?>{
  'specialty': 'Bovine health',
  'licenseNumber': 'CMVP-123',
  'yearsOfExperience': 5,
};

void main() {
  test(
    'reads the full own-account resource using GET only and a fresh token',
    () async {
      final auth = _ReadIdentity()..user = _user;
      final requests = <http.Request>[];
      final repository = _repository(
        auth,
        MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode(_account()), 200);
        }),
      );
      final first = await repository.currentAccount();
      await repository.currentAccount();
      expect(repository.isConfigured, isTrue);
      expect(auth.tokenRequests, 2);
      expect(requests, hasLength(2));
      for (final request in requests) {
        expect(request.method, 'GET');
        expect(
          request.url.toString(),
          'https://api.example.test/api/v1/profiles/me',
        );
        expect(request.followRedirects, isFalse);
        expect(request.body, isEmpty);
        expect(request.headers['Accept'], 'application/json');
        expect(request.headers['Accept-Language'], 'es-419');
        expect(request.headers['Authorization'], startsWith('Bearer '));
      }
      expect(first.email, _user.email);
      expect(first.role, AccountRole.veterinarian);
      expect(first.status, 'TemporarilyBlocked');
      expect(first.profile?.specialty, 'Bovine health');
      expect(first.profile?.licenseNumber, 'CMVP-123');
      expect(first.profile?.yearsOfExperience, 5);
    },
  );

  for (final role in ['Veterinarian', 'RanchManager', 'FieldOperator']) {
    test('accepts nullable and absent profiles for $role', () async {
      for (final omitted in [false, true]) {
        final payload = _account(role: role, profile: null);
        if (omitted) payload.remove('profile');
        final repository = _repository(
          _ReadIdentity()..user = _user,
          MockClient((_) async => http.Response(jsonEncode(payload), 200)),
        );
        expect((await repository.currentAccount()).profile, isNull);
      }
    });
  }

  test(
    'validates nullable profile DTOs without inventing specialty or license formats',
    () async {
      final valid = {
        ..._profile,
        'specialty': ' Other specialty ',
        'licenseNumber': ' local / 123 ',
        'extra': 'ignored',
      };
      final repository = _repository(
        _ReadIdentity()..user = _user,
        MockClient(
          (_) async => http.Response(jsonEncode(_account(profile: valid)), 200),
        ),
      );
      final profile = (await repository.currentAccount()).profile!;
      expect(profile.specialty, 'Other specialty');
      expect(profile.licenseNumber, 'LOCAL / 123');
    },
  );

  test(
    'rejects malformed profiles, unknown roles and profile-only responses',
    () async {
      final invalidProfiles = <Object?>[
        '',
        5,
        <String, Object?>{},
        {..._profile, 'specialty': ' '},
        {..._profile, 'specialty': 5},
        {..._profile, 'specialty': 's' * 121},
        {..._profile, 'licenseNumber': true},
        {..._profile, 'licenseNumber': ' '},
        {..._profile, 'licenseNumber': 'l' * 81},
        {..._profile, 'yearsOfExperience': 5.0},
        {..._profile, 'yearsOfExperience': '5'},
        {..._profile, 'yearsOfExperience': -1},
        {..._profile, 'yearsOfExperience': 2147483648},
        {..._profile}..remove('yearsOfExperience'),
      ];
      for (final payload in [
        ...invalidProfiles.map((profile) => _account(profile: profile)),
        _account(role: 'Unknown'),
        _profile,
      ]) {
        final repository = _repository(
          _ReadIdentity()..user = _user,
          MockClient((_) async => http.Response(jsonEncode(payload), 200)),
        );
        await _expectFailure(
          repository.currentAccount(),
          AuthFailureCode.invalidResponse,
        );
      }
    },
  );

  test(
    'maps safe HTTP failures without exposing response details or replaying',
    () async {
      for (final (status, code) in [
        (401, AuthFailureCode.accountUnavailable),
        (403, AuthFailureCode.forbidden),
        (409, AuthFailureCode.unknown),
        (429, AuthFailureCode.serviceUnavailable),
        (500, AuthFailureCode.serviceUnavailable),
        (503, AuthFailureCode.serviceUnavailable),
      ]) {
        var calls = 0;
        final repository = _repository(
          _ReadIdentity()..user = _user,
          MockClient((_) async {
            calls++;
            return http.Response('{"title":"private details"}', status);
          }),
        );
        await _expectFailure(repository.currentAccount(), code);
        expect(calls, 1);
      }
    },
  );

  test('fails closed without an API or identity and sends no HTTP', () async {
    final noApi = IamProfessionalProfileRepository(api: null);
    expect(noApi.isConfigured, isFalse);
    await _expectFailure(noApi.currentAccount(), AuthFailureCode.configuration);
    var calls = 0;
    final auth = _ReadIdentity();
    final repository = _repository(
      auth,
      MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    await _expectFailure(
      repository.currentAccount(),
      AuthFailureCode.accountUnavailable,
    );
    auth
      ..user = _user
      ..isConfigured = false;
    await _expectFailure(
      repository.currentAccount(),
      AuthFailureCode.configuration,
    );
    expect(calls, 0);
    expect(auth.tokenRequests, 0);
  });

  test(
    'rejects a UID change during token acquisition before sending',
    () async {
      final token = Completer<String>();
      final auth = _ReadIdentity()
        ..user = _user
        ..idTokenCompleter = token;
      var calls = 0;
      final repository = _repository(
        auth,
        MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      final operation = repository.currentAccount();
      auth.user = const AuthUser(
        uid: 'another-user',
        email: 'other@example.test',
        emailVerified: true,
      );
      token.complete('synthetic-token');
      await _expectFailure(operation, AuthFailureCode.accountUnavailable);
      expect(calls, 0);
    },
  );

  test('rejects a UID change while the GET response is pending', () async {
    final response = Completer<http.Response>();
    final seen = Completer<void>();
    final auth = _ReadIdentity()..user = _user;
    final repository = _repository(
      auth,
      MockClient((_) {
        seen.complete();
        return response.future;
      }),
    );
    final operation = repository.currentAccount();
    await seen.future;
    auth.user = null;
    response.complete(http.Response(jsonEncode(_account()), 200));
    await _expectFailure(operation, AuthFailureCode.accountUnavailable);
  });

  test(
    'does not follow redirects or automatically replay a timed-out read',
    () async {
      var calls = 0;
      final redirect = _repository(
        _ReadIdentity()..user = _user,
        MockClient((request) async {
          calls++;
          expect(request.followRedirects, isFalse);
          return http.Response(
            '',
            302,
            headers: {'location': 'https://other.example.test/collect'},
          );
        }),
      );
      await _expectFailure(redirect.currentAccount(), AuthFailureCode.unknown);
      expect(calls, 1);
      final pending = Completer<http.Response>();
      calls = 0;
      final timeout = _repository(
        _ReadIdentity()..user = _user,
        MockClient((_) {
          calls++;
          return pending.future;
        }),
        timeout: const Duration(milliseconds: 20),
      );
      await _expectFailure(timeout.currentAccount(), AuthFailureCode.network);
      expect(calls, 1);
      pending.complete(http.Response(jsonEncode(_account()), 200));
    },
  );
}

Map<String, Object?> _account({
  String role = 'Veterinarian',
  Object? profile = _profile,
}) => {
  'id': '123e4567-e89b-12d3-a456-426614174000',
  'email': _user.email,
  'role': role,
  'status': 'TemporarilyBlocked',
  'profile': profile,
};

IamProfessionalProfileRepository _repository(
  _ReadIdentity auth,
  http.Client client, {
  Duration timeout = const Duration(seconds: 1),
}) => IamProfessionalProfileRepository(
  api: AuthenticatedApiClient(
    baseUri: Uri.parse('https://api.example.test/api/v1'),
    client: client,
    authentication: auth,
    languageTag: () => 'es-419',
    timeout: timeout,
  ),
);

Future<void> _expectFailure(
  Future<Object?> operation,
  AuthFailureCode code,
) async {
  await expectLater(
    operation,
    throwsA(
      isA<AuthFailure>()
          .having((failure) => failure.code, 'code', code)
          .having(
            (failure) => failure.toString(),
            'safe description',
            isNot(contains('private details')),
          ),
    ),
  );
}

final class _ReadIdentity implements AuthenticationRepository {
  @override
  bool isConfigured = true;
  AuthUser? user;
  Completer<String>? idTokenCompleter;
  int tokenRequests = 0;

  @override
  AuthUser? get currentUser => user;
  @override
  Stream<AuthUser?> observeAuthState() => const Stream.empty();
  @override
  Future<AuthUser?> reloadUser() async => user;
  @override
  Future<String> idToken({bool forceRefresh = false}) async {
    tokenRequests++;
    return idTokenCompleter?.future ?? 'synthetic-token-$tokenRequests';
  }

  @override
  Future<AuthUser> signIn(String email, String password) async =>
      throw UnimplementedError();
  @override
  Future<void> signOut() async {
    user = null;
  }

  @override
  Future<void> sendPasswordReset(String email) async {}
}
