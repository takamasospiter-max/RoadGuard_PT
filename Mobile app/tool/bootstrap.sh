#!/usr/bin/env bash
# Generate native Flutter shells without ever overwriting lib/, test/ or pubspec.yaml.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
command -v flutter >/dev/null || { printf '\nFlutter is not installed or not on PATH. Install the current stable Flutter SDK, then rerun this script.\n' >&2; exit 1; }
command -v python3 >/dev/null || { printf 'Python 3 is required for platform configuration.\n' >&2; exit 1; }
flutter --version
if [[ ! -d android || ! -d ios || ! -d web ]]; then
  TEMP_ROOT="$(mktemp -d)"
  trap 'rm -rf "$TEMP_ROOT"' EXIT
  flutter create --platforms=android,ios,web --org tz.roadguard --project-name roadguard_ai --no-pub "$TEMP_ROOT/native_shell"
  for PLATFORM in android ios web; do
    if [[ ! -d "$PLATFORM" ]]; then cp -R "$TEMP_ROOT/native_shell/$PLATFORM" "$PLATFORM"; fi
  done
  if [[ ! -f .metadata ]]; then cp "$TEMP_ROOT/native_shell/.metadata" .metadata; fi
fi
python3 tool/configure_platforms.py
printf '\nNative shells configured. App code and tests were preserved.\nNext: flutter pub get && dart format lib test integration_test && flutter analyze && flutter test\n'
