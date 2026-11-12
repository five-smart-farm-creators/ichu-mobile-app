import 'package:flutter/material.dart';

import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';
import '../../domain/model/cattle_failure.dart';

final class CattleFailureNotice extends StatelessWidget {
  const CattleFailureNotice({super.key, required this.failure});

  final CattleFailure failure;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final message = switch (failure.code) {
      CattleFailureCode.configuration => strings.cattleErrorConfiguration,
      CattleFailureCode.contextUnavailable => strings.cattleChooseRanch,
      CattleFailureCode.invalidSearch => strings.cattleErrorSearch,
      CattleFailureCode.unauthenticated => strings.cattleErrorUnauthenticated,
      CattleFailureCode.forbidden => strings.cattleErrorForbidden,
      CattleFailureCode.notFound => strings.cattleErrorNotFound,
      CattleFailureCode.network => strings.cattleErrorNetwork,
      CattleFailureCode.serviceUnavailable => strings.cattleErrorUnavailable,
      CattleFailureCode.invalidResponse => strings.cattleErrorResponse,
      CattleFailureCode.unknown => strings.cattleErrorUnknown,
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
