import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:ridesync/models/active_ride.dart';
import 'package:ridesync/models/rider.dart';
import 'package:ridesync/models/rider_position.dart';

class RideApiException implements Exception {
  const RideApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class BackendHealth {
  const BackendHealth({required this.status, required this.database});

  final String status;
  final String database;

  bool get isDatabaseConnected => database == 'connected';
}

class RideAlert {
  const RideAlert({
    required this.id,
    required this.userId,
    required this.senderName,
    required this.alertType,
    required this.message,
    required this.ageSeconds,
  });

  final int id;
  final int userId;
  final String senderName;
  final String alertType;
  final String message;
  final int ageSeconds;

  String get title => switch (alertType) {
    'fuel' => 'Fuel stop',
    'wait' => 'Wait up',
    'help' => 'Need help',
    _ => 'Convoy alert',
  };
}

class RidePositionsSnapshot {
  const RidePositionsSnapshot({
    required this.code,
    required this.destination,
    this.destLat,
    this.destLng,
    required this.isEnded,
    required this.riders,
    this.latestAlert,
  });

  final String code;
  final String destination;
  final double? destLat;
  final double? destLng;
  final bool isEnded;
  final List<RiderPosition> riders;
  final RideAlert? latestAlert;
}

// Talks to the RideSync FastAPI backend over HTTP.
class RideApiService {
  RideApiService({
    String baseUrl = const String.fromEnvironment('API_BASE_URL'),
    http.Client? client,
    this.timeout = const Duration(seconds: 6),
  }) : cleanBaseUrl = _normalizeBaseUrl(baseUrl),
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  final String cleanBaseUrl;
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;

  bool get isEnabled => cleanBaseUrl.isNotEmpty;

  static String _normalizeBaseUrl(String raw) {
    var trimmed = raw.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (trimmed.isEmpty) return '';
    final parsed = Uri.tryParse(trimmed);
    if (parsed != null &&
        (parsed.scheme == 'http' || parsed.scheme == 'https') &&
        parsed.host.isNotEmpty) {
      var normalized = parsed.toString();
      while (normalized.endsWith('/')) {
        normalized = normalized.substring(0, normalized.length - 1);
      }
      return normalized;
    }
    return trimmed;
  }

  Uri _uri(String path) {
    final parsed = Uri.tryParse('$cleanBaseUrl$path');
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      throw RideApiException('Invalid server URL "$cleanBaseUrl".');
    }
    return parsed;
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(timeout);
    } on TimeoutException {
      throw RideApiException(
        'Server timed out at $cleanBaseUrl. Check that the backend is running.',
      );
    } on SocketException {
      throw RideApiException(
        'Cannot reach server at $cleanBaseUrl. Check the URL and network.',
      );
    } on http.ClientException {
      throw RideApiException(
        'Cannot reach server at $cleanBaseUrl. Check the URL and network.',
      );
    }
  }

  Map<String, dynamic> _decodeJsonObject(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw RideApiException(
      'Unexpected server response (${response.statusCode}).',
      statusCode: response.statusCode,
    );
  }

  RideApiException _errorFromResponse(http.Response response) {
    var message = 'Request failed (${response.statusCode}).';
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is String && detail.isNotEmpty) {
          message = detail;
        } else if (detail is List && detail.isNotEmpty) {
          final first = detail.first;
          if (first is Map<String, dynamic> && first['msg'] is String) {
            message = first['msg'] as String;
          }
        }
      }
    } catch (_) {
      // Keep the status-code fallback when error body isn't JSON.
    }
    return RideApiException(message, statusCode: response.statusCode);
  }

  Future<BackendHealth> checkHealth() async {
    final response = await _send(() => _client.get(_uri('/health')));
    if (response.statusCode != 200) {
      throw _errorFromResponse(response);
    }
    final data = _decodeJsonObject(response);
    return BackendHealth(
      status: (data['status'] as String?) ?? 'unknown',
      database: (data['database'] as String?) ?? 'unknown',
    );
  }

  Future<ActiveRide> createRide({
    required String destination,
    required String hostName,
    double? destLat,
    double? destLng,
    double? distanceKm,
    int? durationMinutes,
    int? hostId,
  }) async {
    final body = <String, dynamic>{
      'destination': destination.trim(),
      'dest_lat': ?destLat,
      'dest_lng': ?destLng,
      'host_name': hostName.trim().isEmpty ? 'Rider' : hostName.trim(),
      'host_id': ?hostId,
    };
    final response = await _send(
      () => _client.post(
        _uri('/rides'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ),
    );
    if (response.statusCode != 201) {
      throw _errorFromResponse(response);
    }
    final data = _decodeJsonObject(response);
    return ActiveRide(
      joinCode: data['code'] as String,
      destination: data['destination'] as String,
      destLat: (data['dest_lat'] as num?)?.toDouble() ?? destLat,
      destLng: (data['dest_lng'] as num?)?.toDouble() ?? destLng,
      distanceKm: distanceKm,
      durationMinutes: durationMinutes,
      isHost: true,
      currentUserId: (data['host_id'] as num).toInt(),
      currentUserName: (data['host_name'] as String?) ?? hostName,
    );
  }

  Future<ActiveRide> joinRide({
    required String code,
    required String riderName,
    int? userId,
  }) async {
    final cleanCode = code.trim().toUpperCase();
    final body = <String, dynamic>{
      'name': riderName.trim().isEmpty ? 'Rider' : riderName.trim(),
      'user_id': ?userId,
    };
    final response = await _send(
      () => _client.post(
        _uri('/rides/$cleanCode/join'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ),
    );
    if (response.statusCode != 200) {
      throw _errorFromResponse(response);
    }
    final data = _decodeJsonObject(response);
    return ActiveRide(
      joinCode: data['code'] as String,
      destination: data['destination'] as String,
      destLat: (data['dest_lat'] as num?)?.toDouble(),
      destLng: (data['dest_lng'] as num?)?.toDouble(),
      isHost: (data['is_host'] as bool?) ?? false,
      currentUserId: (data['user_id'] as num).toInt(),
      currentUserName: (data['name'] as String?) ?? riderName,
    );
  }

  Future<void> sendPosition({
    required String code,
    required int userId,
    required double latitude,
    required double longitude,
    double speedKmh = 0,
    double headingDegrees = 0,
    int? batteryPercent,
  }) async {
    final cleanCode = code.trim().toUpperCase();
    final safeSpeed = speedKmh < 0 ? 0.0 : speedKmh;
    final safeHeading = headingDegrees < 0 || headingDegrees > 360
        ? 0.0
        : headingDegrees;
    final body = <String, dynamic>{
      'user_id': userId,
      'latitude': latitude,
      'longitude': longitude,
      'speed_kmh': safeSpeed,
      'heading_degrees': safeHeading,
      'battery_percent': ?batteryPercent,
    };
    final response = await _send(
      () => _client.post(
        _uri('/rides/$cleanCode/position'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ),
    );
    if (response.statusCode != 200) {
      throw _errorFromResponse(response);
    }
  }

  Future<RideAlert> sendAlert({
    required String code,
    required int userId,
    required String alertType,
    String message = '',
  }) async {
    final cleanCode = code.trim().toUpperCase();
    final response = await _send(
      () => _client.post(
        _uri('/rides/$cleanCode/alert'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'alert_type': alertType,
          'message': message.trim(),
        }),
      ),
    );
    if (response.statusCode != 201) {
      throw _errorFromResponse(response);
    }
    return _parseAlert(_decodeJsonObject(response));
  }

  RideAlert _parseAlert(Map<String, dynamic> json) {
    return RideAlert(
      id: (json['id'] as num).toInt(),
      userId: (json['user_id'] as num).toInt(),
      senderName: (json['sender_name'] as String?) ?? 'Rider',
      alertType: (json['alert_type'] as String?) ?? 'wait',
      message: (json['message'] as String?) ?? '',
      ageSeconds: ((json['age_seconds'] as num?) ?? 0).toInt(),
    );
  }

  Future<RidePositionsSnapshot> fetchPositions(String code) async {
    final cleanCode = code.trim().toUpperCase();
    final response = await _send(
      () => _client.get(_uri('/rides/$cleanCode/positions')),
    );
    if (response.statusCode != 200) {
      throw _errorFromResponse(response);
    }
    final data = _decodeJsonObject(response);
    final rawRiders = (data['riders'] as List<dynamic>?) ?? const [];
    final riders = <RiderPosition>[];
    for (final item in rawRiders) {
      if (item is! Map<String, dynamic>) continue;
      final riderJson = item['rider'] as Map<String, dynamic>;
      riders.add(
        RiderPosition(
          rider: Rider(
            id: (riderJson['id'] as num).toInt(),
            name: riderJson['name'] as String,
          ),
          latitude: (item['latitude'] as num).toDouble(),
          longitude: (item['longitude'] as num).toDouble(),
          speedKmh: ((item['speed_kmh'] as num?) ?? 0).toDouble(),
          headingDegrees: ((item['heading_degrees'] as num?) ?? 0).toDouble(),
          batteryPercent: (item['battery_percent'] as num?)?.toInt(),
          ageSeconds: ((item['age_seconds'] as num?) ?? 0).toInt(),
        ),
      );
    }
    final rawAlert = data['latest_alert'];
    final latestAlert = rawAlert is Map<String, dynamic>
        ? _parseAlert(rawAlert)
        : null;
    return RidePositionsSnapshot(
      code: (data['code'] as String?) ?? cleanCode,
      destination: (data['destination'] as String?) ?? '',
      destLat: (data['dest_lat'] as num?)?.toDouble(),
      destLng: (data['dest_lng'] as num?)?.toDouble(),
      isEnded: (data['is_ended'] as bool?) ?? false,
      riders: riders,
      latestAlert: latestAlert,
    );
  }

  Future<void> endRide({required String code, required int hostId}) async {
    final cleanCode = code.trim().toUpperCase();
    final response = await _send(
      () => _client.post(
        _uri('/rides/$cleanCode/end'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'host_id': hostId}),
      ),
    );
    if (response.statusCode != 200) {
      throw _errorFromResponse(response);
    }
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
