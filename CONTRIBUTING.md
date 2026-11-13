# Contributing to RideSync

Here's a quick guide on this project so everything stays consistent.

---

## Quick Setup

1. Use **Flutter 3.50.0 / Dart 3.14.0** (matching `sdk: ^3.13.3` in `pubspec.yaml`; check with `flutter --version`).
2. **Clone the repo** and open it in VS Code or Android Studio.
3. Run in terminal:
   ```bash
   flutter pub get
   flutter run
   ```
4. After every `git pull`, run `flutter pub get` again.

---

## Where things live in `lib/` & `test/`

- `lib/screens/` — App pages (`main_screen.dart`, `ride_map_screen.dart`, `rides_screen.dart`, `host_ride_screen.dart`, `join_ride_screen.dart`, `convoy_screen.dart`, `group_screen.dart`, `profile_screen.dart`, `login_screen.dart`).
- `lib/services/` — Device & platform integrations (`location_service.dart` for GPS & permissions).
- `lib/data/` — Fake data for local testing (`mock_rides.dart` and `mock_map_data.dart`).
- `lib/repositories/` — Data access layer (`ride_repository.dart`, `rider_repository.dart`).
- `lib/models/` — Data classes (`active_ride.dart`, `rider.dart`, `rider_position.dart`).
- `lib/theme/` — App light/dark colors and styling (`app_theme.dart`).
- `lib/widgets/` — Reusable UI components (`rider_tile.dart`).
- `test/` — Unit and widget tests (`location_test.dart`, `repository_test.dart`, `widget_test.dart`).

---

## Git & Branching

1. Always create a new branch from `dev` for your work:
   ```bash
   git checkout -b feature/your-feature-name
   ```
   *Examples:* `feature/summary-screen`, `feature/join-code-animation`, `fix/map-padding`.
2. Commit your changes with a clear message:
   ```bash
   git commit -m "feat(map): add ride summary screen"
   ```
3. Push your branch and open a **Pull Request (PR)** into `dev` on GitHub.
4. Don't push directly to `dev` — let someone review first.

---

## Checks & Rules Before Pushing

All of these must pass before committing / opening a PR:

1. **Auto-format code (`dart format`):**
   ```bash
   dart format .
   ```
   (Verify zero unformatted files with `dart format --output=none --set-exit-if-changed .`.)
2. **Static analysis (`flutter analyze`):**
   ```bash
   flutter analyze
   ```
   Must report **0 issues**.
3. **Tests (`flutter test`):**
   ```bash
   flutter test
   ```
   **All tests must pass.** Add or update tests in `test/` whenever you add or change behavior.
4. **Changelog:** Group changes under the current `## YYYY-MM-DD` heading in `docs/changelog.md`.
5. **Packages & secrets:** Tell the team before adding packages to `pubspec.yaml`.
