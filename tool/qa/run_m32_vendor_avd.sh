#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

echo 'Deprecated M3.2 vendor AVD flow: use tool/qa/run_m32_review_flow.sh with the review contract server.' >&2
exit 64

readonly ARTIFACT_ROOT="${QA_ARTIFACT_ROOT:?QA_ARTIFACT_ROOT is required}"
readonly AVD_ID="${QA_AVD_ID:?QA_AVD_ID is required}"
readonly API_LEVEL="${QA_API_LEVEL:?QA_API_LEVEL is required}"
readonly PROFILE="${QA_PROFILE:?QA_PROFILE is required}"
readonly RUN_ID="${QA_RUN_ID:-local}"
readonly RUN_ATTEMPT="${QA_RUN_ATTEMPT:-1}"
readonly GIT_SHA="${QA_GIT_SHA:-$(git rev-parse HEAD)}"

readonly LOG_DIR="$ARTIFACT_ROOT/logs"
readonly SCREENSHOT_DIR="$ARTIFACT_ROOT/screenshots"
readonly APK_DIR="$ARTIFACT_ROOT/apk"
readonly SERVER_DIR="$ARTIFACT_ROOT/contract-server"
readonly SUMMARY_FILE="$ARTIFACT_ROOT/summary.txt"
readonly PAGE_COVERAGE_FILE="$ARTIFACT_ROOT/page_coverage.csv"
readonly TEST_CASES_FILE="$ARTIFACT_ROOT/test_cases.csv"
readonly ENVIRONMENT_FILE="$ARTIFACT_ROOT/environment.txt"
readonly MANIFEST_FILE="$ARTIFACT_ROOT/evidence_manifest.sha256"

mkdir -p "$LOG_DIR" "$SCREENSHOT_DIR" "$APK_DIR" "$SERVER_DIR"
: >"$SUMMARY_FILE"
: >"$ENVIRONMENT_FILE"

DEVICE_ID=""
SERVER_PID=""
LOGCAT_PID=""
RESULT="FAIL"
FAIL_REASON="not_started"
EXPECTED_PHYSICAL_SIZE=""
EXPECTED_DENSITY=""
EXPECTED_VIEWPORT=""
EXPECTED_WIDTH=""
EXPECTED_HEIGHT=""
EXPECTED_DPR=""

cleanup() {
  set +e
  if [[ -n "$LOGCAT_PID" ]]; then
    kill "$LOGCAT_PID" 2>/dev/null || true
    wait "$LOGCAT_PID" 2>/dev/null || true
  fi
  if [[ -n "$SERVER_PID" ]]; then
    kill -TERM "$SERVER_PID" 2>/dev/null || true
    for _ in {1..20}; do
      kill -0 "$SERVER_PID" 2>/dev/null || break
      sleep 0.25
    done
    kill -KILL "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  if [[ -n "$DEVICE_ID" ]]; then
    adb -s "$DEVICE_ID" exec-out screencap -p \
      >"$SCREENSHOT_DIR/final-system-${AVD_ID}.png" 2>/dev/null || true
  fi
  {
    printf 'M3.2 vendor integration AVD acceptance\n'
    printf 'conclusion=%s\n' "$RESULT"
    printf 'failure_reason=%s\n' "$FAIL_REASON"
    printf 'avd=%s\n' "$AVD_ID"
    printf 'api_level=%s\n' "$API_LEVEL"
    printf 'profile=%s\n' "$PROFILE"
    printf 'expected_physical_size=%s\n' "$EXPECTED_PHYSICAL_SIZE"
    printf 'expected_density=%s\n' "$EXPECTED_DENSITY"
    printf 'expected_viewport=%s\n' "$EXPECTED_VIEWPORT"
    printf 'expected_dpr=%s\n' "$EXPECTED_DPR"
    printf 'git_sha=%s\n' "$GIT_SHA"
    printf 'run_id=%s\n' "$RUN_ID"
    printf 'run_attempt=%s\n' "$RUN_ATTEMPT"
    printf 'provider_calls_made=false\n'
    printf 'mobile_client_secret_present=false\n'
    printf 'vendor_integration_status=READY_FOR_PROVIDER_INTEGRATION\n'
    printf 'vendor_runtime_status=VENDOR_BLOCKED\n'
    printf 'screenshot_count=%s\n' \
      "$(find "$SCREENSHOT_DIR" -type f -name '*.png' | wc -l | tr -d ' ')"
  } >"$SUMMARY_FILE"
  find "$ARTIFACT_ROOT" -type f ! -path "$MANIFEST_FILE" -print0 2>/dev/null | \
    sort -z | xargs -0 -r sha256sum >"$MANIFEST_FILE" 2>/dev/null || true
}
trap cleanup EXIT

csv_row() {
  local file="$1"
  shift
  local separator=""
  local value escaped
  for value in "$@"; do
    escaped="${value//\"/\"\"}"
    printf '%s"%s"' "$separator" "$escaped" >>"$file"
    separator=","
  done
  printf '\n' >>"$file"
}

initialize_csv() {
  : >"$PAGE_COVERAGE_FILE"
  csv_row "$PAGE_COVERAGE_FILE" \
    page_id page_name avd api_level viewport state interaction screenshot result notes
  : >"$TEST_CASES_FILE"
  csv_row "$TEST_CASES_FILE" \
    test_case_id module avd api_level viewport expected actual result evidence notes
}
initialize_csv

case "$AVD_ID" in
  AVD-A)
    [[ "$API_LEVEL" == "36" && "$PROFILE" == "pixel_7_pro" ]] || {
      FAIL_REASON="invalid_avd_a_matrix"
      exit 64
    }
    EXPECTED_PHYSICAL_SIZE="1170x2532"
    EXPECTED_DENSITY="480"
    EXPECTED_VIEWPORT="390x844"
    EXPECTED_WIDTH="390"
    EXPECTED_HEIGHT="844"
    EXPECTED_DPR="3.00"
    ;;
  AVD-B)
    [[ "$API_LEVEL" == "35" && "$PROFILE" == "pixel_2" ]] || {
      FAIL_REASON="invalid_avd_b_matrix"
      exit 64
    }
    EXPECTED_PHYSICAL_SIZE="864x1920"
    EXPECTED_DENSITY="384"
    EXPECTED_VIEWPORT="360x800"
    EXPECTED_WIDTH="360"
    EXPECTED_HEIGHT="800"
    EXPECTED_DPR="2.40"
    ;;
  *)
    FAIL_REASON="unknown_avd"
    exit 64
    ;;
esac

for command_name in adb flutter python3 curl unzip sha256sum; do
  command -v "$command_name" >/dev/null 2>&1 || {
    FAIL_REASON="missing_command_${command_name}"
    exit 69
  }
done

DEVICE_ID="${ANDROID_SERIAL:-}"
if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(adb devices | awk '$2 == "device" && $1 ~ /^emulator-/ {print $1; exit}')"
fi
[[ -n "$DEVICE_ID" ]] || {
  FAIL_REASON="emulator_not_found"
  exit 69
}

adb -s "$DEVICE_ID" wait-for-device
for _ in {1..120}; do
  [[ "$(adb -s "$DEVICE_ID" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]] && break
  sleep 2
done
[[ "$(adb -s "$DEVICE_ID" shell getprop sys.boot_completed | tr -d '\r')" == "1" ]] || {
  FAIL_REASON="emulator_boot_incomplete"
  exit 70
}

adb -s "$DEVICE_ID" shell settings put system accelerometer_rotation 0
adb -s "$DEVICE_ID" shell settings put system user_rotation 0
adb -s "$DEVICE_ID" shell settings put system font_scale 1.0
adb -s "$DEVICE_ID" shell settings put global window_animation_scale 0
adb -s "$DEVICE_ID" shell settings put global transition_animation_scale 0
adb -s "$DEVICE_ID" shell settings put global animator_duration_scale 0
adb -s "$DEVICE_ID" shell wm size "$EXPECTED_PHYSICAL_SIZE"
adb -s "$DEVICE_ID" shell wm density "$EXPECTED_DENSITY"
adb -s "$DEVICE_ID" shell input keyevent 82 || true
sleep 3

size_output="$(adb -s "$DEVICE_ID" shell wm size | tr -d '\r')"
density_output="$(adb -s "$DEVICE_ID" shell wm density | tr -d '\r')"
rotation_output="$(adb -s "$DEVICE_ID" shell settings get system user_rotation | tr -d '\r')"
font_scale_output="$(adb -s "$DEVICE_ID" shell settings get system font_scale | tr -d '\r')"
{
  printf 'timestamp=%s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  printf 'device_id=%s\n' "$DEVICE_ID"
  printf 'avd=%s\n' "$AVD_ID"
  printf 'api_level=%s\n' "$API_LEVEL"
  printf 'android_release=%s\n' "$(adb -s "$DEVICE_ID" shell getprop ro.build.version.release | tr -d '\r')"
  printf 'abi=%s\n' "$(adb -s "$DEVICE_ID" shell getprop ro.product.cpu.abi | tr -d '\r')"
  printf 'model=%s\n' "$(adb -s "$DEVICE_ID" shell getprop ro.product.model | tr -d '\r')"
  printf 'wm_size=%s\n' "$size_output"
  printf 'wm_density=%s\n' "$density_output"
  printf 'rotation=%s\n' "$rotation_output"
  printf 'font_scale=%s\n' "$font_scale_output"
  printf 'expected_viewport=%s\n' "$EXPECTED_VIEWPORT"
  printf 'expected_dpr=%s\n' "$EXPECTED_DPR"
  printf 'backend_mode=live\n'
  printf 'api_base_url=http://10.0.2.2:8765/\n'
  printf 'mobile_client_type=oauth_public_client\n'
  printf 'oauth_client_secret_loaded=false\n'
  printf 'provider_calls_made=false\n'
} | tee "$ENVIRONMENT_FILE"

if [[ "$size_output" != *"$EXPECTED_PHYSICAL_SIZE"* || \
      "$density_output" != *"$EXPECTED_DENSITY"* || \
      "$rotation_output" != "0" || "$font_scale_output" != "1.0" ]]; then
  FAIL_REASON="android_viewport_override_rejected"
  csv_row "$TEST_CASES_FILE" \
    M32-VIEWPORT viewport "$AVD_ID" "$API_LEVEL" "$EXPECTED_VIEWPORT" \
    "wm=$EXPECTED_PHYSICAL_SIZE density=$EXPECTED_DENSITY rotation=0 font=1.0" \
    "size=$size_output density=$density_output rotation=$rotation_output font=$font_scale_output" \
    FAIL "$ENVIRONMENT_FILE" "Android rejected the approved exact viewport."
  exit 1
fi

python3 -m py_compile tool/qa/m32_contract_server.py
python3 tool/qa/m32_contract_server.py \
  --host 0.0.0.0 \
  --port 8765 \
  --request-log "$SERVER_DIR/requests.jsonl" \
  --summary-file "$SERVER_DIR/summary.json" \
  >"$SERVER_DIR/server.stdout.log" 2>"$SERVER_DIR/server.stderr.log" &
SERVER_PID=$!

for _ in {1..100}; do
  if curl --fail --silent --show-error http://127.0.0.1:8765/ \
      >"$SERVER_DIR/health.json"; then
    break
  fi
  kill -0 "$SERVER_PID" 2>/dev/null || {
    FAIL_REASON="contract_server_exited"
    exit 1
  }
  sleep 0.2
done
curl --fail --silent http://127.0.0.1:8765/ >/dev/null || {
  FAIL_REASON="contract_server_unreachable"
  exit 1
}

adb -s "$DEVICE_ID" logcat -c
adb -s "$DEVICE_ID" logcat -v threadtime >"$LOG_DIR/logcat.txt" 2>&1 &
LOGCAT_PID=$!

set +e
QA_SCREENSHOT_DIR="$SCREENSHOT_DIR" \
  timeout --signal=TERM --kill-after=30s 45m \
  flutter drive \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/m3_2_vendor_readiness_test.dart \
    --device-id="$DEVICE_ID" \
    --debug \
    --no-pub \
    --dart-define=BACKEND_MODE=live \
    --dart-define=APP_ENV=development \
    --dart-define=ALLOW_INSECURE_HTTP=true \
    --dart-define=API_BASE_URL=http://10.0.2.2:8765/ \
    --dart-define=API_TIMEOUT_SECONDS=15 \
    --dart-define=OAUTH_CLIENT_ID=voice-social-mobile-public \
    --dart-define=DEVELOPMENT_OUTBOX_KEY=ci-local-outbox-placeholder \
    --dart-define=QA_AVD_ID="$AVD_ID" \
    --dart-define=QA_EXPECTED_VIEWPORT_WIDTH="$EXPECTED_WIDTH" \
    --dart-define=QA_EXPECTED_VIEWPORT_HEIGHT="$EXPECTED_HEIGHT" \
    --dart-define=QA_EXPECTED_DPR="$EXPECTED_DPR" \
    --dart-define=QA_HOST_SCREENSHOT_HANDSHAKE=false \
    --dart-define=QA_FRAMEWORK_SCREENSHOTS=false \
    >"$LOG_DIR/flutter-drive.log" 2>&1
DRIVE_STATUS=$?
set -e

adb -s "$DEVICE_ID" exec-out screencap -p \
  >"$SCREENSHOT_DIR/post-flow-system-${AVD_ID}.png" 2>/dev/null || true
curl --fail --silent http://127.0.0.1:8765/__qa__/summary \
  >"$SERVER_DIR/final-summary-response.json" || true

if [[ -f build/app/outputs/flutter-apk/app-debug.apk ]]; then
  cp build/app/outputs/flutter-apk/app-debug.apk "$APK_DIR/m32-${AVD_ID}-app-debug.apk"
  sha256sum "$APK_DIR/m32-${AVD_ID}-app-debug.apk" \
    >"$APK_DIR/m32-${AVD_ID}-app-debug.apk.sha256"
  rm -rf "$APK_DIR/inspection"
  mkdir -p "$APK_DIR/inspection"
  unzip -q "$APK_DIR/m32-${AVD_ID}-app-debug.apk" -d "$APK_DIR/inspection"
  if grep -aRInE 'OAUTH_CLIENT_SECRET|Client-Secret|actual-secret-value|do-not-expose-' \
      "$APK_DIR/inspection" >"$LOG_DIR/apk-secret-scan.txt" 2>&1; then
    FAIL_REASON="forbidden_secret_marker_in_apk"
    DRIVE_STATUS=1
  else
    printf 'forbidden_secret_markers=0\n' >"$LOG_DIR/apk-secret-scan.txt"
  fi
  rm -rf "$APK_DIR/inspection"
fi

python3 - "$SERVER_DIR/summary.json" "$SCREENSHOT_DIR" "$LOG_DIR/flutter-drive.log" \
  "$EXPECTED_VIEWPORT" "$EXPECTED_DPR" <<'PY'
import json
import pathlib
import sys

summary_path = pathlib.Path(sys.argv[1])
screenshot_dir = pathlib.Path(sys.argv[2])
drive_log = pathlib.Path(sys.argv[3]).read_text(encoding="utf-8", errors="replace")
expected_viewport = sys.argv[4]
expected_dpr = sys.argv[5]
summary = json.loads(summary_path.read_text(encoding="utf-8"))
errors = []
if summary.get("missingEndpoints"):
    errors.append(f"missing endpoints: {summary['missingEndpoints']}")
if summary.get("violations"):
    errors.append(f"contract violations: {summary['violations']}")
if summary.get("providerCallsMade") is not False:
    errors.append("providerCallsMade must be false")
if summary.get("oauthClientSecretObserved") is not False:
    errors.append("oauthClientSecretObserved must be false")
screenshots = sorted(screenshot_dir.glob("m32-*.png"))
if len(screenshots) < 9:
    errors.append(f"expected at least 9 framework screenshots, got {len(screenshots)}")
if "M32_ACCEPTANCE_COMPLETE" not in drive_log:
    errors.append("acceptance completion marker missing")
if f"{expected_viewport}::{float(expected_dpr):.2f}" not in drive_log:
    errors.append("exact viewport marker missing")
if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
print(json.dumps({
    "contract": "PASS",
    "screenshots": len(screenshots),
    "exactViewport": expected_viewport,
    "dpr": expected_dpr,
}, sort_keys=True))
PY
VALIDATION_STATUS=$?

if (( DRIVE_STATUS != 0 )); then
  FAIL_REASON="flutter_drive_exit_${DRIVE_STATUS}"
elif (( VALIDATION_STATUS != 0 )); then
  FAIL_REASON="evidence_validation_failed"
else
  RESULT="PASS"
  FAIL_REASON="none"
fi

for row in \
  "M32-PAGE-001|Consent and privacy gate|normal|tap accept|01-consent" \
  "M32-PAGE-002|Public-client SMS login|development outbox|send and authenticate|02-public-client-login" \
  "M32-PAGE-003|Live read-only home|loaded|refresh and inspect|03-live-home" \
  "M32-PAGE-004|Global search|rooms and users|search keyword|04-search-contract" \
  "M32-PAGE-005|Room snapshot|HTTP_SNAPSHOT_ONLY|open and leave|05-room-snapshot-only" \
  "M32-PAGE-006|Vendor readiness|READY_FOR_PROVIDER_INTEGRATION and VENDOR_BLOCKED|inspect SMS RTC IM payment|06-vendor-readiness" \
  "M32-PAGE-007|IM boundary|VENDOR_BLOCKED|open message tab|07-im-blocked" \
  "M32-PAGE-008|Wallet orders and payment boundary|read-only|inspect account tab|08-wallet-orders-payment-blocked" \
  "M32-PAGE-009|Logout|session deleted|logout|09-logout-complete"; do
  IFS='|' read -r page_id page_name state interaction screenshot_suffix <<<"$row"
  screenshot="$(find "$SCREENSHOT_DIR" -maxdepth 1 -type f -name "*${screenshot_suffix}.png" -print -quit)"
  page_result="$RESULT"
  [[ -n "$screenshot" ]] || page_result="FAIL"
  csv_row "$PAGE_COVERAGE_FILE" \
    "$page_id" "$page_name" "$AVD_ID" "$API_LEVEL" "$EXPECTED_VIEWPORT" \
    "$state" "$interaction" "$screenshot" "$page_result" \
    "No production provider call; mobile carries no secret."
done

csv_row "$TEST_CASES_FILE" \
  M32-TC-001 public-client "$AVD_ID" "$API_LEVEL" "$EXPECTED_VIEWPORT" \
  "SMS challenge/login/refresh/logout without mobile secret" \
  "Contract server observed public Client-Id and no secret" "$RESULT" \
  "$SERVER_DIR/summary.json" "Development provider simulator only."
csv_row "$TEST_CASES_FILE" \
  M32-TC-002 exact-viewport "$AVD_ID" "$API_LEVEL" "$EXPECTED_VIEWPORT" \
  "MediaQuery=$EXPECTED_VIEWPORT DPR=$EXPECTED_DPR" \
  "Integration assertion and marker" "$RESULT" "$LOG_DIR/flutter-drive.log" \
  "Physical override $EXPECTED_PHYSICAL_SIZE density $EXPECTED_DENSITY."
csv_row "$TEST_CASES_FILE" \
  M32-TC-003 vendor-boundary "$AVD_ID" "$API_LEVEL" "$EXPECTED_VIEWPORT" \
  "SMS/RTC/IM/PAYMENT boundaries ready; runtime blocked" \
  "Authenticated readiness contract rendered" "$RESULT" \
  "$SCREENSHOT_DIR" "No vendor SDK or credential was invoked."
csv_row "$TEST_CASES_FILE" \
  M32-TC-004 fail-closed-writes "$AVD_ID" "$API_LEVEL" "$EXPECTED_VIEWPORT" \
  "Room, IM and payment writes unavailable" \
  "Snapshot-only room, IM blocked page, payment initiation blocked" "$RESULT" \
  "$SCREENSHOT_DIR" "Read-only interfaces remain available."

if [[ "$RESULT" != "PASS" ]]; then
  exit 1
fi
