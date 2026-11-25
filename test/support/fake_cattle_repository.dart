import 'dart:async';

import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle_date.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle_failure.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle_search.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/repositories/cattle_repository.dart';

final class FakeCattleRepository implements CattleRepository {
  bool configured;
  FakeCattleRepository({this.configured = true});

  @override
  bool get isConfigured => configured;

  List<Cattle> listResult = <Cattle>[];
  CattleProfile? profileResult;
  Object? listFailure;
  Object? profileFailure;
  Completer<List<Cattle>>? listCompleter;
  Completer<CattleProfile>? profileCompleter;
  final List<({String ranchId, CattleSearch query})> listRequests = [];
  final List<({String ranchId, String cattleId})> profileRequests = [];
  int get listCalls => listRequests.length;
  int get profileCalls => profileRequests.length;

  @override
  Future<List<Cattle>> search(String ranchId, CattleSearch query) {
    listRequests.add((ranchId: ranchId, query: query));
    final completer = listCompleter;
    if (completer != null) return completer.future;
    final failure = listFailure;
    if (failure != null) return Future<List<Cattle>>.error(failure);
    return Future<List<Cattle>>.value(listResult);
  }

  @override
  Future<CattleProfile> profile(String ranchId, String cattleId) {
    profileRequests.add((ranchId: ranchId, cattleId: cattleId));
    final completer = profileCompleter;
    if (completer != null) return completer.future;
    final failure = profileFailure;
    if (failure != null) return Future<CattleProfile>.error(failure);
    final result = profileResult;
    if (result == null) {
      return Future<CattleProfile>.error(
        const CattleFailure(CattleFailureCode.notFound),
      );
    }
    return Future<CattleProfile>.value(result);
  }
}

Cattle syntheticCattle({
  required String ranchId,
  required String id,
  String earTag = 'TAG-1',
  CattleStatus status = CattleStatus.active,
}) => Cattle(
  id: syntheticCattleId(id),
  ranchId: ranchId,
  earTag: earTag,
  breed: CattleBreed.crossbred,
  sex: CattleSex.female,
  birthDate: const CattleDate(2020, 1, 2),
  currentStage: CattleStage.heifer,
  status: status,
  version: '00000000-0000-4000-8000-000000000001',
  stagePeriods: <CattleStagePeriod>[
    CattleStagePeriod(
      id: '00000000-0000-4000-8000-000000000002',
      stage: CattleStage.heifer,
      validFrom: const CattleDate(2021, 1, 1),
      validTo: status == CattleStatus.inactive
          ? const CattleDate(2022, 1, 1)
          : null,
    ),
  ],
  exitReason: status == CattleStatus.inactive ? CattleExitReason.sale : null,
  exitDate: status == CattleStatus.inactive
      ? const CattleDate(2022, 1, 1)
      : null,
);

/// Stable, valid UUID for a synthetic cattle identifier label.
String syntheticCattleId(String label) {
  if (RegExp(
    r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$',
  ).hasMatch(label)) {
    return label;
  }
  var hash = 0x811c9dc5;
  for (final unit in label.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  final suffix = hash.toRadixString(16).padLeft(8, '0');
  return '00000000-0000-4000-8000-0000$suffix';
}
