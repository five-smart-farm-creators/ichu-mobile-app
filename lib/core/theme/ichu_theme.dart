import 'package:flutter/material.dart';

import 'ichu_colors.dart';

/// Uses explicit colors rather than a seed-generated approximation of ICHU.
abstract final class IchuTheme {
  static ThemeData get light {
    const colors = ColorScheme.light(
      primary: IchuColors.forest,
      onPrimary: IchuColors.surface,
      primaryContainer: IchuColors.greenSoft,
      onPrimaryContainer: IchuColors.forestDeep,
      secondary: IchuColors.accentText,
      onSecondary: IchuColors.surface,
      secondaryContainer: IchuColors.gold,
      onSecondaryContainer: IchuColors.ink,
      surface: IchuColors.surface,
      onSurface: IchuColors.ink,
      onSurfaceVariant: IchuColors.muted,
      outline: IchuColors.muted,
      outlineVariant: IchuColors.border,
      error: IchuColors.danger,
      onError: IchuColors.surface,
      surfaceTint: Colors.transparent,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      scaffoldBackgroundColor: IchuColors.background,
      fontFamily: 'PlusJakartaSans',
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );
    final text = base.textTheme;
    TextStyle heading(TextStyle? style) => style!.copyWith(
      fontFamily: 'Outfit',
      fontWeight: FontWeight.w600,
      color: IchuColors.forestDeep,
    );

    return base.copyWith(
      textTheme: text.copyWith(
        headlineLarge: heading(text.headlineLarge),
        headlineMedium: heading(text.headlineMedium),
        headlineSmall: heading(text.headlineSmall),
        titleLarge: heading(text.titleLarge),
        titleMedium: heading(text.titleMedium),
        bodyLarge: text.bodyLarge!.copyWith(height: 1.6),
        bodyMedium: text.bodyMedium!.copyWith(height: 1.6),
      ),
      cardTheme: CardThemeData(
        color: IchuColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: IchuColors.border),
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: IchuColors.paperWarm,
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: IchuColors.border),
          borderRadius: BorderRadius.circular(20),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: IchuColors.forest, width: 2),
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
}
