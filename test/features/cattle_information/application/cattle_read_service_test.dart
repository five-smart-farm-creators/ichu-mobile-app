import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/cattle_information/application/services/cattle_read_service.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle_date.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle_failure.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle_search.dart';
import 'package:ichu_mobile_app/features/iam/application/facades/authorized_ranch_session.dart';
import 'package:ichu_mobile_app/features/iam/application/services/auth_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/authentication_lifecycle.dart';
import 'package:ichu_mobile_app/features/iam/application/services/ranch_selection_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_access.dart';

import '../../../support/fake_cattle_repository.dart';
import '../../../support/fake_iam_repositories.dart';

void main() {
  group('CattleReadService', () {
    late _Harness harness;
    late FakeCattleRepository repository;
    late CattleReadService service;

    setUp(() async {
      harness = _Harness();
      repository = FakeCattleRepository();
      service = harness.createService(repository);
      await harness.initializeAndSelect(_ranchA);
    });
    tearDown(() {
      service.dispose();
      harness.dispose();
    });

    test(
      'loads pages by replacement, preserves filters, and never prefetches',
      () async {
        repository.listResult = List<Cattle>.generate(
          20,
          (index) => syntheticCattle(ranchId: _ranchA, id: 'cattle-$index'),
        );
        expect(
          await service.load(
            query: const CattleSearch(
              earTag: ' TAG ',
              status: CattleStatus.inactive,
            ),
          ),
          isTrue,
        );
        expect(repository.listCalls, 1);
        expect(repository.listRequests.single.query.earTag, 'TAG');
        expect(
          repository.listRequests.single.query.status,
          CattleStatus.inactive,
        );
        expect(service.canGoNext, isTrue);

        repository.listResult = <Cattle>[
          syntheticCattle(ranchId: _ranchA, id: 'next'),
        ];
        expect(await service.nextPage(), isTrue);
        expect(repository.listCalls, 2);
        expect(repository.listRequests.last.query.page, 2);
        expect(repository.listRequests.last.query.earTag, 'TAG');
        expect(
          repository.listRequests.last.query.status,
          CattleStatus.inactive,
        );
        expect(service.animals.map((animal) => animal.id), <String>[
          syntheticCattleId('next'),
        ]);
        expect(service.canGoNext, isFalse);
        expect(service.canGoPrevious, isTrue);

        repository.listResult = <Cattle>[];
        expect(await service.previousPage(), isTrue);
        expect(repository.listRequests.last.query.page, 1);
        expect(service.status, CattleLoadStatus.ready);
        expect(service.animals, isEmpty);
      },
    );

    test(
      'keeps inactive records valid and exposes an immutable list',
      () async {
        repository.listResult = <Cattle>[
          syntheticCattle(
            ranchId: _ranchA,
            id: 'inactive',
            status: CattleStatus.inactive,
          ),
        ];
        expect(await service.load(), isTrue);
        expect(service.animals.single.status, CattleStatus.inactive);
        expect(() => service.animals.clear(), throwsUnsupportedError);
      },
    );

    test(
      'reload clears the displayed page while it revalidates and preserves calendar dates',
      () async {
        final first = syntheticCattle(ranchId: _ranchA, id: 'one');
        repository.listResult = <Cattle>[first];
        expect(await service.load(), isTrue);
        expect(service.animals.single.birthDate, const CattleDate(2020, 1, 2));

        final response = Completer<List<Cattle>>();
        repository.listCompleter = response;
        final pending = service.load();
        expect(service.status, CattleLoadStatus.loading);
        expect(service.animals, isEmpty);
        expect(repository.listCalls, 2);
        response.complete(<Cattle>[
          syntheticCattle(ranchId: _ranchA, id: 'one'),
        ]);
        expect(await pending, isTrue);
        expect(service.animals.single.birthDate, const CattleDate(2020, 1, 2));
      },
    );

    test(
      'invalid local search and unconfigured repository make no read call',
      () async {
        expect(
          await service.load(
            query: const CattleSearch(
              earTag: 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
            ),
          ),
          isFalse,
        );
        expect(service.error?.code, CattleFailureCode.invalidSearch);
        expect(repository.listCalls, 0);

        repository.configured = false;
        expect(await service.load(query: const CattleSearch()), isFalse);
        expect(service.error?.code, CattleFailureCode.configuration);
        expect(repository.listCalls, 0);
      },
    );

    test(
      'failed reads do not retry until an explicit load and recover from configuration failure',
      () async {
        repository.listFailure = const CattleFailure(CattleFailureCode.network);
        expect(await service.load(), isFalse);
        expect(service.error?.code, CattleFailureCode.network);
        expect(repository.listCalls, 1);

        repository.listFailure = null;
        repository.listResult = <Cattle>[
          syntheticCattle(ranchId: _ranchA, id: 'retry'),
        ];
        expect(repository.listCalls, 1);
        expect(await service.load(), isTrue);
        expect(repository.listCalls, 2);

        repository.configured = false;
        expect(await service.load(query: const CattleSearch()), isFalse);
        expect(service.error?.code, CattleFailureCode.configuration);
        expect(repository.listCalls, 2);
        repository.configured = true;
        expect(await service.load(), isTrue);
        expect(repository.listCalls, 3);
      },
    );

    test('rejects cross-ranch results', () async {
      repository.listResult = <Cattle>[
        syntheticCattle(ranchId: _ranchB, id: 'foreign'),
      ];
      expect(await service.load(), isFalse);
      expect(service.status, CattleLoadStatus.unavailable);
      expect(service.error?.code, CattleFailureCode.invalidResponse);
      expect(service.animals, isEmpty);
    });

    test('accepts UUID ranch identity with different letter casing', () async {
      repository.listResult = <Cattle>[
        syntheticCattle(ranchId: _ranchA.toUpperCase(), id: 'case-variant'),
      ];
      expect(await service.load(), isTrue);
      expect(service.animals.single.ranchId, _ranchA.toUpperCase());
    });

    test('rejects duplicate cattle identifiers in one page', () async {
      final duplicate = syntheticCattle(ranchId: _ranchA, id: 'duplicate');
      repository.listResult = <Cattle>[duplicate, duplicate];
      expect(await service.load(), isFalse);
      expect(service.error?.code, CattleFailureCode.invalidResponse);
      expect(service.animals, isEmpty);
    });

    test(
      'deduplicates same reads and discards a response after ranch changes',
      () async {
        final revisionBefore = service.revision;
        final pending = Completer<List<Cattle>>();
        repository.listCompleter = pending;
        final first = service.load();
        final duplicate = service.load();
        expect(repository.listCalls, 1);
        await harness.select(_ranchB);
        pending.complete(<Cattle>[
          syntheticCattle(ranchId: _ranchA, id: 'old'),
        ]);
        expect(await first, isFalse);
        expect(await duplicate, isFalse);
        expect(service.animals, isEmpty);
        expect(service.status, CattleLoadStatus.idle);
        expect(service.revision, revisionBefore + 1);
      },
    );

    test(
      'fences an old ranch-A response after A to B to A and permits explicit reload',
      () async {
        final revisionBefore = service.revision;
        final oldResponse = Completer<List<Cattle>>();
        repository.listCompleter = oldResponse;
        final oldRequest = service.load();
        await harness.select(_ranchB);
        await harness.select(_ranchA);

        repository.listCompleter = null;
        repository.listResult = <Cattle>[
          syntheticCattle(ranchId: _ranchA, id: 'fresh'),
        ];
        expect(await service.load(), isTrue);
        oldResponse.complete(<Cattle>[
          syntheticCattle(ranchId: _ranchA, id: 'stale'),
        ]);
        expect(await oldRequest, isFalse);
        expect(service.animals.single.id, syntheticCattleId('fresh'));
        expect(service.revision, revisionBefore + 2);
      },
    );

    test(
      'late permission failure after ranch switch cannot clear the new ranch view',
      () async {
        final oldProfileResponse = Completer<CattleProfile>();
        repository.profileCompleter = oldProfileResponse;
        final oldProfile = service.loadProfile(syntheticCattleId('old-detail'));

        await harness.select(_ranchB);
        repository.profileCompleter = null;
        repository.profileFailure = null;
        repository.listResult = <Cattle>[
          syntheticCattle(ranchId: _ranchB, id: 'new-ranch'),
        ];
        expect(await service.load(), isTrue);

        oldProfileResponse.completeError(
          const CattleFailure(CattleFailureCode.forbidden),
        );
        expect(await oldProfile, isFalse);
        expect(service.status, CattleLoadStatus.ready);
        expect(service.animals.single.ranchId, _ranchB);
      },
    );

    test(
      'revalidation clears list and profile immediately while both requests are pending',
      () async {
        final originalCattle = syntheticCattle(
          ranchId: _ranchA,
          id: 'original',
        );
        final originalProfileId = syntheticCattleId('original');
        repository.listResult = <Cattle>[originalCattle];
        repository.profileResult = CattleProfile(
          cattle: originalCattle,
          device: const CattleDevice(isAvailable: false),
        );
        expect(await service.load(), isTrue);
        expect(await service.loadProfile(originalProfileId), isTrue);

        final listResponse = Completer<List<Cattle>>();
        final profileResponse = Completer<CattleProfile>();
        repository.listCompleter = listResponse;
        repository.profileCompleter = profileResponse;
        final listPending = service.load();
        final profilePending = service.loadProfile(originalProfileId);
        expect(service.status, CattleLoadStatus.loading);
        expect(service.profileStatus, CattleLoadStatus.loading);
        expect(service.animals, isEmpty);
        expect(service.profile, isNull);

        listResponse.complete(<Cattle>[originalCattle]);
        profileResponse.complete(
          CattleProfile(
            cattle: originalCattle,
            device: const CattleDevice(isAvailable: false),
          ),
        );
        expect(await listPending, isTrue);
        expect(await profilePending, isTrue);
        expect(service.animals.single.id, originalCattle.id);
        expect(service.profile?.cattle.id, originalCattle.id);
      },
    );

    test(
      'permission failure clears both views and late independent reads cannot restore them',
      () async {
        final listResponse = Completer<List<Cattle>>();
        repository.listCompleter = listResponse;
        final listPending = service.load();
        repository.listCompleter = null;
        repository.profileFailure = const CattleFailure(
          CattleFailureCode.forbidden,
        );
        expect(await service.loadProfile('detail'), isFalse);
        expect(service.status, CattleLoadStatus.unavailable);
        expect(service.profileStatus, CattleLoadStatus.unavailable);
        expect(service.error?.code, CattleFailureCode.forbidden);
        listResponse.complete(<Cattle>[
          syntheticCattle(ranchId: _ranchA, id: 'late'),
        ]);
        expect(await listPending, isFalse);
        expect(service.animals, isEmpty);
        expect(service.profile, isNull);
      },
    );

    test(
      'permission failure from list invalidates a pending profile read',
      () async {
        final profileResponse = Completer<CattleProfile>();
        repository.profileCompleter = profileResponse;
        final profilePending = service.loadProfile(
          syntheticCattleId('pending-profile'),
        );
        repository.profileCompleter = null;
        repository.listFailure = const CattleFailure(
          CattleFailureCode.unauthenticated,
        );
        expect(await service.load(), isFalse);
        expect(service.status, CattleLoadStatus.unavailable);
        expect(service.profileStatus, CattleLoadStatus.unavailable);
        profileResponse.complete(
          CattleProfile(
            cattle: syntheticCattle(ranchId: _ranchA, id: 'pending-profile'),
            device: const CattleDevice(isAvailable: false),
          ),
        );
        expect(await profilePending, isFalse);
        expect(service.profile, isNull);
      },
    );

    test(
      'empty profile id clears any previous profile without another read',
      () async {
        final profileId = syntheticCattleId('saved-profile');
        repository.profileResult = CattleProfile(
          cattle: syntheticCattle(ranchId: _ranchA, id: 'saved-profile'),
          device: const CattleDevice(isAvailable: false),
        );
        expect(await service.loadProfile(profileId), isTrue);
        final requests = repository.profileCalls;
        expect(await service.loadProfile('  '), isFalse);
        expect(service.profile, isNull);
        expect(service.profileError?.code, CattleFailureCode.notFound);
        expect(repository.profileCalls, requests);
      },
    );

    test(
      'profile response must match both requested identity and ranch',
      () async {
        final requestedId = syntheticCattleId('requested');
        repository.profileResult = CattleProfile(
          cattle: syntheticCattle(ranchId: _ranchA, id: 'other'),
          device: const CattleDevice(isAvailable: false),
        );
        expect(await service.loadProfile(requestedId), isFalse);
        expect(service.profileError?.code, CattleFailureCode.invalidResponse);
      },
    );

    test('superseded profile reads cannot replace a newer profile', () async {
      final oldId = syntheticCattleId('old-id');
      final newId = syntheticCattleId('new-id');
      final oldResponse = Completer<CattleProfile>();
      repository.profileCompleter = oldResponse;
      final oldRequest = service.loadProfile(oldId);
      repository.profileCompleter = null;
      repository.profileResult = CattleProfile(
        cattle: syntheticCattle(ranchId: _ranchA, id: 'new-id'),
        device: const CattleDevice(isAvailable: false),
      );
      expect(await service.loadProfile(newId), isTrue);
      oldResponse.complete(
        CattleProfile(
          cattle: syntheticCattle(ranchId: _ranchA, id: 'old-id'),
          device: const CattleDevice(isAvailable: false),
        ),
      );
      expect(await oldRequest, isFalse);
      expect(service.profile?.cattle.id, newId);
    });

    test(
      'facade notifications do not trigger reads and same context keeps current view',
      () async {
        repository.listResult = <Cattle>[
          syntheticCattle(ranchId: _ranchA, id: 'one'),
        ];
        await service.load();
        final current = harness.access.context!;
        harness.access.notifyListeners();
        expect(identical(harness.access.context, current), isTrue);
        expect(service.animals.single.id, syntheticCattleId('one'));
        expect(repository.listCalls, 1);
      },
    );

    test('logout clears scope and disposal fences pending reads', () async {
      final response = Completer<List<Cattle>>();
      repository.listCompleter = response;
      final pending = service.load();
      await harness.auth.signOut();
      expect(service.hasContext, isFalse);
      expect(service.query, const CattleSearch());
      expect(service.animals, isEmpty);
      service.dispose();
      expect(service.hasContext, isFalse);
      expect(service.animals, isEmpty);
      expect(service.profile, isNull);
      response.complete(<Cattle>[
        syntheticCattle(ranchId: _ranchA, id: 'late'),
      ]);
      expect(await pending, isFalse);
    });

    test(
      'same-UID logout and login installs a new scope and rejects the old response',
      () async {
        final response = Completer<List<Cattle>>();
        repository.listCompleter = response;
        final pending = service.load();
        final oldContext = harness.access.context;

        expect(await harness.auth.signOut(), isTrue);
        expect(service.hasContext, isFalse);
        expect(
          await harness.auth.signIn('user@example.test', 'synthetic-password'),
          isTrue,
        );
        expect(harness.selection.select(_ranchA), isTrue);
        expect(identical(harness.access.context, oldContext), isFalse);

        response.complete(<Cattle>[
          syntheticCattle(ranchId: _ranchA, id: 'old-session'),
        ]);
        expect(await pending, isFalse);
        expect(service.animals, isEmpty);
        expect(service.status, CattleLoadStatus.idle);
      },
    );
  });
}

const String _ranchA = 'a1111111-1111-4111-8111-111111111111';
const String _ranchB = 'b2222222-2222-4222-8222-222222222222';

RanchAccess _ranch(String id) => RanchAccess(
  ranchId: id,
  scope: AccessScope.read,
  name: 'Ranch $id',
  region: 'Synthetic region',
  district: 'Synthetic district',
);

final class _Harness {
  _Harness()
    : identity = FakeAuthenticationRepository(),
      accounts = FakeAccountRepository(
        account: syntheticIamAccount,
        ranches: <RanchAccess>[_ranch(_ranchA), _ranch(_ranchB)],
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
  final List<CattleReadService> services = <CattleReadService>[];

  CattleReadService createService(FakeCattleRepository repository) {
    final created = CattleReadService(access: access, cattle: repository);
    services.add(created);
    return created;
  }

  Future<void> initializeAndSelect(String ranchId) async {
    await auth.initialize();
    await select(ranchId);
  }

  Future<void> select(String ranchId) async {
    expect(selection.select(ranchId), isTrue);
  }

  void dispose() {
    for (final item in services) {
      item.dispose();
    }
    access.dispose();
    selection.dispose();
    auth.dispose();
    lifecycle.dispose();
    unawaited(identity.close());
  }
}
