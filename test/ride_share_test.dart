import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ridesync/models/active_ride.dart';
import 'package:ridesync/screens/host_ride_screen.dart';
import 'package:ridesync/screens/ride_map_screen.dart';
import 'package:ridesync/services/location_service.dart';
import 'package:ridesync/services/ride_api_service.dart';
import 'package:ridesync/theme/app_theme.dart';
import 'package:ridesync/utils/ride_share.dart';

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
}

void main() {
  String? clipboardText;

  setUp(() {
    clipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map<dynamic, dynamic>;
            clipboardText = args['text'] as String?;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('buildRideInviteText formats uppercase code and destination', () {
    expect(
      buildRideInviteText(code: ' k7mpqw ', destination: 'Murree'),
      'Join my RideSync convoy to Murree!\nRide code: K7MPQW',
    );
    expect(
      buildRideInviteText(code: 'ab12cd', destination: ''),
      'Join my RideSync convoy!\nRide code: AB12CD',
    );
  });

  testWidgets('HostRideScreen copies and shares the generated join code', (
    tester,
  ) async {
    String? sharedText;
    String? sharedSubject;

    final client = MockClient((request) async {
      if (request.url.path == '/rides') {
        return http.Response(
          jsonEncode({
            'code': 'K7MPQW',
            'destination': 'Daman-e-Koh',
            'host_id': 1,
            'host_name': 'Nawaf',
            'started_at': '2026-11-22T12:00:00Z',
          }),
          201,
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
        home: HostRideScreen(
          apiService: api,
          hostName: 'Nawaf',
          onShareOverride: (text, subject) async {
            sharedText = text;
            sharedSubject = subject;
          },
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Daman-e-Koh');
    await tester.tap(find.text('Generate Join Code'));
    await tester.pumpAndSettle();

    expect(find.text('K7MPQW'), findsOneWidget);
    expect(find.text('Copy code'), findsOneWidget);
    expect(find.text('Share ride'), findsOneWidget);

    await tester.tap(find.text('Copy code'));
    await tester.pump();
    expect(clipboardText, 'K7MPQW');
    expect(find.text('Copied'), findsOneWidget);
    expect(find.text('Copied ride code K7MPQW'), findsOneWidget);

    await tester.tap(find.text('Share ride'));
    await tester.pump();
    expect(
      sharedText,
      'Join my RideSync convoy to Daman-e-Koh!\nRide code: K7MPQW',
    );
    expect(sharedSubject, 'RideSync convoy code: K7MPQW');

    // Let the 2-second "Copied" reset timer finish cleanly.
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Copy code'), findsOneWidget);
  });

  testWidgets('RideMapScreen active bar copies and shares the join code', (
    tester,
  ) async {
    String? sharedText;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: RideMapScreen(
            activeRide: const ActiveRide(
              joinCode: 'RIDE88',
              destination: 'Margalla Hills',
              isHost: true,
            ),
            onEndRide: () {},
            onHostRide: () {},
            onJoinRide: () {},
            locationService: const _IdleLocationService(),
            onShareOverride: (text, _) async {
              sharedText = text;
            },
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('RIDE88'));
    await tester.pump();
    expect(clipboardText, 'RIDE88');
    expect(find.text('Copied ride code RIDE88'), findsOneWidget);

    await tester.tap(find.byTooltip('Share ride code'));
    await tester.pump();
    expect(
      sharedText,
      'Join my RideSync convoy to Margalla Hills!\nRide code: RIDE88',
    );
  });
}
