import 'dart:async';

import 'package:ichu_mobile_app/features/iam/application/facades/authorized_ranch_session.dart';
import 'package:ichu_mobile_app/features/iam/application/services/auth_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/authentication_lifecycle.dart';
import 'package:ichu_mobile_app/features/iam/application/services/ranch_selection_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_access.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/waterer.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/water_history_query.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/repositories/waterer_repository.dart';

import 'fake_iam_repositories.dart';

const watererRanchA = 'a1111111-1111-4111-8111-111111111111';
const watererRanchB = 'b2222222-2222-4222-8222-222222222222';
const watererId = 'c3333333-3333-4333-8333-333333333333';
const watererControllerId = 'd4444444-4444-4444-8444-444444444444';

/// Synthetic server snapshots; these fixtures do not contact a live backend.
WatererStatus watererStatusFixture({
  String ranchId = watererRanchA,
  String id = watererId,
  String? controllerId = watererControllerId,
  WaterControllerStatus controllerStatus = WaterControllerStatus.communicating,
  WaterMeasurementStatus measurementStatus = WaterMeasurementStatus.valid,
  WaterRangeStatus rangeStatus = WaterRangeStatus.withinRange,
  WaterReading? reading,
  bool hasReading = true,
}) => WatererStatus(
  waterTroughId: id,
  name: 'North trough',
  lotId: null,
  minimumCelsius: 10,
  maximumCelsius: 20,
  controllerStatus: controllerStatus,
  controllerId: controllerId,
  controllerAssignedAt: controllerId == null ? null : DateTime.utc(2026, 11, 1),
  lastCommunicationAt: hasReading ? DateTime.utc(2026, 11, 14, 12) : null,
  measurementStatus: measurementStatus,
  rangeStatus: rangeStatus,
  latestReading: hasReading
      ? reading ?? waterReadingFixture(ranchId: ranchId, troughId: id)
      : null,
  evaluatedAt: DateTime.utc(2026, 11, 14, 12),
);

WaterReading waterReadingFixture({
  String ranchId = watererRanchA,
  String troughId = watererId,
  DateTime? capturedAt,
  String id = 'e5555555-5555-4555-8555-555555555555',
  bool isValid = true,
}) => WaterReading(
  id: id,
  readingId: id,
  ranchId: ranchId,
  waterTroughId: troughId,
  controllerId: watererControllerId,
  gatewayId: 'f6666666-6666-4666-8666-666666666666',
  temperatureCelsius: 16.5,
  isValid: isValid,
  heaterState: WaterHeaterState.on,
  capturedAt: capturedAt ?? DateTime.utc(2026, 11, 14, 5),
  receivedAt: DateTime.utc(2026, 11, 14, 12),
);

WaterHistoryPage waterHistoryFixture(
  WaterHistoryQuery query, {
  int total = 21,
  List<WaterReading>? items,
}) => WaterHistoryPage(
  controllerId: watererControllerId,
  from: query.from.toUtc(),
  to: query.to.toUtc(),
  page: query.page,
  pageSize: query.pageSize,
  totalCount: total,
  items:
      items ??
      [
        waterReadingFixture(
          capturedAt: query.from.add(const Duration(seconds: 1)),
        ),
      ],
);

final class FakeWatererRepository implements WatererRepository {
  @override
  bool isConfigured = true;
  final listRequests = <String>[];
  final detailRequests = <({String ranchId, String id})>[];
  final historyRequests =
      <({String ranchId, String controllerId, WaterHistoryQuery query})>[];
  Future<List<WatererStatus>> Function(String)? onList;
  Future<WatererStatus> Function(String, String)? onDetail;
  Future<WaterHistoryPage> Function(String, String, WaterHistoryQuery)?
  onHistory;

  @override
  Future<List<WatererStatus>> list(String ranchId) async {
    listRequests.add(ranchId);
    return onList == null
        ? [watererStatusFixture(ranchId: ranchId)]
        : onList!(ranchId);
  }

  @override
  Future<WatererStatus> detail(String ranchId, String id) async {
    detailRequests.add((ranchId: ranchId, id: id));
    return onDetail == null
        ? watererStatusFixture(ranchId: ranchId, id: id)
        : onDetail!(ranchId, id);
  }

  @override
  Future<WaterHistoryPage> history(
    String ranchId,
    String controllerId,
    WaterHistoryQuery query,
  ) async {
    historyRequests.add((
      ranchId: ranchId,
      controllerId: controllerId,
      query: query,
    ));
    return onHistory == null
        ? waterHistoryFixture(query)
        : onHistory!(ranchId, controllerId, query);
  }
}

final class WatererTestSession {
  WatererTestSession({
    AccountRole role = AccountRole.ranchManager,
    AccessScope scope = AccessScope.read,
  }) {
    identity = FakeAuthenticationRepository();
    accounts = FakeAccountRepository(
      account: IamAccount(
        id: '11111111-1111-4111-8111-111111111111',
        email: 'user@example.test',
        role: role,
        status: 'Active',
      ),
      ranches: [
        for (final id in [watererRanchA, watererRanchB])
          RanchAccess(
            ranchId: id,
            scope: scope,
            name: 'Selected ranch',
            region: 'Synthetic region',
            district: 'Synthetic district',
          ),
      ],
    );
    lifecycle = AuthenticationLifecycle(identity);
    auth = AuthService(authentication: lifecycle, accounts: accounts);
    selection = RanchSelectionService(session: auth);
    access = AuthorizedRanchSession(
      session: auth,
      selection: selection,
      authentication: identity,
    );
  }

  late final FakeAuthenticationRepository identity;
  late final FakeAccountRepository accounts;
  late final AuthenticationLifecycle lifecycle;
  late final AuthService auth;
  late final RanchSelectionService selection;
  late final AuthorizedRanchSession access;

  Future<void> initialize() async {
    await auth.initialize();
    selection.select(watererRanchA);
  }

  Future<void> dispose() async {
    access.dispose();
    selection.dispose();
    auth.dispose();
    lifecycle.dispose();
    await identity.close();
  }
}
