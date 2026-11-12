import 'package:flutter/material.dart';
import 'package:ridesync/models/active_ride.dart';
import 'package:ridesync/models/rider_position.dart';
import 'package:ridesync/screens/convoy_screen.dart';

// Work-in-progress Group tab. Shows the current convoy if a ride is active
// and explains what group features will be built here later.
class GroupScreen extends StatelessWidget {
  const GroupScreen({
    super.key,
    required this.activeRide,
    required this.riders,
  });

  final ActiveRide? activeRide;
  final List<RiderPosition> riders;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Group')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (activeRide != null) ...[
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: colors.primaryContainer,
                  foregroundColor: colors.onPrimaryContainer,
                  child: const Icon(Icons.groups),
                ),
                title: Text(
                  'Active convoy (${riders.length} riders)',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  'Code ${activeRide!.joinCode} · ${activeRide!.destination}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ConvoyScreen(riders: riders),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.construction, size: 56, color: colors.tertiary),
                  const SizedBox(height: 16),
                  Text(
                    'Work in progress',
                    style: text.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Saved riding groups, member invites, and group settings '
                    'will appear here.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(
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
