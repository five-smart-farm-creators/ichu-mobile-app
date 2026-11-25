import 'package:flutter/material.dart';

import '../../shared/application/services/language_service.dart';
import '../../shared/infrastructure/i18n/generated/app_localizations.dart';
import '../../shared/presentation/widgets/language_menu.dart';
import '../theme/ichu_colors.dart';

/// Shared public layout; content scrolls rather than clipping at large text sizes.
final class PublicShell extends StatelessWidget {
  const PublicShell({
    super.key,
    required this.language,
    required this.child,
    this.showBackButton = false,
    this.onBack,
    this.backLabel,
  });

  final LanguageService language;
  final Widget child;
  final bool showBackButton;
  final VoidCallback? onBack;
  final String? backLabel;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Row(
                    children: [
                      if (showBackButton)
                        IconButton(
                          tooltip: backLabel ?? strings.termsBack,
                          onPressed:
                              onBack ?? () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.arrow_back),
                        ),
                      Expanded(
                        child: Semantics(
                          label: strings.appTitle,
                          excludeSemantics: true,
                          child: Row(
                            children: [
                              Image.asset(
                                'assets/images/ichu_mark.png',
                                width: 28,
                                height: 38,
                                cacheWidth: 112,
                                fit: BoxFit.contain,
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'ICHU',
                                      style: theme.textTheme.titleLarge,
                                    ),
                                    Text(
                                      'SmartFarm',
                                      style: theme.textTheme.labelMedium!
                                          .copyWith(color: IchuColors.muted),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      LanguageMenu(language: language),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          child,
                          const SizedBox(height: 28),
                          Text(
                            strings.copyright(DateTime.now().year),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall!.copyWith(
                              color: IchuColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
