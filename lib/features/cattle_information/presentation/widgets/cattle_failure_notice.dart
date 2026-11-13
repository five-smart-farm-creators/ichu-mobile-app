import 'package:flutter/material.dart';

import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';
import '../../domain/model/cattle_failure.dart';

final class CattleFailureNotice extends StatelessWidget {
  const CattleFailureNotice({
    super.key,
    required this.failure,
    this.isWrite = false,
  });

  final CattleFailure failure;

  /// A denied write still allows reading, so it needs its own explanation.
  final bool isWrite;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final message = switch (failure.code) {
      CattleFailureCode.configuration => strings.cattleErrorConfiguration,
      CattleFailureCode.contextUnavailable => strings.cattleChooseRanch,
      CattleFailureCode.invalidSearch => strings.cattleErrorSearch,
      CattleFailureCode.unauthenticated => strings.cattleErrorUnauthenticated,
      CattleFailureCode.forbidden =>
        isWrite
            ? strings.cattleManageErrorForbidden
            : strings.cattleErrorForbidden,
      CattleFailureCode.notFound => strings.cattleErrorNotFound,
      CattleFailureCode.network => strings.cattleErrorNetwork,
      CattleFailureCode.serviceUnavailable => strings.cattleErrorUnavailable,
      CattleFailureCode.invalidResponse => strings.cattleErrorResponse,
      CattleFailureCode.unknown => strings.cattleErrorUnknown,
      CattleFailureCode.invalidInput => strings.cattleManageErrorInvalid,
      CattleFailureCode.versionConflict => strings.cattleManageErrorVersion,
      CattleFailureCode.duplicateEarTag => strings.cattleManageErrorDuplicate,
      CattleFailureCode.inactive => strings.cattleManageErrorInactive,
      CattleFailureCode.stageAlreadyCurrent =>
        strings.cattleManageErrorStageCurrent,
      CattleFailureCode.outcomeUnknown =>
        strings.cattleManageErrorOutcomeUnknown,
    };
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          message,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}
