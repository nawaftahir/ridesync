import 'package:ridesync/models/rider.dart';
import 'package:ridesync/models/rider_position.dart';

/// Made-up riders so we can build and test the screens before there is any
/// real data. One rider has a battery level, one has none, one lost signal.
const sampleRiders = [
  RiderPosition(
    rider: Rider(id: 1, name: 'Nawaf'),
    latitude: 24.86,
    longitude: 67.00,
    speedKmh: 62,
    headingDegrees: 90,
    batteryPercent: 80,
    ageSeconds: 3,
  ),
  RiderPosition(
    rider: Rider(id: 2, name: 'Ahmed'),
    latitude: 24.87,
    longitude: 67.01,
    speedKmh: 58,
    headingDegrees: 85,
    batteryPercent: null,
    ageSeconds: 5,
  ),
  RiderPosition(
    rider: Rider(id: 3, name: 'Bilal'),
    latitude: 24.85,
    longitude: 66.99,
    speedKmh: 0,
    headingDegrees: 0,
    batteryPercent: 15,
    ageSeconds: 95,
  ),
];
