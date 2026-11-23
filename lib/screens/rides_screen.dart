import 'package:flutter/material.dart';
import 'package:ridesync/models/active_ride.dart';
import 'package:ridesync/models/ride_history.dart';

// Shows quick actions to host/join a ride, the active ride shortcut,
// and real completed ride history synced from MariaDB for signed-in riders.
class RidesScreen extends StatelessWidget {
  const RidesScreen({
    super.key,
    required this.activeRide,
    required this.onOpenMap,
    required this.onHostRide,
    required this.onJoinRide,
    this.isSignedIn = false,
    this.history,
    this.isLoadingHistory = false,
    this.historyError,
    this.onRefreshHistory,
    this.onOpenLogin,
    this.onRideAgain,
  });

  final ActiveRide? activeRide;
  final VoidCallback onOpenMap;
  final VoidCallback onHostRide;
  final VoidCallback onJoinRide;
  final bool isSignedIn;
  final RideHistoryData? history;
  final bool isLoadingHistory;
  final String? historyError;
  final Future<void> Function()? onRefreshHistory;
  final VoidCallback? onOpenLogin;
  final ValueChanged<PastRide>? onRideAgain;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _formatDate(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '${_months[dt.month - 1]} ${dt.day} · $hour:$min';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final pastRides = history?.rides ?? const <PastRide>[];

    final content = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: [
        if (activeRide != null) ...[
          Card(
            color: colors.primaryContainer,
            child: ListTile(
              leading: Icon(Icons.navigation, color: colors.onPrimaryContainer),
              title: Text(
                activeRide!.destination,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: colors.onPrimaryContainer,
                ),
              ),
              subtitle: Text(
                'Live now · Code ${activeRide!.joinCode}',
                style: TextStyle(color: colors.onPrimaryContainer),
              ),
              trailing: TextButton(
                onPressed: onOpenMap,
                child: const Text('Map'),
              ),
              onTap: onOpenMap,
            ),
          ),
          const SizedBox(height: 16),
        ],

        if (activeRide == null) ...[
          Text(
            'Start a group ride or join your crew with a code.',
            style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
        ],

        FilledButton.icon(
          onPressed: onHostRide,
          icon: const Icon(Icons.add_road),
          label: const Text('Host a ride'),
        ),
        const SizedBox(height: 12),

        OutlinedButton.icon(
          onPressed: onJoinRide,
          icon: const Icon(Icons.group_add),
          label: const Text('Join with a code'),
        ),
        const SizedBox(height: 28),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Past rides',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (isSignedIn && onRefreshHistory != null)
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: 'Refresh history',
                visualDensity: VisualDensity.compact,
                onPressed: isLoadingHistory ? null : onRefreshHistory,
              ),
          ],
        ),
        const SizedBox(height: 8),

        if (!isSignedIn)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.history, size: 40, color: colors.onSurfaceVariant),
                  const SizedBox(height: 10),
                  Text(
                    'No past rides yet',
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Sign in to save completed rides and track your convoy history.',
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  if (onOpenLogin != null) ...[
                    const SizedBox(height: 14),
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 42),
                      ),
                      onPressed: onOpenLogin,
                      icon: const Icon(Icons.person_outline, size: 18),
                      label: const Text('Sign in'),
                    ),
                  ],
                ],
              ),
            ),
          )
        else if (isLoadingHistory && pastRides.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (historyError != null && pastRides.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(
                    Icons.cloud_off_outlined,
                    size: 36,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    historyError!,
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  if (onRefreshHistory != null) ...[
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 40),
                      ),
                      onPressed: onRefreshHistory,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Retry'),
                    ),
                  ],
                ],
              ),
            ),
          )
        else if (pastRides.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.history, size: 40, color: colors.onSurfaceVariant),
                  const SizedBox(height: 10),
                  Text(
                    'No past rides yet',
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Completed group rides you host or join will show up here.',
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          for (final ride in pastRides)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 19,
                          backgroundColor: ride.isHost
                              ? colors.primaryContainer
                              : colors.secondaryContainer,
                          child: Icon(
                            ride.isHost
                                ? Icons.flag_rounded
                                : Icons.two_wheeler_rounded,
                            size: 18,
                            color: ride.isHost
                                ? colors.onPrimaryContainer
                                : colors.onSecondaryContainer,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      ride.destination,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: text.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: ride.isHost
                                          ? colors.primaryContainer
                                          : colors.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      ride.isHost ? 'Host' : 'Joined',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: ride.isHost
                                            ? colors.onPrimaryContainer
                                            : colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${_formatDate(ride.endedAt ?? ride.startedAt)}'
                                ' · ${ride.formattedDuration}'
                                ' · ${ride.riderCount} ${ride.riderCount == 1 ? 'rider' : 'riders'}',
                                style: text.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (onRideAgain != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Code ${ride.code} · Hosted by ${ride.hostName}',
                            style: text.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => onRideAgain!(ride),
                            icon: const Icon(Icons.replay_rounded, size: 16),
                            label: const Text('Ride again'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Rides')),
      body: isSignedIn && onRefreshHistory != null
          ? RefreshIndicator(onRefresh: onRefreshHistory!, child: content)
          : content,
    );
  }
}
