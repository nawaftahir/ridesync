import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridesync/models/active_ride.dart';
import 'package:ridesync/models/rider.dart';
import 'package:ridesync/models/rider_position.dart';
import 'package:ridesync/screens/group_screen.dart';
import 'package:ridesync/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'GroupScreen creates, edits, persists, and deletes riding crews',
    (tester) async {
      var hostedFromCrew = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: GroupScreen(
            activeRide: null,
            riders: const [],
            onHostRide: () => hostedFromCrew = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No riding crews yet'), findsOneWidget);

      // Create a new crew.
      await tester.tap(find.text('Create Crew'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'Margalla Dawn Riders',
      );
      await tester.enterText(find.byType(TextField).last, 'Bilal, Zain');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('Margalla Dawn Riders'), findsOneWidget);
      expect(find.text('2 riders'), findsOneWidget);
      expect(find.text('Bilal'), findsOneWidget);
      expect(find.text('Zain'), findsOneWidget);

      // Start Ride with Crew triggers callback.
      await tester.tap(find.text('Start Ride with Crew'));
      await tester.pump();
      expect(hostedFromCrew, isTrue);

      // Rebuilding GroupScreen reloads saved crews from SharedPreferences.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const GroupScreen(activeRide: null, riders: []),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Margalla Dawn Riders'), findsOneWidget);

      // Delete the crew via popup menu.
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('No riding crews yet'), findsOneWidget);
    },
  );

  testWidgets(
    'GroupScreen shares active convoy invite and opens ConvoyScreen',
    (tester) async {
      String? sharedText;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: GroupScreen(
            activeRide: const ActiveRide(
              joinCode: 'CREW77',
              destination: 'Daman-e-Koh',
              isHost: true,
            ),
            riders: const [
              RiderPosition(
                rider: Rider(id: 1, name: 'Bilal'),
                latitude: 33.72,
                longitude: 73.04,
                speedKmh: 38,
                headingDegrees: 0,
                batteryPercent: 88,
                ageSeconds: 4,
              ),
            ],
            serverBaseUrl: 'https://api.example.com',
            onShareOverride: (text, _) async {
              sharedText = text;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Active convoy (1 riders)'), findsOneWidget);
      expect(find.text('CREW77'), findsOneWidget);

      await tester.tap(find.text('Share invite'));
      await tester.pump();
      expect(sharedText, contains('https://api.example.com/join/CREW77'));

      await tester.tap(find.text('View convoy'));
      await tester.pumpAndSettle();
      expect(find.text('Convoy'), findsOneWidget);
      expect(find.text('Bilal'), findsOneWidget);
    },
  );
}
