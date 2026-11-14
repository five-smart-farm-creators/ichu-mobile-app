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
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/field_record_sync.dart';

import '../../../support/fake_iam_repositories.dart';
import '../../../support/fake_field_record_sync_repository.dart';
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
    late FakeFieldRecordSyncRepository remote;

    setUp(() async {
      harness = _Harness();
      repository = MemoryFieldRecordRepository();
      remote = FakeFieldRecordSyncRepository();
      await harness.initializeAndSelect(_ranchA);
      service = FieldRecordService(
        access: harness.access,
        repository: repository,
        syncRepository: remote,
      );
    });

    tearDown(() {
      service.dispose();
      harness.dispose();
    });

    Future<void> capture({int count = 1}) async {
      await service.load();
      await service.cacheCattleOptions([_cattleOption(_ranchA)]);
      for (var i = 0; i < count; i++) {
        await service.save(
          cattleId: _cattleA,
          cattleEarTag: 'TAG-3',
          type: FieldRecordType.healthEvent,
          occurredAt: DateTime.utc(2020),
          observation: 'Synthetic capture $i',
        );
      }
    }

    test(
      'reconciles mixed results independently and retains failed records',
      () async {
        await capture(count: 4);
        remote.respond = (records) => List.generate(
          records.length,
          (index) => FieldRecordSyncResult(
            operationId: records[index].operationId,
            status: FieldRecordSyncStatus.values[index],
            reason: 'Synthetic review reason',
          ),
        );
        expect(await service.synchronize(), isTrue);
        expect(service.lastSyncConfirmed, 2);
        expect(service.records, hasLength(2));
        expect(service.syncIssues.map((issue) => issue.status), [
          FieldRecordSyncStatus.rejected,
          FieldRecordSyncStatus.conflict,
        ]);
        expect(
          await repository.readPending(accountId: _accountA, ranchId: _ranchA),
          service.records,
        );
        expect(service.cattleOptions, hasLength(1));
        expect(remote.requests.single.accountId, _accountA);
        expect(remote.requests.single.ranchId, _ranchA);
        await service.load();
        expect(service.syncIssues.first.reason, 'Synthetic review reason');
      },
    );

    test(
      'network uncertainty keeps the same immutable payload for explicit retry',
      () async {
        await capture();
        final record = service.records.single;
        remote.failure = const FieldRecordSyncFailure(
          FieldRecordSyncFailureCode.network,
        );
        expect(await service.synchronize(), isFalse);
        expect(service.syncError?.code, FieldRecordSyncFailureCode.network);
        expect(service.records, [record]);
        expect(service.canCreate, isTrue);
        expect(remote.requests, hasLength(1));
        remote.failure = null;
        remote.respond = (records) => [
          FieldRecordSyncResult(
            operationId: record.operationId,
            status: FieldRecordSyncStatus.duplicate,
          ),
        ];
        expect(await service.synchronize(), isTrue);
        expect(remote.requests.last.records, [record]);
        expect(service.records, isEmpty);
        expect(service.lastSyncConfirmed, 1);
      },
    );

    test(
      'local confirmation failure keeps data available for a duplicate retry',
      () async {
        await capture();
        final snapshot = service.records;
        repository.applyFailure = StateError('Synthetic write failure');
        expect(await service.synchronize(), isFalse);
        expect(
          service.syncError?.code,
          FieldRecordSyncFailureCode.storageUnavailable,
        );
        expect(service.records, snapshot);
        expect(service.lastSyncConfirmed, 0);
        repository.applyFailure = null;
        expect(await service.synchronize(), isTrue);
        expect(remote.requests.last.records, snapshot);
      },
    );

    test(
      'a failed later chunk preserves earlier confirmations and all remaining work',
      () async {
        await capture(count: 103);
        remote.respond = (records) {
          if (remote.requests.length == 2) {
            throw const FieldRecordSyncFailure(
              FieldRecordSyncFailureCode.network,
            );
          }
          return confirmedFieldRecords(records);
        };
        expect(await service.synchronize(), isFalse);
        expect(remote.requests.map((request) => request.records.length), [
          50,
          50,
        ]);
        expect(service.records, hasLength(53));
        expect(service.lastSyncConfirmed, 50);
        remote.respond = null;
        expect(await service.synchronize(), isTrue);
        expect(remote.requests.map((request) => request.records.length), [
          50,
          50,
          50,
          3,
        ]);
        expect(service.records, isEmpty);
      },
    );

    test(
      'deduplicates synchronization while allowing new offline captures',
      () async {
        await capture();
        remote.pending = Completer<List<FieldRecordSyncResult>>();
        remote.entered = Completer<void>();
        final pending = service.synchronize();
        expect(identical(pending, service.synchronize()), isTrue);
        await remote.entered!.future;
        expect(await service.load(), isFalse);
        await service.save(
          cattleId: _cattleA,
          cattleEarTag: 'TAG-3',
          type: FieldRecordType.birth,
          occurredAt: DateTime.utc(2020),
        );
        remote.pending!.complete(
          confirmedFieldRecords(remote.requests.single.records),
        );
        expect(await pending, isTrue);
        expect(service.records.single.type, FieldRecordType.birth);
        expect(
          await repository.readPending(accountId: _accountA, ranchId: _ranchA),
          service.records,
        );
      },
    );

    for (final change in ['ranch', 'account', 'logout', 'dispose']) {
      test(
        '$change change fences a late response without removing original records',
        () async {
          await capture();
          remote.pending = Completer<List<FieldRecordSyncResult>>();
          remote.entered = Completer<void>();
          final pending = service.synchronize();
          await remote.entered!.future;
          switch (change) {
            case 'ranch':
              harness.selection.select(_ranchB);
              harness.selection.select(_ranchA);
            case 'account':
              harness.accounts.account = _account(_accountB);
              await harness.auth.refresh();
              harness.selection.select(_ranchA);
            case 'logout':
              await harness.auth.signOut();
            case 'dispose':
              service.dispose();
          }
          remote.pending!.complete(
            confirmedFieldRecords(remote.requests.single.records),
          );
          expect(await pending, isFalse);
          expect(
            await repository.readPending(
              accountId: _accountA,
              ranchId: _ranchA,
            ),
            hasLength(1),
          );
          expect(service.syncError, isNull);
          if (change == 'ranch' || change == 'account') {
            expect(await service.load(), isTrue);
            expect(service.records.length, change == 'ranch' ? 1 : 0);
          }
        },
      );
    }

    test('invalid or incomplete decisions cannot clear pending data', () async {
      await capture();
      remote.respond = (_) => [];
      expect(await service.synchronize(), isFalse);
      expect(
        service.syncError?.code,
        FieldRecordSyncFailureCode.invalidResponse,
      );
      expect(service.records, hasLength(1));
    });

    test(
      'does not synchronize without configuration, records or manage permission',
      () async {
        await service.load();
        expect(await service.synchronize(), isFalse);
        await capture();
        remote.isConfigured = false;
        expect(await service.synchronize(), isFalse);
        remote.isConfigured = true;
        harness.accounts.ranches = [_ranch(_ranchA, AccessScope.read)];
        await harness.auth.refresh();
        harness.selection.select(_ranchA);
        await service.load();
        expect(service.canSynchronize, isFalse);
        expect(await service.synchronize(), isFalse);
        expect(remote.requests, isEmpty);
      },
    );

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
