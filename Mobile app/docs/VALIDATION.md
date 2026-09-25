# Validation record

## Remove R launch screen and simplify welcome — 22 September 2026

The road welcome now has one action, Get Started. Sign in and the guest caption
were removed from that page; authentication remains reachable through Profile.
The integration journey now covers Profile → Sign in → Create account → Back
instead of using the removed welcome action, preserving authentication coverage.

Android launch resources now use a matching blue window in day and night modes.
API31+ explicitly uses a transparent vector splash icon to prevent Android from
substituting the R launcher icon. Both night and day API31 variants are supplied.
The system starting window remains briefly before Flutter draws the road image;
there is no added splash timer, plugin or dependency. Legacy launch backgrounds
and NormalTheme also use blue to avoid the old black/white transition.
See [Android's splash-screen customization](https://developer.android.com/develop/ui/views/launch/splash-screen).

Commands actually run:

- `dart format lib/modules/boarding/presentation/pages/welcome_screen.dart test/widgets/auth_flow_test.dart integration_test/local_flow_test.dart`:
  three files, zero changes, exit 0.
- `flutter test test/widgets/auth_flow_test.dart test/bootstrap/app_dependencies_test.dart test/widgets/ui_layout_test.dart --reporter expanded`:
  **21 passed**, five seconds, exit 0; includes single-action assertions,
  onboarding navigation, authentication and small/large-text layouts.
- `flutter analyze`: no issues, 16.8 seconds, exit 0.
- `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/local_flow_test.dart -d 99031FFAZ007TR --keep-app-running --no-pub`:
  both native cases passed, exit 0; `+3` includes teardown. 44 seconds of tests,
  32.6-second build, 7.2-second installation. Uses isolated SQLite/preferences
  and preserves installed app data. Android resource compilation succeeded.
- `flutter run -d 99031FFAZ007TR --no-pub --dart-define=ROADGUARD_API_URL=http://127.0.0.1:8000 --dart-define=ROADGUARD_PRESENTATION=true`:
  normal Android build passed (16.9 seconds), installed (6.4 seconds), launched
  and connected to the VM service; detached with `d`. Updated normal APK is
  `build/app/outputs/flutter-apk/app-debug.apk`. Existing Kotlin migration and
  debug skipped-frame warnings remain; no application exception was observed.
- `python3 /tmp/roadguard_check_launch.py`: force-stopped/relaunched only
  RoadGuard without clearing data and captured six startup frames on Pixel4
  Android13. Inspected frames at 0.62, 1.07 and 2.71 seconds: blue starting window,
  no R logo. Captures are under `build/verification/clean-launch-2026-09-22/`.
  This checks the cold-start transition; the single-button road page and its
  navigation were verified by the passing widget/native integration tests.


## Branded road opening screen — 22 September 2026

Presentation startup now opens the existing full-screen road photograph with
RoadGuard AI branding, tagline, Get Started and Sign in. Get Started continues
to the light onboarding flow. Profile → Restart presentation returns to this
same welcome screen. Normal completed-onboarding startup still opens Explore;
this change does not reset user data or change Android's system launch window.
The existing image asset and responsive welcome layout were reused.

- `dart format lib/core/routes/app_router.dart lib/modules/profile/presentation/pages/profile_screen.dart test/bootstrap/app_dependencies_test.dart test/widgets/live_trip_location_test.dart`:
  passed, four files, zero changes.
- `flutter test test/bootstrap/app_dependencies_test.dart test/widgets/live_trip_location_test.dart test/widgets/auth_flow_test.dart --reporter expanded`:
  **20 passed**, three seconds, exit 0. Startup asserts the actual road-image
  asset, welcome route, Get Started transition to onboarding, light theme and
  preservation of stored trips/preferences/outbox. Profile restart and existing
  authentication/location flows also pass.
- `flutter analyze`: no issues, 13.0 seconds, exit 0.
- `flutter devices`: Pixel 4 `99031FFAZ007TR`, Android13/API33 detected.
- `flutter run -d 99031FFAZ007TR --no-pub --dart-define=ROADGUARD_API_URL=http://127.0.0.1:8000 --dart-define=ROADGUARD_PRESENTATION=true`:
  Android debug build succeeded (76.0 seconds), installed (8.1 seconds), VM
  connected. Restarted with `R` and visually verified the branded road opening
  on the Pixel, captured at `build/verification/road-opening-2026-09-22/pixel4-welcome.png`.
  Existing Kotlin migration/debug skipped-frame warnings remain. No application
  exception appeared in observed startup logs. Normal APK updated at
  `build/app/outputs/flutter-apk/app-debug.apk`.

## Camera report submission and connected portal — 22 September 2026

Real reports now use **Submit report** when the backend is configured: explicit
sharing confirmation, a fresh safety check, native local persistence, photo
upload and a real server acknowledgement. Failure opens the same saved report
for retry; it never claims successful submission or verification. GPS must
still be stationary, fresh, valid, sufficiently accurate and non-mocked. Camera
return/resume requires a new fix. Demo reports remain local-only. This does not
enable telemetry or change consent/authentication gates.

Android already uses image_picker's system camera intent; adding a CAMERA
manifest permission is not required for this flow. The Pixel resolved
`android.media.action.IMAGE_CAPTURE` to Google Camera's CaptureActivity. No
permission was auto-granted and no real photo was taken by the automated test.
The existing iOS descriptions remain; no iOS validation is claimed. GPS is
approximate: the attached fix is checked at save time after camera return,
not guaranteed shutter-time or exact-position evidence.

The existing React portal now uses Django password/TOTP sessions with CSRF,
server-assigned roles, live paginated report lists/counts, protected photo
retrieval, GPS accuracy maps/timestamps and audited/versioned decisions.
**Needs verification** keeps new reports unpublished; only **Confirmed** reports
appear on the public hazard map. There is no new REJECTED state or fabricated
AI score. User management and notifications are clearly unavailable. Existing
prototype source files were retained, and the misleading static update time
and notification indicator were removed from the connected header.

The portal was staged in `../portal`, built/tested, and 15 reviewed files were
applied to `/home/egovirdc/Downloads/new web admin portal` with original-content
hash checks. All 15 applied hashes were verified afterwards. Existing
unrelated files, dependency versions and lockfile were preserved. Git status
still fails because this supplied workspace is not a usable Git repository.
No commit, push, deployment, system installation or app-data wipe was done.

Commands actually executed (Flutter cwd unless noted):

| Command | Result |
|---|---|
| `dart format lib test integration_test test_driver` | Final run: 109 files, one new test formatted, exit 0. |
| `flutter analyze` | No issues found, 19.4 seconds, exit 0. |
| `flutter test test/widgets/report_submission_test.dart --reporter expanded` | Two passed, exit 0. Camera return freshness, movement during confirmation, anonymous photo/GPS submission, acknowledgement, saved upload failure and no telemetry. First run rejected an invalid test-only photo-token fixture; corrected it to the actual 43-character contract and retained all assertions. |
| `flutter test --reporter expanded` | **146 passed**, zero failures, 22 seconds, exit 0. Includes existing safety, lifecycle, upload-idempotency and small-layout regressions. |
| `flutter devices` | Pixel 4 `99031FFAZ007TR`, Android 13/API33, plus Linux/Chrome. |
| `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/local_flow_test.dart -d 99031FFAZ007TR --keep-app-running` | Final: both native cases passed, exit 0; runner `+3` includes teardown, 41 seconds. Android build 36.1 seconds, install 6.9 seconds. First run found a stale `Where to?` label assertion from the earlier search redesign; test now uses the existing search key, preserving all journey/report/storage assertions. |
| `adb -s 99031FFAZ007TR shell cmd package resolve-activity --brief -a android.media.action.IMAGE_CAPTURE` | Resolved Google Camera CaptureActivity. Read-only capability check, not a physical photo capture. |
| `adb -s 99031FFAZ007TR reverse tcp:8000 tcp:8000` | Succeeded. |
| Backend: `docker compose run --rm web python manage.py test tests --noinput --verbosity 0` | **94 passed**, 3.182 seconds, exit 0; actual isolated PostGIS DB. |
| Backend: `docker compose up -d db web`, `docker compose restart web` | Succeeded. Health endpoint returns PostgreSQL/PostGIS `ok`. |
| Portal: `npm run build` | TypeScript and Vite production build passed, exit 0; final 1994 modules, 2.07 seconds. Existing bundle-size warning (507.02 kB main JS). No dependency upgrades. |
| Portal: `npm run lint` | Exit 0, five warnings, zero errors: Fast Refresh exports and unused prototype table/compiler compatibility warnings. |
| Portal: `node tests/live_portal.mjs` | Passed twice against disposable `test_roadguard_portal_browser`. Real photo/GPS intake, duplicate idempotency, private image access, wrong password handling, password/TOTP session, review notes, verification/confirmation, exact stored-coordinate publication, concurrent edit recovery, session reload/logout and officer route restriction. Initial screenshot lookup required a named region; corrected accessible markup. |
| Original portal: `npm run dev -- --host 127.0.0.1 --port 5173 --strictPort` | Running at localhost5173, proxying the actual local backend. |
| `node /tmp/roadguard-portal-login-check.cjs` | Passed: original portal redirects protected route to real sign-in, inputs render, proxy/CSRF succeeds, no browser exceptions. Initial harness incorrectly treated a paragraph as a heading; corrected the locator. No operator account created. |
| `flutter build apk --debug --no-pub --dart-define=ROADGUARD_API_URL=http://127.0.0.1:8000 --dart-define=ROADGUARD_PRESENTATION=true` | Passed, exit 0; Gradle 61.5 seconds. Normal `lib/main.dart` app at `build/app/outputs/flutter-apk/app-debug.apk`. First attempt was interrupted before completion was confirmed. Existing flutter_tts Kotlin migration warning remains. |
| `flutter run -d 99031FFAZ007TR --use-application-binary=build/app/outputs/flutter-apk/app-debug.apk` | Installed in 7.0 seconds, launched normal main entry point, VM service connected. Detached with `d`, leaving the presentation app running. No application exception or SQLite error in observed startup output; debug logs report skipped frames. |

Native integration uses isolated SQLite/preferences, sample photos and no real
GPS/camera requests. It exercises onboarding/auth forms, Explore, route preview,
trip pause/reopen/resume/history, unknown-GPS locks, demo report capture/save/
list/detail/delete, privacy/permissions/preferences and zero guest telemetry.
The driver avoids the previously documented direct-runner DDS failure and uses
`--keep-app-running` to preserve application data. Native debug logs include
skipped frames and the existing predictive-back warning; no performance claim.

Browser tests use fixture accounts/reports only in a disposable database. The
test server and port5174 Vite instance were stopped afterwards; no synthetic
report or operator was inserted into presentation data. Playwright was installed
only in `/tmp/roadguard-browser-tools`, not added to project dependencies. Map
tiles are disabled in the automated browser test. A later tool interruption stopped the original Vite server; it was restarted
on port5173 and returned HTTP200. The original portal's real
login was captured and visually inspected at
`../../portal/build/verification/portal-login.png`.

Before presenting: run the interactive administrator setup command in
[the walkthrough](PRESENTATION_WIFI.md), enroll the authenticator privately,
and perform one stationary outdoor camera/GPS upload over Wi-Fi. Verify its
photo, mapped accuracy and notes in the portal, then confirm or keep under
verification. Physical shutter/GPS accuracy, camera cancellation/process death
and Wi-Fi reconnection remain manual checks. No production readiness, automatic
corroboration/AI, background telemetry, notifications, user-management API or
independent location verification is claimed. The existing SRS ambiguities and
provisional GPS thresholds remain unresolved.

## Moving trip location and Wi-Fi presentation — 21 September 2026

Starting/resuming a live trip now requests foreground GPS for map display.
Fresh positions move its marker and follow camera; dragging suspends camera
follow, and the target button recenters/reconnects. Pause, route departure and
backgrounding cancel the watch and clear the position. Returning to the app
alone does not restart it. Delayed permissions cannot start it after leaving;
the transient Android permission dialog is handled separately from backgrounding.
Display GPS never enables motion sensors or uploads telemetry. Existing account,
consent and reporting gates are unchanged. This is not turn-by-turn navigation,
rerouting, live traffic or arrival detection.

Visible latitude/longitude strings were replaced with place/selection labels
in the planner, hazard dialog, reports and saved route history. Previously saved
coordinate labels retain their stored values but display readable names.
`ROADGUARD_PRESENTATION=true` opens the first introduction page in light mode on
each cold launch. Profile's Restart presentation does the same immediately;
both preserve accounts, existing trips/reports/history, voice preference and
consent/outbox data. No storage wipe or logout is used.

The new [Wi-Fi walkthrough](PRESENTATION_WIFI.md) explains Android wireless ADB
pairing and reconnecting after an IP/port change. `tool/connect_wifi.sh` starts
the existing local backend, checks health, recreates forwarding and opens the
installed APK. Its URL remains localhost; no LAN cleartext authentication,
public database port, new dependencies, native permissions or system settings
were introduced. `tool/run_presentation.sh DEVICE_ID --presentation` builds the
presentation startup variant; omitting the flag restores normal startup.

Commands actually executed from `roadguard_ai/`, unless noted:

| Command | Actual result |
|---|---|
| `dart format lib test integration_test test_driver` | Final: 108 files, zero changes, exit 0. |
| `flutter analyze` | Final: **No issues found**, 43.3 seconds, exit 0. |
| `flutter test --reporter expanded` | **144 passed, zero failed**, 32 seconds, exit 0. |
| `bash -n tool/run_presentation.sh tool/connect_wifi.sh` | Passed, exit 0. Syntax validation only. |
| `adb devices -l` (installed absolute path) | Pixel 4 `99031FFAZ007TR` connected over USB. Sandbox socket restriction required rerunning outside the sandbox. |
| `adb -s 99031FFAZ007TR reverse tcp:8000 tcp:8000` | Succeeded. |
| `adb -s 99031FFAZ007TR shell settings get global adb_wifi_enabled` | `0`: Wireless debugging was off; no Wi-Fi session is claimed. |

Nine added tests cover movement/camera follow, pan/recenter, stale/mocked fixes,
pause/leave/background cancellation, permission denial and delayed permission,
the Android permission-dialog lifecycle, readable legacy labels, presentation
bootstrap and Profile restart preserving data. Search regression checks also
reject visible numeric coordinate labels. Existing safety and small-layout tests
remain intact. A new movement test initially dragged the tile-loading chip;
the test now drags an unobstructed map point and asserts the camera actually
moved. A temporary misplaced widget caused a compile error and was corrected.
A new restart test initially used an invalid profile path; it now uses the
application route constant. None of those failed attempts is counted as a pass.

Native command:

```sh
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/live_services_test.dart -d 99031FFAZ007TR --keep-app-running --dart-define=ROADGUARD_API_URL=http://127.0.0.1:8000
```

**Passed, exit 0**: one end-to-end case, 21 seconds (`+2` includes teardown),
21.2-second Android build, 6.8-second installation. Real Django/Photon/OSRM
requests, readable endpoint selection, route geometry, trip start/pause/resume/
finish, native SQLite history and zero guest telemetry. This service test
explicitly denies device GPS through its injected adapter; it verifies recovery
UI without requesting a real permission or recording the user's position.
Moving GPS input is covered by deterministic widget tests, not a physical walk.
Visually inspected `search-directions.png` and `services-live-trip.png` under
`build/verification/design-2026-09-21/screenshots/`. The planner screenshot
caught tiles loading; the trip screenshot shows the actual route and recovery UI.

The React portal was inspected read-only: its pages still import `src/data/mock`
and its login is a mock. No connected web portal or web build/runtime validation
is claimed in this pass. The Wi-Fi guide includes its existing Vite launch
command and this limitation. Outdoor GPS accuracy/movement and a real Wi-Fi
connection remain manual acceptance checks. No backend code was changed or
backend test rerun required in this pass; earlier backend results below retain
their original scope. Existing Flutter TTS Kotlin compatibility, predictive-back
and skipped-debug-frame warnings remain.

Final presentation installation:

```sh
flutter run -d 99031FFAZ007TR --dart-define=ROADGUARD_API_URL=http://127.0.0.1:8000 --dart-define=ROADGUARD_PRESENTATION=true
```

Built successfully in 30.6 seconds, installed in 5.7 seconds, connected to the
Dart VM and visually verified the actual Pixel on the first onboarding page
with the light theme. No application exception appeared in inspected startup
output. Screenshot:
`build/verification/presentation-wifi-2026-09-21/pixel4-light-onboarding.png`.
Detached with `d` (exit 0); `adb shell pidof com.example.roadguard_ai` returned
`32040`, confirming the app remained running. Final presentation APK:
`build/app/outputs/flutter-apk/app-debug.apk`.

Before presenting: pair/reconnect Wi-Fi using the guide, unplug USB and verify
a successful backend refresh; replay onboarding with Profile → Restart
presentation if needed; finish the preserved existing trip before starting a
new route; grant foreground location and check movement outdoors. The current
USB validation does not substitute for those Wi-Fi and physical GPS checks.

## Explore search and vertical map controls — 21 September 2026

The top route button is now a search bar opening Directions, with searchable
starting point and destination fields, endpoint swapping and map-point fallback.
Explicitly submitted queries use the new Django `searchPlaces` endpoint and
Photon; selected labels are retained in OSRM routes and SQLite trip history.
My location, Report hazard and (when a trip exists) Resume trip are icon-only
48 dp buttons, vertically aligned at the bottom right in both connected and
demo Explore. Tooltips/spoken labels remain. Alert and location feedback stays
beside the controls. Permission, reporting and telemetry consent gates remain.

No package, SDK, native shell or lockfile changes were made. Photon public-demo
terms and official API metadata were consulted; this service has no uptime
guarantee. No automatic keystroke requests, synthetic places or hazard fixtures
are used. Backend limits and provider configuration are documented in
[LIVE_SERVICES.md](../../backend/docs/LIVE_SERVICES.md).

Commands actually run from `roadguard_ai/`, unless otherwise noted:

| Command | Actual result |
|---|---|
| `dart format lib test integration_test test_driver` | 107 files formatted, 3 changed on final formatting pass. |
| `flutter analyze` | Final: **No issues found**, 26.5 seconds, exit 0. |
| `flutter test --reporter expanded` | Final: **135 passed, zero failed**, 24 seconds, exit 0. |
| `docker compose run --rm web python manage.py test tests --noinput --verbosity 0` (`backend/`) | **94 passed**, 4.896 seconds, exit 0. |
| `docker compose restart web` (`backend/`) | Local service restarted successfully. |
| `curl -fsS --max-time 25 -H 'Content-Type: application/json' --data-binary @/tmp/roadguard-place-search.json http://127.0.0.1:8000/graphql/anonymous/` | Six real Photon matches returned for `Mlimani City, Dar es Salaam`, exit 0. |
| `adb -s 99031FFAZ007TR reverse tcp:8000 tcp:8000` (installed absolute adb path) | Restored the missing USB backend tunnel. |

The new Flutter regression checks search submission/selection for both endpoints,
icon-only vertical alignment and minimum touch targets. Existing movement,
camera/resume, stale GPS, consent, persistence and small-screen tests still pass.
Four backend tests cover search validation/results, cache/limiter behavior,
upstream failure and invalid coordinates. Initial Flutter failures were outdated
label expectations; these were updated for the requested UI without weakening
safety assertions. Analyzer findings (braces and an unused test import) were
fixed. An initial backend attempt timed out creating the test database; the full
retry above passed without database configuration changes.

Native command:

```sh
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/live_services_test.dart -d 99031FFAZ007TR --keep-app-running --dart-define=ROADGUARD_API_URL=http://127.0.0.1:8000
```

Final: **passed, exit 0**, one end-to-end test in 16 seconds (`+2` includes
teardown), 23.5-second Android build and 6.3-second installation. The Pixel 4
searched Photon for Mlimani City and Posta in Dar es Salaam, selected both
results, retrieved real OSRM geometry, started/paused/resumed/finished a trip,
verified Android SQLite history and zero guest telemetry. The first attempt
failed because the USB backend tunnel was absent; it is not counted as a pass.
The test used a dedicated database and guest session, preserving the user's
normal trip/account. No GPS permission or sensor collection was enabled.

Visually inspected actual Pixel screenshots:
`build/verification/design-2026-09-21/screenshots/services-explore.png` and
`search-directions.png`. They show the full map with right-hand icon controls
and actual selected search labels/coordinates. The test screenshot has no active
trip, so Resume is correctly absent. Existing debug skipped-frame,
predictive-back and `flutter_tts` future Kotlin compatibility warnings remain;
these checks do not certify performance or future Flutter versions.

Final normal launch:

```sh
flutter run -d 99031FFAZ007TR --dart-define=ROADGUARD_API_URL=http://127.0.0.1:8000
```

Successfully built the normal `lib/main.dart` debug APK in 22.9 seconds,
installed in 5.8 seconds and connected to the Dart VM. Visually verified the
actual Pixel Explore screen: real map tiles, successful live hazard refresh,
top search bar, and all three icons at the lower right with the user's existing
trip preserved. No application exception appeared in inspected startup logs;
debug startup reported skipped frames. Screenshot:
`build/verification/map-controls-2026-09-21/pixel4-final-explore.png`.
Detached with `d` to leave the normal app running. Normal APK:
`build/app/outputs/flutter-apk/app-debug.apk`.

To launch with the local backend and USB tunnel prepared:

```sh
bash /home/egovirdc/Downloads/RoadGuard_AI_Flutter/roadguard_ai/tool/run_presentation.sh 99031FFAZ007TR
```

Manual acceptance: open the top search bar, search/select each endpoint and
request directions; verify the three right-hand icons and their tooltips with
an existing trip; open the report form and confirm unknown GPS still blocks
saving; use My location only when ready to grant foreground permission. Public
Photon/OSRM and map tiles require connectivity. Actual outdoor GPS/camera and
opted-in sensor collection remain separate hardware acceptance checks.

## Report uploads, live road services and foreground telemetry — 21 September 2026

This entry supersedes earlier statements that mobile report uploads, routing,
hazards or registered foreground telemetry are disconnected. The implementation
and unresolved SRS boundaries are in [LIVE_SERVICES.md](../../backend/docs/LIVE_SERVICES.md).

Changes: anonymous photo/report upload with persisted idempotent retry and
server-ACK delivery labels; OSRM routes with actual geometry and SQLite history;
foreground Explore confirmed-hazard polling and transient red sheets; explicit
account/trip consent, native timestamped GPS/motion batches, owner/server-bound
outbox retry and revocation; PostGIS raw observation storage. Real and sample
trip labels are separate. Map routes use palette blue with a white outline for
contrast in both themes. Registration alone never starts sensors. No demo
reports or synthetic confirmed hazards were inserted in the running database.

No dependencies, SDKs, platform shells or lockfile versions were changed in this
pass. Existing installed Flutter/Dart/Android constraints and bootstrap/check
scripts were inspected. Backup before implementation:
`/tmp/roadguard-live-services-before/source.tar.gz`. The expected SRS copy in
`docs/` remains missing; the supplied original outside the app was consulted.
No privileged installation, Git commit/push or production deployment occurred.

Commands actually run from `roadguard_ai/`, unless noted:

| Command | Actual result |
|---|---|
| `dart format lib test integration_test test_driver` | Final: 105 files, zero changes. |
| `dart fix --apply --code=curly_braces_in_flow_control_structures` | Applied analyzer-requested braces; no test assertions removed. |
| `flutter analyze` | Final: **No issues found**, 15.1 seconds. |
| `flutter test --reporter expanded` | Final: **134 passed, zero failed**, 17 seconds, exit 0. |
| `flutter test test/widgets/live_services_test.dart --reporter expanded` | All 3 live UI cases passed. |
| `docker compose run --rm web python manage.py test tests --noinput --verbosity 0` (`backend/`) | **90 passed**, 3.201 seconds, exit 0; real disposable PostGIS test database. |
| `docker compose run --rm web python manage.py migrate --noinput` (`backend/`) | Applied `telemetry.0001_initial` successfully. |
| `docker compose run --rm web python manage.py makemigrations --check --dry-run` (`backend/`) | No changes detected. |
| `docker compose restart web` (`backend/`) | Local web service restarted with the new code. |
| `flutter devices` | Pixel 4 `99031FFAZ007TR`, Android 13/API 33 connected. |
| `adb -s 99031FFAZ007TR reverse tcp:8000 tcp:8000` (installed absolute adb path) | USB localhost tunnel set successfully. |
| `curl -fsS --max-time 25 -H 'Content-Type: application/json' --data-binary @/tmp/roadguard-route-smoke.json http://127.0.0.1:8000/graphql/anonymous/` | Real public OSRM response: two routes, 2967.6 m / 213.6 s and 2601.9 m / 227.1 s. Public-hazard query succeeded with an empty result. No fallback fixtures. |

Regression coverage includes lost upload ACKs, expired unclaimed photo retry,
mismatched ACKs, demo rejection, server-origin binding, stale/mocked GPS,
delayed permissions, account-isolated telemetry queues and explicit withdrawal.
Backend coverage verifies consent owner/trip/window, rejection of missing auth,
revocation across restarts, idempotent batch inserts, spatial points, malformed
observations and routing failures. UI coverage includes real-mode hazard
empty/error/confirmation/dismissal, planner-to-history persistence and 320px /
200% text layouts. Existing reporting camera/resume/movement safeguards still pass.

The initial full Flutter run found an image-decoding timing failure in the map
test: it passed alone, but a fixed 100 ms delay was insufficient under the full
suite. Replaced the fixed delay with a bounded wait for the observable decode
state, preserving every assertion. An initial new planner test dragged the map
instead of the page; it now scrolls the page margin and asserts controls are
reachable. Analyzer errors/lints in new test setup were fixed. One later
terminal session ended before the native local-flow result could be retrieved;
that attempt is not counted as a pass.

Native live-service command:

```sh
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/live_services_test.dart -d 99031FFAZ007TR --keep-app-running --dart-define=ROADGUARD_API_URL=http://127.0.0.1:8000
```

**Passed, exit 0**: one end-to-end case, 11 seconds (`+2` includes teardown),
142.6-second build and 6.5-second installation. Real HTTP to Django/PostGIS and
public OSRM; real Android SQLite in a dedicated test database; online map tiles.
Verified hazard query, map endpoint selection, returned route geometry,
start/pause/resume/finish/history and zero guest telemetry. No credentials,
location permission, camera capture or sensor consent were used in this test.
Screenshots were visually inspected:
`build/verification/design-2026-09-21/screenshots/services-explore.png` and
`services-live-trip.png`. The trip capture caught tiles still loading; it does
not certify all tiles decoded. The subsequent contrast/date-format polish is
covered by the final analyzer/tests and final normal APK.

Native existing-flow command:

```sh
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/local_flow_test.dart -d 99031FFAZ007TR --keep-app-running
```

**Passed, exit 0**: both native cases, 41 seconds (`+3` includes teardown),
27.9-second build and 6.2-second installation. Android SQLite open/reopen,
onboarding/preferences, demo trip recovery/pause/finish/history, real-report
unknown-GPS lock, sample moving lock, sample photo/notes/report save/detail/delete,
privacy/storage and zero telemetry passed. Native permission/camera/GPS quality
is not simulated as success. The test uses isolated DB/preferences and preserves
the installed app. Runtime output included skipped debug frames and Android's
existing predictive-back warning; no performance acceptance is claimed.

The first normal `flutter build apk --debug --dart-define=ROADGUARD_API_URL=http://127.0.0.1:8000`
attempt exited 1 after 98.2 seconds: Kotlin could not connect to its daemon and
the Gradle daemon disappeared. This attempt is not a successful build. The
existing `flutter_tts` future Kotlin-plugin compatibility warning also remains;
no dependency or system-wide Gradle setting was changed to hide it.

The exact same normal APK build command was retried with a fresh Gradle process:
**passed, exit 0**, 128.1 seconds. Final normal `lib/main.dart` debug APK:
`build/app/outputs/flutter-apk/app-debug.apk`, 252,996,441 bytes. The dependency
manifest and lockfile were compared byte-for-byte with the pre-edit snapshot and
are unchanged. `bash -n tool/run_presentation.sh` passed. A final
`curl -fsS --max-time 10 http://127.0.0.1:8000/health/` returned healthy PostgreSQL
and PostGIS. No global Gradle/Java configuration was changed.

Launch the presentation from any directory with:

```sh
bash /home/egovirdc/Downloads/RoadGuard_AI_Flutter/roadguard_ai/tool/run_presentation.sh 99031FFAZ007TR
```

Keep USB connected: the APK uses `http://127.0.0.1:8000` through `adb reverse`;
this is a local demonstration connection, not a deployed public backend.

Final normal launch:

```sh
flutter run -d 99031FFAZ007TR --dart-define=ROADGUARD_API_URL=http://127.0.0.1:8000
```

Built in 69.8 seconds, installed in 6.5 seconds and connected to the Dart VM
service. The normal app was visually verified on the physical Pixel: real OSM
map, successful live “No confirmed hazards in this view” state, visible
attribution, location/report controls and its preserved existing trip. No
application exception or SQLite error appeared in the inspected startup output.
Debug startup reported skipped frames; no performance target is claimed.
Screenshot: `build/verification/live-services-2026-09-21/pixel4-final-explore.png`.
The debugger was detached using `d`, leaving the normal app running; no user
account, trip, report or consent was cleared for this final inspection.

Remaining device acceptance: real stationary GPS/camera upload and actual
opted-in sensor sampling/ACKs need a deliberate outdoor test with the account
owner. Unit/API tests do not certify physical GPS quality, sensor rates, battery
use, motion classification or five-second SRS latency. Foreground collection is
implemented; background collection, DSP/ML/corroboration, automatic hazard
publication, live traffic/turn-by-turn directions, route proximity warnings,
remote notifications, email verification/recovery and full server erasure remain
unimplemented. Public OSRM is a presentation service without an uptime guarantee.
No latency/load/battery/rate target or production release certification is claimed.


## Presentation UI and real traveler authentication — 21 September 2026

This entry supersedes earlier descriptions of unavailable mobile authentication.
The existing Flutter app now connects registration/login/profile/logout to the
workspace Django/PostGIS backend. Passwords use server-side Argon2 hashing;
opaque seven-day sessions use Android secure storage, with only their token
digests in PostgreSQL. Expiry, deactivation, role/password changes and logout
invalidate sessions. The actual REST contract is documented in
[MOBILE_AUTH.md](../../backend/docs/MOBILE_AUTH.md); no GraphQL operation was invented.

Refreshed English login/register forms, validation/errors, password visibility,
autofill and loading states; removed simulated Google authentication. Onboarding
has three pages, persistent completion and a Profile replay action. Explore now
fills its content area with the live map, floating controls and a red sample
alert sheet. It dismisses after eight seconds, supports close/swipe/replay and
stays open for accessibility navigation. Attribution remains visible. Sample
alerts/routes and local-only reports remain explicitly labelled; signing in
does not grant sensor consent or enable collection. Existing reporting GPS,
camera/resume, freshness, motion and persistence safeguards remain covered.

Read the requested project documents and existing source before editing. No
applicable AGENTS.md was found; Git status is unavailable because the supplied
`.git` is not a usable repository. Pre-edit snapshot:
`/tmp/roadguard-presentation-before/source.tar.gz`. The expected
`docs/RoadGuard_AI_SRS.pdf` is still missing; the supplied original at
`/home/egovirdc/Downloads/RoadGuard_AI_SRS.pdf` was read. No SRS decisions were
silently resolved. Platform shells already exist; no regeneration, system-wide
configuration, SDK installation, commit, push or deployment was performed.

Only necessary dependency added: `flutter_secure_storage ^11.2.0`. Official
pub.dev metadata confirmed compatibility with Dart >=3.8, Flutter >=3.19 and
Android minSdk 24. Generated `pubspec.lock` is retained. The installed SDKs remain
Flutter 3.47.1 / bundled Dart 3.13.1, standalone Dart 3.13.3, Flutter-configured
JDK 17.0.20.1 and Android SDK 36. `flutter doctor -v` still reports unknown Android
license status; no license acceptance was performed.

Commands actually executed from `roadguard_ai/` unless otherwise stated:

| Command | Result |
|---|---|
| `flutter --version`, `dart --version`, `flutter doctor -v`, `flutter devices` | Inspected installed tools; physical Pixel 4 `99031FFAZ007TR`, Android 13/API 33, available. |
| `flutter pub get` | Passed; secure-storage dependency and generated lockfile resolved. Existing incompatible newer versions were not upgraded. |
| `dart format lib test integration_test test_driver` | Passed; final run 98 files, zero changes. |
| `flutter analyze` | Passed: no issues found, 12.4 seconds. |
| `flutter test --reporter expanded` | **121 passed, zero failed**, 14 seconds. Log: `build/verification/presentation-2026-09-21/flutter-test.log`. |
| `docker compose run --rm web python manage.py test tests --noinput --verbosity 0` (in `backend/`) | **82 passed**, 4.103 seconds, real PostGIS test database; includes runtime Argon2 roundtrip. |
| `docker compose run --rm web python manage.py migrate --noinput` (in `backend/`) | Passed; applied `accounts.0002_mobilesession` to the development database. |
| `docker compose run --rm web python manage.py makemigrations --check --dry-run` (in `backend/`) | Passed, no changes detected. |
| `docker compose restart web` (in `backend/`) | Passed; local Gunicorn serves the new auth endpoints. |
| `/home/egovirdc/Android/Sdk/platform-tools/adb -s 99031FFAZ007TR reverse tcp:8000 tcp:8000` | Passed; USB-only localhost backend connection. Debug cleartext is limited to localhost/127.0.0.1; release still requires HTTPS. |
| `bash -n tool/run_presentation.sh` | Passed. Launch/setup script documented in [PRESENTATION.md](PRESENTATION.md). |

Native real-authentication command:

```sh
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/presentation_auth_test.dart -d 99031FFAZ007TR --keep-app-running --dart-define=ROADGUARD_API_URL=http://127.0.0.1:8000 --dart-define=ROADGUARD_TEST_EMAIL=presentation-20260921-pass1@roadguard.example
```

**Passed, exit 0**: one end-to-end test, 27 seconds including teardown
(`+2` includes teardown); APK build 22.4 seconds, installation 6.2 seconds.
Verified real registration, persisted secure token, three onboarding pages,
persisted onboarding completion, alert replay/dismissal, restored session via
a fresh HTTP service, server profile identity, logout, wrong-password rejection,
successful subsequent login and zero telemetry records. Real HTTP, PostgreSQL
and Android secure storage were used. Text entry is controlled by Flutter's test
keyboard; map tiles are deterministic fixtures in this test, so these captures
are not evidence of internet map loading. The dedicated secure-storage key and
synthetic account were cleaned up; no existing account/app data was erased.
Six Android screenshots are under
`build/verification/design-2026-09-21/screenshots/presentation-*.png`; welcome,
login, registration, onboarding and warning sheet were visually inspected.

Early device runs revealed test-environment assumptions, not successful checks:
Android accessibility is enabled on this Pixel, so the sheet correctly does not
time out. The test now verifies explicit dismissal in that mode. Injecting text
while the real Android IME was active also overwrote a replacement password;
the test now uses controlled text entry and asserts exact field contents without
printing credentials. See Flutter's
[documented IME caveat](https://api.flutter.dev/flutter/flutter_test/TestTextInput/enterText.html).
The final native run above passed. Eight-second automatic dismissal and large
text/small-screen keyboard layouts pass separate widget regressions. Device
accessibility settings were preserved; TalkBack operation is not certified.

The established `flutter drive` runner is used because the earlier SDK
`flutter test` Android DDS/service-discovery issue is documented below. Initial
sandboxed Snap Flutter and redirected test commands failed; authorized terminal
runs succeeded. Initial analysis/test findings were corrected (lint, changed
labels, lazy Profile scrolling and alert overlays), without removing safety
assertions. Native logs contain existing debug skipped-frame/predictive-back
messages and the `flutter_tts` future Kotlin migration warning; these are not
performance or release certification.

Native local-flow command:

```sh
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/local_flow_test.dart -d 99031FFAZ007TR --keep-app-running
```

**Passed, exit 0**: two native test cases in 40 seconds (`+3` includes teardown),
build 20.6 seconds and install 6.1 seconds. Verified SQLite secure-delete and
close/reopen persistence, onboarding, account-page navigation, planner and route
map, trip pause/restore/resume/finish/history, unknown/moving reporting blocks,
sample photo/notes/local report save/detail/delete, appearance persistence,
permissions/privacy/storage screens and zero telemetry. SQLite/preferences are
isolated from the user's app data. Initial runs exposed a tap beneath the new
alert sheet after restoring a trip and a stale status-label expectation; the
test now dismisses the sheet and checks `Report sync not connected`. No safety
assertions were removed and hit-test warnings remain fatal.

Normal application build:

```sh
flutter build apk --debug --dart-define=ROADGUARD_API_URL=http://127.0.0.1:8000
```

**Passed, exit 0**, Gradle assembleDebug 114.6 seconds. APK:
`build/app/outputs/flutter-apk/app-debug.apk` (normal `lib/main.dart`, no test
entry point). This debug APK connects accounts to localhost through the USB
tunnel described in the presentation guide.

Final normal-device launch:

```sh
flutter run -d 99031FFAZ007TR --use-application-binary=build/app/outputs/flutter-apk/app-debug.apk --dart-define=ROADGUARD_API_URL=http://127.0.0.1:8000
```

Successfully installed in 8.5 seconds, launched `lib/main.dart` and connected the
VM service. Inspected the real OpenStreetMap basemap with the red sample sheet,
Guest Profile and sign-in field validation in the normal Android app. Captures
are `build/verification/presentation-2026-09-21/normal-live-map.png`,
`normal-profile.png` and `normal-sign-in-validation.png`. No credentials were
entered or stored during this final visual check. The app was returned to Explore
and the debugger detached with `d`; the process remained running on the Pixel.
Filtered `adb ... shell logcat -d --pid=22759 -s AndroidRuntime:E flutter:E`
returned no errors. The earlier attempt through `tool/run_presentation.sh` lost
its tool process session before completion could be observed, so no successful
launcher execution is claimed for that attempt. `docker compose ps` subsequently
confirmed healthy API and PostGIS containers, and USB forwarding was restored
before the successful direct launch above.

Launch from any directory (phone connected/unlocked, Docker running):

```sh
bash /home/egovirdc/Downloads/RoadGuard_AI_Flutter/roadguard_ai/tool/run_presentation.sh 99031FFAZ007TR
```

Manual presentation checklist:

- Profile → Create account with your own email and a unique 12+ character password.
- Show the returned profile identity, sign out, then sign back in.
- Profile → View introduction replays onboarding without erasing preferences.
- Explore: pan/zoom, replay the warning, close it, and show the unobstructed map.
  On this accessibility-enabled Pixel use Close; the automatic timer is paused.
- Explain that routes/alerts are samples and reports remain local. Unknown or
  moving GPS must keep manual reporting blocked; login must not start sensors.

Remaining integrations: email verification/recovery, finalized legal acceptance,
account erasure, deployed HTTPS backend, mobile report uploads, live routing and
hazard delivery, authenticated sensor consent/collection and remote notifications.
Presentation login requires the laptop backend and USB tunnel; the basemap needs
internet. GPS denial/permanent-denial variants, actual-motion reporting,
camera recovery, TalkBack and iOS remain broader manual acceptance work.

## Live map and foreground location — 21 September 2026

Implemented the user's request in the existing `roadguard_ai/` app, preserving the RIDC module organization, Riverpod, palette, SQLite and reporting rules. Explore, planner's View on map and active-trip preview now use `flutter_map 8.3.2` with real HTTPS OpenStreetMap tiles. Added `latlong2 0.10.1` and `url_launcher 6.3.2`; official pub.dev metadata confirmed compatibility with installed Flutter 3.47.1 / Dart 3.13.1. Retained the generated lockfile. No project regeneration or system-wide configuration change was performed.

The map supports pan/zoom, visible linked attribution, a 100 MB soft native cache respecting HTTP freshness, decoded-tile loading/error/retry states and an optional real GPS marker. No bulk download, fabricated route geometry, or geographic placement of sample hazards was added. The retained illustration widget still serves explicitly illustrative screens. Routes, times and hazard statuses remain samples; this is not live navigation.

Explore's My location action explicitly requests foreground location. Its subscription and marker stop on Stop location, route coverage, app inactivity or disposal. Pending permission responses cannot restart an ended session, and returning does not automatically resume GPS. Map positions must be real, finite, within coordinate bounds, from the current session, no more than 10 seconds old and have positive accuracy no worse than 5 km. The 5 km display limit is an engineering display choice, not a reporting threshold or approved SRS requirement. Movement is allowed on the map; reporting independently retains its stricter stationary/freshness/25 m gate. Seven report/photo/safety implementation files were compared with the pre-change snapshot and are byte-identical.

Android's existing INTERNET, ACCESS_COARSE_LOCATION and ACCESS_FINE_LOCATION declarations were sufficient. Verified the installed package declarations and existing location grants with `adb -s 99031FFAZ007TR shell dumpsys package com.example.roadguard_ai`. AndroidX also contributes its private signature-protected receiver permission. No background location, foreground location service, notifications, camera, microphone or broad storage grant was added. Updated iOS purpose text and the idempotent platform overlay; retained its existing Always compatibility key because this project uses SwiftPM, with the resolved plugin requesting WhenInUse. iOS was not built/tested. See [PERMISSIONS.md](PERMISSIONS.md) for official sources and exact rationale.

Map/privacy screens now disclose that OpenStreetMap receives viewed tile areas, IP and app identification; centering GPS reveals that approximate area. Cached map tiles are separate from SQLite and are not erased by Clear local data. No auth, sensor consent, telemetry or server submission is fabricated.

Source snapshot: `/tmp/roadguard-live-map/source-before.tar.gz`. The requested `docs/RoadGuard_AI_SRS.pdf` remains missing at that path; the original and unresolved decisions documented in earlier records are unchanged. No source file was removed and no commit, push or deployment occurred.

Commands and observed results from `roadguard_ai/`:

| Command | Result |
|---|---|
| `flutter devices` | Physical Pixel 4 `99031FFAZ007TR`, Android 13/API 33; Linux and Chrome also available. |
| `flutter pub get` | Passed; resolved all three new direct dependencies and their platform/transitive dependencies. Nine newer incompatible transitive versions were not upgraded. |
| `bash tool/bootstrap.sh` | Passed, exit 0. Existing native shells reused; foreground overlay applied without replacing application source. Printed Flutter 3.47.1 / Dart 3.13.1. |
| `dart format lib test integration_test test_driver` | Final pass: 91 files, one formatted, exit 0. |
| `flutter analyze` | Passed twice: initial 26.7 seconds; final **no issues found**, 12.2 seconds, exit 0. |
| `flutter test --reporter expanded` | Initial complete run **107 passed**, 16 seconds, exit 0. |
| `flutter test test/widgets/live_map_tiles_test.dart` | **3 passed**: decoded tiles, attribution/marker ownership and failed-image retry. Deliberately invalid image fixtures emit expected decode messages. |
| `flutter test test/widgets/map_location_lifecycle_test.dart --reporter expanded` | Final focused run **4 passed**, 2 seconds. An earlier test incorrectly expected the browser URL to change on imperative push; now it asserts the visible planner and immediate GPS cancellation. Explore observes the router delegate's actual top route. |
| `flutter test --coverage --reporter expanded` | Final complete run **111 passed, 0 failed**, 17 seconds, exit 0. Coverage in `coverage/lcov.info`. |

The final `tool/check.sh` wrapper invocation was interrupted before an exit status was available; no success is claimed for that wrapper. Its component commands above were completed explicitly. Native overlay fixture validation also passed: Python syntax, repeat-run byte identity, preservation of custom native fields, and no duplicated or background permissions.

Native checks on the physical Pixel 4:

| Command | Result |
|---|---|
| `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/live_map_test.dart -d 99031FFAZ007TR --keep-app-running` | **Passed, exit 0**: one real-network native case, 7 seconds (`+2` includes teardown); build 48.1 seconds and install 5.9 seconds. Real OSM tiles decoded, a small pan loaded successfully, attribution stayed visible and no invented GPS marker appeared. Two Android screenshots captured and inspected. |
| `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/local_flow_test.dart -d 99031FFAZ007TR --keep-app-running` | **Passed, exit 0**: two native cases, 39 seconds (`+3` includes teardown); build 25.5 seconds, install 8.1 seconds. Native SQLite and the complete local journey/report flows passed using explicitly injected in-memory tile images. This second run is not network-tile evidence. |

The first two network-test build attempts failed while Gradle downloaded AndroidX artifacts from Google's Maven repository (`Temporary failure in name resolution`). An official Maven `curl -fsS --max-time 25` request and host `getent ahosts dl.google.com` succeeded. `./gradlew --stop` stopped two build daemons; the subsequent unchanged build succeeded. No dependency downgrade, repository substitution, certificate bypass or DNS settings change was used.

The existing device-test DDS issue is handled by the previously established `flutter drive` runner; `flutter test -d` was not rerun in this pass. Test databases/preferences remained isolated and both driver invocations used `--keep-app-running` to preserve installed user data. Runtime output has expected debug skipped-frame messages, flutter_map's OSM policy notice and the existing TTS future Kotlin-migration / predictive-back warnings. Passing native test logs show no application exception; performance and accessibility certification are not claimed.

Evidence: `build/verification/live-map-2026-09-21/analysis.log`, `flutter-tests.log`, `native-map.log`, `native-local-flow.log`, and `screenshots/live-map-loaded.png` / `live-map-panned.png`. The latter captures are actual Android Flutter map tiles, not HTML or fixture imagery.

`flutter build apk --debug` passed with exit 0; Gradle assembleDebug took 106.9 seconds. It produced the normal application APK at `build/app/outputs/flutter-apk/app-debug.apk` (219,688,634 bytes before the subsequent device-specific launch rebuild). Build output is saved in `build/verification/live-map-2026-09-21/build.log`. `flutter run -d 99031FFAZ007TR` then rebuilt the normal `lib/main.dart` app in 50.4 seconds, installed in 6.6 seconds and connected to the VM service. The resulting device-specific APK is 179,603,781 bytes at the same path. Explore's real map and controls were visually inspected. Tapping My location used the existing foreground location grant and displayed a real marker with reported accuracy ±20 m; native logs recorded location updates starting and stopping. Concurrent device interaction makes the subsequent manual navigation sequence unsuitable as independent route-cancellation proof; the four deterministic lifecycle widget tests above provide that coverage. No real report was submitted. Screenshots `normal-gps-location.png` and `normal-alerts.png` are saved beside the two native map-test captures; an incidental OS-notification capture was replaced with a clean app capture. The debugger was detached with `d`, leaving the installed app open. Run output is in `run.log`.

Launch from the workspace root:

```sh
cd /home/egovirdc/Downloads/RoadGuard_AI_Flutter/roadguard_ai && flutter run -d 99031FFAZ007TR
```

Remaining integrations: live routing/geocoding and hazard feeds, backend account/authentication, approved GraphQL/media operations, server report submission, authenticated consent/background telemetry and remote notifications. Full fresh-install OS permission denial/permanent-denial/approximate-grant variants, real-motion reporting, camera recovery, TalkBack and iOS remain manual/device acceptance work. Do not treat map tile access as verified road conditions.

Manual acceptance checklist: browse/pan/zoom and open attribution; tap My location, then Stop location; leave/background and verify a new explicit request is required; exercise denied/offline/error/retry states; inspect sample route map and preview; verify moving or unknown GPS still blocks real reporting and saved reports remain local-only.

## Attached design implementation — 21 September 2026

Implemented the user's eight-screen image in the existing Flutter traveler app, retaining the RIDC template organization, Riverpod, native SQLite and the supplied palette. The Figma URLs were inaccessible (HTTP 403); the attached screenshot is the visual source, not a claim that Figma layers were inspected.

Changes include the photograph-backed welcome, sign-in/register UI with explicit unavailable-service state, Explore/Alerts/Profile navigation, full-area illustrated Explore map, compact two-route chooser and map sheet, trip map with a rounded information panel, report category/location/photo cards, and guest profile navigation. Existing onboarding, history, report list/detail, privacy and permissions remain available. The generated generic road photograph and its full prompt are recorded in [DESIGN_ASSETS.md](DESIGN_ASSETS.md).

Preserved required report photos even though the reference says optional; retained `Save local report` and `Finish preview` labels so the client does not imply server submission or live navigation. Authentication forms do not transmit/persist inputs, create sessions, mark onboarding complete, or record consent. GPS safety policy, report lifecycle/actions, report/trip controllers, storage, native GPS/photo services and pubspec.lock are byte-identical to the pre-edit snapshot. No dependency versions or native configuration changed.

Workspace Git status still fails because the supplied `.git` is not a usable repository. No applicable AGENTS.md was found. Snapshot: `/tmp/roadguard-design-pass/source-before.tar.gz`. The requested `docs/RoadGuard_AI_SRS.pdf` remains missing; the original was previously read at `/home/egovirdc/Downloads/RoadGuard_AI_SRS.pdf`. Its decisions and ambiguities were not changed.

Commands and observed results (from `roadguard_ai/`):

| Command | Result |
|---|---|
| `flutter --version` | Flutter 3.47.1 stable, bundled Dart 3.13.1. |
| `dart --version` | Standalone Dart 3.13.3. |
| `flutter doctor -v` | Android SDK/build-tools 36.0.0, configured Temurin JDK 17.0.20.1; Android license status remains unknown. No SDK installation or license acceptance performed. |
| `flutter devices` | Physical Pixel 4 `99031FFAZ007TR`, Android 13/API 33; Linux and Chrome also listed. Initial sandboxed Snap invocation failed; authorized host invocation succeeded. |
| `flutter pub get` | Passed; asset registration added, dependency versions and generated lockfile retained. Five newer transitive versions outside constraints were not upgraded. |
| `bash tool/check.sh` | Final terminal run passed, exit 0. A redirected invocation exited 255 without diagnostics; terminal execution worked. |
| `flutter analyze` | No issues found: check-script run 15.0 seconds; final focused-check run after map polish 16.6 seconds. |
| `flutter test --coverage` (check script) | **80 passed, 0 failed**, final run 14 seconds. |
| `dart format lib test integration_test test_driver` | Passed: 84 files, one driver file formatted. |

The first test run found two issues: profile shell navigation retained the previous route URI, and the active-trip expansion tile lacked a visible Material ink surface. Fixed both implementation problems. Review also identified an obscured second route hazard, now accessible through an explicit detail action with a regression test. Existing safety assertions were retained; new coverage verifies account unavailability/guest routing, large-text forms, the route map sheet and the second hazard at 320px/200% text. Both light/dark layout and GPS/camera lifecycle regressions pass.

Check logs: `build/verification/design-2026-09-21/check.log` and `check-first-terminal.log`. Coverage: `coverage/lcov.info`.

Native checks completed on the physical Pixel 4:

| Command | Result |
|---|---|
| `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/local_flow_test.dart -d 99031FFAZ007TR --keep-app-running --dart-define=ROADGUARD_CAPTURE_UI=true` | **Passed, exit 0**: 2 native test cases in 45 seconds (`+3` includes teardown). Integration APK build 61.3 seconds, install 5.0 seconds. 12 screenshots saved. |
| `flutter build apk --debug` | **Passed, exit 0**, Gradle assembleDebug 153.8 seconds. Normal application entry point. |
| `flutter test test/widgets/ui_layout_test.dart test/widgets/trip_hazard_navigation_test.dart --reporter expanded` | **10 passed, 0 failed**, 4 seconds, after correcting map marker proportions during screenshot review. |

The integration flow exercised the welcome and account-page navigation without creating an account, all three onboarding pages and persisted completion, Explore/Alerts, route map sheet, endpoint swap/alternative route, pause/restore/resume/finish/history, unknown-GPS and moving-sample reporting locks, sample photo and notes, local report save/detail/delete, both appearance preference writes, permission/privacy/storage pages and zero telemetry rows. SQLite and preference keys were isolated; the runner retained the installed package and did not clear normal user data.

Screenshots under `build/verification/design-2026-09-21/screenshots/` cover welcome, sign-in, registration, Explore, Alerts, route choice/map, active trip, profile, locked/demo report form and local detail. These are Android Flutter captures, not HTML renders. The device system theme selected dark mode for this integration run. Inspecting the captures prompted a final cosmetic correction so route markers and navigation arrows retain their proportions on tall maps; analysis and the 10 relevant UI regressions passed afterward.

The existing `flutter test` Android DDS/service-discovery problem documented below was not retried; the already validated `flutter drive` runner executes the same test file. Flutter TTS logs its existing future Kotlin-plugin migration warning. Device logs include debug skipped frames and the existing predictive-back warning, with no application exception during the passing flow. These runs are not performance or accessibility certification.

Final normal-app launch: `flutter run -d 99031FFAZ007TR` rebuilt the final source (including the map proportion correction) in 79.9 seconds, installed in 5.2 seconds and connected to the VM service. Light-mode Explore, guest Profile and GPS-locked Report were visually inspected on the physical phone; screenshots `13-normal-explore.png`, `14-normal-profile.png` and `16-normal-report-locked.png` are in the directory above. The existing active preview remained available after startup. The debugger later reported `Lost connection to device`; a subsequent ADB process check confirmed the app was still running (PID 32258), and filtered AndroidRuntime/flutter logs contained no exception. The app remains open on Pixel 4; debugger attachment is not claimed to remain active.

Final APK: `build/app/outputs/flutter-apk/app-debug.apk`, 137,431,393 bytes, rebuilt by the final device launch. This is the normal `lib/main.dart` app, not the integration-test entry point. Build/run logs are `build.log` and `run.log`; device-flow output is `integration-drive.log`; final analysis/layout checks are `final-ui-check.log`, all under `build/verification/design-2026-09-21/`.

Remaining integrations: backend authentication/registration/Google/recovery, registration terms and authenticated consent, live map/routing/hazards, approved GraphQL/media upload and server report submission, background telemetry, remote notifications and server erasure. Real GPS accuracy/physical motion, camera cancellation/retake/process recovery, OS process death, TTS audio, TalkBack and performance remain manual acceptance work. No Android licenses or system settings were changed; iOS/web/release signing were not validated in this pass. SRS ambiguities remain unresolved.

Launch from the workspace root:

```sh
cd /home/egovirdc/Downloads/RoadGuard_AI_Flutter/roadguard_ai && flutter run -d 99031FFAZ007TR
```

Short manual acceptance checklist:

- On a fresh local profile, welcome → Get Started → onboarding → guest; after relaunch, onboarding stays completed. Existing device data is preserved, so existing users open Explore.
- Explore → route choice/map → trip preview; pause/resume/finish and inspect history. Open every route hazard.
- Report form stays locked for unknown/moving/stale GPS; after camera/resume, require fresh stationary evidence. A photo remains required. Confirm sample reports say DEMO/local-only.
- Profile opens My Routes, Reported Incidents and account UI. Unavailable sign-in must not create a session; verify light/dark, large text, keyboard and TalkBack on the phone.

## RIDC template adoption — 21 September 2026

Inspected the user's local `/home/egovirdc/Desktop/flutter_template` at revision `797af815d4e8fe7190382b47cf0f9b8693308261`. The existing modification to its `lib/shared/providers_list.dart` remains untouched. The earlier remote clone could not connect to port 9000; the local source supplied by the user unblocked the work. No remote push, commit or system configuration change was performed.

RoadGuard now follows the template's `app.dart`, `core/injection`, `core/routes`, feature `modules` and `shared` organization. Existing screens and 22 provider/controller declarations were relocated; the former paths remain as compatibility exports. Added feature-owned path constants, encoded detail IDs, modular GoRouter composition, and a testable persisted-state bootstrap. The recovery screen remains retryable and now scrolls on short displays. See [TEMPLATE_ADOPTION.md](TEMPLATE_ADOPTION.md) for the exact mapping and retained integration boundaries.

Pre-edit source snapshot: `/tmp/roadguard-template-adoption/source-before.tar.gz`. Comparison confirmed that pubspec/lockfile, palette, SQLite/settings implementations, GPS and photo services, safety policy and Android manifest remain unchanged. A focused review found no import/export cycles or duplicate state owners. The eight additional tests exercise persisted state restoration/recovery, onboarding route guards, shell navigation and encoded local report IDs. Existing tests and assertions were retained.

| Command | Result |
|---|---|
| `python3 tool/source_audit.py` | Passed local import/delimiter checks; this is only a source sanity check. |
| `bash tool/check.sh` | Final run passed, exit 0: dependency resolution, formatting, analyzer and coverage tests. |
| `flutter pub get` (inside check script) | Passed; existing dependency constraints and lockfile retained. |
| `dart format lib test integration_test` | Final run: 75 files, 0 changes. |
| `flutter analyze` | Final run: no issues, 21.7 seconds. Initial run found a missing safety-policy extension import after provider extraction and one brace lint; both corrected. |
| `flutter test --coverage` | **73 passed, 0 failed**, 27 seconds; coverage regenerated. |
| `flutter devices` | Pixel 4 `99031FFAZ007TR`, Android 13/API 33; Linux and Chrome also available. |
| `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/local_flow_test.dart -d 99031FFAZ007TR --keep-app-running` | **Passed, exit 0**: both native cases in 34 seconds; `+3` includes teardown. Integration APK build 199.0 seconds, install 5.4 seconds. Runner retained the package instead of uninstalling it. |
| `flutter build apk --debug` | **Passed, exit 0**; normal `lib/main.dart` entry point, Gradle assembleDebug 82.9 seconds. APK: `build/app/outputs/flutter-apk/app-debug.apk`. |
| `flutter run -d 99031FFAZ007TR --use-application-binary=build/app/outputs/flutter-apk/app-debug.apk` | Installed the normal app in 6.7 seconds, launched successfully and connected to the Dart VM service. Left running on Pixel 4; no application exception or SQLite startup failure observed. |

Check output is saved in `build/verification/template-2026-09-21/check.log`; the initial analyzer findings are in `check-first.log` and the successful device run is in `integration-drive.log` in that directory. Native tests exercised actual SQLite/preferences, onboarding, planner, trip restoration/history, GPS-unknown/sample-moving locks, demo report save/detail/delete, appearance, permissions/privacy and zero telemetry. They used isolated test databases/preferences and explicit sample photos; real GPS/camera hardware acceptance remains outstanding. Existing flutter_tts Kotlin migration, predictive-back and debug skipped-frame warnings remain; these did not fail the checks.

The final normal-app Explore screen was visually inspected on Pixel 4. It shows the supplied palette and an existing trip's resume action after persisted initialization. Screenshot: `build/verification/template-2026-09-21/pixel4-startup.png`; final build and launch logs are `build.log` and `run.log` in the same directory. No baseline file was removed, and existing test files are byte-identical to the snapshot. Launch from the workspace root with:

```sh
cd /home/egovirdc/Downloads/RoadGuard_AI_Flutter/roadguard_ai && flutter run -d 99031FFAZ007TR
```

Authentication, live maps/routing, server report submission/sync, background telemetry and remote notifications remain unimplemented; adopting template structure does not establish these integrations. The SRS ambiguities remain unresolved.

## Palette update — 21 September 2026

Applied the user's reference colors to the actual Flutter UI: navy `#161D2E`, blue `#1B6BEC`, green `#1CA24B`, red `#DB2A2A`, pink `#FEC6C6`, sky `#DAE9FE`, mint `#DBFCE6`, cream `#FEF3C6`, and white. Updated shared Material light/dark themes, maps, onboarding, planner/trip panels, report/error states, badges, demo notices and profile. Supporting neutral/deeper text colors preserve readable contrast. Dialog backgrounds and snackbar action colors avoid low-contrast blue text on pale blue. Application logic, labels, persistence, reporting safeguards and dependency versions were not changed.

No new AGENTS.md was found. Git status still reports that the workspace is not a Git repository. The pre-edit source snapshot is `/tmp/roadguard-palette/source-before.tar.gz`.

Commands executed for this update:

| Command | Result |
|---|---|
| `dart format lib` | Final run passed: 26 files, 0 changes. The first sandboxed invocation formatted three files but exited 1 on its external telemetry-session file; rerun outside the sandbox passed. |
| `flutter analyze` | Passed twice; final run: no issues, 22.3 seconds. |
| `flutter test` | Passed: 65 tests, 0 failures, 11 seconds. Includes both themes at 320px/200% text and reporting safeguards. |
| `flutter test /tmp/roadguard-palette/capture_test.dart --reporter expanded` | Both capture runs passed: five screens in each theme. The temporary rendering harness uses memory stores and inactive native adapters. Images in `build/verification/palette-2026-09-21/` were inspected for color placement; test-font block glyphs limit typography review. This is not Android device validation. |
| `flutter build apk --debug` | Passed, exit 0; Gradle assembleDebug 261.4 seconds. Produced the updated normal application at `build/app/outputs/flutter-apk/app-debug.apk`. The build logged a Kotlin daemon connection error and the existing flutter_tts KGP migration warning, but ultimately completed successfully. No SDK or system configuration change was made. |
| `flutter devices` | Initial host check showed Linux/Chrome only. Final check detected Pixel 4 `99031FFAZ007TR`, Android 13/API 33. The first sandboxed Snap invocation failed; permitted host invocations succeeded. |
| `flutter run -d 99031FFAZ007TR --use-application-binary=build/app/outputs/flutter-apk/app-debug.apk` | Installed the freshly built APK in 7.9 seconds, launched `lib/main.dart`, and connected to the VM service. Left running on Pixel 4. No application exception or SQLite failure was observed in startup logs; debug startup logged skipped frames. |

Captured and visually inspected the updated dark profile screen on the physical Pixel 4: `build/verification/palette-2026-09-21/pixel4-profile.png`. Native text/icons render correctly, with navy surfaces, sky controls and mint accents. The launch log is stored alongside it as `run.log`. No app uninstall or data-clearing operation was used for this update.

The shared status text pairs were checked numerically: mint status 6.51:1 in light mode and 11.00:1 in dark mode; cream warning text 6.92:1; dark red on pink 4.99:1; white on the blue primary button 4.82:1. These checks are not a complete accessibility certification. The HTML companion and raster launcher icons retain the previous design reference. The earlier Android integration results below describe the 18 September build; the full native flow suite was not repeated for this color-only update.

# Android implementation and validation — 18 September 2026

## Scope and source review

This pass validates the existing Flutter traveler demo on Android. It does not complete the RoadGuard platform or certify SRS acceptance. The HTML companion was inspected as a design reference; no native claim below relies on it.

Read README, architecture, traceability, GraphQL contract, acceptance, previous validation, pubspec, bootstrap/check scripts, and application/test sources. No applicable AGENTS.md was found. `docs/RoadGuard_AI_SRS.pdf` is absent; the original 26-page PDF was found and read at `/home/egovirdc/Downloads/RoadGuard_AI_SRS.pdf`. Its unresolved appendix and provisional architecture decisions remain unresolved.

`git status --short` failed because the supplied `.git` directory is not a usable Git repository. A pre-edit source snapshot was saved at `/tmp/roadguard-validation/source-before.tar.gz`; source comparisons confirmed pubspec.yaml, pubspec.lock, Android application ID, MainActivity and Gradle plugin settings were preserved. No commits, pushes or destructive Git commands were performed.

## Toolchain actually checked

| Command | Observed result |
|---|---|
| `flutter --version` | Flutter 3.47.1 stable, framework 6655482ec0; bundled Dart 3.13.1 |
| `dart --version` | Standalone Dart 3.13.3 |
| `java -version` | Default shell Java 26.0.2; Flutter uses the existing configured Temurin JDK 17.0.20.1 |
| `flutter doctor -v` | Android SDK/build-tools 36.0.0, installed platform android-37.0; one toolchain warning: Android license status unknown |
| `flutter devices` | Pixel 4, `99031FFAZ007TR`, Android 13 / API 33, arm64; also Linux and Chrome |

The device was initially disconnected, then reconnected by the user. No SDK/JDK installation, license acceptance or system-wide configuration change was made. The existing Android build tools successfully built and installed development APKs despite the doctor warning.

## Dependency verification

The installed SDK satisfies `sdk: >=3.13.0 <4.0.0` and `flutter: >=3.47.0`. Package versions were checked against official pub.dev publisher metadata and downloaded package pubspecs, followed by actual dependency resolution and compilation. No dependency version change was needed; the existing generated lockfile remains unchanged.

| Direct package | Locked version | Declared Dart / Flutter minimum |
|---|---|---|
| [flutter_riverpod](https://pub.dev/packages/flutter_riverpod/versions/3.4.3) | 3.4.3 | Dart 3.12 / Flutter 3.0 |
| [go_router](https://pub.dev/packages/go_router/versions/18.0.1) | 18.0.1 | Dart 3.12 / Flutter 3.44 |
| [shared_preferences](https://pub.dev/packages/shared_preferences/versions/2.5.5) | 2.5.5 | Dart 3.9 / Flutter 3.35 |
| [sqflite](https://pub.dev/packages/sqflite/versions/2.4.4) | 2.4.4 | Dart 3.12 / Flutter 3.44 |
| [geolocator](https://pub.dev/packages/geolocator) | 14.0.3 | Dart 3.5 / Flutter 2.8 |
| [image_picker](https://pub.dev/packages/image_picker) | 1.2.3 | Dart 3.10 / Flutter 3.38 |
| [image](https://pub.dev/packages/image/versions/4.10.1) | 4.10.1 | Dart 3.0 |
| [flutter_tts](https://pub.dev/packages/flutter_tts/versions/4.2.5) | 4.2.5 | Dart 3.4 / Flutter 1.22 |
| [sensors_plus](https://pub.dev/packages/sensors_plus/versions/7.1.0) | 7.1.0 | Dart 3.3 / Flutter 3.19 |
| [http](https://pub.dev/packages/http/versions/1.6.0) | 1.6.0 | Dart 3.4 |
| [flutter_lints](https://pub.dev/packages/flutter_lints/versions/6.0.0) | 6.0.0 | Dart 3.8 |

Flutter's SDK archive was also consulted: https://docs.flutter.dev/install/archive. `pub get` reported five newer transitive packages outside the current constraints; these were not unnecessarily upgraded. The Android image_picker package requires no extra camera permission declaration for its camera-intent flow, per its publisher documentation.

## Implementation changes

- Retained and regression-tested the Android startup correction: row-returning `PRAGMA secure_delete = ON` uses `rawQuery`, not `execute`.
- Ran the inspected bootstrap. It generated only missing iOS/web shells in a temporary project, preserved the existing Android shell/application source, and applied foreground location permissions, TTS package visibility, branding, API 24 minimum, disabled backup and disabled production cleartext traffic. iOS/web were not compiled in this pass.
- Reporting now explicitly owns its Riverpod GPS subscription, releasing it on background/camera entry without waiting for another frame. Camera return, cancellation, photo recovery and resume require fresh evidence. Capture/save check the newest GPS event. Permission errors retain retry/settings actions.
- Malformed or truncated JPEG/PNG input now produces a friendly FormatException instead of leaking decoder RangeError. Valid PNG is sanitized to JPEG; unsupported image formats are rejected.
- Polished actual Flutter layouts: responsive Explore headers/cards, trip controls/metrics, route estimates and storage counts; scrollable selection sheets/dialogs/empty states; bounded map/onboarding labels; compact-height onboarding controls scroll with content. Ink/forest-green/lime, English labels and Riverpod remain.
- Added regressions without removing assertions. Existing report tests now explicitly select the page scrollable. Integration taps wait for scrolled layouts and fail on missed hit tests.
- Added optional database paths/preference keys for isolated native tests and a standard integration driver as a workaround for the observed SDK runner issue.

Strict positive-speed blocking, invalid/unknown/stale location rejection, permanent demo tags, local-only report status and disabled guest telemetry remain. No GraphQL operations, accounts, submissions or live maps were invented.

## Commands executed and final results

Commands below ran from `roadguard_ai/` unless otherwise specified.

| Command | Result |
|---|---|
| `bash tool/bootstrap.sh` | Passed; missing shells generated and overlays applied |
| `flutter pub get` | Passed; lockfile retained, no dependency changes |
| `dart format lib test integration_test` | Passed through `tool/check.sh`; 36 Dart files formatted |
| `dart fix --apply --code=curly_braces_in_flow_control_structures` | Applied 23 analyzer-suggested brace fixes |
| `flutter analyze` | Passed: **No issues found!** |
| `flutter test --coverage` | Passed: **65 tests**, **0 failures**, about 10 seconds; `coverage/lcov.info` generated |
| `bash tool/check.sh` | Passed with exit 0 after the corrections above |
| `flutter test test/widgets/ui_layout_test.dart --reporter expanded` | Passed: 8 UI regressions |
| `flutter test test/domain/report_regression_test.dart test/widgets/report_lifecycle_test.dart --reporter expanded` | Passed: 12 reporting regressions |
| `flutter test integration_test/local_flow_test.dart -d 99031FFAZ007TR` | First run: SQLite test passed; UI test found a scroll/tap timing defect, corrected. Subsequent runs stalled before test startup and were interrupted; not claimed passing |
| Same native test command with `-v` | Confirmed the wait was at integration service-extension discovery |
| Same native test command with `--no-dds` | Both test bodies passed, but the command exited 1 due to SDK `streamListen` invalid-parameter error for `integration_test.VmServiceProxyGoldenFileComparator`; not claimed a passing command |
| `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/local_flow_test.dart -d 99031FFAZ007TR --keep-app-running` | **Passed, exit 0**: both native test cases. Device log ends `00:33 +3: All tests passed!` (runner count includes teardown); driver confirms `All tests passed.` |
| `dart format lib test integration_test test_driver` | Passed: 37 files, 0 changes. Follow-up `flutter analyze` also passed with no issues (95.2 seconds) |
| `flutter build apk --debug` | Passed, exit 0; normal `lib/main.dart` entry point, Gradle assembleDebug completed in 150.6 seconds |
| `flutter run -d 99031FFAZ007TR` | Passed: normal app built (52.6 seconds), installed (5.8 seconds), launched on Pixel 4 and connected to the Dart VM service; left running for development |

Initial analyzer runs found lint issues (14 before formatting; 23 exposed after formatting), all resolved. The first full suite found malformed-image error handling and an ambiguous report-test scroll finder; both were fixed and the full suite rerun successfully. A redirected Snap analyzer invocation exited 255 without diagnostics; subsequent terminal-attached execution succeeded.

Logs from successful checks and native drive are in `build/verification/check.log` and `build/verification/integration-drive.log`. Final build and launch logs are in `build.log` and `run.log` in that directory. Diagnostic native attempts are in `integration-first.log` and `integration-direct-vm.log`. Build/coverage artifacts are local and ignored by version control.

The normal app's onboarding screen was captured and visually inspected on the physical Pixel 4: `build/verification/pixel4-final-onboarding.png`. The startup log contained no application exception or SQLite initialization error. Debug startup reported skipped frames, and subsequent runtime logs warned that Android predictive-back callback support is not enabled; no performance or predictive-back acceptance is claimed.

The normal debug APK is `build/app/outputs/flutter-apk/app-debug.apk`. Launch from the workspace root with:

```sh
cd /home/egovirdc/Downloads/RoadGuard_AI_Flutter/roadguard_ai && flutter run -d 99031FFAZ007TR
```

## Native flows exercised

The two integration cases executed on the physical Pixel 4, using actual Android SQLite and SharedPreferencesAsync under unique test names:

1. Database initialization and secure-delete setting; report JPEG bytes, demo/local-only status and paused trip survive close/reopen; outbox FIFO/acknowledgement and deletion work.
2. All onboarding pages and permission explanation; persisted onboarding completion; Explore; endpoint swap/alternative route; pause, rebuild providers/reopen database, resume, finish and history; real-report unknown-GPS lock; demo moving lock, sample photo and keyboard entry; save/list/detail/delete; dark/light preference writes; permission/privacy/storage screens; zero telemetry rows.

Provider reconstruction/database reopening is not an OS process-death test. Real GPS, camera and permission dialogs are not simulated as native successes: the integration photo adapter avoids consuming interrupted user captures, and reports use explicit sample mode. Freshness, camera/cancellation/recovery, lifecycle release, latest-event save checks and permission failure/retry are separately exercised by widget tests. Layout tests cover 320px width, 200% text, both themes, and landscape onboarding/selectors.

**Device-data caveat:** although the test code isolates its own database/preferences, Flutter 3.47.1 defaults to uninstalling the package when integration tests end. Early runs used that default, and verbose logs confirmed an uninstall command. Pre-existing Android app data may therefore have been reset. Remaining instructions use `flutter test ... --no-uninstall` or `flutter drive ... --keep-app-running` to prevent that cleanup; the normal app is reinstalled after tests. No recovery of earlier app data is claimed.

## Remaining limitations

The normal `flutter test` Android runner has an observed DDS/service-discovery issue in this environment; disabling DDS exposes a separate SDK golden-comparator stream error. The alternative SDK driver passes the same tests. No global SDK patch was made. Android license status remains unknown. flutter_tts emits a future built-in-Kotlin compatibility warning, while current compilation succeeds.

Still unimplemented: authentication/registration and revocable registered consent, live maps/routing/hazards, approved GraphQL/media upload contracts, server submission/synchronization, background telemetry, DSP/ML/DBSCAN, remote notifications and server erasure. No SRS latency, battery, sample-rate or server-capacity target was measured. SQLite encryption, iOS backup controls, release signing and store/security review remain open. iOS, web release builds and CI were not run.

Manual device acceptance remains for real stationary GPS quality/permissions, real camera cancel/retake/process recovery, OS process death, physical motion, TTS audio/mute, TalkBack, and full accessibility review. See `ACCEPTANCE.md`; the original SRS ambiguities and provisional thresholds remain unchanged.
