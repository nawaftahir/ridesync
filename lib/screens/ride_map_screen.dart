import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:ridesync/data/mock_map_data.dart';
import 'package:ridesync/models/active_ride.dart';
import 'package:ridesync/models/rider_position.dart';
import 'package:ridesync/repositories/rider_repository.dart';
import 'package:ridesync/screens/convoy_screen.dart';
import 'package:ridesync/services/location_service.dart';
import 'package:ridesync/widgets/open_free_map_layer.dart';

class RideMapScreen extends StatefulWidget {
  const RideMapScreen({
    super.key,
    required this.activeRide,
    required this.onEndRide,
    required this.onHostRide,
    required this.onJoinRide,
    this.riderRepository = const RiderRepository(),
    this.locationService = const LocationService(),
  });

  final ActiveRide? activeRide;
  final VoidCallback onEndRide;
  final VoidCallback onHostRide;
  final VoidCallback onJoinRide;
  final RiderRepository riderRepository;
  final LocationService locationService;

  @override
  State<RideMapScreen> createState() => _RideMapScreenState();
}

class _RideMapScreenState extends State<RideMapScreen>
    with WidgetsBindingObserver {
  final MapController _mapController = MapController();

  StreamSubscription<GpsFix>? _positionSub;
  StreamSubscription<bool>? _serviceStatusSub;
  LocationStatus _locationStatus = LocationStatus.checking;
  GpsFix? _myFix;
  bool _followMe = true;
  bool _isMapReady = false;
  bool _hasInitialGpsCenter = false;
  bool _isSheetCollapsed = false;
  bool _bannerDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenServiceStatus();
    _startLocationTracking();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSub?.cancel();
    _serviceStatusSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _listenServiceStatus() {
    _serviceStatusSub = widget.locationService.serviceEnabledStream().listen((
      enabled,
    ) {
      if (!mounted) return;
      if (enabled && _locationStatus == LocationStatus.serviceDisabled) {
        _startLocationTracking();
      } else if (!enabled && _locationStatus == LocationStatus.ready) {
        _positionSub?.cancel();
        _positionSub = null;
        setState(() {
          _locationStatus = LocationStatus.serviceDisabled;
          _bannerDismissed = false;
        });
      }
    }, onError: (_) {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check automatically when the user returns from phone Settings.
    if (state == AppLifecycleState.resumed &&
        (_locationStatus == LocationStatus.deniedForever ||
            _locationStatus == LocationStatus.serviceDisabled)) {
      _startLocationTracking();
    }
  }

  Future<void> _startLocationTracking({
    bool fallbackToSettingsOnImmediateError = false,
  }) async {
    final status = await widget.locationService.ensurePermission();
    if (!mounted) return;
    setState(() {
      _locationStatus = status;
      _bannerDismissed = false;
    });
    if (status != LocationStatus.ready) return;

    if (_positionSub != null) {
      await _positionSub!.cancel();
      _positionSub = null;
    }

    final attemptStartedAt = DateTime.now();
    _positionSub = widget.locationService.fixStream().listen(
      _onNewFix,
      cancelOnError: true,
      onError: (Object error) {
        _positionSub = null;
        if (!mounted) return;
        if (error is LocationServiceDisabledException) {
          setState(() {
            _locationStatus = LocationStatus.serviceDisabled;
            _bannerDismissed = false;
          });
          final rejectedImmediately =
              DateTime.now().difference(attemptStartedAt) <
              const Duration(milliseconds: 350);
          if (fallbackToSettingsOnImmediateError && rejectedImmediately) {
            widget.locationService.openLocationSettings();
          }
        }
      },
    );

    final lastFix = await widget.locationService.getLastKnownFix();
    if (mounted &&
        lastFix != null &&
        _myFix == null &&
        _locationStatus == LocationStatus.ready) {
      _onNewFix(lastFix);
    }
  }

  void _onNewFix(GpsFix fix) {
    if (!mounted) return;
    setState(() {
      _locationStatus = LocationStatus.ready;
      _myFix = fix;
    });
    if (!_followMe || !_isMapReady) return;

    final camera = _mapController.camera;
    // Zoom in to street level once on the first GPS lock; after that, respect
    // whatever zoom level the rider chose.
    final targetZoom = !_hasInitialGpsCenter && camera.zoom < 16.0
        ? 16.0
        : camera.zoom;
    final movedEnough =
        (camera.center.latitude - fix.point.latitude).abs() >= 1e-5 ||
        (camera.center.longitude - fix.point.longitude).abs() >= 1e-5;
    if (!_hasInitialGpsCenter || movedEnough) {
      _hasInitialGpsCenter = true;
      _mapController.move(fix.point, targetZoom);
    }
  }

  void _recenterMap() {
    setState(() {
      _followMe = true;
    });
    if (!_isMapReady) return;
    if (_myFix != null) {
      _hasInitialGpsCenter = true;
      final currentZoom = _mapController.camera.zoom;
      final targetZoom = currentZoom < 15 ? 16.0 : currentZoom.clamp(3.0, 18.0);
      _mapController.move(_myFix!.point, targetZoom);
      return;
    }
    _mapController.move(const LatLng(kMapCenterLat, kMapCenterLng), 14.0);
  }

  void _zoomBy(double delta) {
    if (!_isMapReady) return;
    final nextZoom = (_mapController.camera.zoom + delta).clamp(3.0, 18.0);
    _mapController.move(_mapController.camera.center, nextZoom);
  }

  Future<void> _handlePermissionAction() async {
    switch (_locationStatus) {
      case LocationStatus.denied:
        await _startLocationTracking();
      case LocationStatus.serviceDisabled:
        // Re-subscribing triggers Android's in-app "Turn on location" dialog
        // without leaving the app (falls back to Settings only if unsupported).
        await _startLocationTracking(fallbackToSettingsOnImmediateError: true);
      case LocationStatus.deniedForever:
        await widget.locationService.openAppSettings();
      case LocationStatus.checking:
      case LocationStatus.ready:
      case LocationStatus.unavailable:
        break;
    }
  }

  // Updates the first rider with live GPS data when a real fix is available.
  List<RiderPosition> _effectivePositions() {
    final base = widget.riderRepository.positions;
    final fix = _myFix;
    if (fix == null || base.isEmpty) return base;
    final me = base.first;
    return [
      RiderPosition(
        rider: me.rider,
        latitude: fix.point.latitude,
        longitude: fix.point.longitude,
        speedKmh: fix.speedKmh,
        headingDegrees: me.headingDegrees,
        batteryPercent: me.batteryPercent,
        ageSeconds: 0,
      ),
      ...base.skip(1),
    ];
  }

  void _openConvoy() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConvoyScreen(riders: _effectivePositions()),
      ),
    );
  }

  Marker _buildRiderMarker(
    BuildContext context, {
    required LatLng point,
    required String label,
    required String tooltip,
    required Color dotColor,
    required Color pillColor,
    required Color labelColor,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Marker(
      point: point,
      width: 108,
      height: 58,
      child: Tooltip(
        message: tooltip,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: pillColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: labelColor,
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
    );
  }

  List<Marker> _buildMarkers(
    BuildContext context,
    List<RiderPosition> positions,
    bool hasActiveRide,
  ) {
    final colors = Theme.of(context).colorScheme;
    final markers = <Marker>[];

    if (hasActiveRide) {
      markers.addAll([
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
      ]);

      // Skip the first mock rider if live GPS is active (replaced by "You").
      final peerRiders = _myFix == null ? positions : positions.skip(1);
      for (final position in peerRiders) {
        final dotColor = position.isStale ? colors.tertiary : colors.secondary;
        markers.add(
          _buildRiderMarker(
            context,
            point: position.point,
            label: position.rider.name,
            tooltip:
                '${position.rider.name} · ${position.speedKmh.round()} km/h',
            dotColor: dotColor,
            pillColor: colors.surfaceContainerLow,
            labelColor: position.isStale ? colors.tertiary : colors.onSurface,
          ),
        );
      }
    }

    final fix = _myFix;
    if (fix != null) {
      markers.add(
        _buildRiderMarker(
          context,
          point: fix.point,
          label: 'You',
          tooltip: 'You · ${fix.speedKmh.round()} km/h',
          dotColor: colors.primary,
          pillColor: colors.primary,
          labelColor: colors.onPrimary,
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
    final positions = _effectivePositions();
    final showPermissionBanner =
        !_bannerDismissed &&
        (_locationStatus == LocationStatus.denied ||
            _locationStatus == LocationStatus.deniedForever ||
            _locationStatus == LocationStatus.serviceDisabled);

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: const LatLng(kMapCenterLat, kMapCenterLng),
            initialZoom: 14, // 1 = world, 14 = street level
            minZoom: 3,
            maxZoom: 18,
            backgroundColor: isDark
                ? const Color(0xFF0C0C0C)
                : const Color(0xFFF2F3F0),
            cameraConstraint: const CameraConstraint.containLatitude(),
            // Keep north-up so pre-rendered street names don't spin upside
            // down from an accidental two-finger twist.
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onMapReady: () {
              _isMapReady = true;
              final myPoint = _myFix?.point;
              if (_followMe && myPoint != null) {
                _hasInitialGpsCenter = true;
                _mapController.move(myPoint, 16);
              }
            },
            onPositionChanged: (_, hasGesture) {
              if (hasGesture && _followMe) {
                setState(() {
                  _followMe = false;
                });
              }
            },
          ),
          children: [
            // OpenFreeMap vector map (falls back to OpenStreetMap if offline).
            OpenFreeMapLayer(isDark: isDark),
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
            MarkerLayer(
              markers: _buildMarkers(context, positions, ride != null),
            ),
          ],
        ),

        // Top floating destination card, permission banner, speed pill, and buttons.
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MapTopCard(activeRide: ride, onTapIdle: widget.onHostRide),
                if (showPermissionBanner) ...[
                  const SizedBox(height: 8),
                  _LocationBanner(
                    status: _locationStatus,
                    onAction: _handlePermissionAction,
                    onDismiss: () {
                      setState(() {
                        _bannerDismissed = true;
                      });
                    },
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _SpeedPill(speedKmh: _myFix?.speedKmh),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _MapActionButton(
                          icon: _followMe
                              ? Icons.my_location
                              : Icons.location_searching,
                          iconColor: _followMe
                              ? colors.primary
                              : colors.onSurfaceVariant,
                          tooltip: 'Recenter map',
                          onPressed: _recenterMap,
                        ),
                        const SizedBox(height: 8),
                        _MapActionButton(
                          icon: Icons.add,
                          iconColor: colors.onSurface,
                          tooltip: 'Zoom in',
                          onPressed: () => _zoomBy(1),
                        ),
                        const SizedBox(height: 8),
                        _MapActionButton(
                          icon: Icons.remove,
                          iconColor: colors.onSurface,
                          tooltip: 'Zoom out',
                          onPressed: () => _zoomBy(-1),
                        ),
                        if (ride != null) ...[
                          const SizedBox(height: 8),
                          _MapActionButton(
                            icon: Icons.people_outline,
                            iconColor: colors.primary,
                            tooltip: 'Convoy riders',
                            onPressed: _openConvoy,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Bottom attribution chip + sheet with "Group ride" status & actions.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Kept above the bottom sheet on the left so credits never overlap
              // right-side map controls on compact screens.
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: const _MapAttributionChip(),
                ),
              ),
              _MapBottomSheet(
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
            ],
          ),
        ),
      ],
    );
  }
}

// Compact map credit pill shown above the bottom sheet for license compliance.
class _MapAttributionChip extends StatelessWidget {
  const _MapAttributionChip();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Tooltip(
      message: 'OpenFreeMap · OpenMapTiles · OpenStreetMap contributors',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Text(
          '© OpenFreeMap · OSM',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// Shows GPS speed in km/h when a fix is available.
class _SpeedPill extends StatelessWidget {
  const _SpeedPill({required this.speedKmh});

  final double? speedKmh;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final speedText = speedKmh == null ? '--' : '${speedKmh!.round()}';

    return Material(
      color: colors.surfaceContainerLow,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.speed, size: 18, color: colors.primary),
              const SizedBox(width: 6),
              Text(
                speedText,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'km/h',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Shown when location permission is denied or GPS is turned off.
class _LocationBanner extends StatelessWidget {
  const _LocationBanner({
    required this.status,
    required this.onAction,
    required this.onDismiss,
  });

  final LocationStatus status;
  final VoidCallback onAction;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (message, actionLabel) = switch (status) {
      LocationStatus.denied => ('Location permission denied', 'Allow'),
      LocationStatus.deniedForever => (
        'Location blocked in settings',
        'Settings',
      ),
      LocationStatus.serviceDisabled => ('GPS is turned off', 'Turn on'),
      _ => ('', ''),
    };

    return Material(
      color: colors.surfaceContainerLow,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.tertiary),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(
          children: [
            Icon(Icons.location_off, size: 18, color: colors.tertiary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(onPressed: onAction, child: Text(actionLabel)),
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 18),
              visualDensity: VisualDensity.compact,
              tooltip: 'Dismiss',
            ),
          ],
        ),
      ),
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
    required this.iconColor,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final Color iconColor;
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
            child: Icon(icon, size: 20, color: iconColor),
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
              // Drag handle — tap or swipe vertically to collapse or expand.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onToggleCollapse,
                onVerticalDragEnd: (details) {
                  final velocity = details.primaryVelocity;
                  if (velocity == null) return;
                  if (velocity > 100 && !isCollapsed) {
                    onToggleCollapse();
                  } else if (velocity < -100 && isCollapsed) {
                    onToggleCollapse();
                  }
                },
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
                      children: [
                        Expanded(
                          child: Text(
                            ride == null ? 'Ready to ride' : 'Group ride',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
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

// "Live sync" (or "Idle") pill shown at the top-right of the bottom sheet.
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
