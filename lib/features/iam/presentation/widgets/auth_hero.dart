import 'package:flutter/material.dart';

import '../../../../core/theme/ichu_colors.dart';
import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';

/// Keeps every caption line legible even on a bright image or large text scale.
final class AuthHero extends StatelessWidget {
  const AuthHero({super.key});

  @override
  Widget build(BuildContext context) => ClipRRect(
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
          constraints: const BoxConstraints(minHeight: 140),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xBF193B2A), Color(0xF2193B2A)],
            ),
          ),
          alignment: Alignment.bottomLeft,
          padding: const EdgeInsets.all(20),
          child: Text(
            AppLocalizations.of(context).herdTagline,
            style: Theme.of(
              context,
            ).textTheme.titleLarge!.copyWith(color: IchuColors.surface),
          ),
        ),
      ],
    ),
  );
}
