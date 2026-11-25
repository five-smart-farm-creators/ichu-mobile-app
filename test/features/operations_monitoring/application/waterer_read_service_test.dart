import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/application/services/waterer_read_service.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/monitoring_failure.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/waterer.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/water_history_query.dart';

import '../../../support/waterer_test_support.dart';

void main() {
  late WatererTestSession session;
  late FakeWatererRepository repository;
  late WatererReadService service;
  final query = WaterHistoryQuery(
    from: DateTime.utc(2026, 11, 14),
    to: DateTime.utc(2026, 11, 15),
  );
  setUp(() async {
    session = WatererTestSession();
    await session.initialize();
    repository = FakeWatererRepository();
    service = WatererReadService(access: session.access, waterers: repository);
  });
  tearDown(() async {
    service.dispose();
    await session.dispose();
  });

  test(
    'loads list, detail and distinct controller pages for the selected ranch',
    () async {
      expect(await service.loadList(), isTrue);
      expect(repository.listRequests.single, watererRanchA);
      expect(await service.loadDetail(watererId), isTrue);
      expect(await service.loadHistory(query), isTrue);
      expect(await service.loadHistory(query.atPage(2)), isTrue);
      expect(service.history!.page, 2);
      expect(service.history!.items, hasLength(1));
      expect(repository.historyRequests.last.ranchId, watererRanchA);
      expect(repository.historyRequests.last.controllerId, watererControllerId);
      expect(repository.historyRequests.last.query.from, query.from);
    },
  );

  test(
    'supports empty list, absent readings and no assigned controller',
    () async {
      repository.onList = (_) async => [];
      repository.onDetail = (_, _) async => watererStatusFixture(
        controllerId: null,
        hasReading: false,
        controllerStatus: WaterControllerStatus.noController,
        measurementStatus: WaterMeasurementStatus.unavailable,
        rangeStatus: WaterRangeStatus.unavailable,
      );
      expect(await service.loadList(), isTrue);
      expect(service.listStatus, WatererLoadStatus.ready);
      expect(service.items, isEmpty);
      expect(await service.loadDetail(watererId), isTrue);
      expect(service.detail!.latestReading, isNull);
      expect(await service.loadHistory(query), isFalse);
      expect(repository.historyRequests, isEmpty);
    },
  );

  test(
    'rejects invalid periods before transport and retries a corrected query',
    () async {
      await service.loadDetail(watererId);
      expect(
        await service.loadHistory(
          WaterHistoryQuery(from: query.to, to: query.from),
        ),
        isFalse,
      );
      expect(
        service.historyError!.code,
        MonitoringFailureCode.invalidHistoryQuery,
      );
      expect(repository.historyRequests, isEmpty);
      expect(await service.loadHistory(query), isTrue);
    },
  );

  for (final failure in [
    MonitoringFailureCode.unauthenticated,
    MonitoringFailureCode.forbidden,
    MonitoringFailureCode.network,
    MonitoringFailureCode.serviceUnavailable,
  ]) {
    test(
      '$failure discards snapshots across all workflows and allows fresh reads',
      () async {
        await service.loadList();
        await service.loadDetail(watererId);
        await service.loadHistory(query);
        repository.onHistory = (_, _, _) async =>
            throw MonitoringFailure(failure);
        expect(await service.loadHistory(query.atPage(2)), isFalse);
        expect(service.items, isEmpty);
        expect(service.detail, isNull);
        expect(service.history, isNull);
        expect(service.detailError!.code, failure);
        repository.onHistory = null;
        expect(await service.loadDetail(watererId), isTrue);
        expect(await service.loadHistory(query), isTrue);
      },
    );
  }

  test('ranch changes fence late list, detail and history responses', () async {
    final pendingList = Completer<List<WatererStatus>>();
    final pendingHistory = Completer<WaterHistoryPage>();
    repository.onList = (_) => pendingList.future;
    await service.loadDetail(watererId);
    repository.onHistory = (_, _, _) => pendingHistory.future;
    final listRequest = service.loadList();
    final historyRequest = service.loadHistory(query);
    session.selection.select(watererRanchB);
    pendingList.complete([watererStatusFixture()]);
    pendingHistory.complete(waterHistoryFixture(query));
    expect(await listRequest, isFalse);
    expect(await historyRequest, isFalse);
    expect(service.items, isEmpty);
    expect(service.detail, isNull);
    expect(service.history, isNull);

    final pendingDetail = Completer<WatererStatus>();
    repository.onDetail = (_, _) => pendingDetail.future;
    final detailRequest = service.loadDetail(watererId);
    session.selection.select(watererRanchA);
    pendingDetail.complete(watererStatusFixture(ranchId: watererRanchB));
    expect(await detailRequest, isFalse);
    expect(service.detail, isNull);
  });

  test(
    'detail refresh invalidates history for a previous controller assignment',
    () async {
      await service.loadDetail(watererId);
      final response = Completer<WaterHistoryPage>();
      repository.onHistory = (_, _, _) => response.future;
      final request = service.loadHistory(query);
      repository.onDetail = (_, _) async =>
          watererStatusFixture(controllerId: null, hasReading: false);
      await service.loadDetail(watererId);
      response.complete(waterHistoryFixture(query));
      expect(await request, isFalse);
      expect(service.history, isNull);
    },
  );

  test('logout and silent SDK identity changes hide all snapshots', () async {
    await service.loadList();
    await service.loadDetail(watererId);
    await service.loadHistory(query);
    session.identity.user = null;
    expect(service.hasContext, isFalse);
    expect(service.items, isEmpty);
    expect(service.detail, isNull);
    expect(service.history, isNull);
    expect(await service.loadList(), isFalse);
    await session.auth.signOut();
    expect(await service.loadDetail(watererId), isFalse);
    expect(await service.loadHistory(query), isFalse);
  });

  test('backgrounding clears snapshots and fences pending responses', () async {
    await service.loadDetail(watererId);
    final response = Completer<WaterHistoryPage>();
    repository.onHistory = (_, _, _) => response.future;
    final request = service.loadHistory(query);
    service.setActive(false);
    expect(await service.loadList(), isFalse);
    expect(service.detail, isNull);
    service.setActive(true);
    response.complete(waterHistoryFixture(query));
    expect(await request, isFalse);
    expect(service.history, isNull);
    expect(service.detailStatus, WatererLoadStatus.idle);
  });

  test('rejects snapshots and pages belonging to another ranch', () async {
    repository.onList = (_) async => [
      watererStatusFixture(ranchId: watererRanchB),
    ];
    expect(await service.loadList(), isFalse);
    expect(service.items, isEmpty);
    repository.onDetail = (_, _) async =>
        watererStatusFixture(id: watererRanchB);
    expect(await service.loadDetail(watererId), isFalse);
    expect(service.detail, isNull);
    repository.onDetail = null;
    await service.loadDetail(watererId);
    repository.onHistory = (_, _, q) async => waterHistoryFixture(
      q,
      items: [waterReadingFixture(ranchId: watererRanchB)],
    );
    expect(await service.loadHistory(query), isFalse);
    expect(service.history, isNull);
  });

  test(
    'sanitizes unexpected failures and never uses an unconfigured adapter',
    () async {
      repository.isConfigured = false;
      expect(await service.loadList(), isFalse);
      expect(repository.listRequests, isEmpty);
      repository.isConfigured = true;
      repository.onDetail = (_, _) async =>
          throw StateError('private server detail');
      expect(await service.loadDetail(watererId), isFalse);
      expect(service.detailError!.code, MonitoringFailureCode.unknown);
      expect(service.detailError.toString(), isNot(contains('private')));
    },
  );

  for (final role in AccountRole.values) {
    test('$role can read with server-issued Read access', () async {
      final otherSession = WatererTestSession(role: role);
      await otherSession.initialize();
      final otherService = WatererReadService(
        access: otherSession.access,
        waterers: repository,
      );
      try {
        expect(await otherService.loadList(), isTrue);
      } finally {
        otherService.dispose();
        await otherSession.dispose();
      }
    });
  }
}
