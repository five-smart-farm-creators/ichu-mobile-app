import 'package:flutter/material.dart';

import 'core/config/app_config.dart';
import 'core/layout/terms_page.dart';
import 'core/theme/ichu_theme.dart';
import 'features/iam/presentation/pages/welcome_page.dart';
import 'shared/application/services/language_service.dart';
import 'shared/infrastructure/i18n/generated/app_localizations.dart';

/// Composition root. Domain code never resolves platform or UI dependencies.
final class IchuApp extends StatelessWidget {
  const IchuApp({
    super.key,
    required this.language,
    required this.config,
    this.initialRoute = '/',
  });

  final LanguageService language;
  final AppConfig config;
  final String initialRoute;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: language,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        theme: IchuTheme.light,
        themeMode: ThemeMode.light,
        locale: Locale(language.current.code),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        initialRoute: initialRoute,
        routes: {'/terms': (_) => TermsPage(language: language)},
        home: Builder(
          builder: (context) => WelcomePage(
            language: language,
            configurationNotice: switch (config.issue) {
              AppConfigIssue.missingApiUrl => AppLocalizations.of(
                context,
              ).apiMissing,
              AppConfigIssue.invalidApiUrl => AppLocalizations.of(
                context,
              ).apiInvalid,
              AppConfigIssue.invalidEnvironment => AppLocalizations.of(
                context,
              ).environmentInvalid,
              null => null,
            },
            onOpenTerms: () => Navigator.of(context).pushNamed('/terms'),
          ),
        ),
      ),
    );
  }
}
