import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:ridesync/screens/host_ride_screen.dart';
import 'package:ridesync/screens/join_ride_screen.dart';
import 'package:ridesync/screens/main_screen.dart';
import 'package:ridesync/services/location_service.dart';
import 'package:ridesync/services/ride_api_service.dart';
import 'package:ridesync/theme/app_theme.dart';

class _FakeLocationService extends LocationService {
  _FakeLocationService(this.stream);

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

void main() {
  test('RideApiService handles disabled URL and trailing slashes', () {
    final disabled = RideApiService(baseUrl: '   ');
    expect(disabled.isEnabled, isFalse);
    disabled.dispose();

    final enabled = RideApiService(baseUrl: ' http://127.0.0.1:8000/// ');
    expect(enabled.isEnabled, isTrue);
    expect(enabled.cleanBaseUrl, 'http://127.0.0.1:8000');
    enabled.dispose();
  });

  test(
    'RideApiService performs health, create, join, sync, and end calls',
    () async {
      final requests = <String>[];
      Map<String, dynamic>? lastPositionBody;

      final client = MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');

        if (request.method == 'GET' && request.url.path == '/health') {
          return http.Response(
            jsonEncode({'status': 'ok', 'database': 'connected'}),
            200,
          );
        }
        if (request.method == 'POST' && request.url.path == '/rides') {
          return http.Response(
            jsonEncode({
              'code': 'K7MPQW',
              'destination': 'Murree',
              'host_id': 10,
              'host_name': 'Nawaf',
              'started_at': '2026-11-18T12:00:00Z',
            }),
            201,
          );
        }
        if (request.method == 'POST' &&
            request.url.path == '/rides/K7MPQW/join') {
          return http.Response(
            jsonEncode({
              'code': 'K7MPQW',
              'destination': 'Murree',
              'user_id': 11,
              'name': 'Bilal',
              'is_host': false,
            }),
            200,
          );
        }
        if (request.method == 'POST' &&
            request.url.path == '/rides/MISSING/join') {
          return http.Response(
            jsonEncode({'detail': "Ride 'MISSING' was not found"}),
            404,
          );
        }
        if (request.method == 'POST' &&
            request.url.path == '/rides/K7MPQW/position') {
          lastPositionBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'code': 'K7MPQW',
              'user_id': 11,
              'updated_at': '2026-11-18T12:01:00Z',
            }),
            200,
          );
        }
        if (request.method == 'GET' &&
            request.url.path == '/rides/K7MPQW/positions') {
          return http.Response(
            jsonEncode({
              'code': 'K7MPQW',
              'destination': 'Murree',
              'is_ended': false,
              'ended_at': null,
              'riders': [
                {
                  'rider': {'id': 10, 'name': 'Nawaf'},
                  'latitude': 33.7215,
                  'longitude': 73.0433,
                  'speed_kmh': 48.0,
                  'battery_percent': 90,
                  'age_seconds': 5,
                  'is_stale': false,
                  'updated_at': '2026-11-18T12:00:55Z',
                },
              ],
            }),
            200,
          );
        }
        if (request.method == 'POST' &&
            request.url.path == '/rides/K7MPQW/end') {
          return http.Response(
            jsonEncode({'code': 'K7MPQW', 'ended_at': '2026-11-18T12:10:00Z'}),
            200,
          );
        }

        return http.Response('Not found', 404);
      });

      final api = RideApiService(
        baseUrl: 'http://127.0.0.1:8000',
        client: client,
      );

      final health = await api.checkHealth();
      expect(health.status, 'ok');
      expect(health.isDatabaseConnected, isTrue);

      final created = await api.createRide(
        destination: 'Murree',
        hostName: 'Nawaf',
      );
      expect(created.joinCode, 'K7MPQW');
      expect(created.isHost, isTrue);
      expect(created.currentUserId, 10);

      final joined = await api.joinRide(code: ' k7mpqw ', riderName: 'Bilal');
      expect(joined.joinCode, 'K7MPQW');
      expect(joined.isHost, isFalse);
      expect(joined.currentUserId, 11);

      await expectLater(
        () => api.joinRide(code: 'missing', riderName: 'Bilal'),
        throwsA(
          isA<RideApiException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having(
                (e) => e.message,
                'message',
                "Ride 'MISSING' was not found",
              ),
        ),
      );

      await api.sendPosition(
        code: 'k7mpqw',
        userId: 11,
        latitude: 33.73,
        longitude: 73.05,
        speedKmh: -4.0,
      );
      expect(lastPositionBody?['speed_kmh'], 0.0);

      final snapshot = await api.fetchPositions('K7MPQW');
      expect(snapshot.isEnded, isFalse);
      expect(snapshot.riders, hasLength(1));
      expect(snapshot.riders.first.rider.name, 'Nawaf');

      await api.endRide(code: 'k7mpqw', hostId: 10);

      final validationClient = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'detail': [
              {
                'loc': ['body', 'destination'],
                'msg': 'String should have at least 1 character',
              },
            ],
          }),
          422,
        );
      });
      final validationApi = RideApiService(
        baseUrl: 'http://127.0.0.1:8000',
        client: validationClient,
      );
      await expectLater(
        () => validationApi.createRide(destination: '', hostName: 'Nawaf'),
        throwsA(
          isA<RideApiException>()
              .having((e) => e.statusCode, 'statusCode', 422)
              .having(
                (e) => e.message,
                'message',
                'String should have at least 1 character',
              ),
        ),
      );

      expect(requests, [
        'GET /health',
        'POST /rides',
        'POST /rides/K7MPQW/join',
        'POST /rides/MISSING/join',
        'POST /rides/K7MPQW/position',
        'GET /rides/K7MPQW/positions',
        'POST /rides/K7MPQW/end',
      ]);
    },
  );

  testWidgets('HostRideScreen and JoinRideScreen talk to backend API', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.url.path == '/rides') {
        return http.Response(
          jsonEncode({
            'code': 'SRV123',
            'destination': 'Nathia Gali',
            'host_id': 1,
            'host_name': 'Nawaf',
            'started_at': '2026-11-18T12:00:00Z',
          }),
          201,
        );
      }
      if (request.url.path == '/rides/SRV123/join') {
        return http.Response(
          jsonEncode({
            'code': 'SRV123',
            'destination': 'Nathia Gali',
            'user_id': 2,
            'name': 'Bilal',
            'is_host': false,
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'detail': 'Not found'}), 404);
    });

    final api = RideApiService(
      baseUrl: 'http://127.0.0.1:8000',
      client: client,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HostRideScreen(apiService: api, hostName: 'Nawaf'),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Nathia Gali');
    await tester.tap(find.text('Generate Join Code'));
    await tester.pumpAndSettle();

    expect(find.text('SRV123'), findsOneWidget);
    expect(find.text('Start Ride'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: JoinRideScreen(apiService: api, riderName: 'Bilal'),
      ),
    );
    expect(
      find.textContaining('Connected to http://127.0.0.1:8000'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'NOPE99');
    await tester.tap(find.text('Join Ride'));
    await tester.pumpAndSettle();
    expect(find.text('Not found'), findsOneWidget);
  });

  testWidgets('MainScreen syncs live positions and ends ride against API', (
    tester,
  ) async {
    final fixController = StreamController<GpsFix>.broadcast();
    addTearDown(fixController.close);

    var postedPositions = 0;
    var endedOnServer = false;

    final client = MockClient((request) async {
      if (request.url.path == '/rides') {
        return http.Response(
          jsonEncode({
            'code': 'LIVE42',
            'destination': 'Khanpur Dam',
            'host_id': 7,
            'host_name': 'Nawaf',
            'started_at': '2026-11-18T12:00:00Z',
          }),
          201,
        );
      }
      if (request.url.path == '/rides/LIVE42/position') {
        postedPositions++;
        return http.Response(
          jsonEncode({
            'code': 'LIVE42',
            'user_id': 7,
            'updated_at': '2026-11-18T12:01:00Z',
          }),
          200,
        );
      }
      if (request.url.path == '/rides/LIVE42/positions') {
        return http.Response(
          jsonEncode({
            'code': 'LIVE42',
            'destination': 'Khanpur Dam',
            'is_ended': false,
            'ended_at': null,
            'riders': [
              {
                'rider': {'id': 8, 'name': 'Zain'},
                'latitude': 33.80,
                'longitude': 72.93,
                'speed_kmh': 55.0,
                'battery_percent': 82,
                'age_seconds': 3,
                'is_stale': false,
                'updated_at': '2026-11-18T12:00:57Z',
              },
            ],
          }),
          200,
        );
      }
      if (request.url.path == '/rides/LIVE42/end') {
        endedOnServer = true;
        return http.Response(
          jsonEncode({'code': 'LIVE42', 'ended_at': '2026-11-18T12:05:00Z'}),
          200,
        );
      }
      return http.Response('Unexpected ${request.url.path}', 404);
    });

    final api = RideApiService(
      baseUrl: 'http://127.0.0.1:8000',
      client: client,
    );
    final fakeLocation = _FakeLocationService(fixController.stream);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MainScreen(apiService: api, locationService: fakeLocation),
      ),
    );
    await tester.pump();

    // Backend mode starts idle rather than showing mock ride MOTO89.
    expect(find.text('Ready to ride'), findsOneWidget);

    await tester.tap(find.text('Host a ride'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Khanpur Dam');
    await tester.tap(find.text('Generate Join Code'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start Ride'));
    await tester.pumpAndSettle();

    // Active ride fetched peer Zain from /rides/LIVE42/positions.
    expect(find.text('LIVE42'), findsOneWidget);
    expect(find.text('Zain'), findsOneWidget);

    fixController.add(
      const GpsFix(point: LatLng(33.79, 72.92), speedKmh: 40.0),
    );
    await tester.pumpAndSettle();
    expect(postedPositions, 1);

    await tester.tap(find.text('End Ride'));
    await tester.pumpAndSettle();
    expect(endedOnServer, isTrue);
    expect(find.text('Ready to ride'), findsOneWidget);
  });

  testWidgets('Joined rider exits cleanly when server marks ride ended', (
    tester,
  ) async {
    var pollCount = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/rides/JOIN99/join') {
        return http.Response(
          jsonEncode({
            'code': 'JOIN99',
            'destination': 'Margalla Hills',
            'user_id': 22,
            'name': 'Bilal',
            'is_host': false,
          }),
          200,
        );
      }
      if (request.url.path == '/rides/JOIN99/positions') {
        pollCount++;
        return http.Response(
          jsonEncode({
            'code': 'JOIN99',
            'destination': 'Margalla Hills',
            'is_ended': pollCount >= 2,
            'ended_at': pollCount >= 2 ? '2026-11-18T12:15:00Z' : null,
            'riders': const [],
          }),
          200,
        );
      }
      return http.Response('Not found', 404);
    });

    final api = RideApiService(
      baseUrl: 'http://127.0.0.1:8000',
      client: client,
    );
    final fakeLocation = _FakeLocationService(const Stream<GpsFix>.empty());

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MainScreen(apiService: api, locationService: fakeLocation),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Join code'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'JOIN99');
    await tester.tap(find.text('Join Ride'));
    await tester.pumpAndSettle();

    expect(find.text('JOIN99'), findsOneWidget);
    expect(find.text('Leave'), findsOneWidget);

    // Advance past the 3-second polling interval so pollCount hits 2 (is_ended=true).
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(find.text('Ride JOIN99 was ended by the host.'), findsOneWidget);
    expect(find.text('Ready to ride'), findsOneWidget);
  });

  testWidgets('Profile Backend server dialog updates server URL preset', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MainScreen(
          locationService: _FakeLocationService(const Stream<GpsFix>.empty()),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    final serverTile = find.text('Backend server');
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Offline preview (mock rides)'), findsOneWidget);

    await tester.tap(serverTile);
    await tester.pumpAndSettle();

    expect(find.text('Backend Server URL'), findsOneWidget);
    await tester.tap(find.text('USB (127.0.0.1:8000)'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('http://127.0.0.1:8000'), findsOneWidget);

    // Switching back to Offline restores idle/mock mode cleanly.
    await tester.tap(find.text('Backend server'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Offline'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Offline preview (mock rides)'), findsOneWidget);
  });
}
