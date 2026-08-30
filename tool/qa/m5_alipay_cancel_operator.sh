#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

# This operator is deliberately narrow: it observes one explicitly selected
# Android device, returns from the real Alipay sandbox cashier with BACK, and
# accepts only the paired, sanitized native-result and bridge-provenance markers
# from a private Flutter driver log.
# It never enumerates devices, starts an app, taps a coordinate, or submits a
# payment.

readonly TARGET_PACKAGE='com.eg.android.AlipayGphoneRC'
readonly TARGET_ACTIVITY='MspContainerActivity'
readonly TARGET_SERIAL='emulator-5554'
readonly EXPECTED_NATIVE_MARKER='M5_ALIPAY_NATIVE_RESULT::sdkCompleted=0::resultStatus=6001'
readonly EXPECTED_BRIDGE_MARKER='M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::pay_task_returned'
readonly DEVICE_UI_DUMP_PATH='/data/local/tmp/voice-social-alipay-cancel-ui.xml'
readonly UI_XML_MAX_BYTES=262144
readonly DEFAULT_TARGET_TIMEOUT_SECONDS=60
readonly DEFAULT_AFTER_BACK_TIMEOUT_SECONDS=8
readonly DEFAULT_MARKER_TIMEOUT_SECONDS=30
readonly DEFAULT_POLL_INTERVAL_SECONDS=1
readonly DEFAULT_STABLE_POLLS=3

readonly EXIT_CONFIGURATION=64
readonly EXIT_MARKER=65
readonly EXIT_DEVICE=69
readonly EXIT_TIMEOUT=70

ANDROID_SERIAL_VALUE=''
TARGET_SERIAL_ARG=''
FLUTTER_LOG_PATH_ARG=''
FLUTTER_LOG_PATH_VALUE="${FLUTTER_LOG_PATH:-}"
ADB_BIN=''
TARGET_TIMEOUT_SECONDS="$DEFAULT_TARGET_TIMEOUT_SECONDS"
AFTER_BACK_TIMEOUT_SECONDS="$DEFAULT_AFTER_BACK_TIMEOUT_SECONDS"
MARKER_TIMEOUT_SECONDS="$DEFAULT_MARKER_TIMEOUT_SECONDS"
POLL_INTERVAL_SECONDS="$DEFAULT_POLL_INTERVAL_SECONDS"
STABLE_POLLS="$DEFAULT_STABLE_POLLS"
BACK_COUNT=0
LOG_BASELINE_BYTES=0
UI_DUMP_LOCAL_PATH=''
UI_DUMP_ACTIVE=false

usage() {
  cat <<'USAGE'
Usage: m5_alipay_cancel_operator.sh --flutter-log PATH [options]

Required:
  ANDROID_SERIAL         one explicit device serial; no device discovery is done
  --flutter-log PATH     absolute path to the private Flutter driver log
  (or FLUTTER_LOG_PATH)  explicit absolute path may be supplied by this env var

Optional test/diagnostic bounds (all are finite):
  --adb PATH             adb executable (defaults to adb on PATH)
  --target-serial ID     confirm the frozen target serial (must be emulator-5554)
  --target-timeout SEC   wait bound for a stable sandbox cashier (default: 60)
  --after-back-timeout SEC
                         wait bound after each BACK (default: 8)
  --marker-timeout SEC   wait bound for the sanitized result marker (default: 30)
  --poll-interval SEC    delay between polls (default: 1; 0 is allowed for fixtures)
  --stable-polls COUNT   consecutive fresh UI-ready observations (default: 3)
USAGE
}

fail_configuration() {
  printf 'M5 Alipay cancel operator: configuration rejected (%s)\n' "$1" >&2
  exit "$EXIT_CONFIGURATION"
}

fail_device() {
  printf 'M5 Alipay cancel operator: device rejected (%s)\n' "$1" >&2
  exit "$EXIT_DEVICE"
}

fail_marker() {
  printf 'M5 Alipay cancel operator: result marker rejected (%s)\n' "$1" >&2
  exit "$EXIT_MARKER"
}

fail_timeout() {
  printf 'M5 Alipay cancel operator: bounded wait expired (%s)\n' "$1" >&2
  exit "$EXIT_TIMEOUT"
}

audit() {
  # Every audit field is a fixed vocabulary or a validated integer. Do not
  # print serials, paths, command output, or any inherited environment value.
  printf 'M5_ALIPAY_CANCEL_OPERATOR::%s\n' "$1"
}

require_integer() {
  local name="$1"
  local value="$2"
  [[ "$value" =~ ^[0-9]+$ ]] || fail_configuration "$name must be a non-negative integer"
  # Keep every poll loop bounded even when a caller supplies an option.
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
      --flutter-log|--flutter-log-path|--log-path)
        (($# >= 2)) || fail_configuration 'Flutter log path is missing'
        [[ -z "$FLUTTER_LOG_PATH_ARG" ]] || fail_configuration 'Flutter log path supplied more than once'
        FLUTTER_LOG_PATH_ARG="$2"
        shift 2
        ;;
      --adb)
        (($# >= 2)) || fail_configuration 'adb path is missing'
        [[ -z "$ADB_BIN" ]] || fail_configuration 'adb path supplied more than once'
        ADB_BIN="$2"
        shift 2
        ;;
      --target-serial|--serial)
        (($# >= 2)) || fail_configuration 'target serial is missing'
        [[ -z "$TARGET_SERIAL_ARG" ]] || fail_configuration 'target serial supplied more than once'
        TARGET_SERIAL_ARG="$2"
        shift 2
        ;;
      --target-timeout)
        (($# >= 2)) || fail_configuration 'target timeout is missing'
        TARGET_TIMEOUT_SECONDS="$2"
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
  local expected_serial="$TARGET_SERIAL"
  if [[ -n "$TARGET_SERIAL_ARG" ]]; then
    [[ "$TARGET_SERIAL_ARG" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$ ]] ||
      fail_configuration 'target serial has an unsafe format'
    [[ "$TARGET_SERIAL_ARG" == "$TARGET_SERIAL" ]] ||
      fail_configuration 'target serial is frozen to emulator-5554'
    expected_serial="$TARGET_SERIAL_ARG"
  fi
  if [[ -z "${ANDROID_SERIAL+x}" || -z "$ANDROID_SERIAL" ]]; then
    fail_configuration 'ANDROID_SERIAL is required'
  fi
  # A serial is passed as one argv element below; reject shell metacharacters,
  # whitespace, and control bytes before it reaches adb.
  [[ "$ANDROID_SERIAL" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$ ]] ||
    fail_configuration 'ANDROID_SERIAL has an unsafe format'
  [[ "$ANDROID_SERIAL" == "$expected_serial" ]] ||
    fail_configuration 'ANDROID_SERIAL does not match the selected target serial'
  ANDROID_SERIAL_VALUE="$ANDROID_SERIAL"

  # When the normal M5 environment names the receiver AVD, reject an accidental
  # attempt to operate it. The operator itself never reads or probes that AVD.
  if [[ -n "${QA_AVD_B_SERIAL+x}" && -n "$QA_AVD_B_SERIAL" &&
    "$QA_AVD_B_SERIAL" == "$ANDROID_SERIAL_VALUE" ]]; then
    fail_configuration 'ANDROID_SERIAL names AVD-B'
  fi
}

validate_log_path() {
  if [[ -n "$FLUTTER_LOG_PATH_ARG" ]]; then
    FLUTTER_LOG_PATH_VALUE="$FLUTTER_LOG_PATH_ARG"
  else
    # The environment form is explicit too, but there is no default path.
    FLUTTER_LOG_PATH_VALUE="${FLUTTER_LOG_PATH_VALUE:-${M5_FLUTTER_LOG_PATH:-}}"
  fi
  [[ -n "$FLUTTER_LOG_PATH_VALUE" ]] || fail_configuration 'private Flutter log path is required'
  [[ "$FLUTTER_LOG_PATH_VALUE" == /* ]] || fail_configuration 'Flutter log path must be absolute'
  # Avoid path traversal and control characters. A symlink is rejected so the
  # operator cannot be redirected to an unrelated or changing log.
  [[ "$FLUTTER_LOG_PATH_VALUE" != *$'\n'* &&
    "$FLUTTER_LOG_PATH_VALUE" != *$'\r'* &&
    "$FLUTTER_LOG_PATH_VALUE" != *$'\t'* &&
    "$FLUTTER_LOG_PATH_VALUE" != *'..'* ]] ||
    fail_configuration 'Flutter log path has an unsafe format'
  [[ -f "$FLUTTER_LOG_PATH_VALUE" && ! -L "$FLUTTER_LOG_PATH_VALUE" ]] ||
    fail_configuration 'private Flutter log file is unavailable'
  [[ -r "$FLUTTER_LOG_PATH_VALUE" ]] || fail_configuration 'private Flutter log is unreadable'
}

validate_bounds() {
  require_integer target-timeout "$TARGET_TIMEOUT_SECONDS"
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
  [[ "$ADB_BIN" != *$'\n'* && "$ADB_BIN" != *$'\r'* ]] ||
    fail_configuration 'adb executable path is unsafe'
  command -v python3 >/dev/null 2>&1 ||
    fail_configuration 'python3 executable is unavailable'
}

pause_between_polls() {
  if (( POLL_INTERVAL_SECONDS > 0 )); then
    sleep "$POLL_INTERVAL_SECONDS"
  fi
}

adb_get_state() {
  local state=''
  local status=0
  state="$("$ADB_BIN" -s "$ANDROID_SERIAL_VALUE" get-state 2>/dev/null)" || status=$?
  state="${state//$'\r'/}"
  state="${state//$'\n'/}"
  if [[ "$state" == 'offline' || "$state" == *'device offline'* ]]; then
    fail_device 'offline'
  fi
  [[ "$status" -eq 0 && "$state" == 'device' ]] || fail_device 'not online'
}

foreground_is_target() {
  local dump="$1"
  # Only activity-manager foreground records are accepted. Matching arbitrary
  # log text that happens to contain the package/class is insufficient.
  awk -v package="$TARGET_PACKAGE" -v activity="$TARGET_ACTIVITY" '
    /(^|[[:space:]])(mResumedActivity|ResumedActivity|topResumedActivity|mFocusedApp):/ {
      component_start = index($0, package "/")
      if (component_start > 0) {
        component = substr($0, component_start + length(package) + 1)
        sub(/[[:space:]}].*$/, "", component)
        if (component ~ ("(^|\\.)" activity "$")) {
          found = 1
        }
      }
    }
    END { exit(found ? 0 : 1) }
  ' <<<"$dump"
}

read_target_state() {
  local dump=''
  local status=0
  dump="$("$ADB_BIN" -s "$ANDROID_SERIAL_VALUE" shell dumpsys activity activities 2>/dev/null)" || status=$?
  if (( status != 0 )); then
    fail_device 'activity state unavailable'
  fi
  if grep -Eiq '(^|[[:space:]])(error:.*offline|device offline|unauthorized|no devices? found)' <<<"$dump"; then
    fail_device 'offline'
  fi
  if foreground_is_target "$dump"; then
    return 0
  fi
  return 1
}

cleanup_ui_dump() {
  if [[ "$UI_DUMP_ACTIVE" == true && -n "$ADB_BIN" &&
    -n "$ANDROID_SERIAL_VALUE" ]]; then
    "$ADB_BIN" -s "$ANDROID_SERIAL_VALUE" shell rm -f \
      "$DEVICE_UI_DUMP_PATH" >/dev/null 2>&1 || true
  fi
  if [[ -n "$UI_DUMP_LOCAL_PATH" && -f "$UI_DUMP_LOCAL_PATH" &&
    ! -L "$UI_DUMP_LOCAL_PATH" ]]; then
    chmod 600 "$UI_DUMP_LOCAL_PATH" >/dev/null 2>&1 || true
    rm -f -- "$UI_DUMP_LOCAL_PATH" || true
  fi
  UI_DUMP_LOCAL_PATH=''
  UI_DUMP_ACTIVE=false
}

cleanup_on_exit() {
  local incoming_status=$?
  set +e
  cleanup_ui_dump
  trap - EXIT
  exit "$incoming_status"
}

capture_fresh_ui_xml() {
  cleanup_ui_dump
  UI_DUMP_LOCAL_PATH="$(mktemp /tmp/voice-social-alipay-cancel-ui.XXXXXX)" ||
    fail_device 'temporary UI XML could not be created'
  chmod 600 "$UI_DUMP_LOCAL_PATH" ||
    fail_device 'temporary UI XML permissions could not be secured'
  UI_DUMP_ACTIVE=true

  "$ADB_BIN" -s "$ANDROID_SERIAL_VALUE" shell rm -f \
    "$DEVICE_UI_DUMP_PATH" >/dev/null 2>&1 ||
    fail_device 'stale UI XML could not be removed'
  "$ADB_BIN" -s "$ANDROID_SERIAL_VALUE" shell uiautomator dump \
    "$DEVICE_UI_DUMP_PATH" >/dev/null 2>&1 ||
    fail_device 'fresh UI XML dump is unavailable'
  "$ADB_BIN" -s "$ANDROID_SERIAL_VALUE" shell chmod 600 \
    "$DEVICE_UI_DUMP_PATH" >/dev/null 2>&1 ||
    fail_device 'fresh UI XML permissions could not be secured'

  local pipeline_status=0
  "$ADB_BIN" -s "$ANDROID_SERIAL_VALUE" shell cat \
    "$DEVICE_UI_DUMP_PATH" |
    head -c "$((UI_XML_MAX_BYTES + 1))" >"$UI_DUMP_LOCAL_PATH" ||
    pipeline_status=$?
  local byte_count=''
  if ! byte_count="$(wc -c <"$UI_DUMP_LOCAL_PATH" 2>/dev/null |
    tr -d '[:space:]')"; then
    fail_device 'fresh UI XML size is unavailable'
  fi
  [[ "$byte_count" =~ ^[0-9]+$ ]] ||
    fail_device 'fresh UI XML size is invalid'
  (( byte_count > 0 )) || fail_device 'fresh UI XML is empty'
  (( byte_count <= UI_XML_MAX_BYTES )) ||
    fail_device 'fresh UI XML exceeds the size limit'
  (( pipeline_status == 0 )) ||
    fail_device 'fresh UI XML could not be read'
  [[ -f "$UI_DUMP_LOCAL_PATH" && ! -L "$UI_DUMP_LOCAL_PATH" ]] ||
    fail_device 'fresh UI XML is not a regular file'
  chmod 600 "$UI_DUMP_LOCAL_PATH" ||
    fail_device 'temporary UI XML permissions could not be restored'
}

ui_xml_state() {
  python3 - "$UI_DUMP_LOCAL_PATH" "$TARGET_PACKAGE" "$TARGET_ACTIVITY" \
    "$UI_XML_MAX_BYTES" <<'PY'
import sys
import xml.etree.ElementTree as ET
import re
from pathlib import Path


def verdict(value: str) -> None:
    print(value)
    raise SystemExit(0)


try:
    path = Path(sys.argv[1])
    package = sys.argv[2]
    activity = sys.argv[3]
    max_bytes = int(sys.argv[4])
    raw = path.read_bytes()
    if not raw or len(raw) > max_bytes or b"\x00" in raw:
        verdict("INVALID")
    text = raw.decode("utf-8")
    if any(ord(character) < 0x20 and character not in "\r\n\t" for character in text):
        verdict("INVALID")
    root = ET.fromstring(text)
except (OSError, UnicodeDecodeError, ValueError, ET.ParseError, IndexError):
    verdict("INVALID")

if root.tag.rsplit("}", 1)[-1] != "hierarchy":
    verdict("INVALID")
nodes = list(root.iter("node"))
if not nodes:
    verdict("INVALID")

activity_folded = activity.casefold()
root_package = root.attrib.get("package", "").strip()
if root_package and root_package != package:
    verdict("INVALID")
target_nodes = [
    node for node in nodes
    if node.attrib.get("package", "").strip() == package
]
if not target_nodes:
    verdict("INVALID")

# Some UI dump producers include the current activity on the hierarchy root;
# others expose it as a node class. If either form is present, a contradictory
# value is not accepted. The activity-manager foreground check is performed
# separately for dumps that do not carry this optional XML evidence.
activity_attribute_values = []
activity_class_values = []
for element in root.iter():
    for key, value in element.attrib.items():
        key_folded = key.casefold().replace("_", "-")
        value_folded = value.casefold()
        if key_folded in {
            "activity",
            "current-activity",
            "resumed-activity",
            "focused-activity",
            "window",
            "window-name",
        }:
            activity_attribute_values.append(value_folded)
        elif key_folded == "class" and activity_folded in value_folded:
            activity_class_values.append(value_folded)
def activity_matches(value: str) -> bool:
    value = value.strip().rstrip("}")
    return value in {activity_folded, activity_folded.lstrip(".")} or any(
        value.endswith(separator + activity_folded)
        for separator in (".", "/")
    )

if activity_attribute_values and not all(
    activity_matches(value) for value in activity_attribute_values
):
    verdict("INVALID")
if activity_class_values and not all(
    activity_matches(value) for value in activity_class_values
):
    verdict("INVALID")

input_markers = (
    "edittext",
    "otp",
    "one-time",
    "one time",
    "passcode",
    "password",
    "支付密码",
    "验证码",
    "verification code",
    "security code",
    "pin",
)

payment_confirmation_markers = (
    "confirm payment",
    "payment confirmation",
    "pay now",
    "confirm and pay",
    "submit payment",
    "确认支付",
    "立即支付",
    "确认付款",
)

transient_markers = (
    "please wait",
    "please_wait",
    "processing",
    "loading",
    "加载",
    "加载中",
    "处理中",
    "请稍候",
    "稍候",
    "busy",
    "server busy",
    "try again",
    "繁忙",
    "稍后",
    "error",
    "错误",
    "失败",
    "异常",
    "unavailable",
    "timeout",
    "reload",
    "retry",
    "重试",
    "重新加载",
    "刷新",
)

allowed_degraded_labels = {
    "please wait a minute. will be back soon.",
    "reload",
}
allowed_degraded_markers = ("please wait a minute", "reload")
bounds_pattern = re.compile(r"^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$")

def node_labels(node):
    return {
        node.attrib.get(attribute, "").strip().casefold()
        for attribute in ("text", "content-desc")
        if node.attrib.get(attribute, "").strip()
    }

def is_visible_enabled(node: ET.Element) -> bool:
    # API-29 uiautomator may omit visible-to-user for a node that is present
    # in the active window. An explicit false or unknown value still fails.
    visible_value = node.attrib.get('visible-to-user', '')
    if visible_value not in ('', 'true'):
        return False
    return node.attrib.get("enabled") == "true"

def is_noninteractive(node: ET.Element) -> bool:
    return all(
        node.attrib.get(attribute) != "true"
        for attribute in ("clickable", "long-clickable", "focusable")
    )

def is_allowed_degraded_feed(node: ET.Element) -> bool:
    labels = node_labels(node)
    if node.attrib.get("package", "").strip() != package:
        return False
    if not labels or not labels.issubset(allowed_degraded_labels):
        return False
    if not is_visible_enabled(node) or not is_noninteractive(node):
        return False
    match = bounds_pattern.fullmatch(node.attrib.get("bounds", ""))
    if match is None:
        return False
    x1, y1, x2, y2 = (int(value) for value in match.groups())
    return 0 <= x1 < x2 <= 1080 and 1200 <= y1 < y2 <= 1920

normalized = text.casefold()
degraded_nodes = []
for node in nodes:
    labels = node_labels(node)
    values = [
        value.strip().casefold()
        for value in node.attrib.values()
        if value.strip()
    ]
    joined = " ".join(values)
    if "edittext" in node.attrib.get("class", "").casefold() or any(
        marker in joined for marker in input_markers
    ):
        verdict("INVALID")
    if any(
        marker in " ".join(labels) for marker in payment_confirmation_markers
    ):
        verdict("INVALID")
    if any(marker in " ".join(labels) for marker in allowed_degraded_markers):
        if is_allowed_degraded_feed(node):
            degraded_nodes.append(node)
        else:
            verdict("RESET")

# A transient/error label in an unrelated attribute or outside a node is never
# silently ignored. Only the two fixed lower-feed labels may be degraded, and
# only after the target activity and cancel control checks below succeed.
for marker in transient_markers:
    if marker in normalized and not any(
        marker in " ".join(node_labels(node)) for node in degraded_nodes
    ):
        verdict("RESET")

if len(degraded_nodes) > 4:
    verdict("RESET")

def is_cancel_or_back(label: str) -> bool:
    return any(
        token in label
        for token in ("cancel", "back", "取消", "返回")
    )

ready_controls = []
for node in nodes:
    labels = [
        node.attrib.get(attribute, "").strip().casefold()
        for attribute in ("text", "content-desc")
        if node.attrib.get(attribute, "").strip()
    ]
    if not any(is_cancel_or_back(label) for label in labels):
        continue
    if node.attrib.get("package", "").strip() != package:
        verdict("INVALID")
    if node.attrib.get("enabled") != "true":
        continue
    if node.attrib.get("visible-to-user") != "true":
        continue
    if node.attrib.get("clickable") != "true":
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
  if ! state="$(ui_xml_state)"; then
    fail_device 'fresh UI XML could not be validated'
  fi
  case "$state" in
    READY)
      return 0
      ;;
    RESET)
      return 1
      ;;
    *)
      fail_device 'Alipay cashier UI is not safely cancellable'
      ;;
  esac
}

wait_for_stable_cashier() {
  local deadline=$((SECONDS + TARGET_TIMEOUT_SECONDS))
  local stable=0
  while (( SECONDS <= deadline )); do
    if read_cashier_ui_state; then
      stable=$((stable + 1))
      if (( stable >= STABLE_POLLS )); then
        audit "UI_READY::polls=$STABLE_POLLS"
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

send_back_once() {
  (( BACK_COUNT < 2 )) || fail_timeout 'BACK budget exhausted'
  assert_no_marker_before_back
  wait_for_stable_cashier
  assert_no_marker_before_back
  BACK_COUNT=$((BACK_COUNT + 1))
  if ! "$ADB_BIN" -s "$ANDROID_SERIAL_VALUE" shell input keyevent KEYCODE_BACK >/dev/null 2>&1; then
    fail_device 'BACK command failed'
  fi
  audit "KEYCODE_BACK_SENT::attempt=$BACK_COUNT"
  cleanup_ui_dump
}

wait_for_target_to_leave() {
  if (( AFTER_BACK_TIMEOUT_SECONDS == 0 )); then
    return 1
  fi
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

scan_marker_stream() {
  awk -v expected_native="$EXPECTED_NATIVE_MARKER" \
    -v expected_bridge="$EXPECTED_BRIDGE_MARKER" '
    function inspect(line) {
      if (line == expected_native) {
        print "NATIVE_VALID"
      } else if (line ~ /^M5_ALIPAY_NATIVE_RESULT::/) {
        print "NATIVE_INVALID"
      } else if (line == expected_bridge) {
        print "BRIDGE_VALID"
      } else {
        print "BRIDGE_INVALID"
      }
    }
    {
      line = $0
      sub(/\r$/, "", line)
      if (line ~ /^M5_ALIPAY_NATIVE_RESULT::/) {
        inspect(line)
      } else if (line ~ /^[VDIWEF]\/flutter \([[:space:]]*[0-9]+\): M5_ALIPAY_NATIVE_RESULT::/) {
        sub(/^[VDIWEF]\/flutter \([[:space:]]*[0-9]+\): /, "", line)
        inspect(line)
      } else if (line ~ /^M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::/) {
        inspect(line)
      } else if (line ~ /^[VDIWEF]\/flutter \([[:space:]]*[0-9]+\): M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::/) {
        sub(/^[VDIWEF]\/flutter \([[:space:]]*[0-9]+\): /, "", line)
        inspect(line)
      }
    }
  '
}

marker_state_from_file_prefix() {
  local marker_count=0
  local invalid_count=0
  local marker_kind=''
  while IFS= read -r marker_kind; do
    case "$marker_kind" in
      NATIVE_VALID|BRIDGE_VALID)
        marker_count=$((marker_count + 1))
        ;;
      INVALID|NATIVE_INVALID|BRIDGE_INVALID)
        invalid_count=$((invalid_count + 1))
        ;;
    esac
  done < <(
    if (( LOG_BASELINE_BYTES > 0 )); then
      if ! head -c "$LOG_BASELINE_BYTES" "$FLUTTER_LOG_PATH_VALUE" 2>/dev/null |
        scan_marker_stream; then
        printf 'INVALID\n'
      fi
    else
      scan_marker_stream </dev/null
    fi
  )
  if (( invalid_count > 0 )); then
    printf 'INVALID'
  elif (( marker_count > 0 )); then
    printf 'PRESENT'
  else
    printf 'MISSING'
  fi
}

classify_marker_pair() {
  local native_valid_count=0
  local bridge_valid_count=0
  local invalid_count=0
  local marker_kind=''

  # Scan only the raw marker or the exact Android Flutter log envelope. Never
  # print the source line: a malformed line could contain a secret payload.
  local current_bytes=0
  current_bytes="$(wc -c < "$FLUTTER_LOG_PATH_VALUE" 2>/dev/null | tr -d '[:space:]')" || {
    printf 'INVALID'
    return 0
  }
  [[ "$current_bytes" =~ ^[0-9]+$ ]] || {
    printf 'INVALID'
    return 0
  }
  if (( current_bytes < LOG_BASELINE_BYTES )); then
    printf 'INVALID'
    return 0
  fi
  while IFS= read -r marker_kind; do
    case "$marker_kind" in
      NATIVE_VALID)
        native_valid_count=$((native_valid_count + 1))
        ;;
      BRIDGE_VALID)
        bridge_valid_count=$((bridge_valid_count + 1))
        ;;
      INVALID|NATIVE_INVALID|BRIDGE_INVALID)
        invalid_count=$((invalid_count + 1))
        ;;
    esac
  done < <(
    if ! tail -c +$((LOG_BASELINE_BYTES + 1)) "$FLUTTER_LOG_PATH_VALUE" 2>/dev/null |
      scan_marker_stream; then
      printf 'INVALID\n'
    fi
  )

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
  LOG_BASELINE_BYTES="$(wc -c < "$FLUTTER_LOG_PATH_VALUE" 2>/dev/null | tr -d '[:space:]')" ||
    fail_configuration 'private Flutter log size is unavailable'
  [[ "$LOG_BASELINE_BYTES" =~ ^[0-9]+$ ]] ||
    fail_configuration 'private Flutter log size is invalid'
  local state
  state="$(marker_state_from_file_prefix)"
  [[ "$state" == 'MISSING' ]] || fail_marker 'pre-existing native or bridge marker'
  audit "LOG_BASELINE::bytes=$LOG_BASELINE_BYTES"
}

assert_no_marker_before_back() {
  local state
  state="$(classify_marker_pair)"
  if (( BACK_COUNT == 0 )); then
    [[ "$state" == 'MISSING' ]] ||
      fail_marker 'native or bridge marker appeared before BACK'
    return 0
  fi
  # A first BACK may have produced one half of the paired evidence while the
  # cashier is still present. A second BACK remains bounded, but a complete,
  # contradictory, or duplicate pair must never be followed by another key.
  case "$state" in
    MISSING|PARTIAL)
      ;;
    *)
      fail_marker 'native or bridge marker appeared before BACK'
      ;;
  esac
}

wait_for_cancel_marker() {
  local deadline=$((SECONDS + MARKER_TIMEOUT_SECONDS))
  local state=''
  while (( SECONDS <= deadline )); do
    state="$(classify_marker_pair)"
    case "$state" in
      VALID)
        audit 'NATIVE_RESULT_ACCEPTED::resultStatus=6001'
        audit 'BRIDGE_OUTCOME_ACCEPTED::pay_task_returned'
        return 0
        ;;
      INVALID)
        fail_marker 'invalid native result or bridge provenance'
        ;;
      AMBIGUOUS)
        fail_marker 'duplicate native or bridge markers'
        ;;
      PARTIAL|MISSING)
        ;;
    esac
    pause_between_polls
  done
  fail_timeout 'sanitized cancellation marker pair was not observed'
}

main() {
  parse_args "$@"
  validate_serial
  # Environment form is intentionally named separately so the required path
  # remains explicit and no accidental default artifact is accepted.
  validate_log_path
  validate_bounds
  resolve_adb

  audit 'START'
  trap cleanup_on_exit EXIT
  record_marker_baseline
  adb_get_state
  audit 'DEVICE_ONLINE'
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
