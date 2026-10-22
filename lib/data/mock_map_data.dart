import 'package:ridesync/models/rider.dart';
import 'package:ridesync/models/rider_position.dart';

// Map camera start point.
const double kMapCenterLat = 33.7215;
const double kMapCenterLng = 73.0433;

// Three fake riders spread around F-6, Islamabad.
const List<RiderPosition> kMockRiderPositions = [
  RiderPosition(
    rider: Rider(id: 1, name: 'Nawaf'),
    latitude: 33.7215,
    longitude: 73.0433,
    speedKmh: 55,
    headingDegrees: 90,
    batteryPercent: 80,
    ageSeconds: 4,
  ),
  RiderPosition(
    rider: Rider(id: 2, name: 'Ahmed'),
    latitude: 33.7230,
    longitude: 73.0460,
    speedKmh: 50,
    headingDegrees: 85,
    batteryPercent: null,
    ageSeconds: 6,
  ),
  RiderPosition(
    rider: Rider(id: 3, name: 'Bilal'),
    latitude: 33.7190,
    longitude: 73.0410,
    speedKmh: 0,
    headingDegrees: 0,
    batteryPercent: 15,
    ageSeconds: 95,
  ),
];
