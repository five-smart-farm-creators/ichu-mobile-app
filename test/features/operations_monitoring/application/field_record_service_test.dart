import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/iam/application/facades/authorized_ranch_session.dart';
import 'package:ichu_mobile_app/features/iam/application/services/auth_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/authentication_lifecycle.dart';
import 'package:ichu_mobile_app/features/iam/application/services/ranch_selection_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_access.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/application/services/field_record_service.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/field_record.dart';

import '../../../support/fake_iam_repositories.dart';
import '../../../support/memory_field_record_repository.dart';

const _accountA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _accountB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _ranchA = '11111111-1111-4111-8111-111111111111';
const _ranchB = '22222222-2222-4222-8222-222222222222';
const _cattleA = '33333333-3333-4333-8333-333333333333';

void main() {
  group('FieldRecordService', () {
    late _Harness harness;
    late MemoryFieldRecordRepository repository;
    late FieldRecordService service;

    setUp(() async {
      harness = _Harness();
      repository = MemoryFieldRecordRepository();
      await harness.initializeAndSelect(_ranchA);
      service = FieldRecordService(
        access: harness.access,
        repository: repository,
      );
    });

    tearDown(() {
      service.dispose();
      harness.dispose();
    });

    test(
      'persists in the original account and ranch across context changes',
      () async {
        expect(await service.load(), isTrue);
        await service.cacheCattleOptions(<FieldCattleOption>[
          _cattleOption(_ranchA),
        ]);
        await service.save(
          cattleId: _cattleA,
          cattleEarTag: 'TAG-3',
          type: FieldRecordType.healthEvent,
          occurredAt: DateTime.utc(2020, 11, 13),
          observation: 'Mild lameness',
        );
        expect(service.records, hasLength(1));

        expect(harness.selection.select(_ranchB), isTrue);
        expect(await service.load(), isTrue);
        expect(service.records, isEmpty);
        expect(harness.selection.select(_ranchA), isTrue);
        expect(await service.load(), isTrue);
        expect(service.records.single.observation, 'Mild lameness');

        harness.accounts.account = _account(_accountB);
        await harness.auth.refresh();
        expect(harness.access.context, isNull);
        expect(harness.selection.select(_ranchA), isTrue);
        expect(await service.load(), isTrue);
        expect(service.records, isEmpty);
        expect(
          await repository.readPending(accountId: _accountA, ranchId: _ranchA),
          hasLength(1),
        );
      },
    );

    test(
      'requires both a server-issued manage grant and a loaded cattle choice',
      () async {
        harness.accounts.ranches = <RanchAccess>[
          _ranch(_ranchA, AccessScope.read),
        ];
        await harness.auth.refresh();
        expect(harness.selection.select(_ranchA), isTrue);
        await service.load();
        expect(service.canCreate, isFalse);
        await expectLater(
          service.save(
            cattleId: _cattleA,
            cattleEarTag: 'TAG-3',
            type: FieldRecordType.healthEvent,
            occurredAt: DateTime.utc(2020, 11, 13),
          ),
          throwsA(
            isA<FieldRecordFailure>().having(
              (failure) => failure.code,
              'code',
              FieldRecordFailureCode.permissionRequired,
            ),
          ),
        );
      },
    );

    test(
      'does not save a cattle identifier that was not loaded for this ranch',
      () async {
        await service.load();
        await expectLater(
          service.save(
            cattleId: _cattleA,
            cattleEarTag: 'TAG-3',
            type: FieldRecordType.healthEvent,
            occurredAt: DateTime.utc(2020, 11, 13),
          ),
          throwsA(
            isA<FieldRecordFailure>().having(
              (failure) => failure.code,
              'code',
              FieldRecordFailureCode.invalidRecord,
            ),
          ),
        );
      },
    );

    test(
      'rejects an event time outside the backend future allowance',
      () async {
        await service.load();
        await service.cacheCattleOptions(<FieldCattleOption>[
          _cattleOption(_ranchA),
        ]);

        await expectLater(
          service.save(
            cattleId: _cattleA,
            cattleEarTag: 'TAG-3',
            type: FieldRecordType.healthEvent,
            occurredAt: DateTime.now().add(const Duration(minutes: 6)),
          ),
          throwsA(
            isA<FieldRecordFailure>().having(
              (failure) => failure.code,
              'code',
              FieldRecordFailureCode.invalidRecord,
            ),
          ),
        );
      },
    );

    test('retains pending work when the account signs out', () async {
      await service.load();
      await service.cacheCattleOptions(<FieldCattleOption>[
        _cattleOption(_ranchA),
      ]);
      await service.save(
        cattleId: _cattleA,
        cattleEarTag: 'TAG-3',
        type: FieldRecordType.healthEvent,
        occurredAt: DateTime.utc(2020, 11, 13),
        observation: 'Saved before sign-out',
      );

      expect(await harness.auth.signOut(), isTrue);
      expect(harness.access.context, isNull);
      expect(
        await repository.readPending(accountId: _accountA, ranchId: _ranchA),
        hasLength(1),
      );
    });

    test(
      'reports a concurrent save instead of claiming it was saved',
      () async {
        await service.load();
        await service.cacheCattleOptions(<FieldCattleOption>[
          _cattleOption(_ranchA),
        ]);
        repository.appendEntered = Completer<void>();
        repository.appendBarrier = Completer<void>();

        final firstSave = service.save(
          cattleId: _cattleA,
          cattleEarTag: 'TAG-3',
          type: FieldRecordType.healthEvent,
          occurredAt: DateTime.utc(2020, 11, 13),
        );
        await repository.appendEntered!.future;

        await expectLater(
          service.save(
            cattleId: _cattleA,
            cattleEarTag: 'TAG-3',
            type: FieldRecordType.healthEvent,
            occurredAt: DateTime.utc(2020, 11, 13),
          ),
          throwsA(
            isA<FieldRecordFailure>().having(
              (failure) => failure.code,
              'code',
              FieldRecordFailureCode.operationInProgress,
            ),
          ),
        );

        repository.appendBarrier!.complete();
        await firstSave;
        expect(service.records, hasLength(1));
      },
    );
  });
}

FieldCattleOption _cattleOption(String ranchId) =>
    FieldCattleOption(cattleId: _cattleA, ranchId: ranchId, earTag: 'TAG-3');

RanchAccess _ranch(String ranchId, AccessScope scope) => RanchAccess(
  ranchId: ranchId,
  scope: scope,
  name: 'Ranch $ranchId',
  region: 'Synthetic region',
  district: 'Synthetic district',
);

IamAccount _account(String id) => IamAccount(
  id: id,
  email: 'user@example.test',
  role: AccountRole.ranchManager,
  status: 'active',
);

final class _Harness {
  _Harness()
    : identity = FakeAuthenticationRepository(),
      accounts = FakeAccountRepository(
        account: _account(_accountA),
        ranches: <RanchAccess>[
          _ranch(_ranchA, AccessScope.manage),
          _ranch(_ranchB, AccessScope.manage),
        ],
      ) {
    lifecycle = AuthenticationLifecycle(identity);
    auth = AuthService(authentication: lifecycle, accounts: accounts);
    selection = RanchSelectionService(session: auth);
    access = AuthorizedRanchSession(
      session: auth,
      selection: selection,
      authentication: lifecycle,
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
