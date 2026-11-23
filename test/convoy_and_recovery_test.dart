import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:ridesync/models/active_ride.dart';
import 'package:ridesync/screens/main_screen.dart';
import 'package:ridesync/services/app_preferences.dart';
import 'package:ridesync/services/battery_service.dart';
import 'package:ridesync/services/location_service.dart';
import 'package:ridesync/services/notification_service.dart';
import 'package:ridesync/services/ride_api_service.dart';
import 'package:ridesync/services/wakelock_service.dart';
import 'package:ridesync/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_maplibre_platform.dart';

class _FixedLocationService extends LocationService {
  const _FixedLocationService(this.fix);

  final GpsFix fix;

  @override
  Future<LocationStatus> ensurePermission() async => LocationStatus.ready;

  @override
  Future<GpsFix?> getLastKnownFix() async => fix;

  @override
  Stream<GpsFix> fixStream() => Stream<GpsFix>.value(fix);

  @override
  Stream<bool> serviceEnabledStream() => const Stream<bool>.empty();
}

class _FixedBatteryService extends BatteryService {
  const _FixedBatteryService(this.percent);

  final int percent;

  @override
  Future<int?> getBatteryPercent() async => percent;
}

void main() {
  late FakeMapLibrePlatform fakeMap;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeMap = FakeMapLibrePlatform.register();
  });

  testWidgets(
    'Convoy screen shows distances, fell-behind/signal-lost, taps to focus rider, and sends real battery %',
    (tester) async {
      int? sentBattery;

      final client = MockClient((request) async {
        if (request.method == 'POST' &&
            request.url.path == '/rides/CONVOY/position') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          sentBattery = (body['battery_percent'] as num?)?.toInt();
          return http.Response(
            jsonEncode({
              'code': 'CONVOY',
              'user_id': 1,
              'updated_at': '2026-11-23T00:00:00Z',
            }),
            200,
          );
        }
        if (request.method == 'GET' &&
            request.url.path == '/rides/CONVOY/positions') {
          return http.Response(
            jsonEncode({
              'code': 'CONVOY',
              'destination': 'Daman-e-Koh',
              'dest_lat': 33.7394,
              'dest_lng': 73.0558,
              'is_ended': false,
              'ended_at': null,
              'riders': [
                {
                  'rider': {'id': 2, 'name': 'Bilal'},
                  'latitude': 33.7000,
                  'longitude': 73.0433,
                  'speed_kmh': 50,
                  'battery_percent': 62,
                  'age_seconds': 5,
                  'is_stale': false,
                },
                {
                  'rider': {'id': 3, 'name': 'Omar'},
                  'latitude': 33.7220,
                  'longitude': 73.0440,
                  'speed_kmh': 0,
                  'battery_percent': 14,
                  'age_seconds': 140,
                  'is_stale': true,
                },
              ],
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final api = RideApiService(
        baseUrl: 'https://api.example.com',
        client: client,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MainScreen(
            apiService: api,
            locationService: const _FixedLocationService(
              GpsFix(point: LatLng(33.7215, 73.0433), speedKmh: 45),
            ),
            batteryService: const _FixedBatteryService(83),
            initialActiveRide: const ActiveRide(
              joinCode: 'CONVOY',
              destination: 'Daman-e-Koh',
              destLat: 33.7394,
              destLng: 73.0558,
              isHost: true,
              currentUserId: 1,
              currentUserName: 'Nawaf',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Real phone battery % was uploaded to the backend.
      expect(sentBattery, 83);

      // Fit all riders button is visible and frames riders + destination.
      expect(find.byTooltip('Fit all riders'), findsOneWidget);
      await tester.tap(find.byTooltip('Fit all riders'));
      await tester.pumpAndSettle();

      // Open Convoy list -> verify distance, Fell behind, Signal lost, and battery.
      await tester.tap(find.byTooltip('Convoy riders'));
      await tester.pumpAndSettle();

      expect(find.text('Bilal'), findsOneWidget);
      expect(find.text('Fell behind'), findsOneWidget);
      expect(find.text('62%'), findsOneWidget);
      expect(find.text('83%'), findsOneWidget);
      expect(find.text('Omar'), findsOneWidget);
      expect(find.text('Signal lost · 2m ago'), findsOneWidget);

      // Tap Bilal -> pops back to Map and focuses camera on Bilal's point.
      await tester.tap(find.text('Bilal'));
      await tester.pumpAndSettle();

      final mapState = fakeMap.latestState!;
      expect(mapState.camera!.center.lat, closeTo(33.7000, 1e-4));
      expect(mapState.camera!.center.lon, closeTo(73.0433, 1e-4));
      expect(mapState.camera!.zoom, equals(16));
    },
  );

  testWidgets('Active ride is restored automatically after app restart', (
    tester,
  ) async {
    final prefs = AppPreferences();
    await prefs.saveActiveRide(
      const ActiveRide(
        joinCode: 'KEEP99',
        destination: 'Nathia Gali',
        destLat: 34.0728,
        destLng: 73.3812,
        isHost: false,
        currentUserId: 7,
        currentUserName: 'Nawaf',
      ),
    );

    final api = RideApiService(
      baseUrl: 'https://api.example.com',
      client: MockClient((request) async {
        if (request.url.path == '/rides/KEEP99/positions') {
          return http.Response(
            jsonEncode({
              'code': 'KEEP99',
              'destination': 'Nathia Gali',
              'dest_lat': 34.0728,
              'dest_lng': 73.3812,
              'is_ended': false,
              'ended_at': null,
              'riders': const [],
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MainScreen(
          apiService: api,
          locationService: const _FixedLocationService(
            GpsFix(point: LatLng(33.7215, 73.0433), speedKmh: 0),
          ),
          batteryService: const _FixedBatteryService(75),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('KEEP99'), findsOneWidget);
    expect(find.text('Nathia Gali'), findsNWidgets(2));
    expect(find.text('Leave'), findsOneWidget);

    // Leaving clears persisted ride so next launch starts clean.
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(await prefs.loadActiveRide(), isNull);
  });

  testWidgets(
    'Background pause stops polling and stationary updates throttle',
    (tester) async {
      var pollCount = 0;
      var postCount = 0;
      final fixController = StreamController<GpsFix>.broadcast();
      addTearDown(fixController.close);

      final api = RideApiService(
        baseUrl: 'https://api.example.com',
        client: MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.path == '/rides/SAVE11/positions') {
            pollCount++;
            return http.Response(
              jsonEncode({
                'code': 'SAVE11',
                'destination': 'Margalla',
                'is_ended': false,
                'ended_at': null,
                'riders': const [],
              }),
              200,
            );
          }
          if (request.method == 'POST' &&
              request.url.path == '/rides/SAVE11/position') {
            postCount++;
            return http.Response(
              jsonEncode({
                'code': 'SAVE11',
                'user_id': 1,
                'updated_at': '2026-11-23T00:00:00Z',
              }),
              200,
            );
          }
          return http.Response('Not found', 404);
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MainScreen(
            apiService: api,
            locationService: _StreamLocationService(fixController.stream),
            batteryService: const _FixedBatteryService(90),
            initialActiveRide: const ActiveRide(
              joinCode: 'SAVE11',
              destination: 'Margalla',
              isHost: true,
              currentUserId: 1,
              currentUserName: 'Nawaf',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Two stationary fixes back-to-back only send once (throttled to 15s).
      fixController.add(
        const GpsFix(point: LatLng(33.7215, 73.0433), speedKmh: 0),
      );
      await tester.pumpAndSettle();
      fixController.add(
        const GpsFix(point: LatLng(33.7215, 73.0433), speedKmh: 0),
      );
      await tester.pumpAndSettle();
      expect(postCount, 1);

      // Backgrounding pauses the 3s sync timer; resuming starts it again.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      final pollsWhenPaused = pollCount;
      await tester.pump(const Duration(seconds: 7));
      expect(pollCount, pollsWhenPaused);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(pollCount, greaterThan(pollsWhenPaused));
    },
  );

  testWidgets(
    'Quick convoy alerts, local notifications, wakelock, and heading arrow work end-to-end',
    (tester) async {
      final notifications = _FakeNotificationService();
      final wakelock = _FakeWakelockService();
      double? sentHeading;

      final client = MockClient((request) async {
        if (request.method == 'POST' &&
            request.url.path == '/rides/UX1234/position') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          sentHeading = (body['heading_degrees'] as num?)?.toDouble();
          return http.Response(
            jsonEncode({
              'code': 'UX1234',
              'user_id': 1,
              'updated_at': '2026-11-23T00:00:00Z',
            }),
            200,
          );
        }
        if (request.method == 'POST' &&
            request.url.path == '/rides/UX1234/alert') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'id': 55,
              'user_id': 1,
              'sender_name': 'Nawaf',
              'alert_type': body['alert_type'],
              'message': 'Needs a fuel stop',
              'age_seconds': 0,
              'created_at': '2026-11-23T00:00:00Z',
            }),
            201,
          );
        }
        if (request.method == 'GET' &&
            request.url.path == '/rides/UX1234/positions') {
          return http.Response(
            jsonEncode({
              'code': 'UX1234',
              'destination': 'Daman-e-Koh',
              'is_ended': false,
              'ended_at': null,
              'riders': [
                {
                  'rider': {'id': 2, 'name': 'Bilal'},
                  'latitude': 33.7220,
                  'longitude': 73.0440,
                  'speed_kmh': 0,
                  'heading_degrees': 90,
                  'battery_percent': 70,
                  'age_seconds': 95,
                  'is_stale': true,
                },
              ],
              'latest_alert': {
                'id': 44,
                'user_id': 2,
                'sender_name': 'Bilal',
                'alert_type': 'help',
                'message': 'Needs help!',
                'age_seconds': 3,
                'created_at': '2026-11-23T00:00:00Z',
              },
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final api = RideApiService(
        baseUrl: 'https://api.example.com',
        client: client,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MainScreen(
            apiService: api,
            locationService: const _FixedLocationService(
              GpsFix(
                point: LatLng(33.7215, 73.0433),
                speedKmh: 45,
                headingDegrees: 180,
              ),
            ),
            batteryService: const _FixedBatteryService(85),
            notificationService: notifications,
            wakelockService: wakelock,
            initialActiveRide: const ActiveRide(
              joinCode: 'UX1234',
              destination: 'Daman-e-Koh',
              isHost: true,
              currentUserId: 1,
              currentUserName: 'Nawaf',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Wakelock enabled, heading uploaded, incoming alert + stale notifications fired.
      expect(wakelock.lastEnabled, isTrue);
      expect(sentHeading, 180);
      expect(find.text('Bilal: Needs help!'), findsOneWidget);
      expect(
        notifications.shownTitles,
        containsAll(['Bilal: Need help', 'Bilal signal lost']),
      );

      // Send a Fuel stop alert via the quick alert sheet.
      await tester.tap(find.byTooltip('Send convoy alert'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fuel stop'));
      await tester.pumpAndSettle();
      expect(find.text('Nawaf: Needs a fuel stop'), findsOneWidget);

      // Ending the ride disables wakelock (dismiss snackbar covering End Ride).
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End Ride'));
      await tester.pumpAndSettle();
      expect(wakelock.lastEnabled, isFalse);
    },
  );
}

class _FakeNotificationService extends NotificationService {
  final List<String> shownTitles = [];

  @override
  Future<void> initializeAndRequestPermission() async {}

  @override
  Future<void> showConvoyNotification({
    required int id,
    required String title,
    required String body,
    bool urgent = false,
  }) async {
    shownTitles.add(title);
  }
}

class _FakeWakelockService extends WakelockService {
  bool? lastEnabled;

  @override
  Future<void> setEnabled(bool enabled) async {
    lastEnabled = enabled;
  }
}

class _StreamLocationService extends LocationService {
  const _StreamLocationService(this.stream);

  final Stream<GpsFix> stream;

  @override
  Future<LocationStatus> ensurePermission() async => LocationStatus.ready;

  @override
  Future<GpsFix?> getLastKnownFix() async => null;

  @override
  Stream<GpsFix> fixStream() => stream;

  @override
  Stream<bool> serviceEnabledStream() => const Stream<bool>.empty();
}
