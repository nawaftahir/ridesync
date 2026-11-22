import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

// One searched or tapped destination on the map.
class PlaceResult {
  const PlaceResult({
    required this.name,
    required this.subtitle,
    required this.point,
  });

  final String name;
  final String subtitle;
  final LatLng point;

  String get displayName => subtitle.isEmpty ? name : '$name, $subtitle';
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

// Free OpenStreetMap place search (Photon) and road routing (OSRM).
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
    final clean = query.trim();
    if (clean.length < 2) return const [];

    final params = <String, String>{'q': clean, 'limit': '6'};
    if (near != null) {
      params['lat'] = near.latitude.toStringAsFixed(5);
      params['lon'] = near.longitude.toStringAsFixed(5);
    }

    final uri = Uri.https('photon.komoot.io', '/api/', params);
    try {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(timeout);
      if (response.statusCode != 200) return const [];
      return _parsePhotonFeatures(response.body);
    } on TimeoutException {
      return const [];
    } on SocketException {
      return const [];
    } on http.ClientException {
      return const [];
    } on FormatException {
      return const [];
    }
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

      results.add(PlaceResult(name: name, subtitle: subtitle, point: point));
    }
    return results;
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
