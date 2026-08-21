#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

: "${EVIDENCE_ROOT:?EVIDENCE_ROOT is required}"
: "${QA_AVD_ID:?QA_AVD_ID is required}"
: "${QA_API_LEVEL:?QA_API_LEVEL is required}"
: "${QA_VIEWPORT:?QA_VIEWPORT is required}"
: "${QA_WIDTH:?QA_WIDTH is required}"
: "${QA_HEIGHT:?QA_HEIGHT is required}"
: "${QA_PHYSICAL:?QA_PHYSICAL is required}"
: "${QA_DENSITY:?QA_DENSITY is required}"
: "${QA_DPR:?QA_DPR is required}"
: "${GITHUB_SHA:?GITHUB_SHA is required}"
: "${GITHUB_RUN_ID:?GITHUB_RUN_ID is required}"
: "${GITHUB_RUN_ATTEMPT:?GITHUB_RUN_ATTEMPT is required}"

readonly PROJECT_ROOT="$(pwd -P)"
readonly APP_ROOT="$PROJECT_ROOT/ci_app"
readonly SCREENSHOT_DIR="$EVIDENCE_ROOT/screenshots"
readonly VIDEO_DIR="$EVIDENCE_ROOT/videos"
readonly VIDEO_REMOTE="/data/local/tmp/m33-${QA_AVD_ID}.mp4"
readonly VIDEO_LOCAL="$VIDEO_DIR/${QA_AVD_ID}.mp4"
readonly PROGRESS_FILE="$EVIDENCE_ROOT/runner-progress.txt"

test -d "$APP_ROOT"
test -f "$APP_ROOT/pubspec.yaml"
mkdir -p "$SCREENSHOT_DIR" "$VIDEO_DIR"
{
  echo "state=STARTED"
  echo "run_id=$GITHUB_RUN_ID"
  echo "run_attempt=$GITHUB_RUN_ATTEMPT"
  echo "git_sha=$GITHUB_SHA"
  echo "avd=$QA_AVD_ID"
  echo "api=$QA_API_LEVEL"
  echo "viewport=$QA_VIEWPORT"
} >"$PROGRESS_FILE"

logcat_pid=''
screenrecord_pid=''

stop_recording() {
  if [[ -n "$screenrecord_pid" ]]; then
    adb shell pkill -INT screenrecord 2>/dev/null || true
    wait "$screenrecord_pid" 2>/dev/null || true
    screenrecord_pid=''
  fi
}

stop_logcat() {
  if [[ -n "$logcat_pid" ]]; then
    kill "$logcat_pid" 2>/dev/null || true
    wait "$logcat_pid" 2>/dev/null || true
    logcat_pid=''
  fi
}

cleanup() {
  stop_recording
  stop_logcat
}

trap cleanup EXIT

adb shell wm size "$QA_PHYSICAL"
adb shell wm density "$QA_DENSITY"
adb shell settings put system font_scale 1.0
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0
adb logcat -c
adb logcat -v threadtime >"$EVIDENCE_ROOT/logcat.txt" &
logcat_pid=$!

adb shell rm -f "$VIDEO_REMOTE"
adb shell screenrecord \
  --size "${QA_WIDTH}x${QA_HEIGHT}" \
  --bit-rate 4000000 \
  --time-limit 180 \
  "$VIDEO_REMOTE" \
  >"$EVIDENCE_ROOT/screenrecord.log" 2>&1 &
screenrecord_pid=$!

set +e
cd "$APP_ROOT"
QA_SCREENSHOT_DIR="$SCREENSHOT_DIR" \
  flutter drive \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/m3_3_video_runtime_ui_test.dart \
    -d emulator-5554 \
    --dart-define=BACKEND_MODE=mock \
    --dart-define=ENABLE_VIDEO_RUNTIME_DEMO=true \
    --dart-define="QA_AVD_ID=$QA_AVD_ID" \
    --dart-define="QA_EXPECTED_VIEWPORT_WIDTH=$QA_WIDTH" \
    --dart-define="QA_EXPECTED_VIEWPORT_HEIGHT=$QA_HEIGHT" \
    --dart-define="QA_EXPECTED_DPR=$QA_DPR" \
    2>&1 | tee "$EVIDENCE_ROOT/flutter-drive.log"
drive_status="${PIPESTATUS[0]}"
set -e

stop_recording
stop_logcat
for attempt in 1 2 3 4 5; do
  if adb shell test -s "$VIDEO_REMOTE"; then
    break
  fi
  sleep 1
done
adb pull "$VIDEO_REMOTE" "$VIDEO_LOCAL"
adb shell rm -f "$VIDEO_REMOTE"
test "$drive_status" -eq 0
test -s "$EVIDENCE_ROOT/logcat.txt"
test -s "$EVIDENCE_ROOT/flutter-drive.log"

screenshots="$(
  find "$SCREENSHOT_DIR" -type f -name '*.png' | wc -l | tr -d ' '
)"
videos="$(
  find "$VIDEO_DIR" -type f -name '*.mp4' -size +0c | wc -l | tr -d ' '
)"
hard_errors="$(
  cat "$EVIDENCE_ROOT/logcat.txt" "$EVIDENCE_ROOT/flutter-drive.log" |
    grep -Eci \
      'FATAL EXCEPTION|AndroidRuntime|ANR in|MissingPluginException|RenderFlex overflow|Unhandled Exception|EXCEPTION CAUGHT BY|Failed assertion|_dependents.isEmpty' ||
    true
)"

provider_marker_count="$(
  grep -Ec 'M33_PROVIDER_CALLS_MADE=(true|false)' \
    "$EVIDENCE_ROOT/flutter-drive.log" || true
)"
test "$provider_marker_count" -eq 1
provider_calls_made="$(
  grep -Eo 'M33_PROVIDER_CALLS_MADE=(true|false)' \
    "$EVIDENCE_ROOT/flutter-drive.log"
)"
provider_calls_made="${provider_calls_made#*=}"
test "$provider_calls_made" = false

provider_graph_marker_count="$(
  grep -Ec 'M33_PROVIDER_GRAPH_PROVEN=(true|false)' \
    "$EVIDENCE_ROOT/flutter-drive.log" || true
)"
test "$provider_graph_marker_count" -eq 1
provider_dependency_graph="$(
  grep -Eo 'M33_PROVIDER_GRAPH_PROVEN=(true|false)' \
    "$EVIDENCE_ROOT/flutter-drive.log"
)"
provider_dependency_graph="${provider_dependency_graph#*=}"
test "$provider_dependency_graph" = true

provider_scope_marker_count="$(
  grep -Ec 'M33_PROVIDER_EVIDENCE_SCOPE=[A-Za-z0-9_-]+' \
    "$EVIDENCE_ROOT/flutter-drive.log" || true
)"
test "$provider_scope_marker_count" -eq 1
provider_evidence_scope="$(
  grep -Eo 'M33_PROVIDER_EVIDENCE_SCOPE=[A-Za-z0-9_-]+' \
    "$EVIDENCE_ROOT/flutter-drive.log"
)"
provider_evidence_scope="${provider_evidence_scope#*=}"
test "$provider_evidence_scope" = \
  m33_video_runtime_mock_graph_and_http_outbound_guard

provider_guard_marker_count="$(
  grep -Ec 'M33_PROVIDER_GUARD_CONNECTION_ATTEMPTS=[0-9]+' \
    "$EVIDENCE_ROOT/flutter-drive.log" || true
)"
test "$provider_guard_marker_count" -eq 1
provider_guard_connection_attempts="$(
  grep -Eo 'M33_PROVIDER_GUARD_CONNECTION_ATTEMPTS=[0-9]+' \
    "$EVIDENCE_ROOT/flutter-drive.log"
)"
provider_guard_connection_attempts="${provider_guard_connection_attempts#*=}"
test "$provider_guard_connection_attempts" -eq 0

test "$screenshots" -ge 8
test "$videos" -ge 1
test "$hard_errors" -eq 0

{
  echo "conclusion=PASS"
  echo "run_id=$GITHUB_RUN_ID"
  echo "run_attempt=$GITHUB_RUN_ATTEMPT"
  echo "git_sha=$GITHUB_SHA"
  echo "avd=$QA_AVD_ID"
  echo "api=$QA_API_LEVEL"
  echo "viewport=$QA_VIEWPORT"
  echo "dpr=$QA_DPR"
  echo "screenshots=$screenshots"
  echo "videos=$videos"
  echo "hard_errors=$hard_errors"
  echo "provider_calls_made=$provider_calls_made"
  echo "provider_dependency_graph=$provider_dependency_graph"
  echo "provider_evidence_scope=$provider_evidence_scope"
  echo "provider_guard_connection_attempts=$provider_guard_connection_attempts"
} | tee "$EVIDENCE_ROOT/summary.txt"
