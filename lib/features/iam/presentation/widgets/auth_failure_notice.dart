import 'package:flutter/material.dart';

import '../../../../core/theme/ichu_colors.dart';
import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';
import '../../domain/model/auth_failure.dart';

/// Never displays raw SDK exceptions, HTTP bodies, or submitted credentials.
final class AuthFailureNotice extends StatelessWidget {
  const AuthFailureNotice({super.key, required this.failure});

  final AuthFailure failure;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final message = switch (failure.code) {
      AuthFailureCode.configuration => strings.iamErrorConfiguration,
      AuthFailureCode.invalidCredentials => strings.iamErrorInvalidCredentials,
      AuthFailureCode.registrationRejected =>
        strings.iamErrorRegistrationRejected,
      AuthFailureCode.profileRejected => strings.iamErrorProfileRejected,
      AuthFailureCode.licenseAlreadyRegistered =>
        strings.iamErrorLicenseAlreadyRegistered,
      AuthFailureCode.accountAlreadyExists =>
        strings.iamErrorAccountAlreadyExists,
      AuthFailureCode.emailNotVerified => strings.iamErrorEmailNotVerified,
      AuthFailureCode.accountUnavailable => strings.iamErrorAccountUnavailable,
      AuthFailureCode.forbidden => strings.iamErrorForbidden,
      AuthFailureCode.network => strings.iamErrorNetwork,
      AuthFailureCode.serviceUnavailable => strings.iamErrorServiceUnavailable,
      AuthFailureCode.invalidResponse => strings.iamErrorInvalidResponse,
      AuthFailureCode.signOutFailed => strings.iamErrorSignOutFailed,
      AuthFailureCode.unknown => strings.iamErrorUnknown,
    };
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(message, style: const TextStyle(color: IchuColors.danger)),
      ),
    );
  }
}
