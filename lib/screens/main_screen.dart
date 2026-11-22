import 'package:flutter/material.dart';
import 'package:ridesync/models/active_ride.dart';
import 'package:ridesync/models/rider_position.dart';
import 'package:ridesync/repositories/ride_repository.dart';
import 'package:ridesync/repositories/rider_repository.dart';
import 'package:ridesync/screens/group_screen.dart';
import 'package:ridesync/screens/host_ride_screen.dart';
import 'package:ridesync/screens/join_ride_screen.dart';
import 'package:ridesync/screens/profile_screen.dart';
import 'package:ridesync/screens/ride_map_screen.dart';
import 'package:ridesync/screens/rides_screen.dart';
import 'package:ridesync/services/location_service.dart';
import 'package:ridesync/services/ride_api_service.dart';

// Main app shell holding the 4-tab bottom bar and the active ride state.
class MainScreen extends StatefulWidget {
  const MainScreen({
    super.key,
    this.rideRepository = const RideRepository(),
    this.riderRepository = const RiderRepository(),
    this.locationService = const LocationService(),
    this.apiService,
    this.initialServerUrl = const String.fromEnvironment('API_BASE_URL'),
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
  });

  final RideRepository rideRepository;
  final RiderRepository riderRepository;
  final LocationService locationService;
  final RideApiService? apiService;
  final String initialServerUrl;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const String _defaultRiderName = 'Nawaf';

  int _selectedIndex = 0;
  ActiveRide? _activeRide;
  List<RiderPosition> _liveRiders = const [];
  late String _serverUrl;
  RideApiService? _ownedApiService;

  RideApiService get _apiService => widget.apiService ?? _ownedApiService!;

  @override
  void initState() {
    super.initState();
    _serverUrl = widget.apiService?.cleanBaseUrl ?? widget.initialServerUrl;
    if (widget.apiService == null) {
      _ownedApiService = RideApiService(baseUrl: _serverUrl);
    }

    // Start with a mock active ride only when no live backend URL is configured.
    if (!_apiService.isEnabled && widget.rideRepository.rides.isNotEmpty) {
      final sample = widget.rideRepository.rides.first;
      _activeRide = ActiveRide(
        joinCode: sample.code,
        destination: sample.destination,
        isHost: true,
        distanceKm: sample.distanceKm,
      );
    }
  }

  @override
  void dispose() {
    _ownedApiService?.dispose();
    super.dispose();
  }

  void _updateServerUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed == _serverUrl) return;
    _ownedApiService?.dispose();
    _ownedApiService = RideApiService(baseUrl: trimmed);
    setState(() {
      _serverUrl = _ownedApiService!.cleanBaseUrl;
      _activeRide = null;
      _liveRiders = const [];
    });
  }

  // Opens HostRideScreen or JoinRideScreen and switches to Map when a ride starts.
  Future<void> _openRideFlow(Widget screen) async {
    final ride = await Navigator.of(context)
        .push<ActiveRide>(MaterialPageRoute(builder: (_) => screen));
    if (!mounted || ride == null) return;
    setState(() {
      _activeRide = ride;
      _liveRiders = const [];
      _selectedIndex = 0;
    });
  }

  void _endRide() {
    final ending = _activeRide;
    setState(() {
      _activeRide = null;
      _liveRiders = const [];
    });

    if (ending != null &&
        ending.isHost &&
        ending.currentUserId != null &&
        _apiService.isEnabled) {
      _notifyBackendEndRide(ending);
    }
  }

  Future<void> _notifyBackendEndRide(ActiveRide ride) async {
    try {
      await _apiService.endRide(
        code: ride.joinCode,
        hostId: ride.currentUserId!,
      );
    } on RideApiException catch (error) {
      if (!mounted) return;
      // 404/409 simply means the ride was already missing or ended.
      if (error.statusCode == 404 || error.statusCode == 409) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('Ended locally (server error: ${error.message})'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final groupRiders =
        (_apiService.isEnabled && _activeRide?.currentUserId != null)
        ? _liveRiders
        : widget.riderRepository.positions;

    return Scaffold(
      // IndexedStack keeps each tab alive when switching (so the map keeps its position).
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          RideMapScreen(
            activeRide: _activeRide,
            onEndRide: _endRide,
            onHostRide: () => _openRideFlow(
              HostRideScreen(
                apiService: _apiService,
                hostName: _defaultRiderName,
              ),
            ),
            onJoinRide: () => _openRideFlow(
              JoinRideScreen(
                apiService: _apiService,
                riderName: _defaultRiderName,
              ),
            ),
            riderRepository: widget.riderRepository,
            locationService: widget.locationService,
            apiService: _apiService,
            onRidersUpdated: (riders) {
              if (!mounted) return;
              setState(() {
                _liveRiders = riders;
              });
            },
          ),
          RidesScreen(
            activeRide: _activeRide,
            onOpenMap: () => setState(() => _selectedIndex = 0),
            onHostRide: () => _openRideFlow(
              HostRideScreen(
                apiService: _apiService,
                hostName: _defaultRiderName,
              ),
            ),
            onJoinRide: () => _openRideFlow(
              JoinRideScreen(
                apiService: _apiService,
                riderName: _defaultRiderName,
              ),
            ),
            rideRepository: widget.rideRepository,
          ),
          GroupScreen(activeRide: _activeRide, riders: groupRiders),
          ProfileScreen(
            rideRepository: widget.rideRepository,
            themeMode: widget.themeMode,
            onThemeModeChanged: widget.onThemeModeChanged,
            serverUrl: _serverUrl,
            onServerUrlChanged: widget.apiService == null
                ? _updateServerUrl
                : null,
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'Map',
            ),
            NavigationDestination(
              icon: Icon(Icons.schedule_outlined),
              selectedIcon: Icon(Icons.schedule),
              label: 'Rides',
            ),
            NavigationDestination(
              icon: Icon(Icons.groups_outlined),
              selectedIcon: Icon(Icons.groups),
              label: 'Group',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
