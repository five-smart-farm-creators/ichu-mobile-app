import 'package:flutter/material.dart';

import '../../../../core/layout/public_shell.dart';
import '../../../../shared/application/services/language_service.dart';
import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';
import '../../application/services/auth_service.dart';
import '../../domain/model/iam_account.dart';
import '../widgets/auth_failure_notice.dart';

/// A minimal real-session view; profile and ranch management are separate work.
final class SessionAccountPage extends StatelessWidget {
  const SessionAccountPage({
    super.key,
    required this.language,
    required this.authentication,
    required this.onOpenTerms,
    required this.onOpenProfile,
  });

  final LanguageService language;
  final AuthService authentication;
  final VoidCallback onOpenTerms;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: authentication,
    builder: (context, _) {
      final strings = AppLocalizations.of(context);
      final theme = Theme.of(context);
      final account = authentication.account;
      // Never retain a previously rendered account when validation is revoked.
      if (authentication.status != SessionStatus.authenticated ||
          account == null) {
        return PublicShell(
          language: language,
          child: Semantics(liveRegion: true, child: Text(strings.iamChecking)),
        );
      }
      final role = switch (account.role) {
        AccountRole.ranchManager => strings.iamRoleManager,
        AccountRole.veterinarian => strings.iamRoleVeterinarian,
        AccountRole.fieldOperator => strings.iamRoleOperator,
      };
      return PublicShell(
        language: language,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                strings.iamAccountTitle,
                style: theme.textTheme.headlineLarge,
              ),
            ),
            const SizedBox(height: 8),
            Text(strings.iamAccountLead),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.verified_user_outlined),
                    const SizedBox(height: 12),
                    Text(
                      strings.iamEmailVerified,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    Text(strings.iamEmail, style: theme.textTheme.labelLarge),
                    Text(account.email),
                    const SizedBox(height: 16),
                    Text(strings.iamRole, style: theme.textTheme.labelLarge),
                    Text(role),
                    const SizedBox(height: 16),
                    Text(
                      strings.iamAccountAccess,
                      style: theme.textTheme.labelLarge,
                    ),
                    Text(strings.iamAccountAuthorized),
                    const SizedBox(height: 16),
                    Text(strings.iamRanchCount(authentication.ranches.length)),
                    if (authentication.ranches.isEmpty)
                      Text(strings.iamNoRanches),
                  ],
                ),
              ),
            ),
            if (authentication.error != null)
              AuthFailureNotice(failure: authentication.error!),
            const SizedBox(height: 20),
            if (account.role == AccountRole.veterinarian) ...[
              OutlinedButton.icon(
                key: const Key('account-professional-profile'),
                onPressed: onOpenProfile,
                icon: const Icon(Icons.badge_outlined),
                label: Text(strings.iamProfessionalProfile),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              key: const Key('account-sign-out'),
              onPressed: () => authentication.signOut(),
              icon: const Icon(Icons.logout),
              label: Text(strings.iamSignOut),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => authentication.refresh(),
              child: Text(strings.iamRefreshSession),
            ),
            TextButton(onPressed: onOpenTerms, child: Text(strings.termsTitle)),
          ],
        ),
      );
    },
  );
}
