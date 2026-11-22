import 'package:flutter/material.dart';
import 'package:ridesync/models/active_ride.dart';

// Shows quick actions to host/join a ride and the active ride shortcut.
class RidesScreen extends StatelessWidget {
  const RidesScreen({
    super.key,
    required this.activeRide,
    required this.onOpenMap,
    required this.onHostRide,
    required this.onJoinRide,
  });

  final ActiveRide? activeRide;
  final VoidCallback onOpenMap;
  final VoidCallback onHostRide;
  final VoidCallback onJoinRide;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

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

          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.history, size: 40, color: colors.onSurfaceVariant),
                  const SizedBox(height: 10),
                  Text(
                    'No past rides yet',
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your completed rides will appear here once ride history sync is added.',
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
