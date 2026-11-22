import 'dart:convert';

import 'package:ridesync/services/map_search_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Saves simple rider settings (display name, backend URL, and recent searches)
// locally on the phone.
class AppPreferences {
  static const String _serverUrlKey = 'server_url';
  static const String _riderNameKey = 'rider_name';
  static const String _recentPlacesKey = 'recent_places';
  static const int _maxRecentPlaces = 8;

  // Injected at build time via `--dart-define=API_BASE_URL=...`
  // or `--dart-define-from-file=.env`. Empty when not provided.
  static const String buildApiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const String defaultRiderName = 'Nawaf';

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
}
