import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ridesync/models/active_ride.dart';
import 'package:ridesync/screens/host_ride_screen.dart';
import 'package:ridesync/screens/main_screen.dart';
import 'package:ridesync/screens/ride_map_screen.dart';
import 'package:ridesync/services/deep_link_service.dart';
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

class _FakeDeepLinkService extends DeepLinkService {
  _FakeDeepLinkService({this.initialUri, Stream<Uri>? stream})
    : _stream = stream ?? const Stream<Uri>.empty();

  final Uri? initialUri;
  final Stream<Uri> _stream;

  @override
  Future<Uri?> getInitialUri() async => initialUri;

  @override
  Stream<Uri> uriStream() => _stream;
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

  test('buildRideJoinUrl, buildRideInviteText, and parseRideCodeFromUri', () {
    expect(
      buildRideJoinUrl(
        code: 'k7mpqw',
        serverBaseUrl: 'https://api.example.com/',
      ),
      'https://api.example.com/join/K7MPQW',
    );
    expect(
      buildRideJoinUrl(
        code: 'k7mpqw',
        serverBaseUrl: 'Https://Api.Example.com/',
      ),
      'https://api.example.com/join/K7MPQW',
    );
    expect(
      RideApiService(baseUrl: 'Https://Api.Example.com/').cleanBaseUrl,
      'https://api.example.com',
    );
    expect(buildRideJoinUrl(code: 'k7mpqw'), 'ridesync://join/K7MPQW');

    expect(
      buildRideInviteText(
        code: ' k7mpqw ',
        destination: 'Daman-e-Koh, Damn-i-koh Road, Islamabad',
        serverBaseUrl: 'https://api.example.com',
      ),
      'Join my RideSync convoy to Daman-e-Koh!\n'
      'https://api.example.com/join/K7MPQW\n'
      'Ride code: K7MPQW',
    );

    expect(parseRideCodeFromUri(Uri.parse('ridesync://join/k7mpqw')), 'K7MPQW');
    expect(
      parseRideCodeFromUri(Uri.parse('ridesync://join?code=ab12cd')),
      'AB12CD',
    );
    expect(
      parseRideCodeFromUri(Uri.parse('https://api.example.com/join/ride88')),
      'RIDE88',
    );
    expect(parseRideCodeFromUri(Uri.parse('https://api.example.com/')), isNull);
    expect(parseRideCodeFromUri(Uri.parse('ridesync://join/bad!')), isNull);
  });

  testWidgets('HostRideScreen copies and shares invite URL with join code', (
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

    await tester.tap(find.text('Copy code'));
    await tester.pump();
    expect(clipboardText, 'K7MPQW');
    expect(find.text('Copied'), findsOneWidget);
    expect(find.text('Copied ride code K7MPQW'), findsOneWidget);

    await tester.tap(find.text('Share ride'));
    await tester.pump();
    expect(
      sharedText,
      'Join my RideSync convoy to Daman-e-Koh!\n'
      'https://api.example.com/join/K7MPQW\n'
      'Ride code: K7MPQW',
    );
    expect(sharedSubject, 'RideSync convoy code: K7MPQW');

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Copy code'), findsOneWidget);
  });

  testWidgets('RideMapScreen active bar copies and shares invite URL', (
    tester,
  ) async {
    String? sharedText;

    final api = RideApiService(
      baseUrl: 'https://api.example.com',
      client: MockClient((_) async => http.Response('Not found', 404)),
    );

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
            apiService: api,
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
      'Join my RideSync convoy to Margalla Hills!\n'
      'https://api.example.com/join/RIDE88\n'
      'Ride code: RIDE88',
    );
  });

  testWidgets('Incoming ridesync://join deep link auto-joins straight to Map', (
    tester,
  ) async {
    final linkController = StreamController<Uri>.broadcast();
    addTearDown(linkController.close);

    final client = MockClient((request) async {
      if (request.method == 'POST' &&
          request.url.path == '/rides/LINK77/join') {
        return http.Response(
          jsonEncode({
            'code': 'LINK77',
            'destination': 'Nathia Gali',
            'dest_lat': 34.0728,
            'dest_lng': 73.3812,
            'user_id': 9,
            'name': 'Nawaf',
            'is_host': false,
          }),
          200,
        );
      }
      if (request.method == 'GET' &&
          request.url.path == '/rides/LINK77/positions') {
        return http.Response(
          jsonEncode({
            'code': 'LINK77',
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
          locationService: const _IdleLocationService(),
          deepLinkService: _FakeDeepLinkService(stream: linkController.stream),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Ready to ride'), findsOneWidget);

    linkController.add(Uri.parse('ridesync://join/link77'));
    await tester.pumpAndSettle();

    expect(find.text('LINK77'), findsOneWidget);
    expect(find.text('Nathia Gali'), findsNWidgets(2));
    expect(find.text('Leave'), findsOneWidget);
  });

  testWidgets('Cold-start HTTPS App Link auto-joins straight to Map', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.method == 'POST' &&
          request.url.path == '/rides/APP999/join') {
        return http.Response(
          jsonEncode({
            'code': 'APP999',
            'destination': 'Monal',
            'dest_lat': 33.7495,
            'dest_lng': 73.0551,
            'user_id': 12,
            'name': 'Nawaf',
            'is_host': false,
          }),
          200,
        );
      }
      if (request.method == 'GET' &&
          request.url.path == '/rides/APP999/positions') {
        return http.Response(
          jsonEncode({
            'code': 'APP999',
            'destination': 'Monal',
            'dest_lat': 33.7495,
            'dest_lng': 73.0551,
            'is_ended': false,
            'ended_at': null,
            'riders': const [],
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
          locationService: const _IdleLocationService(),
          deepLinkService: _FakeDeepLinkService(
            initialUri: Uri.parse('https://api.example.com/join/app999'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('APP999'), findsOneWidget);
    expect(find.text('Monal'), findsNWidgets(2));
    expect(find.text('Leave'), findsOneWidget);
  });
}
