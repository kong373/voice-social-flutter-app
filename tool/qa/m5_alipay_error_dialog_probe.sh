#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

# Narrow, cancellation-neutral diagnostic for one already visible Alipay
# sandbox error dialog. It never creates an order, starts Flutter, enters
# text, or confirms payment. The only permitted device write is one dynamic
# tap on a non-payment dismiss button.

readonly TARGET_PACKAGE='com.eg.android.AlipayGphoneRC'
readonly TARGET_COMPONENT='com.eg.android.AlipayGphoneRC/com.alipay.android.msp.ui.views.MspContainerActivity'
readonly ERROR_TEXT_ZH='人气太旺啦，稍候再试试。(6)'
readonly ERROR_TEXT_EN='Server busy, please try again. (6)'
readonly ERROR_TEXT_EN_ALT='Server busy, please try again later. (6)'
readonly ERROR_TEXT_EN_ALT2='It is busy right now, please try again later. (6)'
readonly ERROR_TEXT_EN_ALT3='Too many people are paying, please try again later. (6)'
readonly DEVICE_UI_DUMP_PATH='/data/local/tmp/voice-social-alipay-error-dialog-ui.xml'
readonly UI_XML_MAX_BYTES=262144
readonly DEFAULT_DIALOG_TIMEOUT_SECONDS=30
readonly DEFAULT_MARKER_TIMEOUT_SECONDS=30
readonly DEFAULT_POLL_INTERVAL_SECONDS=1
readonly EXIT_CONFIGURATION=64
readonly EXIT_MARKER=65
readonly EXIT_DEVICE=69
readonly EXIT_TIMEOUT=70
readonly EXPECTED_BRIDGE_MARKER='M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::pay_task_returned'
readonly REJECTED_SUCCESS_MARKER='M5_ALIPAY_NATIVE_RESULT::sdkCompleted=1::resultStatus=9000'

SELF_TEST=false
SERIAL_VALUE=''
SERIAL_ARG=''
FLUTTER_LOG_PATH=''
FLUTTER_LOG_ARG=''
ADB_BIN=''
DIALOG_TIMEOUT_SECONDS="$DEFAULT_DIALOG_TIMEOUT_SECONDS"
MARKER_TIMEOUT_SECONDS="$DEFAULT_MARKER_TIMEOUT_SECONDS"
POLL_INTERVAL_SECONDS="$DEFAULT_POLL_INTERVAL_SECONDS"
LOG_BASELINE_BYTES=0
CLICK_COUNT=0
SCREEN_WIDTH=0
SCREEN_HEIGHT=0
UI_DUMP_LOCAL_PATH=''
UI_DUMP_ACTIVE=false

usage() {
  cat <<'USAGE'
Usage: m5_alipay_error_dialog_probe.sh --serial ID --flutter-log PATH [options]

Handles one already visible Alipay sandbox error dialog. This diagnostic
never creates an order, starts Flutter, enters text, confirms payment, or
discovers devices. It permits at most one dynamically resolved tap on a
non-payment dismiss button.

Required:
  --serial ID                 explicit physical-device serial
  --flutter-log PATH          absolute private Flutter log file

Optional bounded controls:
  --adb PATH                  adb executable (defaults to adb on PATH)
  --dialog-timeout SEC        wait for the safe error dialog (default: 30)
  --marker-timeout SEC        wait for PayTask return marker (default: 30)
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
  # Fixed vocabulary and counters only. Never print serials, paths, XML,
  # coordinates, markers, provider payloads, inherited env values, or adb output.
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
foreground_is_target() {
  awk -v target="$TARGET_COMPONENT" '
    /(^|[[:space:]])(mResumedActivity|ResumedActivity|topResumedActivity|mFocusedApp):/ {
      offset = index($0, target)
      while (offset > 0) {
        before = (offset == 1) ? "" : substr($0, offset - 1, 1)
        after = substr($0, offset + length(target), 1)
        if ((before == "" || before == " " || before == "{") &&
            (after == "" || after == " " || after == "}")) found = 1
        remainder = substr($0, offset + 1)
        next_offset = index(remainder, target)
        if (next_offset == 0) break
        offset = offset + next_offset
      }
    }
    END { exit(found ? 0 : 1) }
  '
}
read_target_state() {
  local dump='' status=0
  dump="$($ADB_BIN -s "$SERIAL_VALUE" shell dumpsys activity activities 2>/dev/null)" || status=$?
  [[ "$status" -eq 0 ]] || fail_device 'activity state is unavailable'
  if grep -Eiq '(^|[[:space:]])(device offline|unauthorized|no devices? found)' <<<"$dump"; then
    fail_device 'selected serial became unavailable'
  fi
  foreground_is_target <<<"$dump"
}
cleanup_ui_dump() {
  if [[ "$UI_DUMP_ACTIVE" == true && -n "$ADB_BIN" && -n "$SERIAL_VALUE" ]]; then
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
  set +e; cleanup_ui_dump; trap - EXIT; exit "$status"
}
capture_fresh_ui_xml() {
  local byte_count=''
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
  set -e
  byte_count="$(wc -c <"$UI_DUMP_LOCAL_PATH" 2>/dev/null | tr -d '[:space:]')" ||
    fail_device 'fresh UI XML size is unavailable'
  [[ "$byte_count" =~ ^[0-9]+$ ]] || fail_device 'fresh UI XML size is invalid'
  (( byte_count > 0 && byte_count <= UI_XML_MAX_BYTES )) || fail_device 'fresh UI XML size is unsafe'
}
ui_dialog_state() {
  python3 - "$UI_DUMP_LOCAL_PATH" "$TARGET_PACKAGE" "$SCREEN_WIDTH" "$SCREEN_HEIGHT" "$UI_XML_MAX_BYTES" \
    "$ERROR_TEXT_ZH" "$ERROR_TEXT_EN" "$ERROR_TEXT_EN_ALT" "$ERROR_TEXT_EN_ALT2" "$ERROR_TEXT_EN_ALT3" <<'PY'
import re, sys, unicodedata
import xml.etree.ElementTree as ET
from pathlib import Path

def verdict(value):
    print(value)
    raise SystemExit(0)

try:
    path = Path(sys.argv[1]); package = sys.argv[2]
    width = int(sys.argv[3]); height = int(sys.argv[4]); max_bytes = int(sys.argv[5])
    errors = {unicodedata.normalize("NFKC", value).casefold() for value in sys.argv[6:]}
    raw = path.read_bytes()
    if not raw or len(raw) > max_bytes or b"\x00" in raw: verdict("INVALID")
    text = raw.decode("utf-8")
    if any(ord(char) < 0x20 and char not in "\r\n\t" for char in text): verdict("INVALID")
    root = ET.fromstring(text)
except (OSError, UnicodeDecodeError, ValueError, ET.ParseError, IndexError):
    verdict("INVALID")

if root.tag.rsplit("}", 1)[-1] != "hierarchy":
    verdict("INVALID")
root_package = root.attrib.get("package", "").strip()
if root_package and root_package != package:
    verdict("INVALID")
if width <= 0 or height <= 0: verdict("INVALID")
nodes = [node for node in root.iter() if node.tag.rsplit("}", 1)[-1] == "node"]
if not nodes or any(node.attrib.get("package", "").strip() != package for node in nodes):
    verdict("INVALID")

def normalized(value):
    return re.sub(r"\s+", " ", unicodedata.normalize("NFKC", value).strip().casefold())
def labels(node):
    return {normalized(node.attrib.get(name, "")) for name in ("text", "content-desc") if node.attrib.get(name, "").strip()}

def is_visible(node):
    # Android 16's real `uiautomator dump` omits visible-to-user.  The dump is
    # already scoped to the foreground hierarchy, so absence is acceptable;
    # an explicit false value remains fail-closed.
    return node.attrib.get("visible-to-user", "") in ("", "true")

errors = {normalized(value) for value in errors}
error_nodes = [node for node in nodes if is_visible(node) and labels(node) & errors]
if len(error_nodes) != 1: verdict("INVALID")

dangerous = (
    "confirm payment", "payment confirmation", "pay now", "confirm and pay",
    "submit payment", "payment password", "password", "passcode", "otp",
    "security code", "pay", "payment", "付款", "支付", "充值", "密码",
    "验证码", "立即支付", "确认付款", "银行卡", "余额",
)
for node in nodes:
    values = labels(node); node_class = node.attrib.get("class", "").casefold()
    if "edittext" in node_class or "input" in node_class: verdict("UNSAFE")
    if any(fragment in value for value in values for fragment in dangerous): verdict("UNSAFE")

safe_labels = {
    "确定", "关闭", "取消", "返回", "知道了", "我知道了",
    "ok", "close", "cancel", "back", "got it", "dismiss", "done",
}
bounds_pattern = re.compile(r"^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$")
def valid_bounds(node):
    match = bounds_pattern.fullmatch(node.attrib.get("bounds", ""))
    if match is None: return None
    x1, y1, x2, y2 = (int(value) for value in match.groups())
    if not (0 <= x1 < x2 <= width and 0 <= y1 < y2 <= height): return None
    button_width, button_height = x2 - x1, y2 - y1
    area = button_width * button_height
    if button_width < 2 or button_height < 2 or button_width > width * 0.95: return None
    if button_height > height * 0.30 or area > width * height * 0.40: return None
    return (x1, y1, x2, y2)

close_nodes = []
for node in nodes:
    if not is_visible(node) or node.attrib.get("enabled") != "true":
        continue
    if node.attrib.get("clickable") != "true" or not labels(node) & safe_labels:
        continue
    bounds = valid_bounds(node)
    if bounds is None: verdict("INVALID")
    close_nodes.append(bounds)
if len(close_nodes) != 1: verdict("INVALID")
x1, y1, x2, y2 = close_nodes[0]
print("READY %d %d" % (x1 + (x2 - x1) // 2, y1 + (y2 - y1) // 2))
PY
}
wait_for_safe_error_dialog() {
  local deadline=$((SECONDS + DIALOG_TIMEOUT_SECONDS)) state='' ready_x ready_y
  while (( SECONDS <= deadline )); do
    if read_target_state; then
      capture_fresh_ui_xml
      state="$(ui_dialog_state)" || fail_device 'error dialog parser failed'
      cleanup_ui_dump
      if [[ "$state" == READY\ * ]]; then
        ready_x="$(printf '%s\n' "$state" | awk '{print $2}')"
        ready_y="$(printf '%s\n' "$state" | awk '{print $3}')"
        [[ "$ready_x" =~ ^[0-9]+$ && "$ready_y" =~ ^[0-9]+$ ]] || fail_device 'dismiss bounds are invalid'
        printf '%s %s\n' "$ready_x" "$ready_y"
        return 0
      fi
      [[ "$state" != UNSAFE ]] || fail_device 'error dialog contains an unsafe control'
    fi
    pause_between_polls
  done
  fail_timeout 'safe Alipay error dialog was not observed'
}
scan_marker_stream() {
  awk -v expected_bridge="$EXPECTED_BRIDGE_MARKER" -v rejected_success="$REJECTED_SUCCESS_MARKER" '
    function inspect(line) {
      sub(/\r$/, "", line)
      if (line == expected_bridge) print "BRIDGE_VALID"
      else if (line == rejected_success) print "SUCCESS_REJECTED"
      else if (line ~ /^M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::/) print "BRIDGE_INVALID"
      else if (line ~ /^M5_ALIPAY_NATIVE_RESULT::/) print "NATIVE_RESULT"
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
marker_state_from_prefix() {
  local kind seen=0
  while IFS= read -r kind; do
    case "$kind" in
      BRIDGE_VALID|SUCCESS_REJECTED|BRIDGE_INVALID) seen=$((seen + 1)) ;;
    esac
  done < <(head -c "$LOG_BASELINE_BYTES" "$FLUTTER_LOG_PATH" 2>/dev/null | scan_marker_stream || true)
  if (( seen > 0 )); then printf 'PRESENT'; else printf 'MISSING'; fi
}
classify_appended_markers() {
  local current_bytes kind bridge=0 invalid=0
  current_bytes="$(wc -c <"$FLUTTER_LOG_PATH" 2>/dev/null | tr -d '[:space:]')" || { printf INVALID; return; }
  [[ "$current_bytes" =~ ^[0-9]+$ && "$current_bytes" -ge "$LOG_BASELINE_BYTES" ]] || { printf INVALID; return; }
  while IFS= read -r kind; do
    case "$kind" in
      BRIDGE_VALID) bridge=$((bridge + 1)) ;;
      BRIDGE_INVALID|SUCCESS_REJECTED) invalid=$((invalid + 1)) ;;
      NATIVE_RESULT) : ;;
    esac
  done < <(tail -c +$((LOG_BASELINE_BYTES + 1)) "$FLUTTER_LOG_PATH" 2>/dev/null | scan_marker_stream || true)
  if (( invalid > 0 )); then printf INVALID
  elif (( bridge > 1 )); then printf AMBIGUOUS
  elif (( bridge == 1 )); then printf RETURNED
  else printf MISSING
  fi
}
record_marker_baseline() {
  LOG_BASELINE_BYTES="$(wc -c <"$FLUTTER_LOG_PATH" 2>/dev/null | tr -d '[:space:]')" ||
    fail_configuration 'private Flutter log size is unavailable'
  [[ "$LOG_BASELINE_BYTES" =~ ^[0-9]+$ ]] || fail_configuration 'private Flutter log size is invalid'
  [[ "$(marker_state_from_prefix)" == MISSING ]] || fail_marker 'stale PayTask marker before this run'
}
assert_no_marker_before_tap() {
  [[ "$(classify_appended_markers)" == MISSING ]] || fail_marker 'PayTask marker appeared before the diagnostic tap'
}
wait_for_paytask_return() {
  local deadline=$((SECONDS + MARKER_TIMEOUT_SECONDS)) state=''
  while (( SECONDS <= deadline )); do
    state="$(classify_appended_markers)"
    case "$state" in
      RETURNED) audit 'PAYTASK_RETURNED'; return 0 ;;
      INVALID) fail_marker 'success, malformed, or contradictory native marker' ;;
      AMBIGUOUS) fail_marker 'duplicate PayTask return markers' ;;
      MISSING) : ;;
    esac
    pause_between_polls
  done
  fail_timeout 'PayTask return marker was not observed'
}
probe_self_test() {
  (
    set -Eeuo pipefail
    local root ui state
    root="$(mktemp -d /tmp/voice-social-alipay-error-dialog-self-test.XXXXXX)"
    trap 'rm -rf -- "$root"' EXIT
    ui="$root/ui.xml"
    SCREEN_WIDTH=1080; SCREEN_HEIGHT=1920
    printf '%s\n' '<hierarchy rotation="0"><node package="com.eg.android.AlipayGphoneRC" class="android.widget.TextView" text="人气太旺啦，稍候再试试。(6)" /><node package="com.eg.android.AlipayGphoneRC" class="android.widget.Button" text="确定" enabled="true" clickable="true" bounds="[400,900][680,1020]" /></hierarchy>' >"$ui"
    UI_DUMP_LOCAL_PATH="$ui"; state="$(ui_dialog_state)"; [[ "$state" == 'READY 540 960' ]] || exit 1
    sed 's/人气太旺啦，稍候再试试。(6)/Server busy, please try again later. (6)/' "$ui" >"$root/english.xml"
    UI_DUMP_LOCAL_PATH="$root/english.xml"; [[ "$(ui_dialog_state)" == 'READY 540 960' ]] || exit 1
    sed 's/com.eg.android.AlipayGphoneRC/com.other.wallet/g' "$ui" >"$root/wrong-package.xml"
    UI_DUMP_LOCAL_PATH="$root/wrong-package.xml"; [[ "$(ui_dialog_state)" == INVALID ]] || exit 1
    sed 's/人气太旺啦，稍候再试试。(6)/其他提示/' "$ui" >"$root/wrong-text.xml"
    UI_DUMP_LOCAL_PATH="$root/wrong-text.xml"; [[ "$(ui_dialog_state)" == INVALID ]] || exit 1
    sed 's#</hierarchy>#<node package="com.eg.android.AlipayGphoneRC" class="android.widget.Button" text="关闭" enabled="true" visible-to-user="true" clickable="true" bounds="[400,1100][680,1220]" /></hierarchy>#' "$ui" >"$root/multiple-buttons.xml"
    UI_DUMP_LOCAL_PATH="$root/multiple-buttons.xml"; [[ "$(ui_dialog_state)" == INVALID ]] || exit 1
    sed 's#</hierarchy>#<node package="com.eg.android.AlipayGphoneRC" class="android.widget.Button" text="确认支付" enabled="true" visible-to-user="true" clickable="true" bounds="[400,1100][680,1220]" /></hierarchy>#' "$ui" >"$root/payment-button.xml"
    UI_DUMP_LOCAL_PATH="$root/payment-button.xml"; [[ "$(ui_dialog_state)" == UNSAFE ]] || exit 1
    sed 's/\[400,900\]\[680,1020\]/[0,0][1200,2100]/' "$ui" >"$root/bad-bounds.xml"
    UI_DUMP_LOCAL_PATH="$root/bad-bounds.xml"; [[ "$(ui_dialog_state)" == INVALID ]] || exit 1
    FLUTTER_LOG_PATH="$root/flutter.log"; : >"$FLUTTER_LOG_PATH"; LOG_BASELINE_BYTES=0
    record_marker_baseline; printf '%s\n' "$EXPECTED_BRIDGE_MARKER" >>"$FLUTTER_LOG_PATH"
    [[ "$(classify_appended_markers)" == RETURNED ]] || exit 1
    : >"$FLUTTER_LOG_PATH"; record_marker_baseline; printf '%s\n' "$REJECTED_SUCCESS_MARKER" >>"$FLUTTER_LOG_PATH"
    [[ "$(classify_appended_markers)" == INVALID ]] || exit 1
    audit 'PARSER_FAIL_CLOSED_PASS'; audit 'MARKER_FAIL_CLOSED_PASS'; audit 'SELF_TEST_PASS'
  )
  printf 'SELF_TEST::PASS\n'
}
main() {
  parse_args "$@"
  if [[ "$SELF_TEST" == true ]]; then probe_self_test; exit 0; fi
  validate_serial; validate_log_path; validate_bounds; resolve_adb
  trap cleanup_on_exit EXIT
  record_marker_baseline; adb_get_state; verify_physical_device; read_screen_size
  read_target_state || fail_device 'Alipay error-dialog activity is not foreground'
  local coordinates ready_x ready_y
  coordinates="$(wait_for_safe_error_dialog)"
  audit 'ERROR_DIALOG_MATCHED'
  ready_x="$(printf '%s\n' "$coordinates" | awk '{print $1}')"
  ready_y="$(printf '%s\n' "$coordinates" | awk '{print $2}')"
  assert_no_marker_before_tap
  read_target_state || fail_device 'Alipay error-dialog activity changed before tap'
  (( CLICK_COUNT == 0 )) || fail_device 'dismiss tap budget already consumed'
  [[ "$ready_x" =~ ^[0-9]+$ && "$ready_y" =~ ^[0-9]+$ ]] || fail_device 'dismiss coordinates are invalid'
  "$ADB_BIN" -s "$SERIAL_VALUE" shell input tap "$ready_x" "$ready_y" >/dev/null 2>&1 ||
    fail_device 'dismiss tap failed'
  CLICK_COUNT=1
  audit 'DISMISS_BUTTON_TAPPED::count=1'
  # No device operation occurs after the tap; only the private Flutter log is read.
  wait_for_paytask_return
  audit 'PASS'
}
main "$@"
