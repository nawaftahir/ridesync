# Changelog

## 2026-11-15 (experiment)
- Tried OpenFreeMap vector maps (`positron` for light, `dark` for dark mode) in place of the OpenStreetMap picture tiles, with OpenStreetMap as the fallback when offline.
- Added the `vector_map_tiles` package and set `latlong2` back to `^0.9.1`, because that package does not support `latlong2` 0.10 yet.
- Added the map credits (OpenFreeMap, OpenMapTiles, OpenStreetMap contributors) on the map.

## 2026-11-13
- Added a 4-tab bottom navigation bar (`Map`, `Rides`, `Group`, `Profile`) inside `MainScreen`, with `RidesScreen` (host/join actions + mock past rides), work-in-progress `GroupScreen`, and `ProfileScreen` (rider summary + login link).
- Redesigned `RideMapScreen` with a floating destination card, `Recenter map` button with `MapController`, mock route polyline, rider name markers, and a collapsible `"Group ride"` bottom sheet (`Live sync` pill, rider avatars, `PICKUP` / `DESTINATION` card, `End Ride` / `Leave` controls, and overflow fix for narrow screens).
- Passed active ride data between `HostRideScreen`/`JoinRideScreen` and `MainScreen` using `ActiveRide`.
- Added `LocationService` wrapping `geolocator` with Android/iOS manifest permissions, live `'You'` marker, speed pill (WIP), denied/GPS-off banners, and Android's in-app location enable prompt + widget tests (`test/location_test.dart`).
- Added an in-app `Auto` / `Light` / `Dark` theme selector on `ProfileScreen` wired through `MainScreen` and `RideSyncApp`.
- Updated `README.md`, `CONTRIBUTING.md`, and `docs/changelog.md` with current project structure, versions, and mandatory format/analyze/test checks.

## 2026-11-03 Map colors
- Map pins now use the theme colors (main color for active riders, warning color for signal lost) instead of fixed blue and red.
- The map gets darker in dark mode so it matches the rest of the app.

## 2026-11-02 Cleanup
- Removed the icon exporter tool, it was only needed to make the logo.
- README and CONTRIBUTING now show the Flutter version and `flutter pub get` after pulling.
- Fixed folder names in CONTRIBUTING (`lib/data/`, `lib/repositories/`).

## 2026-10-13 — Alpha Build Preview
- Added Host Ride screen with random 6-letter join code generator.
- Added Join Ride screen with code lookup
- Added Map screen showing OpenStreetMap tiles and mock riders in Islamabad (F-6).
- Added basic Login / Sign-up preview screen.
- Added mock ride details and GPS data inside `lib/mock/`.
- Connected Home screen buttons to all preview screens.

## 2026-10-12  Misc
- Set app display name to **RideSync** on Android and iOS.
- Added custom app launcher icons.

## 2026-10-11  Docs & Config
- Updated `.gitignore` and project documentation.

## 2026-10-05  Project Setup
- Initial Flutter project structure.
- Added dependencies for mapping, GPS, state management, and database.