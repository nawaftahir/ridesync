import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:ridesync/data/mock_map_data.dart';
import 'package:ridesync/models/active_ride.dart';
import 'package:ridesync/models/rider_position.dart';
import 'package:ridesync/repositories/rider_repository.dart';
import 'package:ridesync/screens/convoy_screen.dart';

class RideMapScreen extends StatelessWidget {
  const RideMapScreen({
    super.key,
    required this.activeRide,
    required this.onEndRide,
    required this.onHostRide,
    required this.onJoinRide,
    this.riderRepository = const RiderRepository(),
  });

  final ActiveRide? activeRide;
  final VoidCallback onEndRide;
  final VoidCallback onHostRide;
  final VoidCallback onJoinRide;
  final RiderRepository riderRepository;

  // Turns RiderPosition list → flutter_map Marker list.
  // Main theme color = active, warning color = signal lost (ageSeconds > 60).
  List<Marker> _buildMarkers(
    BuildContext context,
    List<RiderPosition> positions,
  ) {
    final colors = Theme.of(context).colorScheme;
    final markers = <Marker>[];

    for (int i = 0; i < positions.length; i++) {
      final position = positions[i];
      final color = position.isStale ? colors.tertiary : colors.primary;
      final textColor = position.isStale ? colors.onTertiary : colors.onPrimary;
      markers.add(
        Marker(
          point: position.point,
          width: 44,
          height: 44,
          child: Tooltip(
            message:
                '${position.rider.name} · ${position.speedKmh.round()} km/h',
            child: CircleAvatar(
              backgroundColor: color,
              child: Text(
                position.rider.initial,
                style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      );
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ride = activeRide;

    return Scaffold(
      appBar: AppBar(
        title: Text(ride?.destination ?? 'RideSync'),
        actions: [
          if (ride != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                avatar: const Icon(Icons.vpn_key, size: 16),
                label: Text(ride.joinCode),
              ),
            ),
        ],
      ),

      // Stack: map sits at the bottom, info bar floats on top.
      body: Stack(
        children: [
          FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(kMapCenterLat, kMapCenterLng),
              initialZoom: 14, // 1 = world, 14 = street level
            ),
            children: [
              // TileLayer fetches map tiles from OpenStreetMap (free, no key).
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.ridesync',
                // In dark mode, darken the map tiles so they match the theme.
                tileBuilder: isDark ? darkModeTileBuilder : null,
              ),
              if (ride != null)
                MarkerLayer(
                  markers: _buildMarkers(context, riderRepository.positions),
                ),
            ],
          ),

          // Bottom bar — either shows the active ride status or Host/Join buttons.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: colors.surface.withValues(alpha: 0.92),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: ride == null
                  ? _IdleRideBar(onHostRide: onHostRide, onJoinRide: onJoinRide)
                  : Row(
                      children: [
                        Chip(
                          avatar: const Icon(Icons.people_outline, size: 18),
                          label: Text(
                            '${riderRepository.positions.length} riders',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Chip(
                          avatar: Icon(
                            Icons.circle,
                            size: 10,
                            color: colors.primary,
                          ),
                          label: Text(
                            'Active',
                            style: text.bodySmall?.copyWith(
                              color: colors.primary,
                            ),
                          ),
                        ),
                        const Spacer(),
                        FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            backgroundColor: colors.errorContainer,
                            foregroundColor: colors.onErrorContainer,
                          ),
                          onPressed: onEndRide,
                          child: Text(ride.isHost ? 'End Ride' : 'Leave'),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),

      // FAB opens the ConvoyScreen (rider list) while a ride is active.
      floatingActionButton: ride == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 64),
              child: FloatingActionButton.extended(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ConvoyScreen(riders: riderRepository.positions),
                  ),
                ),
                icon: const Icon(Icons.people),
                label: const Text('Riders'),
              ),
            ),
    );
  }
}

// Shown at the bottom of the map when no group ride is active yet.
class _IdleRideBar extends StatelessWidget {
  const _IdleRideBar({required this.onHostRide, required this.onJoinRide});

  final VoidCallback onHostRide;
  final VoidCallback onJoinRide;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'No active group ride',
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onHostRide,
                icon: const Icon(Icons.add_road),
                label: const Text('Host a ride'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onJoinRide,
                icon: const Icon(Icons.group_add),
                label: const Text('Join code'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
