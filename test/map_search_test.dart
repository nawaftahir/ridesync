import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:ridesync/screens/main_screen.dart';
import 'package:ridesync/services/location_service.dart';
import 'package:ridesync/services/map_search_service.dart';
import 'package:ridesync/services/ride_api_service.dart';
import 'package:ridesync/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_maplibre_platform.dart';

class _IdleLocationService extends LocationService {
  const _IdleLocationService();

  @override
  Future<LocationStatus> ensurePermission() async => LocationStatus.ready;

  @override
  Future<GpsFix?> getLastKnownFix() async =>
      const GpsFix(point: LatLng(33.7215, 73.0433), speedKmh: 0);

  @override
  Stream<GpsFix> fixStream() => const Stream<GpsFix>.empty();

  @override
  Stream<bool> serviceEnabledStream() => const Stream<bool>.empty();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FakeMapLibrePlatform.register();
  });

  test(
    'MapSearchService parses Photon search, reverse, and OSRM route',
    () async {
      final client = MockClient((request) async {
        if (request.url.host == 'photon.komoot.io' &&
            request.url.path == '/api/') {
          expect(request.url.queryParameters['q'], 'Daman');
          expect(request.url.queryParameters['lat'], '33.72150');
          return http.Response(
            jsonEncode({
              'features': [
                {
                  'geometry': {
                    'coordinates': [73.0558, 33.7394],
                  },
                  'properties': {
                    'name': 'Daman-e-Koh',
                    'city': 'Islamabad',
                    'country': 'Pakistan',
                  },
                },
                {
                  'geometry': {
                    'coordinates': [73.0558, 33.7394],
                  },
                  'properties': {
                    'name': 'Daman-e-Koh',
                    'city': 'Islamabad',
                    'country': 'Pakistan',
                  },
                },
              ],
            }),
            200,
          );
        }
        if (request.url.host == 'photon.komoot.io' &&
            request.url.path == '/reverse') {
          return http.Response(
            jsonEncode({
              'features': [
                {
                  'geometry': {
                    'coordinates': [73.0558, 33.7394],
                  },
                  'properties': {
                    'name': 'Pir Sohawa Road',
                    'city': 'Islamabad',
                  },
                },
              ],
            }),
            200,
          );
        }
        if (request.url.host == 'router.project-osrm.org') {
          return http.Response(
            jsonEncode({
              'routes': [
                {
                  'distance': 8460,
                  'duration': 1020,
                  'geometry': {
                    'coordinates': [
                      [73.0433, 33.7215],
                      [73.0500, 33.7300],
                      [73.0558, 33.7394],
                    ],
                  },
                },
              ],
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final search = MapSearchService(client: client);
      final places = await search.searchPlaces(
        'Daman',
        near: const LatLng(33.7215, 73.0433),
      );
      expect(places, hasLength(1));
      expect(places.first.name, 'Daman-e-Koh');
      expect(places.first.subtitle, 'Islamabad, Pakistan');
      expect(places.first.point.latitude, closeTo(33.7394, 1e-4));

      final reversed = await search.reverseGeocode(
        const LatLng(33.7394, 73.0558),
      );
      expect(reversed.name, 'Pir Sohawa Road');

      final route = await search.fetchRoute(
        from: const LatLng(33.7215, 73.0433),
        to: const LatLng(33.7394, 73.0558),
      );
      expect(route.isFallback, isFalse);
      expect(route.points, hasLength(3));
      expect(route.distanceKm, 8.5);
      expect(route.durationMinutes, 17);
    },
  );

  test(
    'MapSearchService falls back to straight line when OSRM fails',
    () async {
      final offlineClient = MockClient((_) async => http.Response('Down', 503));
      final search = MapSearchService(client: offlineClient);

      final route = await search.fetchRoute(
        from: const LatLng(33.7215, 73.0433),
        to: const LatLng(33.7394, 73.0558),
      );
      expect(route.isFallback, isTrue);
      expect(route.points, hasLength(2));
      expect(route.distanceKm, greaterThan(1.5));
      expect(route.durationMinutes, greaterThanOrEqualTo(1));
    },
  );

  testWidgets(
    'Searching on Map previews route and sends real destination coords to backend',
    (tester) async {
      Map<String, dynamic>? createdPayload;

      final searchClient = MockClient((request) async {
        if (request.url.host == 'photon.komoot.io') {
          return http.Response(
            jsonEncode({
              'features': [
                {
                  'geometry': {
                    'coordinates': [73.0558, 33.7394],
                  },
                  'properties': {'name': 'Daman-e-Koh', 'city': 'Islamabad'},
                },
              ],
            }),
            200,
          );
        }
        if (request.url.host == 'router.project-osrm.org') {
          return http.Response(
            jsonEncode({
              'routes': [
                {
                  'distance': 9100,
                  'duration': 1140,
                  'geometry': {
                    'coordinates': [
                      [73.0433, 33.7215],
                      [73.0558, 33.7394],
                    ],
                  },
                },
              ],
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final apiClient = MockClient((request) async {
        if (request.method == 'POST' && request.url.path == '/rides') {
          createdPayload = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'code': 'REAL77',
              'destination': createdPayload!['destination'],
              'dest_lat': createdPayload!['dest_lat'],
              'dest_lng': createdPayload!['dest_lng'],
              'host_id': 5,
              'host_name': 'Nawaf',
              'started_at': '2026-11-22T12:00:00Z',
            }),
            201,
          );
        }
        if (request.url.path == '/rides/REAL77/positions') {
          return http.Response(
            jsonEncode({
              'code': 'REAL77',
              'destination': 'Daman-e-Koh, Islamabad',
              'dest_lat': 33.7394,
              'dest_lng': 73.0558,
              'is_ended': false,
              'ended_at': null,
              'riders': const [],
            }),
            200,
          );
        }
        if (request.url.path == '/rides/REAL77/position') {
          return http.Response(
            jsonEncode({
              'code': 'REAL77',
              'user_id': 5,
              'updated_at': '2026-11-22T12:00:01Z',
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final api = RideApiService(
        baseUrl: 'https://api.example.com',
        client: apiClient,
      );
      final search = MapSearchService(client: searchClient);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MainScreen(
            apiService: api,
            mapSearchService: search,
            locationService: const _IdleLocationService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the Map search bar -> opens PlaceSearchSheet.
      await tester.tap(find.text('Where are you riding?'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Daman');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('Daman-e-Koh'), findsOneWidget);
      await tester.tap(find.text('Daman-e-Koh'));
      await tester.pumpAndSettle();

      // Preview card displays real OSRM ETA/distance and Host Ride Here CTA.
      expect(find.text('19 min · 9.1 km'), findsOneWidget);
      expect(find.text('Host Ride Here'), findsOneWidget);

      await tester.tap(find.text('Host Ride Here'));
      await tester.pumpAndSettle();

      // HostRideScreen is pre-filled with the locked map pin.
      expect(find.textContaining('Map pin set'), findsOneWidget);

      await tester.tap(find.text('Generate Join Code'));
      await tester.pumpAndSettle();
      expect(find.text('REAL77'), findsOneWidget);
      expect(createdPayload?['dest_lat'], closeTo(33.7394, 1e-4));
      expect(createdPayload?['dest_lng'], closeTo(73.0558, 1e-4));

      await tester.ensureVisible(find.text('Start Ride'));
      await tester.tap(find.text('Start Ride'));
      await tester.pumpAndSettle();
      expect(find.text('REAL77'), findsOneWidget);
      expect(find.text('19 min'), findsOneWidget);
      expect(find.text('9.1 km'), findsOneWidget);
    },
  );

  test('MapSearchService falls back to Nominatim when Photon returns empty and formats distances', () async {
    final client = MockClient((request) async {
      if (request.url.host == 'photon.komoot.io') {
        return http.Response(jsonEncode({'features': const []}), 200);
      }
      if (request.url.host == 'nominatim.openstreetmap.org') {
        return http.Response(
          jsonEncode([
            {
              'lat': '33.7294',
              'lon': '73.0931',
              'name': 'F-7 Markaz',
              'display_name': 'F-7 Markaz, Islamabad, Pakistan',
              'category': 'amenity',
              'type': 'cafe',
              'address': {'city': 'Islamabad', 'country': 'Pakistan'},
            },
          ]),
          200,
        );
      }
      return http.Response('Not found', 404);
    });

    final search = MapSearchService(client: client);
    final outcome = await search.searchPlacesOutcome(
      'F-7 Markaz',
      near: const LatLng(33.7215, 73.0433),
    );
    expect(outcome.hasError, isFalse);
    expect(outcome.usedFallback, isTrue);
    expect(outcome.results, hasLength(1));
    expect(outcome.results.first.name, 'F-7 Markaz');
    expect(outcome.results.first.category, 'cafe');

    expect(
      formatPlaceDistance(
        const LatLng(33.7215, 73.0433),
        const LatLng(33.7250, 73.0433),
      ),
      endsWith('m'),
    );
    expect(
      formatPlaceDistance(
        const LatLng(33.7215, 73.0433),
        const LatLng(33.7415, 73.0533),
      ),
      endsWith('km'),
    );
  });

  testWidgets(
    'Category chip opens search with distance badge, saves recent place, and shows offline retry',
    (tester) async {
      var offline = false;
      final searchClient = MockClient((request) async {
        if (offline) return http.Response('Offline', 503);
        if (request.url.host == 'photon.komoot.io') {
          return http.Response(
            jsonEncode({
              'features': [
                {
                  'geometry': {
                    'coordinates': [73.0558, 33.7394],
                  },
                  'properties': {
                    'name': 'PSO Fuel Station',
                    'city': 'Islamabad',
                    'osm_key': 'amenity',
                    'osm_value': 'fuel',
                  },
                },
              ],
            }),
            200,
          );
        }
        if (request.url.host == 'router.project-osrm.org') {
          return http.Response(
            jsonEncode({
              'routes': [
                {
                  'distance': 2400,
                  'duration': 300,
                  'geometry': {
                    'coordinates': [
                      [73.0433, 33.7215],
                      [73.0558, 33.7394],
                    ],
                  },
                },
              ],
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final search = MapSearchService(client: searchClient);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MainScreen(
            mapSearchService: search,
            locationService: const _IdleLocationService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap floating "Fuel" pill directly on the Map screen.
      expect(find.text('Fuel'), findsOneWidget);
      await tester.tap(find.text('Fuel'));
      await tester.pumpAndSettle();

      expect(find.text('PSO Fuel Station'), findsOneWidget);
      expect(find.text('2.3 km'), findsOneWidget);

      // Select it -> saves to Recent searches and previews route on the map.
      await tester.tap(find.text('PSO Fuel Station'));
      await tester.pumpAndSettle();
      expect(find.text('Host Ride Here'), findsOneWidget);

      // Close preview and re-open search -> Recent section shows PSO Fuel Station.
      await tester.tap(find.byTooltip('Close preview'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Where are you riding?'));
      await tester.pumpAndSettle();

      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('PSO Fuel Station'), findsOneWidget);

      // Clear recent searches.
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(find.text('Recent'), findsNothing);

      // Offline search displays Retry state cleanly.
      offline = true;
      await tester.enterText(find.byType(TextField), 'Murree');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
    },
  );
}
