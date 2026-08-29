#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

# Single-device, sandbox-only success lane. This is separate from the
# cancellation and broad vendor lanes: it never starts AVD-B, SMS, or Tencent,
# and it cannot invoke PayTask until the host operator approves the exact
# just-created order.
readonly PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
readonly DEFAULT_SERIAL='emulator-5554'
readonly APP_PACKAGE='com.kong373.voice_social_app'
readonly TARGET_PACKAGE='com.eg.android.AlipayGphoneRC'
readonly DEVICE_WALLET_UI_DUMP_PATH='/data/local/tmp/voice-social-alipay-success-wallet-ui.xml'
readonly OPERATOR_SCRIPT="$PROJECT_ROOT/tool/qa/m5_alipay_action_confirmation_operator.py"
readonly INTEGRATION_TARGET='integration_test/alipay_focused_success_test.dart'
readonly DRIVER_TARGET='test_driver/integration_test.dart'
readonly AUDIO_MANIFEST_SCRIPT="$PROJECT_ROOT/tool/prepare_android_audio_manifest.py"
readonly BACKEND_BASE_URL='http://10.0.2.2:18080/'
readonly BACKEND_HEALTH_URL='http://127.0.0.1:18080/health'
readonly PUBLIC_OAUTH_CLIENT_ID='voice-social-mobile-public'
readonly EXPECTED_FLUTTER_VERSION='3.44.7'
readonly EXPECTED_DART_VERSION='3.12.2'
readonly EXPECTED_FLUTTER_REVISION='84fc5cbb223bc12f83d65b647ff8a56caf779ffd'
readonly EXPECTED_SUCCESS_CONFIRMATION='I_UNDERSTAND_SANDBOX_SUCCESS_PAYMENT'
readonly EXPECTED_NATIVE_MARKER='M5_ALIPAY_NATIVE_RESULT::sdkCompleted=1::resultStatus=9000'
readonly EXPECTED_BRIDGE_MARKER='M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::pay_task_returned'
readonly EXIT_CONFIGURATION=64
readonly EXIT_DEVICE=69
readonly EXIT_ACCEPTANCE=70

SELF_TEST=false
SERIAL_VALUE="$(printenv ANDROID_SERIAL || true)"
[[ -n "$SERIAL_VALUE" ]] || SERIAL_VALUE="$DEFAULT_SERIAL"
ARTIFACT_DIR_ARG=''
ARTIFACT_DIR=''
ANDROID_HOST_DIR=''
FLUTTER_BIN=''
ADB_BIN=''
FLUTTER_LOG_PATH=''
RELAY_PID=''
RELAY_PORT=''
RELAY_APP_TOKEN=''
RELAY_OPERATOR_TOKEN=''
ACTION_GATE_STATE_DIR=''
ACTION_GATE_STATE_PARENT=''
ACTION_GATE_OPERATOR_FILE=''
ACTION_GATE_MARKER_FILE=''
ACTION_GATE_READY_FILE=''
RUNTIME_TOKEN_FEEDER_PID=''
RUNTIME_TOKEN_FILE='cache/m5-action-gate-token'
RUNTIME_TOKEN_TMP_FILE='cache/m5-action-gate-token.tmp'
WALLET_UI_DUMP_PATH=''
WALLET_UI_DUMP_ACTIVE=false
FLUTTER_STATUS='NOT_RUN'
RUN_RESULT='NOT_RUN'
FAIL_REASON='not_started'
FLUTTER_VERSION='unknown'
DART_VERSION='unknown'
FLUTTER_REVISION='unknown'
FLUTTER_SHA_ACTUAL=''
BACKEND_SHA_ACTUAL=''
BACKEND_DIGEST_ACTUAL=''
APK_SHA=''

QA_M5_RUN_ID="$(printenv QA_M5_RUN_ID || true)"
QA_FLUTTER_SHA="$(printenv QA_FLUTTER_SHA || true)"
QA_BACKEND_SHA="$(printenv QA_BACKEND_SHA || true)"
QA_BACKEND_REPO="$(printenv QA_BACKEND_REPO || true)"
QA_BACKEND_DIGEST="$(printenv QA_BACKEND_DIGEST || true)"
QA_M5_ALLOW_EXTERNAL_PAYMENT="$(printenv QA_M5_ALLOW_EXTERNAL_PAYMENT || true)"
QA_M5_PAYMENT_CONFIRMATION="$(printenv QA_M5_PAYMENT_CONFIRMATION || true)"
QA_M5_SUCCESS_CONFIRMATION="$(printenv QA_M5_SUCCESS_CONFIRMATION || true)"
QA_M5_ALIPAY_SCENARIO="$(printenv QA_M5_ALIPAY_SCENARIO || true)"

usage() {
  cat <<'USAGE'
Usage: run_alipay_focused_success.sh [options]

Options:
  --serial ID           exact target serial (must be emulator-5554)
  --artifact-dir PATH   new absolute directory for sanitized evidence
  --self-test           run offline marker/wallet/gate checks
  --help                show help

Live mode needs an already-authenticated app session. The runner prints only
the operator-file path and relay port. Wait for ACTION_CONFIRMATION_REQUIRED
after the order request, then run the operator tool. It fetches the exact
bound identity in-process and asks only for the success confirmation; no
success action is approved automatically.
USAGE
}

fail_configuration() {
  RUN_RESULT='FAIL'
  FAIL_REASON="$1"
  printf 'Alipay focused success: configuration rejected (%s)\n' "$1" >&2
  exit "$EXIT_CONFIGURATION"
}

fail_device() {
  RUN_RESULT='FAIL'
  FAIL_REASON="$1"
  printf 'Alipay focused success: device rejected (%s)\n' "$1" >&2
  exit "$EXIT_DEVICE"
}

fail_acceptance() {
  RUN_RESULT='FAIL'
  FAIL_REASON="$1"
  printf 'Alipay focused success: acceptance failed (%s)\n' "$1" >&2
  exit "$EXIT_ACCEPTANCE"
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
      --serial)
        (($# >= 2)) || fail_configuration 'serial is missing'
        SERIAL_VALUE="$2"
        shift 2
        ;;
      --serial=*)
        SERIAL_VALUE="$(printf '%s' "$argument" | cut -d= -f2-)"
        shift
        ;;
      --artifact-dir)
        (($# >= 2)) || fail_configuration 'artifact directory is missing'
        ARTIFACT_DIR_ARG="$2"
        shift 2
        ;;
      --artifact-dir=*)
        ARTIFACT_DIR_ARG="$(printf '%s' "$argument" | cut -d= -f2-)"
        shift
        ;;
      *)
        fail_configuration 'unknown option'
        ;;
    esac
  done
}

validate_serial() {
  [[ "$SERIAL_VALUE" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$ ]] ||
    fail_configuration 'serial has an unsafe format'
  [[ "$SERIAL_VALUE" == "$DEFAULT_SERIAL" ]] ||
    fail_configuration 'focused success target serial is frozen to emulator-5554'
  local avd_b_serial
  avd_b_serial="$(printenv QA_AVD_B_SERIAL || true)"
  if [[ -n "$avd_b_serial" && "$avd_b_serial" == "$SERIAL_VALUE" ]]; then
    fail_configuration 'selected serial is reserved for the second AVD'
  fi
}

validate_environment() {
  [[ -n "$QA_M5_RUN_ID" ]] || fail_configuration 'QA_M5_RUN_ID is required'
  [[ "$QA_M5_RUN_ID" =~ ^[A-Za-z0-9_.:-]{1,80}$ ]] ||
    fail_configuration 'QA_M5_RUN_ID is invalid'
  [[ "$QA_FLUTTER_SHA" =~ ^[0-9a-f]{40}$ ]] ||
    fail_configuration 'QA_FLUTTER_SHA must be a lowercase 40-character SHA'
  [[ "$QA_BACKEND_SHA" =~ ^[0-9a-f]{40}$ ]] ||
    fail_configuration 'QA_BACKEND_SHA must be a lowercase 40-character SHA'
  [[ "$QA_BACKEND_DIGEST" =~ ^[0-9a-f]{64}$ ]] ||
    fail_configuration 'QA_BACKEND_DIGEST must be a lowercase SHA-256'
  [[ -n "$QA_BACKEND_REPO" ]] || fail_configuration 'QA_BACKEND_REPO is required'
  [[ "$QA_M5_ALLOW_EXTERNAL_PAYMENT" == 'true' ]] ||
    fail_configuration 'QA_M5_ALLOW_EXTERNAL_PAYMENT must be true'
  [[ "$QA_M5_PAYMENT_CONFIRMATION" == 'I_UNDERSTAND_SANDBOX_PAYMENT' ]] ||
    fail_configuration 'sandbox payment opt-in confirmation is required'
  [[ "$QA_M5_SUCCESS_CONFIRMATION" == "$EXPECTED_SUCCESS_CONFIRMATION" ]] ||
    fail_configuration 'sandbox success action confirmation is required'
  [[ "$QA_M5_ALIPAY_SCENARIO" == 'success' ]] ||
    fail_configuration 'QA_M5_ALIPAY_SCENARIO must be success'
  [[ -z "$(printenv DEVELOPMENT_OUTBOX_KEY || true)" &&
    -z "$(printenv QA_DEVELOPMENT_OUTBOX_KEY || true)" ]] ||
    fail_configuration 'development outbox secrets are forbidden'
  [[ -z "$(printenv M5_ACTION_GATE_TOKEN || true)" &&
    -z "$(printenv QA_M5_ACTION_OPERATOR_TOKEN || true)" ]] ||
    fail_configuration 'action gate tokens must be generated locally'
  [[ -d "$QA_BACKEND_REPO/.git" || -f "$QA_BACKEND_REPO/.git" ]] ||
    fail_configuration 'QA_BACKEND_REPO is not a Git checkout'
  [[ -f "$OPERATOR_SCRIPT" ]] ||
    fail_configuration 'action confirmation operator is missing'
}

resolve_commands() {
  ADB_BIN="$(command -v adb || true)"
  FLUTTER_BIN="$(command -v flutter || true)"
  [[ -n "$ADB_BIN" && -x "$ADB_BIN" ]] || fail_configuration 'adb executable is unavailable'
  [[ -n "$FLUTTER_BIN" && -x "$FLUTTER_BIN" ]] || fail_configuration 'Flutter executable is unavailable'
  for command_name in curl python3 git tar mktemp shasum awk grep wc head tail find sort tr sed cut; do
    command -v "$command_name" >/dev/null 2>&1 ||
      fail_configuration "missing command: $command_name"
  done
}

create_safe_artifact_dir() {
  if [[ -z "$ARTIFACT_DIR_ARG" ]]; then
    ARTIFACT_DIR="$(mktemp -d /tmp/voice-social-alipay-success.XXXXXX)" ||
      fail_configuration 'temporary artifact directory could not be created'
    chmod 700 "$ARTIFACT_DIR"
    return 0
  fi
  ARTIFACT_DIR="$ARTIFACT_DIR_ARG"
  [[ "$ARTIFACT_DIR" == /* && "$ARTIFACT_DIR" != *$'\n'* &&
    "$ARTIFACT_DIR" != *$'\r'* && "$ARTIFACT_DIR" != *$'\t'* &&
    "$ARTIFACT_DIR" != *'..'* ]] ||
    fail_configuration 'artifact directory must be a new absolute path without traversal'
  python3 - "$ARTIFACT_DIR" <<'PY' ||
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
current = ancestor
while True:
    metadata = os.lstat(current)
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        raise SystemExit(1)
    if current == Path(current.anchor):
        break
    current = current.parent
for directory in reversed(missing):
    os.mkdir(directory, 0o700)
os.mkdir(path, 0o700)
PY
    fail_configuration 'artifact directory is not safe to create'
}

attest_flutter() {
  local facts status
  facts="$("$FLUTTER_BIN" --version --machine 2>/dev/null | python3 -c '
import json
import sys
try:
    data = json.load(sys.stdin)
    print(data["frameworkVersion"])
    print(data["dartSdkVersion"])
    print(data["frameworkRevision"])
except (KeyError, TypeError, ValueError):
    raise SystemExit(1)
')" || fail_configuration 'Flutter SDK metadata is invalid'
  [[ "$(printf '%s\n' "$facts" | wc -l | tr -d '[:space:]')" == '3' ]] ||
    fail_configuration 'Flutter SDK metadata is incomplete'
  FLUTTER_VERSION="$(printf '%s\n' "$facts" | sed -n '1p')"
  DART_VERSION="$(printf '%s\n' "$facts" | sed -n '2p')"
  FLUTTER_REVISION="$(printf '%s\n' "$facts" | sed -n '3p')"
  [[ "$FLUTTER_VERSION" == "$EXPECTED_FLUTTER_VERSION" ]] ||
    fail_configuration 'Flutter version mismatch'
  [[ "$DART_VERSION" == "$EXPECTED_DART_VERSION" ]] ||
    fail_configuration 'Dart version mismatch'
  [[ "$FLUTTER_REVISION" == "$EXPECTED_FLUTTER_REVISION" ]] ||
    fail_configuration 'Flutter framework revision mismatch'
  FLUTTER_SHA_ACTUAL="$(git -C "$PROJECT_ROOT" rev-parse --verify HEAD)" ||
    fail_configuration 'Flutter SHA unavailable'
  [[ "$FLUTTER_SHA_ACTUAL" == "$QA_FLUTTER_SHA" ]] ||
    fail_configuration 'QA_FLUTTER_SHA mismatch'
  status="$(git -C "$PROJECT_ROOT" status --porcelain=v1 --untracked-files=all --ignore-submodules=none)" ||
    fail_configuration 'Flutter checkout status unavailable'
  [[ -z "$status" ]] || fail_configuration 'Flutter checkout must be clean'
}

attest_backend() {
  local status digest_script
  status="$(git -C "$QA_BACKEND_REPO" status --porcelain=v1 --untracked-files=all --ignore-submodules=none)" ||
    fail_configuration 'Backend checkout status unavailable'
  [[ -z "$status" ]] || fail_configuration 'Backend checkout must be clean'
  BACKEND_SHA_ACTUAL="$(git -C "$QA_BACKEND_REPO" rev-parse --verify HEAD)" ||
    fail_configuration 'Backend SHA unavailable'
  [[ "$BACKEND_SHA_ACTUAL" == "$QA_BACKEND_SHA" ]] ||
    fail_configuration 'QA_BACKEND_SHA mismatch'
  digest_script="$QA_BACKEND_REPO/scripts/compute-backend-source-digest.sh"
  [[ -x "$digest_script" ]] || fail_configuration 'Backend digest script missing'
  BACKEND_DIGEST_ACTUAL="$(cd "$QA_BACKEND_REPO" && ./scripts/compute-backend-source-digest.sh)" ||
    fail_configuration 'Backend source digest unavailable'
  [[ "$BACKEND_DIGEST_ACTUAL" =~ ^[0-9a-f]{64}$ ]] ||
    fail_configuration 'Backend source digest output is invalid'
  [[ "$BACKEND_DIGEST_ACTUAL" == "$QA_BACKEND_DIGEST" ]] ||
    fail_configuration 'Backend source digest mismatch'
}

attest_backend_health() {
  curl --noproxy '*' --fail --silent --show-error --max-time 5 \
    "$BACKEND_HEALTH_URL" >/dev/null 2>&1 ||
    fail_device 'development backend health is not reachable'
}

wallet_ui_is_healthy() {
  [[ -n "$WALLET_UI_DUMP_PATH" && -f "$WALLET_UI_DUMP_PATH" &&
    ! -L "$WALLET_UI_DUMP_PATH" ]] || return 1
  python3 - "$WALLET_UI_DUMP_PATH" "$TARGET_PACKAGE" 2>/dev/null <<'PY'
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
try:
    path = Path(sys.argv[1])
    package = sys.argv[2]
    text = path.read_text(encoding="utf-8", errors="replace")
    root = ET.fromstring(text)
except (OSError, ValueError, ET.ParseError):
    raise SystemExit(1)
if root.tag != "hierarchy":
    raise SystemExit(1)
if any(phrase in text.casefold() for phrase in (
    "please wait a minute", "reload", "server busy", "try again later",
)):
    raise SystemExit(1)
nodes = [node for node in root.iter("node")
         if node.attrib.get("package") == package]
labels = {
    node.attrib.get(attribute, "").strip().casefold()
    for node in nodes
    for attribute in ("text", "content-desc")
}
if not nodes or not {"scan", "pay", "home"}.issubset(labels):
    raise SystemExit(1)
PY
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
  local state dump
  state="$("$ADB_BIN" -s "$SERIAL_VALUE" get-state 2>/dev/null || true)"
  state="$(printf '%s' "$state" | tr -d '\r\n')"
  [[ "$state" == 'device' ]] || fail_device 'selected serial is not online'
  dump="$("$ADB_BIN" -s "$SERIAL_VALUE" shell dumpsys activity activities 2>/dev/null || true)"
  foreground_package_is_target "$dump" ||
    fail_device 'Alipay sandbox wallet is not the foreground package'
  WALLET_UI_DUMP_PATH="$ARTIFACT_DIR/.wallet-health-ui.xml"
  : >"$WALLET_UI_DUMP_PATH"
  chmod 600 "$WALLET_UI_DUMP_PATH"
  WALLET_UI_DUMP_ACTIVE=true
  "$ADB_BIN" -s "$SERIAL_VALUE" shell uiautomator dump \
    "$DEVICE_WALLET_UI_DUMP_PATH" >/dev/null 2>&1 ||
    fail_device 'Alipay sandbox wallet UI dump is unavailable'
  "$ADB_BIN" -s "$SERIAL_VALUE" shell cat "$DEVICE_WALLET_UI_DUMP_PATH" \
    >"$WALLET_UI_DUMP_PATH" 2>/dev/null ||
    fail_device 'Alipay sandbox wallet UI dump cannot be read'
  wallet_ui_is_healthy ||
    fail_device 'Alipay sandbox wallet health is not proven'
  clear_wallet_ui_dump
}

start_action_relay() {
  ACTION_GATE_STATE_PARENT="$(cd /tmp && pwd -P)" ||
    fail_configuration 'action gate state parent could not be canonicalized'
  ACTION_GATE_STATE_DIR="$(mktemp -d "$ACTION_GATE_STATE_PARENT/voice-social-alipay-success-gate.XXXXXX")" ||
    fail_configuration 'action gate state directory could not be created'
  chmod 700 "$ACTION_GATE_STATE_DIR"
  ACTION_GATE_OPERATOR_FILE="$ACTION_GATE_STATE_DIR/operator-token"
  ACTION_GATE_MARKER_FILE="$ACTION_GATE_STATE_DIR/marker"
  ACTION_GATE_READY_FILE="$ACTION_GATE_STATE_DIR/relay-ready"
  RELAY_APP_TOKEN="$(python3 -c 'import secrets; print(secrets.token_urlsafe(48))')"
  RELAY_OPERATOR_TOKEN="$(python3 -c 'import secrets; print(secrets.token_urlsafe(48))')"
  (umask 077 &&
    printf '%s' "$RELAY_OPERATOR_TOKEN" >"$ACTION_GATE_OPERATOR_FILE" &&
    chmod 600 "$ACTION_GATE_OPERATOR_FILE" &&
    : >"$ACTION_GATE_MARKER_FILE" &&
    chmod 600 "$ACTION_GATE_MARKER_FILE") ||
    fail_configuration 'action gate state initialization failed'
  QA_M5_ACTION_APP_TOKEN="$RELAY_APP_TOKEN" \
    QA_M5_ACTION_OPERATOR_TOKEN="$RELAY_OPERATOR_TOKEN" \
    QA_M5_ACTION_MARKER_FILE="$ACTION_GATE_MARKER_FILE" \
    QA_M5_ACTION_READY_FILE="$ACTION_GATE_READY_FILE" \
    QA_M5_ACTION_RUN_ID="$QA_M5_RUN_ID" \
    QA_M5_ACTION_BACKEND_SHA="$QA_BACKEND_SHA" \
    QA_M5_ACTION_FLUTTER_SHA="$QA_FLUTTER_SHA" \
    PYTHONPATH="$PROJECT_ROOT/tool/qa" \
    python3 -u - >/dev/null 2>&1 <<'PY' &
import hmac
import http.server
import json
import os
from pathlib import Path
import re
import stat
import threading

from m5_alipay_action_gate import (
    ACTION_CONFIRMATION_REQUIRED,
    ActionConfirmationGate,
    ActionGateError,
    ActionIdentity,
)

app_token = os.environ["QA_M5_ACTION_APP_TOKEN"]
operator_token = os.environ["QA_M5_ACTION_OPERATOR_TOKEN"]
marker_file = Path(os.environ["QA_M5_ACTION_MARKER_FILE"])
ready_file = Path(os.environ["QA_M5_ACTION_READY_FILE"])
expected_run = os.environ["QA_M5_ACTION_RUN_ID"]
expected_backend = os.environ["QA_M5_ACTION_BACKEND_SHA"]
expected_flutter = os.environ["QA_M5_ACTION_FLUTTER_SHA"]
serial = "emulator-5554"
safe_value = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$")
safe_run = re.compile(r"^[A-Za-z0-9_.:-]{1,80}$")
safe_sha = re.compile(r"^[0-9a-f]{40}$")
safe_attribute = re.compile(r"^[A-Z][A-Z0-9_.:-]{0,31}$")
safe_created_marker = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:+-]{0,127}$")
max_amount_minor = 10**12
max_gift_coin_amount = 10**12
lock = threading.Lock()
pending_identity = None

def marker_sink(marker):
    if marker != ACTION_CONFIRMATION_REQUIRED:
        raise RuntimeError("marker")
    flags = os.O_WRONLY | os.O_APPEND | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(marker_file, flags)
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or stat.S_IMODE(metadata.st_mode) != 0o600:
            raise RuntimeError("marker")
        os.write(descriptor, (marker + "\n").encode("ascii"))
        os.fsync(descriptor)
    finally:
        os.close(descriptor)

gate = ActionConfirmationGate(
    enabled=True,
    expected_run_id=expected_run,
    expected_avd="AVD-A",
    expected_serial=serial,
    expected_backend_sha=expected_backend,
    expected_flutter_sha=expected_flutter,
    ttl_seconds=120,
    marker_sink=marker_sink,
)

def auth(header, expected):
    values = header.get_all("Authorization") or []
    prefix = "Bearer "
    supplied = values[0][len(prefix):] if len(values) == 1 and values[0].startswith(prefix) else ""
    return bool(supplied) and hmac.compare_digest(supplied, expected)

def body(handler):
    try:
        lengths = handler.headers.get_all("Content-Length") or []
        if len(lengths) != 1 or handler.headers.get_all("Transfer-Encoding"):
            return {}
        length = int(lengths[0])
        if length < 0 or length > 4096:
            return {}
        raw = handler.rfile.read(length)
        value = json.loads(raw.decode("utf-8")) if raw else {}
        return value if isinstance(value, dict) else {}
    except (ValueError, TypeError, UnicodeDecodeError, json.JSONDecodeError):
        return {}

def identity(payload):
    required = {
        "runId", "avd", "serial", "backendSha", "flutterSha",
        "orderNo", "requestId", "account", "productId",
        "amountMinor", "giftCoinAmount", "provider", "status",
    }
    optional = {"createdMarker"}
    if (
        not isinstance(payload, dict)
        or not required.issubset(payload)
        or not set(payload).issubset(required | optional)
    ):
        raise ActionGateError("IDENTITY_INVALID")
    if (payload["avd"] != "AVD-A" or payload["serial"] != serial or
        not safe_run.fullmatch(payload["runId"]) or
        not safe_sha.fullmatch(payload["backendSha"]) or
        not safe_sha.fullmatch(payload["flutterSha"]) or
        not safe_value.fullmatch(payload["orderNo"]) or
        not safe_value.fullmatch(payload["requestId"]) or
        not safe_value.fullmatch(payload["account"]) or
        not safe_value.fullmatch(payload["productId"]) or
        type(payload["amountMinor"]) is not int or
        not 1 <= payload["amountMinor"] <= max_amount_minor or
        type(payload["giftCoinAmount"]) is not int or
        not 1 <= payload["giftCoinAmount"] <= max_gift_coin_amount):
        raise ActionGateError("IDENTITY_INVALID")
    if (
        payload.get("provider") != "ALIPAY"
        or payload.get("status") != "CREATED"
        or not safe_attribute.fullmatch(payload["provider"])
        or not safe_attribute.fullmatch(payload["status"])
    ):
        raise ActionGateError("IDENTITY_INVALID")
    if "createdMarker" in payload and (
        not isinstance(payload["createdMarker"], str)
        or not safe_created_marker.fullmatch(payload["createdMarker"])
    ):
        raise ActionGateError("IDENTITY_INVALID")
    return ActionIdentity(
        run_id=payload["runId"],
        avd=payload["avd"],
        serial=payload["serial"],
        backend_sha=payload["backendSha"],
        flutter_sha=payload["flutterSha"],
        order_no=payload["orderNo"],
        request_id=payload["requestId"],
        account=payload["account"],
        product_id=payload["productId"],
        amount_minor=payload["amountMinor"],
        gift_coin_amount=payload["giftCoinAmount"],
        provider=payload.get("provider"),
        status=payload.get("status"),
        created_marker=payload.get("createdMarker"),
    )

def identity_payload(value):
    result = {
        "runId": value.run_id,
        "avd": value.avd,
        "serial": value.serial,
        "backendSha": value.backend_sha,
        "flutterSha": value.flutter_sha,
        "orderNo": value.order_no,
        "requestId": value.request_id,
        "account": value.account,
        "productId": value.product_id,
        "amountMinor": value.amount_minor,
        "giftCoinAmount": value.gift_coin_amount,
    }
    if value.provider is not None:
        result["provider"] = value.provider
    if value.status is not None:
        result["status"] = value.status
    if value.created_marker is not None:
        result["createdMarker"] = value.created_marker
    return result

class Handler(http.server.BaseHTTPRequestHandler):
    def reply(self, status, payload):
        encoded = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)
    def do_GET(self):
        global pending_identity
        if self.path == "/m5/alipay/action-confirmation/pending":
            if not auth(self.headers, operator_token):
                self.reply(401, {"error": "unauthorized"})
                return
            with lock:
                current = pending_identity
                status = gate.public_status()
                if status["expired"]:
                    pending_identity = None
                    current = None
            if current is None or not status["pending"] or status["approved"] or status["consumed"]:
                self.reply(409, {"pending": False})
                return
            self.reply(200, {"pending": True, **identity_payload(current)})
            return
        if self.path != "/m5/alipay/action-confirmation/status" or not auth(self.headers, operator_token):
            self.reply(401, {"error": "unauthorized"})
            return
        with lock:
            status = gate.public_status()
            if status["expired"]:
                pending_identity = None
        self.reply(200, status)
    def do_POST(self):
        global pending_identity
        approve = self.path == "/m5/alipay/action-confirmation/approve"
        app_path = self.path in (
            "/m5/alipay/action-confirmation/request",
            "/m5/alipay/action-confirmation/consume",
        )
        if approve:
            allowed = auth(self.headers, operator_token)
        elif app_path:
            allowed = auth(self.headers, app_token)
        else:
            self.reply(404, {"error": "not_found"})
            return
        if not allowed:
            self.reply(401, {"error": "unauthorized"})
            return
        payload = body(self)
        try:
            if approve:
                if (
                    not isinstance(payload, dict)
                    or "confirmation" not in payload
                    or not isinstance(payload["confirmation"], str)
                ):
                    raise ActionGateError("IDENTITY_INVALID")
                fields = dict(payload)
                confirmation = fields.pop("confirmation")
                gate.approve(identity(fields), confirmation)
                self.reply(200, {"accepted": True})
                return
            current = identity(payload)
            if self.path.endswith("/request"):
                with lock:
                    gate.request(current)
                    pending_identity = current
                self.reply(200, {"accepted": True, "status": "PENDING"})
            else:
                with lock:
                    gate.consume(current)
                    pending_identity = None
                self.reply(200, {"approved": True})
        except ActionGateError as error:
            self.reply(409, {"approved": False, "error": error.code})
    def log_message(self, *_args):
        return

def write_ready(server):
    payload = json.dumps(
        {"pid": os.getpid(), "port": int(server.server_port)},
        separators=(",", ":"),
    ).encode("ascii")
    temporary = ready_file.with_name("." + ready_file.name + ".tmp")
    flags = (
        os.O_WRONLY
        | os.O_CREAT
        | os.O_EXCL
        | getattr(os, "O_CLOEXEC", 0)
        | getattr(os, "O_NOFOLLOW", 0)
    )
    descriptor = os.open(temporary, flags, 0o600)
    try:
        os.fchmod(descriptor, 0o600)
        os.write(descriptor, payload)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    os.replace(temporary, ready_file)
    metadata = ready_file.lstat()
    if not stat.S_ISREG(metadata.st_mode) or stat.S_IMODE(metadata.st_mode) != 0o600:
        raise RuntimeError("ready")

server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
server.daemon_threads = True
write_ready(server)
server.serve_forever()
PY
  RELAY_PID=$!
  for _ in $(seq 1 60); do
    kill -0 "$RELAY_PID" 2>/dev/null || fail_configuration 'action gate relay exited'
    if [[ -f "$ACTION_GATE_READY_FILE" && ! -L "$ACTION_GATE_READY_FILE" ]]; then
      RELAY_PORT="$(QA_M5_ACTION_OPERATOR_TOKEN="$RELAY_OPERATOR_TOKEN" \
        python3 - "$ACTION_GATE_READY_FILE" "$RELAY_PID" <<'PY'
import json
import os
from pathlib import Path
import stat
import sys
import urllib.request

path = Path(sys.argv[1])
expected_pid = int(sys.argv[2])
try:
    metadata = path.lstat()
    if not stat.S_ISREG(metadata.st_mode) or stat.S_IMODE(metadata.st_mode) != 0o600:
        raise SystemExit(1)
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags)
    try:
        checked = os.fstat(descriptor)
        if not stat.S_ISREG(checked.st_mode) or stat.S_IMODE(checked.st_mode) != 0o600:
            raise SystemExit(1)
        value = json.loads(os.read(descriptor, 256).decode("ascii"))
    finally:
        os.close(descriptor)
    if (
        not isinstance(value, dict)
        or set(value) != {"pid", "port"}
        or type(value["pid"]) is not int
        or type(value["port"]) is not int
        or value["pid"] != expected_pid
        or not 1 <= value["port"] <= 65535
    ):
        raise SystemExit(1)
    token = os.environ["QA_M5_ACTION_OPERATOR_TOKEN"]
    request = urllib.request.Request(
        f"http://127.0.0.1:{value['port']}/m5/alipay/action-confirmation/status",
        headers={"Authorization": "Bearer " + token},
        method="GET",
    )
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *_args, **_kwargs):
            return None
    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({}), NoRedirect()
    )
    with opener.open(request, timeout=1) as response:
        if response.geturl() != request.full_url or response.status != 200:
            raise SystemExit(1)
        status = json.loads(response.read(512))
    if (
        not isinstance(status, dict)
        or type(status.get("pending")) is not bool
        or type(status.get("approved")) is not bool
        or type(status.get("consumed")) is not bool
        or type(status.get("expired")) is not bool
    ):
        raise SystemExit(1)
    print(value["port"])
except (OSError, ValueError, TypeError, UnicodeError, json.JSONDecodeError):
    raise SystemExit(1)
PY
      )" || RELAY_PORT=''
      if [[ "$RELAY_PORT" =~ ^[0-9]+$ && "$RELAY_PORT" -ge 1 &&
        "$RELAY_PORT" -le 65535 ]]; then
        # The parent trusts the child's actual bind only after checking the
        # private readiness file, matching PID, port range, and an
        # authenticated operator status request.
        printf 'ACTION_GATE::armed::operator_file=%s::relay_port=%s\n' \
          "$ACTION_GATE_OPERATOR_FILE" "$RELAY_PORT"
        printf 'ACTION_GATE::waiting_for_order\n'
        return 0
      fi
    fi
    sleep 0.1
  done
  fail_configuration 'action gate relay did not become ready'
}

prepare_android_host() {
  ANDROID_HOST_DIR="$(mktemp -d /tmp/voice-social-alipay-host.XXXXXX)" ||
    fail_configuration 'temporary Android host could not be created'
  "$FLUTTER_BIN" create --platforms=android --android-language=kotlin \
    --org=com.kong373 --project-name=voice_social_app --no-pub \
    "$ANDROID_HOST_DIR" >/dev/null 2>&1 ||
    fail_configuration 'temporary Android host generation failed'
  git -C "$PROJECT_ROOT" archive --format=tar HEAD | tar -x -C "$ANDROID_HOST_DIR" ||
    fail_configuration 'tracked checkout overlay failed'
  [[ -f "$AUDIO_MANIFEST_SCRIPT" ]] ||
    fail_configuration 'Android audio manifest helper is missing'
  python3 "$AUDIO_MANIFEST_SCRIPT" "$ANDROID_HOST_DIR" >/dev/null 2>&1 ||
    fail_configuration 'Android audio manifest preparation failed'
  (
    cd "$ANDROID_HOST_DIR"
    "$FLUTTER_BIN" pub get --enforce-lockfile >/dev/null 2>&1
  ) || fail_configuration 'locked Flutter dependency regeneration failed'
}

build_apk() {
  (
    cd "$ANDROID_HOST_DIR"
    "$FLUTTER_BIN" build apk --debug \
      --target="$INTEGRATION_TARGET" \
      --dart-define=BACKEND_MODE=live \
      --dart-define=APP_ENV=development \
      --dart-define=ALLOW_INSECURE_HTTP=true \
      --dart-define=API_BASE_URL="$BACKEND_BASE_URL" \
      --dart-define=OAUTH_CLIENT_ID="$PUBLIC_OAUTH_CLIENT_ID" \
      --dart-define=CLIENT_TYPE=Android \
      --dart-define=CLIENT_INNER_VERSION=6 \
      --dart-define=API_TIMEOUT_SECONDS=15 \
      --dart-define=ENABLE_TENCENT_IM=false \
      --dart-define=ENABLE_ALIPAY_APP_PAY=true \
      --dart-define=M5_ACTION_GATE_PORT="$RELAY_PORT" \
      --dart-define=M5_ACTION_RUN_ID="$QA_M5_RUN_ID" \
      --dart-define=M5_EXPECTED_BACKEND_SHA="$QA_BACKEND_SHA" \
      --dart-define=M5_EXPECTED_FLUTTER_SHA="$QA_FLUTTER_SHA" \
      --dart-define=M5_EXPECTED_SERIAL="$DEFAULT_SERIAL" \
      --dart-define=M5_ALLOW_EXTERNAL_PAYMENT=true \
      --dart-define=M5_PAYMENT_CONFIRMATION=I_UNDERSTAND_SANDBOX_PAYMENT \
      --dart-define=M5_SUCCESS_CONFIRMATION="$EXPECTED_SUCCESS_CONFIRMATION" \
      --dart-define=M5_ALIPAY_SCENARIO=success >/dev/null 2>&1
  ) || fail_configuration 'focused success APK build failed'
  local apk_source="$ANDROID_HOST_DIR/build/app/outputs/flutter-apk/app-debug.apk"
  [[ -f "$apk_source" && ! -L "$apk_source" ]] ||
    fail_configuration 'focused success APK is missing'
  cp -- "$apk_source" "$ARTIFACT_DIR/app-debug.apk"
  APK_SHA="$(shasum -a 256 "$ARTIFACT_DIR/app-debug.apk" | awk '{print $1}')"
  [[ "$APK_SHA" =~ ^[0-9a-f]{64}$ ]] ||
    fail_configuration 'focused success APK SHA is invalid'
}

feed_runtime_token() {
  local token="$RELAY_APP_TOKEN"
  (
    for _ in $(seq 1 300); do
      printf '%s' "$token" |
        "$ADB_BIN" -s "$SERIAL_VALUE" shell run-as "$APP_PACKAGE" tee \
          "$RUNTIME_TOKEN_TMP_FILE" >/dev/null 2>&1 &&
        "$ADB_BIN" -s "$SERIAL_VALUE" shell run-as "$APP_PACKAGE" chmod 600 \
          "$RUNTIME_TOKEN_TMP_FILE" >/dev/null 2>&1 &&
        "$ADB_BIN" -s "$SERIAL_VALUE" shell run-as "$APP_PACKAGE" mv \
          "$RUNTIME_TOKEN_TMP_FILE" "$RUNTIME_TOKEN_FILE" >/dev/null 2>&1 || true
      sleep 0.2
    done
  ) &
  RUNTIME_TOKEN_FEEDER_PID=$!
}

stop_runtime_token_feeder() {
  if [[ -n "$RUNTIME_TOKEN_FEEDER_PID" ]]; then
    kill "$RUNTIME_TOKEN_FEEDER_PID" 2>/dev/null || true
    wait "$RUNTIME_TOKEN_FEEDER_PID" 2>/dev/null || true
  fi
  RUNTIME_TOKEN_FEEDER_PID=''
}

clear_runtime_token() {
  "$ADB_BIN" -s "$SERIAL_VALUE" shell run-as "$APP_PACKAGE" rm -f \
    "$RUNTIME_TOKEN_FILE" "$RUNTIME_TOKEN_TMP_FILE" >/dev/null 2>&1 || true
}

safe_flutter_log_filter() {
  python3 -u -c '
import re
import sys
patterns = (
    re.compile(r"^M5_ALIPAY_FOCUSED::(?:catalog|order|action_confirmation|native_launcher|query_reconcile|settlement|complete)::(?:START|PASS|FAIL|REQUIRED|GRANTED|NOT_COLLECTED)$"),
    re.compile(r"^M5_ALIPAY_NATIVE_RESULT::sdkCompleted=[01]::resultStatus=[A-Za-z0-9_.-]{1,32}$"),
    re.compile(r"^M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::[A-Za-z0-9_.-]{1,40}$"),
)
for raw in sys.stdin:
    line = raw.rstrip("\r\n")
    if "): " in line:
        line = line.split("): ", 1)[1]
    elif line.startswith("flutter: "):
        line = line[len("flutter: "):]
    for pattern in patterns:
        match = pattern.fullmatch(line)
        if match is not None:
            sys.stdout.write(match.group(0) + "\n")
            sys.stdout.flush()
            break
'
}

exact_marker_count() {
  local marker="$1" file="$2"
  if [[ ! -f "$file" || -L "$file" ]]; then
    printf '0'
    return 0
  fi
  grep -Fxc -- "$marker" "$file" 2>/dev/null || true
}

run_flutter_drive() {
  set +e
  (
    cd "$ANDROID_HOST_DIR"
    env -u QA_LIVE_PHONE -u QA_M5_RECEIVER_PHONE -u QA_OAUTH_CLIENT_ID \
      -u DEVELOPMENT_OUTBOX_KEY -u QA_DEVELOPMENT_OUTBOX_KEY \
      "$FLUTTER_BIN" drive --use-application-binary="$ARTIFACT_DIR/app-debug.apk" \
      --driver="$DRIVER_TARGET" --target="$INTEGRATION_TARGET" \
      --device-id="$SERIAL_VALUE" 2>&1
  ) | safe_flutter_log_filter >"$FLUTTER_LOG_PATH"
  FLUTTER_STATUS="$PIPESTATUS"
  set -e
}

artifact_scan() {
  M5_SCAN_ACTION_APP="$RELAY_APP_TOKEN" \
    M5_SCAN_ACTION_OPERATOR="$RELAY_OPERATOR_TOKEN" \
    python3 - "$ARTIFACT_DIR" <<'PY'
import os
import re
import sys
from pathlib import Path
root = Path(sys.argv[1])
protected = [value.encode().lower() for value in (
    os.environ.get("M5_SCAN_ACTION_APP", ""),
    os.environ.get("M5_SCAN_ACTION_OPERATOR", ""),
) if value]
for path in root.rglob("*"):
    if path.is_symlink():
        raise SystemExit(1)
    if not path.is_file():
        continue
    if path.name == ".env.local" or path.name.endswith(".raw.log"):
        raise SystemExit(1)
    payload = path.read_bytes().lower()
    if re.search(
        rb"[\x22\x27]?(?:orderstr|orderinfo|orderstring)[\x22\x27]?[ \t]*[:=]|"
        rb"[\x22\x27]?(?:alipay_sdk|biz_content|sign_type)[\x22\x27]?[ \t]*[:=]|"
        rb"method[ \t]*=[ \t]*alipay\.trade\.app\.pay",
        payload,
    ):
        raise SystemExit(1)
    if any(needle in payload for needle in protected + [
        b"private_key", b"private key",
        b"-----begin", b"bearer ", b"access_token=", b"client_secret",
    ]):
        raise SystemExit(1)
PY
}

apk_scan() {
  python3 - "$ARTIFACT_DIR/app-debug.apk" <<'PY'
import sys
import zipfile
from pathlib import Path
path = Path(sys.argv[1])
if path.is_symlink() or not path.is_file():
    raise SystemExit(1)
forbidden = (
    b"-----begin private key-----",
    b"-----begin rsa private key-----",
    b"-----begin ec private key-----",
    b"-----begin openssh private key-----",
)
with zipfile.ZipFile(path) as archive:
    for info in archive.infolist():
        if any(value in info.filename.encode().lower() for value in forbidden):
            raise SystemExit(1)
        with archive.open(info) as stream:
            while True:
                chunk = stream.read(1024 * 1024)
                if not chunk:
                    break
                if any(value in chunk.lower() for value in forbidden):
                    raise SystemExit(1)
PY
}

write_summary() {
  [[ -n "$ARTIFACT_DIR" && -d "$ARTIFACT_DIR" ]] || return 0
  local action_required_count=0 action_granted_count=0 action_confirmation='not_requested'
  if [[ -n "$FLUTTER_LOG_PATH" && -f "$FLUTTER_LOG_PATH" ]]; then
    action_required_count="$(exact_marker_count 'M5_ALIPAY_FOCUSED::action_confirmation::REQUIRED' "$FLUTTER_LOG_PATH")"
    action_granted_count="$(exact_marker_count 'M5_ALIPAY_FOCUSED::action_confirmation::GRANTED' "$FLUTTER_LOG_PATH")"
  fi
  if [[ "$action_required_count" == '1' && "$action_granted_count" == '1' ]]; then
    action_confirmation='required_then_operator_granted'
  elif [[ "$action_required_count" == '1' ]]; then
    action_confirmation='required_not_granted'
  fi
  {
    printf 'Alipay focused sandbox success acceptance\n'
    printf 'conclusion=%s\nserial=%s\n' "$RUN_RESULT" "$SERIAL_VALUE"
    printf 'tested_git_sha=%s\nbackend_sha=%s\n' \
      "$(git -C "$PROJECT_ROOT" rev-parse --verify HEAD 2>/dev/null || printf unknown)" \
      "$BACKEND_SHA_ACTUAL"
    printf 'flutter_version=%s\ndart_version=%s\nflutter_revision=%s\n' \
      "$FLUTTER_VERSION" "$DART_VERSION" "$FLUTTER_REVISION"
    printf 'flutter_status=%s\nreason=%s\napk_sha256=%s\n' \
      "$FLUTTER_STATUS" "$FAIL_REASON" "$APK_SHA"
    printf 'wallet_health=%s\ncatalog=%s\norder=%s\n' \
      "$(if [[ -f "$ARTIFACT_DIR/wallet-health.txt" ]]; then cat "$ARTIFACT_DIR/wallet-health.txt"; else printf NOT_PROVEN; fi)" \
      "$(exact_marker_count 'M5_ALIPAY_FOCUSED::catalog::PASS' "$FLUTTER_LOG_PATH")" \
      "$(exact_marker_count 'M5_ALIPAY_FOCUSED::order::PASS' "$FLUTTER_LOG_PATH")"
    printf 'action_confirmation=%s\n' "$action_confirmation"
    printf 'native_success=%s\nquery_reconcile=%s\nsettlement=NOT_COLLECTED\n' \
      "$(exact_marker_count "$EXPECTED_NATIVE_MARKER" "$FLUTTER_LOG_PATH")" \
      "$(exact_marker_count 'M5_ALIPAY_FOCUSED::query_reconcile::PASS' "$FLUTTER_LOG_PATH")"
    printf 'tencent=NOT_RUN\nsms=NOT_RUN\navd_b=NOT_RUN\nreal_debit=forbidden\nraw_flutter_log=not_saved\n'
  } >"$ARTIFACT_DIR/summary.txt"
}

write_manifest() {
  [[ -n "$ARTIFACT_DIR" && -d "$ARTIFACT_DIR" ]] || return 0
  python3 - "$ARTIFACT_DIR" "$ARTIFACT_DIR/evidence-manifest.sha256" <<'PY'
import hashlib
import sys
from pathlib import Path
root = Path(sys.argv[1]).resolve()
manifest = Path(sys.argv[2]).resolve()
rows = []
for path in root.rglob("*"):
    if path.is_file() and not path.is_symlink() and path.resolve() != manifest:
        rows.append((path.relative_to(root).as_posix(), hashlib.sha256(path.read_bytes()).hexdigest()))
temporary = root / ".manifest.tmp"
with temporary.open("w", encoding="utf-8") as stream:
    for name, digest in sorted(rows):
        stream.write(f"{digest}  {name}\n")
temporary.replace(manifest)
PY
}

cleanup() {
  local incoming_status=$?
  set +e
  stop_runtime_token_feeder
  if [[ -n "$RELAY_PID" ]]; then
    kill "$RELAY_PID" 2>/dev/null || true
    wait "$RELAY_PID" 2>/dev/null || true
  fi
  clear_wallet_ui_dump
  if [[ -n "$ADB_BIN" ]]; then
    clear_runtime_token
  fi
  if [[ -n "$ANDROID_HOST_DIR" && -d "$ANDROID_HOST_DIR" &&
    ! -L "$ANDROID_HOST_DIR" ]]; then
    rm -rf -- "$ANDROID_HOST_DIR"
  fi
  if [[ -n "$ACTION_GATE_STATE_PARENT" && -n "$ACTION_GATE_STATE_DIR" &&
    "$ACTION_GATE_STATE_DIR" == "$ACTION_GATE_STATE_PARENT"/voice-social-alipay-success-gate.* &&
    -d "$ACTION_GATE_STATE_DIR" &&
    ! -L "$ACTION_GATE_STATE_DIR" ]]; then
    rm -rf -- "$ACTION_GATE_STATE_DIR"
  fi
  ACTION_GATE_STATE_DIR=''
  ACTION_GATE_STATE_PARENT=''
  ACTION_GATE_READY_FILE=''
  write_summary
  write_manifest
  trap - EXIT
  exit "$incoming_status"
}

self_test() {
  local root log scan_root
  root="$(mktemp -d /tmp/voice-social-alipay-success-self-test.XXXXXX)"
  trap 'rm -rf -- "$root"' RETURN
  log="$root/log"
  FLUTTER_LOG_PATH="$log"
  : >"$log"
  printf '%s\n%s\n' "$EXPECTED_NATIVE_MARKER" "$EXPECTED_BRIDGE_MARKER" >"$log"
  [[ "$(exact_marker_count 'M5_ALIPAY_FOCUSED::catalog::PASS' "$log")" == '0' ]] || exit 1
  [[ "$(grep -Fxc "$EXPECTED_NATIVE_MARKER" "$log")" -eq 1 ]] || exit 1
  [[ "$(grep -Fxc "$EXPECTED_BRIDGE_MARKER" "$log")" -eq 1 ]] || exit 1
  printf '%s\n%s\n%s\n' \
    "I/flutter ( 12345): $EXPECTED_NATIVE_MARKER" \
    "flutter: $EXPECTED_BRIDGE_MARKER" \
    "prefix-$EXPECTED_NATIVE_MARKER" |
    safe_flutter_log_filter >"$root/filtered.log"
  [[ "$(grep -Fxc "$EXPECTED_NATIVE_MARKER" "$root/filtered.log")" -eq 1 ]] || exit 1
  [[ "$(grep -Fxc "$EXPECTED_BRIDGE_MARKER" "$root/filtered.log")" -eq 1 ]] || exit 1
  [[ "$(grep -Fxc "prefix-$EXPECTED_NATIVE_MARKER" "$root/filtered.log" || true)" -eq 0 ]] || exit 1
  WALLET_UI_DUMP_PATH="$root/wallet.xml"
  printf '%s\n' '<hierarchy><node package="com.eg.android.AlipayGphoneRC" text="Scan" /><node package="com.eg.android.AlipayGphoneRC" text="Pay" /><node package="com.eg.android.AlipayGphoneRC" text="Home" /></hierarchy>' >"$WALLET_UI_DUMP_PATH"
  wallet_ui_is_healthy || exit 1
  printf '%s\n' '<hierarchy><node package="com.eg.android.AlipayGphoneRC" text="Scan" /><node package="com.eg.android.AlipayGphoneRC" text="Pay" /></hierarchy>' >"$WALLET_UI_DUMP_PATH"
  wallet_ui_is_healthy && exit 1
  printf '%s\n' '<hierarchy><node package="com.other.wallet" text="Scan" /><node package="com.other.wallet" text="Pay" /><node package="com.other.wallet" text="Home" /></hierarchy>' >"$WALLET_UI_DUMP_PATH"
  wallet_ui_is_healthy && exit 1
  printf '%s\n' '<hierarchy><node package="com.eg.android.AlipayGphoneRC" text="Please wait a minute" /><node package="com.eg.android.AlipayGphoneRC" text="Scan" /><node package="com.eg.android.AlipayGphoneRC" text="Pay" /><node package="com.eg.android.AlipayGphoneRC" text="Home" /></hierarchy>' >"$WALLET_UI_DUMP_PATH"
  wallet_ui_is_healthy && exit 1
  foreground_package_is_target 'mResumedActivity: ActivityRecord{com.eg.android.AlipayGphoneRC/com.alipay.android.msp.ui.views.MspContainerActivity}' || exit 1
  foreground_package_is_target 'mResumedActivity: ActivityRecord{com.other.wallet/.MainActivity}' && exit 1 || true
  scan_root="$root/artifact-scan"
  mkdir -p "$scan_root"
  ARTIFACT_DIR="$scan_root"
  RELAY_APP_TOKEN='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  RELAY_OPERATOR_TOKEN='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
  printf 'safe evidence\n' >"$scan_root/safe.txt"
  artifact_scan || exit 1
  printf '%s\n' "$RELAY_OPERATOR_TOKEN" >"$scan_root/operator-leak.txt"
  artifact_scan && exit 1
  unlink "$scan_root/operator-leak.txt"
  printf '%s\n' "$RELAY_APP_TOKEN" >"$scan_root/app-leak.txt"
  artifact_scan && exit 1
  unlink "$scan_root/app-leak.txt"
  printf '%s\n' '{"orderString":"app_id=fixture&sign=synthetic"}' >"$scan_root/payment-leak.log"
  artifact_scan && exit 1
  unlink "$scan_root/payment-leak.log"
  printf '%s\n' 'raw payment output' >"$scan_root/flutter-drive.raw.log"
  artifact_scan && exit 1
  unlink "$scan_root/flutter-drive.raw.log"
  [[ "$DEFAULT_SERIAL" == 'emulator-5554' ]] || exit 1
  if [[ "$SERIAL_VALUE" != "$DEFAULT_SERIAL" ]]; then
    exit 1
  fi
  printf 'SELF_TEST::PASS\n'
}

parse_args "$@"
validate_serial
if [[ "$SELF_TEST" == true ]]; then
  self_test
  exit 0
fi
validate_environment
resolve_commands
create_safe_artifact_dir
FLUTTER_LOG_PATH="$ARTIFACT_DIR/flutter-drive.log"
: >"$FLUTTER_LOG_PATH"
trap cleanup EXIT
attest_flutter
attest_backend
attest_backend_health
wallet_health_preflight
printf 'wallet-health=PASS\n' >"$ARTIFACT_DIR/wallet-health.txt"
start_action_relay
prepare_android_host
build_apk
"$ADB_BIN" -s "$SERIAL_VALUE" install -r "$ARTIFACT_DIR/app-debug.apk" >/dev/null 2>&1 ||
  fail_device 'focused success APK installation failed'
feed_runtime_token
run_flutter_drive
stop_runtime_token_feeder
clear_runtime_token
if [[ "$FLUTTER_STATUS" -ne 0 ]]; then
  fail_acceptance 'focused Flutter target failed'
fi
if [[ "$(exact_marker_count 'M5_ALIPAY_FOCUSED::action_confirmation::REQUIRED' "$FLUTTER_LOG_PATH")" -ne 1 ||
  "$(exact_marker_count 'M5_ALIPAY_FOCUSED::action_confirmation::GRANTED' "$FLUTTER_LOG_PATH")" -ne 1 ]]; then
  fail_acceptance 'action confirmation marker sequence missing'
fi
if [[ "$(cat "$ACTION_GATE_MARKER_FILE" 2>/dev/null || true)" != 'ACTION_CONFIRMATION_REQUIRED' ]]; then
  fail_acceptance 'action gate did not record the pending marker'
fi
if [[ "$(exact_marker_count "$EXPECTED_NATIVE_MARKER" "$FLUTTER_LOG_PATH")" -ne 1 ||
  "$(exact_marker_count "$EXPECTED_BRIDGE_MARKER" "$FLUTTER_LOG_PATH")" -ne 1 ||
  "$(exact_marker_count 'M5_ALIPAY_FOCUSED::query_reconcile::PASS' "$FLUTTER_LOG_PATH")" -ne 1 ||
  "$(exact_marker_count 'M5_ALIPAY_FOCUSED::complete::PASS' "$FLUTTER_LOG_PATH")" -ne 1 ||
  "$(exact_marker_count 'M5_ALIPAY_FOCUSED::complete::FAIL' "$FLUTTER_LOG_PATH")" -ne 0 ]]; then
  fail_acceptance 'focused success marker set is incomplete'
fi
artifact_scan || fail_acceptance 'artifact scan failed'
apk_scan || fail_acceptance 'APK scan failed'
RUN_RESULT='PASS'
FAIL_REASON='none'
printf 'ALIPAY_FOCUSED_SUCCESS::PASS\n'
exit 0
