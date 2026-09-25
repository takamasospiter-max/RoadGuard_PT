<#
.SYNOPSIS
  Connect the RoadGuard app on an Android phone to the backend on this PC over Wi-Fi (Windows).

.DESCRIPTION
  The app talks to http://127.0.0.1:8000 (debug builds only allow plain HTTP
  to localhost). This script makes that address on the PHONE lead to the
  Django backend on this PC, without a USB cable:

    phone app -> phone 127.0.0.1:8000 -> wireless ADB tunnel -> PC 127.0.0.1:8000 (Django)

  Steps it performs:
    1. Switch ADB to Wi-Fi: with the phone plugged in by USB it runs
       `adb tcpip 5555` and connects to the phone's Wi-Fi address; or, with
       -Device, it connects to an address from Android's "Wireless debugging"
       screen (Settings > System > Developer options > Wireless debugging).
    2. Checks the backend answers at http://127.0.0.1:8000/api/v1/health/.
    3. Creates the tunnel: `adb reverse tcp:8000 tcp:8000`.
    4. Opens the app on the phone.

  Afterwards the USB cable can be unplugged. Re-run the script after the
  phone or PC restarts, Wi-Fi changes, or ADB restarts (the tunnel is lost).

  The phone and the PC must be on the same network (e.g. the PC's Windows
  Mobile Hotspot, 192.168.137.x). Because everything goes through ADB, no
  Windows Firewall rule and no change to the app are needed.

  IMPORTANT: the app must have been BUILT with the server address, or it shows
  "Account connection is not configured" whatever the tunnel does:
    flutter build apk --debug --dart-define=ROADGUARD_API_URL=http://127.0.0.1:8000
    adb -s <IP:port> install -r build\app\outputs\flutter-apk\app-debug.apk
  (or `flutter run -d <IP:port> --dart-define=ROADGUARD_API_URL=http://127.0.0.1:8000`).
  A debug build is needed: release builds only accept an https:// server.

.EXAMPLE
  # Phone plugged in by USB (first time, or after a restart):
  powershell -ExecutionPolicy Bypass -File tool\connect_wifi.ps1

.EXAMPLE
  # No cable: use the IP address & port shown in Wireless debugging:
  powershell -ExecutionPolicy Bypass -File tool\connect_wifi.ps1 -Device 192.168.137.146:40555
#>
param(
  # Phone address "IP:port" for an already-paired wireless-debugging phone.
  [string]$Device = '',
  # TCP port adbd listens on after `adb tcpip` (USB mode).
  [int]$AdbPort = 5555,
  # Backend port on this PC (and on the phone, through the tunnel).
  [int]$ApiPort = 8000,
  # Android package of the app, opened at the end.
  [string]$Package = 'com.example.roadguard_ai'
)
$ErrorActionPreference = 'Stop'

function Adb { & adb @args; if ($LASTEXITCODE -ne 0) { throw "adb $args failed" } }

# --- 1. Wireless ADB connection -------------------------------------------
if (-not $Device) {
  # Use the phone that is plugged in by USB (serials without ':' are USB).
  $usb = (& adb devices) -split "`n" | Where-Object { $_ -match '^(\S+)\s+device$' -and $_ -notmatch ':' } |
         ForEach-Object { ($_ -split '\s+')[0] } | Select-Object -First 1
  if (-not $usb) { throw 'No phone on USB. Plug it in, or pass -Device IP:port from Wireless debugging.' }

  # The phone's Wi-Fi address (interface wlan0).
  $ipLine = & adb -s $usb shell 'ip -f inet addr show wlan0' | Select-String 'inet (\d+\.\d+\.\d+\.\d+)'
  if (-not $ipLine) { throw 'The phone has no Wi-Fi address. Connect it to the same Wi-Fi/hotspot as this PC.' }
  $phoneIp = $ipLine.Matches[0].Groups[1].Value

  Write-Host "Switching ADB to Wi-Fi on the phone (${phoneIp}:${AdbPort})..."
  Adb -s $usb tcpip $AdbPort | Out-Null
  Start-Sleep -Seconds 3           # adbd restarts in network mode
  $Device = "$($phoneIp):$AdbPort"
}
Write-Host "Connecting to $Device over Wi-Fi..."
$result = & adb connect $Device
if ($result -notmatch 'connected') { throw "Could not connect to ${Device}: $result" }

# --- 2. Backend health ------------------------------------------------------
try {
  $health = Invoke-RestMethod -Uri "http://127.0.0.1:$ApiPort/api/v1/health/" -TimeoutSec 10
  Write-Host "Backend OK: $($health.database) + PostGIS $($health.postgis)"
} catch {
  throw "The backend isn't answering on port $ApiPort. Start it first: cd 'D:\ROADGUARD\Web portal\new-backend'; .venv\Scripts\python manage.py runserver $ApiPort"
}

# --- 3. Tunnel: phone 127.0.0.1:ApiPort -> this PC 127.0.0.1:ApiPort ----------
Adb -s $Device reverse "tcp:$ApiPort" "tcp:$ApiPort" | Out-Null
Write-Host "Tunnel active:"; Adb -s $Device reverse --list

# --- 4. Open the app ----------------------------------------------------------
Adb -s $Device shell monkey -p $Package -c android.intent.category.LAUNCHER 1 | Out-Null
Write-Host "Done. The app on $Device now reaches the backend at http://127.0.0.1:$ApiPort. You can unplug the USB cable."
