# RideSync — Plan Ahead

Roadmap of upcoming features, polish, and release prep after core live map, place search, routing, HTTPS backend, and Android CI are in place.

---

## 1. Convoy & Group Experience
- [x] **Interactive Convoy Screen (`lib/screens/convoy_screen.dart`):** tap any rider to focus/pan the map onto them, show distance from you (e.g., `450 m away`), and highlight signal-lost / fell-behind riders clearly.
- [x] **One-tap Copy / Share join code:** copy or share the 6-character ride code + direct clickable HTTPS App Link directly from `HostRideScreen` and the active map top bar.
- [x] **Real phone battery %:** send live device battery level in `POST /rides/{code}/position` (the `positions.battery` column in MariaDB is already ready).
- [x] **Group tab (`lib/screens/group_screen.dart`):** replaced the WIP card with a live Convoy & Saved Riding Crews hub (copy/share active ride invite, open convoy list, create/edit/delete saved crews, and start a ride with a crew).

---

## 2. Riding & Map UX Polish
- [x] **Recover active ride on restart:** save the active ride code and user ID locally so accidentally closing the app mid-ride restores your convoy session.
- [x] **"Fit all riders" map button:** one tap frames every active rider and the destination pin on screen.
- [x] **Keep screen awake during active rides:** prevents screen sleep while mounted on handlebars and pauses automatically when backgrounded or idle.
- [x] **Rider heading / direction arrow:** show travel direction on map pins using GPS heading.
- [x] **Quick convoy alerts & notifications:** one-tap motorcycle status pings (*Fuel stop*, *Wait up*, *Need help*) with live banners and local Android/iOS notifications.

---

## 3. Real Accounts & Authentication
- [x] Wire `lib/screens/login_screen.dart` to FastAPI (`/auth/register`, `/auth/login`, `/auth/me`, `/auth/logout`) with scrypt password hashing and MariaDB bearer tokens (`auth_tokens`), keeping quick guest riding supported when signed out.

---

## 4. Real Ride History & Rider Stats
- [x] Add `GET /rides/history` on FastAPI so `RidesScreen` (`Past rides`) and `ProfileScreen` display real completed rides and stats from MariaDB.

---

## 5. Pre-Play Store Release Prep
- [ ] Replace `applicationId = "com.example.ridesync"` in `android/app/build.gradle.kts` with the final production package ID.
- [ ] Configure a real Android release signing keystore via GitHub Actions Secrets so `v*` tag builds produce Play Store-ready `.aab` bundles.
- [ ] *(Optional)* Upgrade 3-second polling to WebSockets for smoother live rider movement.
- [ ] *(Optional)* Move from free DDNS (`30-day` renewal) to a permanent production domain before public launch.

---

## 6. Must-Have Features & Tweaks (User List)
- [x] **a) Copy code & Share ride:** one-tap **Copy code** and **Share ride** (system share sheet / WhatsApp with direct clickable HTTPS App Link) right when a join code is generated on `HostRideScreen` and on the active map bar.
- [x] **b) Better map navigation (twist / rotate / 3D tilt):** upgraded to `maplibre` + OpenFreeMap (Option A) for 3D tilt (`0°–60°`), one-tap 3D/2D toggle, two-finger rotation with upright street labels, and a reset-to-North compass button.
- [x] **c) Smooth Google Maps-like tiles & Light/Dark mode:** replaced CPU `vector_map_tiles` with native GPU `maplibre` (Vulkan on Android) + OpenFreeMap (`liberty` Light with 3D buildings & `dark` night mode) for smooth 60fps rendering.
- [x] **d) Smarter place search:** added Google Maps–style floating category pills, saved recent searches, distance-to-place badges, Nominatim fallback when Photon misses local spots, and clear offline Retry states.
