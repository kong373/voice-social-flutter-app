#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

# This runner is deliberately narrower than the M5 vendor-live runner. It
# exercises one already-authenticated Android app session and one explicitly
# selected Alipay sandbox device. It never starts an emulator, enumerates
# devices, sends SMS, initializes Tencent, or confirms a successful payment.

readonly PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
readonly DEFAULT_SERIAL='emulator-5554'
readonly APP_PACKAGE='com.kong373.voice_social_app'
readonly TARGET_PACKAGE='com.eg.android.AlipayGphoneRC'
readonly TARGET_ACTIVITY='MspContainerActivity'
readonly DEVICE_WALLET_UI_DUMP_PATH='/data/local/tmp/voice-social-alipay-focused-wallet-ui.xml'
readonly OPERATOR_SCRIPT="$PROJECT_ROOT/tool/qa/m5_alipay_cancel_operator.sh"
readonly INTEGRATION_TARGET='integration_test/alipay_focused_smoke_test.dart'
readonly DRIVER_TARGET='test_driver/integration_test.dart'
readonly AUDIO_MANIFEST_SCRIPT="$PROJECT_ROOT/tool/prepare_android_audio_manifest.py"
readonly BACKEND_BASE_URL='http://10.0.2.2:18080/'
readonly PUBLIC_OAUTH_CLIENT_ID="$(printenv QA_OAUTH_CLIENT_ID || true)"
readonly EXPECTED_NATIVE_MARKER='M5_ALIPAY_NATIVE_RESULT::sdkCompleted=0::resultStatus=6001'
readonly EXPECTED_BRIDGE_MARKER='M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::pay_task_returned'
readonly MAX_BACK_ATTEMPTS=2
readonly EXIT_CONFIGURATION=64
readonly EXIT_MARKER=65
readonly EXIT_DEVICE=69
readonly EXIT_TIMEOUT=70

SELF_TEST=false
SERIAL_VALUE="${ANDROID_SERIAL:-$DEFAULT_SERIAL}"
ARTIFACT_DIR_ARG=''
CONFIRM_CANCEL="${QA_ALIPAY_FOCUSED_CONFIRMATION:-}"
CASHIER_TIMEOUT_SECONDS=60
AFTER_BACK_TIMEOUT_SECONDS=8
MARKER_TIMEOUT_SECONDS=30
POLL_INTERVAL_SECONDS=1
STABLE_POLLS=3
FLUTTER_BIN=''
ADB_BIN=''
ARTIFACT_DIR=''
ANDROID_HOST_DIR=''
FLUTTER_LOG_PATH=''
OPERATOR_LOG_PATH=''
OPERATOR_PID=''
WALLET_UI_DUMP_PATH=''
WALLET_UI_DUMP_ACTIVE=false
LOG_BASELINE_BYTES=0
BACK_COUNT=0
RUN_RESULT='NOT_RUN'
FLUTTER_STATUS='NOT_RUN'
OPERATOR_STATUS='NOT_RUN'
FAIL_REASON='not_started'

usage() {
  cat <<'USAGE'
Usage: run_alipay_focused_smoke.sh [options]

This is an explicitly authorized, cancellation-only Alipay sandbox smoke. It
requires a persisted authenticated app session and never performs a payment.
Before any Flutter target starts, the selected serial must show the audited
Alipay sandbox home UI (exact package plus Scan, Pay, and Home labels). This
cancel-only lane permits only the audited lower-feed degradation; an action
area error, unknown error, malformed page, or unhealthy cashier is rejected.

Options:
  --serial ID                 target Android serial (default: emulator-5554)
  --artifact-dir PATH         new absolute directory for sanitized evidence
  --confirm-cancel            explicit acknowledgement of the sandbox cancel lane
  --cashier-timeout SEC       bounded wait for the Alipay cashier (default: 60)
  --after-back-timeout SEC    bounded wait after each BACK (default: 8)
  --marker-timeout SEC        bounded wait for the PayTask marker (default: 30)
  --poll-interval SEC         poll delay (0 is allowed for self-tests)
  --stable-polls COUNT        consecutive cashier observations (default: 3)
  --self-test                 run offline marker/device/BACK contract checks
  --help                      show this help

The live run uses only BACK to cancel the sandbox cashier. It accepts exactly
sdkCompleted=0 + resultStatus=6001 + pay_task_returned, then requires the
first-party query/reconcile path to report cancellation. A missing, stale,
duplicate, timeout, non-target, or otherwise contradictory marker fails closed.

Live mode requires QA_OAUTH_CLIENT_ID in the protected process environment.
It must be the public OAuth client identifier only: whitespace, '=', and
secret/confidential-looking values are rejected. OAuth client secrets are never
accepted or forwarded to Flutter. The value is passed only as a dart-define and
is never printed.
USAGE
}

fail_configuration() {
  RUN_RESULT='FAIL'
  FAIL_REASON="$1"
  printf 'Alipay focused smoke: configuration rejected (%s)\n' "$1" >&2
  exit "$EXIT_CONFIGURATION"
}

fail_device() {
  RUN_RESULT='FAIL'
  FAIL_REASON="$1"
  printf 'Alipay focused smoke: device rejected (%s)\n' "$1" >&2
  exit "$EXIT_DEVICE"
}

fail_marker() {
  RUN_RESULT='FAIL'
  FAIL_REASON="$1"
  printf 'Alipay focused smoke: result marker rejected (%s)\n' "$1" >&2
  exit "$EXIT_MARKER"
}

fail_timeout() {
  RUN_RESULT='FAIL'
  FAIL_REASON="$1"
  printf 'Alipay focused smoke: bounded wait expired (%s)\n' "$1" >&2
  exit "$EXIT_TIMEOUT"
}

audit() {
  # Only fixed vocabulary and validated counters are emitted. Never print
  # order/account data, command output, or inherited environment values.
  printf 'ALIPAY_FOCUSED_SMOKE::%s\n' "$1"
}

require_integer() {
  local name="$1"
  local value="$2"
  [[ "$value" =~ ^[0-9]+$ ]] || fail_configuration "$name must be a non-negative integer"
  (( value <= 600 )) || fail_configuration "$name exceeds the 600 second bound"
}

public_oauth_client_id_is_valid() {
  local value="$1"
  local normalized=''
  [[ -n "$value" ]] || return 1
  [[ "$value" != *[[:space:]]* ]] || return 1
  [[ "$value" != *'='* ]] || return 1
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* &&
    "$value" != *$'\t'* ]] || return 1
  normalized="$(printf '%s' "$value" | LC_ALL=C tr '[:upper:]' '[:lower:]')" ||
    return 1
  [[ "${#normalized}" -ge 1 && "${#normalized}" -le 256 ]] || return 1
  [[ "$normalized" != *[![:print:]]* ]] || return 1
  if [[ "$normalized" =~ (^|[^a-z0-9])(oauth[-_.:/+]?client[-_.:/+]?secret|client[-_.:/+]?secret|secret|password|private[-_.:/+]?key|access[-_.:/+]?key|api[-_.:/+]?key|token|credential|credentials|pat|auth|bearer)([^a-z0-9]|$) ]]; then
    return 1
  fi
  return 0
}

require_public_oauth_client_id() {
  [[ -z "${QA_OAUTH_CLIENT_SECRET+x}" &&
    -z "${OAUTH_CLIENT_SECRET+x}" ]] ||
    fail_configuration 'OAuth client secrets are forbidden'
  public_oauth_client_id_is_valid "$PUBLIC_OAUTH_CLIENT_ID" ||
    fail_configuration 'QA_OAUTH_CLIENT_ID is missing or invalid'
}

oauth_client_dart_define() {
  local value="$1"
  public_oauth_client_id_is_valid "$value" || return 1
  printf '%s' "--dart-define=OAUTH_CLIENT_ID=$value"
}

parse_args() {
  local argument
  while (($# > 0)); do
    argument="$1"
    case "$argument" in
      --help|-h)
        usage
        exit 0
        ;;
      --self-test)
        SELF_TEST=true
        shift
        ;;
      --confirm-cancel)
        CONFIRM_CANCEL='I_UNDERSTAND_SANDBOX_CANCEL'
        shift
        ;;
      --serial)
        (($# >= 2)) || fail_configuration 'serial is missing'
        [[ -z "${SERIAL_VALUE_ARG+x}" ]] || fail_configuration 'serial supplied more than once'
        SERIAL_VALUE_ARG="$2"
        SERIAL_VALUE="$2"
        shift 2
        ;;
      --serial=*)
        [[ -z "${SERIAL_VALUE_ARG+x}" ]] || fail_configuration 'serial supplied more than once'
        SERIAL_VALUE_ARG="${argument#*=}"
        SERIAL_VALUE="${argument#*=}"
        shift
        ;;
      --artifact-dir)
        (($# >= 2)) || fail_configuration 'artifact directory is missing'
        [[ -z "$ARTIFACT_DIR_ARG" ]] || fail_configuration 'artifact directory supplied more than once'
        ARTIFACT_DIR_ARG="$2"
        shift 2
        ;;
      --artifact-dir=*)
        [[ -z "$ARTIFACT_DIR_ARG" ]] || fail_configuration 'artifact directory supplied more than once'
        ARTIFACT_DIR_ARG="${argument#*=}"
        shift
        ;;
      --cashier-timeout)
        (($# >= 2)) || fail_configuration 'cashier timeout is missing'
        CASHIER_TIMEOUT_SECONDS="$2"
        shift 2
        ;;
      --after-back-timeout)
        (($# >= 2)) || fail_configuration 'after-BACK timeout is missing'
        AFTER_BACK_TIMEOUT_SECONDS="$2"
        shift 2
        ;;
      --marker-timeout)
        (($# >= 2)) || fail_configuration 'marker timeout is missing'
        MARKER_TIMEOUT_SECONDS="$2"
        shift 2
        ;;
      --poll-interval)
        (($# >= 2)) || fail_configuration 'poll interval is missing'
        POLL_INTERVAL_SECONDS="$2"
        shift 2
        ;;
      --stable-polls)
        (($# >= 2)) || fail_configuration 'stable poll count is missing'
        STABLE_POLLS="$2"
        shift 2
        ;;
      *)
        fail_configuration 'unknown option'
        ;;
    esac
  done
}

pause_between_polls() {
  if (( POLL_INTERVAL_SECONDS > 0 )); then
    sleep "$POLL_INTERVAL_SECONDS"
  fi
}

serial_matches_focused_target() {
  [[ "$1" == "$DEFAULT_SERIAL" ]]
}

validate_serial_value() {
  [[ "$SERIAL_VALUE" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$ ]] ||
    fail_configuration 'serial has an unsafe format'
  if [[ -n "${ANDROID_SERIAL:-}" && -n "${SERIAL_VALUE_ARG+x}" &&
    "$ANDROID_SERIAL" != "$SERIAL_VALUE" ]]; then
    fail_configuration 'ANDROID_SERIAL disagrees with --serial'
  fi
  serial_matches_focused_target "$SERIAL_VALUE" ||
    fail_configuration 'focused Alipay smoke target serial is frozen to emulator-5554'
  if [[ -n "${QA_AVD_B_SERIAL:-}" && "$QA_AVD_B_SERIAL" == "$SERIAL_VALUE" ]]; then
    fail_configuration 'selected serial is reserved for the second AVD'
  fi
}

validate_bounds() {
  require_integer cashier-timeout "$CASHIER_TIMEOUT_SECONDS"
  require_integer after-back-timeout "$AFTER_BACK_TIMEOUT_SECONDS"
  require_integer marker-timeout "$MARKER_TIMEOUT_SECONDS"
  require_integer poll-interval "$POLL_INTERVAL_SECONDS"
  require_integer stable-polls "$STABLE_POLLS"
  (( STABLE_POLLS >= 2 )) || fail_configuration 'stable poll count must be at least 2'
}

resolve_commands() {
  ADB_BIN="$(command -v adb || true)"
  FLUTTER_BIN="$(command -v flutter || true)"
  [[ -n "$ADB_BIN" && -x "$ADB_BIN" ]] || fail_configuration 'adb executable is unavailable'
  [[ -n "$FLUTTER_BIN" && -x "$FLUTTER_BIN" ]] || fail_configuration 'Flutter executable is unavailable'
  for command_name in python3 git tar mktemp shasum awk grep wc head tail find tr; do
    command -v "$command_name" >/dev/null 2>&1 || fail_configuration "missing command: $command_name"
  done
}

create_safe_artifact_dir() {
  if [[ -z "$ARTIFACT_DIR_ARG" ]]; then
    ARTIFACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/voice-social-alipay-focused.XXXXXX")" ||
      fail_configuration 'temporary artifact directory could not be created'
    return 0
  fi
  ARTIFACT_DIR="$ARTIFACT_DIR_ARG"
  [[ "$ARTIFACT_DIR" == /* && "$ARTIFACT_DIR" != *$'\n'* &&
    "$ARTIFACT_DIR" != *$'\r'* && "$ARTIFACT_DIR" != *$'\t'* &&
    "$ARTIFACT_DIR" != *'..'* ]] ||
    fail_configuration 'artifact directory must be a new absolute path without traversal'
  python3 - "$ARTIFACT_DIR" <<'PY' || fail_configuration 'artifact directory is not safe to create'
import os
import stat
import sys
from pathlib import Path

raw = sys.argv[1]
path = Path(raw)
if not path.is_absolute() or os.path.normpath(raw) != raw or os.path.lexists(raw):
    raise SystemExit(1)
missing = []
ancestor = path.parent
while not os.path.lexists(ancestor):
    missing.append(ancestor)
    if ancestor == ancestor.parent:
        raise SystemExit(1)
    ancestor = ancestor.parent
current = Path(ancestor.anchor)
for part in ancestor.parts[1:]:
    current /= part
    mode = os.lstat(current).st_mode
    if stat.S_ISLNK(mode) or not stat.S_ISDIR(mode):
        raise SystemExit(1)
for directory in reversed(missing):
    os.mkdir(directory, 0o700)
os.mkdir(path, 0o700)
PY
}

foreground_is_target() {
  local dump="$1"
  awk -v package="$TARGET_PACKAGE" -v activity="$TARGET_ACTIVITY" '
    /(^|[[:space:]])(mResumedActivity|ResumedActivity|topResumedActivity|mFocusedApp):/ {
      component_start = index($0, package "/")
      if (component_start > 0) {
        component = substr($0, component_start + length(package) + 1)
        sub(/[[:space:]}].*$/, "", component)
        if (length(component) >= length(activity) &&
            substr(component, length(component) - length(activity) + 1) == activity) {
          found = 1
        }
      }
    }
    END { exit(found ? 0 : 1) }
  ' <<<"$dump"
}

foreground_package_is_target() {
  local dump="$1"
  awk -v package="$TARGET_PACKAGE" '
    /(^|[[:space:]])(mResumedActivity|ResumedActivity|topResumedActivity|mFocusedApp):/ {
      if (index($0, package "/") > 0) {
        found = 1
      }
    }
    END { exit(found ? 0 : 1) }
  ' <<<"$dump"
}

adb_get_state() {
  local state=''
  local status=0
  state="$("$ADB_BIN" -s "$SERIAL_VALUE" get-state 2>/dev/null)" || status=$?
  state="${state//$'\r'/}"
  state="${state//$'\n'/}"
  [[ "$status" -eq 0 && "$state" == 'device' ]] ||
    fail_device 'selected serial is not online'
}

read_wallet_foreground_state() {
  local dump=''
  local status=0
  dump="$("$ADB_BIN" -s "$SERIAL_VALUE" shell dumpsys activity activities 2>/dev/null)" || status=$?
  [[ "$status" -eq 0 ]] || fail_device 'activity state unavailable'
  foreground_package_is_target "$dump"
}

wallet_ui_is_healthy() {
  [[ -n "$WALLET_UI_DUMP_PATH" && -f "$WALLET_UI_DUMP_PATH" &&
    ! -L "$WALLET_UI_DUMP_PATH" ]] || return 1
  python3 - "$WALLET_UI_DUMP_PATH" "$TARGET_PACKAGE" 2>/dev/null <<'PY'
import xml.etree.ElementTree as ET
import re
import sys
from pathlib import Path

try:
    dump_path = Path(sys.argv[1])
    target_package = sys.argv[2]
    text = dump_path.read_text(encoding='utf-8', errors='replace')
    root = ET.fromstring(text)
except (ET.ParseError, OSError, ValueError):
    raise SystemExit(1)

if root.tag != 'hierarchy':
    raise SystemExit(1)

target_nodes = [
    node for node in root.iter('node')
    if node.attrib.get('package') == target_package
]
if not target_nodes:
    raise SystemExit(1)
labels = {
    node.attrib.get(attribute, '').strip().casefold()
    for node in target_nodes
    for attribute in ('text', 'content-desc')
}
if not {'scan', 'pay', 'home'}.issubset(labels):
    raise SystemExit(1)

# The audited API-29 sandbox wallet can leave its lower home-feed card in a
# degraded state while the native cashier remains usable.  This exception is
# deliberately local to the cancellation runner: it cannot be enabled by an
# environment variable or command-line flag, and it does not relax any PayTask
# result check.  Unknown errors, errors outside the fixed lower-feed region,
# hidden/disabled nodes, or errors attributed to another package fail closed.
always_rejected = ('server busy', 'try again later')
normalized = text.casefold()
if any(phrase in normalized for phrase in always_rejected):
    raise SystemExit(1)

allowed_degraded_markers = ('please wait a minute', 'reload')
allowed_degraded_labels = {
    'please wait a minute. will be back soon.',
    'reload',
}
degraded_nodes = []
for node in root.iter('node'):
    node_labels = {
        node.attrib.get(attribute, '').strip().casefold()
        for attribute in ('text', 'content-desc')
        if node.attrib.get(attribute, '').strip()
    }
    if any(
        marker in label
        for marker in allowed_degraded_markers
        for label in node_labels
    ):
        if not node_labels.issubset(allowed_degraded_labels):
            raise SystemExit(1)
        degraded_nodes.append(node)

for phrase in allowed_degraded_markers:
    if phrase in normalized and not any(
        any(
            phrase in node.attrib.get(attribute, '').strip().casefold()
            for attribute in ('text', 'content-desc')
        )
        for node in degraded_nodes
    ):
        raise SystemExit(1)

if len(degraded_nodes) > 4:
    raise SystemExit(1)

bounds_pattern = re.compile(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
for node in degraded_nodes:
    if node.attrib.get('package') != target_package:
        raise SystemExit(1)
    if node.attrib.get('enabled') != 'true':
        raise SystemExit(1)
    if node.attrib.get('visible-to-user') == 'false':
        raise SystemExit(1)
    match = bounds_pattern.fullmatch(node.attrib.get('bounds', ''))
    if match is None:
        raise SystemExit(1)
    x1, y1, x2, y2 = (int(value) for value in match.groups())
    if not (0 <= x1 < x2 <= 1080 and 1200 <= y1 < y2 <= 1600):
        raise SystemExit(1)
PY
}

clear_wallet_ui_dump() {
  if [[ "$WALLET_UI_DUMP_ACTIVE" == true && -n "$ADB_BIN" ]]; then
    "$ADB_BIN" -s "$SERIAL_VALUE" shell rm -f "$DEVICE_WALLET_UI_DUMP_PATH" >/dev/null 2>&1 || true
  fi
  if [[ -n "$WALLET_UI_DUMP_PATH" && -f "$WALLET_UI_DUMP_PATH" &&
    ! -L "$WALLET_UI_DUMP_PATH" ]]; then
    rm -f -- "$WALLET_UI_DUMP_PATH"
  fi
  WALLET_UI_DUMP_PATH=''
  WALLET_UI_DUMP_ACTIVE=false
}

wallet_health_preflight() {
  adb_get_state
  if ! read_wallet_foreground_state; then
    fail_device 'Alipay sandbox wallet foreground is not proven'
  fi
  WALLET_UI_DUMP_PATH="$ARTIFACT_DIR/.wallet-health-ui.xml"
  : >"$WALLET_UI_DUMP_PATH"
  WALLET_UI_DUMP_ACTIVE=true
  "$ADB_BIN" -s "$SERIAL_VALUE" shell uiautomator dump \
    "$DEVICE_WALLET_UI_DUMP_PATH" >/dev/null 2>&1 ||
    fail_device 'Alipay sandbox wallet UI dump is unavailable'
  "$ADB_BIN" -s "$SERIAL_VALUE" shell cat "$DEVICE_WALLET_UI_DUMP_PATH" \
    >"$WALLET_UI_DUMP_PATH" 2>/dev/null ||
    fail_device 'Alipay sandbox wallet UI dump cannot be read'
  wallet_ui_is_healthy || fail_device 'Alipay sandbox wallet health is not proven'
  clear_wallet_ui_dump
  audit 'WALLET_HEALTH_PASS'
}

scan_marker_stream() {
  while IFS= read -r line; do
    line="${line%$'\r'}"
    case "$line" in
      "$EXPECTED_NATIVE_MARKER") printf 'NATIVE_VALID\n' ;;
      M5_ALIPAY_NATIVE_RESULT::*) printf 'NATIVE_INVALID\n' ;;
      "$EXPECTED_BRIDGE_MARKER") printf 'BRIDGE_VALID\n' ;;
      M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::*) printf 'BRIDGE_INVALID\n' ;;
    esac
  done
}

marker_state_from_file_prefix() {
  local marker_count=0
  local invalid_count=0
  local marker_kind=''
  while IFS= read -r marker_kind; do
    case "$marker_kind" in
      NATIVE_VALID|BRIDGE_VALID) marker_count=$((marker_count + 1)) ;;
      NATIVE_INVALID|BRIDGE_INVALID) invalid_count=$((invalid_count + 1)) ;;
    esac
  done < <(if (( LOG_BASELINE_BYTES > 0 )); then
    head -c "$LOG_BASELINE_BYTES" "$FLUTTER_LOG_PATH" | scan_marker_stream
  else
    scan_marker_stream </dev/null
  fi)
  if (( invalid_count > 0 )); then
    printf 'INVALID'
  elif (( marker_count > 0 )); then
    printf 'PRESENT'
  else
    printf 'MISSING'
  fi
}

classify_marker_pair() {
  local current_bytes marker_kind
  local native_valid_count=0
  local bridge_valid_count=0
  local invalid_count=0
  current_bytes="$(wc -c < "$FLUTTER_LOG_PATH" 2>/dev/null | tr -d '[:space:]')" || {
    printf 'INVALID'
    return 0
  }
  [[ "$current_bytes" =~ ^[0-9]+$ && "$current_bytes" -ge "$LOG_BASELINE_BYTES" ]] || {
    printf 'INVALID'
    return 0
  }
  while IFS= read -r marker_kind; do
    case "$marker_kind" in
      NATIVE_VALID) native_valid_count=$((native_valid_count + 1)) ;;
      BRIDGE_VALID) bridge_valid_count=$((bridge_valid_count + 1)) ;;
      NATIVE_INVALID|BRIDGE_INVALID) invalid_count=$((invalid_count + 1)) ;;
    esac
  done < <(tail -c +$((LOG_BASELINE_BYTES + 1)) "$FLUTTER_LOG_PATH" | scan_marker_stream)
  if (( invalid_count > 0 )); then
    printf 'INVALID'
  elif (( native_valid_count > 1 || bridge_valid_count > 1 )); then
    printf 'AMBIGUOUS'
  elif (( native_valid_count == 1 && bridge_valid_count == 1 )); then
    printf 'VALID'
  elif (( native_valid_count == 1 || bridge_valid_count == 1 )); then
    printf 'PARTIAL'
  else
    printf 'MISSING'
  fi
}

record_marker_baseline() {
  LOG_BASELINE_BYTES="$(wc -c < "$FLUTTER_LOG_PATH" 2>/dev/null | tr -d '[:space:]')" || return 1
  [[ "$LOG_BASELINE_BYTES" =~ ^[0-9]+$ ]] || return 1
  [[ "$(marker_state_from_file_prefix)" == 'MISSING' ]]
}

wait_for_marker_pair() {
  local deadline=$((SECONDS + MARKER_TIMEOUT_SECONDS))
  local state=''
  while (( SECONDS <= deadline )); do
    state="$(classify_marker_pair)"
    case "$state" in
      VALID) return 0 ;;
      INVALID|AMBIGUOUS) return 1 ;;
      PARTIAL|MISSING) ;;
    esac
    pause_between_polls
  done
  return 1
}

safe_flutter_log_filter() {
  # The Flutter tool's raw output is never written. Only fixed, bounded
  # markers survive this filter, so an SDK exception cannot persist orderStr or
  # credentials in the evidence directory.
  python3 -u -c '
import re
import sys

patterns = (
    re.compile(r"^(?:[VDIWEF]/flutter \(\s*[0-9]+\): )?M5_ALIPAY_NATIVE_RESULT::sdkCompleted=[01]::resultStatus=[A-Za-z0-9_.-]{1,32}$"),
    re.compile(r"^(?:[VDIWEF]/flutter \(\s*[0-9]+\): )?M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::[A-Za-z0-9_.-]{1,40}$"),
    re.compile(r"^(?:[VDIWEF]/flutter \(\s*[0-9]+\): )?M5_ALIPAY_FOCUSED::(?:catalog|order|native_launcher|query_reconcile|complete)::(?:START|PASS|FAIL)$"),
)
for raw in sys.stdin:
    line = raw.rstrip("\r\n")
    for pattern in patterns:
        match = pattern.search(line)
        if match is not None:
            marker = match.group(0)
            envelope = re.match(r"^[VDIWEF]/flutter \(\s*[0-9]+\): ", marker)
            if envelope is not None:
                marker = marker[envelope.end():]
            sys.stdout.write(marker + "\n")
            sys.stdout.flush()
            break
'
}

prepare_android_host() {
  ANDROID_HOST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/voice-social-alipay-host.XXXXXX")" ||
    fail_configuration 'temporary Android host could not be created'
  "$FLUTTER_BIN" create --platforms=android --android-language=kotlin \
    --org=com.kong373 --project-name=voice_social_app --no-pub \
    "$ANDROID_HOST_DIR" >/dev/null 2>&1 ||
    fail_configuration 'temporary Android host generation failed'
  git -C "$PROJECT_ROOT" archive --format=tar HEAD | tar -x -C "$ANDROID_HOST_DIR" ||
    fail_configuration 'tracked checkout overlay failed'
  [[ -f "$AUDIO_MANIFEST_SCRIPT" ]] || fail_configuration 'Android audio manifest helper is missing'
  python3 "$AUDIO_MANIFEST_SCRIPT" "$ANDROID_HOST_DIR" >/dev/null 2>&1 ||
    fail_configuration 'Android audio manifest preparation failed'
  (
    cd "$ANDROID_HOST_DIR"
    "$FLUTTER_BIN" pub get --enforce-lockfile >/dev/null 2>&1
  ) || fail_configuration 'locked Flutter dependency regeneration failed'
}

run_flutter_target() {
  set +e
  (
    cd "$ANDROID_HOST_DIR"
    env -u QA_OAUTH_CLIENT_ID -u QA_OAUTH_CLIENT_SECRET -u OAUTH_CLIENT_SECRET \
      "$FLUTTER_BIN" drive --no-pub \
      --driver="$DRIVER_TARGET" --target="$INTEGRATION_TARGET" \
      --device-id="$SERIAL_VALUE" \
      --dart-define=BACKEND_MODE=live \
      --dart-define=APP_ENV=development \
      --dart-define=ALLOW_INSECURE_HTTP=true \
      --dart-define=API_BASE_URL="$BACKEND_BASE_URL" \
      "$(oauth_client_dart_define "$PUBLIC_OAUTH_CLIENT_ID")" \
      --dart-define=CLIENT_TYPE=Android \
      --dart-define=CLIENT_INNER_VERSION=6 \
      --dart-define=API_TIMEOUT_SECONDS=15 \
      --dart-define=ENABLE_TENCENT_IM=false \
      --dart-define=ENABLE_ALIPAY_APP_PAY=true \
      2>&1
  ) | safe_flutter_log_filter >"$FLUTTER_LOG_PATH"
  FLUTTER_STATUS="${PIPESTATUS[0]}"
  set -e
}

start_cancel_operator() {
  ANDROID_SERIAL="$SERIAL_VALUE" \
    "$OPERATOR_SCRIPT" --adb "$ADB_BIN" --target-serial "$SERIAL_VALUE" \
    --flutter-log "$FLUTTER_LOG_PATH" \
    --target-timeout "$CASHIER_TIMEOUT_SECONDS" \
    --after-back-timeout "$AFTER_BACK_TIMEOUT_SECONDS" \
    --marker-timeout "$MARKER_TIMEOUT_SECONDS" \
    --poll-interval "$POLL_INTERVAL_SECONDS" \
    --stable-polls "$STABLE_POLLS" \
    >"$OPERATOR_LOG_PATH" 2>&1 &
  OPERATOR_PID=$!
}

safe_artifact_scan() {
  python3 - "$ARTIFACT_DIR" <<'PY'
import os
import sys
from pathlib import Path

root = Path(sys.argv[1])
for path in root.rglob("*"):
    if not path.is_file() or path.is_symlink():
        continue
    payload = path.read_bytes().lower()
    forbidden = (
        b"orderstr=",
        b"orderstr:",
        b"orderstring=",
        b"orderstring:",
        b"orderinfo=",
        b"orderinfo:",
        b"private_key",
        b"private key",
        b"bearer ",
        b"access_token=",
        b"access_token:",
    )
    if any(needle in payload for needle in forbidden):
        raise SystemExit(1)
PY
}

write_summary() {
  [[ -n "$ARTIFACT_DIR" && -d "$ARTIFACT_DIR" ]] || return 0
  {
    printf 'Alipay focused sandbox cancellation acceptance\n'
    printf 'conclusion=%s\nserial=%s\n' "$RUN_RESULT" "$SERIAL_VALUE"
    printf 'tested_git_sha=%s\n' "$(git -C "$PROJECT_ROOT" rev-parse --verify HEAD 2>/dev/null || printf unknown)"
    printf 'flutter_status=%s\noperator_status=%s\nreason=%s\n' \
      "$FLUTTER_STATUS" "$OPERATOR_STATUS" "$FAIL_REASON"
    if [[ "$RUN_RESULT" == 'PASS' ]]; then
      printf 'wallet_health=PASS\ncatalog=PASS\norder=PASS\nnative_launcher=PASS\n'
      printf 'native_result=sdkCompleted=0,resultStatus=6001,bridge=pay_task_returned\n'
      printf 'query_reconcile=PASS\n'
    else
      printf 'wallet_health=NOT_PROVEN\ncatalog=NOT_PROVEN\norder=NOT_PROVEN\nnative_launcher=NOT_PROVEN\n'
      printf 'native_result=NOT_ACCEPTED\nquery_reconcile=NOT_PROVEN\n'
    fi
    printf 'payment_confirmation=not_used\nreal_debit=forbidden\nmax_back_attempts=%s\n' "$MAX_BACK_ATTEMPTS"
    printf 'raw_flutter_log=not_saved\n'
  } >"$ARTIFACT_DIR/summary.txt"
}

write_manifest() {
  [[ -n "$ARTIFACT_DIR" && -d "$ARTIFACT_DIR" ]] || return 0
  python3 - "$ARTIFACT_DIR" "$ARTIFACT_DIR/evidence-manifest.sha256" <<'PY'
import hashlib
import os
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
manifest = Path(sys.argv[2]).resolve()
rows = []
for path in root.rglob("*"):
    if not path.is_file() or path.is_symlink() or path.resolve() == manifest:
        continue
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    rows.append((path.relative_to(root).as_posix(), digest))
temporary = root / ".evidence-manifest.tmp"
with temporary.open("w", encoding="utf-8") as stream:
    for relative, digest in sorted(rows):
        stream.write(f"{digest}  {relative}\n")
os.replace(temporary, manifest)
PY
}

cleanup() {
  local incoming_status=$?
  set +e
  if [[ -n "$OPERATOR_PID" ]]; then
    kill "$OPERATOR_PID" 2>/dev/null || true
    wait "$OPERATOR_PID" 2>/dev/null || true
  fi
  clear_wallet_ui_dump
  if [[ -n "$ANDROID_HOST_DIR" && -d "$ANDROID_HOST_DIR" && ! -L "$ANDROID_HOST_DIR" ]]; then
    rm -rf -- "$ANDROID_HOST_DIR"
    ANDROID_HOST_DIR=''
  fi
  write_summary
  write_manifest
  trap - EXIT
  exit "$incoming_status"
}

self_test() {
  (
    set -Eeuo pipefail
    if ! serial_matches_focused_target "$DEFAULT_SERIAL"; then
      exit 1
    fi
    if serial_matches_focused_target 'emulator-5556'; then
      exit 1
    fi
    local root
    root="$(mktemp -d "${TMPDIR:-/tmp}/voice-social-alipay-self-test.XXXXXX")"
    trap 'rm -rf -- "$root"' EXIT
    FLUTTER_LOG_PATH="$root/log"
    : >"$FLUTTER_LOG_PATH"
    LOG_BASELINE_BYTES=0

    local fixture_define invalid_client
    fixture_define="$(oauth_client_dart_define 'fixture-public-client')"
    [[ "$fixture_define" == '--dart-define=OAUTH_CLIENT_ID=fixture-public-client' ]] || exit 1
    [[ "$(oauth_client_dart_define "$PUBLIC_OAUTH_CLIENT_ID")" == "--dart-define=OAUTH_CLIENT_ID=$PUBLIC_OAUTH_CLIENT_ID" ]] || exit 1
    for invalid_client in '' 'public client' 'public=client' \
      'public-client-secret' 'public_token' 'Bearer-client'; do
      if public_oauth_client_id_is_valid "$invalid_client"; then
        exit 1
      fi
    done
    public_oauth_client_id_is_valid 'public-client-01' || exit 1

    printf '%s\n' "$EXPECTED_NATIVE_MARKER" >"$FLUTTER_LOG_PATH"
    if record_marker_baseline; then exit 1; fi

    : >"$FLUTTER_LOG_PATH"
    record_marker_baseline || exit 1
    printf '%s\n%s\n' "$EXPECTED_NATIVE_MARKER" "$EXPECTED_BRIDGE_MARKER" >>"$FLUTTER_LOG_PATH"
    [[ "$(classify_marker_pair)" == 'VALID' ]] || exit 1

    : >"$FLUTTER_LOG_PATH"
    record_marker_baseline || exit 1
    printf '%s\n%s\n' \
      'M5_ALIPAY_NATIVE_RESULT::sdkCompleted=0::resultStatus=none' \
      "$EXPECTED_BRIDGE_MARKER" >>"$FLUTTER_LOG_PATH"
    [[ "$(classify_marker_pair)" == 'INVALID' ]] || exit 1

    : >"$FLUTTER_LOG_PATH"
    record_marker_baseline || exit 1
    printf '%s\n%s\n%s\n' \
      "$EXPECTED_NATIVE_MARKER" "$EXPECTED_NATIVE_MARKER" "$EXPECTED_BRIDGE_MARKER" >>"$FLUTTER_LOG_PATH"
    [[ "$(classify_marker_pair)" == 'AMBIGUOUS' ]] || exit 1

    : >"$FLUTTER_LOG_PATH"
    record_marker_baseline || exit 1
    MARKER_TIMEOUT_SECONDS=0
    wait_for_marker_pair && exit 1

    printf '%s\n%s\n%s\n' \
      "I/flutter ( 12345): $EXPECTED_NATIVE_MARKER" \
      "D/flutter (12345): $EXPECTED_BRIDGE_MARKER" \
      "prefix-$EXPECTED_NATIVE_MARKER" >"$root/raw-flutter.log"
    safe_flutter_log_filter <"$root/raw-flutter.log" >"$root/filtered-flutter.log"
    [[ "$(grep -Fxc "$EXPECTED_NATIVE_MARKER" "$root/filtered-flutter.log" || true)" -eq 1 ]] || exit 1
    [[ "$(grep -Fxc "$EXPECTED_BRIDGE_MARKER" "$root/filtered-flutter.log" || true)" -eq 1 ]] || exit 1
    [[ "$(grep -Fxc "prefix-$EXPECTED_NATIVE_MARKER" "$root/filtered-flutter.log" || true)" -eq 0 ]] || exit 1

    WALLET_UI_DUMP_PATH="$root/wallet-ui.xml"
    printf '%s\n' '<hierarchy><node package="com.eg.android.AlipayGphoneRC" text="Scan" /><node package="com.eg.android.AlipayGphoneRC" text="Pay" /><node package="com.eg.android.AlipayGphoneRC" text="Home" /></hierarchy>' >"$WALLET_UI_DUMP_PATH"
    wallet_ui_is_healthy || exit 1
    printf '%s\n' '<hierarchy><node package="com.eg.android.AlipayGphoneRC" text="Scan" /><node package="com.eg.android.AlipayGphoneRC" text="Pay" /></hierarchy>' >"$WALLET_UI_DUMP_PATH"
    wallet_ui_is_healthy && exit 1
    printf '%s\n' '<hierarchy><node package="com.other.wallet" text="Scan" /><node package="com.other.wallet" text="Pay" /><node package="com.other.wallet" text="Home" /></hierarchy>' >"$WALLET_UI_DUMP_PATH"
    wallet_ui_is_healthy && exit 1
    for degraded_text in 'Please wait a minute. Will be back soon.' 'Reload'; do
      printf '<hierarchy><node package="com.eg.android.AlipayGphoneRC" text="Scan" /><node package="com.eg.android.AlipayGphoneRC" text="Pay" /><node package="com.eg.android.AlipayGphoneRC" text="Home" /><node package="com.eg.android.AlipayGphoneRC" text="%s" enabled="true" bounds="[64,1279][1016,1454]" /></hierarchy>\n' "$degraded_text" >"$WALLET_UI_DUMP_PATH"
      wallet_ui_is_healthy || exit 1
      printf '<hierarchy><node package="com.eg.android.AlipayGphoneRC" text="Scan" /><node package="com.eg.android.AlipayGphoneRC" text="Pay" /><node package="com.eg.android.AlipayGphoneRC" text="Home" /><node package="com.eg.android.AlipayGphoneRC" text="%s" enabled="true" bounds="[64,300][1016,360]" /></hierarchy>\n' "$degraded_text" >"$WALLET_UI_DUMP_PATH"
      wallet_ui_is_healthy && exit 1
      printf '<hierarchy><node package="com.eg.android.AlipayGphoneRC" text="Scan" /><node package="com.eg.android.AlipayGphoneRC" text="Pay" /><node package="com.eg.android.AlipayGphoneRC" text="Home" /><node package="com.eg.android.AlipayGphoneRC" text="%s" enabled="true" /></hierarchy>\n' "$degraded_text" >"$WALLET_UI_DUMP_PATH"
      wallet_ui_is_healthy && exit 1
      printf '<hierarchy><node package="com.eg.android.AlipayGphoneRC" text="Scan" /><node package="com.eg.android.AlipayGphoneRC" text="Pay" /><node package="com.eg.android.AlipayGphoneRC" text="Home" /><node package="com.other.wallet" text="%s" enabled="true" bounds="[64,1279][1016,1454]" /></hierarchy>\n' "$degraded_text" >"$WALLET_UI_DUMP_PATH"
      wallet_ui_is_healthy && exit 1
    done
    printf '%s\n' '<hierarchy><node package="com.eg.android.AlipayGphoneRC" text="Scan" /><node package="com.eg.android.AlipayGphoneRC" text="Pay" /><node package="com.eg.android.AlipayGphoneRC" text="Home" /><node package="com.eg.android.AlipayGphoneRC" text="Reload" enabled="false" bounds="[64,1279][1016,1454]" /></hierarchy>' >"$WALLET_UI_DUMP_PATH"
    wallet_ui_is_healthy && exit 1
    printf '%s\n' '<hierarchy><node package="com.eg.android.AlipayGphoneRC" text="Scan" /><node package="com.eg.android.AlipayGphoneRC" text="Pay" /><node package="com.eg.android.AlipayGphoneRC" text="Home" /><node package="com.eg.android.AlipayGphoneRC" text="Reload" enabled="true" visible-to-user="false" bounds="[64,1279][1016,1454]" /></hierarchy>' >"$WALLET_UI_DUMP_PATH"
    wallet_ui_is_healthy && exit 1
    for unhealthy_text in 'Server busy' 'try again later'; do
      printf '<hierarchy><node package="com.eg.android.AlipayGphoneRC" text="Scan" /><node package="com.eg.android.AlipayGphoneRC" text="Pay" /><node package="com.eg.android.AlipayGphoneRC" text="Home" /><node package="com.eg.android.AlipayGphoneRC" text="%s" /></hierarchy>\n' "$unhealthy_text" >"$WALLET_UI_DUMP_PATH"
      wallet_ui_is_healthy && exit 1
    done

    foreground_is_target 'mResumedActivity: ActivityRecord{com.other.app/.MainActivity}' && exit 1 || true
    foreground_is_target 'mResumedActivity: ActivityRecord{com.eg.android.AlipayGphoneRC/com.alipay.android.msp.ui.views.MspContainerActivity}' || exit 1
    foreground_package_is_target 'mResumedActivity: ActivityRecord{com.eg.android.AlipayGphoneRC/com.alipay.mobile.quinox.LauncherActivity}' || exit 1
    foreground_package_is_target 'mResumedActivity: ActivityRecord{com.other.app/.MainActivity}' && exit 1 || true

    BACK_COUNT=0
    (( BACK_COUNT < MAX_BACK_ATTEMPTS )) || exit 1
    BACK_COUNT=$((BACK_COUNT + 1))
    (( BACK_COUNT < MAX_BACK_ATTEMPTS )) || exit 1
    BACK_COUNT=$((BACK_COUNT + 1))
    (( BACK_COUNT == MAX_BACK_ATTEMPTS )) || exit 1
    (( BACK_COUNT < MAX_BACK_ATTEMPTS )) && exit 1 || true
  )
  printf 'SELF_TEST::PASS\n'
}

parse_args "$@"
if [[ "$SELF_TEST" == true ]]; then
  validate_serial_value
  require_public_oauth_client_id
  self_test
  exit 0
fi

validate_serial_value
validate_bounds
require_public_oauth_client_id
[[ "$CONFIRM_CANCEL" == 'I_UNDERSTAND_SANDBOX_CANCEL' ]] ||
  fail_configuration 'explicit --confirm-cancel acknowledgement is required'
[[ -x "$OPERATOR_SCRIPT" ]] || fail_configuration 'cancel operator is missing or not executable'
[[ -f "$PROJECT_ROOT/pubspec.yaml" && -f "$PROJECT_ROOT/$INTEGRATION_TARGET" &&
  -f "$PROJECT_ROOT/$DRIVER_TARGET" ]] || fail_configuration 'focused Flutter target is missing'

resolve_commands
create_safe_artifact_dir
FLUTTER_LOG_PATH="$ARTIFACT_DIR/flutter-drive.log"
OPERATOR_LOG_PATH="$ARTIFACT_DIR/cancel-operator.log"
: >"$FLUTTER_LOG_PATH"
trap cleanup EXIT

git_status="$(git -C "$PROJECT_ROOT" status --porcelain=v1 --untracked-files=all --ignore-submodules=none)" ||
  fail_configuration 'Flutter checkout status is unavailable'
[[ -z "$git_status" ]] || fail_configuration 'Flutter checkout must be clean for focused acceptance'

adb_get_state

audit 'START'
audit 'SINGLE_DEVICE'
audit 'NO_SMS'
audit 'NO_TENCENT'
audit 'CANCEL_ONLY'
wallet_health_preflight
prepare_android_host
start_cancel_operator
run_flutter_target

set +e
wait "$OPERATOR_PID"
OPERATOR_STATUS=$?
set -e
OPERATOR_PID=''

if [[ "$FLUTTER_STATUS" -ne 0 ]]; then
  RUN_RESULT='FAIL'
  FAIL_REASON='focused_flutter_target_failed'
elif [[ "$OPERATOR_STATUS" -ne 0 ]]; then
  RUN_RESULT='FAIL'
  FAIL_REASON='cancel_operator_failed'
elif [[ "$(grep -Fxc "$EXPECTED_NATIVE_MARKER" "$FLUTTER_LOG_PATH" 2>/dev/null || true)" -ne 1 ||
  "$(grep -Fxc "$EXPECTED_BRIDGE_MARKER" "$FLUTTER_LOG_PATH" 2>/dev/null || true)" -ne 1 ]]; then
  RUN_RESULT='FAIL'
  FAIL_REASON='accepted_marker_pair_missing_or_duplicated'
elif grep -Eq 'M5_ALIPAY_NATIVE_RESULT::sdkCompleted=0::resultStatus=none|M5_ALIPAY_NATIVE_RESULT::sdkCompleted=1::' \
  "$FLUTTER_LOG_PATH"; then
  RUN_RESULT='FAIL'
  FAIL_REASON='non_cancel_or_incomplete_native_result'
elif [[ "$(grep -Fxc 'M5_ALIPAY_FOCUSED::catalog::PASS' "$FLUTTER_LOG_PATH" 2>/dev/null || true)" -ne 1 ||
  "$(grep -Fxc 'M5_ALIPAY_FOCUSED::order::PASS' "$FLUTTER_LOG_PATH" 2>/dev/null || true)" -ne 1 ||
  "$(grep -Fxc 'M5_ALIPAY_FOCUSED::native_launcher::START' "$FLUTTER_LOG_PATH" 2>/dev/null || true)" -ne 1 ||
  "$(grep -Fxc 'M5_ALIPAY_FOCUSED::native_launcher::PASS' "$FLUTTER_LOG_PATH" 2>/dev/null || true)" -ne 1 ||
  "$(grep -Fxc 'M5_ALIPAY_FOCUSED::query_reconcile::PASS' "$FLUTTER_LOG_PATH" 2>/dev/null || true)" -ne 1 ||
  "$(grep -Fxc 'M5_ALIPAY_FOCUSED::complete::PASS' "$FLUTTER_LOG_PATH" 2>/dev/null || true)" -ne 1 ]]; then
  RUN_RESULT='FAIL'
  FAIL_REASON='focused_flow_marker_missing'
elif grep -Fq 'M5_ALIPAY_FOCUSED::complete::FAIL' "$FLUTTER_LOG_PATH"; then
  RUN_RESULT='FAIL'
  FAIL_REASON='focused_flow_reported_failure'
elif ! safe_artifact_scan; then
  RUN_RESULT='FAIL'
  FAIL_REASON='artifact_secret_scan_failed'
  printf 'status=FAIL\n' >"$ARTIFACT_DIR/artifact-secret-scan.txt"
else
  RUN_RESULT='PASS'
  FAIL_REASON='none'
  printf 'status=PASS\n' >"$ARTIFACT_DIR/artifact-secret-scan.txt"
fi

if [[ "$RUN_RESULT" == 'PASS' ]]; then
  audit 'PASS'
  exit 0
fi
audit "FAIL::$FAIL_REASON"
exit 1
