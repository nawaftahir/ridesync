// Holds the active ride details passed between screens (Host/Join -> Map).
class ActiveRide {
  const ActiveRide({
    required this.joinCode,
    required this.destination,
    required this.isHost,
  });

  final String joinCode;
  final String destination;
  final bool isHost;
}
