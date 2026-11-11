import 'package:flutter/material.dart';

import '../../../../core/layout/public_shell.dart';
import '../../../../core/theme/ichu_colors.dart';
import '../../../../shared/application/services/language_service.dart';
import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';

/// An explicitly unauthenticated preview, not a simulated sign-in experience.
final class WelcomePage extends StatelessWidget {
  const WelcomePage({
    super.key,
    required this.language,
    this.configurationNotice,
    required this.onOpenTerms,
  });

  final LanguageService language;
  final String? configurationNotice;
  final VoidCallback onOpenTerms;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return PublicShell(
      language: language,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/images/login_andean_herd.webp',
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, 0.4),
                    excludeFromSemantics: true,
                  ),
                ),
                Container(
                  constraints: BoxConstraints(
                    minHeight: MediaQuery.sizeOf(context).width >= 680
                        ? 220
                        : 160,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      // Even over white image pixels, the lightest scrim keeps
                      // every wrapped caption line above 4.5:1 contrast.
                      colors: [Color(0xBF193B2A), Color(0xF2193B2A)],
                    ),
                  ),
                  alignment: Alignment.bottomLeft,
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    strings.herdTagline,
                    style: theme.textTheme.titleLarge!.copyWith(
                      color: IchuColors.surface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: IchuColors.greenSoft,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text(
                strings.previewLabel,
                style: theme.textTheme.labelLarge!.copyWith(
                  color: IchuColors.forestDeep,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Semantics(
            header: true,
            child: Text(
              strings.welcomeTitle,
              style: theme.textTheme.headlineLarge,
            ),
          ),
          const SizedBox(height: 8),
          Text(strings.welcomeLead, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.eco_outlined, color: IchuColors.forest),
                  const SizedBox(height: 12),
                  Text(strings.previewTitle, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(strings.previewBody),
                  if (configurationNotice != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      configurationNotice!,
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: IchuColors.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onOpenTerms,
            icon: const Icon(Icons.privacy_tip_outlined),
            label: Text(strings.termsTitle),
          ),
        ],
      ),
    );
  }
}
