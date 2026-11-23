import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:ridesync/models/active_ride.dart';
import 'package:ridesync/services/map_search_service.dart';
import 'package:ridesync/services/ride_api_service.dart';
import 'package:ridesync/utils/ride_share.dart';
import 'package:ridesync/widgets/place_search_sheet.dart';

class HostRideScreen extends StatefulWidget {
  const HostRideScreen({
    super.key,
    this.apiService,
    this.searchService,
    this.hostName = 'Rider',
    this.initialPlace,
    this.initialRoute,
    this.nearPoint,
    this.onShareOverride,
  });

  final RideApiService? apiService;
  final MapSearchService? searchService;
  final String hostName;
  final PlaceResult? initialPlace;
  final RoutePreview? initialRoute;
  final LatLng? nearPoint;
  final RideShareHandler? onShareOverride;

  @override
  State<HostRideScreen> createState() => _HostRideScreenState();
}

class _HostRideScreenState extends State<HostRideScreen> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.hostName == 'Rider' ? '' : widget.hostName,
  );
  late final TextEditingController _destinationController =
      TextEditingController(text: widget.initialPlace?.displayName ?? '');

  String get _effectiveHostName {
    final typed = _nameController.text.trim();
    return typed.isEmpty ? 'Rider' : typed;
  }

  late PlaceResult? _selectedPlace = widget.initialPlace;

  // The generated code. null = not generated yet -> code card is hidden.
  String? _joinCode;
  ActiveRide? _createdRide;
  String? _errorMessage;
  bool _isLoading = false;
  bool _copiedRecently = false;
  Timer? _copiedResetTimer;

  void _onDestinationChanged(String value) {
    // Editing text clears the previously selected pin until a new suggestion is picked.
    if (_selectedPlace != null &&
        value.trim() != _selectedPlace!.displayName &&
        value.trim() != _selectedPlace!.name) {
      setState(() {
        _selectedPlace = null;
      });
    }
  }

  void _pickSuggestion(PlaceResult place) {
    _destinationController.text = place.displayName;
    setState(() {
      _selectedPlace = place;
    });
  }

  Future<void> _openPlaceSearchSheet() async {
    final search = widget.searchService;
    if (search == null) return;
    final action = await showModalBottomSheet<PlaceSearchAction>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PlaceSearchSheet(
        searchService: search,
        nearPoint: widget.nearPoint,
        initialQuery: _destinationController.text.trim(),
        showPickOnMap: false,
        allowCustomEntry: true,
      ),
    );
    if (!mounted || action == null) return;
    if (action.place != null) {
      _pickSuggestion(action.place!);
    } else if (action.customDestination != null &&
        action.customDestination!.trim().isNotEmpty) {
      _destinationController.text = action.customDestination!.trim();
      setState(() {
        _selectedPlace = null;
      });
    }
  }

  Future<void> _onGenerateTapped() async {
    final destination = _destinationController.text.trim();
    if (destination.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a destination first.')),
      );
      return;
    }

    final point = _selectedPlace?.point;
    final matchedInitialRoute =
        widget.initialPlace != null &&
            _selectedPlace?.point == widget.initialPlace!.point
        ? widget.initialRoute
        : null;

    final api = widget.apiService;
    if (api == null || !api.isEnabled) {
      setState(() {
        _errorMessage = 'Set a Backend Server URL in Profile first.';
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
        destLat: point?.latitude,
        destLng: point?.longitude,
        distanceKm: matchedInitialRoute?.distanceKm,
        durationMinutes: matchedInitialRoute?.durationMinutes,
        hostName: _effectiveHostName,
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
    Navigator.of(context).pop(
      _createdRide ??
          ActiveRide(
            joinCode: _joinCode!,
            destination: _destinationController.text.trim(),
            destLat: _selectedPlace?.point.latitude,
            destLng: _selectedPlace?.point.longitude,
            isHost: true,
            currentUserName: _effectiveHostName,
          ),
    );
  }

  Future<void> _onCopyCodeTapped() async {
    final code = _joinCode;
    if (code == null) return;
    await copyRideCode(context, code);
    if (!mounted) return;
    _copiedResetTimer?.cancel();
    setState(() {
      _copiedRecently = true;
    });
    _copiedResetTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _copiedRecently = false;
      });
    });
  }

  Future<void> _onShareRideTapped() async {
    final code = _joinCode;
    if (code == null) return;
    final destination =
        _createdRide?.destination ?? _destinationController.text.trim();
    await shareRideInvite(
      code: code,
      destination: destination,
      serverBaseUrl: widget.apiService?.cleanBaseUrl,
      onShareOverride: widget.onShareOverride,
    );
  }

  @override
  void dispose() {
    _copiedResetTimer?.cancel();
    _nameController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Host a Ride')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Your name', style: text.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              maxLength: 30,
              decoration: const InputDecoration(
                hintText: 'Enter a temp name (optional, defaults to Rider)',
                prefixIcon: Icon(Icons.person_outline),
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

            Text('Where are you going?', style: text.titleMedium),
            const SizedBox(height: 12),

            if (widget.searchService != null)
              Material(
                color: colors.surfaceContainerLow,
                elevation: 2,
                shadowColor: Colors.black.withValues(alpha: 0.14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colors.outlineVariant),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _openPlaceSearchSheet,
                  child: SizedBox(
                    height: 52,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          Icon(
                            Icons.search,
                            size: 20,
                            color: _destinationController.text.trim().isEmpty
                                ? colors.onSurfaceVariant
                                : colors.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _destinationController.text.trim().isEmpty
                                  ? 'Where are you riding?'
                                  : _destinationController.text.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color:
                                    _destinationController.text.trim().isEmpty
                                    ? colors.onSurfaceVariant
                                    : colors.onSurface,
                              ),
                            ),
                          ),
                          if (_destinationController.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              tooltip: 'Clear destination',
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                setState(() {
                                  _destinationController.clear();
                                  _selectedPlace = null;
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else
              TextField(
                controller: _destinationController,
                textCapitalization: TextCapitalization.words,
                onChanged: _onDestinationChanged,
                decoration: InputDecoration(
                  hintText: 'Where are you riding?',
                  filled: true,
                  fillColor: colors.surfaceContainerHighest,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _destinationController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Clear destination',
                          onPressed: () {
                            setState(() {
                              _destinationController.clear();
                              _selectedPlace = null;
                            });
                          },
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),

            if (_selectedPlace != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.check_circle, size: 16, color: colors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Map pin set (${_selectedPlace!.point.latitude.toStringAsFixed(4)}, '
                      '${_selectedPlace!.point.longitude.toStringAsFixed(4)})',
                      style: text.bodySmall?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],

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
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _onCopyCodeTapped,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: Text(
                            _joinCode!,
                            style: text.displaySmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 8,
                              color: colors.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _onCopyCodeTapped,
                              icon: Icon(
                                _copiedRecently
                                    ? Icons.check_rounded
                                    : Icons.copy_rounded,
                                size: 18,
                              ),
                              label: Text(
                                _copiedRecently ? 'Copied' : 'Copy code',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: _onShareRideTapped,
                              icon: const Icon(Icons.share_rounded, size: 18),
                              label: const Text('Share ride'),
                            ),
                          ),
                        ],
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
