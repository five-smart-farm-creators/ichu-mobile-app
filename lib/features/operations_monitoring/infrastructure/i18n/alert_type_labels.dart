import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';
import '../../domain/model/ranch_alert.dart';

/// Localized alert type name, shared by the alert list and alert notifications.
String alertTypeLabel(AppLocalizations strings, AlertType type) =>
    switch (type) {
      AlertType.temperature => strings.alertTypeTemperature,
      AlertType.activity => strings.alertTypeActivity,
      AlertType.heartRate => strings.alertTypeHeartRate,
      AlertType.methane => strings.alertTypeMethane,
      AlertType.geofence => strings.alertTypeGeofence,
    };
