# Connected-service manual acceptance — 21 September 2026

Use `bash roadguard_ai/tool/run_presentation.sh 99031FFAZ007TR` from the workspace
root with the Pixel unlocked and connected by USB. Backend and internet must be
available. Use your own account and real observations; never present test data
as a real road hazard.

- Register/sign in; verify Profile identity and that sensing is still off.
- Pan Explore; confirm empty/error states are clear. A genuinely confirmed report
  should show a red map marker/sheet after refresh; dismiss it (TalkBack retains
  the sheet). No hazards should be invented when the server is empty/offline.
- Choose map start/destination, request an OSRM route, view its geometry, start,
  pause/resume, finish and reopen history. Confirm OSRM routes and sample trips
  have distinct labels. Route time excludes live traffic.
- While safely stationary outdoors, capture a real hazard with fresh accurate
  zero-speed GPS and a photo. Resume/camera return must recheck eligibility.
  Save locally, read the anonymous-upload disclosure, upload and verify an actual
  server receipt. Receipt does not mean confirmed. A demo report cannot upload.
- On an active live trip, read and explicitly accept sensor consent only if you
  want to share account-linked GPS/motion data. Check GPS quality and server ACK
  batch count. Pause, leave the trip or background the app: collection stops and
  never silently restarts. Check offline queue preservation and explicit retry.
- Withdraw all sensor consent; confirm this account's pending local batches are
  cleared after server revocation. Previously received observations are not
  erased. Do not claim sampling-rate, battery or automatic hazard-detection
  acceptance from this walkthrough.

The detailed earlier acceptance requirements below remain open where they
cover unimplemented/background features or unmeasured SRS targets.

# Acceptance checklist

These checks cover local/device acceptance beyond the automated development pass. See `VALIDATION.md` for checks actually executed; items below are not implicitly marked passed.

## Development checks

Run `bash tool/bootstrap.sh`, `flutter pub get`, `dart format lib test integration_test`, `flutter analyze`, and `flutter test`. Retain the generated dependency lockfile. Run the integration test on a connected emulator/device with `--no-uninstall`; the test code uses a unique SQLite database and preference key, then deletes only its own test data, but Flutter's default runner cleanup otherwise removes the whole installed app. For the alternative `flutter drive` command in README, use `--keep-app-running`. Run debug Android and iOS builds separately; a browser build is not mobile build evidence.

## Manual mobile acceptance

- Fresh install: view all three onboarding pages; skip to permission explanation; deny location; continue as guest. Relaunch and verify onboarding stays completed.
- Explore: every visible navigation/card action opens the intended screen; sample-data labels stay visible; sample hazard details never claim live verification.
- Live maps: open Explore, the planner's View on map sheet and an active preview. Verify actual geographic tiles, pan/zoom and visible, clickable OpenStreetMap attribution. Disconnect/reconnect the network and verify loading/error/retry states. A failed download must not be presented as a loaded live map. Sample routes and hazards must not acquire invented geographic lines or markers.
- Map location: browsing alone must not request or collect GPS. Tap My location and test foreground precise/approximate access, denial, permanent denial and disabled location services. Map browsing remains available. Only fresh valid real positions show a location marker; stale/invalid/mocked evidence must remove or withhold it. Test Recenter and Stop location, cover or leave Explore, background and return. Updates stop and the marker clears; returning requires a new explicit My location action. This does not enable telemetry or background tracking.
- Planner: swap endpoints, select both candidate routes, reject identical endpoints, start a preview, pause/resume, background and restore it, finish and confirm it appears in local history. Relaunch with an active preview and resume it.
- Real report: deny GPS, permanently deny it, disable GPS service, provide negative/unknown speed, stale fix and poor accuracy. Fields, capture and save must stay locked. A raw speed of 0.000001 m/s must still block the form.
- Report while stationary: receive valid current GPS, capture a JPEG/PNG photo, cancel and retake it, return from camera, wait for fresh GPS, save. Confirm local-only status and photo persistence across app restart. No success should be shown when storage fails.
- Move while the report form is open: editing/capture/save immediately lock on positive-speed evidence. Returning from background or camera requires new GPS evidence. Verify no position collection continues after closing the report screen.
- Sample report: explicitly enable sample mode, test moving/stationary controls, add a sample photo and save. It remains tagged DEMO. Switching back to real mode removes the sample photo and never transfers mock GPS to the real gate.
- Android camera process death: force the documented picker-recovery scenario, reopen the report screen, recover one photo and recheck stationarity before saving.
- Privacy: change theme and audio preference and relaunch. Clear local data and verify reports/photos/history/outbox counts are empty. Existing settings remain. Confirm the map-data explanation identifies the third-party tile area/IP disclosure and distinguishes the 100 MB HTTP-aware map cache from SQLite data: Clear local data does not clear cached tiles. Follow [PERMISSIONS.md](PERMISSIONS.md) for device app-cache removal. The UI must not claim remote account erasure or guaranteed offline maps.
- Accessibility: test TalkBack/VoiceOver, 320 px width, landscape, 200% text, system reduced motion, contrast in both themes and keyboard focus. Capture actual Flutter screenshots once tested.

## Release blockers beyond the preview

Live-routing provider integration, licensing and routing correctness; production tile-service capacity/terms review beyond the current OpenStreetMap basemap; backend auth/schema/media contracts; registered consent enforcement/revocation; reliable native background sensing; measured sample rate, battery and alert latency; background process-kill recovery; SQLite encryption and iOS backup exclusion; server privacy and erasure; backend load/clustering/audit tests; signed builds; store permission disclosures and platform security review.

Do not use trip previews for road navigation or treat UI completion as system acceptance.
