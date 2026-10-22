import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:ridesync/data/mock_map_data.dart';
import 'package:ridesync/models/rider_position.dart';
import 'package:ridesync/repositories/rider_repository.dart';
import 'package:ridesync/screens/convoy_screen.dart';

class RideMapScreen extends StatelessWidget {
  const RideMapScreen({
    super.key,
    required this.joinCode,
    required this.destination,
    required this.isHost,
    this.riderRepository = const RiderRepository(),
  });

  final String joinCode; // shown as a chip in the app bar
  final String destination; // shown as the app bar title
  final bool isHost; // true = show the "End Ride" button
  final RiderRepository riderRepository;

  // Turns RiderPosition list → flutter_map Marker list.
  // Blue pin = active, red pin = signal lost (ageSeconds > 60).
  List<Marker> _buildMarkers(List<RiderPosition> positions) {
    final markers = <Marker>[];

    for (int i = 0; i < positions.length; i++) {
      final position = positions[i];
      final color = position.isStale ? Colors.redAccent : Colors.blueAccent;
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
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(destination),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Chip(
              avatar: const Icon(Icons.vpn_key, size: 16),
              label: Text(joinCode),
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
              ),
              MarkerLayer(markers: _buildMarkers(riderRepository.positions)),
            ],
          ),

          // Bottom info bar — Positioned pins it to the bottom of the Stack.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: colors.surface.withValues(alpha: 0.92),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Row(
                children: [
                  Chip(
                    avatar: const Icon(Icons.people_outline, size: 18),
                    label: Text('${riderRepository.positions.length} riders'),
                  ),
                  const SizedBox(width: 12),
                  Chip(
                    avatar: Icon(Icons.circle, size: 10, color: colors.primary),
                    label: Text(
                      'Active',
                      style: text.bodySmall?.copyWith(color: colors.primary),
                    ),
                  ),
                  const Spacer(),
                  // Only the host gets to end the ride.
                  if (isHost)
                    FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.errorContainer,
                        foregroundColor: colors.onErrorContainer,
                      ),
                      onPressed: () =>
                          Navigator.of(context).popUntil((r) => r.isFirst),
                      child: const Text('End Ride'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),

      // FAB opens the ConvoyScreen (rider list).
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ConvoyScreen(riders: riderRepository.positions),
          ),
        ),
        icon: const Icon(Icons.people),
        label: const Text('Riders'),
      ),
    );
  }
}
