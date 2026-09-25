#!/usr/bin/env bash
# Reconnect the installed presentation APK without rebuilding or changing its URL.
set -euo pipefail
ROADGUARD_APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROADGUARD_ADB="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/home/egovirdc/Android/Sdk}}/platform-tools/adb"
ROADGUARD_WIFI_DEVICE="${1:-}"
if [[ ! "$ROADGUARD_WIFI_DEVICE" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$ ]]; then
  echo 'Usage: bash tool/connect_wifi.sh PHONE_WIFI_IP:CONNECTION_PORT' >&2
  echo 'Use IP address & Port on Wireless debugging, not the temporary pairing port.' >&2
  exit 1
fi
"$ROADGUARD_ADB" connect "$ROADGUARD_WIFI_DEVICE"
if [[ "$("$ROADGUARD_ADB" -s "$ROADGUARD_WIFI_DEVICE" get-state)" != 'device' ]]; then
  echo 'Pair the phone first, then retry with its current connection IP and port.' >&2
  exit 1
fi
cd "$ROADGUARD_APP_DIR/../backend"
docker compose up -d db web
curl -fsS --max-time 5 --retry 12 --retry-delay 1 --retry-connrefused http://127.0.0.1:8000/health/
"$ROADGUARD_ADB" -s "$ROADGUARD_WIFI_DEVICE" reverse tcp:8000 tcp:8000
"$ROADGUARD_ADB" -s "$ROADGUARD_WIFI_DEVICE" shell am start -n com.example.roadguard_ai/.MainActivity
echo 'Wi-Fi backend connection ready. In Profile, use Restart presentation for light-mode onboarding.'
