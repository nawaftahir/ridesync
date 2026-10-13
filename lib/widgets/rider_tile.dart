import 'package:flutter/material.dart';
import 'package:ridesync/models/rider_position.dart';

class RiderTile extends StatelessWidget {
  const RiderTile({super.key, required this.position});

  final RiderPosition position;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text(position.rider.initial)),
        title: Text(position.rider.name),
        subtitle: Text('${position.speedKmh.round()} km/h'),
        trailing: _status(context),
      ),
    );
  }

  // What to show on the right side of the tile. Returns null for "nothing".
  Widget? _status(BuildContext context) {
    if (position.isStale) {
      // The warning color comes from the theme, so it looks right in both
      // light and dark mode.
      final warning = Theme.of(context).colorScheme.tertiary;
      return Text('Signal lost', style: TextStyle(color: warning));
    }
    final battery = position.batteryPercent;
    if (battery == null) {
      return null;
    }
    return Text('$battery%');
  }
}
