import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:ridesync/models/active_ride.dart';
import 'package:ridesync/models/rider.dart';
import 'package:ridesync/models/rider_position.dart';
import 'package:ridesync/screens/convoy_screen.dart';
import 'package:ridesync/services/location_service.dart';
import 'package:ridesync/services/map_search_service.dart';
import 'package:ridesync/services/ride_api_service.dart';
import 'package:ridesync/utils/ride_share.dart';
import 'package:ridesync/widgets/open_free_map_layer.dart';
import 'package:ridesync/widgets/place_search_sheet.dart';

// Initial map camera position shown only before the device gets its first GPS lock.
const LatLng _kDefaultMapCenter = LatLng(33.7215, 73.0433);

class RideMapScreen extends StatefulWidget {
  const RideMapScreen({
    super.key,
    required this.activeRide,
    required this.onEndRide,
    required this.onHostRide,
    required this.onJoinRide,
    this.onHostRideWithPlace,
    this.locationService = const LocationService(),
    this.apiService,
    this.searchService,
    this.onRidersUpdated,
    this.onShareOverride,
  });

  final ActiveRide? activeRide;
  final VoidCallback onEndRide;
  final VoidCallback onHostRide;
  final VoidCallback onJoinRide;
  final void Function(PlaceResult place, RoutePreview? route, LatLng? near)?
  onHostRideWithPlace;
  final LocationService locationService;
  final RideApiService? apiService;
  final MapSearchService? searchService;
  final ValueChanged<List<RiderPosition>>? onRidersUpdated;
  final RideShareHandler? onShareOverride;

  @override
  State<RideMapScreen> createState() => _RideMapScreenState();
}

class _RideMapScreenState extends State<RideMapScreen>
    with WidgetsBindingObserver {
  final MapController _mapController = MapController();

  StreamSubscription<GpsFix>? _positionSub;
  StreamSubscription<bool>? _serviceStatusSub;
  Timer? _syncTimer;
  LocationStatus _locationStatus = LocationStatus.checking;
  GpsFix? _myFix;
  List<RiderPosition> _liveRiders = const [];
  DateTime? _lastPositionSentAt;
  bool _isSendingPosition = false;
  bool _isFetchingPositions = false;
  bool _followMe = true;
  bool _isMapReady = false;
  bool _hasInitialGpsCenter = false;
  bool _isSheetCollapsed = false;
  bool _bannerDismissed = false;

  // Map search, tap-to-pin, and real road route state.
  PlaceResult? _previewPlace;
  RoutePreview? _previewRoute;
  RoutePreview? _activeRoute;
  LatLng? _remoteDestPoint;
  LatLng? _lastRoutedOrigin;
  int _routeRequestId = 0;
  bool _isLoadingRoute = false;
  bool _isPickingOnMap = false;

  bool get _isLiveBackendRide =>
      widget.apiService?.isEnabled == true &&
      widget.activeRide?.currentUserId != null;

  LatLng? get _activeDestPoint =>
      widget.activeRide?.destinationPoint ?? _remoteDestPoint;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenServiceStatus();
    _startLocationTracking();
    if (_isLiveBackendRide) {
      _startBackendSync();
    }
    if (widget.activeRide != null) {
      _refreshActiveRideRoute(force: true);
    }
  }

  @override
  void didUpdateWidget(covariant RideMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final rideChanged =
        oldWidget.activeRide?.joinCode != widget.activeRide?.joinCode ||
        oldWidget.activeRide?.currentUserId !=
            widget.activeRide?.currentUserId ||
        oldWidget.apiService != widget.apiService;
    if (!rideChanged) return;

    _stopBackendSync();
    _liveRiders = const [];
    _lastPositionSentAt = null;
    _remoteDestPoint = null;
    _activeRoute = null;
    _lastRoutedOrigin = null;
    if (widget.activeRide != null) {
      _previewPlace = null;
      _previewRoute = null;
      _isPickingOnMap = false;
    }
    if (_isLiveBackendRide) {
      _startBackendSync();
    }
    if (widget.activeRide != null) {
      _refreshActiveRideRoute(force: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSub?.cancel();
    _serviceStatusSub?.cancel();
    _stopBackendSync();
    _mapController.dispose();
    super.dispose();
  }

  void _startBackendSync() {
    _stopBackendSync();
    _refreshRemotePositions();
    if (_myFix != null) {
      _sendPositionIfNeeded(_myFix!);
    }
    _syncTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _refreshRemotePositions(),
    );
  }

  void _stopBackendSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  Future<void> _sendPositionIfNeeded(GpsFix fix) async {
    final api = widget.apiService;
    final ride = widget.activeRide;
    final userId = ride?.currentUserId;
    if (api == null || !api.isEnabled || ride == null || userId == null) {
      return;
    }
    if (_isSendingPosition) return;
    final now = DateTime.now();
    if (_lastPositionSentAt != null &&
        now.difference(_lastPositionSentAt!) < const Duration(seconds: 2)) {
      return;
    }

    _isSendingPosition = true;
    _lastPositionSentAt = now;
    try {
      await api.sendPosition(
        code: ride.joinCode,
        userId: userId,
        latitude: fix.point.latitude,
        longitude: fix.point.longitude,
        speedKmh: fix.speedKmh,
      );
    } on RideApiException {
      // Ignore temporary network blips so GPS tracking keeps running smoothly.
    } finally {
      _isSendingPosition = false;
    }
  }

  Future<void> _refreshRemotePositions() async {
    final api = widget.apiService;
    final ride = widget.activeRide;
    if (api == null ||
        !api.isEnabled ||
        ride == null ||
        ride.currentUserId == null ||
        _isFetchingPositions) {
      return;
    }

    _isFetchingPositions = true;
    final code = ride.joinCode;
    try {
      final snapshot = await api.fetchPositions(code);
      if (!mounted || widget.activeRide?.joinCode != code) return;

      if (snapshot.isEnded) {
        _stopBackendSync();
        setState(() {
          _liveRiders = const [];
        });
        widget.onRidersUpdated?.call(const []);
        if (!ride.isHost) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text('Ride $code was ended by the host.')),
          );
          widget.onEndRide();
        }
        return;
      }

      final hadDest = _activeDestPoint != null;
      final incomingDest =
          (snapshot.destLat != null && snapshot.destLng != null)
          ? LatLng(snapshot.destLat!, snapshot.destLng!)
          : null;

      setState(() {
        _liveRiders = snapshot.riders;
        if (incomingDest != null) {
          _remoteDestPoint = incomingDest;
        }
      });
      if (!hadDest && incomingDest != null) {
        _refreshActiveRideRoute(force: true);
      }
      widget.onRidersUpdated?.call(snapshot.riders);
    } on RideApiException {
      // Keep the last known positions on screen if a single poll fails.
    } finally {
      _isFetchingPositions = false;
    }
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
    if (_isLiveBackendRide) {
      _sendPositionIfNeeded(fix);
    }
    if (widget.activeRide != null) {
      _refreshActiveRideRoute();
    }
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
    _mapController.move(_kDefaultMapCenter, 14.0);
  }

  void _zoomBy(double delta) {
    if (!_isMapReady) return;
    final nextZoom = (_mapController.camera.zoom + delta).clamp(3.0, 18.0);
    _mapController.move(_mapController.camera.center, nextZoom);
  }

  Future<void> _openPlaceSearch() async {
    final search = widget.searchService;
    if (search == null) {
      widget.onHostRide();
      return;
    }

    final near =
        _myFix?.point ?? (_isMapReady ? _mapController.camera.center : null);
    final action = await showModalBottomSheet<PlaceSearchAction>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PlaceSearchSheet(
        searchService: search,
        nearPoint: near,
        initialQuery: _previewPlace?.name ?? '',
      ),
    );
    if (!mounted || action == null) return;

    if (action.pickOnMap) {
      setState(() {
        _isPickingOnMap = true;
        _followMe = false;
      });
      return;
    }

    if (action.place != null) {
      await _selectPreviewPlace(action.place!);
    }
  }

  Future<void> _pickPointOnMap(LatLng point) async {
    final search = widget.searchService;
    setState(() {
      _isPickingOnMap = false;
      _followMe = false;
      _previewPlace = PlaceResult(
        name: 'Pinned spot',
        subtitle:
            '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}',
        point: point,
      );
      _previewRoute = null;
      _isLoadingRoute = true;
    });

    final resolved = search == null
        ? _previewPlace!
        : await search.reverseGeocode(point);
    if (!mounted || _previewPlace?.point != point) return;
    await _selectPreviewPlace(resolved);
  }

  Future<void> _selectPreviewPlace(PlaceResult place) async {
    final search = widget.searchService;
    final origin =
        _myFix?.point ??
        (_isMapReady ? _mapController.camera.center : _kDefaultMapCenter);
    final reqId = ++_routeRequestId;

    setState(() {
      _isPickingOnMap = false;
      _followMe = false;
      _previewPlace = place;
      _previewRoute = null;
      _isLoadingRoute = search != null;
    });

    if (_isMapReady) {
      _fitCameraToPoints([origin, place.point]);
    }
    if (search == null) return;

    final route = await search.fetchRoute(from: origin, to: place.point);
    if (!mounted || reqId != _routeRequestId || _previewPlace != place) return;
    setState(() {
      _previewRoute = route;
      _isLoadingRoute = false;
    });
    if (_isMapReady) {
      _fitCameraToPoints(route.points);
    }
  }

  void _clearPreview() {
    _routeRequestId++;
    setState(() {
      _previewPlace = null;
      _previewRoute = null;
      _isLoadingRoute = false;
      _isPickingOnMap = false;
    });
  }

  Future<void> _refreshActiveRideRoute({bool force = false}) async {
    final search = widget.searchService;
    final dest = _activeDestPoint;
    final origin = _myFix?.point;
    if (search == null || dest == null || origin == null) return;

    if (!force && _lastRoutedOrigin != null) {
      final movedMeters = const Distance().as(
        LengthUnit.Meter,
        _lastRoutedOrigin!,
        origin,
      );
      if (movedMeters < 150) return;
    }

    _lastRoutedOrigin = origin;
    final reqId = ++_routeRequestId;
    final code = widget.activeRide?.joinCode;
    final route = await search.fetchRoute(from: origin, to: dest);
    if (!mounted ||
        reqId != _routeRequestId ||
        widget.activeRide?.joinCode != code) {
      return;
    }
    setState(() {
      _activeRoute = route;
    });
  }

  void _fitCameraToPoints(List<LatLng> points) {
    if (!_isMapReady || points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.first, 15.0);
      return;
    }
    final bounds = LatLngBounds.fromPoints(points);
    if (bounds.southWest == bounds.northEast) {
      _mapController.move(points.first, 15.0);
      return;
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.fromLTRB(48, 120, 48, 250),
        maxZoom: 16.0,
      ),
    );
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

  // Combines polled convoy riders with your live local GPS fix.
  List<RiderPosition> _effectivePositions() {
    final ride = widget.activeRide;
    final fix = _myFix;
    if (ride == null) return const [];

    final myId = ride.currentUserId;
    final merged = <RiderPosition>[];
    var foundMe = false;

    for (final pos in _liveRiders) {
      if (myId != null && pos.rider.id == myId && fix != null) {
        foundMe = true;
        merged.add(
          RiderPosition(
            rider: pos.rider,
            latitude: fix.point.latitude,
            longitude: fix.point.longitude,
            speedKmh: fix.speedKmh,
            headingDegrees: pos.headingDegrees,
            batteryPercent: pos.batteryPercent,
            ageSeconds: 0,
          ),
        );
      } else {
        merged.add(pos);
      }
    }

    if (!foundMe && fix != null) {
      merged.insert(
        0,
        RiderPosition(
          rider: Rider(id: myId ?? 0, name: ride.currentUserName),
          latitude: fix.point.latitude,
          longitude: fix.point.longitude,
          speedKmh: fix.speedKmh,
          headingDegrees: 0,
          batteryPercent: null,
          ageSeconds: 0,
        ),
      );
    }
    return merged;
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

  List<LatLng> _currentRoutePoints(ActiveRide? ride) {
    if (ride != null) {
      if (_activeRoute != null && _activeRoute!.points.length >= 2) {
        return _activeRoute!.points;
      }
      return const [];
    }
    if (_previewRoute != null && _previewRoute!.points.length >= 2) {
      return _previewRoute!.points;
    }
    return const [];
  }

  List<Marker> _buildMarkers(
    BuildContext context,
    List<RiderPosition> positions,
    ActiveRide? ride,
    List<LatLng> routePoints,
  ) {
    final colors = Theme.of(context).colorScheme;
    final markers = <Marker>[];

    final LatLng? destinationPin = ride != null
        ? _activeDestPoint
        : _previewPlace?.point;

    if (routePoints.length >= 2 && _myFix == null) {
      markers.add(
        Marker(
          point: routePoints.first,
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
      );
    }

    if (destinationPin != null) {
      markers.add(
        Marker(
          point: destinationPin,
          width: 36,
          height: 36,
          alignment: Alignment.topCenter,
          child: Icon(Icons.location_on, color: colors.primary, size: 36),
        ),
      );
    }

    if (ride != null) {
      // Avoid drawing a duplicate marker for the current rider when "You" is shown.
      final myId = ride.currentUserId;
      final peerRiders = _myFix == null
          ? positions
          : positions.where((p) => p.rider.id != (myId ?? 0));
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
    final routePoints = _currentRoutePoints(ride);
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
            initialCenter: _kDefaultMapCenter,
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
            onTap: (_, point) {
              if (_isPickingOnMap && ride == null) {
                _pickPointOnMap(point);
              }
            },
            onLongPress: (_, point) {
              if (ride == null && widget.searchService != null) {
                _pickPointOnMap(point);
              }
            },
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
            if (routePoints.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: routePoints,
                    strokeWidth: 12,
                    color: colors.primary.withValues(alpha: 0.22),
                  ),
                  Polyline(
                    points: routePoints,
                    strokeWidth: 5,
                    color: colors.primary,
                  ),
                ],
              ),
            MarkerLayer(
              markers: _buildMarkers(context, positions, ride, routePoints),
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
                _MapTopCard(
                  activeRide: ride,
                  previewPlace: _previewPlace,
                  onTapSearch: _openPlaceSearch,
                  onClearPreview: _clearPreview,
                  onCopyCode: ride == null
                      ? null
                      : () => copyRideCode(context, ride.joinCode),
                  onShareRide: ride == null
                      ? null
                      : () => shareRideInvite(
                          code: ride.joinCode,
                          destination: ride.destination,
                          onShareOverride: widget.onShareOverride,
                        ),
                ),
                if (_isPickingOnMap && ride == null) ...[
                  const SizedBox(height: 8),
                  _PickOnMapBanner(
                    onCancel: () {
                      setState(() {
                        _isPickingOnMap = false;
                      });
                    },
                  ),
                ],
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
              if (ride == null && _previewPlace != null)
                _PreviewDestinationCard(
                  place: _previewPlace!,
                  route: _previewRoute,
                  isLoadingRoute: _isLoadingRoute,
                  onHostHere: () {
                    final place = _previewPlace!;
                    final route = _previewRoute;
                    if (widget.onHostRideWithPlace != null) {
                      widget.onHostRideWithPlace!(place, route, _myFix?.point);
                    } else {
                      widget.onHostRide();
                    }
                  },
                  onClose: _clearPreview,
                )
              else
                _MapBottomSheet(
                  activeRide: ride,
                  routePreview: _activeRoute,
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

// Banner shown while the user is tapping the map to pick a destination pin.
class _PickOnMapBanner extends StatelessWidget {
  const _PickOnMapBanner({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.primaryContainer,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(
          children: [
            Icon(Icons.touch_app, size: 18, color: colors.onPrimaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Tap anywhere on the map to set destination',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colors.onPrimaryContainer,
                ),
              ),
            ),
            TextButton(onPressed: onCancel, child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }
}

// Floating top bar showing active destination, searched place, or search prompt.
class _MapTopCard extends StatelessWidget {
  const _MapTopCard({
    required this.activeRide,
    required this.previewPlace,
    required this.onTapSearch,
    required this.onClearPreview,
    this.onCopyCode,
    this.onShareRide,
  });

  final ActiveRide? activeRide;
  final PlaceResult? previewPlace;
  final VoidCallback onTapSearch;
  final VoidCallback onClearPreview;
  final VoidCallback? onCopyCode;
  final VoidCallback? onShareRide;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final ride = activeRide;
    final label =
        ride?.destination ?? previewPlace?.name ?? 'Where are you riding?';
    final isPlaceholder = ride == null && previewPlace == null;

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
        onTap: ride == null ? onTapSearch : null,
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(
                  ride == null ? Icons.search : Icons.navigation_rounded,
                  size: 20,
                  color: isPlaceholder
                      ? colors.onSurfaceVariant
                      : colors.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isPlaceholder
                          ? colors.onSurfaceVariant
                          : colors.onSurface,
                    ),
                  ),
                ),
                if (ride == null && previewPlace != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Clear destination',
                    visualDensity: VisualDensity.compact,
                    onPressed: onClearPreview,
                  ),
                if (ride != null) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Copy ride code',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: onCopyCode,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              ride.joinCode,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                                color: colors.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.copy_rounded,
                              size: 13,
                              color: colors.onPrimaryContainer,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.share_outlined, size: 19),
                    tooltip: 'Share ride code',
                    visualDensity: VisualDensity.compact,
                    onPressed: onShareRide,
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

// Bottom preview sheet shown after searching or pinning a destination before hosting.
class _PreviewDestinationCard extends StatelessWidget {
  const _PreviewDestinationCard({
    required this.place,
    required this.route,
    required this.isLoadingRoute,
    required this.onHostHere,
    required this.onClose,
  });

  final PlaceResult place;
  final RoutePreview? route;
  final bool isLoadingRoute;
  final VoidCallback onHostHere;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Material(
      color: colors.surfaceContainerLow,
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        place.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (place.subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          place.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                  tooltip: 'Close preview',
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (isLoadingRoute)
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Finding road route…',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ],
              )
            else if (route != null)
              Row(
                children: [
                  Icon(Icons.directions_bike, size: 18, color: colors.primary),
                  const SizedBox(width: 6),
                  Text(
                    '${route!.durationMinutes} min · ${route!.distanceKm} km'
                    '${route!.isFallback ? ' (straight-line est.)' : ''}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onHostHere,
              icon: const Icon(Icons.add_road),
              label: const Text('Host Ride Here'),
            ),
          ],
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
    required this.routePreview,
    required this.positions,
    required this.isCollapsed,
    required this.onToggleCollapse,
    required this.onOpenConvoy,
    required this.onEndRide,
    required this.onHostRide,
    required this.onJoinRide,
  });

  final ActiveRide? activeRide;
  final RoutePreview? routePreview;
  final List<RiderPosition> positions;
  final bool isCollapsed;
  final VoidCallback onToggleCollapse;
  final VoidCallback onOpenConvoy;
  final VoidCallback onEndRide;
  final VoidCallback onHostRide;
  final VoidCallback onJoinRide;

  String _riderSummary() {
    if (positions.isEmpty) {
      return 'Waiting for GPS updates…';
    }
    final staleCount = positions.where((p) => p.isStale).length;
    if (staleCount == 0) {
      return positions.length == 1
          ? '1 rider active'
          : 'All ${positions.length} riders active';
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
                              positions.isEmpty
                                  ? 'Convoy'
                                  : positions
                                        .map((p) => p.rider.name)
                                        .join(', '),
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
                _RouteSummaryCard(ride: ride, routePreview: routePreview),
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
                  'Search above, long-press the map to drop a pin, or join with a code.',
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
  const _RouteSummaryCard({required this.ride, this.routePreview});

  final ActiveRide ride;
  final RoutePreview? routePreview;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final minutes = routePreview?.durationMinutes ?? ride.durationMinutes;
    final distanceKm = routePreview?.distanceKm ?? ride.distanceKm;

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
                  minutes == null ? '-- min' : '$minutes min',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                Text(
                  distanceKm == null ? '-- km' : '$distanceKm km',
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
