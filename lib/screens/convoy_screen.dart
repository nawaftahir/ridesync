import 'package:flutter/material.dart';
import 'package:ridesync/models/rider_position.dart';
import 'package:ridesync/widgets/rider_tile.dart';

// Shows everyone in the ride as a list of tiles. Not used yet. It waits for
// real rider data, and it will be opened from the ride screen later.
class ConvoyScreen extends StatelessWidget {
  const ConvoyScreen({super.key, required this.riders});

  final List<RiderPosition> riders;

  @override
  Widget build(BuildContext context) {
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
          for (final r in riders) RiderTile(position: r),
        ],
      ),
    );
  }
}
