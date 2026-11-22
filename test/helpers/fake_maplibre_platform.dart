import 'package:flutter/widgets.dart';
// ignore: depend_on_referenced_packages
import 'package:maplibre_platform_interface/maplibre_platform_interface.dart';

// Lightweight in-memory MapLibre platform used in Flutter widget tests.
class FakeMapLibrePlatform extends MapLibrePlatform {
  FakeMapLibreMapState? latestState;

  static FakeMapLibrePlatform register() {
    final platform = FakeMapLibrePlatform();
    MapLibrePlatform.instance = platform;
    return platform;
  }

  @override
  MapLibreMapState createWidgetState() {
    final state = FakeMapLibreMapState();
    latestState = state;
    return state;
  }
}

class FakeMapLibreMapState extends MapLibreMapState {
  @override
  StyleController? get style => null;

  CameraPosition _buildInitialCamera() {
    final init = initialCamera;
    if (init is CameraUpdatePosition) {
      return CameraPosition(
        center: init.center ?? const Geographic(lon: 0, lat: 0),
        zoom: (init.zoom ?? 0).clamp(options.minZoom, options.maxZoom),
        bearing: init.bearing ?? 0,
        pitch: (init.pitch ?? 0).clamp(options.minPitch, options.maxPitch),
      );
    }
    return CameraPosition(
      center: const Geographic(lon: 0, lat: 0),
      zoom: options.minZoom,
      bearing: 0,
      pitch: options.minPitch,
    );
  }

  @override
  void initState() {
    super.initState();
    camera = _buildInitialCamera();
    isInitialized = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        effectiveWidget.onMapCreated?.call(this);
      }
    });
  }

  @override
  Widget buildPlatformWidget(BuildContext context) {
    return const SizedBox.expand();
  }

  CameraPosition _applyUpdate(CameraUpdate update) {
    final current = camera ?? _buildInitialCamera();
    if (update is CameraUpdatePosition) {
      return CameraPosition(
        center: update.center ?? current.center,
        zoom: (update.zoom ?? current.zoom).clamp(
          options.minZoom,
          options.maxZoom,
        ),
        bearing: update.bearing ?? current.bearing,
        pitch: (update.pitch ?? current.pitch).clamp(
          options.minPitch,
          options.maxPitch,
        ),
      );
    }
    if (update is CameraUpdateFit) {
      final box = update.bounds;
      final center = Geographic(
        lon: (box.west + box.east) / 2,
        lat: (box.south + box.north) / 2,
      );
      final targetZoom = (update.maxZoom ?? current.zoom).clamp(
        options.minZoom,
        options.maxZoom,
      );
      return CameraPosition(
        center: center,
        zoom: targetZoom,
        bearing: update.bearing ?? current.bearing,
        pitch: (update.pitch ?? current.pitch).clamp(
          options.minPitch,
          options.maxPitch,
        ),
      );
    }
    return current;
  }

  // Simulates a user rotating or tilting the map with gestures during tests.
  void simulateGestureCamera({
    Geographic? center,
    double? zoom,
    double? bearing,
    double? pitch,
  }) {
    final current = camera ?? _buildInitialCamera();
    final next = CameraPosition(
      center: center ?? current.center,
      zoom: (zoom ?? current.zoom).clamp(options.minZoom, options.maxZoom),
      bearing: bearing ?? current.bearing,
      pitch: (pitch ?? current.pitch).clamp(options.minPitch, options.maxPitch),
    );
    effectiveWidget.onCameraMoveStart?.call(
      const MapEventCameraMoveStart(reason: CameraChangeReason.gesture),
    );
    setState(() {
      camera = next;
    });
    effectiveWidget.onCameraMove?.call(
      MapEventCameraMove(camera: next, reason: CameraChangeReason.gesture),
    );
    effectiveWidget.onCameraMoveEnd?.call(
      MapEventCameraMoveEnd(camera: next, reason: CameraChangeReason.gesture),
    );
  }

  @override
  Future<void> moveCamera(CameraUpdate update) async {
    final next = _applyUpdate(update);
    if (mounted) {
      setState(() => camera = next);
    } else {
      camera = next;
    }
    effectiveWidget.onCameraMove?.call(
      MapEventCameraMove(camera: next, reason: CameraChangeReason.programmatic),
    );
    effectiveWidget.onCameraMoveEnd?.call(
      MapEventCameraMoveEnd(
        camera: next,
        reason: CameraChangeReason.programmatic,
      ),
    );
  }

  @override
  Future<CameraAnimationResult> animateCamera(
    CameraUpdate update, {
    CameraAnimation animation = const CameraAnimation.ease(),
  }) async {
    await moveCamera(update);
    return CameraAnimationResult.completed;
  }

  @override
  Future<void> stopCamera() async {}

  @override
  Future<CameraPosition> cameraFor(CameraUpdate update) async =>
      _applyUpdate(update);

  @override
  CameraPosition getCamera() => camera ?? _buildInitialCamera();

  @override
  Offset toScreenLocation(Geographic lngLat) => const Offset(180, 320);

  @override
  List<Offset> toScreenLocations(List<Geographic> lngLats) =>
      lngLats.map(toScreenLocation).toList(growable: false);

  @override
  Geographic toLngLat(Offset screenLocation) =>
      camera?.center ?? const Geographic(lon: 0, lat: 0);

  @override
  List<Geographic> toLngLats(List<Offset> screenLocations) =>
      screenLocations.map(toLngLat).toList(growable: false);

  @override
  double getMetersPerPixelAtLatitude(double latitude) => 1.0;

  @override
  GeoBox getVisibleBounds() {
    final c = camera?.center ?? const Geographic(lon: 0, lat: 0);
    return GeoBox(
      west: c.lon - 0.1,
      south: c.lat - 0.1,
      east: c.lon + 0.1,
      north: c.lat + 0.1,
    );
  }

  @override
  Future<List<RenderedFeature>> queryRenderedFeatures(
    QueryGeometry geometry, {
    List<String>? layerIds,
    Expression<bool>? filter,
  }) async => const [];

  @override
  Future<List<SourceFeature>> querySourceFeatures(
    String sourceId, {
    String? sourceLayer,
    Expression<bool>? filter,
  }) async => const [];

  @override
  Future<double> getClusterExpansionZoom(
    String sourceId,
    int clusterId,
  ) async => 0;

  @override
  Future<List<SourceFeature>> getClusterChildren(
    String sourceId,
    int clusterId,
  ) async => const [];

  @override
  Future<List<SourceFeature>> getClusterLeaves(
    String sourceId,
    int clusterId, {
    int limit = 10,
    int offset = 0,
  }) async => const [];
}
