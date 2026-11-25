import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/iam/application/services/auth_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/authentication_lifecycle.dart';
import 'package:ichu_mobile_app/features/iam/application/services/herd_advisory_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/ranch_selection_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/herd_advisory.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/herd_advisory_failure.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_access.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_summary.dart';

import '../../../support/fake_herd_advisory_repository.dart';
import '../../../support/fake_iam_repositories.dart';

const _ranchId = '11111111-1111-4111-8111-111111111111';
const _advisoryId = '22222222-2222-4222-8222-222222222222';
const _veterinarianId = '33333333-3333-4333-8333-333333333333';
final _now = DateTime.utc(2026, 11, 13, 12);

void main() {
  test('trims a shared code before the authenticated ranch lookup', () async {
    final repository = FakeHerdAdvisoryRepository(
      ranchResult: const RanchSummary(
        ranchId: _ranchId,
        name: 'Test ranch',
        region: 'Test region',
        district: 'Test district',
      ),
    );
    final harness = await _Harness.create(repository);
    addTearDown(harness.dispose);

    final result = await harness.service.findRanchByAccessCode(' abcd2345 ');

    expect(result.ranchId, _ranchId);
    expect(repository.lookupCalls, 1);
    expect(repository.lastAccessCode, 'abcd2345');
  });

  test('rejects an empty access code without sending a lookup', () async {
    final repository = FakeHerdAdvisoryRepository();
    final harness = await _Harness.create(repository);
    addTearDown(harness.dispose);

    await expectLater(
      harness.service.findRanchByAccessCode('  '),
      throwsA(
        isA<HerdAdvisoryFailure>().having(
          (failure) => failure.code,
          'code',
          HerdAdvisoryFailureCode.invalidRequest,
        ),
      ),
    );

    expect(repository.lookupCalls, 0);
  });

  test(
    'trims a request reason and sends the ranch returned by lookup',
    () async {
      final repository = FakeHerdAdvisoryRepository(requestResult: _advisory());
      final harness = await _Harness.create(repository);
      addTearDown(harness.dispose);

      final result = await harness.service.requestAccess(
        ranchId: _ranchId,
        reason: '  Herd health review  ',
      );

      expect(result.id, _advisoryId);
      expect(repository.requestCalls, 1);
      expect(repository.lastRanchId, _ranchId);
      expect(repository.lastReason, 'Herd health review');
    },
  );

  test(
    'rejects invalid request details before calling the repository',
    () async {
      final repository = FakeHerdAdvisoryRepository();
      final harness = await _Harness.create(repository);
      addTearDown(harness.dispose);

      for (final reason in <String>[
        ' ',
        List<String>.filled(1001, 'x').join(),
      ]) {
        await expectLater(
          harness.service.requestAccess(ranchId: _ranchId, reason: reason),
          throwsA(isA<HerdAdvisoryFailure>()),
        );
      }
      await expectLater(
        harness.service.requestAccess(ranchId: 'invalid', reason: 'Review'),
        throwsA(isA<HerdAdvisoryFailure>()),
      );
      expect(repository.requestCalls, 0);
    },
  );

  test(
    'requires a selected server-authorized ranch for advisory history',
    () async {
      final repository = FakeHerdAdvisoryRepository();
      final harness = await _Harness.create(repository);
      addTearDown(harness.dispose);

      await expectLater(
        harness.service.advisoriesForSelectedRanch(),
        throwsA(
          isA<HerdAdvisoryFailure>().having(
            (failure) => failure.code,
            'code',
            HerdAdvisoryFailureCode.contextUnavailable,
          ),
        ),
      );
      expect(repository.listCalls, 0);
    },
  );

  test(
    'does not turn a selected read scope into local write authorization',
    () async {
      final repository = FakeHerdAdvisoryRepository(requestResult: _advisory());
      final harness = await _Harness.create(
        repository,
        scope: AccessScope.read,
        selectRanch: true,
      );
      addTearDown(harness.dispose);

      await harness.service.decideForSelectedRanch(
        advisoryId: _advisoryId,
        decision: HerdAdvisoryDecision.reject,
      );

      expect(repository.decisionCalls, 1);
      expect(repository.lastRanchId, _ranchId);
      expect(repository.lastDecision, HerdAdvisoryDecision.reject);
    },
  );

  test('grant requires a supported scope and future expiration', () async {
    final repository = FakeHerdAdvisoryRepository(requestResult: _advisory());
    final harness = await _Harness.create(
      repository,
      scope: AccessScope.manage,
      selectRanch: true,
    );
    addTearDown(harness.dispose);

    await expectLater(
      harness.service.decideForSelectedRanch(
        advisoryId: _advisoryId,
        decision: HerdAdvisoryDecision.grant,
        scope: AccessScope.manage,
        expiresAt: _now.add(const Duration(days: 1)),
      ),
      throwsA(isA<HerdAdvisoryFailure>()),
    );
    await expectLater(
      harness.service.decideForSelectedRanch(
        advisoryId: _advisoryId,
        decision: HerdAdvisoryDecision.grant,
        scope: AccessScope.read,
        expiresAt: _now,
      ),
      throwsA(isA<HerdAdvisoryFailure>()),
    );
    expect(repository.decisionCalls, 0);

    await harness.service.decideForSelectedRanch(
      advisoryId: _advisoryId,
      decision: HerdAdvisoryDecision.grant,
      scope: AccessScope.clinicalWrite,
      expiresAt: _now.add(const Duration(days: 1)),
    );
    expect(repository.decisionCalls, 1);
    expect(repository.lastScope, AccessScope.clinicalWrite);
  });

  test(
    'direct grants require a real account identifier and explicit scope',
    () async {
      final repository = FakeHerdAdvisoryRepository(requestResult: _advisory());
      final harness = await _Harness.create(
        repository,
        scope: AccessScope.manage,
        selectRanch: true,
      );
      addTearDown(harness.dispose);

      await expectLater(
        harness.service.grantDirectly(
          veterinarianId: 'unknown',
          scope: AccessScope.read,
          expiresAt: _now.add(const Duration(days: 1)),
        ),
        throwsA(isA<HerdAdvisoryFailure>()),
      );
      await harness.service.grantDirectly(
        veterinarianId: _veterinarianId,
        scope: AccessScope.read,
        expiresAt: _now.add(const Duration(days: 1)),
      );
      expect(repository.directGrantCalls, 1);
      expect(repository.lastVeterinarianId, _veterinarianId);
      expect(repository.lastScope, AccessScope.read);
    },
  );
}

HerdAdvisory _advisory() => HerdAdvisory(
  id: _advisoryId,
  veterinarianId: _veterinarianId,
  ranchId: _ranchId,
  reason: 'Herd health review',
  status: HerdAdvisoryStatus.pending,
  scope: AccessScope.read,
  requestedAt: _now,
);

final class _Harness {
  _Harness._({
    required this.identity,
    required this.lifecycle,
    required this.auth,
    required this.selection,
    required this.service,
  });

  final FakeAuthenticationRepository identity;
  final AuthenticationLifecycle lifecycle;
  final AuthService auth;
  final RanchSelectionService selection;
  final HerdAdvisoryService service;

  static Future<_Harness> create(
    FakeHerdAdvisoryRepository repository, {
    AccessScope scope = AccessScope.read,
    bool selectRanch = false,
  }) async {
    final identity = FakeAuthenticationRepository();
    final lifecycle = AuthenticationLifecycle(identity);
    final auth = AuthService(
      authentication: lifecycle,
      accounts: FakeAccountRepository(
        ranches: <RanchAccess>[
          RanchAccess(
            ranchId: _ranchId,
            scope: scope,
            name: 'Test ranch',
            region: 'Test region',
            district: 'Test district',
          ),
        ],
      ),
    );
    await auth.initialize();
    final selection = RanchSelectionService(session: auth, now: () => _now);
    if (selectRanch) selection.select(_ranchId);
    return _Harness._(
      identity: identity,
      lifecycle: lifecycle,
      auth: auth,
      selection: selection,
      service: HerdAdvisoryService(
        advisories: repository,
        selection: selection,
        now: () => _now,
      ),
    );
  }

  Future<void> dispose() async {
    selection.dispose();
    auth.dispose();
    lifecycle.dispose();
    await identity.close();
  }
}
