import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:ridesync/models/active_ride.dart';
import 'package:ridesync/models/auth_session.dart';
import 'package:ridesync/models/ride_history.dart';
import 'package:ridesync/models/rider_position.dart';
import 'package:ridesync/models/riding_crew.dart';
import 'package:ridesync/screens/group_screen.dart';
import 'package:ridesync/screens/host_ride_screen.dart';
import 'package:ridesync/screens/join_ride_screen.dart';
import 'package:ridesync/screens/login_screen.dart';
import 'package:ridesync/screens/profile_screen.dart';
import 'package:ridesync/screens/ride_map_screen.dart';
import 'package:ridesync/screens/rides_screen.dart';
import 'package:ridesync/services/app_preferences.dart';
import 'package:ridesync/services/battery_service.dart';
import 'package:ridesync/services/deep_link_service.dart';
import 'package:ridesync/services/location_service.dart';
import 'package:ridesync/services/map_search_service.dart';
import 'package:ridesync/services/notification_service.dart';
import 'package:ridesync/services/ride_api_service.dart';
import 'package:ridesync/services/wakelock_service.dart';
import 'package:ridesync/utils/ride_share.dart';

// Main app shell holding the 4-tab bottom bar and the active ride state.
class MainScreen extends StatefulWidget {
  const MainScreen({
    super.key,
    this.locationService = const LocationService(),
    this.batteryService = const BatteryService(),
    this.notificationService = const NotificationService(),
    this.wakelockService = const WakelockService(),
    this.deepLinkService = const DeepLinkService(),
    this.apiService,
    this.mapSearchService,
    this.initialServerUrl,
    this.initialActiveRide,
    this.initialAuthSession,
    this.initialTabIndex = 0,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
  });

  final LocationService locationService;
  final BatteryService batteryService;
  final NotificationService notificationService;
  final WakelockService wakelockService;
  final DeepLinkService deepLinkService;
  final RideApiService? apiService;
  final MapSearchService? mapSearchService;
  final String? initialServerUrl;
  final ActiveRide? initialActiveRide;
  final AuthSession? initialAuthSession;
  final int initialTabIndex;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final AppPreferences _prefs = AppPreferences();

  int _selectedIndex = 0;
  ActiveRide? _activeRide;
  AuthSession? _authSession;
  RideHistoryData? _rideHistory;
  bool _isLoadingHistory = false;
  String? _historyError;
  List<RiderPosition> _liveRiders = const [];
  String _riderName = AppPreferences.defaultRiderName;
  late String _serverUrl;
  RideApiService? _ownedApiService;
  MapSearchService? _ownedSearchService;
  StreamSubscription<Uri>? _deepLinkSub;
  bool _isHandlingDeepLink = false;

  RideApiService get _apiService => widget.apiService ?? _ownedApiService!;
  MapSearchService get _searchService =>
      widget.mapSearchService ?? _ownedSearchService!;

  @override
  void initState() {
    super.initState();
    _activeRide = widget.initialActiveRide;
    _authSession = widget.initialAuthSession;
    if (_authSession != null) {
      _riderName = _authSession!.user.name;
    }
    _selectedIndex = _activeRide != null ? 0 : widget.initialTabIndex;
    _serverUrl =
        widget.apiService?.cleanBaseUrl ??
        widget.initialServerUrl ??
        AppPreferences.buildApiBaseUrl;
    if (widget.apiService == null) {
      _ownedApiService = RideApiService(
        baseUrl: _serverUrl,
        authToken: _authSession?.accessToken,
      );
    } else if (_authSession != null) {
      widget.apiService!.authToken = _authSession!.accessToken;
    }
    if (widget.mapSearchService == null) {
      _ownedSearchService = MapSearchService();
    }

    _listenDeepLinks();
    if (widget.apiService == null && widget.initialServerUrl == null) {
      _loadSavedSettings();
    } else if (widget.initialActiveRide == null) {
      _restoreSavedRideOnly();
    }
    if (_authSession != null) {
      unawaited(_verifyAuthSession());
      unawaited(_refreshRideHistory());
    }
  }

  Future<void> _restoreSavedRideOnly() async {
    final savedRide = await _prefs.loadActiveRide();
    if (!mounted || savedRide == null || _activeRide != null) return;
    setState(() {
      _activeRide = savedRide;
      _selectedIndex = 0;
    });
  }

  void _listenDeepLinks() {
    widget.deepLinkService.getInitialUri().then((uri) {
      if (mounted && uri != null) {
        _handleIncomingUri(uri);
      }
    });
    _deepLinkSub = widget.deepLinkService.uriStream().listen((uri) {
      if (mounted) {
        _handleIncomingUri(uri);
      }
    }, onError: (_) {});
  }

  Future<void> _handleIncomingUri(Uri uri) async {
    final code = parseRideCodeFromUri(uri);
    if (code == null || _isHandlingDeepLink) return;
    if (_activeRide?.joinCode == code) {
      setState(() => _selectedIndex = 0);
      return;
    }

    _isHandlingDeepLink = true;
    try {
      await _openRideFlow(
        JoinRideScreen(
          apiService: _apiService,
          riderName: _riderName,
          initialCode: code,
          autoJoin: true,
        ),
      );
    } finally {
      _isHandlingDeepLink = false;
    }
  }

  Future<void> _loadSavedSettings() async {
    try {
      final savedUrl = await _prefs.loadServerUrl();
      final savedName = await _prefs.loadRiderName();
      final savedSession = _authSession == null
          ? await _prefs.loadAuthSession()
          : null;
      final savedRide = widget.initialActiveRide == null
          ? await _prefs.loadActiveRide()
          : null;
      if (!mounted) return;

      var changed = false;
      if (savedSession != null) {
        _authSession = savedSession;
        _riderName = savedSession.user.name;
        changed = true;
      } else if (savedName != null &&
          savedName.trim().isNotEmpty &&
          savedName != _riderName) {
        _riderName = savedName.trim();
        changed = true;
      }
      if (savedUrl != null &&
          savedUrl.trim().isNotEmpty &&
          savedUrl != _serverUrl) {
        _ownedApiService?.dispose();
        _ownedApiService = RideApiService(
          baseUrl: savedUrl,
          authToken: _authSession?.accessToken,
        );
        _serverUrl = _ownedApiService!.cleanBaseUrl;
        changed = true;
      } else if (_authSession != null) {
        _apiService.authToken = _authSession!.accessToken;
      }
      if (savedRide != null && _activeRide == null) {
        _activeRide = savedRide;
        _selectedIndex = 0;
        changed = true;
      }
      if (changed) {
        setState(() {});
      }
      if (savedSession != null) {
        unawaited(_verifyAuthSession());
        unawaited(_refreshRideHistory());
      }
    } catch (_) {
      // Ignore storage errors on unsupported platforms / headless tests.
    }
  }

  Future<void> _refreshRideHistory() async {
    if (_authSession == null || !_apiService.isEnabled) return;
    if (mounted) {
      setState(() {
        _isLoadingHistory = true;
        _historyError = null;
      });
    }
    try {
      final data = await _apiService.fetchRideHistory();
      if (!mounted) return;
      setState(() {
        _rideHistory = data;
        _isLoadingHistory = false;
        _historyError = null;
      });
    } on RideApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingHistory = false;
        _historyError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingHistory = false;
        _historyError = 'Could not load ride history right now.';
      });
    }
  }

  Future<void> _verifyAuthSession() async {
    if (_authSession == null || !_apiService.isEnabled) return;
    try {
      final me = await _apiService.fetchMe();
      if (!mounted || _authSession == null) return;
      if (me.name != _authSession!.user.name || me.name != _riderName) {
        final refreshed = _authSession!.copyWith(user: me);
        setState(() {
          _authSession = refreshed;
          _riderName = me.name;
        });
        unawaited(_prefs.saveAuthSession(refreshed));
      }
    } on RideApiException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 401) {
        _apiService.authToken = null;
        setState(() {
          _authSession = null;
        });
        unawaited(_prefs.clearAuthSession());
      }
    } catch (_) {
      // Ignore transient offline failures; keep cached session.
    }
  }

  Future<void> _openLogin() async {
    final session = await Navigator.of(context).push<AuthSession>(
      MaterialPageRoute(builder: (_) => LoginScreen(apiService: _apiService)),
    );
    if (!mounted || session == null) return;
    _apiService.authToken = session.accessToken;
    setState(() {
      _authSession = session;
      _riderName = session.user.name;
    });
    unawaited(_refreshRideHistory());
  }

  Future<void> _logout() async {
    try {
      await _apiService.logout();
    } catch (_) {
      // Clear local session even if server is unreachable.
    }
    _apiService.authToken = null;
    await _prefs.clearAuthSession();
    if (!mounted) return;
    setState(() {
      _authSession = null;
      _rideHistory = null;
      _historyError = null;
    });
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _deepLinkSub?.cancel();
    _ownedApiService?.dispose();
    _ownedSearchService?.dispose();
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
    _prefs.saveServerUrl(_serverUrl).catchError((_) {});
  }

  void _updateRiderName(String rawName) {
    final clean = rawName.trim();
    if (clean.isEmpty || clean == _riderName) return;
    final session = _authSession;
    setState(() {
      _riderName = clean;
      if (session != null) {
        _authSession = session.copyWith(
          user: session.user.copyWith(name: clean),
        );
      }
    });
    if (_authSession != null) {
      _prefs.saveAuthSession(_authSession!).catchError((_) {});
      if (_apiService.isEnabled) {
        unawaited(
          _apiService.updateMyName(clean).catchError((_) => _authSession!.user),
        );
      }
    } else {
      _prefs.saveRiderName(clean).catchError((_) {});
    }
  }

  // Opens HostRideScreen or JoinRideScreen and switches to Map when a ride starts.
  Future<void> _openRideFlow(Widget screen, {RidingCrew? crew}) async {
    final pickedRide = await Navigator.of(context)
        .push<ActiveRide>(MaterialPageRoute(builder: (_) => screen));
    if (!mounted || pickedRide == null) return;
    final ride = crew == null
        ? pickedRide
        : pickedRide.copyWith(crewName: crew.name, crewMembers: crew.members);
    setState(() {
      _activeRide = ride;
      _liveRiders = const [];
      _selectedIndex = 0;
    });
    _prefs.saveActiveRide(ride).catchError((_) {});
  }

  Future<void> _openHostRide({
    String? initialDestination,
    PlaceResult? initialPlace,
    RoutePreview? initialRoute,
    LatLng? nearPoint,
    RidingCrew? crew,
  }) {
    return _openRideFlow(
      HostRideScreen(
        apiService: _apiService,
        searchService: _searchService,
        hostName: _riderName,
        isSignedIn: _authSession != null,
        initialDestination: initialDestination,
        initialPlace: initialPlace,
        initialRoute: initialRoute,
        nearPoint: nearPoint,
      ),
      crew: crew,
    );
  }

  void _endRide() {
    final ending = _activeRide;
    setState(() {
      _activeRide = null;
      _liveRiders = const [];
    });
    _prefs.clearActiveRide().catchError((_) {});

    if (ending != null &&
        ending.isHost &&
        ending.currentUserId != null &&
        _apiService.isEnabled) {
      _notifyBackendEndRide(ending);
    } else if (_authSession != null) {
      unawaited(_refreshRideHistory());
    }
  }

  Future<void> _notifyBackendEndRide(ActiveRide ride) async {
    try {
      await _apiService.endRide(
        code: ride.joinCode,
        hostId: ride.currentUserId!,
      );
      if (mounted && _authSession != null) {
        unawaited(_refreshRideHistory());
      }
    } on RideApiException catch (error) {
      if (!mounted) return;
      // 404/409 simply means the ride was already missing or ended.
      if (error.statusCode == 404 || error.statusCode == 409) {
        if (_authSession != null) unawaited(_refreshRideHistory());
        return;
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('Ended locally (server error: ${error.message})'),
        ),
      );
    }
  }

  Future<void> _rideAgain(PastRide pastRide) {
    final point = pastRide.destinationPoint;
    final place = point == null
        ? null
        : PlaceResult(name: pastRide.destination, subtitle: '', point: point);
    return _openHostRide(
      initialDestination: pastRide.destination,
      initialPlace: place,
    );
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
            onHostRide: () => _openHostRide(),
            onHostRideWithPlace: (place, route, nearPoint) => _openHostRide(
              initialPlace: place,
              initialRoute: route,
              nearPoint: nearPoint,
            ),
            onJoinRide: () => _openRideFlow(
              JoinRideScreen(
                apiService: _apiService,
                riderName: _riderName,
                isSignedIn: _authSession != null,
              ),
            ),
            locationService: widget.locationService,
            batteryService: widget.batteryService,
            notificationService: widget.notificationService,
            wakelockService: widget.wakelockService,
            apiService: _apiService,
            searchService: _searchService,
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
            onHostRide: () => _openHostRide(),
            onJoinRide: () => _openRideFlow(
              JoinRideScreen(
                apiService: _apiService,
                riderName: _riderName,
                isSignedIn: _authSession != null,
              ),
            ),
            isSignedIn: _authSession != null,
            history: _rideHistory,
            isLoadingHistory: _isLoadingHistory,
            historyError: _historyError,
            onRefreshHistory: _refreshRideHistory,
            onOpenLogin: _openLogin,
            onRideAgain: _rideAgain,
          ),
          GroupScreen(
            activeRide: _activeRide,
            riders: _liveRiders,
            serverBaseUrl: _apiService.cleanBaseUrl,
            onHostRide: () => _openHostRide(),
            onHostCrewRide: (crew) => _openHostRide(crew: crew),
          ),
          ProfileScreen(
            themeMode: widget.themeMode,
            onThemeModeChanged: widget.onThemeModeChanged,
            riderName: _riderName,
            onRiderNameChanged: _updateRiderName,
            serverUrl: _serverUrl,
            authSession: _authSession,
            stats: _rideHistory?.stats,
            onOpenLogin: _openLogin,
            onLogout: _logout,
            onServerUrlChanged:
                widget.apiService == null &&
                    (kDebugMode || _serverUrl.trim().isEmpty)
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
