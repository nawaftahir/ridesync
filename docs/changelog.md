# Changelog

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