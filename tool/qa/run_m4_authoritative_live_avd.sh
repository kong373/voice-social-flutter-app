#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

# M4 runs the Flutter client against the real first-party development backend.
# It does not start a deterministic contract server or any formal vendor. The
# only local process is an ephemeral relay for operator values; those values
# never enter a dart-define.

readonly PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
required() {
  local name="$1"
  local value
  value="$(printenv "$name" || true)"
  [[ -n "$value" ]] || { printf '%s is required\n' "$name" >&2; exit 64; }
  printf '%s' "$value"
}

readonly ARTIFACT_ROOT="$(required QA_ARTIFACT_ROOT)"
readonly FLUTTER_SHA_EXPECTED="$(required QA_FLUTTER_SHA)"
readonly BACKEND_SHA_EXPECTED="$(required QA_BACKEND_SHA)"
readonly BACKEND_REPO="$(required QA_BACKEND_REPO)"
readonly LIVE_PHONE="$(required QA_LIVE_PHONE)"
readonly OAUTH_CLIENT_ID="$(required QA_OAUTH_CLIENT_ID)"
readonly DB_TOKEN="$(printenv QA_DB_EVIDENCE_TOKEN || true)"
readonly BACKEND_BASE_URL='http://10.0.2.2:18080/'
readonly RUN_ID="$(printenv QA_RUN_ID || printf m4-local)"
readonly AVD_A_SERIAL="$(printenv QA_AVD_A_SERIAL || true)"
readonly AVD_B_SERIAL="$(printenv QA_AVD_B_SERIAL || true)"
readonly AVD_A_NAME="$(printenv QA_AVD_A_NAME || printf pixel_7_pro)"
readonly AVD_B_NAME="$(printenv QA_AVD_B_NAME || printf pixel_2)"

readonly A_API='36'
readonly A_PROFILE='pixel_7_pro'
readonly A_PHYSICAL='1170x2532'
readonly A_DENSITY='480'
readonly A_WIDTH='390'
readonly A_HEIGHT='844'
readonly A_DPR='3.00'
readonly B_API='35'
readonly B_PROFILE='pixel_2'
readonly B_PHYSICAL='864x1920'
readonly B_DENSITY='384'
readonly B_WIDTH='360'
readonly B_HEIGHT='800'
readonly B_DPR='2.40'

mkdir -p "$ARTIFACT_ROOT"
readonly SUMMARY_FILE="$ARTIFACT_ROOT/summary.txt"
readonly MANIFEST_FILE="$ARTIFACT_ROOT/evidence-manifest.sha256"
readonly STARTED_SERIALS_FILE="$ARTIFACT_ROOT/.started-emulator-serials"
RELAY_PID=''
RELAY_PORT=''
LOGCAT_PID=''
OVERALL_RESULT='PASS'

fail() {
  OVERALL_RESULT='FAIL'
  printf 'M4 preflight failed: %s\n' "$1" >&2
  exit 64
}

cleanup() {
  set +e
  [[ -z "$LOGCAT_PID" ]] || { kill "$LOGCAT_PID" 2>/dev/null || true; wait "$LOGCAT_PID" 2>/dev/null || true; }
  [[ -z "$RELAY_PID" ]] || { kill "$RELAY_PID" 2>/dev/null || true; wait "$RELAY_PID" 2>/dev/null || true; }
  local started_serial
  if [[ -f "$STARTED_SERIALS_FILE" ]]; then
    while IFS= read -r started_serial; do
      [[ -n "$started_serial" ]] || continue
      adb -s "$started_serial" emu kill >/dev/null 2>&1 || true
    done <"$STARTED_SERIALS_FILE"
    rm -f "$STARTED_SERIALS_FILE"
  fi
  {
    printf 'M4 authoritative live AVD acceptance\n'
    printf 'conclusion=%s\n' "$OVERALL_RESULT"
    printf 'flutter_sha=%s\n' "$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || printf unknown)"
    printf 'backend_sha=%s\n' "$(git -C "$BACKEND_REPO" rev-parse HEAD 2>/dev/null || printf unknown)"
    printf 'backend_mode=live\nbackend_base_url=%s\n' "$BACKEND_BASE_URL"
    printf 'provider_calls_made=false\n'
    printf 'formal_sms_vendor_started=false\nformal_rtc_vendor_started=false\n'
    printf 'formal_im_vendor_started=false\nformal_payment_vendor_started=false\n'
    printf 'formal_push_vendor_started=false\nformal_storage_vendor_started=false\n'
    printf 'development_outbox_key_to_flutter=false\nrun_id=%s\n' "$RUN_ID"
    for avd in AVD-A AVD-B; do
      if [[ -f "$ARTIFACT_ROOT/$avd/result.txt" ]]; then
        sed "s/^/$avd./" "$ARTIFACT_ROOT/$avd/result.txt"
      else
        printf '%s.result=NOT_RUN\n' "$avd"
      fi
      if [[ -f "$ARTIFACT_ROOT/$avd/db-evidence-status.txt" ]]; then
        sed "s/^/$avd./" "$ARTIFACT_ROOT/$avd/db-evidence-status.txt"
      fi
    done
  } >"$SUMMARY_FILE"
  # Re-scan after writing the summary so the final metadata file is covered as
  # well. The manifest is generated from hashes only after this check.
  if declare -F secret_scan >/dev/null 2>&1 && ! secret_scan "$ARTIFACT_ROOT"; then
    OVERALL_RESULT='FAIL'
    local summary_tmp="$ARTIFACT_ROOT/.summary.tmp"
    awk -v result="$OVERALL_RESULT" '
      /^conclusion=/ { print "conclusion=" result; next }
      { print }
    ' "$SUMMARY_FILE" >"$summary_tmp" && mv "$summary_tmp" "$SUMMARY_FILE"
  fi
  if command -v shasum >/dev/null 2>&1; then
    find "$ARTIFACT_ROOT" -type f ! -path "$MANIFEST_FILE" -print0 |
      sort -z | xargs -0 -r shasum -a 256 >"$MANIFEST_FILE" 2>/dev/null || true
  elif command -v sha256sum >/dev/null 2>&1; then
    find "$ARTIFACT_ROOT" -type f ! -path "$MANIFEST_FILE" -print0 |
      sort -z | xargs -0 -r sha256sum >"$MANIFEST_FILE" 2>/dev/null || true
  fi
}
trap cleanup EXIT

for command_name in adb flutter git python3 curl find sort awk grep unzip; do
  command -v "$command_name" >/dev/null 2>&1 || fail "missing command: $command_name"
done
[[ -f "$PROJECT_ROOT/pubspec.yaml" ]] || fail 'not a Flutter checkout'
[[ -d "$BACKEND_REPO/.git" || -f "$BACKEND_REPO/.git" ]] || fail 'QA_BACKEND_REPO is not Git'
[[ "$LIVE_PHONE" =~ ^1[3-9][0-9]{9}$ ]] || fail 'QA_LIVE_PHONE is invalid'
[[ -n "$OAUTH_CLIENT_ID" ]] || fail 'QA_OAUTH_CLIENT_ID is empty'
[[ "$RUN_ID" =~ ^[A-Za-z0-9_.:-]{1,80}$ ]] || fail 'QA_RUN_ID contains unsafe characters'
[[ -z "$AVD_A_SERIAL" || "$AVD_A_SERIAL" =~ ^[A-Za-z0-9_.:-]{1,80}$ ]] || fail 'QA_AVD_A_SERIAL contains unsafe characters'
[[ -z "$AVD_B_SERIAL" || "$AVD_B_SERIAL" =~ ^[A-Za-z0-9_.:-]{1,80}$ ]] || fail 'QA_AVD_B_SERIAL contains unsafe characters'
[[ "$AVD_A_NAME" =~ ^[A-Za-z0-9_.-]{1,80}$ && "$AVD_B_NAME" =~ ^[A-Za-z0-9_.-]{1,80}$ ]] || fail 'AVD name contains unsafe characters'

readonly FLUTTER_SHA_ACTUAL="$(git -C "$PROJECT_ROOT" rev-parse --verify HEAD)"
readonly BACKEND_SHA_ACTUAL="$(git -C "$BACKEND_REPO" rev-parse --verify HEAD)"
[[ "$FLUTTER_SHA_EXPECTED" == "$FLUTTER_SHA_ACTUAL" ]] || fail 'QA_FLUTTER_SHA mismatch'
[[ "$BACKEND_SHA_EXPECTED" == "$BACKEND_SHA_ACTUAL" ]] || fail 'QA_BACKEND_SHA mismatch'

[[ -z "$(printenv DEVELOPMENT_OUTBOX_KEY || true)" ]] || fail 'DEVELOPMENT_OUTBOX_KEY is forbidden'
[[ -z "$(printenv QA_DEVELOPMENT_OUTBOX_KEY || true)" ]] || fail 'QA_DEVELOPMENT_OUTBOX_KEY is forbidden'
[[ -z "$(printenv QA_API_BASE_URL || true)" ]] || fail 'QA_API_BASE_URL override is forbidden'
[[ -z "$(printenv CONTRACT_SERVER_PORT || true)" &&
  -z "$(printenv QA_CONTRACT_SERVER_PORT || true)" ]] || fail 'contract-server variables are forbidden'
[[ "$BACKEND_BASE_URL" != *':8765'* && "$BACKEND_BASE_URL" != *'contract-server'* ]] || fail 'backend target is not authoritative'
[[ "$ARTIFACT_ROOT" != *':8765'* && "$ARTIFACT_ROOT" != *'contract-server'* && "$ARTIFACT_ROOT" != *'.env.local'* ]] || fail 'artifact path names a forbidden source'
[[ "$ARTIFACT_ROOT" != *"$LIVE_PHONE"* && "$ARTIFACT_ROOT" != *"$OAUTH_CLIENT_ID"* ]] || fail 'artifact path contains a runtime secret'
[[ -z "$DB_TOKEN" || "$ARTIFACT_ROOT" != *"$DB_TOKEN"* ]] || fail 'artifact path contains the DB token'

run_with_timeout() {
  local timeout_seconds="$1"
  local kill_after_seconds="$2"
  shift 2
  python3 - "$timeout_seconds" "$kill_after_seconds" "$@" <<'PY'
import os
import signal
import subprocess
import sys

timeout_seconds = int(sys.argv[1])
kill_after_seconds = int(sys.argv[2])
command = sys.argv[3:]
process = subprocess.Popen(command, start_new_session=True)
try:
    raise SystemExit(process.wait(timeout=timeout_seconds))
except subprocess.TimeoutExpired:
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=kill_after_seconds)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
    raise SystemExit(124)
PY
}

sanitize() {
  QA_M4_SECRET_PHONE="$LIVE_PHONE" \
    QA_M4_SECRET_CLIENT="$OAUTH_CLIENT_ID" \
    QA_M4_SECRET_DB_TOKEN="$DB_TOKEN" \
    python3 -u -c '
import os
import re
import sys
values = [os.environ.get("QA_M4_SECRET_PHONE", ""), os.environ.get("QA_M4_SECRET_CLIENT", ""), os.environ.get("QA_M4_SECRET_DB_TOKEN", "")]
for line in sys.stdin:
    for value in values:
        if value:
            line = line.replace(value, "[REDACTED]")
    line = re.sub(r"(?<!\d)1[3-9]\d{9}(?!\d)", "[REDACTED_PHONE]", line)
    line = re.sub(r"(?<!\d)\d{6}(?!\d)", "[REDACTED_OTP]", line)
    line = re.sub(r"(?i)(bearer\s+)[A-Za-z0-9._~+/=-]{12,}", r"\1[REDACTED_TOKEN]", line)
    line = re.sub(r"(?i)((?:access[_-]?token|refresh[_-]?token|client[_-]?secret|password|token)\s*[:=]\s*)[A-Za-z0-9._~+/=-]{8,}", r"\1[REDACTED_TOKEN]", line)
    line = re.sub(r"(?i)(\"(?:access_token|refresh_token|accessToken|refreshToken)\"\s*[:=]\s*\")[^\"]+", r"\1[REDACTED_TOKEN]", line)
    sys.stdout.write(line)
    sys.stdout.flush()
'
}

start_relay() {
  local relay_dir="$ARTIFACT_ROOT/config-relay"
  mkdir -p "$relay_dir"
  RELAY_PORT="$(python3 - <<'PY'
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)"
  python3 -u - "$RELAY_PORT" >"$relay_dir/relay.log" 2>&1 <<'PY' &
import http.server
import json
import os
import sys
port = int(sys.argv[1])
phone = os.environ["QA_LIVE_PHONE"]
client_id = os.environ["QA_OAUTH_CLIENT_ID"]
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/m4/config":
            self.send_response(404)
            self.end_headers()
            return
        body = json.dumps({"phone": phone, "oauthClientId": client_id}, separators=(",", ":")).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, _format, *_args):
        return
http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
PY
  RELAY_PID=$!
  for _ in {1..60}; do
    kill -0 "$RELAY_PID" 2>/dev/null || fail 'runtime config relay exited'
    if curl --fail --silent --show-error \
      "http://127.0.0.1:$RELAY_PORT/m4/config" >/dev/null; then
      return 0
    fi
    sleep 0.1
  done
  fail 'runtime config relay did not become ready'
}

device_for_api() {
  local serial sdk
  while read -r serial _state; do
    [[ "$serial" == emulator-* ]] || continue
    sdk="$(adb -s "$serial" shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r')"
    [[ "$sdk" == "$1" ]] && { printf '%s\n' "$serial"; return 0; }
  done < <(adb devices | awk 'NR > 1 && $2 == "device" {print $1, $2}')
  return 1
}

wait_boot() {
  local serial="$1"
  adb -s "$serial" wait-for-device >/dev/null
  local attempt
  for attempt in {1..180}; do
    [[ "$(adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == '1' ]] && return 0
    sleep 2
  done
  return 1
}

start_emulator() {
  local api="$1"
  local name="$2"
  local run_dir="$3"
  local emulator_bin
  emulator_bin="$(command -v emulator 2>/dev/null || true)"
  if [[ -z "$emulator_bin" ]]; then
    local sdk_root
    sdk_root="$(printenv ANDROID_SDK_ROOT || printenv ANDROID_HOME || true)"
    [[ -n "$sdk_root" && -x "$sdk_root/emulator/emulator" ]] || fail "no API $api emulator or emulator binary"
    emulator_bin="$sdk_root/emulator/emulator"
  fi
  "$emulator_bin" -avd "$name" -no-snapshot -no-boot-anim -gpu swiftshader_indirect \
    -no-window >"$run_dir/emulator.log" 2>&1 &
  local pid=$!
  local serial
  for _ in {1..180}; do
    serial="$(device_for_api "$api" || true)"
    if [[ -n "$serial" ]] && wait_boot "$serial"; then
      # This function is called through command substitution, so shell state
      # assigned here cannot reach cleanup. Persist only the non-sensitive
      # emulator serial in a short-lived file that cleanup removes.
      printf '%s\n' "$serial" >>"$STARTED_SERIALS_FILE"
      printf '%s\n' "$serial"
      return 0
    fi
    kill -0 "$pid" 2>/dev/null || fail "emulator $name exited before API $api booted"
    sleep 2
  done
  fail "timed out waiting for API $api emulator"
}

select_device() {
  local avd="$1"
  local api="$2"
  local override="$3"
  local name="$4"
  local run_dir="$5"
  local serial=''
  if [[ -n "$override" ]]; then
    serial="$override"
    [[ "$(adb -s "$serial" shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r')" == "$api" ]] || fail "$avd serial is not API $api"
    wait_boot "$serial" || fail "$avd failed to boot"
  else
    serial="$(device_for_api "$api" || true)"
    [[ -n "$serial" ]] || serial="$(start_emulator "$api" "$name" "$run_dir")"
  fi
  printf '%s\n' "$serial"
}

configure_viewport() {
  local serial="$1"
  local physical="$2"
  local density="$3"
  adb -s "$serial" shell settings put system accelerometer_rotation 0 >/dev/null
  adb -s "$serial" shell settings put system user_rotation 0 >/dev/null
  adb -s "$serial" shell settings put system font_scale 1.0 >/dev/null
  adb -s "$serial" shell settings put global window_animation_scale 0 >/dev/null
  adb -s "$serial" shell settings put global transition_animation_scale 0 >/dev/null
  adb -s "$serial" shell settings put global animator_duration_scale 0 >/dev/null
  adb -s "$serial" shell wm size "$physical" >/dev/null
  adb -s "$serial" shell wm density "$density" >/dev/null
  local size density_value rotation font
  size="$(adb -s "$serial" shell wm size | tr -d '\r')"
  density_value="$(adb -s "$serial" shell wm density | tr -d '\r')"
  rotation="$(adb -s "$serial" shell settings get system user_rotation | tr -d '\r')"
  font="$(adb -s "$serial" shell settings get system font_scale | tr -d '\r')"
  [[ "$size" == *"$physical"* && "$density_value" == *"$density"* &&
    "$rotation" == '0' && "$font" == '1.0' ]] || return 1
  printf 'wm_size=%s\nwm_density=%s\nrotation=%s\nfont_scale=%s\n' "$size" "$density_value" "$rotation" "$font"
}

write_environment() {
  local dir="$1"; shift
  local avd="$1"; shift
  local api="$1"; shift
  local profile="$1"; shift
  local width="$1"; shift
  local height="$1"; shift
  local dpr="$1"; shift
  local serial="$1"; shift
  local viewport="$1"
  {
    printf 'avd=%s\napi_level=%s\nprofile=%s\nserial=%s\n' "$avd" "$api" "$profile" "$serial"
    printf 'expected_viewport=%sx%s\nexpected_dpr=%s\n' "$width" "$height" "$dpr"
    printf 'backend_mode=live\nbackend_base_url=%s\n' "$BACKEND_BASE_URL"
    printf 'flutter_sha=%s\nbackend_sha=%s\n' "$FLUTTER_SHA_ACTUAL" "$BACKEND_SHA_ACTUAL"
    printf 'oauth_client_id_loaded_by_flutter=false\n'
    printf 'development_outbox_key_loaded_by_flutter=false\nprovider_calls_made=false\n'
    printf '%s\n' "$viewport"
  } >"$dir/environment.txt"
}

write_route_evidence() {
  local dir="$1"
  local log="$dir/logs/flutter-drive.log"
  {
    printf 'capability,method,route,status,state\n'
    awk -F '::' '/M4_ROUTE_STATUS::/ {
      gsub(/,/, "%2C", $2); gsub(/,/, "%2C", $3); gsub(/,/, "%2C", $4)
      printf "%s,%s,%s,%s,%s\n", $2, $3, $4, $5, $6
    }' "$log" | sort -u
  } >"$dir/http-route-coverage.csv"
  awk -F '::' '/M4_AUTHORITY_INVARIANT::/ {print $2}' "$log" | sort -u >"$dir/authority-invariants.txt"
  local writes
  writes="$(grep -Ec 'M4_ROUTE_STATUS::[^:]+::(POST|PUT|PATCH|DELETE)::' "$log" || true)"
  {
    printf 'source=client_observed_route_markers\nwrite_route_marker_count=%s\n' "$writes"
    printf 'database_write_counter_source=operator_redacted_db_evidence\n'
    printf 'database_write_counter_file=db-evidence.json\n'
  } >"$dir/db-write-counters.txt"
}

db_evidence() {
  local dir="$1"
  local url
  url="$(printenv QA_DB_EVIDENCE_URL || true)"
  if [[ -n "$url" || -n "$DB_TOKEN" ]]; then
    [[ -n "$url" && -n "$DB_TOKEN" ]] || { printf 'db_evidence_status=FAIL\n' >"$dir/db-evidence-error.txt"; return 1; }
    [[ "$url" != *':8765'* && "$url" != *'contract-server'* ]] || { printf 'db_evidence_status=FAIL\n' >"$dir/db-evidence-error.txt"; return 1; }
    set +e
    QA_M4_DB_TOKEN="$DB_TOKEN" QA_M4_DB_URL="$url" \
      python3 -u - 2>"$dir/db-evidence-curl.stderr" <<'PY' | sanitize >"$dir/db-evidence.json"
import os
import sys
import urllib.error
import urllib.request

request = urllib.request.Request(
    os.environ["QA_M4_DB_URL"],
    headers={
        "Authorization": "Bearer " + os.environ["QA_M4_DB_TOKEN"],
        "Accept": "application/json",
    },
)
try:
    with urllib.request.urlopen(request, timeout=20) as response:
        if response.status < 200 or response.status >= 300:
            raise RuntimeError("db evidence returned non-success status")
        sys.stdout.buffer.write(response.read())
except (OSError, urllib.error.URLError, RuntimeError) as error:
    print("db evidence request failed", file=sys.stderr)
    raise SystemExit(1) from error
PY
    local status=${PIPESTATUS[0]}
    set -e
    [[ "$status" -eq 0 && -s "$dir/db-evidence.json" ]] || { printf 'db_evidence_status=FAIL\n' >"$dir/db-evidence-error.txt"; return 1; }
    if ! python3 - "$dir/db-evidence.json" 2>"$dir/db-evidence-validation.stderr" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    payload = json.load(stream)
if not isinstance(payload, dict):
    raise SystemExit(1)
allowed = {"status", "writeCounters", "authorityInvariants", "providerCalls", "secrets"}
if set(payload) - allowed:
    raise SystemExit(1)
if payload.get("status") != "OK":
    raise SystemExit(1)
if (
    "writeCounters" not in payload
    or "authorityInvariants" not in payload
    or "providerCalls" not in payload
):
    raise SystemExit(1)
if not isinstance(payload["writeCounters"], dict) or not payload["writeCounters"]:
    raise SystemExit(1)
if not isinstance(payload["authorityInvariants"], dict) or not payload["authorityInvariants"]:
    raise SystemExit(1)
if payload["providerCalls"] not in (0, False, "0"):
    raise SystemExit(1)
if payload.get("secrets") is not False:
    raise SystemExit(1)
PY
    then
      printf 'db_evidence_status=FAIL\n' >"$dir/db-evidence-error.txt"
      return 1
    fi
    printf 'db_evidence_status=COLLECTED\n' >"$dir/db-evidence-status.txt"
  else
    printf '{"status":"NOT_CONFIGURED","source":"none","writeCounters":"unknown","authorityInvariants":"see authority-invariants.txt","providerCalls":"unknown"}\n' >"$dir/db-evidence.json"
    printf 'db_evidence_status=NOT_CONFIGURED\n' >"$dir/db-evidence-status.txt"
  fi
}

secret_scan() {
  local dir="$1"
  local output="$dir/secret-scan.txt"
  local bad=0 path base
  : >"$output"
  while IFS= read -r -d '' path; do
    base="$(basename "$path")"
    if [[ "$base" == '.env.local' || "$path" == *'.env.local'* ||
      "$path" == *'contract-server'* || "$path" == *':8765'* ]]; then
      printf 'forbidden_artifact_name=%s\n' "$base" >>"$output"; bad=1
    fi
    if grep -aFq "$LIVE_PHONE" "$path" 2>/dev/null ||
      grep -aFq "$OAUTH_CLIENT_ID" "$path" 2>/dev/null ||
      { [[ -n "$DB_TOKEN" ]] && grep -aFq "$DB_TOKEN" "$path" 2>/dev/null; }; then
      printf 'runtime_secret_value_found=true\n' >>"$output"; bad=1
    fi
    if grep -aEiq '1[3-9][0-9]{9}|Bearer[[:space:]]+[A-Za-z0-9._~+/=-]{12,}' "$path" 2>/dev/null; then
      printf 'credential_like_value_found=true\n' >>"$output"; bad=1
    fi
    if python3 - "$path" <<'PY'
import re
import sys

try:
    text = open(sys.argv[1], "rb").read().decode("utf-8", errors="ignore")
except OSError:
    raise SystemExit(0)
keys = (
    "access_token", "refresh_token", "accessToken", "refreshToken",
    "token", "password", "client_secret", "clientSecret", "oauthClientId",
    "mobile", "phone",
)
for key in keys:
    pattern = r'"' + re.escape(key) + r'"\s*:\s*"([^"]+)"'
    for match in re.finditer(pattern, text):
        value = match.group(1)
        if value and not value.startswith("[REDACTED"):
            raise SystemExit(1)
raise SystemExit(0)
PY
    then
      :
    else
      printf 'credential_field_value_found=true\n' >>"$output"; bad=1
    fi
  done < <(find "$dir" -type f -print0)
  [[ "$bad" -eq 0 ]] && { printf 'secret_scan=0\n' >>"$output"; return 0; }
  printf 'secret_scan=FAIL\n' >>"$output"
  return 1
}

apk_scan() {
  local dir="$1"
  local output="$dir/apk-secret-scan.txt"
  local bad=0 apk apk_count=0
  : >"$output"
  while IFS= read -r -d '' apk; do
    apk_count=$((apk_count + 1))
    unzip -p "$apk" 2>/dev/null | grep -aFq "$LIVE_PHONE" && { printf 'apk_phone_value_found=true\n' >>"$output"; bad=1; } || true
    unzip -p "$apk" 2>/dev/null | grep -aFq "$OAUTH_CLIENT_ID" && { printf 'apk_oauth_client_value_found=true\n' >>"$output"; bad=1; } || true
  done < <(find "$PROJECT_ROOT/build/app/outputs" -type f -name '*.apk' -print0 2>/dev/null || true)
  [[ "$apk_count" -gt 0 ]] || { printf 'apk_missing=true\n' >>"$output"; bad=1; }
  [[ "$bad" -eq 0 ]] && { printf 'apk_secret_scan=0\n' >>"$output"; return 0; }
  printf 'apk_secret_scan=FAIL\n' >>"$output"
  return 1
}

run_one() {
  local avd="$1"; shift
  local api="$1"; shift
  local profile="$1"; shift
  local physical="$1"; shift
  local density="$1"; shift
  local width="$1"; shift
  local height="$1"; shift
  local dpr="$1"; shift
  local serial_override="$1"; shift
  local avd_name="$1"
  local dir="$ARTIFACT_ROOT/$avd"
  mkdir -p "$dir/logs" "$dir/screenshots"
  local serial viewport
  serial="$(select_device "$avd" "$api" "$serial_override" "$avd_name" "$dir")"
  viewport="$(configure_viewport "$serial" "$physical" "$density" || true)"
  [[ -n "$viewport" ]] || { printf 'result=FAIL\nreason=viewport_override_rejected\n' >"$dir/result.txt"; OVERALL_RESULT='FAIL'; return 1; }
  write_environment "$dir" "$avd" "$api" "$profile" "$width" "$height" "$dpr" "$serial" "$viewport"

  adb -s "$serial" logcat -c >/dev/null 2>&1 || true
  set +e
  adb -s "$serial" logcat -v threadtime | sanitize >"$dir/logs/logcat-full.txt" 2>"$dir/logs/logcat-sanitizer.stderr" &
  LOGCAT_PID=$!
  set -e
  set +e
  run_with_timeout 1500 30 \
    env -u QA_LIVE_PHONE -u QA_OAUTH_CLIENT_ID \
      -u QA_DB_EVIDENCE_URL -u QA_DB_EVIDENCE_TOKEN \
      -u DEVELOPMENT_OUTBOX_KEY -u QA_DEVELOPMENT_OUTBOX_KEY \
      -u OAUTH_CLIENT_ID -u M3_OAUTH_CLIENT_ID -u M3_API_BASE_URL -u QA_API_BASE_URL \
      QA_SCREENSHOT_DIR="$dir/screenshots" \
      flutter drive --driver=test_driver/integration_test.dart \
      --target=integration_test/m4_first_party_live_integration_test.dart \
      --device-id="$serial" --debug --no-pub \
      --dart-define=BACKEND_MODE=live --dart-define=APP_ENV=development \
      --dart-define=ALLOW_INSECURE_HTTP=true --dart-define=API_BASE_URL="$BACKEND_BASE_URL" \
      --dart-define=API_TIMEOUT_SECONDS=15 \
      --dart-define=M4_RUNTIME_CONFIG_PORT="$RELAY_PORT" \
      --dart-define=M4_EXPECTED_FLUTTER_SHA="$FLUTTER_SHA_EXPECTED" \
      --dart-define=M4_EXPECTED_BACKEND_SHA="$BACKEND_SHA_EXPECTED" \
      --dart-define=QA_AVD_ID="$avd" \
      --dart-define=QA_EXPECTED_VIEWPORT_WIDTH="$width" \
      --dart-define=QA_EXPECTED_VIEWPORT_HEIGHT="$height" \
      --dart-define=QA_EXPECTED_DPR="$dpr" 2>&1 | sanitize >"$dir/logs/flutter-drive.log"
  local drive_status=${PIPESTATUS[0]}
  set -e
  kill "$LOGCAT_PID" 2>/dev/null || true
  wait "$LOGCAT_PID" 2>/dev/null || true
  LOGCAT_PID=''

  write_route_evidence "$dir"
  local db_status='FAIL'
  if db_evidence "$dir"; then
    db_status="$(sed -n 's/^db_evidence_status=//p' "$dir/db-evidence-status.txt" 2>/dev/null || printf FAIL)"
  fi
  local screenshot_count marker_count provider_count invariant_count hard_count crash_count
  screenshot_count="$(find "$dir/screenshots" -type f -name '*.png' -size +0c | wc -l | tr -d ' ')"
  marker_count="$(awk -F '::' '/M4_ROUTE_STATUS::/ {print $2 "::" $3 "::" $4 "::" $5 "::" $6}' "$dir/logs/flutter-drive.log" | sort -u | wc -l | tr -d ' ')"
  provider_marker_count="$(grep -Ec 'M4_PROVIDER_CALLS::' "$dir/logs/flutter-drive.log" || true)"
  provider_count="$(grep -Ec '(^|[[:space:]])M4_PROVIDER_CALLS::0($|[[:space:]])' "$dir/logs/flutter-drive.log" || true)"
  provider_nonzero_count="$(awk '/M4_PROVIDER_CALLS::/ && $0 !~ /M4_PROVIDER_CALLS::0([[:space:]]|$)/ {count += 1} END {print count + 0}' "$dir/logs/flutter-drive.log")"
  invariant_count="$(grep -Ec 'M4_AUTHORITY_INVARIANT::' "$dir/logs/flutter-drive.log" || true)"
  hard_count="$(cat "$dir/logs/logcat-full.txt" "$dir/logs/flutter-drive.log" | grep -Eci 'FATAL EXCEPTION|AndroidRuntime|Fatal signal [0-9]+|ANR in com\.kong373\.voice_social_app|MissingPluginException|RenderFlex overflow|Unhandled Exception|EXCEPTION CAUGHT BY|Failed assertion' || true)"
  crash_count="$(grep -Eci 'FATAL EXCEPTION|Fatal signal [0-9]+|ANR in com\.kong373\.voice_social_app' "$dir/logs/logcat-full.txt" "$dir/logs/flutter-drive.log" || true)"
  grep -Ei 'EXCEPTION CAUGHT BY|Unhandled Exception|Failed assertion|RenderFlex overflow' "$dir/logs/flutter-drive.log" >"$dir/logs/flutter-errors.txt" || true
  grep -Ei 'FATAL EXCEPTION|AndroidRuntime|Fatal signal [0-9]+|ANR in com\.kong373\.voice_social_app' "$dir/logs/logcat-full.txt" "$dir/logs/flutter-drive.log" >"$dir/logs/crash-anr.txt" || true

  local expected_marker="M4_VIEWPORT::$avd::"$width"x"$height"::$dpr"
  local acceptance_marker
  acceptance_marker="$(grep -Ec '(^|[[:space:]])M4_ACCEPTANCE::PASS($|[[:space:]])' "$dir/logs/flutter-drive.log" || true)"
  acceptance_failure_marker="$(grep -Ec '(^|[[:space:]])M4_ACCEPTANCE::FAIL($|[[:space:]])' "$dir/logs/flutter-drive.log" || true)"
  bad_route_status_count="$(awk -F '::' '/M4_ROUTE_STATUS::/ {if ($5 !~ /^[2-4][0-9][0-9]$/) count += 1} END {print count + 0}' "$dir/logs/flutter-drive.log")"
  local secret_status='PASS'
  local apk_status='PASS'
  secret_scan "$dir" || secret_status='FAIL'
  apk_scan "$dir" || apk_status='FAIL'
  local result='PASS'
  local reason='complete'
  if [[ "$drive_status" -ne 0 ]]; then result='FAIL'; reason="flutter_drive_exit_$drive_status"
  elif [[ "$marker_count" -lt 10 ]]; then result='FAIL'; reason='insufficient_http_route_markers'
  elif [[ "$provider_marker_count" -ne 1 || "$provider_count" -ne 1 || "$provider_nonzero_count" -ne 0 ]]; then result='FAIL'; reason='provider_calls_marker_missing_or_nonzero'
  elif [[ "$invariant_count" -lt 5 ]]; then result='FAIL'; reason='insufficient_authority_invariants'
  elif [[ "$screenshot_count" -lt 4 ]]; then result='FAIL'; reason='insufficient_screenshots'
  elif [[ "$acceptance_marker" -ne 1 || "$acceptance_failure_marker" -ne 0 ]]; then result='FAIL'; reason='acceptance_marker_missing_or_failed'
  elif [[ "$bad_route_status_count" -ne 0 ]]; then result='FAIL'; reason='route_status_missing_or_failed'
  elif ! grep -Fq "$expected_marker" "$dir/logs/flutter-drive.log"; then result='FAIL'; reason='viewport_marker_missing'
  elif [[ "$hard_count" -ne 0 || "$crash_count" -ne 0 ]]; then result='FAIL'; reason='hard_flutter_or_android_finding'
  elif [[ "$db_status" != 'COLLECTED' ]]; then result='FAIL'; reason='db_write_evidence_missing_or_failed'
  elif [[ "$secret_status" != PASS || "$apk_status" != PASS ]]; then result='FAIL'; reason='secret_scan_failed'
  fi
  {
    printf 'result=%s\nreason=%s\navd=%s\napi_level=%s\nprofile=%s\nserial=%s\n' "$result" "$reason" "$avd" "$api" "$profile" "$serial"
    printf 'run_id=%s\ntested_git_sha=%s\nflutter_sha=%s\nbackend_sha=%s\nhttp_route_marker_count=%s\nauthority_invariant_count=%s\n' "$RUN_ID" "$FLUTTER_SHA_ACTUAL" "$FLUTTER_SHA_ACTUAL" "$BACKEND_SHA_ACTUAL" "$marker_count" "$invariant_count"
    printf 'screenshot_count=%s\nhard_finding_count=%s\ncrash_anr_count=%s\n' "$screenshot_count" "$hard_count" "$crash_count"
    printf 'acceptance_status=%s\nprovider_calls_made=false\ndb_evidence=%s\nsecret_scan=%s\napk_secret_scan=%s\n' "$([[ "$result" == PASS ]] && printf PASS || printf FAIL)" "$db_status" "$secret_status" "$apk_status"
  } >"$dir/result.txt"
  [[ "$result" == PASS ]] || { OVERALL_RESULT='FAIL'; return 1; }
  return 0
}

start_relay
# AVD-A then AVD-B is intentional and produces independent API36 and API35
# evidence even when only one emulator slot is available.
run_one AVD-A "$A_API" "$A_PROFILE" "$A_PHYSICAL" "$A_DENSITY" "$A_WIDTH" "$A_HEIGHT" "$A_DPR" "$AVD_A_SERIAL" "$AVD_A_NAME" || true
run_one AVD-B "$B_API" "$B_PROFILE" "$B_PHYSICAL" "$B_DENSITY" "$B_WIDTH" "$B_HEIGHT" "$B_DPR" "$AVD_B_SERIAL" "$AVD_B_NAME" || true
if ! secret_scan "$ARTIFACT_ROOT"; then
  OVERALL_RESULT='FAIL'
fi
[[ "$OVERALL_RESULT" == PASS ]] || exit 1
exit 0
