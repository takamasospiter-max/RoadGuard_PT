# Presentation walkthrough

**For tomorrow without USB:** follow [onboarding, live-trip and Wi-Fi setup](PRESENTATION_WIFI.md).
The presentation build starts with light-mode onboarding and keeps existing data.
The instructions below retain the original USB option.

The Android app now supports real traveler registration and login against the
workspace's Django/PostGIS backend. Explore is a full map with floating controls
and a temporary red sheet for a server-confirmed hazard. Configured builds use
real OSRM routes, anonymous report uploads and optional foreground sensor sharing.

## Start on the Pixel 4

Keep the phone unlocked with USB debugging enabled and connected to this laptop.
Docker must be running. From the workspace root:

```bash
bash roadguard_ai/tool/run_presentation.sh 99031FFAZ007TR
```

The script starts the local backend, applies migrations, forwards the phone's
localhost port 8000 over USB, and launches Flutter with the API configured.
It preserves existing app data and accounts. If the USB cable is disconnected,
repeat the command to restore the connection. Accounts, reports, hazards and telemetry need the running laptop backend; the
OpenStreetMap basemap and public OSRM routing need internet. Public OSRM has no
uptime guarantee and may reject or time out; retry without claiming a sample route. This is a local
presentation connection, not a publicly deployed account service.

## Suggested demonstration

1. On a first launch, show the road welcome and its single Get Started button.
   Walk through the three onboarding pages; permissions remain optional.
   Choose Continue as guest without enabling location if indoors.
2. Open Profile → Sign in → Create account. Use your own email/name and a
   unique password with at least 12 characters. The server also rejects common,
   all-numeric and overly similar passwords. Return to Explore after registering.
3. Explore fills the screen with the real map. My location, Report hazard and
   Resume trip (when a trip exists) are icon buttons at the bottom right. Confirmed hazards are loaded from
   PostGIS every five seconds while Explore is visible. An empty database shows
   an honest empty state. A new confirmed hazard opens a red sheet; accessibility
   navigation keeps it open until dismissed. No fake alert is seeded.
4. Tap the top search bar. Search for a starting point and destination, submit
   each search and select a result. Include the city for more precise results.
   You can also choose points on the map. Scroll down and choose Find live routes. The two points are sent to
   public OSRM via Django. Select a route, start a trip, pause/resume and finish
   into history. The drawn line is returned road geometry; time has no traffic
   input. Start trip requests foreground GPS and follows your moving position; pan to browse or tap the target to recenter. Pause/leave stops display GPS. This is not turn-by-turn navigation or a safety ranking.
5. Open Profile to show the real account. Sign out and sign back in; wrong
   credentials show an inline error. View introduction replays onboarding.
6. Report only while safely stationary with fresh, accurate zero-speed GPS and
   a photo. Save locally, open the report and choose Upload anonymously. Read
   the disclosure before confirming. Only a server ACK changes its delivery
   label. A received NEW report is not verified; real operator moderation is
   required before it can appear among confirmed hazards. Demo reports remain
   local and cannot upload. Local deletion does not erase the server copy.
7. On a live trip, a signed-in traveler can choose Review consent and start.
   This shares account-linked foreground GPS, speed, accuracy and raw motion
   observations. Grant location permission only if you want to demonstrate it.
   Unknown or inaccurate GPS sends no observations. Pause, leave the trip or
   background the app to stop. Resume does not silently restart sensing.
8. Retry pending uploads explicitly after connectivity returns. Withdraw all
   sensor consent revokes this account’s sessions and clears its pending local
   batches on this device; previously received server data is not erased.

On the Pixel 4 tested on 2026-09-21, Android accessibility was enabled, so
the alert stays visible until closed. This device preference is preserved;
use the close button when demonstrating it. Automatic eight-second dismissal
is covered separately with accessibility navigation off.

Already onboarded? Start from Profile to reach Sign in/Create account. Restart presentation opens the road welcome, followed by light onboarding, without clearing data. There is no need to clear storage or reinstall the app.

## Account behavior and remaining work

Names/emails are persisted in Django/PostgreSQL. Passwords are hashed with the
configured Argon2 hasher. The phone stores an opaque session token through
flutter_secure_storage, separately from SQLite/preferences. Logout revokes the
server token before removing it from secure storage. Sessions expire after
seven days and fail after account deactivation, role change or password change.
An offline restore does not claim a valid session; Profile offers a retry.

Traveler tokens cannot access the administration portal or attach identity to
anonymous report uploads. Account creation records no sensor consent and starts
no motion collection. Email ownership verification, recovery emails, finalized
terms acceptance and account erasure are not implemented; no verification or
legal acceptance is claimed. Background telemetry, automatic hazard classification/corroboration, route
proximity warnings, remote notifications and full server erasure remain open.
Foreground telemetry requests 10 Hz per native sensor; its actual rate and battery
use have not been certified. See the [implemented contracts](../../backend/docs/LIVE_SERVICES.md).

HTTP is allowed only for localhost in the Android debug configuration and Dart
debug client, through USB or paired wireless ADB forwarding. Release builds require a configured
HTTPS backend. No production TLS bypass or cleartext LAN login is enabled.

See [VALIDATION.md](VALIDATION.md) for the actual commands and test/build results.
