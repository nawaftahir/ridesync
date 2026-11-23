import 'package:flutter/material.dart';
import 'package:ridesync/models/active_ride.dart';
import 'package:ridesync/models/rider_position.dart';
import 'package:ridesync/models/riding_crew.dart';
import 'package:ridesync/screens/convoy_screen.dart';
import 'package:ridesync/services/app_preferences.dart';
import 'package:ridesync/utils/ride_share.dart';

// Live convoy hub + saved riding crews for quick group ride launches.
class GroupScreen extends StatefulWidget {
  const GroupScreen({
    super.key,
    required this.activeRide,
    required this.riders,
    this.serverBaseUrl,
    this.onHostRide,
    this.onShareOverride,
    this.preferences,
  });

  final ActiveRide? activeRide;
  final List<RiderPosition> riders;
  final String? serverBaseUrl;
  final VoidCallback? onHostRide;
  final RideShareHandler? onShareOverride;
  final AppPreferences? preferences;

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  late final AppPreferences _prefs = widget.preferences ?? AppPreferences();
  List<RidingCrew> _crews = const [];

  @override
  void initState() {
    super.initState();
    _loadCrews();
  }

  Future<void> _loadCrews() async {
    final loaded = await _prefs.loadCrews();
    if (!mounted) return;
    setState(() {
      _crews = loaded;
    });
  }

  Future<void> _openCrewDialog({RidingCrew? existing}) async {
    final result = await showDialog<_CrewDraft>(
      context: context,
      builder: (_) => _CrewEditorDialog(existing: existing),
    );
    if (!mounted || result == null) return;

    final updated = List<RidingCrew>.of(_crews);
    if (existing == null) {
      updated.insert(
        0,
        RidingCrew(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: result.name,
          members: result.members,
        ),
      );
    } else {
      final index = updated.indexWhere((c) => c.id == existing.id);
      if (index != -1) {
        updated[index] = RidingCrew(
          id: existing.id,
          name: result.name,
          members: result.members,
        );
      }
    }
    setState(() => _crews = updated);
    await _prefs.saveCrews(updated);
  }

  Future<void> _deleteCrew(RidingCrew crew) async {
    final updated = _crews.where((c) => c.id != crew.id).toList();
    setState(() => _crews = updated);
    await _prefs.saveCrews(updated);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final ride = widget.activeRide;

    return Scaffold(
      appBar: AppBar(title: const Text('Group')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (ride != null) ...[
            Card(
              color: colors.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: colors.primary,
                          foregroundColor: colors.onPrimary,
                          child: const Icon(Icons.groups),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Active convoy (${widget.riders.length} riders)',
                                style: text.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: colors.onPrimaryContainer,
                                ),
                              ),
                              Text(
                                ride.destination,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => copyRideCode(context, ride.joinCode),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: colors.surface,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              ride.joinCode,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => shareRideInvite(
                              code: ride.joinCode,
                              destination: ride.destination,
                              serverBaseUrl: widget.serverBaseUrl,
                              onShareOverride: widget.onShareOverride,
                            ),
                            icon: const Icon(Icons.share_outlined, size: 18),
                            label: const Text('Share invite'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ConvoyScreen(
                                  riders: widget.riders,
                                  currentUserId: ride.currentUserId,
                                  rideCode: ride.joinCode,
                                  destination: ride.destination,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.people_outline, size: 18),
                            label: const Text('View convoy'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Riding crews',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: () => _openCrewDialog(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New crew'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_crews.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.two_wheeler_outlined,
                      size: 48,
                      color: colors.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No riding crews yet',
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Save your regular weekend or city riding buddies here to launch convoys faster.',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _openCrewDialog(),
                        icon: const Icon(Icons.group_add_outlined),
                        label: const Text('Create Crew'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            for (final crew in _crews)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: colors.secondaryContainer,
                            foregroundColor: colors.onSecondaryContainer,
                            child: Text(
                              crew.name[0].toUpperCase(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  crew.name,
                                  style: text.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  crew.members.isEmpty
                                      ? 'No riders listed'
                                      : '${crew.members.length} riders',
                                  style: text.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (action) {
                              if (action == 'edit') {
                                _openCrewDialog(existing: crew);
                              } else if (action == 'delete') {
                                _deleteCrew(crew);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (crew.members.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final member in crew.members)
                              Chip(
                                label: Text(member),
                                visualDensity: VisualDensity.compact,
                              ),
                          ],
                        ),
                      ],
                      if (widget.onHostRide != null) ...[
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          onPressed: widget.onHostRide,
                          icon: const Icon(Icons.add_road, size: 18),
                          label: const Text('Start Ride with Crew'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _CrewDraft {
  const _CrewDraft({required this.name, required this.members});

  final String name;
  final List<String> members;
}

class _CrewEditorDialog extends StatefulWidget {
  const _CrewEditorDialog({this.existing});

  final RidingCrew? existing;

  @override
  State<_CrewEditorDialog> createState() => _CrewEditorDialogState();
}

class _CrewEditorDialogState extends State<_CrewEditorDialog> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _membersController = TextEditingController(
    text: widget.existing?.members.join(', ') ?? '',
  );

  @override
  void dispose() {
    _nameController.dispose();
    _membersController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final members = _membersController.text
        .split(',')
        .map((m) => m.trim())
        .where((m) => m.isNotEmpty)
        .toList(growable: false);
    Navigator.of(context).pop(_CrewDraft(name: name, members: members));
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    return AlertDialog(
      title: Text(isEditing ? 'Edit Riding Crew' : 'Create Riding Crew'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            maxLength: 40,
            decoration: const InputDecoration(
              labelText: 'Crew name',
              hintText: 'e.g. Margalla Dawn Riders',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _membersController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Riders (comma-separated)',
              hintText: 'e.g. Bilal, Zain, Ayesha',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(isEditing ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}
