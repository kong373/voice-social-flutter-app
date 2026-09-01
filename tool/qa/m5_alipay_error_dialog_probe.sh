#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

# Narrow, cancellation-neutral diagnostic for one already visible Alipay
# sandbox error dialog. It never creates an order, starts Flutter, enters
# text, or confirms payment. The only permitted device write is one dynamic
# device-side click on the exact non-payment dismiss button.

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
readonly PROJECT_ROOT
readonly HELPER_BUILD_SCRIPT="$PROJECT_ROOT/tool/qa/build_alipay_atomic_dialog_helper.sh"
readonly HELPER_SOURCE_FILE="$PROJECT_ROOT/tool/qa/alipay_atomic_dialog/AlipayConfigErrorDismissTest.java"
readonly TARGET_PACKAGE='com.eg.android.AlipayGphoneRC'
readonly TARGET_COMPONENT='com.eg.android.AlipayGphoneRC/com.alipay.android.msp.ui.views.MspContainerActivity'
readonly ERROR_TEXT_ZH='人气太旺啦，稍候再试试。(6)'
readonly DEVICE_UI_DUMP_PATH='/data/local/tmp/voice-social-alipay-error-dialog-ui.xml'
readonly UI_XML_MAX_BYTES=262144
readonly MAX_SHARED_ANCESTOR_DEPTH=3
readonly DEFAULT_DIALOG_TIMEOUT_SECONDS=30
readonly DEFAULT_MARKER_TIMEOUT_SECONDS=30
readonly DEFAULT_POLL_INTERVAL_SECONDS=1
readonly EXIT_CONFIGURATION=64
readonly EXIT_MARKER=65
readonly EXIT_DEVICE=69
readonly EXIT_TIMEOUT=70
readonly EXPECTED_BRIDGE_MARKER='M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::pay_task_returned'
readonly EXPECTED_LAUNCH_MARKER='M5_ALIPAY_FOCUSED::native_launcher::START'
readonly INVOCATION_MARKER_PREFIX='M5_ALIPAY_PROBE_INVOCATION'
readonly ATOMIC_HELPER_MARKER='ALIPAY_ATOMIC_DIALOG_PROBE::DISMISS_CLICKED'
readonly ATOMIC_VERIFY_HELPER_MARKER='ALIPAY_ATOMIC_DIALOG_PROBE::VERIFY_PASSED'
readonly ATOMIC_HELPER_CLASS='com.kong373.voicesocial.qa.AlipayConfigErrorDismissTest#testDismissConfigError'
readonly ATOMIC_VERIFY_HELPER_CLASS='com.kong373.voicesocial.qa.AlipayConfigErrorDismissTest#testVerifyConfigError'
readonly DEVICE_HELPER_PATH='/data/local/tmp/voice-social-alipay-atomic-dialog-helper.jar'

SELF_TEST=false
SERIAL_VALUE=''
SERIAL_ARG=''
FLUTTER_LOG_PATH=''
FLUTTER_LOG_ARG=''
ADB_BIN=''
SDK_ROOT=''
SDK_ROOT_ARG=''
JAVA_HOME_VALUE=''
JAVA_HOME_ARG=''
ATOMIC_HELPER_JAR=''
HELPER_BUILD_DIR=''
INVOCATION_ID=''
INVOCATION_ID_ARG=''
DIALOG_TIMEOUT_SECONDS="$DEFAULT_DIALOG_TIMEOUT_SECONDS"
MARKER_TIMEOUT_SECONDS="$DEFAULT_MARKER_TIMEOUT_SECONDS"
POLL_INTERVAL_SECONDS="$DEFAULT_POLL_INTERVAL_SECONDS"
LOG_BASELINE_BYTES=0
CLICK_COUNT=0
SCREEN_WIDTH=0
SCREEN_HEIGHT=0
UI_DUMP_LOCAL_PATH=''
UI_DUMP_ACTIVE=false
LOCK_PATH=''
LOCK_HELD=false
TAP_COMPLETED=false
MATCH_X=0
MATCH_Y=0
MATCH_ROTATION=''
MATCH_SIGNATURE=''

usage() {
  cat <<'USAGE'
Usage: m5_alipay_error_dialog_probe.sh --serial ID --flutter-log PATH [options]

Handles one already visible Alipay sandbox error dialog. This diagnostic
never creates an order, starts Flutter, enters text, confirms payment, or
discovers devices. It permits at most one dynamically resolved tap on the
exact Chinese dismiss button.

Required:
  --serial ID                 explicit physical-device serial
  --flutter-log PATH          absolute private Flutter log file
  --sdk-root PATH             absolute Android SDK root used for a fresh build
  --java-home PATH            absolute Java home used for a fresh build
  --invocation-id HEX         32 lowercase hex chars bound to this PayTask call

Optional bounded controls:
  --adb PATH                  adb executable (defaults to adb on PATH)
  --dialog-timeout SEC        wait for the safe error dialog (default: 30)
  --marker-timeout SEC        wait for PayTask return markers (default: 30)
  --poll-interval SEC         delay between polls (default: 1; 0 for fixtures)
  --self-test                 run offline parser and marker checks
  --help                      show this help
USAGE
}

fail_configuration() {
  printf 'ALIPAY_ERROR_DIALOG_PROBE: configuration rejected (%s)\n' "$1" >&2
  exit "$EXIT_CONFIGURATION"
}

fail_marker() {
  printf 'ALIPAY_ERROR_DIALOG_PROBE: marker rejected (%s)\n' "$1" >&2
  exit "$EXIT_MARKER"
}

fail_device() {
  printf 'ALIPAY_ERROR_DIALOG_PROBE: device rejected (%s)\n' "$1" >&2
  exit "$EXIT_DEVICE"
}

fail_timeout() {
  printf 'ALIPAY_ERROR_DIALOG_PROBE: bounded wait expired (%s)\n' "$1" >&2
  exit "$EXIT_TIMEOUT"
}

audit() {
  # Fixed vocabulary, counters, and a validated numeric result status only.
  # Never print serials, paths, XML, coordinates, markers, payloads, or adb output.
  printf 'ALIPAY_ERROR_DIALOG_PROBE::%s\n' "$1"
}

require_integer() {
  local name="$1" value="$2"
  [[ "$value" =~ ^[0-9]+$ ]] || fail_configuration "$name must be a non-negative integer"
  (( value <= 600 )) || fail_configuration "$name exceeds the 600 second bound"
}

parse_args() {
  local argument
  while (($# > 0)); do
    argument="$1"
    case "$argument" in
      --help|-h) usage; exit 0 ;;
      --self-test) SELF_TEST=true; shift ;;
      --serial)
        (($# >= 2)) || fail_configuration 'serial is missing'
        [[ -z "$SERIAL_ARG" ]] || fail_configuration 'serial supplied more than once'
        SERIAL_ARG="$2"; SERIAL_VALUE="$2"; shift 2 ;;
      --serial=*)
        [[ -z "$SERIAL_ARG" ]] || fail_configuration 'serial supplied more than once'
        SERIAL_ARG="$(printf '%s' "$argument" | sed 's/^[^=]*=//')"
        SERIAL_VALUE="$SERIAL_ARG"; shift ;;
      --flutter-log)
        (($# >= 2)) || fail_configuration 'Flutter log path is missing'
        [[ -z "$FLUTTER_LOG_ARG" ]] || fail_configuration 'Flutter log path supplied more than once'
        FLUTTER_LOG_ARG="$2"; FLUTTER_LOG_PATH="$2"; shift 2 ;;
      --flutter-log=*)
        [[ -z "$FLUTTER_LOG_ARG" ]] || fail_configuration 'Flutter log path supplied more than once'
        FLUTTER_LOG_ARG="$(printf '%s' "$argument" | sed 's/^[^=]*=//')"
        FLUTTER_LOG_PATH="$FLUTTER_LOG_ARG"; shift ;;
      --adb)
        (($# >= 2)) || fail_configuration 'adb path is missing'
        [[ -z "$ADB_BIN" ]] || fail_configuration 'adb path supplied more than once'
        ADB_BIN="$2"; shift 2 ;;
      --sdk-root)
        (($# >= 2)) || fail_configuration 'Android SDK root is missing'
        [[ -z "$SDK_ROOT_ARG" ]] || fail_configuration 'Android SDK root supplied more than once'
        SDK_ROOT_ARG="$2"; SDK_ROOT="$2"; shift 2 ;;
      --java-home)
        (($# >= 2)) || fail_configuration 'Java home is missing'
        [[ -z "$JAVA_HOME_ARG" ]] || fail_configuration 'Java home supplied more than once'
        JAVA_HOME_ARG="$2"; JAVA_HOME_VALUE="$2"; shift 2 ;;
      --invocation-id)
        (($# >= 2)) || fail_configuration 'invocation ID is missing'
        [[ -z "$INVOCATION_ID_ARG" ]] || fail_configuration 'invocation ID supplied more than once'
        INVOCATION_ID_ARG="$2"; INVOCATION_ID="$2"; shift 2 ;;
      --dialog-timeout)
        (($# >= 2)) || fail_configuration 'dialog timeout is missing'
        DIALOG_TIMEOUT_SECONDS="$2"; shift 2 ;;
      --marker-timeout)
        (($# >= 2)) || fail_configuration 'marker timeout is missing'
        MARKER_TIMEOUT_SECONDS="$2"; shift 2 ;;
      --poll-interval)
        (($# >= 2)) || fail_configuration 'poll interval is missing'
        POLL_INTERVAL_SECONDS="$2"; shift 2 ;;
      *) fail_configuration 'unknown option' ;;
    esac
  done
}

validate_serial() {
  [[ -n "$SERIAL_ARG" ]] || fail_configuration '--serial is required; no default serial is allowed'
  [[ "$SERIAL_VALUE" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$ ]] ||
    fail_configuration 'serial has an unsafe format'
  if [[ "$SERIAL_VALUE" =~ [Ee][Mm][Uu][Ll][Aa][Tt][Oo][Rr] ||
    "$SERIAL_VALUE" =~ [Qq][Ee][Mm][Uu] ]]; then
    fail_configuration 'serial looks like an emulator or qemu target'
  fi
  local inherited_serial
  inherited_serial="$(printenv ANDROID_SERIAL || true)"
  if [[ -n "$inherited_serial" && "$inherited_serial" != "$SERIAL_VALUE" ]]; then
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
  python3 - "$FLUTTER_LOG_PATH" <<'PY' || fail_configuration 'private Flutter log permissions are unsafe'
import os, stat, sys
value = os.stat(sys.argv[1], follow_symlinks=False)
raise SystemExit(0 if value.st_uid == os.getuid() and not (stat.S_IMODE(value.st_mode) & 0o077) else 1)
PY
}

validate_helper_source_attestation() {
  [[ -n "$SDK_ROOT_ARG" ]] || fail_configuration '--sdk-root is required'
  [[ "$SDK_ROOT" == /* && -d "$SDK_ROOT" && ! -L "$SDK_ROOT" &&
    "$SDK_ROOT" != *$'\n'* && "$SDK_ROOT" != *$'\r'* &&
    "$SDK_ROOT" != *$'\t'* && "$SDK_ROOT" != *'..'* ]] ||
    fail_configuration 'Android SDK root is unsafe'
  [[ -n "$JAVA_HOME_ARG" && "$JAVA_HOME_VALUE" == /* && -d "$JAVA_HOME_VALUE" &&
    ! -L "$JAVA_HOME_VALUE" && -x "$JAVA_HOME_VALUE/bin/javac" &&
    -x "$JAVA_HOME_VALUE/bin/jar" && "$JAVA_HOME_VALUE" != *'..'* ]] ||
    fail_configuration 'Java home is unsafe or incomplete'
  [[ -n "$INVOCATION_ID_ARG" && "$INVOCATION_ID" =~ ^[a-f0-9]{32}$ ]] ||
    fail_configuration '--invocation-id must be exactly 32 lowercase hex chars'
  [[ -x "$HELPER_BUILD_SCRIPT" && ! -L "$HELPER_BUILD_SCRIPT" &&
    -f "$HELPER_SOURCE_FILE" && ! -L "$HELPER_SOURCE_FILE" ]] ||
    fail_configuration 'tracked helper sources are unavailable'
  command -v git >/dev/null 2>&1 || fail_configuration 'git is unavailable for source attestation'
  [[ "$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel 2>/dev/null || true)" == "$PROJECT_ROOT" ]] ||
    fail_configuration 'helper source repository authority is unavailable'
  git -C "$PROJECT_ROOT" ls-files --error-unmatch \
    tool/qa/m5_alipay_error_dialog_probe.sh \
    tool/qa/build_alipay_atomic_dialog_helper.sh \
    tool/qa/alipay_atomic_dialog/AlipayConfigErrorDismissTest.java >/dev/null 2>&1 ||
    fail_configuration 'helper sources are not tracked'
  git -C "$PROJECT_ROOT" diff --quiet HEAD -- \
    tool/qa/m5_alipay_error_dialog_probe.sh \
    tool/qa/build_alipay_atomic_dialog_helper.sh \
    tool/qa/alipay_atomic_dialog/AlipayConfigErrorDismissTest.java ||
    fail_configuration 'helper sources differ from the committed checkout'
}

validate_bounds() {
  require_integer dialog-timeout "$DIALOG_TIMEOUT_SECONDS"
  require_integer marker-timeout "$MARKER_TIMEOUT_SECONDS"
  require_integer poll-interval "$POLL_INTERVAL_SECONDS"
}

resolve_adb() {
  if [[ -z "$ADB_BIN" ]]; then ADB_BIN="$(command -v adb || true)"; fi
  [[ -n "$ADB_BIN" && -x "$ADB_BIN" ]] || fail_configuration 'adb executable is unavailable'
  [[ "$ADB_BIN" != *$'\n'* && "$ADB_BIN" != *$'\r'* && "$ADB_BIN" != *$'\t'* ]] ||
    fail_configuration 'adb executable path is unsafe'
  command -v python3 >/dev/null 2>&1 || fail_configuration 'python3 executable is unavailable'
}

pause_between_polls() {
  if (( POLL_INTERVAL_SECONDS > 0 )); then sleep "$POLL_INTERVAL_SECONDS"; fi
}

acquire_serial_lock() {
  LOCK_PATH="/tmp/voice-social-alipay-error-dialog.${SERIAL_VALUE}.lock"
  (umask 077; mkdir -- "$LOCK_PATH" 2>/dev/null) ||
    fail_device 'another probe already holds the serial lock'
  LOCK_HELD=true
}

release_serial_lock() {
  if [[ "$LOCK_HELD" == true && -n "$LOCK_PATH" ]]; then
    rmdir -- "$LOCK_PATH" >/dev/null 2>&1 || true
    LOCK_HELD=false
  fi
}

adb_get_state() {
  local state='' status=0
  state="$($ADB_BIN -s "$SERIAL_VALUE" get-state 2>/dev/null)" || status=$?
  state="$(printf '%s' "$state" | tr -d '\r\n')"
  [[ "$state" != *'offline'* ]] || fail_device 'selected serial is offline'
  [[ "$status" -eq 0 && "$state" == 'device' ]] || fail_device 'selected serial is not online'
}

read_prop() {
  local property="$1" value='' status=0
  value="$($ADB_BIN -s "$SERIAL_VALUE" shell getprop "$property" 2>/dev/null)" || status=$?
  [[ "$status" -eq 0 ]] || fail_device 'device properties are unavailable'
  value="$(printf '%s' "$value" | tr -d '\r\n')"
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* && "$value" != *$'\t'* ]] ||
    fail_device 'device property contains control data'
  printf '%s' "$value"
}

verify_physical_device() {
  local qemu_kernel qemu_boot hardware model product device board metadata qemu_values
  qemu_kernel="$(read_prop ro.kernel.qemu)"; qemu_boot="$(read_prop ro.boot.qemu)"
  hardware="$(read_prop ro.hardware)"; model="$(read_prop ro.product.model)"
  product="$(read_prop ro.product.name)"; device="$(read_prop ro.product.device)"
  board="$(read_prop ro.product.board)"
  qemu_values="$(printf '%s\n' "$qemu_kernel" "$qemu_boot" | tr '[:upper:]' '[:lower:]')"
  [[ "$qemu_values" != *'1'* && "$qemu_values" != *'true'* && "$qemu_values" != *'qemu'* ]] ||
    fail_device 'qemu property is enabled'
  metadata="$(printf '%s\n' "$hardware" "$model" "$product" "$device" "$board" | tr '[:upper:]' '[:lower:]')"
  [[ ! "$metadata" =~ goldfish|ranchu|emulator|simulator|sdk_gphone|generic_x86|generic_x86_64|vbox|qemu ]] ||
    fail_device 'device properties identify an emulator or qemu'
  [[ -n "$hardware$model$product$device$board" ]] || fail_device 'physical identity is unavailable'
  audit 'DEVICE_ONLINE'; audit 'PHYSICAL_DEVICE_VERIFIED'
}

prepare_atomic_helper() {
  "$ADB_BIN" -s "$SERIAL_VALUE" push "$ATOMIC_HELPER_JAR" "$DEVICE_HELPER_PATH" >/dev/null 2>&1 ||
    fail_device 'atomic UiAutomator helper could not be staged'
  "$ADB_BIN" -s "$SERIAL_VALUE" shell chmod 600 "$DEVICE_HELPER_PATH" >/dev/null 2>&1 ||
    fail_device 'atomic UiAutomator helper permissions failed'
}

build_atomic_helper() {
  HELPER_BUILD_DIR="$(mktemp -d /tmp/voice-social-alipay-atomic-helper.XXXXXX)" ||
    fail_configuration 'private helper build directory could not be created'
  chmod 700 "$HELPER_BUILD_DIR" ||
    fail_configuration 'private helper build directory permissions failed'
  ATOMIC_HELPER_JAR="$HELPER_BUILD_DIR/helper.jar"
  "$HELPER_BUILD_SCRIPT" --sdk-root "$SDK_ROOT" --java-home "$JAVA_HOME_VALUE" \
    --output "$ATOMIC_HELPER_JAR" >/dev/null ||
    fail_configuration 'tracked atomic helper build failed'
  [[ -f "$ATOMIC_HELPER_JAR" && ! -L "$ATOMIC_HELPER_JAR" && -r "$ATOMIC_HELPER_JAR" ]] ||
    fail_configuration 'fresh atomic helper jar is unavailable'
  python3 - "$ATOMIC_HELPER_JAR" <<'PY' || fail_configuration 'fresh atomic helper jar permissions are unsafe'
import os, stat, sys
value = os.stat(sys.argv[1], follow_symlinks=False)
raise SystemExit(0 if value.st_uid == os.getuid() and not (stat.S_IMODE(value.st_mode) & 0o077) else 1)
PY
}

cleanup_local_helper() {
  if [[ -n "$ATOMIC_HELPER_JAR" && -f "$ATOMIC_HELPER_JAR" && ! -L "$ATOMIC_HELPER_JAR" ]]; then
    chmod 600 "$ATOMIC_HELPER_JAR" >/dev/null 2>&1 || true
    rm -f -- "$ATOMIC_HELPER_JAR" || true
  fi
  if [[ -n "$HELPER_BUILD_DIR" && -d "$HELPER_BUILD_DIR" && ! -L "$HELPER_BUILD_DIR" ]]; then
    rmdir -- "$HELPER_BUILD_DIR" >/dev/null 2>&1 || true
  fi
  ATOMIC_HELPER_JAR=''; HELPER_BUILD_DIR=''
}

read_screen_size() {
  local raw dimensions='' status=0
  raw="$($ADB_BIN -s "$SERIAL_VALUE" shell wm size 2>/dev/null)" || status=$?
  [[ "$status" -eq 0 ]] || fail_device 'screen size is unavailable'
  dimensions="$(printf '%s\n' "$raw" | awk '
    match($0, /[0-9]+x[0-9]+/) { value=substr($0, RSTART, RLENGTH) }
    END { print value }
  ')"
  [[ "$dimensions" =~ ^[1-9][0-9]{0,4}x[1-9][0-9]{0,4}$ ]] || fail_device 'screen size is invalid'
  SCREEN_WIDTH="$(printf '%s\n' "$dimensions" | cut -d'x' -f1)"
  SCREEN_HEIGHT="$(printf '%s\n' "$dimensions" | cut -d'x' -f2)"
  (( SCREEN_WIDTH > 0 && SCREEN_HEIGHT > 0 )) || fail_device 'screen size is empty'
}

foreground_state() {
  awk -v target="$TARGET_COMPONENT" '
    function normalize_component(value, slash, package, activity) {
      slash = index(value, "/")
      if (slash == 0) return value
      package = substr(value, 1, slash - 1)
      activity = substr(value, slash + 1)
      if (substr(activity, 1, 1) == ".") activity = package activity
      return package "/" activity
    }
    function inspect_component(value, slash, normalized) {
      slash = index(value, "/")
      if (slash == 0) return
      normalized = normalize_component(value)
      if (normalized == target) target_found = 1
      else conflict_found = 1
      component_found = 1
    }
    {
      if ($0 !~ /(^|[[:space:]])(mResumedActivity|ResumedActivity|topResumedActivity|mFocusedApp|mCurrentFocus|mFocusedWindow|mTopActivity|topActivity)(:|=)/) next
      field_found = 1
      remainder = $0
      line_component_found = 0
      while (match(remainder, /[A-Za-z0-9_.$-]+\/[A-Za-z0-9_.$-]+/)) {
        inspect_component(substr(remainder, RSTART, RLENGTH))
        line_component_found = 1
        remainder = substr(remainder, RSTART + RLENGTH)
      }
      if (!line_component_found) missing_component_found = 1
    }
    END {
      if (conflict_found || missing_component_found) print "CONFLICT"
      else if (target_found && field_found && component_found) print "OK"
      else if (field_found) print "WRONG"
      else print "MISSING"
    }
  '
}

read_target_state() {
  local dump='' status=0 state=''
  dump="$($ADB_BIN -s "$SERIAL_VALUE" shell dumpsys activity activities 2>/dev/null)" || status=$?
  [[ "$status" -eq 0 ]] || fail_device 'activity state is unavailable'
  if grep -Eiq '(^|[[:space:]])(device offline|unauthorized|no devices? found)' <<<"$dump"; then
    fail_device 'selected serial became unavailable'
  fi
  state="$(foreground_state <<<"$dump")"
  case "$state" in
    OK) return 0 ;;
    CONFLICT) fail_device 'foreground Activity authority fields conflict' ;;
    WRONG|MISSING) return 1 ;;
    *) fail_device 'foreground Activity state is malformed' ;;
  esac
}

cleanup_ui_dump() {
  if [[ "$TAP_COMPLETED" != true && "$UI_DUMP_ACTIVE" == true &&
    -n "$ADB_BIN" && -n "$SERIAL_VALUE" ]]; then
    "$ADB_BIN" -s "$SERIAL_VALUE" shell rm -f "$DEVICE_UI_DUMP_PATH" >/dev/null 2>&1 || true
  fi
  if [[ -n "$UI_DUMP_LOCAL_PATH" && -f "$UI_DUMP_LOCAL_PATH" && ! -L "$UI_DUMP_LOCAL_PATH" ]]; then
    chmod 600 "$UI_DUMP_LOCAL_PATH" >/dev/null 2>&1 || true
    rm -f -- "$UI_DUMP_LOCAL_PATH" || true
  fi
  UI_DUMP_LOCAL_PATH=''; UI_DUMP_ACTIVE=false
}

cleanup_on_exit() {
  local status=$?
  set +e
  cleanup_ui_dump
  cleanup_local_helper
  release_serial_lock
  trap - EXIT
  exit "$status"
}

capture_fresh_ui_xml() {
  local byte_count='' cat_status=0
  UI_DUMP_LOCAL_PATH="$(mktemp /tmp/voice-social-alipay-error-dialog-ui.XXXXXX)" ||
    fail_device 'temporary UI XML could not be created'
  chmod 600 "$UI_DUMP_LOCAL_PATH" || fail_device 'temporary UI XML permissions failed'
  UI_DUMP_ACTIVE=true
  "$ADB_BIN" -s "$SERIAL_VALUE" shell rm -f "$DEVICE_UI_DUMP_PATH" >/dev/null 2>&1 ||
    fail_device 'stale UI XML could not be removed'
  "$ADB_BIN" -s "$SERIAL_VALUE" shell uiautomator dump "$DEVICE_UI_DUMP_PATH" >/dev/null 2>&1 ||
    fail_device 'fresh UI XML dump is unavailable'
  "$ADB_BIN" -s "$SERIAL_VALUE" shell chmod 600 "$DEVICE_UI_DUMP_PATH" >/dev/null 2>&1 ||
    fail_device 'fresh UI XML permissions could not be secured'
  set +e
  "$ADB_BIN" -s "$SERIAL_VALUE" shell cat "$DEVICE_UI_DUMP_PATH" |
    dd bs="$((UI_XML_MAX_BYTES + 1))" count=1 of="$UI_DUMP_LOCAL_PATH" 2>/dev/null
  cat_status=$?
  set -e
  (( cat_status == 0 )) || fail_device 'fresh UI XML could not be read'
  byte_count="$(wc -c <"$UI_DUMP_LOCAL_PATH" 2>/dev/null | tr -d '[:space:]')" ||
    fail_device 'fresh UI XML size is unavailable'
  [[ "$byte_count" =~ ^[0-9]+$ ]] || fail_device 'fresh UI XML size is invalid'
  (( byte_count > 0 && byte_count <= UI_XML_MAX_BYTES )) || fail_device 'fresh UI XML size is unsafe'
}

ui_dialog_state() {
  python3 - "$UI_DUMP_LOCAL_PATH" "$TARGET_PACKAGE" "$SCREEN_WIDTH" "$SCREEN_HEIGHT" "$UI_XML_MAX_BYTES" "$ERROR_TEXT_ZH" "$MAX_SHARED_ANCESTOR_DEPTH" <<'PY'
import hashlib
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def verdict(value):
    print(value)
    raise SystemExit(0)


try:
    path = Path(sys.argv[1])
    package = sys.argv[2]
    width = int(sys.argv[3])
    height = int(sys.argv[4])
    max_bytes = int(sys.argv[5])
    expected_error = sys.argv[6]
    max_shared_ancestor_depth = int(sys.argv[7])
    raw = path.read_bytes()
    if not raw or len(raw) > max_bytes or b"\x00" in raw:
        verdict("INVALID")
    if b"<!DOCTYPE" in raw.upper() or b"<!ENTITY" in raw.upper():
        verdict("INVALID")
    text = raw.decode("utf-8")
    if any(ord(char) < 0x20 and char not in "\r\n\t" for char in text):
        verdict("INVALID")
    root = ET.fromstring(text)
except (OSError, UnicodeDecodeError, ValueError, ET.ParseError, IndexError):
    verdict("INVALID")


def local_name(value):
    return value.rsplit("}", 1)[-1]


if local_name(root.tag) != "hierarchy":
    verdict("INVALID")
root_package = root.attrib.get("package")
# Android's real uiautomator hierarchy root normally has only `rotation`;
# package authority lives on each node. Accept an absent root package, but
# reject a conflicting value if a vendor build emits one.
if root_package not in {None, "", package}:
    verdict("INVALID")
rotation = root.attrib.get("rotation", "")
if rotation not in {"0", "1", "2", "3"}:
    verdict("INVALID")
if width <= 0 or height <= 0:
    verdict("INVALID")
if max_shared_ancestor_depth < 1 or max_shared_ancestor_depth > 3:
    verdict("INVALID")

nodes = [node for node in root.iter() if local_name(node.tag) == "node"]
if not nodes:
    verdict("INVALID")
if any(node.attrib.get("package") != package for node in nodes):
    verdict("INVALID")
if any(not node.attrib.get("class", "") for node in nodes):
    verdict("INVALID")


def visible(node):
    return node.attrib.get("visible-to-user", "") in {"", "true"}


error_nodes = [
    node
    for node in nodes
    if visible(node)
    and node.attrib.get("class") == "android.widget.TextView"
    and node.attrib.get("text") == expected_error
]
if len(error_nodes) != 1:
    verdict("INVALID")
error_node = error_nodes[0]

button_nodes = [
    node
    for node in nodes
    if node.attrib.get("class") == "android.widget.Button"
    and node.attrib.get("text") == "确定"
]
if len(button_nodes) != 1:
    verdict("INVALID")
button_node = button_nodes[0]
if any(
    node.attrib.get("class") == "android.widget.Button" and node is not button_node
    for node in nodes
):
    verdict("INVALID")
if not visible(button_node):
    verdict("INVALID")
if button_node.attrib.get("enabled") != "true":
    verdict("INVALID")
if button_node.attrib.get("clickable") != "true":
    verdict("INVALID")


dangerous = (
    "confirm payment",
    "payment confirmation",
    "pay now",
    "confirm and pay",
    "submit payment",
    "payment password",
    "password",
    "passcode",
    "otp",
    "security code",
    "pay",
    "payment",
    "付款",
    "支付",
    "充值",
    "密码",
    "验证码",
    "立即支付",
    "确认付款",
    "银行卡",
    "余额",
)
interactive_attributes = (
    "clickable",
    "scrollable",
    "long-clickable",
    "focusable",
    "checkable",
)
for node in nodes:
    node_class = node.attrib.get("class", "")
    folded_class = node_class.casefold()
    if "webview" in folded_class or "edittext" in folded_class or "input" in folded_class:
        verdict("UNSAFE")
    if not (node_class.startswith("android.") or node_class.startswith("androidx.")):
        verdict("UNSAFE")
    # Do not substring-scan resource-id for `pay`: every legitimate resource id
    # may contain the target package name `AlipayGphoneRC`. Interactivity is
    # instead fail-closed below, and all node classes are platform allowlisted.
    for attribute in ("text", "content-desc", "hint"):
        value = node.attrib.get(attribute, "")
        folded = value.casefold()
        if any(fragment in folded for fragment in dangerous):
            verdict("UNSAFE")
    if node is not button_node:
        if node.attrib.get("enabled") == "true" and node.attrib.get("clickable") == "true":
            verdict("UNSAFE")
        if any(node.attrib.get(attribute) == "true" for attribute in interactive_attributes):
            verdict("UNSAFE")


parent_by_id = {}
for parent in root.iter():
    for child in list(parent):
        parent_by_id[id(child)] = parent
allowed_containers = {
    "android.app.Dialog",
    "android.view.ViewGroup",
    "android.widget.ConstraintLayout",
    "android.widget.FrameLayout",
    "android.widget.LinearLayout",
    "android.widget.RelativeLayout",
    "android.widget.TableLayout",
    "android.widget.GridLayout",
    "android.widget.ScrollView",
}


def ancestor_path(node):
    result = []
    current = node
    for depth in range(1, max_shared_ancestor_depth + 1):
        current = parent_by_id.get(id(current))
        if current is None:
            break
        result.append((depth, current))
    return result


error_ancestors = ancestor_path(error_node)
button_ancestors = ancestor_path(button_node)
button_by_id = {id(node): depth for depth, node in button_ancestors}
shared = None
for error_depth, ancestor in error_ancestors:
    button_depth = button_by_id.get(id(ancestor))
    if button_depth is not None:
        shared = (error_depth, button_depth, ancestor)
        break
if shared is None:
    verdict("INVALID")
error_depth, button_depth, common_ancestor = shared
if common_ancestor.attrib.get("class", "") not in allowed_containers:
    verdict("INVALID")
for depth, ancestor in error_ancestors:
    if depth > error_depth:
        break
    if ancestor.attrib.get("package") != package:
        verdict("INVALID")
    if ancestor.attrib.get("class", "") not in allowed_containers:
        verdict("INVALID")
for depth, ancestor in button_ancestors:
    if depth > button_depth:
        break
    if ancestor.attrib.get("package") != package:
        verdict("INVALID")
    if ancestor.attrib.get("class", "") not in allowed_containers:
        verdict("INVALID")


bounds_pattern = re.compile(r"^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$")
match = bounds_pattern.fullmatch(button_node.attrib.get("bounds", ""))
if match is None:
    verdict("INVALID")
x1, y1, x2, y2 = (int(value) for value in match.groups())
if not (0 <= x1 < x2 <= width and 0 <= y1 < y2 <= height):
    verdict("INVALID")
button_width, button_height = x2 - x1, y2 - y1
area = button_width * button_height
if button_width < 2 or button_height < 2:
    verdict("INVALID")
if button_width > width * 0.95 or button_height > height * 0.30:
    verdict("INVALID")
if area > width * height * 0.40:
    verdict("INVALID")


def canonical(node):
    attributes = "".join(
        key + "=" + json.dumps(value, ensure_ascii=False, separators=(",", ":")) + ";"
        for key, value in sorted(node.attrib.items())
    )
    children = "".join(canonical(child) for child in list(node))
    return "<" + local_name(node.tag) + " " + attributes + ">" + children + "</" + local_name(node.tag) + ">"


signature = hashlib.sha256(canonical(root).encode("utf-8")).hexdigest()
center_x = x1 + button_width // 2
center_y = y1 + button_height // 2
print("READY %d %d %s %s" % (center_x, center_y, rotation, signature))
PY
}

consume_snapshot_state() {
  local state="$1" ready_x='' ready_y='' rotation='' signature=''
  if [[ "$state" != READY\ * ]]; then
    SNAPSHOT_STATUS="$state"
    return 0
  fi
  IFS=' ' read -r _ ready_x ready_y rotation signature <<<"$state"
  [[ "$ready_x" =~ ^[0-9]+$ && "$ready_y" =~ ^[0-9]+$ &&
    "$rotation" =~ ^[0-3]$ && "$signature" =~ ^[a-f0-9]{64}$ ]] ||
    fail_device 'stable dialog snapshot fields are invalid'
  SNAPSHOT_STATUS='READY'
  SNAPSHOT_X="$ready_x"
  SNAPSHOT_Y="$ready_y"
  SNAPSHOT_ROTATION="$rotation"
  SNAPSHOT_SIGNATURE="$signature"
}

wait_for_safe_error_dialog() {
  local deadline=$((SECONDS + DIALOG_TIMEOUT_SECONDS)) state=''
  local ready_x='' ready_y=''
  while (( SECONDS <= deadline )); do
    if read_target_state; then
      capture_fresh_ui_xml
      state="$(ui_dialog_state)" || fail_device 'error dialog parser failed'
      cleanup_ui_dump
      read_target_state || fail_device 'foreground Activity changed during dialog snapshot'
      consume_snapshot_state "$state"
      if [[ "$SNAPSHOT_STATUS" == READY ]]; then
        MATCH_X="$SNAPSHOT_X"
        MATCH_Y="$SNAPSHOT_Y"
        MATCH_ROTATION="$SNAPSHOT_ROTATION"
        MATCH_SIGNATURE="$SNAPSHOT_SIGNATURE"
        return 0
      fi
      [[ "$SNAPSHOT_STATUS" != UNSAFE ]] || fail_device 'error dialog contains an unsafe control'
    fi
    pause_between_polls
  done
  fail_timeout 'safe Alipay error dialog was not observed'
}

stabilize_before_tap() {
  local state=''
  for _ in 1 2; do
    read_target_state || fail_device 'Alipay error-dialog activity changed before tap'
    capture_fresh_ui_xml
    state="$(ui_dialog_state)" || fail_device 'stable error dialog parser failed'
    cleanup_ui_dump
    read_target_state || fail_device 'foreground Activity changed during stable snapshot'
    consume_snapshot_state "$state"
    [[ "$SNAPSHOT_STATUS" == READY ]] || fail_device 'error dialog changed before tap'
    [[ "$SNAPSHOT_X" == "$MATCH_X" && "$SNAPSHOT_Y" == "$MATCH_Y" &&
      "$SNAPSHOT_ROTATION" == "$MATCH_ROTATION" &&
      "$SNAPSHOT_SIGNATURE" == "$MATCH_SIGNATURE" ]] ||
      fail_device 'stable dialog UI signature, bounds, or rotation changed'
  done
}

scan_marker_stream() {
  awk -v expected_bridge="$EXPECTED_BRIDGE_MARKER" \
    -v expected_start="$INVOCATION_MARKER_PREFIX::START::$INVOCATION_ID" \
    -v expected_return="$INVOCATION_MARKER_PREFIX::RETURN::$INVOCATION_ID" '
    function strip_flutter_prefix(line) {
      if (line ~ /^[VDIWEF]\/flutter \([[:space:]]*[0-9]+\): /)
        sub(/^[VDIWEF]\/flutter \([[:space:]]*[0-9]+\): /, "", line)
      return line
    }
    {
      line = strip_flutter_prefix($0)
      if (line ~ /^M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::/) {
        if (line == expected_bridge) print "BRIDGE_VALID"
        else print "BRIDGE_INVALID"
        next
      }
      if (line ~ /^M5_ALIPAY_PROBE_INVOCATION::/) {
        if (line == expected_start) print "INVOCATION_START_VALID"
        else if (line == expected_return) print "INVOCATION_RETURN_VALID"
        else print "INVOCATION_INVALID"
        next
      }
      if (line ~ /^M5_ALIPAY_NATIVE_RESULT::/) {
        if (line ~ /^M5_ALIPAY_NATIVE_RESULT::sdkCompleted=0::resultStatus=[0-9][0-9]*$/) {
          code = line
          sub(/^M5_ALIPAY_NATIVE_RESULT::sdkCompleted=0::resultStatus=/, "", code)
          if (length(code) >= 1 && length(code) <= 6 && code + 0 > 0 && code + 0 != 9000)
            print "NATIVE_VALID " code
          else print "NATIVE_INVALID"
        } else print "NATIVE_INVALID"
      }
    }
  '
}

marker_state_from_prefix() {
  local kind seen=0
  while IFS=' ' read -r kind _; do
    case "$kind" in
      BRIDGE_VALID|BRIDGE_INVALID|NATIVE_VALID|NATIVE_INVALID|INVOCATION_RETURN_VALID|INVOCATION_INVALID)
        seen=$((seen + 1)) ;;
    esac
  done < <(head -c "$LOG_BASELINE_BYTES" "$FLUTTER_LOG_PATH" 2>/dev/null | scan_marker_stream || true)
  if (( seen > 0 )); then printf 'PRESENT'; else printf 'MISSING'; fi
}

classify_appended_markers() {
  local current_bytes kind code bridge=0 native=0 invocation_return=0 invalid=0 result_status=''
  current_bytes="$(wc -c <"$FLUTTER_LOG_PATH" 2>/dev/null | tr -d '[:space:]')" || { printf INVALID; return; }
  [[ "$current_bytes" =~ ^[0-9]+$ && "$current_bytes" -ge "$LOG_BASELINE_BYTES" ]] || { printf INVALID; return; }
  while IFS=' ' read -r kind code; do
    case "$kind" in
      BRIDGE_VALID) bridge=$((bridge + 1)) ;;
      INVOCATION_RETURN_VALID) invocation_return=$((invocation_return + 1)) ;;
      BRIDGE_INVALID|NATIVE_INVALID|INVOCATION_INVALID|INVOCATION_START_VALID)
        invalid=$((invalid + 1)) ;;
      NATIVE_VALID)
        native=$((native + 1))
        result_status="$code"
        ;;
    esac
  done < <(tail -c +$((LOG_BASELINE_BYTES + 1)) "$FLUTTER_LOG_PATH" 2>/dev/null | scan_marker_stream || true)
  if (( invalid > 0 )); then printf 'INVALID'
  elif (( bridge > 1 || native > 1 || invocation_return > 1 )); then printf 'AMBIGUOUS'
  elif (( bridge == 1 && native == 1 && invocation_return == 1 )); then printf 'RETURNED %s' "$result_status"
  else printf 'MISSING'
  fi
}

record_marker_baseline() {
  local launch_count='' invocation_start_count='' invocation_total_count=''
  LOG_BASELINE_BYTES="$(wc -c <"$FLUTTER_LOG_PATH" 2>/dev/null | tr -d '[:space:]')" ||
    fail_configuration 'private Flutter log size is unavailable'
  [[ "$LOG_BASELINE_BYTES" =~ ^[0-9]+$ ]] || fail_configuration 'private Flutter log size is invalid'
  [[ "$(marker_state_from_prefix)" == MISSING ]] || fail_marker 'stale PayTask marker before this run'
  launch_count="$(head -c "$LOG_BASELINE_BYTES" "$FLUTTER_LOG_PATH" 2>/dev/null |
    grep -Fxc -- "$EXPECTED_LAUNCH_MARKER" || true)"
  [[ "$launch_count" == 1 ]] || fail_marker 'current PayTask invocation start marker is missing or duplicated'
  invocation_start_count="$(head -c "$LOG_BASELINE_BYTES" "$FLUTTER_LOG_PATH" 2>/dev/null |
    grep -Fxc -- "$INVOCATION_MARKER_PREFIX::START::$INVOCATION_ID" || true)"
  invocation_total_count="$(head -c "$LOG_BASELINE_BYTES" "$FLUTTER_LOG_PATH" 2>/dev/null |
    grep -Ec '^M5_ALIPAY_PROBE_INVOCATION::' || true)"
  [[ "$invocation_start_count" == 1 && "$invocation_total_count" == 1 ]] ||
    fail_marker 'PayTask invocation token is missing, duplicated, or mismatched'
}

assert_no_marker_before_tap() {
  [[ "$(classify_appended_markers)" == MISSING ]] ||
    fail_marker 'PayTask marker appeared before the diagnostic tap'
}

wait_for_paytask_return() {
  local deadline=$((SECONDS + MARKER_TIMEOUT_SECONDS)) state='' result_status=''
  while (( SECONDS <= deadline )); do
    state="$(classify_appended_markers)"
    case "$state" in
      RETURNED\ *)
        result_status="${state#RETURNED }"
        [[ "$result_status" =~ ^[0-9]{1,6}$ && "$result_status" != 9000 && "$result_status" != 0* ]] ||
          fail_marker 'native result status is not a safe numeric error code'
        audit "PAYTASK_RETURNED::resultStatus=$result_status"
        return 0
        ;;
      INVALID) fail_marker 'success, malformed, or contradictory native marker' ;;
      AMBIGUOUS) fail_marker 'duplicate PayTask return markers' ;;
      MISSING) : ;;
    esac
    pause_between_polls
  done
  fail_timeout 'PayTask return markers were not observed'
}

validate_atomic_helper_output() {
  local output="$1" expected_marker="$2" phase="$3"
  local normalized marker_count summary_count failure_count
  # UiAutomator writes the complete JUnit report and Java System.out to the
  # remote stderr stream. Normalize only CRLF; never print or persist the
  # report because it can contain vendor diagnostics outside this allowlist.
  normalized="$(printf '%s\n' "$output" | tr -d '\r')"
  failure_count="$(printf '%s\n' "$normalized" | grep -Eic \
    '(^|[^[:alnum:]_])(FAILURES!!!|FAILURES|Failure|INSTRUMENTATION_FAILED|Exception|Throwable|AssertionError|Stack trace)([^[:alnum:]_]|$)|INSTRUMENTATION_STATUS_CODE:[[:space:]]*-[0-9]+' || true)"
  [[ "$failure_count" == 0 ]] ||
    fail_device "atomic UiAutomator $phase report contains a failure"
  # UiAutomator may carry Java System.out through an exact instrumentation
  # stream line instead of emitting a bare line. Accept only those two
  # complete-line forms; never substring-match a stack trace or arbitrary
  # diagnostic text.
  marker_count="$(printf '%s\n' "$normalized" | awk -v expected="$expected_marker" '
    {
      if ($0 == expected) count++
      else if (index($0, "INSTRUMENTATION_STATUS: stream=") == 1 &&
          substr($0, length("INSTRUMENTATION_STATUS: stream=") + 1) == expected) count++
    }
    END { print count + 0 }
  ')"
  [[ "$marker_count" == 1 ]] ||
    fail_device "atomic UiAutomator $phase marker is missing or duplicated"
  summary_count="$(printf '%s\n' "$normalized" | awk '
    {
      if ($0 == "OK (1 test)") count++
      else if (index($0, "INSTRUMENTATION_STATUS: stream=") == 1 &&
          substr($0, length("INSTRUMENTATION_STATUS: stream=") + 1) == "OK (1 test)") count++
    }
    END { print count + 0 }
  ')"
  [[ "$summary_count" == 1 ]] ||
    fail_device "atomic UiAutomator $phase success summary is missing or duplicated"
}

invoke_verify_helper() {
  local output='' status=0
  set +e
  output="$("$ADB_BIN" -s "$SERIAL_VALUE" shell uiautomator runtest \
    "$DEVICE_HELPER_PATH" -c "$ATOMIC_VERIFY_HELPER_CLASS" 2>&1)"
  status=$?
  set -e
  # Parse the merged stream before considering rc: runtest can return zero
  # while reporting a failed JUnit invocation.
  validate_atomic_helper_output "$output" "$ATOMIC_VERIFY_HELPER_MARKER" 'verify'
  [[ "$status" -eq 0 ]] || fail_device 'atomic UiAutomator verify helper exited unsuccessfully'
  audit 'DIALOG_VERIFY_PASSED'
}

invoke_atomic_helper() {
  local output='' status=0 marker_count=''
  (( CLICK_COUNT == 0 )) || fail_device 'dismiss action budget already consumed'
  # The final adb command performs the fresh selector verification and the
  # related UiObject click in one device-side UiAutomator process. Mark this
  # phase first so EXIT cleanup can never issue another device command after
  # a possible click.
  TAP_COMPLETED=true
  set +e
  output="$("$ADB_BIN" -s "$SERIAL_VALUE" shell uiautomator runtest \
    "$DEVICE_HELPER_PATH" -c "$ATOMIC_HELPER_CLASS" 2>&1)"
  status=$?
  set -e
  # The helper's click is the final device operation. Validate the already
  # captured merged output locally; no adb command follows this invocation.
  validate_atomic_helper_output "$output" "$ATOMIC_HELPER_MARKER" 'click'
  [[ "$status" -eq 0 ]] || fail_device 'atomic UiAutomator helper exited unsuccessfully'
  CLICK_COUNT=1
  audit 'DISMISS_BUTTON_TAPPED::count=1'
}

probe_self_test() {
  (
    set -Eeuo pipefail
    local root ui state
    root="$(mktemp -d /tmp/voice-social-alipay-error-dialog-self-test.XXXXXX)"
    trap 'rm -rf -- "$root"' EXIT
    ui="$root/ui.xml"
    INVOCATION_ID='0123456789abcdef0123456789abcdef'
    SCREEN_WIDTH=1080; SCREEN_HEIGHT=1920
    printf '%s\n' '<hierarchy rotation="0"><node package="com.eg.android.AlipayGphoneRC" class="android.widget.LinearLayout"><node package="com.eg.android.AlipayGphoneRC" class="android.widget.TextView" text="人气太旺啦，稍候再试试。(6)" /><node package="com.eg.android.AlipayGphoneRC" class="android.widget.Button" text="确定" enabled="true" clickable="true" bounds="[400,900][680,1020]" /></node></hierarchy>' >"$ui"
    UI_DUMP_LOCAL_PATH="$ui"; state="$(ui_dialog_state)"; [[ "$state" == READY\ 540\ 960\ 0\ * ]] || exit 1
    sed 's/人气太旺啦，稍候再试试。(6)/人气太旺啦，稍候再试试。 (6)/' "$ui" >"$root/strict-text.xml"
    UI_DUMP_LOCAL_PATH="$root/strict-text.xml"; [[ "$(ui_dialog_state)" == INVALID ]] || exit 1
    sed 's/com.eg.android.AlipayGphoneRC/com.other.wallet/g' "$ui" >"$root/wrong-package.xml"
    UI_DUMP_LOCAL_PATH="$root/wrong-package.xml"; [[ "$(ui_dialog_state)" == INVALID ]] || exit 1
    sed 's/人气太旺啦，稍候再试试。(6)/其他提示/' "$ui" >"$root/wrong-text.xml"
    UI_DUMP_LOCAL_PATH="$root/wrong-text.xml"; [[ "$(ui_dialog_state)" == INVALID ]] || exit 1
    sed 's#</node></hierarchy>#<node package="com.eg.android.AlipayGphoneRC" class="android.widget.Button" text="关闭" enabled="true" clickable="true" bounds="[400,1100][680,1220]" /></node></hierarchy>#' "$ui" >"$root/multiple-buttons.xml"
    UI_DUMP_LOCAL_PATH="$root/multiple-buttons.xml"; state="$(ui_dialog_state)"; [[ "$state" == INVALID || "$state" == UNSAFE ]] || exit 1
    sed 's#</node></hierarchy>#<node package="com.eg.android.AlipayGphoneRC" class="android.widget.Button" text="确认支付" enabled="true" clickable="true" bounds="[400,1100][680,1220]" /></node></hierarchy>#' "$ui" >"$root/payment-button.xml"
    UI_DUMP_LOCAL_PATH="$root/payment-button.xml"; state="$(ui_dialog_state)"; [[ "$state" == INVALID || "$state" == UNSAFE ]] || exit 1
    sed 's/\[400,900\]\[680,1020\]/[0,0][1200,2100]/' "$ui" >"$root/bad-bounds.xml"
    UI_DUMP_LOCAL_PATH="$root/bad-bounds.xml"; [[ "$(ui_dialog_state)" == INVALID ]] || exit 1
    FLUTTER_LOG_PATH="$root/flutter.log"; printf '%s\n%s\n' "$EXPECTED_LAUNCH_MARKER" "$INVOCATION_MARKER_PREFIX::START::$INVOCATION_ID" >"$FLUTTER_LOG_PATH"; LOG_BASELINE_BYTES=0
    record_marker_baseline
    printf '%s\n%s\n%s\n' "$INVOCATION_MARKER_PREFIX::RETURN::$INVOCATION_ID" 'M5_ALIPAY_NATIVE_RESULT::sdkCompleted=0::resultStatus=4000' "$EXPECTED_BRIDGE_MARKER" >>"$FLUTTER_LOG_PATH"
    [[ "$(classify_appended_markers)" == 'RETURNED 4000' ]] || exit 1
    printf '%s\n%s\n' "$EXPECTED_LAUNCH_MARKER" "$INVOCATION_MARKER_PREFIX::START::$INVOCATION_ID" >"$FLUTTER_LOG_PATH"; record_marker_baseline
    printf '%s\n%s\n%s\n' "$INVOCATION_MARKER_PREFIX::RETURN::$INVOCATION_ID" 'M5_ALIPAY_NATIVE_RESULT::sdkCompleted=1::resultStatus=9000' "$EXPECTED_BRIDGE_MARKER" >>"$FLUTTER_LOG_PATH"
    [[ "$(classify_appended_markers)" == INVALID ]] || exit 1
    printf '%s\n%s\n' "$EXPECTED_LAUNCH_MARKER" "$INVOCATION_MARKER_PREFIX::START::$INVOCATION_ID" >"$FLUTTER_LOG_PATH"; record_marker_baseline
    printf '%s\n%s\n%s\n%s\n' "$INVOCATION_MARKER_PREFIX::RETURN::$INVOCATION_ID" 'M5_ALIPAY_NATIVE_RESULT::sdkCompleted=0::resultStatus=4000' 'M5_ALIPAY_NATIVE_RESULT::sdkCompleted=0::resultStatus=4000' "$EXPECTED_BRIDGE_MARKER" >>"$FLUTTER_LOG_PATH"
    [[ "$(classify_appended_markers)" == AMBIGUOUS ]] || exit 1
    audit 'PARSER_FAIL_CLOSED_PASS'; audit 'MARKER_FAIL_CLOSED_PASS'; audit 'SELF_TEST_PASS'
  )
  printf 'SELF_TEST::PASS\n'
}

main() {
  parse_args "$@"
  if [[ "$SELF_TEST" == true ]]; then probe_self_test; exit 0; fi
  validate_serial; validate_log_path; validate_helper_source_attestation; validate_bounds; resolve_adb
  trap cleanup_on_exit EXIT
  acquire_serial_lock
  adb_get_state
  verify_physical_device
  read_screen_size
  read_target_state || fail_device 'Alipay error-dialog activity is not foreground'
  wait_for_safe_error_dialog
  audit 'ERROR_DIALOG_MATCHED'
  stabilize_before_tap
  # Build and stage only after the host-side UI gates have passed. The helper
  # still revalidates the live accessibility objects immediately before click.
  build_atomic_helper
  prepare_atomic_helper
    record_marker_baseline
    assert_no_marker_before_tap
    invoke_verify_helper
    assert_no_marker_before_tap
    # Re-snapshot the live foreground and UI after the read-only device-side
    # verification. The click helper is launched only after this fresh,
    # stable host-side check passes.
    stabilize_before_tap
    assert_no_marker_before_tap
    invoke_atomic_helper
  # No device operation occurs after the tap; only the private Flutter log is read.
  wait_for_paytask_return
  audit 'PASS'
}

main "$@"
