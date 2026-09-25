# Presentation: onboarding, live trip and Wi-Fi

## Ready the app

The presentation APK is built with `ROADGUARD_PRESENTATION=true`. Each cold
launch opens the road photograph with RoadGuard AI branding and only **Get Started**.
Sign in/Create account remain available from Profile. **Get Started**
opens the first onboarding page in light mode. Completing onboarding
still works normally for that session. To restart without closing the app, use
**Profile → Restart presentation**. This changes only onboarding completion and
theme. Accounts, reports, existing trips, history and consent records are kept.
It does not log you out. Sign out separately if you want to demonstrate login.
If an earlier trip is active, finish it into history before starting a new one.

To install this build while the Pixel is connected (USB or wireless device ID):

```bash
cd /home/egovirdc/Downloads/RoadGuard_AI_Flutter/roadguard_ai
bash tool/run_presentation.sh 99031FFAZ007TR --presentation
```

Use `d` in the Flutter terminal to detach while leaving the app running. To
return to normal persisted startup after the presentation, run the same command
without `--presentation`. **Restart presentation** also returns to the branded
road welcome screen before the light introduction.

## Pair Wi-Fi once — no USB required

The Pixel 4 runs Android 13 and supports Android's wireless debugging. Keep the
computer and phone on the **same Wi-Fi** with device-to-device communication.
Both need internet for map tiles, place search and public OSRM routes.

1. Phone: Settings → System → Developer options → Wireless debugging. Enable it
   for your network. Choose **Pair device with pairing code** and keep it open.
2. In a computer terminal, set the tool path, then pair using the **pairing**
   address and port shown in that dialog. Replace the example values below:

   ```bash
   export ROADGUARD_ADB=/home/egovirdc/Android/Sdk/platform-tools/adb
   "$ROADGUARD_ADB" pair 192.168.1.50:37123
   ```

   Enter the six-digit code when prompted. The example is not your device's
   address. Android Studio's “Pair Devices Using Wi-Fi” is an alternative.
3. Return to the phone's main **Wireless debugging** screen. Read **IP address &
   Port** there. This connection port is different from the temporary pairing
   port. Run, with those current values:

   ```bash
   bash /home/egovirdc/Downloads/RoadGuard_AI_Flutter/roadguard_ai/tool/connect_wifi.sh 192.168.1.50:40555
   ```

   The helper connects ADB over Wi-Fi, starts the existing backend, checks its
   health, forwards phone localhost port 8000 to the computer and opens the
   installed app. Docker must be running. Backend secrets/migrations must have
   already been initialized, as they are in this workspace.
4. Unplug USB. Check Explore's hazard refresh and open Profile to confirm the
   backend can still be reached. Pairing/connecting alone is not proof of a
   successful backend request. Reopen the app or use Restart presentation when
   ready to begin.

## When the IP address changes

**Do not edit Dart files or rebuild the APK.** Read the new phone connection
IP:port from Wireless debugging and rerun `connect_wifi.sh` with that value.
The app keeps `http://127.0.0.1:8000`; the wireless ADB tunnel provides the
connection. The computer's changing LAN address does not go into app settings.
Recreate the tunnel after a reconnect, Wi-Fi change, phone/computer restart or
ADB server restart. Pair again only if Android no longer trusts the computer.

Useful checks (replace the sample connection address):

```bash
"$ROADGUARD_ADB" devices -l
"$ROADGUARD_ADB" -s 192.168.1.50:40555 reverse --list
curl -fsS --max-time 10 http://127.0.0.1:8000/health/
```

Keep the computer awake and Docker/ADB running during the demonstration. Some
venue/guest networks block communication between clients; use a private router
or a shared hotspot that permits it. If Android shows a different port after
re-enabling wireless debugging, use the new port. No database port or cleartext
login endpoint needs to be exposed to the venue network. This is a development
presentation connection; a public standalone app needs a hosted HTTPS backend.

Official pairing instructions:
[Android Developers — connect using Wi-Fi](https://developer.android.com/studio/run/device#wireless).

## Demonstrate a moving trip

1. Complete the introduction and permissions page. Open the search bar and
   select a starting place and destination; map selections use readable labels.
2. Choose **Find live routes → Start trip**. Allow foreground precise location
   when Android asks. The target icon reconnects/recenters; dragging the map lets
   you look elsewhere while the position marker continues updating.
3. Walk safely outdoors with the trip open. Fresh device GPS moves the blue
   position marker and camera. Unknown/stale/mocked fixes never become a fake
   moving dot. Indoor positioning can be unavailable or imprecise; the UI says
   so. The route line is OSRM geometry, not a recording of your traveled path.
4. Pause stops location. Resume explicitly reconnects. Leaving/backgrounding
   clears the position; after returning, tap the target to reconnect. Finishing
   saves the route to local history. No turn-by-turn instructions, rerouting,
   live traffic or arrival detection is implemented.
5. Sensor sharing remains a separate signed-in, explicitly consented action.
   Viewing your trip position alone does not upload GPS or motion batches.

## Show the web portal on the computer

Run its existing Vite script, then present that browser window:

```bash
cd '/home/egovirdc/Downloads/new web admin portal'
npm run dev -- --host 127.0.0.1 --port 5173 --strictPort
```

Open `http://127.0.0.1:5173`. If that port is already serving this portal, use
its existing terminal/server. The laptop browser needs no Wi-Fi IP configuration.
The portal now connects to Django through Vite's local proxy. Sign in using a
real portal administrator account and authenticator code; traveler accounts
cannot enter the portal. Create your administrator once:

```bash
cd /home/egovirdc/Downloads/RoadGuard_AI_Flutter/backend
docker compose run --rm web python manage.py provision_portal_user \
  --email 'YOUR_EMAIL' --name 'YOUR_NAME' --role admin
```

It prompts for a password, shows a private authenticator enrollment URI, and
verifies your code. Keep the URI/secret private and use the next code to sign in.
See [portal setup and review walkthrough](../../portal/README.md).

## Demonstrate a real camera report

1. Stop safely outdoors. Open Report hazard, leave demo mode off, and request
   precise foreground location. Wait for a fresh stationary fix.
2. Take a photo using the device camera. After returning, wait for a new GPS
   fix; movement or missing/stale/poor location keeps submission blocked.
3. Add a description, tap **Submit report**, and confirm sending its photo and
   GPS location. Acknowledgement means received and awaiting review, not verified.
   Failed uploads remain on the device with a retry action.
4. The portal's Reports page refreshes every five seconds. Open Review to see
   the photo, map/accuracy circle, description and times. Add a decision note
   and choose **Confirm report** or **Needs verification**. Only confirmed
   reports appear on the traveler's public hazard map after refreshing it.

GPS is approximate; the portal shows its reported accuracy. The location is
rechecked when saving after camera return. Do not switch to demo mode to
demonstrate uploading: simulated reports are intentionally local-only.
