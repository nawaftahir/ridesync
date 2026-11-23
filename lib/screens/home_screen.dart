import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ridesync/models/active_ride.dart';
import 'package:ridesync/models/auth_session.dart';
import 'package:ridesync/screens/host_ride_screen.dart';
import 'package:ridesync/screens/join_ride_screen.dart';
import 'package:ridesync/screens/login_screen.dart';
import 'package:ridesync/screens/main_screen.dart';
import 'package:ridesync/services/app_preferences.dart';
import 'package:ridesync/services/deep_link_service.dart';
import 'package:ridesync/services/map_search_service.dart';
import 'package:ridesync/services/ride_api_service.dart';
import 'package:ridesync/utils/ride_share.dart';

// First screen shown when opening RideSync as a guest user.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    this.deepLinkService = const DeepLinkService(),
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final DeepLinkService deepLinkService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AppPreferences _prefs = AppPreferences();
  String _serverUrl = AppPreferences.buildApiBaseUrl;
  String _riderName = AppPreferences.defaultRiderName;
  RideApiService? _apiService;
  MapSearchService? _searchService;
  ActiveRide? _resumableRide;
  StreamSubscription<Uri>? _deepLinkSub;
  bool _isHandlingDeepLink = false;
  bool _didAutoEnterSignedIn = false;

  @override
  void initState() {
    super.initState();
    _apiService = RideApiService(baseUrl: _serverUrl);
    _searchService = MapSearchService();
    _loadPrefsAndVerifySavedRide();
    _listenDeepLinks();
  }

  @override
  void dispose() {
    _deepLinkSub?.cancel();
    _apiService?.dispose();
    _searchService?.dispose();
    super.dispose();
  }

  Future<void> _loadPrefsAndVerifySavedRide() async {
    try {
      final savedUrl = await _prefs.loadServerUrl();
      final savedName = await _prefs.loadRiderName();
      final savedSession = await _prefs.loadAuthSession();
      final savedRide = await _prefs.loadActiveRide();
      if (!mounted) return;

      if (savedName != null && savedName.trim().isNotEmpty) {
        _riderName = savedName.trim();
      }
      if (savedUrl != null &&
          savedUrl.trim().isNotEmpty &&
          savedUrl != _serverUrl) {
        _apiService?.dispose();
        _serverUrl = savedUrl.trim();
        _apiService = RideApiService(baseUrl: _serverUrl);
      }

      if (savedSession != null) {
        _apiService?.authToken = savedSession.accessToken;
        _riderName = savedSession.user.name;
        if (!_didAutoEnterSignedIn) {
          _didAutoEnterSignedIn = true;
          ActiveRide? liveRide;
          if (savedRide != null && await _verifyRideIsStillLive(savedRide)) {
            liveRide = savedRide;
          } else if (savedRide != null) {
            await _prefs.clearActiveRide();
          }
          if (!mounted) return;
          await _enterMainApp(
            initialRide: liveRide,
            initialSession: savedSession,
            initialTabIndex: liveRide != null ? 0 : 1,
          );
          return;
        }
      } else {
        _apiService?.authToken = null;
      }

      if (savedRide != null) {
        final stillLive = await _verifyRideIsStillLive(savedRide);
        if (!mounted) return;
        if (stillLive) {
          setState(() => _resumableRide = savedRide);
        } else {
          await _prefs.clearActiveRide();
        }
      }
    } catch (_) {
      // Ignore storage/network errors on startup; stay cleanly on Home.
    }
  }

  Future<bool> _verifyRideIsStillLive(ActiveRide ride) async {
    final api = _apiService;
    if (api == null || !api.isEnabled || ride.currentUserId == null) {
      return false;
    }
    try {
      await api.fetchPositions(ride.joinCode);
      return true;
    } on RideApiException catch (error) {
      if (error.statusCode == 404 || error.statusCode == 410) {
        return false;
      }
      // Keep resumable only if network is temporarily unreachable.
      return true;
    } catch (_) {
      return false;
    }
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
    _isHandlingDeepLink = true;
    try {
      final joined = await Navigator.of(context).push<ActiveRide>(
        MaterialPageRoute(
          builder: (_) => JoinRideScreen(
            apiService: _apiService,
            riderName: _riderName,
            initialCode: code,
            autoJoin: true,
          ),
        ),
      );
      if (!mounted || joined == null) return;
      await _enterMainApp(initialRide: joined, initialTabIndex: 0);
    } finally {
      _isHandlingDeepLink = false;
    }
  }

  Future<void> _enterMainApp({
    ActiveRide? initialRide,
    AuthSession? initialSession,
    required int initialTabIndex,
  }) async {
    if (initialRide != null) {
      await _prefs.saveActiveRide(initialRide);
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MainScreen(
          initialActiveRide: initialRide,
          initialAuthSession: initialSession,
          initialTabIndex: initialTabIndex,
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
        ),
      ),
    );
    if (mounted) {
      _loadPrefsAndVerifySavedRide();
    }
  }

  Future<void> _openLogin() async {
    final session = await Navigator.of(context).push<AuthSession>(
      MaterialPageRoute(builder: (_) => LoginScreen(apiService: _apiService)),
    );
    if (!mounted || session == null) return;
    _apiService?.authToken = session.accessToken;
    _riderName = session.user.name;
    _didAutoEnterSignedIn = true;
    await _enterMainApp(initialSession: session, initialTabIndex: 1);
  }

  Future<void> _openHostRide() async {
    final ride = await Navigator.of(context).push<ActiveRide>(
      MaterialPageRoute(
        builder: (_) => HostRideScreen(
          apiService: _apiService,
          searchService: _searchService,
          hostName: _riderName,
        ),
      ),
    );
    if (!mounted || ride == null) return;
    await _enterMainApp(initialRide: ride, initialTabIndex: 0);
  }

  Future<void> _openJoinRide() async {
    final ride = await Navigator.of(context).push<ActiveRide>(
      MaterialPageRoute(
        builder: (_) =>
            JoinRideScreen(apiService: _apiService, riderName: _riderName),
      ),
    );
    if (!mounted || ride == null) return;
    await _enterMainApp(initialRide: ride, initialTabIndex: 0);
  }

  Future<void> _dismissSavedRide() async {
    setState(() => _resumableRide = null);
    await _prefs.clearActiveRide();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final resumable = _resumableRide;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Icon(
                    Icons.two_wheeler_rounded,
                    size: 48,
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'RideSync',
                textAlign: TextAlign.center,
                style: textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Live convoy tracking for group rides',
                textAlign: TextAlign.center,
                style: textTheme.bodyLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),

              if (resumable != null) ...[
                Card(
                  color: colors.primaryContainer,
                  margin: const EdgeInsets.only(bottom: 18),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(
                          Icons.navigation_rounded,
                          color: colors.onPrimaryContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Active ride · ${resumable.joinCode}',
                                style: textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: colors.onPrimaryContainer,
                                ),
                              ),
                              Text(
                                resumable.destination,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: colors.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: _dismissSavedRide,
                          child: const Text('Dismiss'),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 38),
                          ),
                          onPressed: () => _enterMainApp(
                            initialRide: resumable,
                            initialTabIndex: 0,
                          ),
                          child: const Text('Resume'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              FilledButton.icon(
                onPressed: _openHostRide,
                icon: const Icon(Icons.add_road),
                label: const Text('Host a ride'),
              ),
              const SizedBox(height: 12),

              OutlinedButton.icon(
                onPressed: _openJoinRide,
                icon: const Icon(Icons.group_add),
                label: const Text('Join with a code'),
              ),
              const SizedBox(height: 12),

              FilledButton.tonalIcon(
                onPressed: () => _enterMainApp(initialTabIndex: 0),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Explore live map'),
              ),
              const Spacer(),

              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: () => _enterMainApp(initialTabIndex: 2),
                    icon: const Icon(Icons.groups_outlined, size: 18),
                    label: const Text('Crews'),
                  ),
                  Text('·', style: TextStyle(color: colors.outline)),
                  TextButton.icon(
                    onPressed: _openLogin,
                    icon: const Icon(Icons.person_outline, size: 18),
                    label: const Text('Sign up or log in'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
