# Contributing to RideSync

Here's a quick guide on this project so everything stays consistent.

---

## Quick Setup

1. Use Flutter 3.47.6 (check with `flutter --version`).
2. **Clone the repo** and open it in VS Code or Android Studio.
3. Run in terminal:
   ```bash
   flutter pub get
   flutter run
   ```
4. After every `git pull`, run `flutter pub get` again.

---

## 📁 Where things live in `lib/`

* `screens/` — App pages (`home_screen.dart`, `host_ride_screen.dart`, `ride_map_screen.dart`, etc.).
* `data/` — Fake data for testing (`mock_rides.dart` and `mock_map_data.dart`). If your screen needs pretend data, pull it from here or add to it.
* `repositories/` — Where screens get their data from.
* `models/` — Data classes (`Rider`, `RiderPosition`).
* `theme/` — App colors and styling (`app_theme.dart`).
* `widgets/` — Reusable UI pieces (like `rider_tile.dart`).

---

## 🌿 Git & Branching

1. Always create a new branch from `dev` for your work:
   ```bash
   git checkout -b feature/your-feature-name
   ```
   *Examples:* `feature/summary-screen`, `feature/join-code-animation`, `fix/map-padding`.
2. Commit your changes with a clear message:
   ```bash
   git commit -m "Add ride summary screen with mock stats"
   ```
3. Push your branch and open a **Pull Request (PR)** on GitHub.
4. Don't push directly to `dev`. Let someone review first.

---

## 💡 Quick Rules to Follow

- **Check for errors before pushing:** Run `flutter analyze` in terminal. It should show 0 issues.
- **Auto-format code:** Run `dart format .` so all our files look clean and consistent.
- **Changelog:** add a line to `docs/changelog.md` with your change.
---
