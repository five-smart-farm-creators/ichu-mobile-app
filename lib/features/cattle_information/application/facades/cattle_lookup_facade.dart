import '../../../iam/application/facades/authorized_ranch_session.dart';
import '../../domain/model/cattle.dart';
import '../../domain/model/cattle_failure.dart';
import '../../domain/model/cattle_search.dart';
import '../../domain/repositories/cattle_repository.dart';

enum CattleLookupFailureCode {
  configuration,
  contextUnavailable,
  permissionRequired,
  invalidQuery,
  invalidResponse,
  unavailable,
}

final class CattleLookupFailure implements Exception {
  const CattleLookupFailure(this.code);

  final CattleLookupFailureCode code;
}

/// Minimal cattle data exposed to another application context for field entry.
final class CattleLookupItem {
  const CattleLookupItem({
    required this.cattleId,
    required this.ranchId,
    required this.earTag,
  });

  final String cattleId;
  final String ranchId;
  final String earTag;
}

/// Performs an exact cattle lookup only within the current managed ranch.
final class CattleLookupFacade {
  CattleLookupFacade({required this.access, required this.cattle});

  static const int _pageSize = 20;

  final AuthorizedRanchSession access;
  final CattleRepository cattle;

  Future<List<CattleLookupItem>> findByExactEarTag({
    required String accountId,
    required String ranchId,
    required String earTag,
  }) async {
    final tag = earTag.trim();
    if (tag.isEmpty || tag.length > 30) {
      throw const CattleLookupFailure(CattleLookupFailureCode.invalidQuery);
    }

    final context = access.context;
    if (context == null ||
        !access.isCurrent(context) ||
        !_sameId(context.accountId, accountId) ||
        !_sameId(context.ranchId, ranchId)) {
      throw const CattleLookupFailure(
        CattleLookupFailureCode.contextUnavailable,
      );
    }
    if (!context.canManage) {
      throw const CattleLookupFailure(
        CattleLookupFailureCode.permissionRequired,
      );
    }
    if (!cattle.isConfigured) {
      throw const CattleLookupFailure(CattleLookupFailureCode.configuration);
    }

    final List<Cattle> matches;
    try {
      matches = await cattle.search(
        context.ranchId,
        CattleSearch(earTag: tag, pageSize: _pageSize),
      );
    } on CattleFailure catch (failure) {
      throw CattleLookupFailure(switch (failure.code) {
        CattleFailureCode.configuration =>
          CattleLookupFailureCode.configuration,
        CattleFailureCode.contextUnavailable ||
        CattleFailureCode.unauthenticated =>
          CattleLookupFailureCode.contextUnavailable,
        CattleFailureCode.forbidden =>
          CattleLookupFailureCode.permissionRequired,
        CattleFailureCode.invalidSearch ||
        CattleFailureCode.invalidInput => CattleLookupFailureCode.invalidQuery,
        CattleFailureCode.invalidResponse =>
          CattleLookupFailureCode.invalidResponse,
        _ => CattleLookupFailureCode.unavailable,
      });
    } catch (_) {
      throw const CattleLookupFailure(CattleLookupFailureCode.unavailable);
    }

    if (!access.isCurrent(context) || !identical(access.context, context)) {
      throw const CattleLookupFailure(
        CattleLookupFailureCode.contextUnavailable,
      );
    }
    if (matches.length > 1 ||
        matches.any(
          (item) =>
              !_sameId(item.ranchId, context.ranchId) ||
              item.earTag != tag ||
              !_isUuid(item.id),
        )) {
      throw const CattleLookupFailure(CattleLookupFailureCode.invalidResponse);
    }

    return List<CattleLookupItem>.unmodifiable(
      matches.map(
        (item) => CattleLookupItem(
          cattleId: item.id,
          ranchId: item.ranchId,
          earTag: item.earTag,
        ),
      ),
    );
  }

  bool _sameId(String left, String right) =>
      left.toLowerCase() == right.toLowerCase();

  bool _isUuid(String value) =>
      RegExp(
        r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$',
      ).hasMatch(value) &&
      value.replaceAll('-', '').replaceAll('0', '').isNotEmpty;
}
