import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ridesync/main.dart';
import 'package:ridesync/models/auth_session.dart';
import 'package:ridesync/screens/login_screen.dart';
import 'package:ridesync/screens/main_screen.dart';
import 'package:ridesync/services/app_preferences.dart';
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
    'LoginScreen signs up, logs in, validates input, and persists session',
    (tester) async {
      String? lastPath;
      Map<String, dynamic>? lastBody;

      final api = RideApiService(
        baseUrl: 'https://api.example.com',
        client: MockClient((request) async {
          lastPath = request.url.path;
          lastBody = jsonDecode(request.body) as Map<String, dynamic>;
          if (request.url.path == '/auth/register') {
            return http.Response(
              jsonEncode({
                'access_token': 'tok_register_1',
                'token_type': 'bearer',
                'user': {
                  'id': 7,
                  'email': 'nawaf@example.com',
                  'name': lastBody!['name'],
                  'created_at': '2026-11-23T12:00:00Z',
                },
              }),
              201,
            );
          }
          if (request.url.path == '/auth/login') {
            if (lastBody!['password'] != 'secret123') {
              return http.Response(
                jsonEncode({'detail': 'Invalid email or password.'}),
                401,
              );
            }
            return http.Response(
              jsonEncode({
                'access_token': 'tok_login_2',
                'token_type': 'bearer',
                'user': {
                  'id': 7,
                  'email': 'nawaf@example.com',
                  'name': 'Nawaf',
                  'created_at': '2026-11-23T12:00:00Z',
                },
              }),
              200,
            );
          }
          return http.Response('Not found', 404);
        }),
      );

      AuthSession? returnedSession;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  returnedSession = await Navigator.of(context)
                      .push<AuthSession>(
                        MaterialPageRoute(
                          builder: (_) => LoginScreen(apiService: api),
                        ),
                      );
                },
                child: const Text('Open Auth'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Auth'));
      await tester.pumpAndSettle();

      // Validation catches short password before hitting API.
      await tester.enterText(find.byType(TextField).first, 'nawaf@example.com');
      await tester.enterText(find.byType(TextField).last, '123');
      final loginButton = find.widgetWithText(FilledButton, 'Log In');
      await tester.ensureVisible(loginButton);
      await tester.tap(loginButton);
      await tester.pumpAndSettle();
      expect(
        find.text('Password must be at least 6 characters.'),
        findsOneWidget,
      );

      // Wrong password displays server error.
      await tester.enterText(find.byType(TextField).last, 'wrongpass');
      await tester.ensureVisible(loginButton);
      await tester.tap(loginButton);
      await tester.pumpAndSettle();
      expect(find.text('Invalid email or password.'), findsOneWidget);

      // Switch to Sign Up and create an account.
      await tester.ensureVisible(find.text("Don't have an account?  Sign up"));
      await tester.tap(find.text("Don't have an account?  Sign up"));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Captain Nawaf');
      await tester.enterText(find.byType(TextField).at(1), 'nawaf@example.com');
      await tester.enterText(find.byType(TextField).at(2), 'secret123');
      await tester.ensureVisible(find.text('Create Account'));
      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();

      expect(lastPath, '/auth/register');
      expect(returnedSession?.accessToken, 'tok_register_1');
      expect(returnedSession?.user.name, 'Captain Nawaf');

      final stored = await AppPreferences().loadAuthSession();
      expect(stored?.accessToken, 'tok_register_1');
      expect(stored?.user.email, 'nawaf@example.com');
    },
  );

  testWidgets(
    'Signed-in MainScreen syncs name, attaches Bearer token, and logs out',
    (tester) async {
      String? patchAuthHeader;
      String? patchedName;
      String? createRideAuthHeader;
      bool loggedOutOnServer = false;

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
          if (request.method == 'PATCH' && request.url.path == '/auth/me') {
            patchAuthHeader = request.headers['authorization'];
            patchedName =
                (jsonDecode(request.body) as Map<String, dynamic>)['name']
                    as String?;
            return http.Response(
              jsonEncode({
                'id': 7,
                'email': 'nawaf@example.com',
                'name': patchedName,
                'created_at': '2026-11-23T12:00:00Z',
              }),
              200,
            );
          }
          if (request.method == 'POST' && request.url.path == '/rides') {
            createRideAuthHeader = request.headers['authorization'];
            return http.Response(
              jsonEncode({
                'code': 'AUTH77',
                'destination': 'Monal',
                'host_id': 7,
                'host_name': patchedName ?? 'Nawaf',
                'started_at': '2026-11-23T12:00:00Z',
              }),
              201,
            );
          }
          if (request.method == 'POST' && request.url.path == '/auth/logout') {
            loggedOutOnServer = true;
            return http.Response(jsonEncode({'ok': true}), 200);
          }
          return http.Response('Not found', 404);
        }),
      );

      const session = AuthSession(
        accessToken: 'tok_live_99',
        user: AuthUser(id: 7, email: 'nawaf@example.com', name: 'Nawaf'),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MainScreen(
            apiService: api,
            locationService: const _IdleLocationService(),
            initialAuthSession: session,
            initialTabIndex: 3, // Profile
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nawaf'), findsOneWidget);
      expect(find.text('nawaf@example.com'), findsOneWidget);
      expect(find.text('Signed in'), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);

      // Editing display name calls PATCH /auth/me with Bearer token.
      await tester.tap(find.text('Nawaf'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Rider Nawaf');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(patchAuthHeader, 'Bearer tok_live_99');
      expect(patchedName, 'Rider Nawaf');
      expect(find.text('Rider Nawaf'), findsOneWidget);

      // Hosting a ride shows signed-in banner and attaches Bearer token.
      await tester.tap(find.text('Rides'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Host a ride'));
      await tester.pumpAndSettle();
      expect(find.text('Hosting as Rider Nawaf'), findsOneWidget);

      await tester.tap(find.text('Where are you riding?'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Monal');
      await tester.pump();
      await tester.tap(find.text('Use "Monal"'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate Join Code'));
      await tester.pumpAndSettle();
      expect(createRideAuthHeader, 'Bearer tok_live_99');
      expect(find.text('AUTH77'), findsOneWidget);

      // Back out of HostRideScreen and log out from Profile.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();

      expect(loggedOutOnServer, isTrue);
      expect(find.text('Sign up or log in'), findsOneWidget);
      expect(await AppPreferences().loadAuthSession(), isNull);
    },
  );

  testWidgets('RideSyncApp skips guest HomeScreen when a saved session exists', (
    tester,
  ) async {
    const saved = AuthSession(
      accessToken: 'tok_saved',
      user: AuthUser(id: 9, email: 'zain@example.com', name: 'Zain'),
    );
    await AppPreferences().saveAuthSession(saved);

    await tester.pumpWidget(const RideSyncApp());
    await tester.pumpAndSettle();

    // Entered MainScreen directly on Rides tab with bottom navigation visible.
    expect(find.text('Map'), findsOneWidget);
    expect(find.text('Group'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Explore live map'), findsNothing);
  });
}
