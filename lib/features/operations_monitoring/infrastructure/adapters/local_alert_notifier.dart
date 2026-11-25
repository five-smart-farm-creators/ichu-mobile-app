import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';
import '../../domain/model/ranch_alert.dart';
import '../../domain/repositories/alert_notifier.dart';
import '../i18n/alert_type_labels.dart';

/// Posts alert notifications through flutter_local_notifications on Android and iOS.
final class LocalAlertNotifier implements AlertNotifier {
  LocalAlertNotifier({required this._plugin, required this._locale});

  static const _channelId = 'cloud_alerts';

  final FlutterLocalNotificationsPlugin _plugin;
  final Locale Function() _locale;
  final _taps = StreamController<void>.broadcast();
  Future<void>? _initialization;

  @override
  Stream<void> get taps => _taps.stream;

  @override
  Future<void> initialize() => _initialization ??= _initializePlugin();

  @override
  Future<void> show(RanchAlert alert) async {
    await initialize();
    final strings = lookupAppLocalizations(_locale());
    await _plugin.show(
      // The plugin expects a 32-bit ID; masking keeps the hash non-negative.
      id: alert.alertId.hashCode & 0x7fffffff,
      title: switch (alert.severity) {
        AlertSeverity.informative => strings.alertNotificationTitleInformative,
        AlertSeverity.warning => strings.alertNotificationTitleWarning,
        AlertSeverity.critical => strings.alertNotificationTitleCritical,
      },
      body: strings.alertNotificationBody(
        alertTypeLabel(strings, alert.type),
        alert.deviceId,
      ),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          strings.alertNotificationChannelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  Future<void> _initializePlugin() async {
    // The Darwin defaults request iOS alert and sound permission here, at first use.
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(requestBadgePermission: false),
      ),
      onDidReceiveNotificationResponse: (_) => _taps.add(null),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }
}
