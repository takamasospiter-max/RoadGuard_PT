#!/usr/bin/env bash
set -euo pipefail
ROADGUARD_APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROADGUARD_DEVICE="${1:-99031FFAZ007TR}"
ROADGUARD_FLUTTER_FLAGS=()
if [[ "${2:-}" == '--presentation' ]]; then
  ROADGUARD_FLUTTER_FLAGS+=(--dart-define=ROADGUARD_PRESENTATION=true)
elif [[ -n "${2:-}" ]]; then
  echo 'Usage: run_presentation.sh DEVICE_ID [--presentation]' >&2
  exit 1
fi
ROADGUARD_ADB="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/home/egovirdc/Android/Sdk}}/platform-tools/adb"
cd "$ROADGUARD_APP_DIR/../backend"
if [[ ! -f .env ]]; then
  echo 'Backend .env is missing. Follow backend/README.md to initialize local secrets.' >&2
  exit 1
fi
docker compose up -d db
docker compose run --rm web python manage.py migrate --noinput
docker compose up -d web
"$ROADGUARD_ADB" -s "$ROADGUARD_DEVICE" reverse tcp:8000 tcp:8000
cd "$ROADGUARD_APP_DIR"
exec flutter run -d "$ROADGUARD_DEVICE" --dart-define=ROADGUARD_API_URL=http://127.0.0.1:8000 "${ROADGUARD_FLUTTER_FLAGS[@]}"
