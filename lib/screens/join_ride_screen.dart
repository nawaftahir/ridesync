import 'package:flutter/material.dart';
import 'package:ridesync/models/active_ride.dart';
import 'package:ridesync/repositories/ride_repository.dart';
import 'package:ridesync/services/ride_api_service.dart';

class JoinRideScreen extends StatefulWidget {
  const JoinRideScreen({super.key, this.apiService, this.riderName = 'Nawaf'});

  final RideApiService? apiService;
  final String riderName;

  @override
  State<JoinRideScreen> createState() => _JoinRideScreenState();
}

class _JoinRideScreenState extends State<JoinRideScreen> {
  static const _rideRepository = RideRepository();

  final _codeController = TextEditingController();
  String? _errorMessage;
  bool _isLoading = false;

  // async/await: this function pauses at `await` without freezing the UI.
  Future<void> _onJoinTapped() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() {
        _errorMessage = 'Enter a 6-character ride code.';
      });
      return;
    }

    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    final api = widget.apiService;
    if (api != null && api.isEnabled) {
      try {
        final joined = await api.joinRide(
          code: code,
          riderName: widget.riderName,
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
      return;
    }

    // Offline mock-preview fallback.
    await Future.delayed(const Duration(milliseconds: 800));

    final ride = _rideRepository.findByCode(code);

    // `mounted` check: if the user left this screen during the delay, stop.
    if (!mounted) return;

    if (ride == null) {
      setState(() {
        _errorMessage =
            'No ride found for "$code". '
            'Try MOTO89 or RIDE42.';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = false;
    });
    // Return the joined ride to MainScreen so it opens on the Map tab.
    Navigator.of(context).pop(
      ActiveRide(
        joinCode: ride.code,
        destination: ride.destination,
        isHost: false,
        distanceKm: ride.distanceKm,
        currentUserName: widget.riderName,
      ),
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Join with a Code')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Enter Code from a host to join.', style: text.bodyLarge),
            const SizedBox(height: 24),

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
              // null disables the button (greyed out) while loading.
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

            // Info card showing whether we are using a live server or mock preview.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  widget.apiService?.isEnabled == true
                      ? 'Connected to ${widget.apiService!.cleanBaseUrl} · Enter any live ride code.'
                      : '🛈  Alpha hint: valid codes are MOTO89 and RIDE42',
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
