# RideSync

A Flutter app where a group of motorcyclists share their live location during a ride, see each other on a map, and follow a shared route to a destination.

---

## Current Features

- **Live Map & GPS (`RideMapScreen`)**: Real device GPS tracking via `geolocator`, `'You'` live marker, follow-me `Recenter`, `km/h` speed pill (WIP), mock convoy route/riders, collapsible `"Group ride"` bottom sheet, and in-app permission + Android GPS enable prompts.
- **4-Tab Navigation (`MainScreen`)**: `Map`, `Rides` (host/join actions + mock past rides), `Group` (WIP overview), and `Profile` (rider summary + login screen preview).
- **Host & Join Ride Flows (Mock Data Preview)**: Generate a 6-character ride code on `HostRideScreen`, or join sample rides (`RIDE42`, `MOTO89`) on `JoinRideScreen`.
- **Theme Switcher (`Auto / Light / Dark`)**: Follows the device theme by default or can be overridden directly in **Profile → Appearance**, updating both UI and map tiles.

> **Note:** Ride sync, convoy positions, and authentication currently run on local mock data (`lib/data/` and `lib/repositories/`) ahead of backend integration.

---

## Versions & Stack

- **Flutter:** `3.50.0` (channel `stable`)
- **Dart:** `3.14.0` (`sdk: ^3.13.3` in `pubspec.yaml`)
- **Main packages:** `flutter_map`, `latlong2`, `geolocator`, `http`, `provider`

Check your local SDK version:

```bash
flutter --version
```

---

## Getting Started

1. Install dependencies:
   ```bash
   flutter pub get
   ```
2. Run on a connected phone or emulator:
   ```bash
   flutter run
   ```
   *(Real GPS updates work best on a physical device. Android and iOS location permissions are configured in `android/app/src/main/AndroidManifest.xml` and `ios/Runner/Info.plist`.)*

Re-run `flutter pub get` after every `git pull`.

---

## Code Quality & Tests

Run these checks before committing or opening a PR:

```bash
dart format .
flutter analyze
flutter test
```

All formatting checks, analyzer rules (`0 issues`), and tests in `test/` should pass.

---

## Project Layout

```text
lib/
  data/          # Mock ride and map data
  models/        # Rider, RiderPosition, ActiveRide
  repositories/  # Ride and rider data repositories
  screens/       # App tabs and ride/auth screens
  services/      # LocationService (GPS & permissions)
  theme/         # Light & Dark Material 3 theme
  widgets/       # Shared UI components
test/            # Unit and widget tests
docs/            # Changelog and project notes
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for branching and PR guidelines, and [docs/changelog.md](docs/changelog.md) for recent changes.
