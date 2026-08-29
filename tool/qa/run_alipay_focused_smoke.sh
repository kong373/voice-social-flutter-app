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
readonly EXPECTED_LAUNCH_MARKER='M5_ALIPAY_FOCUSED::native_launcher::START'
readonly DEFAULT_PRE_LAUNCH_TIMEOUT_SECONDS=300
readonly DEFAULT_POST_LAUNCH_TIMEOUT_SECONDS=180
readonly FLUTTER_REAP_TIMEOUT_SECONDS=10
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
PRE_LAUNCH_TIMEOUT_SECONDS="$DEFAULT_PRE_LAUNCH_TIMEOUT_SECONDS"
POST_LAUNCH_TIMEOUT_SECONDS="$DEFAULT_POST_LAUNCH_TIMEOUT_SECONDS"
FLUTTER_BIN=''
ADB_BIN=''
ARTIFACT_DIR=''
ANDROID_HOST_DIR=''
FLUTTER_LOG_PATH=''
FLUTTER_STATUS_PATH=''
OPERATOR_LOG_PATH=''
OPERATOR_PID=''
OPERATOR_PID_PATH=''
OPERATOR_PID_START_TIME=''
OPERATOR_PID_GROUP=''
OPERATOR_PID_REAPED=false
FLUTTER_PID=''
FLUTTER_PID_START_TIME=''
FLUTTER_PID_GROUP=''
FLUTTER_PID_REAPED=false
FLUTTER_TOOL_PID=''
FLUTTER_TOOL_START_TIME=''
FLUTTER_TOOL_GROUP=''
FLUTTER_TOOL_PID_PATH=''
WALLET_UI_DUMP_PATH=''
WALLET_UI_DUMP_ACTIVE=false
LOG_BASELINE_BYTES=0
LAUNCH_MARKER_BASELINE_BYTES=0
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
  --post-launch-timeout SEC   bounded wait after native launcher start (default: 180)
  --poll-interval SEC         poll delay (0 is allowed for self-tests)
  --stable-polls COUNT        consecutive cashier observations (default: 3)
  --self-test                 run offline marker/device/BACK contract checks
  --help                      show this help

The live run uses only BACK to cancel the sandbox cashier. It accepts exactly
sdkCompleted=0 + resultStatus=6001 + pay_task_returned, then requires the
first-party query/reconcile path to report cancellation. A missing, stale,
duplicate, timeout, non-target, or otherwise contradictory marker fails closed.
The Flutter build/installation phase has its own bounded 300 second wait for
the native-launcher START marker. The 60 second cashier timeout begins only
after that marker is observed.

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
      --post-launch-timeout)
        (($# >= 2)) || fail_configuration 'post-launch timeout is missing'
        POST_LAUNCH_TIMEOUT_SECONDS="$2"
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
  require_integer post-launch-timeout "$POST_LAUNCH_TIMEOUT_SECONDS"
  require_integer poll-interval "$POLL_INTERVAL_SECONDS"
  require_integer stable-polls "$STABLE_POLLS"
  (( STABLE_POLLS >= 2 )) || fail_configuration 'stable poll count must be at least 2'
}

resolve_commands() {
  ADB_BIN="$(command -v adb || true)"
  FLUTTER_BIN="$(command -v flutter || true)"
  [[ -n "$ADB_BIN" && -x "$ADB_BIN" ]] || fail_configuration 'adb executable is unavailable'
  [[ -n "$FLUTTER_BIN" && -x "$FLUTTER_BIN" ]] || fail_configuration 'Flutter executable is unavailable'
  for command_name in python3 git tar mktemp shasum awk grep wc head tail find tr ps; do
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
    if node.attrib.get('visible-to-user') != 'true':
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
  "$ADB_BIN" -s "$SERIAL_VALUE" shell rm -f "$DEVICE_WALLET_UI_DUMP_PATH" \
    >/dev/null 2>&1 || fail_device 'stale Alipay sandbox wallet UI dump could not be removed'
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

force_stop_flutter_app() {
  # keep-app-running preserves the installed package and its data, but the
  # next drive invocation must not inherit an already-running VM service.
  # force-stop only terminates this app process; it does not clear data or
  # uninstall the package.
  "$ADB_BIN" -s "$SERIAL_VALUE" shell am force-stop "$APP_PACKAGE" \
    >/dev/null 2>&1 || fail_device 'Flutter app process could not be stopped'
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

launch_marker_count_from_log_suffix() {
  local current_bytes=''
  local marker_count=''
  current_bytes="$(wc -c <"$FLUTTER_LOG_PATH" 2>/dev/null | tr -d '[:space:]')" || {
    printf 'INVALID'
    return 0
  }
  [[ "$current_bytes" =~ ^[0-9]+$ &&
    "$current_bytes" -ge "$LAUNCH_MARKER_BASELINE_BYTES" ]] || {
    printf 'INVALID'
    return 0
  }
  marker_count="$(tail -c +$((LAUNCH_MARKER_BASELINE_BYTES + 1)) \
    "$FLUTTER_LOG_PATH" 2>/dev/null |
    grep -Fxc "$EXPECTED_LAUNCH_MARKER" || true)"
  [[ "$marker_count" =~ ^[0-9]+$ ]] || {
    printf 'INVALID'
    return 0
  }
  if (( marker_count == 0 )); then
    printf 'MISSING'
  elif (( marker_count == 1 )); then
    printf 'PRESENT'
  else
    printf 'AMBIGUOUS'
  fi
}

record_launch_marker_baseline() {
  LAUNCH_MARKER_BASELINE_BYTES="$(wc -c <"$FLUTTER_LOG_PATH" 2>/dev/null |
    tr -d '[:space:]')" || return 1
  [[ "$LAUNCH_MARKER_BASELINE_BYTES" =~ ^[0-9]+$ ]] || return 1
  [[ "$(launch_marker_count_from_log_suffix)" == 'MISSING' ]]
}

wait_for_native_launcher_start() {
  local deadline=$((SECONDS + PRE_LAUNCH_TIMEOUT_SECONDS))
  local state=''
  while (( SECONDS <= deadline )); do
    if [[ -z "$FLUTTER_TOOL_PID" ]]; then
      record_flutter_tool_identity || true
    fi
    state="$(launch_marker_count_from_log_suffix)"
    case "$state" in
      PRESENT)
        audit 'NATIVE_LAUNCHER_START_PASS'
        return 0
        ;;
      AMBIGUOUS|INVALID)
        audit "NATIVE_LAUNCHER_START_FAIL::$state"
        return 1
        ;;
      MISSING)
        ;;
    esac
    # A completed Flutter target without its launch marker cannot become
    # cancellable; fail promptly instead of consuming the full pre-launch
    # bound after a catalog/order failure.
    if [[ -n "$FLUTTER_STATUS_PATH" && -s "$FLUTTER_STATUS_PATH" ]]; then
      audit 'NATIVE_LAUNCHER_START_FAIL::FLUTTER_TARGET_ENDED'
      return 1
    fi
    pause_between_polls
  done
  audit 'NATIVE_LAUNCHER_START_TIMEOUT'
  return 1
}

process_start_time() {
  local pid="$1" start=''
  [[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 0 ]] || return 1
  start="$(ps -o lstart= -p "$pid" 2>/dev/null | tr -d '\r')" || return 1
  start="${start#"${start%%[![:space:]]*}"}"
  start="${start%"${start##*[![:space:]]}"}"
  [[ -n "$start" ]] && printf '%s\n' "$start"
}

process_is_alive() {
  local pid="$1" state=''
  [[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 0 ]] || return 1
  state="$(ps -o stat= -p "$pid" 2>/dev/null | tr -d '[:space:]')" || return 1
  [[ -n "$state" && "$state" != Z* ]]
}

process_exists() {
  local pid="$1" observed_pid=''
  [[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 0 ]] || return 1
  observed_pid="$(ps -o pid= -p "$pid" 2>/dev/null | tr -d '[:space:]')" || return 1
  [[ "$observed_pid" == "$pid" ]]
}

flutter_process_is_alive() { process_is_alive "$1"; }

flutter_process_group_id() {
  local pid="$1" group_id=''
  [[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 0 ]] || return 1
  group_id="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d '[:space:]')" || return 1
  [[ "$group_id" =~ ^[0-9]+$ ]] && printf '%s\n' "$group_id"
}

process_identity_is_current() {
  local pid="$1" expected_start="$2" observed_start=''
  [[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 0 && -n "$expected_start" ]] || return 1
  observed_start="$(process_start_time "$pid" || true)"
  [[ -n "$observed_start" && "$observed_start" == "$expected_start" ]]
}

process_needs_reap() {
  local pid="$1" expected_start="$2"
  if process_identity_is_current "$pid" "$expected_start"; then
    process_is_alive "$pid"
  else
    process_exists "$pid"
  fi
}

capture_process_identity() {
  local pid="$1"
  CAPTURED_PROCESS_START_TIME="$(process_start_time "$pid" || true)"
  CAPTURED_PROCESS_GROUP_ID="$(flutter_process_group_id "$pid" || true)"
  [[ -n "$CAPTURED_PROCESS_START_TIME" &&
    "$CAPTURED_PROCESS_GROUP_ID" =~ ^[0-9]+$ ]]
}

flutter_tool_pid_from_file() {
  local candidate=''
  [[ -n "$FLUTTER_TOOL_PID_PATH" && -f "$FLUTTER_TOOL_PID_PATH" &&
    ! -L "$FLUTTER_TOOL_PID_PATH" ]] || return 0
  candidate="$(tr -d '[:space:]' <"$FLUTTER_TOOL_PID_PATH" 2>/dev/null || true)"
  [[ "$candidate" =~ ^[0-9]+$ && "$candidate" -gt 0 ]] && printf '%s\n' "$candidate"
}

record_flutter_tool_identity() {
  local candidate=''
  candidate="$(flutter_tool_pid_from_file)" || return 1
  [[ "$candidate" =~ ^[0-9]+$ && "$candidate" -gt 0 ]] || return 1
  capture_process_identity "$candidate" || return 1
  FLUTTER_TOOL_PID="$candidate"
  FLUTTER_TOOL_START_TIME="$CAPTURED_PROCESS_START_TIME"
  FLUTTER_TOOL_GROUP="$CAPTURED_PROCESS_GROUP_ID"
}

record_operator_identity() {
  local candidate=''
  [[ -n "$OPERATOR_PID_PATH" && -f "$OPERATOR_PID_PATH" &&
    ! -L "$OPERATOR_PID_PATH" ]] || return 1
  candidate="$(tr -d '[:space:]' <"$OPERATOR_PID_PATH" 2>/dev/null || true)"
  [[ "$candidate" =~ ^[0-9]+$ && "$candidate" == "$OPERATOR_PID" ]] || return 1
  capture_process_identity "$candidate" || return 1
  OPERATOR_PID_START_TIME="$CAPTURED_PROCESS_START_TIME"
  OPERATOR_PID_GROUP="$CAPTURED_PROCESS_GROUP_ID"
}

signal_owned_process() {
  local signal="$1" pid="$2" expected_start="$3"
  process_identity_is_current "$pid" "$expected_start" || return 0
  kill -"$signal" "$pid" 2>/dev/null || true
}

signal_owned_process_group() {
  local signal="$1" pid="$2" expected_start="$3" expected_group="$4"
  local protected_pid="$5" protected_group="$6" current_group=''
  process_identity_is_current "$pid" "$expected_start" || return 0
  current_group="$(flutter_process_group_id "$pid" || true)"
  if [[ "$expected_group" =~ ^[0-9]+$ && "$expected_group" == "$pid" &&
    "$current_group" == "$expected_group" && "$expected_group" != '1' &&
    "$expected_group" != "$$" && "$expected_group" != "$protected_pid" &&
    "$expected_group" != "$protected_group" ]]; then
    kill -"$signal" "-$expected_group" 2>/dev/null || true
  else
    signal_owned_process "$signal" "$pid" "$expected_start"
  fi
}

signal_flutter_target() {
  local signal="$1" wrapper_pid="$2" tool_pid="$3" expected_group="$4" wrapper_group="$5"
  signal_owned_process_group "$signal" "$tool_pid" "$FLUTTER_TOOL_START_TIME" \
    "$expected_group" "$wrapper_pid" "$wrapper_group"
  signal_owned_process "$signal" "$wrapper_pid" "$FLUTTER_PID_START_TIME"
}

signal_cancel_operator() {
  signal_owned_process_group "$1" "$OPERATOR_PID" "$OPERATOR_PID_START_TIME" \
    "$OPERATOR_PID_GROUP" "$$" ''
}

terminate_flutter_target() {
  local wrapper_pid="$FLUTTER_PID" tool_pid="$FLUTTER_TOOL_PID"
  local deadline=0 wrapper_alive=false tool_alive=false
  [[ "$wrapper_pid" =~ ^[0-9]+$ && "$wrapper_pid" -gt 0 ]] || {
    FLUTTER_PID=''
    return 0
  }
  signal_flutter_target TERM "$wrapper_pid" "$tool_pid" "$FLUTTER_TOOL_GROUP" "$FLUTTER_PID_GROUP"
  deadline=$((SECONDS + FLUTTER_REAP_TIMEOUT_SECONDS))
  while (( SECONDS <= deadline )); do
    wrapper_alive=false; tool_alive=false
    process_needs_reap "$wrapper_pid" "$FLUTTER_PID_START_TIME" && wrapper_alive=true
    process_needs_reap "$tool_pid" "$FLUTTER_TOOL_START_TIME" && tool_alive=true
    [[ "$wrapper_alive" == false && "$tool_alive" == false ]] && break
    sleep 1
  done
  if [[ "$wrapper_alive" == true || "$tool_alive" == true ]]; then
    signal_flutter_target KILL "$wrapper_pid" "$tool_pid" "$FLUTTER_TOOL_GROUP" "$FLUTTER_PID_GROUP"
    deadline=$((SECONDS + 2))
    while (( SECONDS <= deadline )); do
      wrapper_alive=false; tool_alive=false
      process_needs_reap "$wrapper_pid" "$FLUTTER_PID_START_TIME" && wrapper_alive=true
      process_needs_reap "$tool_pid" "$FLUTTER_TOOL_START_TIME" && tool_alive=true
      [[ "$wrapper_alive" == false && "$tool_alive" == false ]] && break
      sleep 1
    done
  fi
  if process_identity_is_current "$wrapper_pid" "$FLUTTER_PID_START_TIME" &&
    ! process_is_alive "$wrapper_pid"; then
    wait "$wrapper_pid" 2>/dev/null || true
  fi
  if process_identity_is_current "$tool_pid" "$FLUTTER_TOOL_START_TIME" &&
    ! process_is_alive "$tool_pid"; then
    wait "$tool_pid" 2>/dev/null || true
  fi
  FLUTTER_PID=''; FLUTTER_PID_START_TIME=''; FLUTTER_PID_GROUP=''
  FLUTTER_TOOL_PID=''; FLUTTER_TOOL_START_TIME=''; FLUTTER_TOOL_GROUP=''
}

terminate_cancel_operator() {
  local pid="$OPERATOR_PID" deadline=0 alive=false
  [[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 0 ]] || { OPERATOR_PID=''; return 0; }
  signal_cancel_operator TERM
  deadline=$((SECONDS + FLUTTER_REAP_TIMEOUT_SECONDS))
  while (( SECONDS <= deadline )); do
    alive=false; process_needs_reap "$pid" "$OPERATOR_PID_START_TIME" && alive=true
    [[ "$alive" == false ]] && break
    sleep 1
  done
  if [[ "$alive" == true ]]; then
    signal_cancel_operator KILL
    deadline=$((SECONDS + 2))
    while (( SECONDS <= deadline )); do
      alive=false; process_needs_reap "$pid" "$OPERATOR_PID_START_TIME" && alive=true
      [[ "$alive" == false ]] && break
      sleep 1
    done
  fi
  if process_identity_is_current "$pid" "$OPERATOR_PID_START_TIME" &&
    ! process_is_alive "$pid"; then
    wait "$pid" 2>/dev/null || true
  fi
  OPERATOR_PID=''; OPERATOR_PID_START_TIME=''; OPERATOR_PID_GROUP=''
}

watchdog_pause() {
  local remaining=$(($1 - SECONDS)) interval="$POLL_INTERVAL_SECONDS"
  (( remaining > 0 )) || return 0
  (( interval > remaining )) && interval="$remaining"
  (( interval > 0 )) && sleep "$interval"
}

reap_process_if_done() {
  local pid="$1" expected_start="$2" wait_status=0
  if process_needs_reap "$pid" "$expected_start"; then return 1; fi
  set +e; wait "$pid" 2>/dev/null; wait_status=$?; set -e
  REAP_STATUS="$wait_status"
}

reap_flutter_target_if_done() {
  [[ "$FLUTTER_PID_REAPED" == true ]] && return 0
  [[ "$FLUTTER_PID" =~ ^[0-9]+$ && "$FLUTTER_PID" -gt 0 ]] || {
    FLUTTER_PID_REAPED=true; return 0; }
  reap_process_if_done "$FLUTTER_PID" "$FLUTTER_PID_START_TIME" || return 1
  FLUTTER_STATUS="$REAP_STATUS"; FLUTTER_PID=''; FLUTTER_PID_REAPED=true
}

reap_cancel_operator_if_done() {
  [[ "$OPERATOR_PID_REAPED" == true ]] && return 0
  [[ "$OPERATOR_PID" =~ ^[0-9]+$ && "$OPERATOR_PID" -gt 0 ]] || {
    OPERATOR_PID_REAPED=true; return 0; }
  reap_process_if_done "$OPERATOR_PID" "$OPERATOR_PID_START_TIME" || return 1
  OPERATOR_STATUS="$REAP_STATUS"; OPERATOR_PID=''; OPERATOR_PID_REAPED=true
}

wait_for_post_launch_completion() {
  local deadline=$((SECONDS + POST_LAUNCH_TIMEOUT_SECONDS))
  while :; do
    reap_flutter_target_if_done || true; reap_cancel_operator_if_done || true
    [[ "$FLUTTER_PID_REAPED" == true && "$OPERATOR_PID_REAPED" == true ]] && return 0
    (( SECONDS >= deadline )) && break
    watchdog_pause "$deadline"
  done
  reap_flutter_target_if_done || true; reap_cancel_operator_if_done || true
  [[ "$FLUTTER_PID_REAPED" == true && "$OPERATOR_PID_REAPED" == true ]]
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
    # Flutter drive otherwise stops and uninstalls the package in
    # DriverService.stop(), which erases the persisted Secure Storage
    # session. Keep the installed app/data on both pass and test failure.
    env -u QA_OAUTH_CLIENT_ID -u QA_OAUTH_CLIENT_SECRET -u OAUTH_CLIENT_SECRET \
      python3 -c '
import os
import sys

pid_path, command, *args = sys.argv[1:]
try:
    os.setsid()
except OSError:
    # The shell fallback remains safe because the reaper verifies the
    # process start time before signalling this PID directly.
    pass
with open(pid_path, "w", encoding="ascii") as stream:
    stream.write(str(os.getpid()))
    stream.flush()
os.execv(command, [command, *args])
' \
      "$FLUTTER_TOOL_PID_PATH" "$FLUTTER_BIN" drive --no-pub \
      --keep-app-running \
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
  printf '%s\n' "$FLUTTER_STATUS" >"$FLUTTER_STATUS_PATH"
  set -e
  return "$FLUTTER_STATUS"
}

start_cancel_operator() {
  local deadline=0
  env -u QA_OAUTH_CLIENT_ID -u QA_OAUTH_CLIENT_SECRET -u OAUTH_CLIENT_SECRET \
    ANDROID_SERIAL="$SERIAL_VALUE" python3 -c '
import os
import sys

pid_path, command, *args = sys.argv[1:]
try:
    os.setsid()
except OSError:
    pass
with open(pid_path, "w", encoding="ascii") as stream:
    stream.write(str(os.getpid()))
    stream.flush()
os.execv(command, [command, *args])
' \
    "$OPERATOR_PID_PATH" "$OPERATOR_SCRIPT" --adb "$ADB_BIN" \
    --target-serial "$SERIAL_VALUE" --flutter-log "$FLUTTER_LOG_PATH" \
    --target-timeout "$CASHIER_TIMEOUT_SECONDS" \
    --after-back-timeout "$AFTER_BACK_TIMEOUT_SECONDS" \
    --marker-timeout "$MARKER_TIMEOUT_SECONDS" \
    --poll-interval "$POLL_INTERVAL_SECONDS" \
    --stable-polls "$STABLE_POLLS" \
    >"$OPERATOR_LOG_PATH" 2>&1 &
  OPERATOR_PID=$!
  OPERATOR_PID_REAPED=false
  deadline=$((SECONDS + 2))
  while (( SECONDS <= deadline )); do
    if record_operator_identity; then
      return 0
    fi
    process_is_alive "$OPERATOR_PID" || break
    sleep 1
  done
  if [[ -z "$OPERATOR_PID_START_TIME" ]] &&
    capture_process_identity "$OPERATOR_PID"; then
    OPERATOR_PID_START_TIME="$CAPTURED_PROCESS_START_TIME"
    OPERATOR_PID_GROUP="$CAPTURED_PROCESS_GROUP_ID"
  fi
  return 1
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

exact_marker_count() {
  local marker="$1"
  if [[ -z "$FLUTTER_LOG_PATH" || ! -f "$FLUTTER_LOG_PATH" ||
    -L "$FLUTTER_LOG_PATH" ]]; then
    printf '0'
    return 0
  fi
  local count=''
  count="$(grep -Fxc -- "$marker" "$FLUTTER_LOG_PATH" 2>/dev/null || true)"
  [[ "$count" =~ ^[0-9]+$ ]] || count=0
  printf '%s' "$count"
}

summary_pass_status() {
  local marker="$1"
  [[ "$(exact_marker_count "$marker")" == '1' ]] &&
    printf 'PASS' || printf 'NOT_PROVEN'
}

summary_native_launcher_status() {
  local start_count pass_count
  start_count="$(exact_marker_count 'M5_ALIPAY_FOCUSED::native_launcher::START')"
  pass_count="$(exact_marker_count 'M5_ALIPAY_FOCUSED::native_launcher::PASS')"
  if [[ "$start_count" == '1' && "$pass_count" == '1' ]]; then
    printf 'PASS'
  elif [[ "$start_count" == '1' && "$pass_count" == '0' ]]; then
    printf 'STARTED'
  else
    printf 'NOT_PROVEN'
  fi
}

summary_native_result_status() {
  if [[ -z "$FLUTTER_LOG_PATH" || ! -f "$FLUTTER_LOG_PATH" ||
    -L "$FLUTTER_LOG_PATH" ]]; then
    printf 'NOT_ACCEPTED'
    return 0
  fi
  local native_valid_count=0
  local bridge_valid_count=0
  local invalid_count=0
  local marker_kind=''
  while IFS= read -r marker_kind; do
    case "$marker_kind" in
      NATIVE_VALID) native_valid_count=$((native_valid_count + 1)) ;;
      BRIDGE_VALID) bridge_valid_count=$((bridge_valid_count + 1)) ;;
      NATIVE_INVALID|BRIDGE_INVALID) invalid_count=$((invalid_count + 1)) ;;
    esac
  done < <(scan_marker_stream <"$FLUTTER_LOG_PATH" 2>/dev/null || true)
  if (( native_valid_count == 1 && bridge_valid_count == 1 &&
    invalid_count == 0 )); then
    printf 'ACCEPTED'
  else
    printf 'NOT_ACCEPTED'
  fi
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
      printf 'wallet_health=NOT_PROVEN\ncatalog=%s\norder=%s\nnative_launcher=%s\n' \
        "$(summary_pass_status 'M5_ALIPAY_FOCUSED::catalog::PASS')" \
        "$(summary_pass_status 'M5_ALIPAY_FOCUSED::order::PASS')" \
        "$(summary_native_launcher_status)"
      printf 'native_result=%s\nquery_reconcile=%s\n' \
        "$(summary_native_result_status)" \
        "$(summary_pass_status 'M5_ALIPAY_FOCUSED::query_reconcile::PASS')"
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
    terminate_cancel_operator
  fi
  if [[ -n "$FLUTTER_PID" ]]; then
    terminate_flutter_target
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

    local fake_adb fake_adb_calls forbidden_verb
    fake_adb="$root/fake-adb"
    fake_adb_calls="$root/fake-adb.calls"
    : >"$fake_adb_calls"
    cat >"$fake_adb" <<'FAKE_ADB'
#!/usr/bin/env bash
set -Eeuo pipefail
: "${FAKE_ADB_CALLS:?}"
printf '%s\n' "$*" >>"$FAKE_ADB_CALLS"
for forbidden_verb in clear uninstall; do
  case " $* " in
    *" pm ${forbidden_verb} "*) exit 92 ;;
  esac
done
[[ "$*" == '-s emulator-5554 shell am force-stop com.kong373.voice_social_app' ]]
FAKE_ADB
    chmod 700 "$fake_adb"
    ADB_BIN="$fake_adb"
    SERIAL_VALUE="$DEFAULT_SERIAL"
    FAKE_ADB_CALLS="$fake_adb_calls"
    export FAKE_ADB_CALLS
    force_stop_flutter_app || exit 1
    [[ "$(wc -l <"$fake_adb_calls" | tr -d '[:space:]')" == '1' ]] || exit 1
    [[ "$(head -n 1 "$fake_adb_calls")" == \
      '-s emulator-5554 shell am force-stop com.kong373.voice_social_app' ]] || exit 1
    audit 'FORCE_STOP_PASS'

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

    : >"$FLUTTER_LOG_PATH"
    PRE_LAUNCH_TIMEOUT_SECONDS=2
    POLL_INTERVAL_SECONDS=0
    record_launch_marker_baseline || exit 1
    (
      sleep 0.2
      printf '%s\n' "$EXPECTED_LAUNCH_MARKER" >>"$FLUTTER_LOG_PATH"
    ) &
    local launch_marker_writer_pid=$!
    wait_for_native_launcher_start || exit 1
    wait "$launch_marker_writer_pid" || exit 1

    : >"$FLUTTER_LOG_PATH"
    record_launch_marker_baseline || exit 1
    PRE_LAUNCH_TIMEOUT_SECONDS=0
    wait_for_native_launcher_start && exit 1

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
      printf '<hierarchy><node package="com.eg.android.AlipayGphoneRC" text="Scan" /><node package="com.eg.android.AlipayGphoneRC" text="Pay" /><node package="com.eg.android.AlipayGphoneRC" text="Home" /><node package="com.eg.android.AlipayGphoneRC" text="%s" enabled="true" visible-to-user="true" bounds="[64,1279][1016,1454]" /></hierarchy>\n' "$degraded_text" >"$WALLET_UI_DUMP_PATH"
      wallet_ui_is_healthy || exit 1
      printf '<hierarchy><node package="com.eg.android.AlipayGphoneRC" text="Scan" /><node package="com.eg.android.AlipayGphoneRC" text="Pay" /><node package="com.eg.android.AlipayGphoneRC" text="Home" /><node package="com.eg.android.AlipayGphoneRC" text="%s" enabled="true" visible-to-user="true" bounds="[64,300][1016,360]" /></hierarchy>\n' "$degraded_text" >"$WALLET_UI_DUMP_PATH"
      wallet_ui_is_healthy && exit 1
      printf '<hierarchy><node package="com.eg.android.AlipayGphoneRC" text="Scan" /><node package="com.eg.android.AlipayGphoneRC" text="Pay" /><node package="com.eg.android.AlipayGphoneRC" text="Home" /><node package="com.eg.android.AlipayGphoneRC" text="%s" enabled="true" visible-to-user="true" /></hierarchy>\n' "$degraded_text" >"$WALLET_UI_DUMP_PATH"
      wallet_ui_is_healthy && exit 1
      printf '<hierarchy><node package="com.eg.android.AlipayGphoneRC" text="Scan" /><node package="com.eg.android.AlipayGphoneRC" text="Pay" /><node package="com.eg.android.AlipayGphoneRC" text="Home" /><node package="com.other.wallet" text="%s" enabled="true" visible-to-user="true" bounds="[64,1279][1016,1454]" /></hierarchy>\n' "$degraded_text" >"$WALLET_UI_DUMP_PATH"
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
    audit 'WALLET_VISIBILITY_PASS'

    local watchdog_flutter_pid watchdog_tool_pid watchdog_operator_pid
    local watchdog_flutter_path watchdog_operator_path watchdog_deadline
    watchdog_flutter_path="$root/watchdog-flutter.pid"
    watchdog_operator_path="$root/watchdog-operator.pid"
    : >"$watchdog_flutter_path"
    : >"$watchdog_operator_path"
    spawn_watchdog_fixture() {
      python3 -c 'import os,sys,time; os.setsid(); open(sys.argv[1], "w").write(str(os.getpid())); time.sleep(30)' "$1" &
      WATCHDOG_LAST_PID=$!
    }
    spawn_watchdog_fixture "$watchdog_flutter_path"
    watchdog_flutter_pid="$WATCHDOG_LAST_PID"
    spawn_watchdog_fixture "$watchdog_flutter_path"
    watchdog_tool_pid="$WATCHDOG_LAST_PID"
    spawn_watchdog_fixture "$watchdog_operator_path"
    watchdog_operator_pid="$WATCHDOG_LAST_PID"
    watchdog_deadline=$((SECONDS + 2))
    while [[ ! -s "$watchdog_flutter_path" || ! -s "$watchdog_operator_path" ]] &&
      (( SECONDS <= watchdog_deadline )); do
      sleep 0.1
    done
    [[ -s "$watchdog_flutter_path" && -s "$watchdog_operator_path" ]] || exit 1

    FLUTTER_PID="$watchdog_flutter_pid"
    FLUTTER_PID_REAPED=false
    capture_process_identity "$FLUTTER_PID" || exit 1
    FLUTTER_PID_START_TIME="$CAPTURED_PROCESS_START_TIME"
    FLUTTER_PID_GROUP="$CAPTURED_PROCESS_GROUP_ID"
    FLUTTER_TOOL_PID="$watchdog_tool_pid"
    capture_process_identity "$FLUTTER_TOOL_PID" || exit 1
    [[ "$CAPTURED_PROCESS_GROUP_ID" == "$FLUTTER_TOOL_PID" ]] || exit 1
    FLUTTER_TOOL_START_TIME="$CAPTURED_PROCESS_START_TIME"
    FLUTTER_TOOL_GROUP="$CAPTURED_PROCESS_GROUP_ID"
    OPERATOR_PID="$watchdog_operator_pid"
    OPERATOR_PID_REAPED=false
    capture_process_identity "$OPERATOR_PID" || exit 1
    [[ "$CAPTURED_PROCESS_GROUP_ID" == "$OPERATOR_PID" ]] || exit 1
    OPERATOR_PID_START_TIME="$CAPTURED_PROCESS_START_TIME"
    OPERATOR_PID_GROUP="$CAPTURED_PROCESS_GROUP_ID"
    OPERATOR_PID_PATH="$watchdog_operator_path"
    POST_LAUNCH_TIMEOUT_SECONDS=0
    POLL_INTERVAL_SECONDS=0
    wait_for_post_launch_completion && exit 1
    FLUTTER_STATUS=124
    OPERATOR_STATUS=124
    terminate_cancel_operator
    terminate_flutter_target
    wait "$watchdog_tool_pid" 2>/dev/null || true
    process_is_alive "$watchdog_flutter_pid" && exit 1 || true
    process_is_alive "$watchdog_tool_pid" && exit 1 || true
    process_is_alive "$watchdog_operator_pid" && exit 1 || true
    audit 'POST_LAUNCH_WATCHDOG_PASS'

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

    local summary_dir summary_file summary_log
    summary_dir="$root/summary-artifact"
    summary_file="$summary_dir/summary.txt"
    summary_log="$root/summary-log"
    mkdir -m 700 "$summary_dir"
    ARTIFACT_DIR="$summary_dir"
    FLUTTER_LOG_PATH="$summary_log"
    SERIAL_VALUE="$DEFAULT_SERIAL"
    FLUTTER_STATUS=1
    OPERATOR_STATUS=65
    RUN_RESULT='FAIL'
    FAIL_REASON='focused_flow_reported_failure'
    printf '%s\n' \
      'M5_ALIPAY_FOCUSED::catalog::PASS' \
      'M5_ALIPAY_FOCUSED::order::PASS' \
      'M5_ALIPAY_FOCUSED::native_launcher::START' \
      "$EXPECTED_NATIVE_MARKER" \
      "$EXPECTED_BRIDGE_MARKER" \
      'M5_ALIPAY_FOCUSED::complete::FAIL' >"$summary_log"
    write_summary
    [[ -f "$summary_file" ]] || exit 1
    grep -Fqx 'conclusion=FAIL' "$summary_file" || exit 1
    grep -Fqx 'reason=focused_flow_reported_failure' "$summary_file" || exit 1
    grep -Fqx 'catalog=PASS' "$summary_file" || exit 1
    grep -Fqx 'order=PASS' "$summary_file" || exit 1
    grep -Fqx 'native_launcher=STARTED' "$summary_file" || exit 1
    grep -Fqx 'native_result=ACCEPTED' "$summary_file" || exit 1
    grep -Fqx 'query_reconcile=NOT_PROVEN' "$summary_file" || exit 1
    grep -Fqi 'orderStr' "$summary_file" && exit 1 || true
    grep -Fqi 'secret' "$summary_file" && exit 1 || true
    printf '%s\n' \
      'SUMMARY_PARTIAL_EVIDENCE::conclusion=FAIL::catalog=PASS::order=PASS::native_launcher=STARTED::native_result=ACCEPTED::query_reconcile=NOT_PROVEN'

    summary_dir="$root/summary-missing-native-artifact"
    summary_file="$summary_dir/summary.txt"
    summary_log="$root/summary-missing-native-log"
    mkdir -m 700 "$summary_dir"
    ARTIFACT_DIR="$summary_dir"
    FLUTTER_LOG_PATH="$summary_log"
    RUN_RESULT='FAIL'
    FAIL_REASON='accepted_marker_pair_missing_or_duplicated'
    printf '%s\n' \
      'M5_ALIPAY_FOCUSED::catalog::PASS' \
      'M5_ALIPAY_FOCUSED::order::PASS' \
      'M5_ALIPAY_FOCUSED::native_launcher::START' >"$summary_log"
    write_summary
    grep -Fqx 'conclusion=FAIL' "$summary_file" || exit 1
    grep -Fqx 'catalog=PASS' "$summary_file" || exit 1
    grep -Fqx 'order=PASS' "$summary_file" || exit 1
    grep -Fqx 'native_launcher=STARTED' "$summary_file" || exit 1
    grep -Fqx 'native_result=NOT_ACCEPTED' "$summary_file" || exit 1
    grep -Fqx 'query_reconcile=NOT_PROVEN' "$summary_file" || exit 1
    grep -Fqi 'orderStr' "$summary_file" && exit 1 || true
    grep -Fqi 'secret' "$summary_file" && exit 1 || true
    printf '%s\n' \
      'SUMMARY_MISSING_NATIVE::conclusion=FAIL::catalog=PASS::order=PASS::native_launcher=STARTED::native_result=NOT_ACCEPTED::query_reconcile=NOT_PROVEN'
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
FLUTTER_STATUS_PATH="$ARTIFACT_DIR/flutter-drive.status"
OPERATOR_LOG_PATH="$ARTIFACT_DIR/cancel-operator.log"
OPERATOR_PID_PATH="$ARTIFACT_DIR/cancel-operator.pid"
FLUTTER_TOOL_PID_PATH="$ARTIFACT_DIR/flutter-drive.pid"
: >"$FLUTTER_LOG_PATH"
: >"$FLUTTER_TOOL_PID_PATH"
: >"$OPERATOR_PID_PATH"
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
force_stop_flutter_app
prepare_android_host
record_launch_marker_baseline || fail_timeout 'Flutter log baseline could not be recorded'
run_flutter_target &
FLUTTER_PID=$!
FLUTTER_PID_REAPED=false
capture_process_identity "$FLUTTER_PID" ||
  fail_timeout 'Flutter runner process identity could not be recorded'
FLUTTER_PID_START_TIME="$CAPTURED_PROCESS_START_TIME"
FLUTTER_PID_GROUP="$CAPTURED_PROCESS_GROUP_ID"
if ! wait_for_native_launcher_start; then
  if [[ -s "$FLUTTER_STATUS_PATH" ]]; then
    FAIL_REASON='focused_flutter_target_failed_before_native_launcher'
  else
    FAIL_REASON='native_launcher_start_timeout'
  fi
  RUN_RESULT='FAIL'
  terminate_flutter_target
  audit "FAIL::$FAIL_REASON"
  exit 1
fi
if [[ -z "$FLUTTER_TOOL_PID" || -z "$FLUTTER_TOOL_START_TIME" ]]; then
  RUN_RESULT='FAIL'
  FAIL_REASON='flutter_tool_identity_unavailable'
  terminate_flutter_target
  audit "FAIL::$FAIL_REASON"
  exit 1
fi
if ! start_cancel_operator; then
  RUN_RESULT='FAIL'
  FAIL_REASON='cancel_operator_identity_unavailable'
  OPERATOR_STATUS=124
  terminate_cancel_operator
  terminate_flutter_target
  audit "FAIL::$FAIL_REASON"
  exit 1
fi
if ! wait_for_post_launch_completion; then
  RUN_RESULT='FAIL'
  FAIL_REASON='post_launch_watchdog_timeout'
  audit 'POST_LAUNCH_WATCHDOG_TIMEOUT'
  [[ "$FLUTTER_PID_REAPED" == true ]] || FLUTTER_STATUS=124
  [[ "$OPERATOR_PID_REAPED" == true ]] || OPERATOR_STATUS=124
  terminate_cancel_operator
  terminate_flutter_target
  audit "FAIL::$FAIL_REASON"
  exit 1
fi

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
