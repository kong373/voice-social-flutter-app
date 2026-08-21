#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

readonly AVD_ID="${QA_AVD_ID:?QA_AVD_ID is required}"
readonly PHYSICAL_RESOLUTION="${QA_PHYSICAL_RESOLUTION:?QA_PHYSICAL_RESOLUTION is required}"
readonly DENSITY="${QA_DENSITY:?QA_DENSITY is required}"
readonly EXPECTED_WIDTH="${QA_EXPECTED_VIEWPORT_WIDTH:?QA_EXPECTED_VIEWPORT_WIDTH is required}"
readonly EXPECTED_HEIGHT="${QA_EXPECTED_VIEWPORT_HEIGHT:?QA_EXPECTED_VIEWPORT_HEIGHT is required}"
readonly EXPECTED_DPR="${QA_EXPECTED_DPR:?QA_EXPECTED_DPR is required}"
readonly SCREENSHOT_DIR="${QA_SCREENSHOT_DIR:?QA_SCREENSHOT_DIR is required}"
readonly CONTRACT_PORT="${CONTRACT_PORT:?CONTRACT_PORT is required}"
readonly PUBLIC_CLIENT_ID="${PUBLIC_CLIENT_ID:?PUBLIC_CLIENT_ID is required}"
readonly EVIDENCE_ROOT="../evidence/${AVD_ID}"
readonly LOG_DIR="${EVIDENCE_ROOT}/logs"

mkdir -p "$SCREENSHOT_DIR" "$LOG_DIR"

DEVICE_ID="${ANDROID_SERIAL:-}"
if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(adb devices | awk 'NR > 1 && $2 == "device" {print $1; exit}')"
fi
[[ -n "$DEVICE_ID" ]] || {
  echo "No running Android emulator was found." >&2
  exit 1
}

LOGCAT_PID=""
cleanup() {
  set +e
  if [[ -n "$LOGCAT_PID" ]]; then
    kill "$LOGCAT_PID" 2>/dev/null || true
    wait "$LOGCAT_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

adb -s "$DEVICE_ID" shell settings put system accelerometer_rotation 0
adb -s "$DEVICE_ID" shell settings put system user_rotation 0
adb -s "$DEVICE_ID" shell settings put system font_scale 1.0
adb -s "$DEVICE_ID" shell wm size "$PHYSICAL_RESOLUTION"
adb -s "$DEVICE_ID" shell wm density "$DENSITY"
adb -s "$DEVICE_ID" logcat -c
adb -s "$DEVICE_ID" logcat -v threadtime >"$LOG_DIR/logcat.txt" 2>&1 &
LOGCAT_PID=$!

QA_SCREENSHOT_DIR="$SCREENSHOT_DIR" \
  timeout --signal=TERM --kill-after=30s 35m \
  flutter drive \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/m3_2_vendor_readiness_test.dart \
    --device-id="$DEVICE_ID" \
    --debug \
    --no-pub \
    --dart-define=BACKEND_MODE=live \
    --dart-define=APP_ENV=development \
    --dart-define=API_BASE_URL="http://10.0.2.2:${CONTRACT_PORT}" \
    --dart-define=ALLOW_INSECURE_HTTP=true \
    --dart-define=OAUTH_CLIENT_ID="$PUBLIC_CLIENT_ID" \
    --dart-define=CLIENT_TYPE=Android \
    --dart-define=CLIENT_INNER_VERSION=1 \
    --dart-define=LIVE_PROBE_PATH=/health \
    --dart-define=ENABLE_QA_CONSOLE=false \
    --dart-define=QA_AVD_ID="$AVD_ID" \
    --dart-define=QA_EXPECTED_VIEWPORT_WIDTH="$EXPECTED_WIDTH" \
    --dart-define=QA_EXPECTED_VIEWPORT_HEIGHT="$EXPECTED_HEIGHT" \
    --dart-define=QA_EXPECTED_DPR="$EXPECTED_DPR" \
  2>&1 | tee "$LOG_DIR/flutter-drive.log"

cleanup
trap - EXIT
