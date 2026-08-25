#!/usr/bin/env bash
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is not available in PATH." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -d android || ! -d ios ]]; then
  TEMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TEMP_DIR"' EXIT
  flutter create \
    --platforms=android,ios \
    --org=com.kong373 \
    --project-name=voice_social_app \
    --no-pub \
    "$TEMP_DIR/generated"
  cp -R "$TEMP_DIR/generated/android" "$ROOT_DIR/android"
  cp -R "$TEMP_DIR/generated/ios" "$ROOT_DIR/ios"
fi

bash "$ROOT_DIR/tool/apply_native_permissions.sh" "$ROOT_DIR"

flutter pub get
flutter analyze
flutter test

echo "Local Flutter runners are ready. Run: flutter run"
