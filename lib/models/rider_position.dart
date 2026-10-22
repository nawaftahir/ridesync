import 'package:latlong2/latlong.dart';
import 'package:ridesync/models/rider.dart';

class RiderPosition {
  const RiderPosition({
    required this.rider,
    required this.latitude,
    required this.longitude,
    required this.speedKmh,
    required this.headingDegrees,
    required this.batteryPercent,
    required this.ageSeconds,
  });

  final Rider rider;
  final double latitude;
  final double longitude;
  final double speedKmh;
  final double headingDegrees;
  final int? batteryPercent;
  final int ageSeconds;

  LatLng get point {
    return LatLng(latitude, longitude);
  }

  // A rider is "stale" (signal lost) if their last update is over 60s old.
  bool get isStale {
    return ageSeconds > 60;
  }
}
