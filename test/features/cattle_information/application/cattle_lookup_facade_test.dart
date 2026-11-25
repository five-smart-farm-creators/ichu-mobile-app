import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/cattle_information/application/facades/cattle_lookup_facade.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle.dart';
import 'package:ichu_mobile_app/features/iam/application/facades/authorized_ranch_session.dart';
import 'package:ichu_mobile_app/features/iam/application/services/auth_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/authentication_lifecycle.dart';
import 'package:ichu_mobile_app/features/iam/application/services/ranch_selection_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_access.dart';

import '../../../support/fake_cattle_repository.dart';
import '../../../support/fake_iam_repositories.dart';

const _ranchA = '11111111-1111-4111-8111-111111111111';
const _ranchB = '22222222-2222-4222-8222-222222222222';
const _accountId = 'accountUUID';

void main() {
  late _Harness harness;
  late FakeCattleRepository repository;
  late CattleLookupFacade facade;

  setUp(() async {
    harness = _Harness();
    repository = FakeCattleRepository();
    facade = CattleLookupFacade(access: harness.access, cattle: repository);
    await harness.initializeAndSelect(_ranchA);
  });

  tearDown(() => harness.dispose());

  test('searches an exact tag only under the current managed ranch', () async {
    repository.listResult = <Cattle>[
      syntheticCattle(ranchId: _ranchA, id: 'match', earTag: 'TAG-7'),
    ];

    final result = await facade.findByExactEarTag(
      accountId: _accountId,
      ranchId: _ranchA,
      earTag: ' TAG-7 ',
    );

    expect(result, hasLength(1));
    expect(result.single.cattleId, syntheticCattleId('match'));
    expect(result.single.ranchId, _ranchA);
    expect(result.single.earTag, 'TAG-7');
    expect(repository.listRequests.single.ranchId, _ranchA);
    expect(repository.listRequests.single.query.earTag, 'TAG-7');
  });

  test(
    'rejects an unselected ranch, wrong account, and read-only grant',
    () async {
      await _expectFailure(
        facade.findByExactEarTag(
          accountId: _accountId,
          ranchId: _ranchB,
          earTag: 'TAG-7',
        ),
        CattleLookupFailureCode.contextUnavailable,
      );
      await _expectFailure(
        facade.findByExactEarTag(
          accountId: 'other-account',
          ranchId: _ranchA,
          earTag: 'TAG-7',
        ),
        CattleLookupFailureCode.contextUnavailable,
      );
      expect(repository.listCalls, 0);

      await harness.select(_ranchB);
      await _expectFailure(
        facade.findByExactEarTag(
          accountId: _accountId,
          ranchId: _ranchB,
          earTag: 'TAG-7',
        ),
        CattleLookupFailureCode.permissionRequired,
      );
      expect(repository.listCalls, 0);
    },
  );

  test(
    'rejects malformed, cross-ranch, and non-exact search results',
    () async {
      await _expectFailure(
        facade.findByExactEarTag(
          accountId: _accountId,
          ranchId: _ranchA,
          earTag: ' ',
        ),
        CattleLookupFailureCode.invalidQuery,
      );
      expect(repository.listCalls, 0);

      repository.listResult = <Cattle>[
        syntheticCattle(ranchId: _ranchB, id: 'foreign', earTag: 'TAG-7'),
      ];
      await _expectFailure(
        facade.findByExactEarTag(
          accountId: _accountId,
          ranchId: _ranchA,
          earTag: 'TAG-7',
        ),
        CattleLookupFailureCode.invalidResponse,
      );

      repository.listResult = <Cattle>[
        syntheticCattle(ranchId: _ranchA, id: 'wrong-tag', earTag: 'TAG-70'),
      ];
      await _expectFailure(
        facade.findByExactEarTag(
          accountId: _accountId,
          ranchId: _ranchA,
          earTag: 'TAG-7',
        ),
        CattleLookupFailureCode.invalidResponse,
      );
    },
  );

  test(
    'does not return a lookup after the authorized context changes',
    () async {
      final pending = Completer<List<Cattle>>();
      repository.listCompleter = pending;
      final lookup = facade.findByExactEarTag(
        accountId: _accountId,
        ranchId: _ranchA,
        earTag: 'TAG-7',
      );
      await Future<void>.value();
      await harness.select(_ranchB);
      pending.complete(<Cattle>[
        syntheticCattle(ranchId: _ranchA, id: 'stale', earTag: 'TAG-7'),
      ]);

      await _expectFailure(lookup, CattleLookupFailureCode.contextUnavailable);
    },
  );
}

Future<void> _expectFailure<T>(
  Future<T> operation,
  CattleLookupFailureCode code,
) async {
  await expectLater(
    operation,
    throwsA(
      isA<CattleLookupFailure>().having(
        (failure) => failure.code,
        'code',
        code,
      ),
    ),
  );
}

final class _Harness {
  _Harness()
    : identity = FakeAuthenticationRepository(),
      accounts = FakeAccountRepository(
        account: syntheticIamAccount,
        ranches: <RanchAccess>[
          _ranch(_ranchA, AccessScope.manage),
          _ranch(_ranchB, AccessScope.read),
        ],
      ) {
    lifecycle = AuthenticationLifecycle(identity);
    auth = AuthService(authentication: lifecycle, accounts: accounts);
    selection = RanchSelectionService(session: auth);
    access = AuthorizedRanchSession(
      session: auth,
      selection: selection,
      authentication: identity,
    );
  }

  final FakeAuthenticationRepository identity;
  final FakeAccountRepository accounts;
  late final AuthenticationLifecycle lifecycle;
  late final AuthService auth;
  late final RanchSelectionService selection;
  late final AuthorizedRanchSession access;

  Future<void> initializeAndSelect(String ranchId) async {
    await auth.initialize();
    await select(ranchId);
  }

  Future<void> select(String ranchId) async {
    expect(selection.select(ranchId), isTrue);
  }

  void dispose() {
    access.dispose();
    selection.dispose();
    auth.dispose();
    lifecycle.dispose();
    unawaited(identity.close());
  }
}

RanchAccess _ranch(String id, AccessScope scope) => RanchAccess(
  ranchId: id,
  scope: scope,
  name: 'Ranch $id',
  region: 'Synthetic region',
  district: 'Synthetic district',
);
