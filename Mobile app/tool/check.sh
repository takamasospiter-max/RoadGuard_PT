#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
command -v flutter >/dev/null || { echo 'Install Flutter and add it to PATH first.' >&2; exit 1; }
flutter pub get
dart format lib test integration_test
flutter analyze
flutter test --coverage
printf '\nSource analysis and Flutter tests completed. Physical-device checks are still required.\n'
