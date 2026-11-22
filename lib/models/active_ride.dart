import 'package:latlong2/latlong.dart';

// Holds the active ride details passed between screens (Host/Join -> Map).
class ActiveRide {
  const ActiveRide({
    required this.joinCode,
    required this.destination,
    required this.isHost,
    this.destLat,
    this.destLng,
    this.pickupLabel = 'Your location',
    this.distanceKm,
    this.durationMinutes,
    this.currentUserId,
    this.currentUserName = 'Nawaf',
  });

  final String joinCode;
  final String destination;
  final bool isHost;
  final double? destLat;
  final double? destLng;
  final String pickupLabel;
  final double? distanceKm;
  final int? durationMinutes;

  // Set when the ride comes from the FastAPI backend; null in offline demo mode.
  final int? currentUserId;
  final String currentUserName;

  LatLng? get destinationPoint =>
      (destLat != null && destLng != null) ? LatLng(destLat!, destLng!) : null;
}
