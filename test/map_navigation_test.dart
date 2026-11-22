import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre/maplibre.dart';
import 'package:ridesync/main.dart';
import 'package:ridesync/models/active_ride.dart';
import 'package:ridesync/screens/main_screen.dart';
import 'package:ridesync/utils/map_styles.dart';

import 'helpers/fake_maplibre_platform.dart';

void main() {
  late FakeMapLibrePlatform fakeMap;

  setUp(() {
    fakeMap = FakeMapLibrePlatform.register();
  });

  testWidgets(
    'MapLibre switches OpenFreeMap liberty/dark styles and enables 3D gestures',
    (tester) async {
      await tester.pumpWidget(
        const RideSyncApp(initialThemeMode: ThemeMode.light),
      );
      await tester.pumpAndSettle();

      var map = tester.widget<MapLibreMap>(find.byType(MapLibreMap));
      expect(
        map.options.style,
        const MapStyle.url(OpenFreeMapStyles.lightStyleUrl),
      );
      expect(map.options.minZoom, equals(3));
      expect(map.options.maxZoom, equals(20));
      expect(map.options.maxPitch, equals(60));
      expect(map.options.movements.rotate, isTrue);
      expect(map.options.movements.pitch, isTrue);

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle();

      map = tester.widget<MapLibreMap>(find.byType(MapLibreMap));
      expect(
        map.options.style,
        const MapStyle.url(OpenFreeMapStyles.darkStyleUrl),
      );
    },
  );

  testWidgets(
    '3D tilt toggle, compass reset-to-North, and zoom buttons work cleanly',
    (tester) async {
      await tester.pumpWidget(const RideSyncApp());
      await tester.pumpAndSettle();

      final state = fakeMap.latestState!;
      expect(state.camera!.zoom, equals(14));
      expect(state.camera!.pitch, equals(0));
      expect(find.byTooltip('Reset to North'), findsNothing);

      // Tap 3D button -> tilts camera to 45 degrees and shows compass reset.
      await tester.tap(find.text('3D'));
      await tester.pumpAndSettle();
      expect(state.camera!.pitch, equals(45));
      expect(find.text('2D'), findsOneWidget);
      expect(find.byTooltip('Reset to North'), findsOneWidget);

      // Simulate user twisting the map by 55 degrees -> tap compass to reset.
      state.simulateGestureCamera(bearing: 55, pitch: 45);
      await tester.pumpAndSettle();
      expect(state.camera!.bearing, equals(55));

      await tester.tap(find.byTooltip('Reset to North'));
      await tester.pumpAndSettle();
      expect(state.camera!.bearing, equals(0));
      expect(state.camera!.pitch, equals(0));
      expect(find.text('3D'), findsOneWidget);
      expect(find.byTooltip('Reset to North'), findsNothing);

      // Tap zoom in repeatedly; must clamp at maxZoom (20).
      for (var i = 0; i < 8; i++) {
        await tester.tap(find.byTooltip('Zoom in'));
      }
      await tester.pumpAndSettle();
      expect(state.camera!.zoom, equals(20));

      // Tap zoom out past minZoom; must clamp at minZoom (3).
      for (var i = 0; i < 20; i++) {
        await tester.tap(find.byTooltip('Zoom out'));
      }
      await tester.pumpAndSettle();
      expect(state.camera!.zoom, equals(3));
    },
  );

  testWidgets(
    'RideMapScreen keeps OpenFreeMap attribution chip visible above bottom sheet',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: MainScreen(
            initialActiveRide: ActiveRide(
              joinCode: 'MAP123',
              destination: 'Daman-e-Koh, Islamabad',
              isHost: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final chip = find.text('© OpenFreeMap · OSM');
      expect(chip, findsOneWidget);

      final chipRect = tester.getRect(chip);
      final sheetRect = tester.getRect(find.text('Group ride'));
      expect(chipRect.bottom, lessThan(sheetRect.top));
    },
  );

  testWidgets(
    'RideMapScreen bottom sheet supports vertical swipe to collapse and expand',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MainScreen(
            initialActiveRide: ActiveRide(
              joinCode: 'MAP123',
              destination: 'Daman-e-Koh, Islamabad',
              isHost: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PICKUP'), findsOneWidget);

      await tester.fling(find.text('Group ride'), const Offset(0, 120), 600);
      await tester.pumpAndSettle();
      expect(find.text('PICKUP'), findsNothing);

      await tester.fling(find.text('Group ride'), const Offset(0, -120), 600);
      await tester.pumpAndSettle();
      expect(find.text('PICKUP'), findsOneWidget);
    },
  );
}
