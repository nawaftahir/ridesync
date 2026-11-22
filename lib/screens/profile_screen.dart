import 'package:flutter/material.dart';
import 'package:ridesync/repositories/ride_repository.dart';
import 'package:ridesync/screens/login_screen.dart';
import 'package:ridesync/services/ride_api_service.dart';

// Rider profile page with mock rider summary, theme switcher, server config, and login link.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    this.rideRepository = const RideRepository(),
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.serverUrl = '',
    this.onServerUrlChanged,
  });

  final RideRepository rideRepository;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final String serverUrl;
  final ValueChanged<String>? onServerUrlChanged;

  IconData get _themeIcon => switch (themeMode) {
    ThemeMode.system => Icons.brightness_auto_outlined,
    ThemeMode.light => Icons.light_mode_outlined,
    ThemeMode.dark => Icons.dark_mode_outlined,
  };

  String get _themeDescription => switch (themeMode) {
    ThemeMode.system => 'Auto · Follows phone Light / Dark mode',
    ThemeMode.light => 'Light · Always uses light theme',
    ThemeMode.dark => 'Dark · Always uses dark theme',
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final pastRides = rideRepository.pastRides;
    final totalKm = pastRides.fold<double>(
      0,
      (sum, ride) => sum + ride.distanceKm,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: colors.primary,
                    foregroundColor: colors.onPrimary,
                    child: const Text(
                      'N',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nawaf',
                          style: text.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Guest rider · Not signed in',
                          style: text.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Past rides',
                  value: '${pastRides.length}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'Total distance',
                  value: '${totalKm.toStringAsFixed(1)} km',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          FilledButton.icon(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const LoginScreen())),
            icon: const Icon(Icons.person_add),
            label: const Text('Sign up or log in'),
          ),
          const SizedBox(height: 20),

          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(_themeIcon),
                  title: const Text('Appearance'),
                  subtitle: Text(_themeDescription),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.system,
                          icon: Icon(Icons.brightness_auto_outlined, size: 18),
                          label: Text('Auto'),
                        ),
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode_outlined, size: 18),
                          label: Text('Light'),
                        ),
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode_outlined, size: 18),
                          label: Text('Dark'),
                        ),
                      ],
                      selected: {themeMode},
                      onSelectionChanged: onThemeModeChanged == null
                          ? null
                          : (selection) => onThemeModeChanged!(selection.first),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: const Text('Backend server'),
                  subtitle: Text(
                    serverUrl.trim().isEmpty
                        ? 'Offline preview (mock rides)'
                        : serverUrl.trim(),
                  ),
                  trailing: onServerUrlChanged == null
                      ? null
                      : const Icon(Icons.chevron_right),
                  onTap: onServerUrlChanged == null
                      ? null
                      : () => _openServerDialog(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.two_wheeler),
                  title: const Text('RideSync'),
                  subtitle: Text(
                    serverUrl.trim().isEmpty
                        ? 'Version 1.0.0 (Mock data preview)'
                        : 'Version 1.0.0 (Live backend mode)',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openServerDialog(BuildContext context) async {
    final nextUrl = await showDialog<String>(
      context: context,
      builder: (_) => _ServerConfigDialog(initialUrl: serverUrl),
    );
    if (nextUrl != null) {
      onServerUrlChanged?.call(nextUrl);
    }
  }
}

class _ServerConfigDialog extends StatefulWidget {
  const _ServerConfigDialog({required this.initialUrl});

  final String initialUrl;

  @override
  State<_ServerConfigDialog> createState() => _ServerConfigDialogState();
}

class _ServerConfigDialogState extends State<_ServerConfigDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialUrl,
  );
  bool _isTesting = false;
  String? _statusMessage;
  bool _statusOk = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final api = RideApiService(baseUrl: _controller.text);
    if (!api.isEnabled) {
      api.dispose();
      setState(() {
        _statusOk = true;
        _statusMessage = 'Offline preview mode selected.';
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _statusMessage = null;
    });
    try {
      final health = await api.checkHealth();
      if (!mounted) return;
      setState(() {
        _statusOk = health.isDatabaseConnected;
        _statusMessage = health.isDatabaseConnected
            ? 'Connected · MariaDB connected'
            : 'API reachable · MariaDB ${health.database}';
        _isTesting = false;
      });
    } on RideApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _statusOk = false;
        _statusMessage = error.message;
        _isTesting = false;
      });
    } finally {
      api.dispose();
    }
  }

  void _setPreset(String url) {
    _controller.text = url;
    setState(() {
      _statusMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Backend Server URL'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'Leave empty for offline demo',
                labelText: 'Server URL',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: const Text('Offline'),
                  onPressed: () => _setPreset(''),
                ),
                ActionChip(
                  label: const Text('USB (127.0.0.1:8000)'),
                  onPressed: () => _setPreset('http://127.0.0.1:8000'),
                ),
                ActionChip(
                  label: const Text('Emulator (10.0.2.2:8000)'),
                  onPressed: () => _setPreset('http://10.0.2.2:8000'),
                ),
              ],
            ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _statusMessage!,
                style: TextStyle(
                  color: _statusOk ? colors.primary : colors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isTesting ? null : _testConnection,
          child: Text(_isTesting ? 'Testing…' : 'Test'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
