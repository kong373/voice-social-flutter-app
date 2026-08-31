#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

# PHYSICAL_DEVICE_DIAGNOSTIC is an intentionally independent lane.  It never
# changes the existing emulator-5554 focused runner and never starts an
# emulator, enumerates devices, taps a coordinate, or submits a payment.
# Every adb invocation below is scoped to the one explicit --serial value.

readonly TARGET_PACKAGE='com.eg.android.AlipayGphoneRC'
readonly TARGET_ACTIVITY='MspContainerActivity'
readonly API_BASE_URL='http://127.0.0.1:18080/'
readonly REVERSE_SPEC='tcp:18080 tcp:18080'
readonly EXPECTED_NATIVE_MARKER='M5_ALIPAY_NATIVE_RESULT::sdkCompleted=0::resultStatus=6001'
readonly EXPECTED_BRIDGE_MARKER='M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::pay_task_returned'
readonly REJECTED_SUCCESS_MARKER='M5_ALIPAY_NATIVE_RESULT::sdkCompleted=1::resultStatus=9000'
readonly REJECTED_NONE_MARKER='M5_ALIPAY_NATIVE_RESULT::sdkCompleted=0::resultStatus=none'
readonly DEVICE_UI_DUMP_PATH='/data/local/tmp/voice-social-alipay-physical-diagnostic-ui.xml'
readonly UI_XML_MAX_BYTES=262144
readonly MAX_FRESH_UI_DUMP_ATTEMPTS=2
readonly MAX_BACK_ATTEMPTS=2
readonly DEFAULT_CASHIER_TIMEOUT_SECONDS=60
readonly DEFAULT_AFTER_BACK_TIMEOUT_SECONDS=8
readonly DEFAULT_MARKER_TIMEOUT_SECONDS=30
readonly DEFAULT_POLL_INTERVAL_SECONDS=1
readonly DEFAULT_STABLE_POLLS=3

readonly EXIT_CONFIGURATION=64
readonly EXIT_MARKER=65
readonly EXIT_DEVICE=69
readonly EXIT_TIMEOUT=70

SELF_TEST=false
SERIAL_VALUE=''
SERIAL_ARG=''
FLUTTER_LOG_PATH=''
FLUTTER_LOG_ARG=''
ADB_BIN=''
CASHIER_TIMEOUT_SECONDS="$DEFAULT_CASHIER_TIMEOUT_SECONDS"
AFTER_BACK_TIMEOUT_SECONDS="$DEFAULT_AFTER_BACK_TIMEOUT_SECONDS"
MARKER_TIMEOUT_SECONDS="$DEFAULT_MARKER_TIMEOUT_SECONDS"
POLL_INTERVAL_SECONDS="$DEFAULT_POLL_INTERVAL_SECONDS"
STABLE_POLLS="$DEFAULT_STABLE_POLLS"
LOG_BASELINE_BYTES=0
BACK_COUNT=0
SCREEN_WIDTH=0
SCREEN_HEIGHT=0
UI_DUMP_LOCAL_PATH=''
UI_DUMP_ACTIVE=false

usage() {
  cat <<'USAGE'
Usage: m5_alipay_physical_device_cancel_operator.sh --serial ID --flutter-log PATH [options]

PHYSICAL_DEVICE_DIAGNOSTIC is a cancellation-only operator for one already
connected physical Android device.  It does not discover devices and it never
confirms or submits a payment.

Required:
  --serial ID                 explicit physical-device serial
  --flutter-log PATH          absolute private Flutter driver log

Optional bounded controls:
  --adb PATH                  adb executable (defaults to adb on PATH)
  --cashier-timeout SEC       wait for a safe cashier UI (default: 60)
  --after-back-timeout SEC    wait for cashier to leave after BACK (default: 8)
  --marker-timeout SEC        wait for the exact cancellation marker pair (default: 30)
  --poll-interval SEC         delay between polls (default: 1; 0 for fixtures)
  --stable-polls COUNT        consecutive fresh UI observations (default: 3)
  --self-test                 run offline marker and dynamic-UI checks
  --help                      show this help
USAGE
}

fail_configuration() {
  printf 'PHYSICAL_DEVICE_DIAGNOSTIC operator: configuration rejected (%s)\n' "$1" >&2
  exit "$EXIT_CONFIGURATION"
}

fail_marker() {
  printf 'PHYSICAL_DEVICE_DIAGNOSTIC operator: result marker rejected (%s)\n' "$1" >&2
  exit "$EXIT_MARKER"
}

fail_device() {
  printf 'PHYSICAL_DEVICE_DIAGNOSTIC operator: physical device rejected (%s)\n' "$1" >&2
  exit "$EXIT_DEVICE"
}

fail_timeout() {
  printf 'PHYSICAL_DEVICE_DIAGNOSTIC operator: bounded wait expired (%s)\n' "$1" >&2
  exit "$EXIT_TIMEOUT"
}

audit() {
  # Fixed vocabulary plus validated counters only.  Do not print a serial,
  # path, XML, command output, marker payload, or inherited environment value.
  printf 'PHYSICAL_DEVICE_DIAGNOSTIC::%s\n' "$1"
}

require_integer() {
  local name="$1"
  local value="$2"
  [[ "$value" =~ ^[0-9]+$ ]] || fail_configuration "$name must be a non-negative integer"
  (( value <= 600 )) || fail_configuration "$name exceeds the 600 second bound"
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
      --serial|--target-serial)
        (($# >= 2)) || fail_configuration 'serial is missing'
        [[ -z "$SERIAL_ARG" ]] || fail_configuration 'serial supplied more than once'
        SERIAL_ARG="$2"
        SERIAL_VALUE="$2"
        shift 2
        ;;
      --serial=*|--target-serial=*)
        [[ -z "$SERIAL_ARG" ]] || fail_configuration 'serial supplied more than once'
        SERIAL_ARG="${argument#*=}"
        SERIAL_VALUE="${argument#*=}"
        shift
        ;;
      --flutter-log|--flutter-log-path|--log-path)
        (($# >= 2)) || fail_configuration 'Flutter log path is missing'
        [[ -z "$FLUTTER_LOG_ARG" ]] || fail_configuration 'Flutter log path supplied more than once'
        FLUTTER_LOG_ARG="$2"
        FLUTTER_LOG_PATH="$2"
        shift 2
        ;;
      --flutter-log=*|--flutter-log-path=*|--log-path=*)
        [[ -z "$FLUTTER_LOG_ARG" ]] || fail_configuration 'Flutter log path supplied more than once'
        FLUTTER_LOG_ARG="${argument#*=}"
        FLUTTER_LOG_PATH="${argument#*=}"
        shift
        ;;
      --adb)
        (($# >= 2)) || fail_configuration 'adb path is missing'
        [[ -z "$ADB_BIN" ]] || fail_configuration 'adb path supplied more than once'
        ADB_BIN="$2"
        shift 2
        ;;
      --cashier-timeout|--target-timeout)
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

validate_serial() {
  [[ -n "$SERIAL_ARG" ]] || fail_configuration '--serial is required; no default serial is allowed'
  [[ "$SERIAL_VALUE" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$ ]] ||
    fail_configuration 'serial has an unsafe format'
  # A physical runner must never silently operate a qemu/emulator endpoint.
  if [[ "$SERIAL_VALUE" =~ [Ee][Mm][Uu][Ll][Aa][Tt][Oo][Rr] ||
    "$SERIAL_VALUE" =~ [Qq][Ee][Mm][Uu] ]]; then
    fail_configuration 'serial looks like an emulator or qemu target'
  fi
  if [[ -n "${ANDROID_SERIAL+x}" && -n "$ANDROID_SERIAL" &&
    "$ANDROID_SERIAL" != "$SERIAL_VALUE" ]]; then
    fail_configuration 'ANDROID_SERIAL disagrees with --serial'
  fi
}

validate_log_path() {
  [[ -n "$FLUTTER_LOG_PATH" ]] || fail_configuration '--flutter-log is required'
  [[ "$FLUTTER_LOG_PATH" == /* ]] || fail_configuration 'Flutter log path must be absolute'
  [[ "$FLUTTER_LOG_PATH" != *$'\n'* && "$FLUTTER_LOG_PATH" != *$'\r'* &&
    "$FLUTTER_LOG_PATH" != *$'\t'* && "$FLUTTER_LOG_PATH" != *'..'* ]] ||
    fail_configuration 'Flutter log path has an unsafe format'
  [[ -f "$FLUTTER_LOG_PATH" && ! -L "$FLUTTER_LOG_PATH" ]] ||
    fail_configuration 'private Flutter log file is unavailable'
  [[ -r "$FLUTTER_LOG_PATH" ]] || fail_configuration 'private Flutter log is unreadable'
}

validate_bounds() {
  require_integer cashier-timeout "$CASHIER_TIMEOUT_SECONDS"
  require_integer after-back-timeout "$AFTER_BACK_TIMEOUT_SECONDS"
  require_integer marker-timeout "$MARKER_TIMEOUT_SECONDS"
  require_integer poll-interval "$POLL_INTERVAL_SECONDS"
  require_integer stable-polls "$STABLE_POLLS"
  (( STABLE_POLLS >= 3 )) || fail_configuration 'stable poll count must be at least 3'
}

resolve_adb() {
  if [[ -z "$ADB_BIN" ]]; then
    ADB_BIN="$(command -v adb || true)"
  fi
  [[ -n "$ADB_BIN" && -x "$ADB_BIN" ]] || fail_configuration 'adb executable is unavailable'
  [[ "$ADB_BIN" != *$'\n'* && "$ADB_BIN" != *$'\r'* && "$ADB_BIN" != *$'\t'* ]] ||
    fail_configuration 'adb executable path is unsafe'
  command -v python3 >/dev/null 2>&1 || fail_configuration 'python3 executable is unavailable'
}

pause_between_polls() {
  if (( POLL_INTERVAL_SECONDS > 0 )); then
    sleep "$POLL_INTERVAL_SECONDS"
  fi
}

adb_get_state() {
  local state='' status=0
  state="$("$ADB_BIN" -s "$SERIAL_VALUE" get-state 2>/dev/null)" || status=$?
  state="${state//$'\r'/}"
  state="${state//$'\n'/}"
  if [[ "$state" == 'offline' || "$state" == *'offline'* ]]; then
    fail_device 'selected serial is offline'
  fi
  [[ "$status" -eq 0 && "$state" == 'device' ]] || fail_device 'selected serial is not online'
}

read_prop() {
  local property="$1" value='' status=0
  value="$("$ADB_BIN" -s "$SERIAL_VALUE" shell getprop "$property" 2>/dev/null)" || status=$?
  [[ "$status" -eq 0 ]] || fail_device 'device properties are unavailable'
  value="${value//$'\r'/}"
  value="${value//$'\n'/}"
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* && "$value" != *$'\t'* ]] ||
    fail_device 'device property contains control data'
  printf '%s' "$value"
}

verify_physical_device() {
  local qemu_kernel qemu_boot hardware model product device board metadata
  qemu_kernel="$(read_prop ro.kernel.qemu)"
  qemu_boot="$(read_prop ro.boot.qemu)"
  hardware="$(read_prop ro.hardware)"
  model="$(read_prop ro.product.model)"
  product="$(read_prop ro.product.name)"
  device="$(read_prop ro.product.device)"
  board="$(read_prop ro.product.board)"
  local qemu_values
  qemu_values="$(printf '%s\n' "$qemu_kernel" "$qemu_boot" | tr '[:upper:]' '[:lower:]')"
  if [[ "$qemu_values" == *'1'* || "$qemu_values" == *'true'* || "$qemu_values" == *'qemu'* ]]; then
    fail_device 'qemu property is enabled'
  fi
  metadata="$(printf '%s\n' "$hardware" "$model" "$product" "$device" "$board" |
    tr '[:upper:]' '[:lower:]')"
  if [[ "$metadata" =~ goldfish|ranchu|emulator|simulator|sdk_gphone|generic_x86|generic_x86_64|vbox|qemu ]]; then
    fail_device 'device properties identify an emulator or qemu'
  fi
  [[ -n "${hardware}${model}${product}${device}${board}" ]] || fail_device 'physical device identity is unavailable'
  audit 'DEVICE_ONLINE'
  audit 'PHYSICAL_DEVICE_VERIFIED'
}

read_screen_size() {
  local raw dimensions='' status=0
  raw="$("$ADB_BIN" -s "$SERIAL_VALUE" shell wm size 2>/dev/null)" || status=$?
  [[ "$status" -eq 0 ]] || fail_device 'dynamic screen size is unavailable'
  dimensions="$(printf '%s\n' "$raw" | awk '
    match($0, /[0-9]+x[0-9]+/) { value=substr($0, RSTART, RLENGTH) }
    END { print value }
  ')"
  [[ "$dimensions" =~ ^[1-9][0-9]{0,4}x[1-9][0-9]{0,4}$ ]] ||
    fail_device 'dynamic screen size is invalid'
  SCREEN_WIDTH="${dimensions%x*}"
  SCREEN_HEIGHT="${dimensions#*x}"
  (( SCREEN_WIDTH > 0 && SCREEN_HEIGHT > 0 )) || fail_device 'dynamic screen size is empty'
  audit "SCREEN_SIZE_VERIFIED::width=${SCREEN_WIDTH}::height=${SCREEN_HEIGHT}"
}

verify_reverse() {
  local mappings='' status=0
  # Required host bridge: adb reverse tcp:18080 tcp:18080.  This is the only
  # API route allowed by this lane; the Flutter target uses 127.0.0.1:18080.
  "$ADB_BIN" -s "$SERIAL_VALUE" reverse tcp:18080 tcp:18080 >/dev/null 2>&1 ||
    fail_device 'adb reverse tcp:18080 tcp:18080 failed'
  mappings="$("$ADB_BIN" -s "$SERIAL_VALUE" reverse --list 2>/dev/null)" || status=$?
  [[ "$status" -eq 0 ]] || fail_device 'adb reverse mapping cannot be inspected'
  grep -Eq '(^|[[:space:]])tcp:18080[[:space:]]+tcp:18080([[:space:]]|$)' <<<"$mappings" ||
    fail_device 'adb reverse tcp:18080 tcp:18080 is missing'
  audit 'ADB_REVERSE_PASS::tcp=18080'
}

foreground_is_target() {
  local dump="$1"
  awk -v package="$TARGET_PACKAGE" -v activity="$TARGET_ACTIVITY" '
    /(^|[[:space:]])(mResumedActivity|ResumedActivity|topResumedActivity|mFocusedApp):/ {
      start = index($0, package "/")
      if (start > 0) {
        component = substr($0, start + length(package) + 1)
        sub(/[[:space:]}].*$/, "", component)
        if (component ~ ("(^|\\.)" activity "$")) found = 1
      }
    }
    END { exit(found ? 0 : 1) }
  ' <<<"$dump"
}

read_target_state() {
  local dump='' status=0
  dump="$("$ADB_BIN" -s "$SERIAL_VALUE" shell dumpsys activity activities 2>/dev/null)" || status=$?
  [[ "$status" -eq 0 ]] || fail_device 'activity state is unavailable'
  if grep -Eiq '(^|[[:space:]])(device offline|unauthorized|no devices? found)' <<<"$dump"; then
    fail_device 'selected serial became unavailable'
  fi
  foreground_is_target "$dump"
}

cleanup_ui_dump() {
  if [[ "$UI_DUMP_ACTIVE" == true && -n "$ADB_BIN" && -n "$SERIAL_VALUE" ]]; then
    "$ADB_BIN" -s "$SERIAL_VALUE" shell rm -f "$DEVICE_UI_DUMP_PATH" >/dev/null 2>&1 || true
  fi
  if [[ -n "$UI_DUMP_LOCAL_PATH" && -f "$UI_DUMP_LOCAL_PATH" && ! -L "$UI_DUMP_LOCAL_PATH" ]]; then
    chmod 600 "$UI_DUMP_LOCAL_PATH" >/dev/null 2>&1 || true
    rm -f -- "$UI_DUMP_LOCAL_PATH" || true
  fi
  UI_DUMP_LOCAL_PATH=''
  UI_DUMP_ACTIVE=false
}

cleanup_on_exit() {
  local status=$?
  set +e
  cleanup_ui_dump
  trap - EXIT
  exit "$status"
}

capture_fresh_ui_xml() {
  local attempt=1 pipeline_status=0 byte_count=''
  while (( attempt <= MAX_FRESH_UI_DUMP_ATTEMPTS )); do
    cleanup_ui_dump
    UI_DUMP_LOCAL_PATH="$(mktemp /tmp/voice-social-alipay-physical-ui.XXXXXX)" ||
      fail_device 'temporary UI XML could not be created'
    chmod 600 "$UI_DUMP_LOCAL_PATH" || fail_device 'temporary UI XML permissions failed'
    UI_DUMP_ACTIVE=true
    "$ADB_BIN" -s "$SERIAL_VALUE" shell rm -f "$DEVICE_UI_DUMP_PATH" >/dev/null 2>&1 ||
      fail_device 'stale UI XML could not be removed'
    "$ADB_BIN" -s "$SERIAL_VALUE" shell uiautomator dump "$DEVICE_UI_DUMP_PATH" >/dev/null 2>&1 ||
      fail_device 'fresh UI XML dump is unavailable'
    if ! "$ADB_BIN" -s "$SERIAL_VALUE" shell chmod 600 "$DEVICE_UI_DUMP_PATH" >/dev/null 2>&1; then
      cleanup_ui_dump
      if (( attempt < MAX_FRESH_UI_DUMP_ATTEMPTS )); then
        attempt=$((attempt + 1))
        continue
      fi
      fail_device 'fresh UI XML permissions could not be secured'
    fi
    set +e
    "$ADB_BIN" -s "$SERIAL_VALUE" shell cat "$DEVICE_UI_DUMP_PATH" |
      head -c "$((UI_XML_MAX_BYTES + 1))" >"$UI_DUMP_LOCAL_PATH"
    pipeline_status=$?
    set -e
    byte_count="$(wc -c <"$UI_DUMP_LOCAL_PATH" 2>/dev/null | tr -d '[:space:]')" ||
      fail_device 'fresh UI XML size is unavailable'
    [[ "$byte_count" =~ ^[0-9]+$ ]] || fail_device 'fresh UI XML size is invalid'
    (( byte_count > 0 && byte_count <= UI_XML_MAX_BYTES )) || fail_device 'fresh UI XML size is unsafe'
    (( pipeline_status == 0 )) || fail_device 'fresh UI XML could not be read'
    return 0
  done
  fail_device 'fresh UI XML could not be secured'
}

ui_xml_state() {
  python3 - "$UI_DUMP_LOCAL_PATH" "$TARGET_PACKAGE" "$TARGET_ACTIVITY" \
    "$SCREEN_WIDTH" "$SCREEN_HEIGHT" "$UI_XML_MAX_BYTES" <<'PY'
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def verdict(value: str) -> None:
    print(value)
    raise SystemExit(0)


try:
    path = Path(sys.argv[1])
    package = sys.argv[2]
    activity = sys.argv[3].casefold().lstrip(".")
    width = int(sys.argv[4])
    height = int(sys.argv[5])
    max_bytes = int(sys.argv[6])
    raw = path.read_bytes()
    if not raw or len(raw) > max_bytes or b"\x00" in raw:
        verdict("INVALID")
    text = raw.decode("utf-8")
    if any(ord(character) < 0x20 and character not in "\r\n\t" for character in text):
        verdict("INVALID")
    root = ET.fromstring(text)
except (OSError, UnicodeDecodeError, ValueError, ET.ParseError, IndexError):
    verdict("INVALID")

if root.tag.rsplit("}", 1)[-1] != "hierarchy" or width <= 0 or height <= 0:
    verdict("INVALID")
nodes = [node for node in root.iter() if node.tag.rsplit("}", 1)[-1] == "node"]
if not nodes:
    verdict("INVALID")
root_package = root.attrib.get("package", "").strip()
if root_package and root_package != package:
    verdict("INVALID")
target_nodes = [node for node in nodes if node.attrib.get("package", "").strip() == package]
if not target_nodes:
    verdict("INVALID")

def labels(node):
    return {
        node.attrib.get(attribute, "").strip().casefold()
        for attribute in ("text", "content-desc")
        if node.attrib.get(attribute, "").strip()
    }

def is_visible(node):
    # Android 16 omits visible-to-user from a real foreground UI dump.  Treat
    # omission as visible, but continue rejecting an explicit false value.
    return node.attrib.get("visible-to-user", "") in ("", "true")

all_values = " ".join(
    value.strip().casefold() for node in target_nodes for value in node.attrib.values() if value.strip()
)
for marker in (
    "server busy", "busy", "timeout", "timed out", "try again", "error", "failed",
    "繁忙", "超时", "重试", "失败", "异常",
):
    if marker in all_values:
        verdict("UNSAFE")

for node in target_nodes:
    node_class = node.attrib.get("class", "").casefold()
    joined = " ".join(labels(node))
    if "edittext" in node_class or any(
        marker in joined
        for marker in ("otp", "one-time", "one time", "passcode", "password", "支付密码", "验证码", "security code", "pin")
    ):
        verdict("UNSAFE")
    if any(
        marker in joined
        for marker in ("confirm payment", "payment confirmation", "pay now", "confirm and pay", "submit payment", "确认支付", "立即支付", "确认付款")
    ):
        verdict("UNSAFE")

bounds_pattern = re.compile(r"^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$")
def valid_bounds(node):
    match = bounds_pattern.fullmatch(node.attrib.get("bounds", ""))
    if match is None:
        return False
    x1, y1, x2, y2 = (int(value) for value in match.groups())
    return 0 <= x1 < x2 <= width and 0 <= y1 < y2 <= height

def is_cancel_label(value):
    return any(token in value for token in ("cancel", "back", "取消", "返回"))

ready_controls = []
for node in target_nodes:
    if not any(is_cancel_label(value) for value in labels(node)):
        continue
    if node.attrib.get("enabled") != "true" or not is_visible(node):
        continue
    if node.attrib.get("clickable") != "true" or not valid_bounds(node):
        continue
    ready_controls.append(node)
if not ready_controls:
    verdict("INVALID")

verdict("READY")
PY
}

read_cashier_ui_state() {
  adb_get_state
  if ! read_target_state; then
    return 1
  fi
  capture_fresh_ui_xml
  local state=''
  state="$(ui_xml_state)" || fail_device 'fresh UI XML could not be validated'
  cleanup_ui_dump
  case "$state" in
    READY) return 0 ;;
    UNSAFE) fail_device 'Alipay cashier UI contains unsafe state' ;;
    INVALID) fail_device 'Alipay cashier UI is not safely cancellable' ;;
    *) fail_device 'Alipay cashier UI state is unknown' ;;
  esac
}

wait_for_stable_cashier() {
  local deadline=$((SECONDS + CASHIER_TIMEOUT_SECONDS)) stable=0
  while (( SECONDS <= deadline )); do
    if read_cashier_ui_state; then
      stable=$((stable + 1))
      if (( stable >= STABLE_POLLS )); then
        audit "UI_READY::polls=${STABLE_POLLS}"
        return 0
      fi
    else
      stable=0
      audit 'UI_GATE_RESET'
    fi
    pause_between_polls
  done
  fail_timeout 'Alipay cashier UI did not become safely cancellable'
}

scan_marker_stream() {
  awk -v expected_native="$EXPECTED_NATIVE_MARKER" -v expected_bridge="$EXPECTED_BRIDGE_MARKER" '
    function inspect(line) {
      sub(/\r$/, "", line)
      if (line == expected_native) print "NATIVE_VALID"
      else if (line ~ /^M5_ALIPAY_NATIVE_RESULT::/) print "NATIVE_INVALID"
      else if (line == expected_bridge) print "BRIDGE_VALID"
      else if (line ~ /^M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::/) print "BRIDGE_INVALID"
    }
    {
      line = $0
      if (line ~ /^[VDIWEF]\/flutter \([[:space:]]*[0-9]+\): M5_ALIPAY_NATIVE_RESULT::/ ||
          line ~ /^[VDIWEF]\/flutter \([[:space:]]*[0-9]+\): M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::/) {
        sub(/^[VDIWEF]\/flutter \([[:space:]]*[0-9]+\): /, "", line)
      }
      if (line ~ /^M5_ALIPAY_NATIVE_RESULT::/ || line ~ /^M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::/) inspect(line)
    }
  '
}

marker_state_from_file_prefix() {
  local valid_count=0 invalid_count=0 marker_kind=''
  while IFS= read -r marker_kind; do
    case "$marker_kind" in
      NATIVE_VALID|BRIDGE_VALID) valid_count=$((valid_count + 1)) ;;
      NATIVE_INVALID|BRIDGE_INVALID) invalid_count=$((invalid_count + 1)) ;;
    esac
  done < <(head -c "$LOG_BASELINE_BYTES" "$FLUTTER_LOG_PATH" 2>/dev/null | scan_marker_stream || true)
  if (( invalid_count > 0 )); then printf 'INVALID'
  elif (( valid_count > 0 )); then printf 'PRESENT'
  else printf 'MISSING'
  fi
}

classify_marker_pair() {
  local current_bytes marker_kind native_valid=0 bridge_valid=0 invalid=0
  current_bytes="$(wc -c <"$FLUTTER_LOG_PATH" 2>/dev/null | tr -d '[:space:]')" || {
    printf 'INVALID'; return 0;
  }
  [[ "$current_bytes" =~ ^[0-9]+$ && "$current_bytes" -ge "$LOG_BASELINE_BYTES" ]] || {
    printf 'INVALID'; return 0;
  }
  while IFS= read -r marker_kind; do
    case "$marker_kind" in
      NATIVE_VALID) native_valid=$((native_valid + 1)) ;;
      BRIDGE_VALID) bridge_valid=$((bridge_valid + 1)) ;;
      NATIVE_INVALID|BRIDGE_INVALID) invalid=$((invalid + 1)) ;;
    esac
  done < <(tail -c +$((LOG_BASELINE_BYTES + 1)) "$FLUTTER_LOG_PATH" 2>/dev/null | scan_marker_stream || true)
  if (( invalid > 0 )); then printf 'INVALID'
  elif (( native_valid > 1 || bridge_valid > 1 )); then printf 'AMBIGUOUS'
  elif (( native_valid == 1 && bridge_valid == 1 )); then printf 'VALID'
  elif (( native_valid == 1 || bridge_valid == 1 )); then printf 'PARTIAL'
  else printf 'MISSING'
  fi
}

record_marker_baseline() {
  LOG_BASELINE_BYTES="$(wc -c <"$FLUTTER_LOG_PATH" 2>/dev/null | tr -d '[:space:]')" ||
    fail_configuration 'private Flutter log size is unavailable'
  [[ "$LOG_BASELINE_BYTES" =~ ^[0-9]+$ ]] || fail_configuration 'private Flutter log size is invalid'
  [[ "$(marker_state_from_file_prefix)" == 'MISSING' ]] ||
    fail_marker 'stale native or bridge marker before this run'
}

assert_no_marker_before_back() {
  local state
  state="$(classify_marker_pair)"
  if (( BACK_COUNT == 0 )); then
    [[ "$state" == 'MISSING' ]] || fail_marker 'native or bridge marker appeared before BACK'
    return 0
  fi
  case "$state" in
    MISSING|PARTIAL) ;;
    *) fail_marker 'complete, invalid, or duplicate marker appeared before next BACK' ;;
  esac
}

send_back_once() {
  (( BACK_COUNT < MAX_BACK_ATTEMPTS )) || fail_timeout 'BACK budget exhausted'
  wait_for_stable_cashier
  assert_no_marker_before_back
  BACK_COUNT=$((BACK_COUNT + 1))
  "$ADB_BIN" -s "$SERIAL_VALUE" shell input keyevent KEYCODE_BACK >/dev/null 2>&1 ||
    fail_device 'KEYCODE_BACK command failed'
  audit "KEYCODE_BACK_SENT::attempt=${BACK_COUNT}"
  cleanup_ui_dump
}

wait_for_target_to_leave() {
  (( AFTER_BACK_TIMEOUT_SECONDS > 0 )) || return 1
  local deadline=$((SECONDS + AFTER_BACK_TIMEOUT_SECONDS))
  while (( SECONDS <= deadline )); do
    if ! read_target_state; then
      audit 'TARGET_LEFT_AFTER_BACK'
      return 0
    fi
    pause_between_polls
  done
  return 1
}

wait_for_cancel_marker() {
  local deadline=$((SECONDS + MARKER_TIMEOUT_SECONDS)) state=''
  while (( SECONDS <= deadline )); do
    state="$(classify_marker_pair)"
    case "$state" in
      VALID)
        audit 'NATIVE_RESULT_ACCEPTED::sdkCompleted=0::resultStatus=6001'
        audit 'BRIDGE_OUTCOME_ACCEPTED::pay_task_returned'
        return 0
        ;;
      INVALID) fail_marker 'only sdkCompleted=0/resultStatus=6001 is trusted; resultStatus=9000/none is rejected' ;;
      AMBIGUOUS) fail_marker 'duplicate native or bridge markers' ;;
      PARTIAL|MISSING) ;;
    esac
    pause_between_polls
  done
  fail_timeout 'trusted native cancellation marker pair was not observed'
}

operator_self_test() {
  (
    set -Eeuo pipefail
    local root log ui_state
    [[ "$API_BASE_URL" == 'http://127.0.0.1:18080/' ]] || exit 1
    [[ "$REVERSE_SPEC" == 'tcp:18080 tcp:18080' ]] || exit 1
    root="$(mktemp -d /tmp/voice-social-alipay-physical-operator-self-test.XXXXXX)"
    trap 'rm -rf -- "$root"' EXIT
    log="$root/flutter.log"
    : >"$log"
    FLUTTER_LOG_PATH="$log"
    LOG_BASELINE_BYTES=0
    record_marker_baseline
    printf '%s\n%s\n' "$EXPECTED_NATIVE_MARKER" "$EXPECTED_BRIDGE_MARKER" >>"$log"
    [[ "$(classify_marker_pair)" == 'VALID' ]] || exit 1
    : >"$log"
    record_marker_baseline
    printf '%s\n%s\n' "$REJECTED_SUCCESS_MARKER" "$EXPECTED_BRIDGE_MARKER" >>"$log"
    [[ "$(classify_marker_pair)" == 'INVALID' ]] || exit 1
    : >"$log"
    record_marker_baseline
    printf '%s\n%s\n' "$REJECTED_NONE_MARKER" "$EXPECTED_BRIDGE_MARKER" >>"$log"
    [[ "$(classify_marker_pair)" == 'INVALID' ]] || exit 1
    : >"$log"
    printf '%s\n' "$EXPECTED_NATIVE_MARKER" >"$log"
    LOG_BASELINE_BYTES="$(wc -c <"$log" | tr -d '[:space:]')"
    [[ "$(marker_state_from_file_prefix)" != 'MISSING' ]] || exit 1
    printf '%s\n' '<hierarchy package="com.eg.android.AlipayGphoneRC"><node package="com.eg.android.AlipayGphoneRC" text="Cancel" content-desc="Cancel" enabled="true" clickable="true" bounds="[40,2800][1400,3000]" /></hierarchy>' >"$root/ui.xml"
    UI_DUMP_LOCAL_PATH="$root/ui.xml"
    SCREEN_WIDTH=1440
    SCREEN_HEIGHT=3200
    ui_state="$(ui_xml_state)"
    [[ "$ui_state" == 'READY' ]] || exit 1
    printf '%s\n' '<hierarchy package="com.other.wallet"><node package="com.other.wallet" text="Cancel" enabled="true" visible-to-user="true" clickable="true" bounds="[40,2800][1400,3000]" /></hierarchy>' >"$root/ui.xml"
    [[ "$(ui_xml_state)" == 'INVALID' ]] || exit 1
    audit 'MARKER_FAIL_CLOSED_PASS'
    audit 'DYNAMIC_UI_PASS'
    audit 'SELF_TEST_PASS'
  )
  printf 'SELF_TEST::PASS\n'
}

main() {
  parse_args "$@"
  if [[ "$SELF_TEST" == true ]]; then
    operator_self_test
    exit 0
  fi
  validate_serial
  validate_log_path
  validate_bounds
  resolve_adb
  trap cleanup_on_exit EXIT
  record_marker_baseline
  adb_get_state
  verify_physical_device
  verify_reverse
  read_screen_size
  audit 'CANCEL_ONLY'
  send_back_once
  if wait_for_target_to_leave; then
    :
  else
    audit 'TARGET_STILL_PRESENT_AFTER_BOUNDED_WAIT'
    send_back_once
  fi
  wait_for_cancel_marker
  audit 'PASS'
}

main "$@"
