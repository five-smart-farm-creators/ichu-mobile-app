import 'dart:async';

import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle_commands.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle_failure.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/repositories/cattle_command_repository.dart';

/// Records write intents and returns configured outcomes without contacting a server.
final class FakeCattleCommandRepository implements CattleCommandRepository {
  FakeCattleCommandRepository({this.configured = true});

  bool configured;
  Cattle? result;
  Object? failure;
  Completer<Cattle>? completer;
  final List<
    ({
      String operation,
      String ranchId,
      String? cattleId,
      String? expectedVersion,
    })
  >
  requests = [];

  @override
  bool get isConfigured => configured;

  int get calls => requests.length;

  @override
  Future<Cattle> register(String ranchId, CattleRegistration registration) {
    requests.add((
      operation: 'register',
      ranchId: ranchId,
      cattleId: null,
      expectedVersion: null,
    ));
    return _respond();
  }

  @override
  Future<Cattle> correct(
    String ranchId,
    String cattleId,
    String expectedVersion,
    CattleCorrection correction,
  ) {
    requests.add((
      operation: 'correct',
      ranchId: ranchId,
      cattleId: cattleId,
      expectedVersion: expectedVersion,
    ));
    return _respond();
  }

  @override
  Future<Cattle> changeStage(
    String ranchId,
    String cattleId,
    String expectedVersion,
    CattleStageChange change,
  ) {
    requests.add((
      operation: 'changeStage',
      ranchId: ranchId,
      cattleId: cattleId,
      expectedVersion: expectedVersion,
    ));
    return _respond();
  }

  @override
  Future<Cattle> deactivate(
    String ranchId,
    String cattleId,
    String expectedVersion,
    CattleExit exit,
  ) {
    requests.add((
      operation: 'deactivate',
      ranchId: ranchId,
      cattleId: cattleId,
      expectedVersion: expectedVersion,
    ));
    return _respond();
  }

  Future<Cattle> _respond() {
    final pending = completer;
    if (pending != null) return pending.future;
    final error = failure;
    if (error != null) return Future<Cattle>.error(error);
    final value = result;
    if (value == null) {
      return Future<Cattle>.error(
        const CattleFailure(CattleFailureCode.unknown),
      );
    }
    return Future<Cattle>.value(value);
  }
}
