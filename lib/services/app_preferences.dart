import 'dart:convert';

import 'package:ridesync/models/active_ride.dart';
import 'package:ridesync/models/riding_crew.dart';
import 'package:ridesync/services/map_search_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Saves simple rider settings (display name, backend URL, recent searches,
// riding crews, and active ride state) locally on the phone.
class AppPreferences {
  static const String _serverUrlKey = 'server_url';
  static const String _riderNameKey = 'rider_name';
  static const String _recentPlacesKey = 'recent_places';
  static const String _activeRideKey = 'active_ride';
  static const String _crewsKey = 'riding_crews';
  static const int _maxRecentPlaces = 8;

  // Injected at build time via `--dart-define=API_BASE_URL=...`
  // or `--dart-define-from-file=.env`. Empty when not provided.
  static const String buildApiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const String defaultRiderName = 'Rider';

  Future<String?> loadServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_serverUrlKey);
  }

  Future<void> saveServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverUrlKey, url.trim());
  }

  Future<String?> loadRiderName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_riderNameKey);
  }

  Future<void> saveRiderName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_riderNameKey, name.trim());
  }

  Future<List<PlaceResult>> loadRecentPlaces() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_recentPlacesKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final results = <PlaceResult>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final parsed = PlaceResult.fromJson(item);
          if (parsed != null) results.add(parsed);
        }
      }
      return results;
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveRecentPlace(PlaceResult place) async {
    try {
      final existing = await loadRecentPlaces();
      final key = '${place.name.toLowerCase()}|${place.subtitle.toLowerCase()}';
      final updated = <PlaceResult>[
        place,
        ...existing.where(
          (item) =>
              '${item.name.toLowerCase()}|${item.subtitle.toLowerCase()}' !=
              key,
        ),
      ].take(_maxRecentPlaces).toList(growable: false);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _recentPlacesKey,
        jsonEncode(updated.map((p) => p.toJson()).toList(growable: false)),
      );
    } catch (_) {
      // Ignore storage failures on unsupported platforms / headless tests.
    }
  }

  Future<void> clearRecentPlaces() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_recentPlacesKey);
    } catch (_) {
      // Ignore storage failures.
    }
  }

  Future<ActiveRide?> loadActiveRide() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_activeRideKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return ActiveRide.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveActiveRide(ActiveRide ride) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_activeRideKey, jsonEncode(ride.toJson()));
    } catch (_) {
      // Ignore storage failures on unsupported platforms / headless tests.
    }
  }

  Future<void> clearActiveRide() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_activeRideKey);
    } catch (_) {
      // Ignore storage failures.
    }
  }

  Future<List<RidingCrew>> loadCrews() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_crewsKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final crews = <RidingCrew>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final parsed = RidingCrew.fromJson(item);
          if (parsed != null) crews.add(parsed);
        }
      }
      return crews;
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveCrews(List<RidingCrew> crews) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _crewsKey,
        jsonEncode(crews.map((c) => c.toJson()).toList(growable: false)),
      );
    } catch (_) {
      // Ignore storage failures.
    }
  }
}
