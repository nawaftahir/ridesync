import 'package:flutter/material.dart';
import 'package:ridesync/models/rider_position.dart';
import 'package:ridesync/widgets/rider_tile.dart';

// Shows everyone in the ride as a list of tiles. Opened from the ride map.
class ConvoyScreen extends StatelessWidget {
  const ConvoyScreen({super.key, required this.riders});

  final List<RiderPosition> riders;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Convoy')),
      body: riders.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Waiting for riders\' GPS updates…',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Riders (${riders.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final position in riders) RiderTile(position: position),
              ],
            ),
    );
  }
}
