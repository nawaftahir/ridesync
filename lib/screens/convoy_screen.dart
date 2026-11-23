import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:ridesync/models/rider_position.dart';
import 'package:ridesync/widgets/rider_tile.dart';

// Shows everyone in the active convoy with live speed, distance from you,
// battery %, and signal status. Tapping any rider returns them so the map
// pans straight to their location.
class ConvoyScreen extends StatelessWidget {
  const ConvoyScreen({
    super.key,
    required this.riders,
    this.currentUserId,
    this.myPoint,
    this.rideCode,
    this.destination,
  });

  final List<RiderPosition> riders;
  final int? currentUserId;
  final LatLng? myPoint;
  final String? rideCode;
  final String? destination;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final staleCount = riders.where((r) => r.isStale).length;
    final activeCount = riders.length - staleCount;

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
                if (rideCode != null || destination != null)
                  Card(
                    color: colors.primaryContainer,
                    margin: const EdgeInsets.only(bottom: 14),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            Icons.two_wheeler_rounded,
                            color: colors.onPrimaryContainer,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (destination != null &&
                                    destination!.isNotEmpty)
                                  Text(
                                    destination!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: colors.onPrimaryContainer,
                                    ),
                                  ),
                                Text(
                                  '$activeCount active'
                                  '${staleCount > 0 ? ' · $staleCount signal lost' : ''}'
                                  '${rideCode != null ? ' · Code $rideCode' : ''}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: colors.onPrimaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Riders (${riders.length})',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Tap a rider to locate',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final position in riders)
                  RiderTile(
                    position: position,
                    isCurrentUser:
                        currentUserId != null &&
                        position.rider.id == currentUserId,
                    myPoint: myPoint,
                    onTap: () => Navigator.of(context).pop(position),
                  ),
              ],
            ),
    );
  }
}
