import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridesync/main.dart';
import 'package:ridesync/screens/main_screen.dart';
import 'package:ridesync/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('RideSyncApp starts on clean live map with 4 tabs', (
    tester,
  ) async {
    await tester.pumpWidget(const RideSyncApp());
    await tester.pump();

    // Bottom navigation shows the 4 main tabs.
    expect(find.text('Map'), findsOneWidget);
    expect(find.text('Rides'), findsOneWidget);
    expect(find.text('Group'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);

    // Live default mode starts on a clean idle map (no fake MOTO89 ride).
    expect(find.text('Where are you riding?'), findsOneWidget);
    expect(find.text('Ready to ride'), findsOneWidget);
    expect(find.text('Idle'), findsOneWidget);
    expect(find.text('Host a ride'), findsOneWidget);
    expect(find.text('Join code'), findsOneWidget);
    expect(find.byTooltip('Recenter map'), findsOneWidget);

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

    // Switch to Profile tab and check profile, live server URL, & login link.
    await tester.tap(find.text('Profile'));
    await tester.pump();
    expect(find.text('Nawaf'), findsOneWidget);
    expect(find.text('Sign up or log in'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('https://ridesync.ddns.net'), findsOneWidget);
  });

  testWidgets('Offline demo mode renders mock ride, collapse, end, and join', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const MainScreen(initialServerUrl: ''),
      ),
    );
    await tester.pump();

    // Offline preview starts with the mock active ride layout and bottom sheet.
    expect(find.text('MOTO89'), findsOneWidget);
    expect(find.text('Daman-e-Koh, Islamabad'), findsNWidgets(2));
    expect(find.text('Group ride'), findsOneWidget);
    expect(find.text('Live sync'), findsOneWidget);
    expect(find.text('PICKUP'), findsOneWidget);
    expect(find.text('DESTINATION'), findsOneWidget);
    expect(find.text('End Ride'), findsOneWidget);

    // Tapping the sheet header collapses and re-expands the bottom sheet.
    await tester.tap(find.text('Group ride'));
    await tester.pump();
    expect(find.text('PICKUP'), findsNothing);

    await tester.tap(find.text('Group ride'));
    await tester.pump();
    expect(find.text('PICKUP'), findsOneWidget);

    // End the default mock ride on the Map tab.
    await tester.tap(find.text('End Ride'));
    await tester.pump();
    expect(find.text('Where are you riding?'), findsOneWidget);
    expect(find.text('Ready to ride'), findsOneWidget);

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
    expect(find.text('Lake View Park, Islamabad'), findsNWidgets(2));
    expect(find.text('Leave'), findsOneWidget);
  });

  testWidgets('Profile appearance switches between Auto, Light, and Dark', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const RideSyncApp());
    await tester.pump();

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Auto · Follows phone Light / Dark mode'), findsOneWidget);

    MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app().themeMode, ThemeMode.system);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(app().themeMode, ThemeMode.dark);
    expect(find.text('Dark · Always uses dark theme'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.text('Appearance'))).brightness,
      Brightness.dark,
    );

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(app().themeMode, ThemeMode.light);
    expect(find.text('Light · Always uses light theme'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.text('Appearance'))).brightness,
      Brightness.light,
    );

    await tester.tap(find.text('Auto'));
    await tester.pumpAndSettle();
    expect(app().themeMode, ThemeMode.system);
    expect(find.text('Auto · Follows phone Light / Dark mode'), findsOneWidget);
  });
}
