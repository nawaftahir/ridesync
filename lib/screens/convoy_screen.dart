import 'package:flutter/material.dart';
import 'package:ridesync/models/rider_position.dart';
import 'package:ridesync/widgets/rider_tile.dart';

// Shows everyone in the ride as a list of tiles. Opened from the ride map.
class ConvoyScreen extends StatelessWidget {
  const ConvoyScreen({super.key, required this.riders});

  final List<RiderPosition> riders;

  @override
  Widget build(BuildContext context) {
    // Build one tile per rider.
    final tiles = <Widget>[];
    for (int i = 0; i < riders.length; i++) {
      tiles.add(RiderTile(position: riders[i]));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Convoy')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Riders (${riders.length})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Column(children: tiles),
        ],
      ),
    );
  }
}
