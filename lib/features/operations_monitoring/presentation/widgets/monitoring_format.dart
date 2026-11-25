import 'package:intl/intl.dart';

import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';

/// Display formatting shared by monitoring snapshots and persisted alert events.
abstract final class MonitoringFormat {
  static String instant(AppLocalizations strings, DateTime value) =>
      DateFormat.yMMMd(strings.localeName).add_Hms().format(value.toLocal());

  static String number(AppLocalizations strings, double value) {
    // Preserve shortest decimals instead of exposing binary rounding artifacts.
    final magnitude = value.abs();
    final representation =
        magnitude != 0 && (magnitude < 0.000001 || magnitude >= 1e9)
        ? value.toStringAsExponential()
        : value.toString();
    final parts = representation.split('e');
    final mantissa = parts.first.endsWith('.0')
        ? parts.first.substring(0, parts.first.length - 2)
        : parts.first;
    final decimal = NumberFormat.decimalPattern(
      strings.localeName,
    ).symbols.DECIMAL_SEP;
    final localized = mantissa.replaceAll('.', decimal);
    return parts.length == 1
        ? localized
        : '${localized}E${int.parse(parts.last)}';
  }
}
