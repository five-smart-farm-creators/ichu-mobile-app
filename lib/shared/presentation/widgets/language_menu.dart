import 'package:flutter/material.dart';

import '../../application/services/language_service.dart';
import '../../domain/model/app_language.dart';
import '../../infrastructure/i18n/generated/app_localizations.dart';

/// Endonyms stay in their own language, as in the web language menu.
final class LanguageMenu extends StatelessWidget {
  const LanguageMenu({super.key, required this.language});

  final LanguageService language;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return PopupMenuButton<AppLanguage>(
      enabled: !language.saving,
      tooltip: '${strings.languageLabel}: ${_label(language.current)}',
      icon: const Icon(Icons.translate),
      onSelected: (value) async {
        final saved = await language.select(value);
        // Let MaterialApp install the selected locale before localizing feedback.
        await WidgetsBinding.instance.endOfFrame;
        if (!saved && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).languageSaveFailed),
            ),
          );
        }
      },
      itemBuilder: (context) => [
        for (final value in AppLanguage.values)
          CheckedPopupMenuItem(
            value: value,
            checked: value == language.current,
            child: Text(_label(value)),
          ),
      ],
    );
  }

  static String _label(AppLanguage value) => switch (value) {
    AppLanguage.english => 'English',
    AppLanguage.spanish => 'Español',
  };
}
