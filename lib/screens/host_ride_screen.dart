import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:ridesync/models/active_ride.dart';
import 'package:ridesync/services/map_search_service.dart';
import 'package:ridesync/services/ride_api_service.dart';
import 'package:ridesync/utils/ride_share.dart';

class HostRideScreen extends StatefulWidget {
  const HostRideScreen({
    super.key,
    this.apiService,
    this.searchService,
    this.hostName = 'Nawaf',
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
  late final TextEditingController _destinationController =
      TextEditingController(text: widget.initialPlace?.displayName ?? '');

  late PlaceResult? _selectedPlace = widget.initialPlace;
  Timer? _searchDebounce;
  int _searchRequestId = 0;
  bool _isSearching = false;
  List<PlaceResult> _suggestions = const [];

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

    final search = widget.searchService;
    if (search == null) return;

    _searchDebounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.length < 2) {
      _searchRequestId++;
      setState(() {
        _isSearching = false;
        _suggestions = const [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      final reqId = ++_searchRequestId;
      final results = await search.searchPlaces(
        trimmed,
        near: widget.nearPoint,
      );
      if (!mounted || reqId != _searchRequestId) return;
      setState(() {
        _suggestions = results;
        _isSearching = false;
      });
    });
  }

  void _pickSuggestion(PlaceResult place) {
    _searchDebounce?.cancel();
    _searchRequestId++;
    _destinationController.text = place.displayName;
    setState(() {
      _selectedPlace = place;
      _suggestions = const [];
      _isSearching = false;
    });
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
      _suggestions = const [];
    });
    try {
      final ride = await api.createRide(
        destination: destination,
        destLat: point?.latitude,
        destLng: point?.longitude,
        distanceKm: matchedInitialRoute?.distanceKm,
        durationMinutes: matchedInitialRoute?.durationMinutes,
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
    Navigator.of(context).pop(
      _createdRide ??
          ActiveRide(
            joinCode: _joinCode!,
            destination: _destinationController.text.trim(),
            destLat: _selectedPlace?.point.latitude,
            destLng: _selectedPlace?.point.longitude,
            isHost: true,
            currentUserName: widget.hostName,
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
      onShareOverride: widget.onShareOverride,
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _copiedResetTimer?.cancel();
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
            Text('Where are you going?', style: text.titleMedium),
            const SizedBox(height: 12),

            TextField(
              controller: _destinationController,
              textCapitalization: TextCapitalization.words,
              onChanged: _onDestinationChanged,
              decoration: InputDecoration(
                hintText: 'Search a place, road, or landmark',
                prefixIcon: const Icon(Icons.location_on_outlined),
                suffixIcon: _isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : (_destinationController.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _destinationController.clear();
                                _onDestinationChanged('');
                              },
                            )),
                border: const OutlineInputBorder(),
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

            if (_suggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (int i = 0; i < _suggestions.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.location_on_outlined,
                          color: colors.primary,
                        ),
                        title: Text(
                          _suggestions[i].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: _suggestions[i].subtitle.isEmpty
                            ? null
                            : Text(
                                _suggestions[i].subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                        onTap: () => _pickSuggestion(_suggestions[i]),
                      ),
                    ],
                  ],
                ),
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
