import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridesync/main.dart';

void main() {
  testWidgets('MainScreen renders bottom navigation and switches tabs', (
    tester,
  ) async {
    await tester.pumpWidget(const RideSyncApp());
    await tester.pump();

    // Bottom navigation shows the 4 main tabs.
    expect(find.text('Map'), findsOneWidget);
    expect(find.text('Rides'), findsOneWidget);
    expect(find.text('Group'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);

    // Map tab starts with the mock active ride.
    expect(find.text('MOTO89'), findsOneWidget);
    expect(find.text('End Ride'), findsOneWidget);

    // Switch to Rides tab and check actions & past rides.
    await tester.tap(find.text('Rides'));
    await tester.pump();
    expect(find.text('Host a ride'), findsOneWidget);
    expect(find.text('Join with a code'), findsOneWidget);
    expect(find.text('Past rides'), findsOneWidget);

    // Switch to Group tab and check work-in-progress card.
    await tester.tap(find.text('Group'));
    await tester.pump();
    expect(find.text('Work in progress'), findsOneWidget);

    // Switch to Profile tab and check profile & login link.
    await tester.tap(find.text('Profile'));
    await tester.pump();
    expect(find.text('Nawaf'), findsOneWidget);
    expect(find.text('Sign up or log in'), findsOneWidget);
  });

  testWidgets('Ending a ride shows idle bar and joining returns to Map tab', (
    tester,
  ) async {
    await tester.pumpWidget(const RideSyncApp());
    await tester.pump();

    // End the default mock ride on the Map tab.
    await tester.tap(find.text('End Ride'));
    await tester.pump();
    expect(find.text('No active group ride'), findsOneWidget);

    // Open JoinRideScreen from the Rides tab and join RIDE42.
    await tester.tap(find.text('Rides'));
    await tester.pump();
    await tester.tap(find.text('Join with a code'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'RIDE42');
    await tester.tap(find.text('Join Ride'));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();

    // Should pop back to MainScreen on the Map tab with the joined ride.
    expect(find.text('RIDE42'), findsOneWidget);
    expect(find.text('Lake View Park, Islamabad'), findsOneWidget);
    expect(find.text('Leave'), findsOneWidget);
  });
}
