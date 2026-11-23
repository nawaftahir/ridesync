import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Handles Google Maps-style ongoing ride notifications, quick convoy alerts,
// emergency help alerts, and rider status notifications on Android & iOS.
class NotificationService {
  const NotificationService();

  static const int ongoingRideNotificationId = 100;
  static const String actionEndRide = 'end_ride';
  static const String actionOpenConvoy = 'open_convoy';

  static const String _ongoingChannelId = 'ridesync_active_ride';
  static const String _ongoingChannelName = 'Active Ride';
  static const String _ongoingChannelDescription =
      'Ongoing ride status, ETA, and convoy count while riding.';

  static const String _convoyChannelId = 'ridesync_convoy_alerts';
  static const String _convoyChannelName = 'Convoy Alerts & Updates';
  static const String _convoyChannelDescription =
      'Fuel stops, wait up pings, riders joining/leaving, and signal updates.';

  static const String _urgentChannelId = 'ridesync_urgent_help';
  static const String _urgentChannelName = 'Emergency Rider Help';
  static const String _urgentChannelDescription =
      'High-priority alerts when a convoy rider taps Need help.';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static final StreamController<String> _actionController =
      StreamController<String>.broadcast();
  static bool _initialized = false;

  // Emits notification action IDs ('open_convoy', 'end_ride') when tapped.
  Stream<String> get actionStream => _actionController.stream;

  void _emitResponse(NotificationResponse response) {
    final action = response.actionId?.trim();
    if (action != null && action.isNotEmpty) {
      _actionController.add(action);
      return;
    }
    final payload = response.payload?.trim();
    if (payload != null && payload.isNotEmpty) {
      _actionController.add(payload);
    }
  }

  Future<void> initializeAndRequestPermission() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      if (!_initialized) {
        const settings = InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        );
        await _plugin.initialize(
          settings: settings,
          onDidReceiveNotificationResponse: _emitResponse,
        );
        _initialized = true;

        if (Platform.isAndroid) {
          final android = _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
          if (android != null) {
            await android.createNotificationChannel(
              const AndroidNotificationChannel(
                _ongoingChannelId,
                _ongoingChannelName,
                description: _ongoingChannelDescription,
                importance: Importance.low,
                playSound: false,
                enableVibration: false,
                showBadge: false,
              ),
            );
            await android.createNotificationChannel(
              const AndroidNotificationChannel(
                _convoyChannelId,
                _convoyChannelName,
                description: _convoyChannelDescription,
                importance: Importance.high,
              ),
            );
            await android.createNotificationChannel(
              const AndroidNotificationChannel(
                _urgentChannelId,
                _urgentChannelName,
                description: _urgentChannelDescription,
                importance: Importance.max,
                enableLights: true,
                ledColor: Color(0xFFD32F2F),
                audioAttributesUsage: AudioAttributesUsage.alarm,
              ),
            );
          }
        }

        final launchDetails = await _plugin.getNotificationAppLaunchDetails();
        if (launchDetails?.didNotificationLaunchApp == true &&
            launchDetails?.notificationResponse != null) {
          _emitResponse(launchDetails!.notificationResponse!);
        }
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

  // Shows or updates the persistent Google Maps-style "Ride in progress" card.
  Future<void> showOngoingRideNotification({
    required String destination,
    required String rideCode,
    required String summary,
    required bool isHost,
    required DateTime startedAt,
    String? shortStatusChip,
  }) async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      if (!_initialized) {
        await initializeAndRequestPermission();
      }
      final title = destination.trim().isEmpty
          ? 'Ride in progress'
          : 'Riding to $destination';
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          _ongoingChannelId,
          _ongoingChannelName,
          channelDescription: _ongoingChannelDescription,
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          silent: true,
          channelShowBadge: false,
          showWhen: true,
          when: startedAt.millisecondsSinceEpoch,
          usesChronometer: true,
          visibility: NotificationVisibility.public,
          category: AndroidNotificationCategory.navigation,
          requestPromotedOngoing: true,
          shortCriticalText: shortStatusChip ?? rideCode,
          subText: 'Code $rideCode',
          styleInformation: BigTextStyleInformation(
            summary,
            contentTitle: title,
            summaryText: 'Code $rideCode',
          ),
          actions: [
            const AndroidNotificationAction(
              actionOpenConvoy,
              'Convoy',
              showsUserInterface: true,
              cancelNotification: false,
            ),
            AndroidNotificationAction(
              actionEndRide,
              isHost ? 'End ride' : 'Leave ride',
              showsUserInterface: true,
              cancelNotification: false,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: false,
          presentSound: false,
          presentBanner: false,
          presentList: true,
        ),
      );
      await _plugin.show(
        id: ongoingRideNotificationId,
        title: title,
        body: summary,
        notificationDetails: details,
        payload: actionOpenConvoy,
      );
    } on MissingPluginException {
      // Ignore on unsupported runners.
    } on UnsupportedError {
      // Ignore on unsupported runners.
    } on Exception {
      // Ignore notification display failures.
    }
  }

  // Removes the persistent ongoing ride notification when the ride finishes.
  Future<void> cancelOngoingRideNotification() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      await _plugin.cancel(id: ongoingRideNotificationId);
    } on MissingPluginException {
      // Ignore on unsupported runners.
    } on UnsupportedError {
      // Ignore on unsupported runners.
    } on Exception {
      // Ignore cancellation failures.
    }
  }

  // Shows a convoy update, rider event, or urgent help alert notification.
  Future<void> showConvoyNotification({
    required int id,
    required String title,
    required String body,
    bool urgent = false,
    String? subText,
    String? payload,
  }) async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      if (!_initialized) {
        await initializeAndRequestPermission();
      }
      final channelId = urgent ? _urgentChannelId : _convoyChannelId;
      final channelName = urgent ? _urgentChannelName : _convoyChannelName;
      final channelDesc = urgent
          ? _urgentChannelDescription
          : _convoyChannelDescription;

      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDesc,
          importance: urgent ? Importance.max : Importance.high,
          priority: urgent ? Priority.max : Priority.high,
          visibility: NotificationVisibility.public,
          category: urgent
              ? AndroidNotificationCategory.alarm
              : AndroidNotificationCategory.social,
          color: urgent ? const Color(0xFFD32F2F) : null,
          enableLights: urgent,
          ledColor: urgent ? const Color(0xFFD32F2F) : null,
          audioAttributesUsage: urgent
              ? AudioAttributesUsage.alarm
              : AudioAttributesUsage.notification,
          subText: subText,
          styleInformation: BigTextStyleInformation(
            body,
            contentTitle: title,
            summaryText: subText,
          ),
        ),
        iOS: DarwinNotificationDetails(
          interruptionLevel: urgent
              ? InterruptionLevel.timeSensitive
              : InterruptionLevel.active,
        ),
      );
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload ?? actionOpenConvoy,
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
