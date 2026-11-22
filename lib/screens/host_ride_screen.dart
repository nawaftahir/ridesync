import 'dart:math';

import 'package:flutter/material.dart';
import 'package:ridesync/models/active_ride.dart';
import 'package:ridesync/services/ride_api_service.dart';

class HostRideScreen extends StatefulWidget {
  const HostRideScreen({super.key, this.apiService, this.hostName = 'Nawaf'});

  final RideApiService? apiService;
  final String hostName;

  @override
  State<HostRideScreen> createState() => _HostRideScreenState();
}

class _HostRideScreenState extends State<HostRideScreen> {
  // Reads whatever is typed in the destination field.
  final _destinationController = TextEditingController();

  // The generated code. null = not generated yet → code card is hidden.
  String? _joinCode;
  ActiveRide? _createdRide;
  String? _errorMessage;
  bool _isLoading = false;

  // Builds a random 6-letter uppercase code, e.g. "KXMQTB" (offline mode only).
  // ASCII 65 = 'A', so 65 + 0…25 gives A…Z.
  String _generateCode() {
    final random = Random();
    String code = '';
    for (int i = 0; i < 6; i++) {
      code += String.fromCharCode(65 + random.nextInt(26));
    }
    return code;
  }

  Future<void> _onGenerateTapped() async {
    final destination = _destinationController.text.trim();
    if (destination.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a destination first.')),
      );
      return;
    }

    final api = widget.apiService;
    if (api == null || !api.isEnabled) {
      // Offline mock-preview mode.
      setState(() {
        _errorMessage = null;
        _createdRide = null;
        _joinCode = _generateCode();
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final ride = await api.createRide(
        destination: destination,
        hostName: widget.hostName,
      );
      if (!mounted) return;
      setState(() {
        _createdRide = ride;
        _joinCode = ride.joinCode;
        _isLoading = false;
      });
    } on RideApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.message;
        _isLoading = false;
      });
    }
  }

  void _onStartRideTapped() {
    // Return the created ride to MainScreen so it opens on the Map tab.
    Navigator.of(context).pop(
      _createdRide ??
          ActiveRide(
            joinCode: _joinCode!,
            destination: _destinationController.text.trim(),
            isHost: true,
            currentUserName: widget.hostName,
          ),
    );
  }

  @override
  void dispose() {
    // Always dispose controllers to free memory when the screen closes.
    _destinationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Host a Ride')),
      // SingleChildScrollView prevents overflow when the keyboard opens.
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Where are you going?', style: text.titleMedium),
            const SizedBox(height: 12),

            TextField(
              controller: _destinationController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'e.g. Daman-e-Koh, Islamabad',
                prefixIcon: Icon(Icons.location_on_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

            FilledButton.icon(
              onPressed: _isLoading ? null : _onGenerateTapped,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.vpn_key_outlined),
              label: Text(_isLoading ? 'Creating…' : 'Generate Join Code'),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(_errorMessage!, style: TextStyle(color: colors.error)),
            ],
            const SizedBox(height: 24),

            // `if` inside a list: the widget is only added when the condition
            // is true. Here, the code card and Start button appear only after
            // a code is generated.
            if (_joinCode != null)
              Card(
                color: colors.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Text(
                        'Share this code with your riders',
                        style: text.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _joinCode!,
                        style: text.displaySmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 8,
                          color: colors.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_joinCode != null) const SizedBox(height: 20),
            if (_joinCode != null)
              FilledButton.icon(
                onPressed: _onStartRideTapped,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Start Ride'),
              ),
          ],
        ),
      ),
    );
  }
}
