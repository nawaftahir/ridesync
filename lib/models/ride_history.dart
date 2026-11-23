import 'package:latlong2/latlong.dart';

// Aggregated stats for a signed-in rider returned by GET /rides/history.
class RiderStats {
  const RiderStats({
    required this.totalRides,
    required this.hostedRides,
    required this.joinedRides,
    required this.totalMinutes,
  });

  final int totalRides;
  final int hostedRides;
  final int joinedRides;
  final int totalMinutes;

  String get formattedTotalTime => formatRideDuration(totalMinutes);

  factory RiderStats.fromJson(Map<String, dynamic> json) => RiderStats(
    totalRides: ((json['total_rides'] as num?) ?? 0).toInt(),
    hostedRides: ((json['hosted_rides'] as num?) ?? 0).toInt(),
    joinedRides: ((json['joined_rides'] as num?) ?? 0).toInt(),
    totalMinutes: ((json['total_minutes'] as num?) ?? 0).toInt(),
  );
}

// A single completed ride returned by GET /rides/history.
class PastRide {
  const PastRide({
    required this.code,
    required this.destination,
    this.destLat,
    this.destLng,
    required this.hostName,
    required this.isHost,
    required this.riderCount,
    required this.startedAt,
    this.endedAt,
    required this.durationMinutes,
  });

  final String code;
  final String destination;
  final double? destLat;
  final double? destLng;
  final String hostName;
  final bool isHost;
  final int riderCount;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int durationMinutes;

  LatLng? get destinationPoint =>
      (destLat != null && destLng != null) ? LatLng(destLat!, destLng!) : null;

  String get formattedDuration => formatRideDuration(durationMinutes);

  static PastRide? fromJson(Map<String, dynamic> json) {
    final code = json['code'];
    final destination = json['destination'];
    final startedRaw = json['started_at'];
    if (code is! String || destination is! String || startedRaw is! String) {
      return null;
    }
    final startedAt = DateTime.tryParse(startedRaw)?.toLocal();
    if (startedAt == null) return null;
    final endedRaw = json['ended_at'];
    final endedAt = endedRaw is String
        ? DateTime.tryParse(endedRaw)?.toLocal()
        : null;
    return PastRide(
      code: code.trim().toUpperCase(),
      destination: destination.trim(),
      destLat: (json['dest_lat'] as num?)?.toDouble(),
      destLng: (json['dest_lng'] as num?)?.toDouble(),
      hostName: (json['host_name'] as String?) ?? 'Rider',
      isHost: (json['is_host'] as bool?) ?? false,
      riderCount: ((json['rider_count'] as num?) ?? 1).toInt(),
      startedAt: startedAt,
      endedAt: endedAt,
      durationMinutes: ((json['duration_minutes'] as num?) ?? 0).toInt(),
    );
  }
}

class RideHistoryData {
  const RideHistoryData({required this.stats, required this.rides});

  final RiderStats stats;
  final List<PastRide> rides;

  factory RideHistoryData.fromJson(Map<String, dynamic> json) {
    final rawStats = json['stats'];
    final stats = rawStats is Map<String, dynamic>
        ? RiderStats.fromJson(rawStats)
        : const RiderStats(
            totalRides: 0,
            hostedRides: 0,
            joinedRides: 0,
            totalMinutes: 0,
          );
    final rawRides = (json['rides'] as List<dynamic>?) ?? const [];
    final rides = <PastRide>[];
    for (final item in rawRides) {
      if (item is Map<String, dynamic>) {
        final parsed = PastRide.fromJson(item);
        if (parsed != null) rides.add(parsed);
      }
    }
    return RideHistoryData(stats: stats, rides: rides);
  }
}

String formatRideDuration(int minutes) {
  if (minutes <= 0) return '< 1 min';
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rem = minutes % 60;
  return rem == 0 ? '${hours}h' : '${hours}h ${rem}m';
}
