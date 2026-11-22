import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

// One searched, recent, or tapped destination on the map.
class PlaceResult {
  const PlaceResult({
    required this.name,
    required this.subtitle,
    required this.point,
    this.category,
  });

  final String name;
  final String subtitle;
  final LatLng point;
  final String? category;

  String get displayName => subtitle.isEmpty ? name : '$name, $subtitle';

  Map<String, dynamic> toJson() => {
    'name': name,
    'subtitle': subtitle,
    'lat': point.latitude,
    'lng': point.longitude,
    if (category != null) 'category': category,
  };

  static PlaceResult? fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final lat = json['lat'];
    final lng = json['lng'];
    if (name is! String || name.trim().isEmpty || lat is! num || lng is! num) {
      return null;
    }
    return PlaceResult(
      name: name.trim(),
      subtitle: (json['subtitle'] as String?)?.trim() ?? '',
      point: LatLng(lat.toDouble(), lng.toDouble()),
      category: (json['category'] as String?)?.trim(),
    );
  }
}

// Result of a place search, distinguishing "no matches" from offline/network errors.
class PlaceSearchOutcome {
  const PlaceSearchOutcome({
    required this.results,
    this.errorMessage,
    this.usedFallback = false,
  });

  final List<PlaceResult> results;
  final String? errorMessage;
  final bool usedFallback;

  bool get hasError => errorMessage != null;
}

// Road route polyline + distance/ETA returned by OSRM (or straight-line fallback).
class RoutePreview {
  const RoutePreview({
    required this.points,
    required this.distanceKm,
    required this.durationMinutes,
    this.isFallback = false,
  });

  final List<LatLng> points;
  final double distanceKm;
  final int durationMinutes;
  final bool isFallback;
}

// Formats straight-line distance from rider to a place (e.g. "450 m", "2.4 km").
String formatPlaceDistance(LatLng from, LatLng to) {
  final meters = const Distance().as(LengthUnit.Meter, from, to);
  if (meters < 1000) {
    final rounded = ((meters / 10).round() * 10).clamp(10, 990);
    return '$rounded m';
  }
  final km = meters / 1000.0;
  if (km < 10) {
    return '${km.toStringAsFixed(1)} km';
  }
  return '${km.round()} km';
}

// Free OpenStreetMap place search (Photon + Nominatim fallback) and OSRM routing.
// No API keys needed.
class MapSearchService {
  MapSearchService({
    http.Client? client,
    this.timeout = const Duration(seconds: 6),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  static const _headers = {'User-Agent': 'RideSync/1.0 (Flutter)'};

  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;

  // Searches real places worldwide, preferring results near `near` when available.
  Future<List<PlaceResult>> searchPlaces(String query, {LatLng? near}) async {
    final outcome = await searchPlacesOutcome(query, near: near);
    return outcome.results;
  }

  // Searches Photon first and falls back to OSM Nominatim when Photon returns
  // empty results (common for local sectors, petrol pumps, and smaller landmarks).
  Future<PlaceSearchOutcome> searchPlacesOutcome(
    String query, {
    LatLng? near,
  }) async {
    final clean = query.trim();
    if (clean.length < 2) {
      return const PlaceSearchOutcome(results: []);
    }

    final photon = await _searchPhoton(clean, near: near);
    if (photon.results.isNotEmpty) {
      return PlaceSearchOutcome(
        results: _sortNearbyIfClose(photon.results, near),
      );
    }

    final nominatim = await _searchNominatim(clean, near: near);
    if (nominatim.results.isNotEmpty) {
      return PlaceSearchOutcome(
        results: _sortNearbyIfClose(nominatim.results, near),
        usedFallback: true,
      );
    }

    if (photon.failed && nominatim.failed) {
      return const PlaceSearchOutcome(
        results: [],
        errorMessage:
            'Could not reach place search. Check your internet connection.',
      );
    }

    return const PlaceSearchOutcome(results: []);
  }

  Future<({List<PlaceResult> results, bool failed})> _searchPhoton(
    String query, {
    LatLng? near,
  }) async {
    final params = <String, String>{'q': query, 'limit': '8', 'lang': 'en'};
    if (near != null) {
      params['lat'] = near.latitude.toStringAsFixed(5);
      params['lon'] = near.longitude.toStringAsFixed(5);
    }

    final uri = Uri.https('photon.komoot.io', '/api/', params);
    try {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(timeout);
      if (response.statusCode != 200) {
        return (results: const <PlaceResult>[], failed: true);
      }
      return (results: _parsePhotonFeatures(response.body), failed: false);
    } on TimeoutException {
      return (results: const <PlaceResult>[], failed: true);
    } on SocketException {
      return (results: const <PlaceResult>[], failed: true);
    } on http.ClientException {
      return (results: const <PlaceResult>[], failed: true);
    } on FormatException {
      return (results: const <PlaceResult>[], failed: true);
    }
  }

  Future<({List<PlaceResult> results, bool failed})> _searchNominatim(
    String query, {
    LatLng? near,
  }) async {
    final params = <String, String>{
      'q': query,
      'format': 'jsonv2',
      'addressdetails': '1',
      'limit': '8',
      'accept-language': 'en',
    };
    if (near != null) {
      // Bias results toward a ~60km box around the rider without hard-blocking
      // searches for far-away cities.
      const delta = 0.55;
      final left = (near.longitude - delta).toStringAsFixed(4);
      final right = (near.longitude + delta).toStringAsFixed(4);
      final top = (near.latitude + delta).toStringAsFixed(4);
      final bottom = (near.latitude - delta).toStringAsFixed(4);
      params['viewbox'] = '$left,$top,$right,$bottom';
    }

    final uri = Uri.https('nominatim.openstreetmap.org', '/search', params);
    try {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(timeout);
      if (response.statusCode != 200) {
        return (results: const <PlaceResult>[], failed: true);
      }
      return (results: _parseNominatimResults(response.body), failed: false);
    } on TimeoutException {
      return (results: const <PlaceResult>[], failed: true);
    } on SocketException {
      return (results: const <PlaceResult>[], failed: true);
    } on http.ClientException {
      return (results: const <PlaceResult>[], failed: true);
    } on FormatException {
      return (results: const <PlaceResult>[], failed: true);
    }
  }

  List<PlaceResult> _sortNearbyIfClose(
    List<PlaceResult> results,
    LatLng? near,
  ) {
    if (near == null || results.length <= 1) return results;
    const distance = Distance();
    final sorted = List<PlaceResult>.of(results);
    // Keep nearby hits (< 100 km) sorted by distance ahead of distant matches.
    sorted.sort((a, b) {
      final da = distance.as(LengthUnit.Meter, near, a.point);
      final db = distance.as(LengthUnit.Meter, near, b.point);
      final aLocal = da <= 100000;
      final bLocal = db <= 100000;
      if (aLocal && !bLocal) return -1;
      if (!aLocal && bLocal) return 1;
      if (aLocal && bLocal) return da.compareTo(db);
      return 0;
    });
    return sorted;
  }

  // Turns a tapped map coordinate into a readable place name.
  Future<PlaceResult> reverseGeocode(LatLng point) async {
    final fallback = PlaceResult(
      name: 'Pinned spot',
      subtitle:
          '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}',
      point: point,
    );

    final uri = Uri.https('photon.komoot.io', '/reverse', {
      'lat': point.latitude.toStringAsFixed(6),
      'lon': point.longitude.toStringAsFixed(6),
      'lang': 'en',
    });
    try {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(timeout);
      if (response.statusCode != 200) return fallback;
      final results = _parsePhotonFeatures(response.body, overridePoint: point);
      return results.isEmpty ? fallback : results.first;
    } catch (_) {
      return fallback;
    }
  }

  // Fetches the driving road polyline, distance, and ETA between two points.
  // Falls back to a straight line if OSRM is unreachable so the destination still shows.
  Future<RoutePreview> fetchRoute({
    required LatLng from,
    required LatLng to,
  }) async {
    final path =
        '/route/v1/driving/'
        '${from.longitude},${from.latitude};${to.longitude},${to.latitude}';
    final uri = Uri.https('router.project-osrm.org', path, {
      'overview': 'full',
      'geometries': 'geojson',
    });

    try {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(timeout);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final routes = decoded['routes'];
          if (routes is List && routes.isNotEmpty) {
            final route = routes.first as Map<String, dynamic>;
            final geometry = route['geometry'] as Map<String, dynamic>?;
            final coords =
                geometry?['coordinates'] as List<dynamic>? ?? const [];
            final points = <LatLng>[];
            for (final pair in coords) {
              if (pair is List && pair.length >= 2) {
                points.add(
                  LatLng(
                    (pair[1] as num).toDouble(),
                    (pair[0] as num).toDouble(),
                  ),
                );
              }
            }
            if (points.length >= 2) {
              final meters = ((route['distance'] as num?) ?? 0).toDouble();
              final seconds = ((route['duration'] as num?) ?? 0).toDouble();
              final distanceKm = double.parse(
                (meters / 1000.0).toStringAsFixed(1),
              );
              final minutes = (seconds / 60.0).round().clamp(1, 9999);
              return RoutePreview(
                points: points,
                distanceKm: distanceKm,
                durationMinutes: minutes,
              );
            }
          }
        }
      }
    } catch (_) {
      // Fall through to straight-line estimate below.
    }

    return _straightLineFallback(from: from, to: to);
  }

  RoutePreview _straightLineFallback({
    required LatLng from,
    required LatLng to,
  }) {
    final meters = const Distance().as(LengthUnit.Meter, from, to);
    final km = double.parse((meters / 1000.0).toStringAsFixed(1));
    // Rough 40 km/h urban motorcycle speed estimate when routing is offline.
    final minutes = ((km / 40.0) * 60.0).round().clamp(1, 9999);
    return RoutePreview(
      points: [from, to],
      distanceKm: km,
      durationMinutes: minutes,
      isFallback: true,
    );
  }

  List<PlaceResult> _parsePhotonFeatures(
    String rawBody, {
    LatLng? overridePoint,
  }) {
    final decoded = jsonDecode(rawBody);
    if (decoded is! Map<String, dynamic>) return const [];
    final features = decoded['features'];
    if (features is! List) return const [];

    final results = <PlaceResult>[];
    final seenLabels = <String>{};

    for (final item in features) {
      if (item is! Map<String, dynamic>) continue;
      final geometry = item['geometry'];
      final props = item['properties'];
      if (geometry is! Map<String, dynamic> || props is! Map<String, dynamic>) {
        continue;
      }
      final coords = geometry['coordinates'];
      if (coords is! List || coords.length < 2) continue;

      final point =
          overridePoint ??
          LatLng((coords[1] as num).toDouble(), (coords[0] as num).toDouble());

      final name = _firstNonEmpty([
        props['name'],
        props['street'],
        props['district'],
        props['city'],
      ]);
      if (name == null) continue;

      final subtitleParts = <String>[];
      for (final raw in [
        props['street'],
        props['district'],
        props['city'],
        props['state'],
        props['country'],
      ]) {
        final text = raw is String ? raw.trim() : '';
        if (text.isEmpty || text == name || subtitleParts.contains(text)) {
          continue;
        }
        subtitleParts.add(text);
        if (subtitleParts.length == 2) break;
      }

      final subtitle = subtitleParts.join(', ');
      final key = '${name.toLowerCase()}|${subtitle.toLowerCase()}';
      if (!seenLabels.add(key)) continue;

      final category = _normalizeCategory(
        props['osm_value'] as String?,
        props['osm_key'] as String?,
      );

      results.add(
        PlaceResult(
          name: name,
          subtitle: subtitle,
          point: point,
          category: category,
        ),
      );
    }
    return results;
  }

  List<PlaceResult> _parseNominatimResults(String rawBody) {
    final decoded = jsonDecode(rawBody);
    if (decoded is! List) return const [];

    final results = <PlaceResult>[];
    final seenLabels = <String>{};

    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      final lat = double.tryParse('${item['lat']}');
      final lon = double.tryParse('${item['lon']}');
      if (lat == null || lon == null) continue;

      final displayName = (item['display_name'] as String?)?.trim() ?? '';
      final address = item['address'] is Map<String, dynamic>
          ? item['address'] as Map<String, dynamic>
          : const <String, dynamic>{};

      final name = _firstNonEmpty([
        item['name'],
        displayName.contains(',')
            ? displayName.substring(0, displayName.indexOf(','))
            : displayName,
      ]);
      if (name == null) continue;

      final subtitleParts = <String>[];
      for (final raw in [
        address['road'],
        address['suburb'],
        address['neighbourhood'],
        address['city'],
        address['town'],
        address['state'],
        address['country'],
      ]) {
        final text = raw is String ? raw.trim() : '';
        if (text.isEmpty || text == name || subtitleParts.contains(text)) {
          continue;
        }
        subtitleParts.add(text);
        if (subtitleParts.length == 2) break;
      }
      if (subtitleParts.isEmpty && displayName.contains(',')) {
        final rest = displayName
            .split(',')
            .skip(1)
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .take(2);
        subtitleParts.addAll(rest);
      }

      final subtitle = subtitleParts.join(', ');
      final key = '${name.toLowerCase()}|${subtitle.toLowerCase()}';
      if (!seenLabels.add(key)) continue;

      final category = _normalizeCategory(
        item['type'] as String?,
        item['category'] as String?,
      );

      results.add(
        PlaceResult(
          name: name,
          subtitle: subtitle,
          point: LatLng(lat, lon),
          category: category,
        ),
      );
    }
    return results;
  }

  String? _normalizeCategory(String? value, String? key) {
    final v = (value ?? '').toLowerCase();
    final k = (key ?? '').toLowerCase();
    if (v == 'fuel' || v == 'charging_station') return 'fuel';
    if (v == 'cafe' || v == 'coffee_shop') return 'cafe';
    if (v == 'restaurant' || v == 'fast_food' || v == 'food_court') {
      return 'food';
    }
    if (v == 'motorcycle' || v == 'car_repair' || v == 'motorcycle_repair') {
      return 'mechanic';
    }
    if (v == 'hospital' || v == 'clinic' || v == 'pharmacy') {
      return 'hospital';
    }
    if (v == 'viewpoint' || v == 'peak' || v == 'park' || k == 'tourism') {
      return 'viewpoint';
    }
    return null;
  }

  String? _firstNonEmpty(List<Object?> values) {
    for (final value in values) {
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
