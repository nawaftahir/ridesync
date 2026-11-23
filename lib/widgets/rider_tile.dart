import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:ridesync/models/rider_position.dart';
import 'package:ridesync/services/map_search_service.dart';

// Distance threshold (meters) above which a peer rider is highlighted as "Far behind".
const double _kFarBehindMeters = 1500;

class RiderTile extends StatelessWidget {
  const RiderTile({
    super.key,
    required this.position,
    this.isCurrentUser = false,
    this.isHost = false,
    this.myPoint,
    this.onTap,
  });

  final RiderPosition position;
  final bool isCurrentUser;
  final bool isHost;
  final LatLng? myPoint;
  final VoidCallback? onTap;

  double? get _distanceMeters {
    if (isCurrentUser || myPoint == null) return null;
    return const Distance().as(LengthUnit.Meter, myPoint!, position.point);
  }

  bool get _isFarBehind =>
      !position.isStale &&
      _distanceMeters != null &&
      _distanceMeters! >= _kFarBehindMeters;

  String _subtitleText() {
    final speed = '${position.speedKmh.round()} km/h';
    if (isCurrentUser) {
      return '$speed · You';
    }
    if (myPoint != null) {
      final dist = formatPlaceDistance(myPoint!, position.point);
      return '$speed · $dist away';
    }
    return speed;
  }

  String _staleLabel() {
    final mins = (position.ageSeconds / 60).floor();
    if (mins < 1) return 'Signal lost';
    return 'Signal lost · ${mins}m ago';
  }

  IconData _batteryIcon(int percent) {
    if (percent <= 15) return Icons.battery_alert_rounded;
    if (percent <= 35) return Icons.battery_2_bar_rounded;
    if (percent <= 70) return Icons.battery_4_bar_rounded;
    return Icons.battery_full_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final avatarBg = position.isStale
        ? colors.tertiaryContainer
        : (isCurrentUser ? colors.primary : colors.secondaryContainer);
    final avatarFg = position.isStale
        ? colors.onTertiaryContainer
        : (isCurrentUser ? colors.onPrimary : colors.onSecondaryContainer);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: position.isStale
              ? colors.tertiary
              : (_isFarBehind
                    ? colors.error.withValues(alpha: 0.6)
                    : colors.outlineVariant),
        ),
      ),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: CircleAvatar(
          backgroundColor: avatarBg,
          foregroundColor: avatarFg,
          child: Text(
            position.rider.initial,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                position.rider.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (isCurrentUser) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'You',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ),
            ],
            if (isHost) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Host',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: colors.onSecondaryContainer,
                  ),
                ),
              ),
            ],
            if (_isFarBehind) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Fell behind',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: colors.onErrorContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          _subtitleText(),
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        trailing: _status(context),
      ),
    );
  }

  Widget? _status(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (position.isStale) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.signal_wifi_off_rounded, size: 16, color: colors.tertiary),
          const SizedBox(width: 4),
          Text(
            _staleLabel(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colors.tertiary,
            ),
          ),
        ],
      );
    }

    final battery = position.batteryPercent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (battery != null) ...[
          Icon(
            _batteryIcon(battery),
            size: 16,
            color: battery <= 15 ? colors.error : colors.onSurfaceVariant,
          ),
          const SizedBox(width: 2),
          Text(
            '$battery%',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: battery <= 15 ? colors.error : colors.onSurfaceVariant,
            ),
          ),
        ],
        if (onTap != null) ...[
          const SizedBox(width: 4),
          Icon(Icons.my_location_rounded, size: 18, color: colors.primary),
        ],
      ],
    );
  }
}
