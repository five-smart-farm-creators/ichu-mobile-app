import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/cattle_information/application/services/cattle_management_service.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle_commands.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle_date.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle_failure.dart';
import 'package:ichu_mobile_app/features/iam/application/facades/authorized_ranch_session.dart';
import 'package:ichu_mobile_app/features/iam/application/services/auth_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/authentication_lifecycle.dart';
import 'package:ichu_mobile_app/features/iam/application/services/ranch_selection_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_user.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_access.dart';

import '../../../support/fake_cattle_command_repository.dart';
import '../../../support/fake_cattle_repository.dart';
import '../../../support/fake_iam_repositories.dart';

void main() {
  group('CattleManagementService', () {
    test('offers no write and sends nothing without a manage grant', () async {
      for (final scope in <AccessScope>[
        AccessScope.read,
        AccessScope.clinicalWrite,
      ]) {
        final fixture = await _ready(scope: scope);
        addTearDown(fixture.dispose);

        expect(fixture.service.canManage, isFalse);
        expect(
          await fixture.service.changeStage(
            _current(),
            CattleStageChange(
              stage: CattleStage.milkingCow,
              validFrom: const CattleDate(2026, 1, 1),
            ),
          ),
          isNull,
        );
        expect(fixture.service.error?.code, CattleFailureCode.forbidden);
        expect(fixture.commands.calls, 0);
      }
    });

    test('requires configured commands before offering writes', () async {
      final fixture = await _ready();
      addTearDown(fixture.dispose);
      fixture.commands.configured = false;

      expect(fixture.service.canManage, isFalse);
    });

    test('validates input and ranch ownership before sending', () async {
      final fixture = await _ready();
      addTearDown(fixture.dispose);

      expect(
        await fixture.service.correct(
          _current(),
          CattleCorrection(
            earTag: '   ',
            breed: CattleBreed.crossbred,
            sex: CattleSex.female,
            birthDate: const CattleDate(2020, 1, 2),
          ),
        ),
        isNull,
      );
      expect(fixture.service.error?.code, CattleFailureCode.invalidInput);

      final foreign = _current(ranchId: _ranchB);
      expect(
        await fixture.service.deactivate(
          foreign,
          CattleExit(
            reason: CattleExitReason.death,
            exitDate: const CattleDate(2026, 1, 1),
          ),
        ),
        isNull,
      );
      expect(fixture.service.error?.code, CattleFailureCode.contextUnavailable);
      expect(fixture.commands.calls, 0);
    });

    test(
      'sends one version-checked write and returns the saved animal',
      () async {
        final fixture = await _ready();
        addTearDown(fixture.dispose);
        final saved = syntheticCattle(
          ranchId: _ranchA,
          id: _cattleId,
          earTag: 'NEW',
        );
        fixture.commands.result = saved;
        final current = _current();

        final result = await fixture.service.correct(
          current,
          CattleCorrection(
            earTag: 'NEW',
            breed: CattleBreed.crossbred,
            sex: CattleSex.female,
            birthDate: const CattleDate(2020, 1, 2),
          ),
        );

        expect(result, same(saved));
        final request = fixture.commands.requests.single;
        expect(request.operation, 'correct');
        expect(request.ranchId, _ranchA);
        expect(request.cattleId, current.id);
        expect(request.expectedVersion, current.version);
        expect(fixture.service.isSaving, isFalse);
        expect(fixture.service.error, isNull);
      },
    );

    test('runs one write at a time and ignores overlapping requests', () async {
      final fixture = await _ready();
      addTearDown(fixture.dispose);
      final completer = Completer<Cattle>();
      fixture.commands.completer = completer;
      final change = CattleStageChange(
        stage: CattleStage.milkingCow,
        validFrom: const CattleDate(2026, 1, 1),
      );
      final first = fixture.service.changeStage(_current(), change);
      expect(fixture.service.isSaving, isTrue);

      final overlapping = await fixture.service.deactivate(
        _current(),
        CattleExit(
          reason: CattleExitReason.sale,
          exitDate: const CattleDate(2026, 1, 1),
        ),
      );
      expect(overlapping, isNull);
      expect(fixture.commands.calls, 1);

      final saved = syntheticCattle(ranchId: _ranchA, id: _cattleId);
      completer.complete(saved);
      expect(await first, same(saved));
      expect(fixture.service.isSaving, isFalse);
    });

    test('discards a late result after the ranch context changes', () async {
      final fixture = await _ready();
      addTearDown(fixture.dispose);
      final completer = Completer<Cattle>();
      fixture.commands.completer = completer;
      final pending = fixture.service.register(
        CattleRegistration(
          earTag: 'PE-0001',
          breed: CattleBreed.brownSwiss,
          sex: CattleSex.female,
          birthDate: const CattleDate(2024, 3, 1),
          lifeStage: CattleStage.calf,
        ),
      );

      expect(fixture.selection.select(_ranchB), isTrue);
      completer.complete(syntheticCattle(ranchId: _ranchA, id: _cattleId));

      expect(await pending, isNull);
      expect(fixture.service.isSaving, isFalse);
      expect(fixture.service.error, isNull);
      expect(fixture.commands.calls, 1);
    });

    test('keeps permission failures visible and never retries', () async {
      final fixture = await _ready();
      addTearDown(fixture.dispose);
      fixture.commands.failure = const CattleFailure(
        CattleFailureCode.forbidden,
      );

      expect(
        await fixture.service.deactivate(
          _current(),
          CattleExit(
            reason: CattleExitReason.theft,
            exitDate: const CattleDate(2026, 1, 1),
          ),
        ),
        isNull,
      );
      expect(fixture.service.error?.code, CattleFailureCode.forbidden);
      expect(fixture.commands.calls, 1);
    });

    test('reports unconfirmed outcomes once and clears on request', () async {
      final fixture = await _ready();
      addTearDown(fixture.dispose);
      fixture.commands.failure = const CattleFailure(
        CattleFailureCode.outcomeUnknown,
      );

      await fixture.service.changeStage(
        _current(),
        CattleStageChange(
          stage: CattleStage.milkingCow,
          validFrom: const CattleDate(2026, 1, 1),
        ),
      );
      expect(fixture.service.error?.code, CattleFailureCode.outcomeUnknown);
      expect(fixture.service.requiresReload, isTrue);
      expect(fixture.commands.calls, 1);

      fixture.service.clearError();
      expect(fixture.service.error, isNull);
      expect(fixture.service.requiresReload, isFalse);
    });

    test('a denied write does not ask for a reload', () async {
      final fixture = await _ready();
      addTearDown(fixture.dispose);
      fixture.commands.failure = const CattleFailure(
        CattleFailureCode.forbidden,
      );

      await fixture.service.changeStage(
        _current(),
        CattleStageChange(
          stage: CattleStage.milkingCow,
          validFrom: const CattleDate(2026, 1, 1),
        ),
      );
      expect(fixture.service.requiresReload, isFalse);
      expect(fixture.service.isSaving, isFalse);
    });

    test('maps unexpected errors to a sanitized unknown failure', () async {
      final fixture = await _ready();
      addTearDown(fixture.dispose);
      fixture.commands.failure = StateError('sensitive-sdk-detail');

      await fixture.service.register(
        CattleRegistration(
          earTag: 'PE-0001',
          breed: CattleBreed.brownSwiss,
          sex: CattleSex.female,
          birthDate: const CattleDate(2024, 3, 1),
          lifeStage: CattleStage.calf,
        ),
      );
      expect(fixture.service.error?.code, CattleFailureCode.unknown);
      expect(
        fixture.service.error.toString(),
        isNot(contains('sensitive-sdk-detail')),
      );
    });
  });
}

const _ranchA = '11111111-1111-4111-8111-111111111111';
const _ranchB = '22222222-2222-4222-8222-222222222222';
const _cattleId = '33333333-3333-4333-8333-333333333333';

const _identity = AuthUser(
  uid: 'cattle-management-user',
  email: 'rancher@example.test',
  emailVerified: true,
);

const _account = IamAccount(
  id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  email: 'rancher@example.test',
  role: AccountRole.ranchManager,
  status: 'active',
);

Cattle _current({String ranchId = _ranchA}) =>
    syntheticCattle(ranchId: ranchId, id: _cattleId);

Future<_Fixture> _ready({AccessScope scope = AccessScope.manage}) async {
  final authentication = FakeAuthenticationRepository(user: _identity);
  final accounts = FakeAccountRepository(
    account: _account,
    ranches: <RanchAccess>[
      RanchAccess(
        ranchId: _ranchA,
        scope: scope,
        name: 'Ranch A',
        region: 'Synthetic region',
        district: 'Synthetic district',
      ),
      const RanchAccess(
        ranchId: _ranchB,
        scope: AccessScope.read,
        name: 'Ranch B',
        region: 'Synthetic region',
        district: 'Synthetic district',
      ),
    ],
  );
  final lifecycle = AuthenticationLifecycle(authentication);
  final auth = AuthService(authentication: lifecycle, accounts: accounts);
  await auth.initialize();
  final selection = RanchSelectionService(session: auth);
  expect(selection.select(_ranchA), isTrue);
  final access = AuthorizedRanchSession(
    session: auth,
    selection: selection,
    authentication: authentication,
  );
  final commands = FakeCattleCommandRepository();
  final service = CattleManagementService(
    access: access,
    commands: commands,
    clock: () => DateTime.utc(2026, 11, 13),
  );
  return _Fixture(
    authentication: authentication,
    lifecycle: lifecycle,
    auth: auth,
    selection: selection,
    access: access,
    commands: commands,
    service: service,
  );
}

final class _Fixture {
  _Fixture({
    required this.authentication,
    required this.lifecycle,
    required this.auth,
    required this.selection,
    required this.access,
    required this.commands,
    required this.service,
  });

  final FakeAuthenticationRepository authentication;
  final AuthenticationLifecycle lifecycle;
  final AuthService auth;
  final RanchSelectionService selection;
  final AuthorizedRanchSession access;
  final FakeCattleCommandRepository commands;
  final CattleManagementService service;

  void dispose() {
    service.dispose();
    access.dispose();
    selection.dispose();
    auth.dispose();
    lifecycle.dispose();
    unawaited(authentication.close());
  }
}
