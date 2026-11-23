import 'package:flutter/material.dart';
import 'package:ridesync/services/ride_api_service.dart';

class JoinRideScreen extends StatefulWidget {
  const JoinRideScreen({
    super.key,
    this.apiService,
    this.riderName = 'Rider',
    this.isSignedIn = false,
    this.initialCode,
    this.autoJoin = false,
  });

  final RideApiService? apiService;
  final String riderName;
  final bool isSignedIn;
  final String? initialCode;
  final bool autoJoin;

  @override
  State<JoinRideScreen> createState() => _JoinRideScreenState();
}

class _JoinRideScreenState extends State<JoinRideScreen> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.riderName == 'Rider' ? '' : widget.riderName,
  );
  late final TextEditingController _codeController = TextEditingController(
    text: (widget.initialCode ?? '').trim().toUpperCase(),
  );
  String? _errorMessage;
  bool _isLoading = false;

  String get _effectiveRiderName {
    final typed = _nameController.text.trim();
    return typed.isEmpty ? 'Rider' : typed;
  }

  @override
  void initState() {
    super.initState();
    if (widget.autoJoin && _codeController.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _onJoinTapped();
        }
      });
    }
  }

  Future<void> _onJoinTapped() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() {
        _errorMessage = 'Enter a 6-character ride code.';
      });
      return;
    }

    final api = widget.apiService;
    if (api == null || !api.isEnabled) {
      setState(() {
        _errorMessage = 'Set a Backend Server URL in Profile first.';
      });
      return;
    }

    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    try {
      final joined = await api.joinRide(
        code: code,
        riderName: _effectiveRiderName,
      );
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      Navigator.of(context).pop(joined);
    } on RideApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.message;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Join with a Code')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Enter Code from a host to join.', style: text.bodyLarge),
            const SizedBox(height: 16),

            if (widget.isSignedIn) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      size: 18,
                      color: colors.onPrimaryContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Joining as ${widget.riderName}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: colors.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ] else ...[
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                maxLength: 30,
                decoration: const InputDecoration(
                  labelText: 'Your name (optional)',
                  hintText: 'Defaults to Rider',
                  prefixIcon: Icon(Icons.person_outline),
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
            ],

            TextField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 6,
              ),
              decoration: InputDecoration(
                hintText: 'XXXXXX',
                border: const OutlineInputBorder(),
                errorText: _errorMessage,
                errorMaxLines: 3,
              ),
              onSubmitted: (_) => _onJoinTapped(),
            ),
            const SizedBox(height: 16),

            FilledButton.icon(
              onPressed: _isLoading ? null : _onJoinTapped,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.group_add),
              label: Text(_isLoading ? 'Checking…' : 'Join Ride'),
            ),
            const SizedBox(height: 32),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  widget.apiService?.isEnabled == true
                      ? 'Connected to ${widget.apiService!.cleanBaseUrl} · Enter the 6-character code from your host.'
                      : 'No server configured. Set your server URL in Profile -> Backend server.',
                  style: text.bodySmall,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
