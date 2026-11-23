import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Lightweight local notification helper for convoy alerts, signal-lost warnings,
// and ride-ended updates on Android & iOS (safe no-op on desktop/tests).
class NotificationService {
  const NotificationService();

  static const String _channelId = 'ridesync_convoy';
  static const String _channelName = 'Convoy Alerts';
  static const String _channelDescription =
      'Live alerts from riders in your convoy (fuel stops, wait up, help).';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  Future<void> initializeAndRequestPermission() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      if (!_initialized) {
        const settings = InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        );
        await _plugin.initialize(settings: settings);
        _initialized = true;
      }
      if (Platform.isAndroid) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      }
    } on MissingPluginException {
      // Ignore on unsupported runners.
    } on UnsupportedError {
      // Ignore on unsupported runners.
    } on Exception {
      // Ignore permission prompt failures.
    }
  }

  Future<void> showConvoyNotification({
    required int id,
    required String title,
    required String body,
    bool urgent = false,
  }) async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      if (!_initialized) {
        await initializeAndRequestPermission();
      }
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: urgent ? Importance.max : Importance.high,
          priority: urgent ? Priority.high : Priority.defaultPriority,
        ),
        iOS: const DarwinNotificationDetails(),
      );
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } on MissingPluginException {
      // Ignore on unsupported runners.
    } on UnsupportedError {
      // Ignore on unsupported runners.
    } on Exception {
      // Ignore notification display failures.
    }
  }
}
