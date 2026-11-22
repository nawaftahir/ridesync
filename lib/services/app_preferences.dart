import 'package:shared_preferences/shared_preferences.dart';

// Saves simple rider settings (display name and backend URL) on the phone.
class AppPreferences {
  static const String _serverUrlKey = 'server_url';
  static const String _riderNameKey = 'rider_name';

  static const String defaultLiveServerUrl = 'https://ridesync.ddns.net';
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
}
