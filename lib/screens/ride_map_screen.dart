import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:ridesync/data/mock_map_data.dart';
import 'package:ridesync/models/active_ride.dart';
import 'package:ridesync/models/rider_position.dart';
import 'package:ridesync/repositories/rider_repository.dart';
import 'package:ridesync/screens/convoy_screen.dart';

class RideMapScreen extends StatefulWidget {
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

  @override
  State<RideMapScreen> createState() => _RideMapScreenState();
}

class _RideMapScreenState extends State<RideMapScreen> {
  final MapController _mapController = MapController();
  bool _isSheetCollapsed = false;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _recenterMap() {
    _mapController.move(const LatLng(kMapCenterLat, kMapCenterLng), 14);
  }

  void _openConvoy() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConvoyScreen(riders: widget.riderRepository.positions),
      ),
    );
  }

  // Turns RiderPosition list + route endpoints into flutter_map Markers.
  List<Marker> _buildMarkers(
    BuildContext context,
    List<RiderPosition> positions,
  ) {
    final colors = Theme.of(context).colorScheme;
    final markers = <Marker>[
      // Route pickup dot and destination pin.
      Marker(
        point: kMockRoutePoints.first,
        width: 22,
        height: 22,
        child: Container(
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            shape: BoxShape.circle,
            border: Border.all(color: colors.primary, width: 4),
          ),
        ),
      ),
      Marker(
        point: kMockRoutePoints.last,
        width: 36,
        height: 36,
        alignment: Alignment.topCenter,
        child: Icon(Icons.location_on, color: colors.primary, size: 36),
      ),
    ];

    for (final position in positions) {
      final dotColor = position.isStale ? colors.tertiary : colors.secondary;
      markers.add(
        Marker(
          point: position.point,
          width: 108,
          height: 58,
          child: Tooltip(
            message:
                '${position.rider.name} · ${position.speedKmh.round()} km/h',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Text(
                    position.rider.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: position.isStale
                          ? colors.tertiary
                          : colors.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: dotColor.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colors.surfaceContainerLow,
                        width: 2.5,
                      ),
                    ),
                  ),
                ),
              ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ride = widget.activeRide;
    final positions = widget.riderRepository.positions;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: const MapOptions(
            initialCenter: LatLng(kMapCenterLat, kMapCenterLng),
            initialZoom: 14, // 1 = world, 14 = street level
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.ridesync',
              tileBuilder: isDark ? darkModeTileBuilder : null,
            ),
            if (ride != null)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: kMockRoutePoints,
                    strokeWidth: 12,
                    color: colors.primary.withValues(alpha: 0.22),
                  ),
                  Polyline(
                    points: kMockRoutePoints,
                    strokeWidth: 5,
                    color: colors.primary,
                  ),
                ],
              ),
            if (ride != null)
              MarkerLayer(markers: _buildMarkers(context, positions)),
          ],
        ),

        // Top floating destination card and right-side map controls.
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _MapTopCard(activeRide: ride, onTapIdle: widget.onHostRide),
                const SizedBox(height: 10),
                _MapActionButton(
                  icon: Icons.my_location,
                  tooltip: 'Recenter map',
                  onPressed: _recenterMap,
                ),
                if (ride != null) ...[
                  const SizedBox(height: 8),
                  _MapActionButton(
                    icon: Icons.people_outline,
                    tooltip: 'Convoy riders',
                    onPressed: _openConvoy,
                  ),
                ],
              ],
            ),
          ),
        ),

        // Bottom sheet with "Group ride" status, avatars, route card & actions.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _MapBottomSheet(
            activeRide: ride,
            positions: positions,
            isCollapsed: _isSheetCollapsed,
            onToggleCollapse: () {
              setState(() {
                _isSheetCollapsed = !_isSheetCollapsed;
              });
            },
            onOpenConvoy: _openConvoy,
            onEndRide: widget.onEndRide,
            onHostRide: widget.onHostRide,
            onJoinRide: widget.onJoinRide,
          ),
        ),
      ],
    );
  }
}

// Floating top bar showing either the active destination or "Where are you riding?".
class _MapTopCard extends StatelessWidget {
  const _MapTopCard({required this.activeRide, required this.onTapIdle});

  final ActiveRide? activeRide;
  final VoidCallback onTapIdle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final ride = activeRide;

    return Material(
      color: colors.surfaceContainerLow,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: ride == null ? onTapIdle : null,
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(
                  ride == null ? Icons.search : Icons.navigation_rounded,
                  size: 20,
                  color: ride == null
                      ? colors.onSurfaceVariant
                      : colors.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    ride?.destination ?? 'Where are you riding?',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: ride == null
                          ? colors.onSurfaceVariant
                          : colors.onSurface,
                    ),
                  ),
                ),
                if (ride != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      ride.joinCode,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Square-rounded floating button (44x44) for Recenter / Convoy controls.
class _MapActionButton extends StatelessWidget {
  const _MapActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: colors.surfaceContainerLow,
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colors.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 20, color: colors.primary),
          ),
        ),
      ),
    );
  }
}

// Rounded bottom sheet matching the DesignArtifact.html layout.
class _MapBottomSheet extends StatelessWidget {
  const _MapBottomSheet({
    required this.activeRide,
    required this.positions,
    required this.isCollapsed,
    required this.onToggleCollapse,
    required this.onOpenConvoy,
    required this.onEndRide,
    required this.onHostRide,
    required this.onJoinRide,
  });

  final ActiveRide? activeRide;
  final List<RiderPosition> positions;
  final bool isCollapsed;
  final VoidCallback onToggleCollapse;
  final VoidCallback onOpenConvoy;
  final VoidCallback onEndRide;
  final VoidCallback onHostRide;
  final VoidCallback onJoinRide;

  String _riderSummary() {
    final staleCount = positions.where((p) => p.isStale).length;
    if (staleCount == 0) {
      return 'All ${positions.length} riders active';
    }
    final activeCount = positions.length - staleCount;
    return '$activeCount active · $staleCount signal lost';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.6;
    final ride = activeRide;

    return Material(
      color: colors.surfaceContainerLow,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.24),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle — tap to collapse or expand the sheet.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onToggleCollapse,
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: colors.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          ride == null ? 'Ready to ride' : 'Group ride',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        _StatusPill(isLive: ride != null),
                      ],
                    ),
                  ],
                ),
              ),

              if (!isCollapsed && ride != null) ...[
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onOpenConvoy,
                  child: Row(
                    children: [
                      _RiderAvatarStack(positions: positions),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              positions.map((p) => p.rider.name).join(', '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              _riderSummary(),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _RouteSummaryCard(ride: ride),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: colors.errorContainer,
                    foregroundColor: colors.onErrorContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: onEndRide,
                  child: Text(ride.isHost ? 'End Ride' : 'Leave'),
                ),
              ],

              if (!isCollapsed && ride == null) ...[
                const SizedBox(height: 8),
                Text(
                  'Start a ride or join with a 6-character code.',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
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
            ],
          ),
        ),
      ),
    );
  }
}

// "Live sync" (or "Not active") pill shown at the top-right of the bottom sheet.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.isLive});

  final bool isLive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isLive
            ? colors.primaryContainer
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isLive ? colors.primary : colors.onSurfaceVariant,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            isLive ? 'Live sync' : 'Idle',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: isLive
                  ? colors.onPrimaryContainer
                  : colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// Overlapping circular avatars for riders in the current convoy.
class _RiderAvatarStack extends StatelessWidget {
  const _RiderAvatarStack({required this.positions});

  final List<RiderPosition> positions;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final visible = positions.take(3).toList();
    final avatarColors = [
      colors.primary,
      colors.secondary,
      colors.onPrimaryContainer,
    ];
    final textColors = [colors.onPrimary, colors.onSecondary, colors.surface];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < visible.length; i++)
          Align(
            widthFactor: 0.75,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: visible[i].isStale
                    ? colors.tertiary
                    : avatarColors[i % avatarColors.length],
                shape: BoxShape.circle,
                border: Border.all(
                  color: colors.surfaceContainerLow,
                  width: 2.5,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                visible[i].rider.initial,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: visible[i].isStale
                      ? colors.onTertiary
                      : textColors[i % textColors.length],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// Soft inset panel showing Pickup, Destination, ETA, and Distance.
class _RouteSummaryCard extends StatelessWidget {
  const _RouteSummaryCard({required this.ride});

  final ActiveRide ride;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.primary, width: 3),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: colors.outlineVariant,
                    ),
                  ),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colors.onSurface,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PICKUP',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    ride.pickupLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'DESTINATION',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    ride.destination,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${ride.durationMinutes} min',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                Text(
                  '${ride.distanceKm} km',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
