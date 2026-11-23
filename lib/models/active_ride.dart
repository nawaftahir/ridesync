import 'package:latlong2/latlong.dart';

// Holds the active ride details passed between screens (Host/Join -> Map)
// and saved locally so reopening the app restores an in-progress convoy.
class ActiveRide {
  const ActiveRide({
    required this.joinCode,
    required this.destination,
    required this.isHost,
    this.destLat,
    this.destLng,
    this.pickupLabel = 'Your location',
    this.distanceKm,
    this.durationMinutes,
    this.currentUserId,
    this.currentUserName = 'Rider',
    this.crewName,
    this.crewMembers = const [],
  });

  final String joinCode;
  final String destination;
  final bool isHost;
  final double? destLat;
  final double? destLng;
  final String pickupLabel;
  final double? distanceKm;
  final int? durationMinutes;

  // Set when the ride comes from the FastAPI backend; null in offline demo mode.
  final int? currentUserId;
  final String currentUserName;

  // Optional riding crew context when started from the Group tab.
  final String? crewName;
  final List<String> crewMembers;

  LatLng? get destinationPoint =>
      (destLat != null && destLng != null) ? LatLng(destLat!, destLng!) : null;

  ActiveRide copyWith({String? crewName, List<String>? crewMembers}) =>
      ActiveRide(
        joinCode: joinCode,
        destination: destination,
        isHost: isHost,
        destLat: destLat,
        destLng: destLng,
        pickupLabel: pickupLabel,
        distanceKm: distanceKm,
        durationMinutes: durationMinutes,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
        crewName: crewName ?? this.crewName,
        crewMembers: crewMembers ?? this.crewMembers,
      );

  Map<String, dynamic> toJson() => {
    'joinCode': joinCode,
    'destination': destination,
    'isHost': isHost,
    if (destLat != null) 'destLat': destLat,
    if (destLng != null) 'destLng': destLng,
    'pickupLabel': pickupLabel,
    if (distanceKm != null) 'distanceKm': distanceKm,
    if (durationMinutes != null) 'durationMinutes': durationMinutes,
    if (currentUserId != null) 'currentUserId': currentUserId,
    'currentUserName': currentUserName,
    if (crewName != null && crewName!.isNotEmpty) 'crewName': crewName,
    if (crewMembers.isNotEmpty) 'crewMembers': crewMembers,
  };

  static ActiveRide? fromJson(Map<String, dynamic> json) {
    final code = json['joinCode'];
    final dest = json['destination'];
    final isHost = json['isHost'];
    if (code is! String ||
        code.trim().isEmpty ||
        dest is! String ||
        isHost is! bool) {
      return null;
    }
    final rawMembers = json['crewMembers'];
    final members = rawMembers is List
        ? rawMembers.whereType<String>().toList(growable: false)
        : const <String>[];
    return ActiveRide(
      joinCode: code.trim().toUpperCase(),
      destination: dest,
      isHost: isHost,
      destLat: (json['destLat'] as num?)?.toDouble(),
      destLng: (json['destLng'] as num?)?.toDouble(),
      pickupLabel: (json['pickupLabel'] as String?) ?? 'Your location',
      distanceKm: (json['distanceKm'] as num?)?.toDouble(),
      durationMinutes: (json['durationMinutes'] as num?)?.toInt(),
      currentUserId: (json['currentUserId'] as num?)?.toInt(),
      currentUserName: (json['currentUserName'] as String?) ?? 'Rider',
      crewName: json['crewName'] as String?,
      crewMembers: members,
    );
  }
}
