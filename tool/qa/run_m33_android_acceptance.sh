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
readonly APP_PACKAGE="com.kong373.voice_social_app"
readonly SCREENSHOT_DIR="$EVIDENCE_ROOT/screenshots"
readonly VIDEO_DIR="$EVIDENCE_ROOT/videos"
readonly VIDEO_REMOTE="/data/local/tmp/m33-${QA_AVD_ID}.mp4"
readonly VIDEO_LOCAL="$VIDEO_DIR/${QA_AVD_ID}.mp4"
readonly APP_LOGCAT_FILE="$EVIDENCE_ROOT/logcat-app.txt"
readonly APP_LOGCAT_ERROR_FILE="$EVIDENCE_ROOT/logcat-app.stderr.txt"
readonly APP_UID_FILE="$EVIDENCE_ROOT/app-uid.txt"
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
app_logcat_pid=''
app_uid=''

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

stop_app_logcat() {
  if [[ -n "$app_logcat_pid" ]]; then
    kill "$app_logcat_pid" 2>/dev/null || true
    wait "$app_logcat_pid" 2>/dev/null || true
    app_logcat_pid=''
  fi
}

stop_app() {
  adb shell am force-stop "$APP_PACKAGE" >/dev/null 2>&1 || true
}

cleanup() {
  stop_recording
  stop_app_logcat
  stop_logcat
  stop_app
}

trap cleanup EXIT

wait_for_app_uid() {
  local package_line=''
  local package_path=''
  local uid=''
  local attempt

  for attempt in {1..600}; do
    package_line=''
    package_path=''
    uid=''
    if package_line="$(adb shell pm list packages -U "$APP_PACKAGE" 2>/dev/null | tr -d '\r')" &&
      package_path="$(adb shell pm path "$APP_PACKAGE" 2>/dev/null | tr -d '\r')" &&
      [[ -n "$package_path" ]]; then
      uid="$(printf '%s\n' "$package_line" | sed -n \
        "s/^package:${APP_PACKAGE}[[:space:]][[:space:]]*uid:\([0-9][0-9]*\).*$/\1/p" | head -n 1)"
    fi
    if [[ "$uid" =~ ^[0-9]+$ ]]; then
      printf '%s\n' "$uid"
      return 0
    fi
    sleep 1
  done
  return 1
}

start_app_logcat() {
  local resolved_uid=''

  if ! resolved_uid="$(wait_for_app_uid)"; then
    echo "Unable to resolve installed UID for $APP_PACKAGE" \
      >"$APP_LOGCAT_ERROR_FILE"
    return 1
  fi
  printf 'package=%s\nuid=%s\n' \
    "$APP_PACKAGE" "$resolved_uid" >"$APP_UID_FILE"
  exec adb logcat --uid="$resolved_uid" -v threadtime -T 10000 \
    >"$APP_LOGCAT_FILE" 2>"$APP_LOGCAT_ERROR_FILE"
}

wait_for_app_logcat_evidence() {
  local attempt

  for attempt in {1..25}; do
    if [[ -s "$APP_UID_FILE" && -s "$APP_LOGCAT_FILE" ]]; then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

stop_app
adb shell wm size "$QA_PHYSICAL"
adb shell wm density "$QA_DENSITY"
adb shell settings put system font_scale 1.0
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0
adb logcat -c
adb logcat -v threadtime >"$EVIDENCE_ROOT/logcat.txt" &
logcat_pid=$!
start_app_logcat &
app_logcat_pid=$!

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
app_logcat_ready=false
if wait_for_app_logcat_evidence; then
  app_logcat_ready=true
fi
stop_app_logcat
stop_logcat
for attempt in 1 2 3 4 5; do
  if adb shell test -s "$VIDEO_REMOTE"; then
    break
  fi
  sleep 1
done
adb pull "$VIDEO_REMOTE" "$VIDEO_LOCAL"
adb shell rm -f "$VIDEO_REMOTE"
test -s "$EVIDENCE_ROOT/logcat.txt"
test -s "$EVIDENCE_ROOT/flutter-drive.log"

test "$app_logcat_ready" = true
test -s "$APP_UID_FILE"
test -s "$APP_LOGCAT_FILE"
app_uid="$(sed -n 's/^uid=//p' "$APP_UID_FILE")"
[[ "$app_uid" =~ ^[0-9]+$ ]]

screenshots="$(
  find "$SCREENSHOT_DIR" -type f -name '*.png' | wc -l | tr -d ' '
)"
videos="$(
  find "$VIDEO_DIR" -type f -name '*.mp4' -size +0c | wc -l | tr -d ' '
)"
# Keep this broad count as an audit of the complete device log. It is not the
# verdict because Android/Google processes can legitimately contribute here.
system_hard_findings="$(
  cat "$EVIDENCE_ROOT/logcat.txt" "$EVIDENCE_ROOT/flutter-drive.log" |
    grep -Eci \
      'FATAL EXCEPTION|AndroidRuntime|ANR in|MissingPluginException|RenderFlex overflow|Unhandled Exception|EXCEPTION CAUGHT BY|Failed assertion|_dependents.isEmpty' ||
    true
)"
app_hard_errors="$(
  cat "$APP_LOGCAT_FILE" "$EVIDENCE_ROOT/flutter-drive.log" |
    grep -Eci \
      'FATAL EXCEPTION|Fatal signal [0-9]+|MissingPluginException|RenderFlex overflow|Unhandled Exception|EXCEPTION CAUGHT BY|Failed assertion|_dependents\.isEmpty' ||
    true
)"
global_app_anrs="$(
  grep -Eci \
    'ANR in com\.kong373\.voice_social_app([[:space:]:]|$)' \
    "$EVIDENCE_ROOT/logcat.txt" ||
  true
)"
hard_errors="$((app_hard_errors + global_app_anrs))"

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
test "$drive_status" -eq 0
test "$global_app_anrs" -eq 0
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
  echo "app_uid=$app_uid"
  echo "app_logcat=$(basename "$APP_LOGCAT_FILE")"
  echo "app_hard_errors=$app_hard_errors"
  echo "global_app_anrs=$global_app_anrs"
  echo "system_hard_findings=$system_hard_findings"
  echo "hard_errors=$hard_errors"
  echo "provider_calls_made=$provider_calls_made"
  echo "provider_dependency_graph=$provider_dependency_graph"
  echo "provider_evidence_scope=$provider_evidence_scope"
  echo "provider_guard_connection_attempts=$provider_guard_connection_attempts"
} | tee "$EVIDENCE_ROOT/summary.txt"
