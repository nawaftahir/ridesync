import 'package:flutter/material.dart';
import 'package:ridesync/screens/login_screen.dart';
import 'package:ridesync/services/app_preferences.dart';
import 'package:ridesync/services/ride_api_service.dart';

// Rider profile page with editable name, theme switcher, server config, and login link.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.riderName = AppPreferences.defaultRiderName,
    this.onRiderNameChanged,
    this.serverUrl = AppPreferences.buildApiBaseUrl,
    this.onServerUrlChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final String riderName;
  final ValueChanged<String>? onRiderNameChanged;
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

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onRiderNameChanged == null
                  ? null
                  : () => _openNameDialog(context),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: colors.primary,
                      foregroundColor: colors.onPrimary,
                      child: Text(
                        riderName.trim().isEmpty
                            ? '?'
                            : riderName.trim()[0].toUpperCase(),
                        style: const TextStyle(
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
                            riderName.trim().isEmpty
                                ? AppPreferences.defaultRiderName
                                : riderName.trim(),
                            style: text.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            onRiderNameChanged == null
                                ? 'Guest rider · Not signed in'
                                : 'Tap to change display name',
                            style: text.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onRiderNameChanged != null)
                      Icon(
                        Icons.edit_outlined,
                        size: 20,
                        color: colors.onSurfaceVariant,
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

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
                if (onServerUrlChanged != null) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.dns_outlined),
                    title: const Text('Backend server'),
                    subtitle: Text(
                      serverUrl.trim().isEmpty
                          ? 'Not configured'
                          : serverUrl.trim(),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openServerDialog(context),
                  ),
                ],
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.two_wheeler),
                  title: Text('RideSync'),
                  subtitle: Text('Version 1.0.0'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openNameDialog(BuildContext context) async {
    final nextName = await showDialog<String>(
      context: context,
      builder: (_) => _RiderNameDialog(initialName: riderName),
    );
    if (nextName != null && nextName.isNotEmpty) {
      onRiderNameChanged?.call(nextName);
    }
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

class _RiderNameDialog extends StatefulWidget {
  const _RiderNameDialog({required this.initialName});

  final String initialName;

  @override
  State<_RiderNameDialog> createState() => _RiderNameDialogState();
}

class _RiderNameDialogState extends State<_RiderNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rider Display Name'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        maxLength: 30,
        decoration: const InputDecoration(
          labelText: 'Your name on the map',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
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
        _statusOk = false;
        _statusMessage = 'Enter a server URL to test.';
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
              textCapitalization: TextCapitalization.none,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                hintText: 'https://api.example.com',
                labelText: 'Server URL',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (AppPreferences.buildApiBaseUrl.isNotEmpty)
                  ActionChip(
                    label: const Text('Build default'),
                    onPressed: () => _setPreset(AppPreferences.buildApiBaseUrl),
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
