import 'package:flutter/material.dart';

import '../../shared/application/services/language_service.dart';
import '../../shared/infrastructure/i18n/generated/app_localizations.dart';
import 'public_shell.dart';

/// Describes platform services separately from the current mobile capabilities.
final class TermsPage extends StatelessWidget {
  const TermsPage({super.key, required this.language, required this.onBack});

  final LanguageService language;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sections = [
      (strings.termsAuthenticationTitle, strings.termsAuthentication),
      (strings.termsRecordsTitle, strings.termsRecords),
      (strings.termsPreferencesTitle, strings.termsPreferences),
      (strings.termsPaymentsTitle, strings.termsPayments),
      (strings.termsContactTitle, strings.termsContact),
    ];

    return PublicShell(
      language: language,
      showBackButton: true,
      onBack: onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              strings.termsTitle,
              style: theme.textTheme.headlineLarge,
            ),
          ),
          const SizedBox(height: 16),
          Text(strings.termsScope),
          const SizedBox(height: 24),
          for (final (title, body) in sections) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(title, style: theme.textTheme.titleLarge),
                    ),
                    const SizedBox(height: 8),
                    Text(body),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
            label: Text(strings.termsBack),
          ),
        ],
      ),
    );
  }
}
