import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

export 'package:geolocator/geolocator.dart'
    show LocationServiceDisabledException;

// Current state of device GPS and location permission.
enum LocationStatus {
  checking,
  ready,
  serviceDisabled,
  denied,
  deniedForever,
  unavailable,
}

// A single GPS reading from the device, converted into map-friendly values.
class GpsFix {
  const GpsFix({required this.point, required this.speedKmh});

  final LatLng point;
  final double speedKmh;

  factory GpsFix.fromPosition(Position position) {
    // Geolocator reports speed in m/s (or negative when unavailable).
    final speedMetersPerSec = position.speed < 0 ? 0.0 : position.speed;
    return GpsFix(
      point: LatLng(position.latitude, position.longitude),
      speedKmh: speedMetersPerSec * 3.6,
    );
  }
}

// Wraps Geolocator so RideMapScreen stays easy to read and test.
class LocationService {
  const LocationService();

  static const LocationSettings _liveSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 3, // meters moved before sending the next update
  );

  // Checks and requests runtime location permission in-app.
  // Note: we intentionally do not fail early on isLocationServiceEnabled() here
  // so subscribing to fixStream() can trigger Android's in-app "Turn on location"
  // dialog instead of kicking the user out to Settings.
  Future<LocationStatus> ensurePermission() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      return switch (permission) {
        LocationPermission.always ||
        LocationPermission.whileInUse => LocationStatus.ready,
        LocationPermission.denied => LocationStatus.denied,
        LocationPermission.deniedForever => LocationStatus.deniedForever,
        LocationPermission.unableToDetermine => LocationStatus.unavailable,
      };
    } on MissingPluginException {
      return LocationStatus.unavailable;
    } on UnsupportedError {
      return LocationStatus.unavailable;
    } on Exception {
      return LocationStatus.unavailable;
    }
  }

  // Returns the phone's cached position quickly (not supported on web).
  Future<GpsFix?> getLastKnownFix() async {
    if (kIsWeb) return null;
    try {
      final position = await Geolocator.getLastKnownPosition();
      return position == null ? null : GpsFix.fromPosition(position);
    } on UnsupportedError {
      return null;
    } on Exception {
      return null;
    }
  }

  // Emits live GPS updates and triggers Android's in-app GPS dialog if off.
  Stream<GpsFix> fixStream() {
    return Geolocator.getPositionStream(locationSettings: _liveSettings)
        .map(GpsFix.fromPosition);
  }

  // Emits true/false whenever the user toggles GPS from Quick Settings.
  Stream<bool> serviceEnabledStream() {
    try {
      return Geolocator.getServiceStatusStream().map(
        (status) => status == ServiceStatus.enabled,
      );
    } on MissingPluginException {
      return const Stream<bool>.empty();
    } on UnsupportedError {
      return const Stream<bool>.empty();
    } on Exception {
      return const Stream<bool>.empty();
    }
  }

  Future<bool> openAppSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } on UnsupportedError {
      return false;
    } on Exception {
      return false;
    }
  }

  Future<bool> openLocationSettings() async {
    try {
      return await Geolocator.openLocationSettings();
    } on UnsupportedError {
      return false;
    } on Exception {
      return false;
    }
  }
}
