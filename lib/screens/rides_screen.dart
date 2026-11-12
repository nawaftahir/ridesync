import 'package:flutter/material.dart';
import 'package:ridesync/models/active_ride.dart';
import 'package:ridesync/repositories/ride_repository.dart';

// Shows quick actions to host/join a ride and a list of past rides (mock data).
class RidesScreen extends StatelessWidget {
  const RidesScreen({
    super.key,
    required this.activeRide,
    required this.onOpenMap,
    required this.onHostRide,
    required this.onJoinRide,
    this.rideRepository = const RideRepository(),
  });

  final ActiveRide? activeRide;
  final VoidCallback onOpenMap;
  final VoidCallback onHostRide;
  final VoidCallback onJoinRide;
  final RideRepository rideRepository;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final pastRides = rideRepository.pastRides;

    return Scaffold(
      appBar: AppBar(title: const Text('Rides')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (activeRide != null) ...[
            Card(
              color: colors.primaryContainer,
              child: ListTile(
                leading: Icon(
                  Icons.navigation,
                  color: colors.onPrimaryContainer,
                ),
                title: Text(
                  activeRide!.destination,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: colors.onPrimaryContainer,
                  ),
                ),
                subtitle: Text(
                  'Live now · Code ${activeRide!.joinCode}',
                  style: TextStyle(color: colors.onPrimaryContainer),
                ),
                trailing: TextButton(
                  onPressed: onOpenMap,
                  child: const Text('Map'),
                ),
                onTap: onOpenMap,
              ),
            ),
            const SizedBox(height: 16),
          ],

          FilledButton.icon(
            onPressed: onHostRide,
            icon: const Icon(Icons.add_road),
            label: const Text('Host a ride'),
          ),
          const SizedBox(height: 12),

          OutlinedButton.icon(
            onPressed: onJoinRide,
            icon: const Icon(Icons.group_add),
            label: const Text('Join with a code'),
          ),
          const SizedBox(height: 28),

          Text(
            'Past rides',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),

          for (final ride in pastRides)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: colors.primaryContainer,
                  foregroundColor: colors.onPrimaryContainer,
                  child: const Icon(Icons.two_wheeler),
                ),
                title: Text(
                  ride.destination,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${ride.dateLabel} · ${ride.durationMinutes} min · '
                  '${ride.distanceKm} km',
                ),
                trailing: Text(
                  '${ride.riderCount} riders',
                  style: text.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
