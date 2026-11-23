import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ridesync/models/auth_session.dart';
import 'package:ridesync/screens/main_screen.dart';
import 'package:ridesync/services/location_service.dart';
import 'package:ridesync/services/ride_api_service.dart';
import 'package:ridesync/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_maplibre_platform.dart';

class _IdleLocationService extends LocationService {
  const _IdleLocationService();

  @override
  Future<LocationStatus> ensurePermission() async => LocationStatus.ready;

  @override
  Future<GpsFix?> getLastKnownFix() async => null;

  @override
  Stream<GpsFix> fixStream() => const Stream<GpsFix>.empty();

  @override
  Stream<bool> serviceEnabledStream() => const Stream<bool>.empty();

  @override
  Stream<double> compassHeadingStream() => const Stream<double>.empty();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FakeMapLibrePlatform.register();
  });

  testWidgets(
    'Signed-in RidesScreen and ProfileScreen show real ride history, stats, and Ride again',
    (tester) async {
      String? historyAuthHeader;

      final api = RideApiService(
        baseUrl: 'https://api.example.com',
        client: MockClient((request) async {
          if (request.method == 'GET' && request.url.path == '/auth/me') {
            return http.Response(
              jsonEncode({
                'id': 7,
                'email': 'nawaf@example.com',
                'name': 'Nawaf',
                'created_at': '2026-11-23T12:00:00Z',
              }),
              200,
            );
          }
          if (request.method == 'GET' && request.url.path == '/rides/history') {
            historyAuthHeader = request.headers['authorization'];
            return http.Response(
              jsonEncode({
                'stats': {
                  'total_rides': 3,
                  'hosted_rides': 2,
                  'joined_rides': 1,
                  'total_minutes': 95,
                },
                'rides': [
                  {
                    'code': 'PAST01',
                    'destination': 'Daman-e-Koh',
                    'dest_lat': 33.7394,
                    'dest_lng': 73.0558,
                    'host_name': 'Nawaf',
                    'is_host': true,
                    'rider_count': 4,
                    'started_at': '2026-11-23T10:00:00Z',
                    'ended_at': '2026-11-23T10:45:00Z',
                    'duration_minutes': 45,
                  },
                  {
                    'code': 'PAST02',
                    'destination': 'Murree',
                    'dest_lat': null,
                    'dest_lng': null,
                    'host_name': 'Bilal',
                    'is_host': false,
                    'rider_count': 2,
                    'started_at': '2026-11-22T09:00:00Z',
                    'ended_at': '2026-11-22T09:50:00Z',
                    'duration_minutes': 50,
                  },
                ],
              }),
              200,
            );
          }
          return http.Response('Not found', 404);
        }),
      );

      const session = AuthSession(
        accessToken: 'tok_hist_1',
        user: AuthUser(id: 7, email: 'nawaf@example.com', name: 'Nawaf'),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MainScreen(
            apiService: api,
            locationService: const _IdleLocationService(),
            initialAuthSession: session,
            initialTabIndex: 1, // Rides tab
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Rides tab displays real completed rides from GET /rides/history.
      expect(historyAuthHeader, 'Bearer tok_hist_1');
      expect(find.text('Daman-e-Koh'), findsOneWidget);
      expect(find.text('Murree'), findsOneWidget);
      expect(find.text('Host'), findsOneWidget);
      expect(find.text('Joined'), findsOneWidget);
      expect(find.textContaining('45 min · 4 riders'), findsOneWidget);

      // Profile tab displays aggregated rider stats.
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('Rides'), findsAtLeastNWidgets(2));
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Hosted'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Time ridden'), findsOneWidget);
      expect(find.text('1h 35m'), findsOneWidget);

      // Back to Rides tab -> tapping "Ride again" opens HostRideScreen with pin set.
      await tester.tap(find.text('Rides').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ride again').first);
      await tester.pumpAndSettle();
      expect(find.text('Host a Ride'), findsOneWidget);
      expect(find.text('Daman-e-Koh'), findsOneWidget);
      expect(find.textContaining('Map pin set'), findsOneWidget);
    },
  );
}
