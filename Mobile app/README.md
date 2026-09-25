# RoadGuard AI — Traveler mobile app

**Flutter + Riverpod • v0.1.0 • local-first implementation**

This package contains the traveler app implementation based on `RoadGuard_AI_SRS.pdf`, not the administration portal or Python backend. It includes modern Material 3 screens, onboarding, local state/persistence, native GPS/camera/TTS adapters, safety rules, tests, and a separate interactive HTML design preview.

**Delivery status:** Production Flutter traveller app for RoadGuard. It uses the Django backend in `../Web portal/new-backend` for sign-in (required), anonymous pothole reports, live hazards, turn-by-turn routes and optional sensor sharing. There is no demo or sample mode: every route, hazard and report is real. See `docs/VALIDATION.md` for historical test and device notes.

The app now follows the supplied RIDC Flutter template's `app.dart`, `core`, `modules` and `shared` organization. Existing RoadGuard screens, the supplied color palette, Riverpod state, persisted onboarding and native SQLite remain in place. [Template adoption](docs/TEMPLATE_ADOPTION.md) records the local source, file mapping and integration boundaries.

The Flutter UI follows the eight screen references supplied by the user: a photographic welcome, connected account forms, a full-map Explore view, compact route choices, a trip panel, hazard reporting and a card-based traveler profile. The earlier supplied palette is retained. [Design assets](docs/DESIGN_ASSETS.md) records the generated generic road photograph used on the welcome screen; it does not depict monitored road conditions.

## Android SDK-shell repair (Windows)

If Android reports **"Build failed due to use of deleted Android v1 embedding"** or the project was copied from another machine, do not downgrade Flutter or change the stack. From PowerShell run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\tool\repair_android_sdk.ps1
```

The script regenerates only the Android platform shell from the **Flutter SDK installed on your machine**, reapplies RoadGuard permissions/minSdk, resolves packages, analyzes the Dart code, and builds a debug APK. The Dart/Flutter/Riverpod application code is preserved. Machine-specific `android/local.properties`, Gradle caches and generated plugin registrants are intentionally not shipped.

## Apply the updated authentication UI

Use the fresh extraction instructions in `../../RUN_THIS_UPDATE.md` to avoid running an older project folder. Existing local settings skip onboarding and open Explore; access the updated login from **Profile → Log in**. The matching interactive preview is `preview/index.html`. Login and registration require `ROADGUARD_API_URL` for real accounts.

## Run the Flutter app

Install the current stable Flutter SDK (this source targets Flutter >=3.47 / Dart >=3.13), Python 3, and the platform tooling. Android requires an emulator or USB-debugging device and Android SDK; iOS builds require macOS/Xcode. Native targets are Android API 24+ and iOS 15+ (implementation choices, not SRS mandates).

From this directory:

```bash
bash tool/bootstrap.sh
flutter pub get
dart format lib test integration_test
flutter analyze
flutter test
flutter devices
flutter run
```

The bootstrap script generates standard Android, iOS and web shells using your installed Flutter SDK in a temporary directory, then copies only missing native shell directories. It **does not replace `lib/`, `test/`, `pubspec.yaml`, or any existing project code**. It applies this new app’s permission, branding and minimum-platform overlays. Do not use the overlay script on an unrelated app.

For a browser preview of the **actual Flutter code**, after bootstrapping:

```bash
flutter run -d chrome
```

The Flutter browser target uses in-memory reports/trips, not SQLite, and clearly explains the difference in the UI. Android and iOS use SQLite. The separate `preview/index.html` is an HTML design companion, **not a compiled Flutter application**. Open that file directly to inspect the visual direction without installing Flutter.

## Included experience

| Area | Implementation |
|---|---|
| Welcome and onboarding | Photographic welcome, then three swipeable (and scrollable) screens with progress, persisted completion and optional permission explanation. |
| Account UI | Sign-in is required. Real Django sign-in/registration, secure token storage, server-checked restoration and sign-out. Terms and email verification remain pending. |
| Navigation | Three bottom tabs: Explore, Alerts and Profile. Profile cards open trip history and reported incidents. |
| Explore and Alerts | Full OpenStreetMap map with hazard markers: officer-confirmed, or reported by several drivers' phones (labelled differently). Route warnings are shown and spoken during a live trip; Alerts keeps warnings received on this device. |
| Planner | Search real destinations or drop a destination pin; the current GPS fix supplies the origin. RoadGuard returns route alternatives with live geometry, distance and estimated time. |
| Trip | Turn-by-turn navigation: next manoeuvre banner, spoken directions, live time/distance remaining, automatic rerouting, speed and GPS status. Pause/resume, finish and history. Travellers can explicitly consent to foreground GPS/motion sharing. |
| Reports | Pothole reports only (road cracks are out of scope): one required camera image, optional notes, stationary GPS gate (≤ 0.5 m/s, ≤ 25 m accuracy — same as the backend), local save/list/details/delete and anonymous upload with idempotent retry and server receipt. |
| Profile | Account identity, sign-out, appearance, permission information, privacy and local erasure. |
| Persistence | Native SQLite reports/photos/trips and bounded telemetry outbox; preference persistence via SharedPreferencesAsync. |
| State | Riverpod Notifier controllers, FutureProvider reads, auto-disposed GPS/clock streams, injectable services. |
| Integration seam | Connected anonymous road API and authenticated consent/telemetry API; separate clients, server/account-bound retries and PostGIS raw observations. |

## Important distinctions

**Configured builds use real services.** The Leaflet-style `flutter_map` displays
OpenStreetMap tiles. Django proxies explicitly requested OSRM routes and returns
officer-confirmed and crowd-reported PostGIS hazards. Unconfigured builds show
unavailable states; the app never substitutes made-up places, routes or hazards.
No safety ranking or complete road-condition coverage is claimed.

**Map browsing does not start GPS.** Tap My location in Explore to request foreground location. Stop location, covering/leaving Explore or backgrounding the app ends the map subscription and removes its position marker; returning does not restart it automatically. Reporting owns separate, stricter stationary GPS checks. No background tracking or telemetry is enabled by viewing a map.

**Map tiles use a third-party service.** OpenStreetMap receives the requested tile area, IP address and app identification; centering on GPS reveals that approximate area through tile requests. Visible attribution links to OpenStreetMap's copyright page. Native HTTP-aware image caching has a 100 MB soft limit and is separate from SQLite: Clear local data does not clear cached map tiles. There is no bulk download or guaranteed offline map feature. See [Map and device permissions](docs/PERMISSIONS.md) for declarations, runtime requests and cache removal.

**A saved report is not a submitted report.** Reports stay local until an explicit
anonymous upload gets a matching server ACK. Receipt status is not verification;
reports recorded with mocked GPS cannot upload. Local deletion does not erase server evidence.

**Telemetry is separately opt-in.** Signed-in travelers can review consent during
an active live trip. Raw foreground motion/GPS batches are stored in PostGIS and
retried from an account/server-bound SQLite outbox. Leaving the trip, pausing,
signing out or backgrounding stops collection. Background services, calibrated
DSP/ML, corroboration and measured 10 Hz verification remain open.

**Accounts connect to the workspace Django backend.** Configure `ROADGUARD_API_URL` when launching. For local testing, use a USB tunnel to the backend (`adb reverse tcp:8000 tcp:8000`, then `ROADGUARD_API_URL=http://127.0.0.1:8000`); release builds require HTTPS. Credentials are validated by Django, passwords are hashed server-side, and only an opaque token plus its server origin is stored in Android secure storage. Profile shows the server-returned name/email; logout revokes the session. Missing/unreachable services show an error, never a simulated successful login.

**Other integrations remain separate.** Automatic detection and remote notifications are not connected. Login grants no sensor consent or portal permissions. Email verification, password recovery, finalized terms and server account-erasure flows remain pending. The backend and its API are documented in `../Web portal/README.md` (sections 15–19).

## Safety and privacy behavior

**Standing-still rule (changed 2026-09-25):** a real report can be saved when GPS speed is **at most 0.5 m/s (1.8 km/h)**. Phones at rest often report small speed drift, so the SRS's strict "any speed above 0 blocks reporting" rule was blocking genuine reports. This is a **deliberate, documented exception to the SRS**. To restore the strict rule, set `stationarySpeedThresholdMps` to `0` in `lib/core/models/safety_policy.dart` **and** `MAX_STATIONARY_SPEED_MPS` to `0` in the backend (`new-backend/mobile/reports.py`). Unknown, negative, NaN and infinite speed never become zero.

The app and the backend enforce **the same limits**, so a report the app lets you save is never refused on upload. Real reports also need a fix no older than 10 seconds, horizontal accuracy **≤ 25 metres**, a non-future timestamp, valid coordinates and non-mocked GPS. The 10 s and 25 m values are engineering assumptions, not SRS-derived thresholds. A post-resume fix is required after leaving the foreground/camera.

Form fields and capture are locked while moving; the writer checks the fix again on save, and the camera never opens while the app is in the background.

A photo remains required to save a report, including in the redesigned form. The visual reference's optional-photo wording does not change this implementation safeguard or turn local saving into server submission.

Camera photos are decoded, orientation-adjusted, reconstructed from pixels and re-encoded as JPEG to discard metadata. This does not blur faces/plates or remove identifying content from notes. Server-side stripping remains required. Photos larger than 15 MB or 24 megapixels are rejected as provisional local resource limits; no adaptive low-bandwidth image policy is silently chosen.

Android backup and cleartext-network access are disabled in the main manifest. No TLS certificate bypass, private keys or API credentials are bundled. SQLite is **not SQLCipher**; at-rest encryption, iOS backup exclusion and device protections require production review. Clearing local data is not the SRS’s server-erasure workflow.

## Structure

```text
lib/
  app.dart             RoadGuard app, theme and lifecycle composition
  core/
    config/            api_config.dart: the ONE backend base URL (server + api/v1/) and its security rules
    injection/         Riverpod service providers and persisted bootstrap setup
    routes/            Router composition and exported module path constants
    models/            Domain models and safety policy
    services/          GPS, camera sanitation, TTS, GraphQL and telemetry seams
    storage/           SQLite/native and memory/test implementations
    theme/             Shared light/dark design tokens
  modules/
    auth/              Sign-in/registration and session state and shared form layout
    boarding/          Welcome, onboarding and permission explanation
    home/              Explore/Alerts/Profile shell and live hazard views
    planner/           Route choice
    trips/             Active preview and history
    reports/           Form, list and detail
    profile/           Preferences, privacy and integration status
    # Each module owns presentation/pages, routes and any state providers.
  shared/
    providers_list.dart  Riverpod provider exports
    widgets/           Common UI and the live geographic map
  main.dart            Startup and recoverable storage-error UI
assets/images/         Welcome-screen photograph (see docs/DESIGN_ASSETS.md)
test/                  Unit and widget test sources
integration_test/      Local journey flow test source
tool/                  Bootstrap, platform overlays, source audit and checks
preview/               Independent HTML design preview
docs/                  Architecture, SRS mapping, integration and validation
```

Module state lives in `presentation/providers`; module route lists and path constants compose the central GoRouter. Infrastructure enters through Riverpod overrides. Temporary form input stays in widget state; account/session state uses Riverpod and the configured Django service. The template's Provider/GetIt packages, school-bus authentication/FAQ operations and map example are not added to RoadGuard; they do not establish a RoadGuard backend or routing contract. The earlier UI redesign retained its dependency versions. The live-map addition uses `flutter_map ^8.3.2`, `latlong2 ^0.10.1` and `url_launcher ^6.3.2`; the resolver-generated lockfile is retained.

## Quality commands

```bash
bash tool/check.sh
# With an emulator/device connected (tests isolate their own data):
flutter test integration_test/local_flow_test.dart -d DEVICE_ID --no-uninstall
# After native validation, create a local debug APK:
flutter build apk --debug
```

`tool/check.sh` runs dependency resolution, Dart formatting, analysis and Flutter tests. Keep the included resolver-generated `pubspec.lock` for reproducible builds. The included GitHub Actions workflow is configuration, not evidence of a completed CI run.

Use `--no-uninstall` for device tests: this Flutter SDK otherwise uninstalls the app afterward, which clears its device data. If `flutter test` stalls while discovering its service extension, the same tests can run through the SDK's alternative driver:

```bash
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/local_flow_test.dart -d DEVICE_ID --keep-app-running
```

After device tests, run `flutter run -d DEVICE_ID` to reinstall the normal application entry point. See `docs/VALIDATION.md` for the runner issue observed in this environment.

## Next implementation boundary

Review the unresolved SRS choices in `docs/ARCHITECTURE.md` and the actual
[service contracts](../backend/docs/LIVE_SERVICES.md). Production routing/tile
capacity, sensor-rate and battery measurements, DSP/corroboration, background
operation, retention/erasure and notification delivery remain separate work.
