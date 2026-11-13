import 'package:flutter/material.dart';
import 'package:ridesync/models/active_ride.dart';
import 'package:ridesync/repositories/ride_repository.dart';
import 'package:ridesync/repositories/rider_repository.dart';
import 'package:ridesync/screens/group_screen.dart';
import 'package:ridesync/screens/host_ride_screen.dart';
import 'package:ridesync/screens/join_ride_screen.dart';
import 'package:ridesync/screens/profile_screen.dart';
import 'package:ridesync/screens/ride_map_screen.dart';
import 'package:ridesync/screens/rides_screen.dart';
import 'package:ridesync/services/location_service.dart';

// Main app shell holding the 4-tab bottom bar and the active ride state.
class MainScreen extends StatefulWidget {
  const MainScreen({
    super.key,
    this.rideRepository = const RideRepository(),
    this.riderRepository = const RiderRepository(),
    this.locationService = const LocationService(),
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
  });

  final RideRepository rideRepository;
  final RiderRepository riderRepository;
  final LocationService locationService;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  ActiveRide? _activeRide;

  @override
  void initState() {
    super.initState();
    // Start with a mock active ride so Week 1 shows the live map layout.
    if (widget.rideRepository.rides.isNotEmpty) {
      final sample = widget.rideRepository.rides.first;
      _activeRide = ActiveRide(
        joinCode: sample.code,
        destination: sample.destination,
        isHost: true,
        distanceKm: sample.distanceKm,
      );
    }
  }

  // Opens HostRideScreen or JoinRideScreen and switches to Map when a ride starts.
  Future<void> _openRideFlow(Widget screen) async {
    final ride = await Navigator.of(context)
        .push<ActiveRide>(MaterialPageRoute(builder: (_) => screen));
    if (!mounted || ride == null) return;
    setState(() {
      _activeRide = ride;
      _selectedIndex = 0;
    });
  }

  void _endRide() {
    setState(() {
      _activeRide = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      // IndexedStack keeps each tab alive when switching (so the map keeps its position).
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          RideMapScreen(
            activeRide: _activeRide,
            onEndRide: _endRide,
            onHostRide: () => _openRideFlow(const HostRideScreen()),
            onJoinRide: () => _openRideFlow(const JoinRideScreen()),
            riderRepository: widget.riderRepository,
            locationService: widget.locationService,
          ),
          RidesScreen(
            activeRide: _activeRide,
            onOpenMap: () => setState(() => _selectedIndex = 0),
            onHostRide: () => _openRideFlow(const HostRideScreen()),
            onJoinRide: () => _openRideFlow(const JoinRideScreen()),
            rideRepository: widget.rideRepository,
          ),
          GroupScreen(
            activeRide: _activeRide,
            riders: widget.riderRepository.positions,
          ),
          ProfileScreen(
            rideRepository: widget.rideRepository,
            themeMode: widget.themeMode,
            onThemeModeChanged: widget.onThemeModeChanged,
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
