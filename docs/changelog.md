# Changelog

## 2026-11-13 Theme switcher (Auto / Light / Dark)
- Added an in-app `Auto` / `Light` / `Dark` theme selector on `ProfileScreen` wired through `MainScreen` and `RideSyncApp` so riders can override system appearance directly in the app.

## 2026-11-13 Real GPS tracking
- Added `LocationService` wrapping `geolocator` to check GPS/permissions, handle denied states, trigger Android's in-app location dialog without leaving the app, and stream live coordinates and speed (`km/h`).
- Added live `'You'` marker, speed pill, permission banner with retry/settings actions, and follow-me `Recenter` behavior to `RideMapScreen`.
- Configured Android location/internet permissions in `AndroidManifest.xml` and iOS location usage text in `Info.plist`.

## 2026-11-13 Bottom navigation & tab pages
- Redesigned the map screen to match the design: floating destination card, `Recenter map` button with `MapController`, mock route polyline, and rider name markers.
- Added the collapsible `"Group ride"` bottom sheet with `"Live sync"` pill, overlapping rider avatars, `PICKUP` / `DESTINATION` route card, and `End Ride` / `Leave` controls.
- Added a 4-tab bottom navigation bar (`Map`, `Rides`, `Group`, `Profile`) inside `MainScreen`.
- Added `RidesScreen` (host/join actions + mock past rides), work-in-progress `GroupScreen`, and `ProfileScreen` (rider summary + login link).
- Passed active ride data between `HostRideScreen`/`JoinRideScreen` and `MainScreen` using `ActiveRide`, and added `End Ride` / `Leave` state handling on the map.

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