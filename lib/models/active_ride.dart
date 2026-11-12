// Holds the active ride details passed between screens (Host/Join -> Map).
class ActiveRide {
  const ActiveRide({
    required this.joinCode,
    required this.destination,
    required this.isHost,
    this.pickupLabel = 'F-6, Islamabad',
    this.distanceKm = 8.2,
    this.durationMinutes = 18,
  });

  final String joinCode;
  final String destination;
  final bool isHost;
  final String pickupLabel;
  final double distanceKm;
  final int durationMinutes;
}
