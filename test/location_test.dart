import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:ridesync/screens/main_screen.dart';
import 'package:ridesync/services/location_service.dart';
import 'package:ridesync/theme/app_theme.dart';

class _FakeLocationService extends LocationService {
  _FakeLocationService({
    required this.status,
    this.streamFactory,
    this.serviceStream,
  });

  LocationStatus status;
  final Stream<GpsFix> Function()? streamFactory;
  final Stream<bool>? serviceStream;
  bool openedLocationSettings = false;

  @override
  Future<LocationStatus> ensurePermission() async => status;

  @override
  Future<GpsFix?> getLastKnownFix() async => null;

  @override
  Stream<GpsFix> fixStream() =>
      streamFactory?.call() ?? const Stream<GpsFix>.empty();

  @override
  Stream<bool> serviceEnabledStream() =>
      serviceStream ?? const Stream<bool>.empty();

  @override
  Future<bool> openLocationSettings() async {
    openedLocationSettings = true;
    return true;
  }
}

Position _buildPosition({required double speedMetersPerSec}) {
  return Position(
    longitude: 73.0433,
    latitude: 33.7215,
    timestamp: DateTime(2026, 11, 13),
    accuracy: 5,
    altitude: 500,
    altitudeAccuracy: 1,
    heading: 0,
    headingAccuracy: 1,
    speed: speedMetersPerSec,
    speedAccuracy: 1,
  );
}

void main() {
  test('GpsFix converts m/s to km/h and clamps negative speed to zero', () {
    final moving = GpsFix.fromPosition(_buildPosition(speedMetersPerSec: 10));
    expect(moving.speedKmh, closeTo(36.0, 0.01));

    final unknown = GpsFix.fromPosition(_buildPosition(speedMetersPerSec: -1));
    expect(unknown.speedKmh, 0.0);
  });

  testWidgets(
    'Shows denied permission banner and retries when Allow is tapped',
    (tester) async {
      final fakeLocation = _FakeLocationService(status: LocationStatus.denied);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MainScreen(locationService: fakeLocation),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Location permission denied'), findsOneWidget);
      expect(find.text('Allow'), findsOneWidget);

      // Simulate the user granting permission and tapping Allow.
      fakeLocation.status = LocationStatus.ready;
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();

      expect(find.text('Location permission denied'), findsNothing);
    },
  );

  testWidgets('Displays live GPS marker and updates speed from stream', (
    tester,
  ) async {
    final controller = StreamController<GpsFix>.broadcast();
    addTearDown(controller.close);

    final fakeLocation = _FakeLocationService(
      status: LocationStatus.ready,
      streamFactory: () => controller.stream,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MainScreen(locationService: fakeLocation),
      ),
    );
    // Let _startLocationTracking finish subscribing to the stream.
    await tester.pumpAndSettle();

    expect(find.text('--'), findsOneWidget);

    controller.add(
      const GpsFix(point: LatLng(33.7250, 73.0480), speedKmh: 42.4),
    );
    await tester.pumpAndSettle();

    expect(find.text('42'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
  });

  testWidgets('Shows GPS off banner and retries in-app on Turn on tap', (
    tester,
  ) async {
    var attempt = 0;
    final retryController = StreamController<GpsFix>.broadcast();
    addTearDown(retryController.close);

    final fakeLocation = _FakeLocationService(
      status: LocationStatus.ready,
      streamFactory: () {
        attempt++;
        if (attempt == 1) {
          return Stream<GpsFix>.error(const LocationServiceDisabledException());
        }
        return retryController.stream;
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MainScreen(locationService: fakeLocation),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('GPS is turned off'), findsOneWidget);
    expect(find.text('Turn on'), findsOneWidget);

    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();

    expect(fakeLocation.openedLocationSettings, isFalse);

    retryController.add(
      const GpsFix(point: LatLng(33.7250, 73.0480), speedKmh: 18.0),
    );
    await tester.pumpAndSettle();

    expect(find.text('GPS is turned off'), findsNothing);
    expect(find.text('18'), findsOneWidget);
  });

  testWidgets('Auto-recovers when device GPS service is re-enabled', (
    tester,
  ) async {
    final serviceController = StreamController<bool>.broadcast();
    final fixController = StreamController<GpsFix>.broadcast();
    addTearDown(() async {
      await serviceController.close();
      await fixController.close();
    });

    final fakeLocation = _FakeLocationService(
      status: LocationStatus.ready,
      streamFactory: () => fixController.stream,
      serviceStream: serviceController.stream,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MainScreen(locationService: fakeLocation),
      ),
    );
    await tester.pumpAndSettle();

    serviceController.add(false);
    await tester.pumpAndSettle();
    expect(find.text('GPS is turned off'), findsOneWidget);

    serviceController.add(true);
    await tester.pumpAndSettle();
    expect(find.text('GPS is turned off'), findsNothing);

    fixController.add(
      const GpsFix(point: LatLng(33.7250, 73.0480), speedKmh: 25.0),
    );
    await tester.pumpAndSettle();
    expect(find.text('25'), findsOneWidget);
  });

  testWidgets('Follow-me preserves user zoom across later GPS updates', (
    tester,
  ) async {
    final fixController = StreamController<GpsFix>.broadcast();
    addTearDown(fixController.close);

    final fakeLocation = _FakeLocationService(
      status: LocationStatus.ready,
      streamFactory: () => fixController.stream,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MainScreen(locationService: fakeLocation),
      ),
    );
    await tester.pumpAndSettle();

    final controller = tester
        .widget<FlutterMap>(find.byType(FlutterMap))
        .mapController!;

    // First fix auto-zooms to street level (16).
    const firstPoint = LatLng(33.7250, 73.0480);
    fixController.add(const GpsFix(point: firstPoint, speedKmh: 20.0));
    await tester.pumpAndSettle();
    expect(controller.camera.zoom, equals(16));
    expect(controller.camera.center.latitude, closeTo(33.7250, 1e-4));

    // User zooms out twice to zoom 14; subsequent fixes must keep zoom 14.
    await tester.tap(find.byTooltip('Zoom out'));
    await tester.tap(find.byTooltip('Zoom out'));
    await tester.pumpAndSettle();
    expect(controller.camera.zoom, equals(14));

    const secondPoint = LatLng(33.7290, 73.0510);
    fixController.add(const GpsFix(point: secondPoint, speedKmh: 30.0));
    await tester.pumpAndSettle();
    expect(controller.camera.zoom, equals(14));
    expect(controller.camera.center.latitude, closeTo(33.7290, 1e-4));
  });
}
