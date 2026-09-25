# Connected service addition — 21 September 2026

`RoadApi` handles anonymous reports, confirmed hazards and server-proxied OSRM
routes. Configured builds use live screens; unconfigured builds keep explicit
sample flows. Live errors never select demo data. `ReportUploader` persists
server origin, idempotency ID and photo token before submission and requires an
ACK. Real route geometry lives with each SQLite trip.

`TripCollection` coordinates authenticated consent, native foreground GPS/motion,
account/server-bound SQLite batches, ACK-only retries and explicit withdrawal.
No sensor is started by login. Leaving a live trip or backgrounding stops its
subscriptions. Django stores validated observations as PostGIS points and does
not classify them as hazards. See [live contracts and limitations](../../backend/docs/LIVE_SERVICES.md).

The earlier architecture below records the starting design; descriptions of
unconnected services are superseded by this addition. Its unresolved SRS choices
remain unresolved.

# Architecture and implementation decisions

## Scope and sources

Source baseline: user-provided `RoadGuard_AI_SRS.pdf`, 26 pages. Requested addition: modern UI, onboarding, Flutter and Riverpod. This package implements the traveler client first. It does not implement UC-17 administrative moderation, Python DSP, database clustering or server capacity requirements.

The SRS specifies Flutter, minimalist driving views, GraphQL, native smartphone inputs and SQLite. It does not specify a Flutter state library, palette, map vendor, authentication protocol, concrete GraphQL schema or record serialization. Riverpod is the user’s explicit choice; the remaining implementation decisions below are additions, not quotations from the SRS.

The user's local RIDC template at `/home/egovirdc/Desktop/flutter_template` supplies the application organization. [TEMPLATE_ADOPTION.md](TEMPLATE_ADOPTION.md) records the inspected revision and the concrete mapping. This structural adoption retains RoadGuard's behavior, package identity, native persistence and dependencies.

## Source organization

`lib/app.dart` composes the themed application. `core/routes/app_router.dart` combines routes owned by `modules/auth`, `boarding`, `home`, `planner`, `trips`, `reports` and `profile`; each module defines path constants and route builders in `routes/`. `core/routes/route_paths.dart` exports those constants for navigation callers. Persisted onboarding controls the initial route: incomplete onboarding opens `/welcome`, followed by the existing three-page flow; completion opens Explore. The account UI routes `/sign-in` and `/register` are accessible before onboarding, while continuing as a guest still follows the persisted onboarding state.

The home shell has Explore, Alerts and Profile bottom tabs, with selection derived from the current route. Trip history and the report list remain reachable from Profile cards. Planner, active trip, report creation and detail screens retain dedicated routes. This navigation change does not alter stored trips or reports.

Each module owns its pages in `presentation/pages` and shared feature state in `presentation/providers`. `core/injection/service_providers.dart` declares infrastructure providers; `core/injection/injection_container.dart` loads settings, opens the store and restores an active trip before application startup. `shared/providers_list.dart` exports the providers, while `shared/widgets` contains reusable UI, the live map component and retained demo illustration. Domain models, safety rules, storage and native adapters remain under `core`.

The former `app/*.dart`, `features/*` and `core/widgets/*` compatibility exports were removed on 2026-09-25; everything is imported from its real location. Riverpod supplies dependency injection and state throughout; the template's GetIt and Provider mechanisms are adapted to Riverpod, without introducing a second container or state framework.

## Application boundaries

Presentation → Riverpod controllers/providers → domain rules and repository interfaces → local/native adapters.

Widgets do not write SQL or invoke RoadGuard backend HTTP operations. Map rendering delegates tile requests to flutter_map's injectable `TileProvider`. `ReportWriter` rechecks safety independently of presentation state. `TripController` owns active state and storage updates; completed history is invalidated only after persistence succeeds. `SettingsController` saves an entire settings snapshot and rejects concurrent writes instead of silently reordering them. Riverpod provider overrides supply deterministic in-memory adapters in tests.

The production planner calls `RoadApi` with the selected destination coordinates and current GPS fix. Missing service configuration, invalid destinations and failed route requests remain explicit errors; no fixture is substituted. `DemoRouteRepository` is retained only as a test fixture and is not registered as a runtime provider. Returned alternatives use their server route geometry. This is live route following, not turn-by-turn navigation.

`LiveRoadMap` uses flutter_map and OpenStreetMap's HTTPS raster tiles in Explore, the planner map sheet and trip preview. Its attribution remains outside the map canvas, and consumers keep it clear of controls and trip panels. An injectable tile-provider factory supports deterministic loading/error/retry tests. Network failures expose a retry action; they never substitute an illustrated map and call it live. The native built-in cache honors HTTP freshness with a 100 MB soft limit. No bulk/offline prefetch is implemented. [PERMISSIONS.md](PERMISSIONS.md) links the applicable tile policy and package documentation.

Explore owns a `MapLocationSession` using the existing injected location service. Browsing never starts it; My location explicitly requests foreground access. The session rejects stale, invalid or mocked positions for its marker, and expiry removes an outdated marker. Map display permits moving positions and approximate accuracy up to 5 km, shown in the location status; these display limits do not replace the stricter report gate. Stopping location, covering/leaving Explore or backgrounding the app cancels the subscription and clears the position. It does not automatically restart on return. Planner and demo trip basemaps do not start a GPS session. Starting/resuming a live trip opens a display-only MapLocationSession with foreground permission. Fresh GPS updates its marker and camera; panning suspends camera follow until recenter. Pause, leaving the trip or backgrounding cancels it; app resume alone does not restart it. The Android permission dialog may be inactive while requesting, but actual backgrounding still cancels the pending request. This display-only session is separate from reporting evidence and does not enable telemetry or background location.

The report form owns an explicit Riverpod GPS subscription and closes/invalidates it immediately when the app leaves the foreground, the camera opens, or demo mode is selected. This does not depend on a paused app drawing another frame. Camera return, cancellation, photo recovery and app resume require new GPS evidence before unlocking. Capture and save read the latest provider event rather than a previous rendered frame. A ticking provider expires old zero-speed evidence even without further GPS events. Audio stops when the app leaves the foreground.

## State ownership

| State | Owner |
|---|---|
| Theme, voice preference, onboarding completion | Profile module SettingsController + SettingsStore |
| Active trip preview and history | Trips module TripController/history provider + SQLite/native store |
| Route options | Planner module FutureProvider.family keyed by value-equal RouteRequest |
| Report list | Reports module FutureProvider backed by LocalStore |
| Sample hazards | Home module fixture provider |
| GPS and freshness ticks | Reports module auto-disposed StreamProviders |
| Foreground map position and expiry | Home module MapLocationSession, owned by visible Explore or a live trip screen |
| Geographic tile rendering, load/retry state and HTTP image cache | Shared LiveRoadMap + injectable flutter_map TileProvider |
| Storage counts | Profile module FutureProvider backed by LocalStore |
| Native services and persisted initial state | core/injection providers, overridden during startup/tests |
| Unsaved input, selected chip, page animation, in-flight camera UI | Local widget state |
| Example account details and password visibility | Auth module widget state only; no session, persistence or transport |
| Save-time report invariants | Reports module ReportWriter + core SafetyPolicy |

Using widget state for ephemeral form input and animation is intentional; shared/business state lives in Riverpod. No StateNotifier legacy import or generated provider files are needed.

## Native versus demo behavior

Native GPS, permission checks, camera capture and TTS adapters are supplied. See `VALIDATION.md` for the executed Android checks and remaining hardware acceptance work. Android/iOS persist reports, their photo bytes, and trip previews in SQLite. Browser-only preview storage is ephemeral. Non-sensitive UI preferences use SharedPreferencesAsync. Integration test code uses an isolated database path and preference key. The runner also needs `--no-uninstall` (`flutter test`) or `--keep-app-running` (`flutter drive`) to avoid removing the installed app and its data afterward.

The app has no authenticated user session. Sign-in and registration screens accept example details in temporary text controllers, validate the form, then explain that account services are unavailable. Details are never sent to a service or saved to storage; password fields are cleared after valid submission and controllers are disposed with the screen. Google sign-in and password recovery have no connected service. The terms checkbox is disabled and no consent acceptance is requested or recorded. These screens do not create accounts or change guest authorization.

UC-23’s registered actor is not fabricated through a “demo login.” The sensor adapter checks registration, consent, active-trip and foreground eligibility but is not wired into guest trips. It requests 100 ms sampling; the real achieved rate must be measured per device. It produces raw motion events, not classified or clustered hazards.

## Provisional choices requiring review

1. GPS freshness <=10 seconds, accuracy <=25 meters, speed <=0.5 m/s counts as standing still; mock/future/invalid evidence rejected. The 0.5 m/s allowance for GPS speed drift is a deliberate exception to the SRS's strict zero-speed rule (2026-09-25). The backend (new-backend/mobile/reports.py) enforces the identical limits.
2. A telemetry outbox row is a proposed 1–20 event chunk capped at 32 KiB. This is not an approved interpretation of the ambiguous “500 telemetry records.” The 500-row cap is enforced transactionally; new rows are rejected at capacity without deleting unsent evidence.
3. Photo input maximum 15 MB / 24 megapixels and JPEG re-encoding quality 90 are local safety/resource decisions. Automatic low-bandwidth resizing/blocking remains open in the SRS appendix.
4. Local preview history is used to demonstrate familiarity. Live registered and anonymous route-history semantics remain a backend decision.
5. Android API 24+, iOS 15+, current stable Flutter/Dart, English labels and light/dark themes are implementation choices. The current colors follow the user's palette supplied on 21 September 2026.
6. User-created reports remain local-only until an actual transport contract is integrated. No report status is advanced by a timer or a fake upload.

## Security boundaries

The RoadGuard GraphQL transport accepts HTTPS endpoints only; credentials in URL user-info are rejected, redirects are disabled, bearer tokens are omitted for explicitly anonymous calls, and HTTP errors and GraphQL errors do not become ACKs. The transport does not claim to enforce a measured TLS minimum by itself; TLS 1.2+ must be validated at native and gateway levels. No custom certificate trust bypass is included.

Guest report DTOs have no user ID or hardware device token. Pixel re-encoding reduces image metadata exposure, but metadata removal does not anonymize visible content or typed notes. The gateway must enforce its own anonymous-field allowlist, media stripping and idempotency. A custom HTTP client’s credential/cookie policy also needs review before anonymous integration.

SQL uses parameterized writes/queries. Native storage failure presents a retry screen without wiping data or silently changing to temporary memory. Android automatic backup is disabled. Native SQLite data is not application-encrypted; iOS backup exclusion, encryption/keys, storage retention and validated server-erasure/backup interactions are release blockers, not solved compliance claims.

OpenStreetMap tile requests are a separate third-party network integration. The tile service receives the requested map area, IP address and application identification; centering on GPS exposes that approximate area through the requested tiles. Reports, photos and a GPS track are not uploaded as map-request payloads. Native cached tiles can reveal viewed areas and are independent of SQLite reports/history/outbox. Clear local data does not remove this cache; device app-cache controls can remove it. See [PERMISSIONS.md](PERMISSIONS.md) for permission timing and the complete map-data boundary.

## UI design

The current layout follows the user's eight attached screen references supplied after the Figma reference could not be accessed. Material 3 uses 24 px margins on content screens, shared 10–16 px corner radii, larger rounding on the active-trip panel, 48 px or larger principal controls, natural text wrapping and scrollable forms. The welcome uses a bundled generated generic road photograph with Flutter-rendered branding and contrast overlays; [DESIGN_ASSETS.md](DESIGN_ASSETS.md) records its source and intended use.

Explore presents an interactive geographic map with separate action controls, location status and visible attribution. It shows confirmed hazard markers only; proximity warnings are reserved for an active live trip. Planner searches actual destinations or accepts a map pin and presents the route alternatives returned by RoadGuard. The active-trip screen follows the live GPS position and route, displays confirmed hazards ahead and can read warnings aloud. Alerts retains warnings shown during a trip on this device; remote notifications are not enabled. Account screens use the configured service and offer guest access when it is unavailable.

The report redesign retains a required photo, fresh stationary GPS gate, camera/resume rechecks and local-only saving. Optional-photo wording in the visual reference is not adopted. Layout references do not authorize changes to safety policy, backend contracts or consent conditions.

Navy panels, blue actions and pale supporting surfaces follow the current welcome-screen palette. Color is supported by text/icons for status. System/light/dark preferences persist; OpenStreetMap raster tiles retain their provider styling. Onboarding motion respects the system reduced-animation setting. Map controls and the real-position marker have semantic labels. Content respects text scaling, and account forms scroll with the keyboard. Real device accessibility audits are outstanding. Riverpod and native SQLite remain the state and storage foundations.

The shared `RoadColors` tokens and both Material color schemes use the welcome-screen navy/blue palette across the Flutter UI. Blue and pale blue indicate interaction and selected routes; red/pink indicate errors; amber is reserved for hazard notices. Pale fills use dark text, with neutral/deeper tones for readability. The independent HTML design companion and raster launcher artwork retain their own earlier references.


## Presentation and traveler authentication update — 2026-09-21

This update supersedes the earlier account-preview statements above. The
`auth` module now connects registration/login to `backend/accounts/mobile.py`,
using server-assigned traveler roles and seven-day opaque sessions. Tokens are
stored using flutter_secure_storage and checked on restoration; passwords never
enter SQLite/preferences. Portal MFA and anonymous report transports remain
separate. The actual contract is `backend/docs/MOBILE_AUTH.md`; no guessed
GraphQL identity operation was connected. Terms, verification emails, erasure,
sensor consent and report synchronization remain open.

Explore uses the whole content area for the geographic map with floating
controls; attribution remains separate and visible. A labelled sample alert
slides in, can be swiped or dismissed, and hides after eight seconds. It stays
open for accessibility navigation, pauses its timer during touch interaction,
and closes when leaving Explore/backgrounding. The replay button demonstrates
this UI without claiming a live nearby observation. Profile can replay the
introduction via an explicit replay route without resetting stored onboarding.
