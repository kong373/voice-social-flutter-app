#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

# PHYSICAL_DEVICE_DIAGNOSTIC is a separate cancellation-only lane.  It does
# not alter the emulator-5554 focused runner and never starts or discovers an
# emulator.  All Android commands are scoped to the one explicit serial.

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
readonly PROJECT_ROOT
readonly EXPECTED_FLUTTER_VERSION='3.44.7'
readonly EXPECTED_DART_VERSION='3.12.2'
readonly API_BASE_URL='http://127.0.0.1:18080/'
readonly REVERSE_SPEC='tcp:18080 tcp:18080'
readonly APP_PACKAGE='com.kong373.voice_social_app'
readonly TARGET_PACKAGE='com.eg.android.AlipayGphoneRC'
readonly TARGET_ACTIVITY='MspContainerActivity'
readonly TARGET_ISOLATION_ACTIVITY='com.kong373.alipay_app_pay.NativeAlipayIsolationActivity'
readonly OPERATOR_SCRIPT="$PROJECT_ROOT/tool/qa/m5_alipay_physical_device_cancel_operator.sh"
readonly INTEGRATION_TARGET='integration_test/alipay_native_isolation_smoke_test.dart'
readonly DRIVER_TARGET='test_driver/integration_test.dart'
readonly AUDIO_MANIFEST_SCRIPT="$PROJECT_ROOT/tool/prepare_android_audio_manifest.py"
readonly EXPECTED_NATIVE_MARKER='M5_ALIPAY_NATIVE_RESULT::sdkCompleted=0::resultStatus=6001'
readonly EXPECTED_BRIDGE_MARKER='M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::pay_task_returned'
readonly REJECTED_SUCCESS_MARKER='M5_ALIPAY_NATIVE_RESULT::sdkCompleted=1::resultStatus=9000'
readonly REJECTED_NONE_MARKER='M5_ALIPAY_NATIVE_RESULT::sdkCompleted=0::resultStatus=none'
readonly PHYSICAL_EVIDENCE_SCHEMA='alipay-physical-cancel-v1'
readonly EXPECTED_ISOLATION_MARKER_PREFIX='M5_ALIPAY_NATIVE_ISOLATION::'
readonly EXPECTED_ISOLATION_ENTER_MARKER_PREFIX="${EXPECTED_ISOLATION_MARKER_PREFIX}ENTER_TEST::"
readonly EXPECTED_PAYLOAD_STAGED_MARKER_PREFIX="${EXPECTED_ISOLATION_MARKER_PREFIX}PAYLOAD_STAGED::"
readonly EXPECTED_ISOLATION_START_MARKER_PREFIX="${EXPECTED_ISOLATION_MARKER_PREFIX}START::"
readonly EXPECTED_ISOLATION_LAUNCH_CALL_MARKER_PREFIX="${EXPECTED_ISOLATION_MARKER_PREFIX}LAUNCH_CALL::"
readonly EXPECTED_ISOLATION_LAUNCH_RETURN_MARKER_PREFIX="${EXPECTED_ISOLATION_MARKER_PREFIX}LAUNCH_RETURN::"
readonly EXPECTED_ISOLATION_RETURN_MARKER_PREFIX="${EXPECTED_ISOLATION_MARKER_PREFIX}PAYTASK_RETURN::"
readonly EXPECTED_ISOLATION_FAIL_MARKER_PREFIX="${EXPECTED_ISOLATION_MARKER_PREFIX}FAIL::"
readonly EXPECTED_PROBE_MARKER_PREFIX='M5_ALIPAY_PROBE_INVOCATION::'
readonly DEFAULT_PRE_LAUNCH_TIMEOUT_SECONDS=300
readonly DEFAULT_POST_LAUNCH_TIMEOUT_SECONDS=240
readonly DEFAULT_CASHIER_TIMEOUT_SECONDS=60
readonly DEFAULT_AFTER_BACK_TIMEOUT_SECONDS=8
readonly DEFAULT_MARKER_TIMEOUT_SECONDS=30
readonly DEFAULT_POLL_INTERVAL_SECONDS=1
readonly FLUTTER_REAP_TIMEOUT_SECONDS=10
readonly MAX_BACK_ATTEMPTS=2
readonly EXIT_CONFIGURATION=64
readonly EXIT_MARKER=65
readonly EXIT_DEVICE=69
readonly EXIT_TIMEOUT=70

SELF_TEST=false
SERIAL_VALUE=''
SERIAL_ARG=''
ARTIFACT_DIR_ARG=''
ARTIFACT_DIR=''
CONFIRM_CANCEL=''
DB_EVIDENCE_FILE=''
DB_EVIDENCE_FILE_ARG=''
DB_EVIDENCE_COMMAND=''
DB_EVIDENCE_COMMAND_ARG=''
DB_EVIDENCE_STATE_DIR=''
PUBLIC_OAUTH_CLIENT_ID="$(printenv QA_OAUTH_CLIENT_ID || true)"
PRE_LAUNCH_TIMEOUT_SECONDS="$DEFAULT_PRE_LAUNCH_TIMEOUT_SECONDS"
POST_LAUNCH_TIMEOUT_SECONDS="$DEFAULT_POST_LAUNCH_TIMEOUT_SECONDS"
CASHIER_TIMEOUT_SECONDS="$DEFAULT_CASHIER_TIMEOUT_SECONDS"
AFTER_BACK_TIMEOUT_SECONDS="$DEFAULT_AFTER_BACK_TIMEOUT_SECONDS"
MARKER_TIMEOUT_SECONDS="$DEFAULT_MARKER_TIMEOUT_SECONDS"
POLL_INTERVAL_SECONDS="$DEFAULT_POLL_INTERVAL_SECONDS"
STABLE_POLLS=3
ADB_BIN=''
FLUTTER_BIN=''
FLUTTER_LOG_PATH=''
FLUTTER_STATUS_PATH=''
OPERATOR_LOG_PATH=''
OPERATOR_STATUS_PATH=''
FLUTTER_PID=''
OPERATOR_PID=''
ANDROID_HOST_DIR=''
BACK_COUNT=0
SCREEN_WIDTH=0
SCREEN_HEIGHT=0
RUN_ID=''
RUN_STARTED_AT=0
ISOLATION_RUN_ID=''
PROBE_INVOCATION_ID=''
FLUTTER_SHA=''
BACKEND_SHA=''
RUN_RESULT='NOT_RUN'
FAIL_REASON='not_started'
FLUTTER_STATUS='NOT_RUN'
OPERATOR_STATUS='NOT_RUN'
DB_STATUS='NOT_PROVEN'
DB_PROVIDER_EVENTS='NOT_PROVEN'
DB_WALLET_TRANSACTIONS='NOT_PROVEN'
DB_LEDGER_JOURNALS='NOT_PROVEN'
DB_LEDGER_ENTRIES='NOT_PROVEN'
CANCEL_CONTRACT_VERIFIED=false
DB_START_COMPLETED=false
DB_COLLECT_COMPLETED=false

usage() {
  cat <<'USAGE'
Usage: run_alipay_physical_device_diagnostic.sh --serial ID --confirm-cancel [options]

PHYSICAL_DEVICE_DIAGNOSTIC runs one cancellation-only Alipay sandbox check on
one explicitly selected physical Android device. The Flutter target stages its
strict app-private isolation input and launches the debug-only native activity;
this host runner only starts the Flutter target, runs the bounded cancel
operator, and validates fixed markers. It never starts an emulator, discovers
devices, sends SMS, taps a coordinate, or confirms payment.

Required in live mode:
  --serial ID                 explicit physical-device serial
  --confirm-cancel            acknowledge the sandbox cancellation lane
  QA_OAUTH_CLIENT_ID          public OAuth client id in the environment
  QA_BACKEND_SHA (or M5_BACKEND_SHA)
                              40-hex backend commit attestation
  --db-evidence-file PATH     protected, sanitized post-run DB evidence JSON
                              (or QA_ALIPAY_PHYSICAL_DB_EVIDENCE_FILE)
  --db-evidence-command PATH  required two-phase read-only DB collector hook
                              (start before Flutter/order; collect after cancel)

Optional:
  --artifact-dir PATH         new absolute directory for redacted evidence
  --cashier-timeout SEC       bounded cashier wait (default: 60)
  --after-back-timeout SEC    bounded wait after each BACK (default: 8)
  --marker-timeout SEC        bounded native marker wait (default: 30)
  --post-launch-timeout SEC   bounded Flutter/operator completion wait (default: 240)
  --poll-interval SEC         poll delay (0 is allowed for self-tests)
  --stable-polls COUNT        consecutive cashier UI observations (default: 3)
  --self-test                 run offline contract and redaction checks
  --help                      show this help

The hook receives QA_ALIPAY_PHYSICAL_EVIDENCE_BASELINE_FILE for its private
start-phase UTC_TIMESTAMP(6)/MAX(id) baseline; it must not write the final
evidence path until collect.

The isolation test must emit one run-bound ENTER_TEST and PAYLOAD_STAGED; the
isolation activity must then emit one START,
PAYTASK_RETURN, and probe START/RETURN sequence. The only accepted native
cancellation evidence is exactly sdkCompleted=0/resultStatus=6001 together
with bridge=pay_task_returned. 9000, none, timeout, server-busy, stale,
missing, duplicate, or contradictory markers fail closed. Native or Dart
watchdog timeout is an explicit failure. The DB evidence must prove zero
provider events, wallet transactions, ledger journals, and ledger entries for
this run.
The post-run collector must query the scoped recharge_order rows and assert
provider=alipay-sandbox, database status=CANCELLED, and exactly one row; the
redacted evidence normalizes that status to CANCELED.
USAGE
}

fail_configuration() {
  RUN_RESULT='FAIL'
  FAIL_REASON="$1"
  printf 'PHYSICAL_DEVICE_DIAGNOSTIC: configuration rejected (%s)\n' "$1" >&2
  exit "$EXIT_CONFIGURATION"
}

fail_device() {
  RUN_RESULT='FAIL'
  FAIL_REASON="$1"
  printf 'PHYSICAL_DEVICE_DIAGNOSTIC: physical device rejected (%s)\n' "$1" >&2
  exit "$EXIT_DEVICE"
}

fail_marker() {
  RUN_RESULT='FAIL'
  FAIL_REASON="$1"
  printf 'PHYSICAL_DEVICE_DIAGNOSTIC: result marker rejected (%s)\n' "$1" >&2
  exit "$EXIT_MARKER"
}

fail_timeout() {
  RUN_RESULT='FAIL'
  FAIL_REASON="$1"
  printf 'PHYSICAL_DEVICE_DIAGNOSTIC: bounded wait expired (%s)\n' "$1" >&2
  exit "$EXIT_TIMEOUT"
}

audit() {
  printf 'PHYSICAL_DEVICE_DIAGNOSTIC::%s\n' "$1"
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
        [[ -z "$SERIAL_ARG" ]] || fail_configuration 'serial supplied more than once'
        SERIAL_ARG="$2"
        SERIAL_VALUE="$2"
        shift 2
        ;;
      --serial=*)
        [[ -z "$SERIAL_ARG" ]] || fail_configuration 'serial supplied more than once'
        SERIAL_ARG="${argument#*=}"
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
      --db-evidence-file)
        (($# >= 2)) || fail_configuration 'DB evidence file is missing'
        [[ -z "$DB_EVIDENCE_FILE_ARG" ]] || fail_configuration 'DB evidence file supplied more than once'
        DB_EVIDENCE_FILE_ARG="$2"
        shift 2
        ;;
      --db-evidence-file=*)
        [[ -z "$DB_EVIDENCE_FILE_ARG" ]] || fail_configuration 'DB evidence file supplied more than once'
        DB_EVIDENCE_FILE_ARG="${argument#*=}"
        shift
        ;;
      --db-evidence-command)
        (($# >= 2)) || fail_configuration 'DB evidence command is missing'
        [[ -z "$DB_EVIDENCE_COMMAND_ARG" ]] || fail_configuration 'DB evidence command supplied more than once'
        DB_EVIDENCE_COMMAND_ARG="$2"
        shift 2
        ;;
      --db-evidence-command=*)
        [[ -z "$DB_EVIDENCE_COMMAND_ARG" ]] || fail_configuration 'DB evidence command supplied more than once'
        DB_EVIDENCE_COMMAND_ARG="${argument#*=}"
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

validate_serial() {
  [[ -n "$SERIAL_ARG" ]] || fail_configuration '--serial is required; no default serial is allowed'
  [[ "$SERIAL_VALUE" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$ ]] || fail_configuration 'serial has an unsafe format'
  if [[ "$SERIAL_VALUE" =~ [Ee][Mm][Uu][Ll][Aa][Tt][Oo][Rr] || "$SERIAL_VALUE" =~ [Qq][Ee][Mm][Uu] ]]; then
    fail_configuration 'serial looks like an emulator or qemu target'
  fi
  if [[ -n "${ANDROID_SERIAL+x}" && -n "$ANDROID_SERIAL" && "$ANDROID_SERIAL" != "$SERIAL_VALUE" ]]; then
    fail_configuration 'ANDROID_SERIAL disagrees with --serial'
  fi
}

validate_path() {
  local name="$1" value="$2"
  [[ "$value" == /* && "$value" != *$'\n'* && "$value" != *$'\r'* && "$value" != *$'\t'* && "$value" != *'..'* ]] ||
    fail_configuration "$name must be an absolute path without traversal"
}

resolve_db_evidence_path() {
  if [[ -n "$DB_EVIDENCE_FILE_ARG" ]]; then
    DB_EVIDENCE_FILE="$DB_EVIDENCE_FILE_ARG"
  else
    DB_EVIDENCE_FILE="$(printenv QA_ALIPAY_PHYSICAL_DB_EVIDENCE_FILE || true)"
  fi
  [[ -n "$DB_EVIDENCE_FILE" ]] || fail_configuration 'DB evidence file is required for zero-mutation proof'
  validate_path DB-evidence-file "$DB_EVIDENCE_FILE"
  [[ ! -e "$DB_EVIDENCE_FILE" && ! -L "$DB_EVIDENCE_FILE" ]] ||
    fail_configuration 'DB evidence output must not pre-exist; stale static evidence is forbidden'
  local parent="${DB_EVIDENCE_FILE%/*}"
  [[ -n "$parent" && -d "$parent" && ! -L "$parent" ]] ||
    fail_configuration 'DB evidence parent directory is unavailable'
}

resolve_db_evidence_command() {
  [[ -n "$DB_EVIDENCE_COMMAND_ARG" ]] ||
    fail_configuration '--db-evidence-command is required for two-phase DB proof'
  DB_EVIDENCE_COMMAND="$DB_EVIDENCE_COMMAND_ARG"
  validate_path DB-evidence-command "$DB_EVIDENCE_COMMAND"
  [[ -f "$DB_EVIDENCE_COMMAND" && ! -L "$DB_EVIDENCE_COMMAND" && -x "$DB_EVIDENCE_COMMAND" ]] ||
    fail_configuration 'DB evidence command is not a private executable'
}

resolve_backend_sha() {
  local configured_qa configured_m5 configured_qa_m5
  configured_qa="$(printenv QA_BACKEND_SHA || true)"
  configured_m5="$(printenv M5_BACKEND_SHA || true)"
  configured_qa_m5="$(printenv QA_M5_BACKEND_SHA || true)"
  BACKEND_SHA="$configured_qa"
  [[ -z "$BACKEND_SHA" || -z "$configured_m5" || "$BACKEND_SHA" == "$configured_m5" ]] ||
    fail_configuration 'QA_BACKEND_SHA and M5_BACKEND_SHA disagree'
  [[ -n "$BACKEND_SHA" ]] || BACKEND_SHA="$configured_m5"
  [[ -z "$BACKEND_SHA" || -z "$configured_qa_m5" || "$BACKEND_SHA" == "$configured_qa_m5" ]] ||
    fail_configuration 'backend SHA environment values disagree'
  [[ -n "$BACKEND_SHA" ]] || BACKEND_SHA="$configured_qa_m5"
  [[ "$BACKEND_SHA" =~ ^[0-9a-fA-F]{40}$ ]] ||
    fail_configuration 'QA_BACKEND_SHA (or M5_BACKEND_SHA) must be a 40-hex commit SHA'
  BACKEND_SHA="$(printf '%s' "$BACKEND_SHA" | tr '[:upper:]' '[:lower:]')"
}

initialize_run_binding() {
  RUN_STARTED_AT="$(python3 -c 'import time; print(int(time.time()))')" ||
    fail_configuration 'run start time could not be established'
  [[ "$RUN_STARTED_AT" =~ ^[1-9][0-9]{0,11}$ ]] || fail_configuration 'run start time is invalid'
  RUN_ID="physical-${RUN_STARTED_AT}-$(python3 -c 'import uuid; print(uuid.uuid4().hex)')" ||
    fail_configuration 'run id could not be established'
  [[ "$RUN_ID" =~ ^[A-Za-z0-9_.:-]{1,96}$ ]] || fail_configuration 'run id is invalid'
  ISOLATION_RUN_ID="$(python3 -c 'import secrets; print(secrets.token_hex(16))')" ||
    fail_configuration 'native isolation run id could not be established'
  PROBE_INVOCATION_ID="$(python3 -c 'import secrets; print(secrets.token_hex(16))')" ||
    fail_configuration 'native probe id could not be established'
  [[ "$ISOLATION_RUN_ID" =~ ^[a-f0-9]{32}$ ]] ||
    fail_configuration 'native isolation run id is invalid'
  [[ "$PROBE_INVOCATION_ID" =~ ^[a-f0-9]{32}$ ]] ||
    fail_configuration 'native probe id is invalid'
  FLUTTER_SHA="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null)" ||
    fail_configuration 'Flutter source SHA could not be established'
  [[ "$FLUTTER_SHA" =~ ^[0-9a-fA-F]{40}$ ]] || fail_configuration 'Flutter source SHA is invalid'
  FLUTTER_SHA="$(printf '%s' "$FLUTTER_SHA" | tr '[:upper:]' '[:lower:]')"
}

validate_bounds() {
  require_integer cashier-timeout "$CASHIER_TIMEOUT_SECONDS"
  require_integer after-back-timeout "$AFTER_BACK_TIMEOUT_SECONDS"
  require_integer marker-timeout "$MARKER_TIMEOUT_SECONDS"
  require_integer post-launch-timeout "$POST_LAUNCH_TIMEOUT_SECONDS"
  require_integer poll-interval "$POLL_INTERVAL_SECONDS"
  require_integer stable-polls "$STABLE_POLLS"
  (( STABLE_POLLS >= 3 )) || fail_configuration 'stable poll count must be at least 3'
}

public_oauth_client_id_is_valid() {
  local value="$1" folded
  [[ -n "$value" && "$value" != *[[:space:]]* && "$value" != *'='* ]] || return 1
  folded="$(printf '%s' "$value" | LC_ALL=C tr '[:upper:]' '[:lower:]')" || return 1
  [[ ${#folded} -ge 1 && ${#folded} -le 256 ]] || return 1
  [[ "$folded" != *[![:print:]]* ]] || return 1
  [[ "$folded" != *secret* && "$folded" != *password* && "$folded" != *token* && "$folded" != *private* && "$folded" != *bearer* && "$folded" != *credential* ]] || return 1
  return 0
}

require_public_oauth_client_id() {
  [[ -z "${QA_OAUTH_CLIENT_SECRET+x}" && -z "${OAUTH_CLIENT_SECRET+x}" ]] || fail_configuration 'OAuth client secrets are forbidden'
  public_oauth_client_id_is_valid "$PUBLIC_OAUTH_CLIENT_ID" || fail_configuration 'QA_OAUTH_CLIENT_ID is missing or invalid'
}

oauth_client_dart_define() {
  public_oauth_client_id_is_valid "$1" || return 1
  printf '%s' "--dart-define=OAUTH_CLIENT_ID=$1"
}

resolve_commands() {
  ADB_BIN="$(command -v adb || true)"
  FLUTTER_BIN="$(command -v flutter || true)"
  [[ -n "$ADB_BIN" && -x "$ADB_BIN" ]] || fail_configuration 'adb executable is unavailable'
  [[ -n "$FLUTTER_BIN" && -x "$FLUTTER_BIN" ]] || fail_configuration 'Flutter executable is unavailable'
  for command_name in python3 git tar mktemp shasum awk grep wc head tail find tr ps sed env; do
    command -v "$command_name" >/dev/null 2>&1 || fail_configuration "missing command: $command_name"
  done
}

create_safe_directory() {
  if [[ -z "$ARTIFACT_DIR_ARG" ]]; then
    ARTIFACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/voice-social-alipay-physical.XXXXXX")" || fail_configuration 'artifact directory could not be created'
    return 0
  fi
  ARTIFACT_DIR="$ARTIFACT_DIR_ARG"
  validate_path artifact-directory "$ARTIFACT_DIR"
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

pause_between_polls() {
  if (( POLL_INTERVAL_SECONDS > 0 )); then sleep "$POLL_INTERVAL_SECONDS"; fi
}

adb_get_state() {
  local state='' status=0
  state="$("$ADB_BIN" -s "$SERIAL_VALUE" get-state 2>/dev/null)" || status=$?
  state="${state//$'\r'/}"
  state="${state//$'\n'/}"
  if [[ "$state" == 'offline' || "$state" == *offline* ]]; then fail_device 'selected serial is offline'; fi
  [[ "$status" -eq 0 && "$state" == device ]] || fail_device 'selected serial is not online'
}

read_prop() {
  local property="$1" value='' status=0
  value="$("$ADB_BIN" -s "$SERIAL_VALUE" shell getprop "$property" 2>/dev/null)" || status=$?
  [[ "$status" -eq 0 ]] || fail_device 'physical identity property is unavailable'
  value="${value//$'\r'/}"
  value="${value//$'\n'/}"
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* && "$value" != *$'\t'* ]] || fail_device 'physical identity property is unsafe'
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
  [[ "$qemu_values" != *1* && "$qemu_values" != *true* && "$qemu_values" != *qemu* ]] || fail_device 'qemu property is enabled'
  metadata="$(printf '%s\n' "$hardware" "$model" "$product" "$device" "$board" | tr '[:upper:]' '[:lower:]')"
  [[ ! "$metadata" =~ goldfish|ranchu|emulator|simulator|sdk_gphone|generic_x86|generic_x86_64|vbox|qemu ]] || fail_device 'device properties identify an emulator or qemu'
  [[ -n "${hardware}${model}${product}${device}${board}" ]] || fail_device 'physical identity is unavailable'
  audit 'DEVICE_ONLINE'
  audit 'PHYSICAL_DEVICE_VERIFIED'
}

read_screen_size() {
  local raw dimensions='' status=0
  raw="$("$ADB_BIN" -s "$SERIAL_VALUE" shell wm size 2>/dev/null)" || status=$?
  [[ "$status" -eq 0 ]] || fail_device 'dynamic screen size is unavailable'
  dimensions="$(printf '%s\n' "$raw" | awk 'match($0, /[0-9]+x[0-9]+/) { value=substr($0, RSTART, RLENGTH) } END { print value }')"
  [[ "$dimensions" =~ ^[1-9][0-9]{0,4}x[1-9][0-9]{0,4}$ ]] || fail_device 'dynamic screen size is invalid'
  SCREEN_WIDTH="${dimensions%x*}"
  SCREEN_HEIGHT="${dimensions#*x}"
  audit "SCREEN_SIZE_VERIFIED::width=${SCREEN_WIDTH}::height=${SCREEN_HEIGHT}"
}

verify_reverse() {
  local mappings='' status=0
  # Required host bridge: adb reverse tcp:18080 tcp:18080.
  "$ADB_BIN" -s "$SERIAL_VALUE" reverse tcp:18080 tcp:18080 >/dev/null 2>&1 || fail_device 'adb reverse tcp:18080 tcp:18080 failed'
  mappings="$("$ADB_BIN" -s "$SERIAL_VALUE" reverse --list 2>/dev/null)" || status=$?
  [[ "$status" -eq 0 ]] || fail_device 'adb reverse mapping cannot be inspected'
  grep -Eq '(^|[[:space:]])tcp:18080[[:space:]]+tcp:18080([[:space:]]|$)' <<<"$mappings" || fail_device 'adb reverse tcp:18080 tcp:18080 is missing'
  audit 'ADB_REVERSE_PASS::tcp=18080'
}

require_sandbox_wallet() {
  local packages='' status=0
  packages="$("$ADB_BIN" -s "$SERIAL_VALUE" shell pm list packages "$TARGET_PACKAGE" 2>/dev/null)" || status=$?
  [[ "$status" -eq 0 && "$packages" == *"package:${TARGET_PACKAGE}"* ]] || fail_device 'sandbox wallet package is not installed'
  audit 'SANDBOX_WALLET_PACKAGE_PASS'
}

force_stop_flutter_app() {
  "$ADB_BIN" -s "$SERIAL_VALUE" shell am force-stop "$APP_PACKAGE" >/dev/null 2>&1 || fail_device 'Flutter app process could not be stopped'
}

safe_flutter_log_filter() {
  # The Flutter tool's raw output is never persisted. Only fixed, run-bound
  # marker namespaces survive. Native logcat prefixes are stripped before the
  # allowlist is written to the private artifact log.
  python3 -u -c '
import re
import sys
isolation_run_id = re.escape(sys.argv[1])
probe_id = re.escape(sys.argv[2])
prefix = r"(?:[VDIWEF]/[A-Za-z0-9_.-]+\s*\(\s*[0-9]+\): )?"
isolation_failure_reasons = (
    "INVALID_LAUNCH", "ALREADY_ACTIVE", "STALE_RESULT", "PAYLOAD_REJECTED",
    "EXECUTOR_UNAVAILABLE", "REENTRY_REJECTED", "RESULT_WRITE_FAILED",
    "NATIVE_EXCEPTION", "NATIVE_UNAVAILABLE",
)
failure_stages = (
    "startup", "config", "files", "negative_launch", "negative_settle",
    "negative_check", "payload_stage", "native_launch", "native_wait",
    "authoritative_reconcile",
)
bridge_outcomes = (
    "pay_task_returned", "native_watchdog_timeout", "dart_watchdog_timeout",
    "native_not_invoked", "native_exception", "native_unavailable",
    "timeout", "server-busy", "none",
)
patterns = (
    re.compile(prefix + r"M5_ALIPAY_NATIVE_ISOLATION::(?:ENTER_TEST|PAYLOAD_STAGED|LAUNCH_CALL|LAUNCH_RETURN|START)::" + isolation_run_id + r"$"),
    re.compile(prefix + r"M5_ALIPAY_NATIVE_ISOLATION::PAYTASK_RETURN::" + isolation_run_id + r"::(?:resultStatus=(?:none|[A-Za-z0-9_.-]{1,32})::sdkCompleted=[01]|sdkCompleted=[01]::resultStatus=(?:none|[A-Za-z0-9_.-]{1,32}))$"),
    re.compile(prefix + r"M5_ALIPAY_NATIVE_ISOLATION::FAIL::" + isolation_run_id + r"::reason=(?:" + "|".join(isolation_failure_reasons) + r")$"),
    re.compile(prefix + r"M5_ALIPAY_NATIVE_ISOLATION::FAIL_STAGE::(?:" + "|".join(failure_stages) + r")$"),
    re.compile(prefix + r"M5_ALIPAY_PROBE_INVOCATION::(?:START|RETURN)::" + probe_id + r"$"),
    re.compile(prefix + r"M5_ALIPAY_NATIVE_RESULT::sdkCompleted=[01]::resultStatus=[A-Za-z0-9_.-]{1,32}$"),
    re.compile(prefix + r"M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::(?:" + "|".join(bridge_outcomes) + r")$"),
    re.compile(prefix + r"M5_ALIPAY_FOCUSED::(?:catalog|order|native_launcher|query_reconcile|complete)::(?:START|PASS|FAIL)$"),
)
prefix_re = re.compile(prefix)
for raw in sys.stdin:
    line = raw.rstrip("\r\n")
    for pattern in patterns:
        if pattern.fullmatch(line) is not None:
            print(prefix_re.sub("", line, count=1), flush=True)
            break
' "$ISOLATION_RUN_ID" "$PROBE_INVOCATION_ID"
}

exact_marker_count() {
  local marker="$1" count='0'
  [[ -f "$FLUTTER_LOG_PATH" && ! -L "$FLUTTER_LOG_PATH" ]] || { printf '0'; return; }
  count="$(grep -Fxc -- "$marker" "$FLUTTER_LOG_PATH" 2>/dev/null || true)"
  [[ "$count" =~ ^[0-9]+$ ]] || count=0
  printf '%s' "$count"
}

safe_artifact_scan() {
  python3 - "$ARTIFACT_DIR" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
for path in root.rglob("*"):
    if not path.is_file() or path.is_symlink():
        continue
    payload = path.read_bytes().lower()
    forbidden = (
        b"orderstr=", b"orderstr:", b"orderstring=", b"orderstring:",
        b"orderinfo=", b"orderinfo:", b"private_key", b"private key",
        b"bearer ", b"access_token=", b"access_token:", b"client_secret",
        b"password=", b"authorization:",
    )
    if any(needle in payload for needle in forbidden):
        raise SystemExit(1)
PY
}

verify_zero_mutations() {
  [[ -f "$DB_EVIDENCE_FILE" && ! -L "$DB_EVIDENCE_FILE" && -r "$DB_EVIDENCE_FILE" ]] || {
    DB_STATUS='FAIL'
    FAIL_REASON='db_evidence_missing'
    return 1
  }
  local result=''
  result="$(PYTHONDONTWRITEBYTECODE=1 python3 -B "$PROJECT_ROOT/tool/qa/m5_alipay_physical_zero_mutation_validator.py" \
    "$DB_EVIDENCE_FILE" "$SERIAL_VALUE" "$RUN_ID" "$RUN_STARTED_AT" "$FLUTTER_SHA" "$BACKEND_SHA" 2>/dev/null)" || {
    DB_STATUS='FAIL'
    FAIL_REASON='db_evidence_invalid_or_nonzero'
    return 1
  }
  IFS=' ' read -r DB_PROVIDER_EVENTS DB_WALLET_TRANSACTIONS DB_LEDGER_JOURNALS DB_LEDGER_ENTRIES <<<"$result"
  [[ "$DB_PROVIDER_EVENTS" == 0 && "$DB_WALLET_TRANSACTIONS" == 0 && "$DB_LEDGER_JOURNALS" == 0 && "$DB_LEDGER_ENTRIES" == 0 ]] || {
    DB_STATUS='FAIL'
    FAIL_REASON='db_evidence_invalid_or_nonzero'
    return 1
  }
  DB_STATUS='PASS'
  audit 'DB_ZERO_MUTATIONS_PASS'
}

run_db_evidence_hook() {
  local phase="$1"
  [[ "$phase" == start || "$phase" == collect ]] || fail_configuration 'invalid DB evidence phase'
  [[ -n "$DB_EVIDENCE_COMMAND" ]] || fail_configuration 'DB evidence command is unavailable'
  local status=0
  # The start phase must record a private DB UTC_TIMESTAMP(6) plus MAX(id)
  # baselines before Flutter creates an order.  The collect phase must query
  # only rows after that baseline, assert recharge_order.status=CANCELLED
  # (the DB spelling), exactly one alipay-sandbox row, and four zero deltas;
  # it then writes normalized CANCELED evidence.  The validator binds that
  # file to this run's random id, serial, commit SHAs, and start time.
  # Hook stdout/stderr is never persisted or printed.
  set +e
  env \
    QA_ALIPAY_PHYSICAL_EVIDENCE_PHASE="$phase" \
    QA_ALIPAY_PHYSICAL_RUN_ID="$RUN_ID" \
    QA_ALIPAY_PHYSICAL_SERIAL="$SERIAL_VALUE" \
    QA_ALIPAY_PHYSICAL_RUN_STARTED_AT="$RUN_STARTED_AT" \
    QA_ALIPAY_PHYSICAL_FLUTTER_SHA="$FLUTTER_SHA" \
    QA_ALIPAY_PHYSICAL_BACKEND_SHA="$BACKEND_SHA" \
    QA_ALIPAY_PHYSICAL_DB_EVIDENCE_FILE="$DB_EVIDENCE_FILE" \
    QA_ALIPAY_PHYSICAL_EVIDENCE_STATE_DIR="$DB_EVIDENCE_STATE_DIR" \
    QA_ALIPAY_PHYSICAL_EVIDENCE_BASELINE_FILE="$DB_EVIDENCE_STATE_DIR/baseline.json" \
    QA_ALIPAY_PHYSICAL_EVIDENCE_SCHEMA="$PHYSICAL_EVIDENCE_SCHEMA" \
    "$DB_EVIDENCE_COMMAND" >/dev/null 2>&1
  status=$?
  set -e
  [[ "$status" -eq 0 ]] || {
    FAIL_REASON="db_evidence_${phase}_hook_failed"
    return 1
  }
  if [[ "$phase" == start ]]; then
    DB_START_COMPLETED=true
  else
    DB_COLLECT_COMPLETED=true
  fi
}

prepare_android_host() {
  ANDROID_HOST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/voice-social-alipay-physical-host.XXXXXX")" || fail_configuration 'temporary Android host could not be created'
  "$FLUTTER_BIN" create --platforms=android --android-language=kotlin --org=com.kong373 --project-name=voice_social_app --no-pub "$ANDROID_HOST_DIR" >/dev/null 2>&1 || fail_configuration 'temporary Android host generation failed'
  git -C "$PROJECT_ROOT" archive --format=tar HEAD | tar -x -C "$ANDROID_HOST_DIR" || fail_configuration 'tracked checkout overlay failed'
  [[ -f "$AUDIO_MANIFEST_SCRIPT" ]] || fail_configuration 'Android audio manifest helper is missing'
  python3 "$AUDIO_MANIFEST_SCRIPT" "$ANDROID_HOST_DIR" >/dev/null 2>&1 || fail_configuration 'Android audio manifest preparation failed'
  (cd "$ANDROID_HOST_DIR" && "$FLUTTER_BIN" pub get --enforce-lockfile >/dev/null 2>&1) || fail_configuration 'locked Flutter dependency regeneration failed'
}

attest_flutter_sdk() {
  local version_json versions framework_version dart_version
  version_json="$($FLUTTER_BIN --version --machine 2>/dev/null)" || fail_configuration 'Flutter version probe failed'
  versions="$(printf '%s' "$version_json" | python3 -c 'import json,sys; p=json.load(sys.stdin); print(p.get("frameworkVersion", "")); print(p.get("dartSdkVersion", ""))')" || fail_configuration 'Flutter version metadata is invalid'
  framework_version="$(printf '%s\n' "$versions" | sed -n '1p')"
  dart_version="$(printf '%s\n' "$versions" | sed -n '2p')"
  [[ "$framework_version" == "$EXPECTED_FLUTTER_VERSION" ]] || fail_configuration 'Flutter 3.44.7 is required'
  [[ "$dart_version" == "$EXPECTED_DART_VERSION" ]] || fail_configuration 'Dart 3.12.2 is required'
  audit 'FLUTTER_3_44_7_PASS'
}

run_flutter_target() {
  set +e
  (
    cd "$ANDROID_HOST_DIR"
    env -u QA_OAUTH_CLIENT_ID -u QA_OAUTH_CLIENT_SECRET -u OAUTH_CLIENT_SECRET -u QA_ALIPAY_PHYSICAL_DB_EVIDENCE_FILE \
      "$FLUTTER_BIN" drive --no-pub --keep-app-running \
      --driver="$DRIVER_TARGET" --target="$INTEGRATION_TARGET" --device-id="$SERIAL_VALUE" \
      --dart-define=BACKEND_MODE=live --dart-define=APP_ENV=development \
      --dart-define=ALLOW_INSECURE_HTTP=true --dart-define=API_BASE_URL="$API_BASE_URL" \
      --dart-define=API_TIMEOUT_SECONDS=15 --dart-define=ENABLE_TENCENT_IM=false \
      --dart-define=ENABLE_ALIPAY_APP_PAY=true --dart-define=CLIENT_TYPE=Android \
      --dart-define=CLIENT_INNER_VERSION=6 \
      --dart-define=PHYSICAL_DEVICE_DIAGNOSTIC_RUN_ID="$RUN_ID" \
      --dart-define=PHYSICAL_DEVICE_DIAGNOSTIC_RUN_STARTED_AT="$RUN_STARTED_AT" \
      --dart-define=QA_ALIPAY_NATIVE_ISOLATION_RUN_ID="$ISOLATION_RUN_ID" \
      --dart-define=QA_ALIPAY_PROBE_INVOCATION_ID="$PROBE_INVOCATION_ID" \
      --dart-define=QA_ALIPAY_NATIVE_ISOLATION_NEGATIVE_ONLY=false \
      "$(oauth_client_dart_define "$PUBLIC_OAUTH_CLIENT_ID")" 2>&1
  ) | safe_flutter_log_filter >"$FLUTTER_LOG_PATH"
  local status="${PIPESTATUS[0]}"
  printf '%s\n' "$status" >"$FLUTTER_STATUS_PATH"
  set -e
  return "$status"
}

start_operator() {
  set +e
  (
    env -u QA_OAUTH_CLIENT_ID -u QA_OAUTH_CLIENT_SECRET -u OAUTH_CLIENT_SECRET \
      ANDROID_SERIAL="$SERIAL_VALUE" "$OPERATOR_SCRIPT" --adb "$ADB_BIN" --serial "$SERIAL_VALUE" \
      --flutter-log "$FLUTTER_LOG_PATH" --cashier-timeout "$CASHIER_TIMEOUT_SECONDS" \
      --after-back-timeout "$AFTER_BACK_TIMEOUT_SECONDS" --marker-timeout "$MARKER_TIMEOUT_SECONDS" \
      --poll-interval "$POLL_INTERVAL_SECONDS" --stable-polls "$STABLE_POLLS" >"$OPERATOR_LOG_PATH" 2>&1
    local status=$?
    printf '%s\n' "$status" >"$OPERATOR_STATUS_PATH"
    exit "$status"
  ) &
  OPERATOR_PID=$!
  set -e
}

process_alive() {
  local pid="$1"
  [[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 0 ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

terminate_process() {
  local pid="$1" deadline
  process_alive "$pid" || return 0
  kill -TERM "$pid" 2>/dev/null || true
  deadline=$((SECONDS + FLUTTER_REAP_TIMEOUT_SECONDS))
  while process_alive "$pid" && (( SECONDS <= deadline )); do sleep 1; done
  process_alive "$pid" && kill -KILL "$pid" 2>/dev/null || true
}

isolation_marker() {
  local prefix="$1"
  printf '%s%s' "$prefix" "$ISOLATION_RUN_ID"
}

probe_marker() {
  local stage="$1"
  printf '%s%s::%s' "$EXPECTED_PROBE_MARKER_PREFIX" "$stage" "$PROBE_INVOCATION_ID"
}

wait_for_isolation_marker() {
  local marker="$1" success_audit="$2" timeout_seconds="$3"
  local deadline=$((SECONDS + timeout_seconds)) count='0' fail_count='0'
  while (( SECONDS <= deadline )); do
    count="$(exact_marker_count "$marker")"
    if [[ "$count" == 1 ]]; then
      audit "$success_audit"
      return 0
    fi
    [[ "$count" == 0 ]] || fail_marker 'isolation marker is stale or duplicated'
    fail_count="$(grep -Ec "^${EXPECTED_ISOLATION_FAIL_MARKER_PREFIX}${ISOLATION_RUN_ID}::reason=" "$FLUTTER_LOG_PATH" 2>/dev/null || true)"
    [[ "$fail_count" == 0 ]] || fail_marker 'native isolation failed before the awaited marker'
    [[ ! -s "$FLUTTER_STATUS_PATH" ]] || fail_marker 'Flutter target ended before isolation marker'
    pause_between_polls
  done
  fail_timeout 'isolation marker was not observed'
}

wait_for_isolation_payload_staged() {
  wait_for_isolation_marker \
    "$(isolation_marker "$EXPECTED_PAYLOAD_STAGED_MARKER_PREFIX")" \
    'ISOLATION_PAYLOAD_STAGED_PASS' "$PRE_LAUNCH_TIMEOUT_SECONDS"
}

wait_for_isolation_start() {
  wait_for_isolation_marker \
    "$(isolation_marker "$EXPECTED_ISOLATION_START_MARKER_PREFIX")" \
    'ISOLATION_NATIVE_START_PASS' "$MARKER_TIMEOUT_SECONDS"
}

# Kept as a compatibility alias for callers that used the focused runner's
# old name. The marker contract is now the debug-only isolation activity.
wait_for_native_launcher_start() {
  wait_for_isolation_start
}

wait_for_completion() {
  local deadline=$((SECONDS + POST_LAUNCH_TIMEOUT_SECONDS))
  while (( SECONDS <= deadline )); do
    if ! process_alive "$FLUTTER_PID" && ! process_alive "$OPERATOR_PID"; then return 0; fi
    pause_between_polls
  done
  return 1
}

evaluate_marker_contract() {
  local native_count bridge_count isolation_return_count isolation_cancel_count
  local enter_count staged_count start_count launch_call_count launch_return_count
  local probe_start_count probe_return_count isolation_fail_count
  native_count="$(exact_marker_count "$EXPECTED_NATIVE_MARKER")"
  bridge_count="$(exact_marker_count "$EXPECTED_BRIDGE_MARKER")"
  enter_count="$(exact_marker_count "$(isolation_marker "$EXPECTED_ISOLATION_ENTER_MARKER_PREFIX")")"
  staged_count="$(exact_marker_count "$(isolation_marker "$EXPECTED_PAYLOAD_STAGED_MARKER_PREFIX")")"
  start_count="$(exact_marker_count "$(isolation_marker "$EXPECTED_ISOLATION_START_MARKER_PREFIX")")"
  launch_call_count="$(exact_marker_count "$(isolation_marker "$EXPECTED_ISOLATION_LAUNCH_CALL_MARKER_PREFIX")")"
  launch_return_count="$(exact_marker_count "$(isolation_marker "$EXPECTED_ISOLATION_LAUNCH_RETURN_MARKER_PREFIX")")"
  probe_start_count="$(exact_marker_count "$(probe_marker START)")"
  probe_return_count="$(exact_marker_count "$(probe_marker RETURN)")"
  isolation_return_count="$(grep -Ec "^${EXPECTED_ISOLATION_RETURN_MARKER_PREFIX}${ISOLATION_RUN_ID}::" "$FLUTTER_LOG_PATH" 2>/dev/null || true)"
  isolation_cancel_count="$(exact_marker_count "$(isolation_marker "$EXPECTED_ISOLATION_RETURN_MARKER_PREFIX")::resultStatus=6001::sdkCompleted=0")"
  isolation_fail_count="$(grep -Ec "^${EXPECTED_ISOLATION_FAIL_MARKER_PREFIX}${ISOLATION_RUN_ID}::reason=" "$FLUTTER_LOG_PATH" 2>/dev/null || true)"
  [[ "$isolation_fail_count" == 0 ]] || {
    FAIL_REASON='isolation_activity_failed'
    return 1
  }
  [[ "$native_count" == 1 && "$bridge_count" == 1 ]] || {
    FAIL_REASON='trusted_cancel_marker_pair_missing_or_duplicated'
    return 1
  }
  [[ "$enter_count" == 1 && "$staged_count" == 1 && "$start_count" == 1 &&
    "$launch_call_count" == 1 && "$launch_return_count" == 1 &&
    "$probe_start_count" == 1 && "$probe_return_count" == 1 ]] || {
    FAIL_REASON='isolation_marker_missing_or_duplicated'
    return 1
  }
  [[ "$isolation_return_count" == 1 && "$isolation_cancel_count" == 1 ]] || {
    FAIL_REASON='isolation_paytask_return_missing_or_not_cancel'
    return 1
  }
  if [[ "$(exact_marker_count "$REJECTED_SUCCESS_MARKER")" != 0 ||
    "$(exact_marker_count "$REJECTED_NONE_MARKER")" != 0 ]] ||
    grep -Eq 'M5_ALIPAY_NATIVE_RESULT::sdkCompleted=1::|M5_ALIPAY_NATIVE_RESULT::[^[:space:]]*resultStatus=(9000|none)|M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::(timeout|server-busy|none)' "$FLUTTER_LOG_PATH"; then
    FAIL_REASON='non_cancel_or_incomplete_native_result'
    return 1
  fi
  for marker in \
    'M5_ALIPAY_FOCUSED::catalog::PASS' \
    'M5_ALIPAY_FOCUSED::order::PASS' \
    'M5_ALIPAY_FOCUSED::native_launcher::START' \
    'M5_ALIPAY_FOCUSED::native_launcher::PASS' \
    'M5_ALIPAY_FOCUSED::query_reconcile::PASS' \
    'M5_ALIPAY_FOCUSED::complete::PASS'; do
    [[ "$(exact_marker_count "$marker")" == 1 ]] || { FAIL_REASON='focused_flow_marker_missing'; return 1; }
  done
  return 0
}

summary_native_marker_count() {
  [[ -f "$FLUTTER_LOG_PATH" && ! -L "$FLUTTER_LOG_PATH" ]] || {
    printf '0'
    return 0
  }
  local count=''
  count="$(grep -Ec '^M5_ALIPAY_NATIVE_RESULT::sdkCompleted=[01]::resultStatus=[A-Za-z0-9_.-]{1,32}$' "$FLUTTER_LOG_PATH" 2>/dev/null || true)"
  [[ "$count" =~ ^[0-9]+$ ]] || count=0
  printf '%s' "$count"
}

summary_bridge_marker_count() {
  [[ -f "$FLUTTER_LOG_PATH" && ! -L "$FLUTTER_LOG_PATH" ]] || {
    printf '0'
    return 0
  }
  local count=''
  count="$(grep -Ec '^M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::(pay_task_returned|native_watchdog_timeout|dart_watchdog_timeout|native_not_invoked|native_exception|native_unavailable|timeout|server-busy|none)$' "$FLUTTER_LOG_PATH" 2>/dev/null || true)"
  [[ "$count" =~ ^[0-9]+$ ]] || count=0
  printf '%s' "$count"
}

summary_native_marker_value() {
  local count line sdk status
  count="$(summary_native_marker_count)"
  if [[ "$count" == 0 ]]; then
    printf 'NOT_OBSERVED'
    return 0
  fi
  if [[ "$count" != 1 ]]; then
    printf 'AMBIGUOUS'
    return 0
  fi
  line="$(grep -E '^M5_ALIPAY_NATIVE_RESULT::sdkCompleted=[01]::resultStatus=[A-Za-z0-9_.-]{1,32}$' "$FLUTTER_LOG_PATH" 2>/dev/null | head -n 1 || true)"
  sdk="${line#M5_ALIPAY_NATIVE_RESULT::sdkCompleted=}"
  status="${sdk#*::resultStatus=}"
  sdk="${sdk%%::*}"
  [[ "$sdk" == 0 || "$sdk" == 1 ]] || sdk='UNTRUSTED'
  case "$status" in
    6001|9000|none|processing|4000|4001|5000|8000|unknown) ;;
    *) status='UNTRUSTED' ;;
  esac
  printf 'sdkCompleted=%s,resultStatus=%s' "$sdk" "$status"
}

summary_bridge_marker_value() {
  local count line value
  count="$(summary_bridge_marker_count)"
  if [[ "$count" == 0 ]]; then
    printf 'NOT_OBSERVED'
    return 0
  fi
  if [[ "$count" != 1 ]]; then
    printf 'AMBIGUOUS'
    return 0
  fi
  line="$(grep -E '^M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::(pay_task_returned|native_watchdog_timeout|dart_watchdog_timeout|native_not_invoked|native_exception|native_unavailable|timeout|server-busy|none)$' "$FLUTTER_LOG_PATH" 2>/dev/null | head -n 1 || true)"
  value="${line#M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::}"
  case "$value" in
    pay_task_returned|native_watchdog_timeout|dart_watchdog_timeout|native_not_invoked|native_exception|native_unavailable|timeout|server-busy|none) ;;
    *) value='UNTRUSTED' ;;
  esac
  printf '%s' "$value"
}

summary_native_result_value() {
  local native bridge
  native="$(summary_native_marker_value)"
  bridge="$(summary_bridge_marker_value)"
  if [[ "$native" == NOT_OBSERVED && "$bridge" == NOT_OBSERVED ]]; then
    printf 'NOT_OBSERVED'
  else
    printf '%s,bridge=%s' "$native" "$bridge"
  fi
}

summary_flutter_failure_value() {
  local bridge native
  bridge="$(summary_bridge_marker_value)"
  native="$(summary_native_marker_value)"
  case "$bridge" in
    dart_watchdog_timeout|native_watchdog_timeout|native_not_invoked|native_exception|native_unavailable|timeout|server-busy|none)
      printf '%s' "$bridge"
      return 0
      ;;
  esac
  if [[ "$native" == *'resultStatus=none' ]]; then
    printf 'none'
    return 0
  fi
  if [[ -f "$FLUTTER_LOG_PATH" && ! -L "$FLUTTER_LOG_PATH" ]] &&
    [[ "$(exact_marker_count 'M5_ALIPAY_FOCUSED::complete::FAIL')" == 1 ]]; then
    printf 'focused_flow_failed'
    return 0
  fi
  case "$FAIL_REASON" in
    post_launch_watchdog_timeout|native_launcher_start_timeout)
      printf 'watchdog_timeout'
      ;;
    focused_flutter_target_failed*)
      printf 'flutter_target_failed'
      ;;
    *)
      printf 'NOT_OBSERVED'
      ;;
  esac
}

summary_operator_failure_value() {
  if [[ -f "$OPERATOR_LOG_PATH" && ! -L "$OPERATOR_LOG_PATH" ]]; then
    if grep -Fq 'Alipay cashier UI contains unsafe state' "$OPERATOR_LOG_PATH" ||
      grep -Fq 'Alipay cashier UI is not safely cancellable' "$OPERATOR_LOG_PATH"; then
      printf 'unsafe_cashier_ui'
      return 0
    fi
    if grep -Fq 'result marker rejected' "$OPERATOR_LOG_PATH"; then
      printf 'marker_rejected'
      return 0
    fi
    if grep -Fq 'bounded wait expired' "$OPERATOR_LOG_PATH"; then
      printf 'bounded_wait_expired'
      return 0
    fi
    if grep -Fq 'physical device rejected' "$OPERATOR_LOG_PATH"; then
      printf 'physical_device_rejected'
      return 0
    fi
  fi
  if [[ "$OPERATOR_STATUS" == 0 ]]; then
    printf 'none'
  elif [[ "$OPERATOR_STATUS" =~ ^[0-9]+$ ]]; then
    printf 'operator_exit_nonzero'
  else
    printf 'NOT_OBSERVED'
  fi
}

summary_db_phases() {
  if [[ "$DB_START_COMPLETED" == true && "$DB_COLLECT_COMPLETED" == true ]]; then
    printf 'start,collect'
  elif [[ "$DB_START_COMPLETED" == true ]]; then
    printf 'start'
  elif [[ "$DB_COLLECT_COMPLETED" == true ]]; then
    printf 'collect'
  else
    printf 'none'
  fi
}

write_summary() {
  [[ -n "$ARTIFACT_DIR" && -d "$ARTIFACT_DIR" ]] || return 0
  local native_result flutter_failure operator_failure db_phases
  local accepted=false conclusion='PHYSICAL_DEVICE_DIAGNOSTIC_FAIL'
  local payment_status='NOT_PROVEN' canceled_order_count='NOT_PROVEN'
  local provider_events='NOT_PROVEN' wallet_transactions='NOT_PROVEN'
  local ledger_journals='NOT_PROVEN' ledger_entries='NOT_PROVEN'
  local observed_at='NOT_PROVEN' db_zero_mutations='NOT_PROVEN'
  local isolation_entered='NOT_OBSERVED' isolation_staged='NOT_OBSERVED'
  local isolation_started='NOT_OBSERVED'
  local isolation_returned='NOT_OBSERVED' probe_started='NOT_OBSERVED' probe_returned='NOT_OBSERVED'
  native_result="$(summary_native_result_value)"
  flutter_failure="$(summary_flutter_failure_value)"
  operator_failure="$(summary_operator_failure_value)"
  db_phases="$(summary_db_phases)"
  if [[ -n "$ISOLATION_RUN_ID" ]]; then
    isolation_entered="$(exact_marker_count "$(isolation_marker "$EXPECTED_ISOLATION_ENTER_MARKER_PREFIX")")"
    isolation_staged="$(exact_marker_count "$(isolation_marker "$EXPECTED_PAYLOAD_STAGED_MARKER_PREFIX")")"
    isolation_started="$(exact_marker_count "$(isolation_marker "$EXPECTED_ISOLATION_START_MARKER_PREFIX")")"
    isolation_returned="$(grep -Ec "^${EXPECTED_ISOLATION_RETURN_MARKER_PREFIX}${ISOLATION_RUN_ID}::" "$FLUTTER_LOG_PATH" 2>/dev/null || true)"
  fi
  if [[ -n "$PROBE_INVOCATION_ID" ]]; then
    probe_started="$(exact_marker_count "$(probe_marker START)")"
    probe_returned="$(exact_marker_count "$(probe_marker RETURN)")"
  fi
  # A successful-looking marker is never enough for artifact success.  The
  # summary may claim CANCELED/count=1/zero only after the exact native pair,
  # successful operator, and the collect-phase validator all passed.
  if [[ "$RUN_RESULT" == PASS && "$CANCEL_CONTRACT_VERIFIED" == true &&
    "$DB_COLLECT_COMPLETED" == true && "$DB_STATUS" == PASS &&
    "$native_result" == 'sdkCompleted=0,resultStatus=6001,bridge=pay_task_returned' ]]; then
    accepted=true
    conclusion='PHYSICAL_DEVICE_DIAGNOSTIC_PASS'
    payment_status='CANCELED'
    canceled_order_count=1
    provider_events=0
    wallet_transactions=0
    ledger_journals=0
    ledger_entries=0
    observed_at='attested'
    db_zero_mutations='PASS'
  fi
  {
    printf 'lane=PHYSICAL_DEVICE_DIAGNOSTIC\nconclusion=%s\n' "$conclusion"
    printf 'device_class=physical\nserial=redacted\napi_base=127.0.0.1:18080\nreverse=tcp:18080->tcp:18080\n'
    printf 'flutter_version=%s\ndart_version=%s\n' "$EXPECTED_FLUTTER_VERSION" "$EXPECTED_DART_VERSION"
    printf 'flutter_sha=%s\nbackend_sha=%s\nrun_id=redacted\nisolation_run_id=redacted\nprobe_invocation_id=redacted\nrun_started_at=attested\nobserved_at=%s\n' "$FLUTTER_SHA" "$BACKEND_SHA" "$observed_at"
    printf 'screen_width=%s\nscreen_height=%s\n' "$SCREEN_WIDTH" "$SCREEN_HEIGHT"
    printf 'flutter_status=%s\noperator_status=%s\nback_attempts=%s\n' "$FLUTTER_STATUS" "$OPERATOR_STATUS" "$BACK_COUNT"
    printf 'native_cancel=%s\nnative_result=%s\n' "$native_result" "$native_result"
    printf 'isolation_markers=enter_test:%s,staged:%s,start:%s,paytask_return:%s,probe_start:%s,probe_return:%s\n' "$isolation_entered" "$isolation_staged" "$isolation_started" "$isolation_returned" "$probe_started" "$probe_returned"
    printf 'flutter_failure=%s\noperator_failure=%s\n' "$flutter_failure" "$operator_failure"
    printf 'payment_provider=alipay-sandbox\npayment_status=%s\ncanceled_order_count=%s\n' "$payment_status" "$canceled_order_count"
    printf 'payment_provider_events=%s\nprovider_events=%s\nwallet_transactions=%s\nledger_journals=%s\nledger_entries=%s\n' "$provider_events" "$provider_events" "$wallet_transactions" "$ledger_journals" "$ledger_entries"
    printf 'db_zero_mutations=%s\ndb_evidence_phases=%s\nevidence_binding=serial+run_id+flutter_sha+backend_sha+run_started_at+observed_at\nsecrets=redacted\nacceptance_gate=%s\nreason=%s\nraw_flutter_log=not_saved\n' "$db_zero_mutations" "$db_phases" "$accepted" "$FAIL_REASON"
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
    rows.append((path.relative_to(root).as_posix(), hashlib.sha256(path.read_bytes()).hexdigest()))
temporary = root / ".evidence-manifest.tmp"
with temporary.open("w", encoding="utf-8") as stream:
    for relative, digest in sorted(rows):
        stream.write(f"{digest}  {relative}\n")
os.replace(temporary, manifest)
PY
}

cleanup() {
  local status=$?
  set +e
  [[ -n "$OPERATOR_PID" ]] && terminate_process "$OPERATOR_PID"
  [[ -n "$FLUTTER_PID" ]] && terminate_process "$FLUTTER_PID"
  if [[ -n "$ANDROID_HOST_DIR" && -d "$ANDROID_HOST_DIR" && ! -L "$ANDROID_HOST_DIR" ]]; then
    rm -rf -- "$ANDROID_HOST_DIR"
    ANDROID_HOST_DIR=''
  fi
  if [[ -n "$DB_EVIDENCE_STATE_DIR" && -d "$DB_EVIDENCE_STATE_DIR" && ! -L "$DB_EVIDENCE_STATE_DIR" ]]; then
    rm -rf -- "$DB_EVIDENCE_STATE_DIR"
    DB_EVIDENCE_STATE_DIR=''
  fi
  if [[ -n "$ARTIFACT_DIR" && -d "$ARTIFACT_DIR" ]]; then
    if ! safe_artifact_scan; then
      RUN_RESULT='FAIL'
      FAIL_REASON='artifact_secret_scan_failed'
      printf 'status=FAIL\n' >"$ARTIFACT_DIR/artifact-secret-scan.txt"
      status=1
    else
      printf 'status=PASS\n' >"$ARTIFACT_DIR/artifact-secret-scan.txt"
    fi
    write_summary
    write_manifest
  fi
  trap - EXIT
  exit "$status"
}

self_test() {
  (
    set -Eeuo pipefail
    local root artifact
    root="$(mktemp -d /tmp/voice-social-alipay-physical-self-test.XXXXXX)"
    trap 'rm -rf -- "$root"' EXIT
    [[ "$API_BASE_URL" == 'http://127.0.0.1:18080/' ]] || exit 1
    [[ "$REVERSE_SPEC" == 'tcp:18080 tcp:18080' ]] || exit 1
    [[ "$MAX_BACK_ATTEMPTS" == 2 ]] || exit 1
    [[ "$EXPECTED_FLUTTER_VERSION" == '3.44.7' ]] || exit 1
    [[ "$TARGET_ACTIVITY" == 'MspContainerActivity' ]] || exit 1
    [[ "$TARGET_ISOLATION_ACTIVITY" == 'com.kong373.alipay_app_pay.NativeAlipayIsolationActivity' ]] || exit 1
    [[ "$EXPECTED_ISOLATION_MARKER_PREFIX" == 'M5_ALIPAY_NATIVE_ISOLATION::' ]] || exit 1
    public_oauth_client_id_is_valid 'fixture-public-client' || exit 1
    for invalid in '' 'public client' 'public-client-secret' 'public_token'; do
      public_oauth_client_id_is_valid "$invalid" && exit 1
    done
    RUN_ID='physical-self-test'
    RUN_STARTED_AT="$(python3 -c 'import time; print(int(time.time()))')"
    FLUTTER_SHA="$(python3 -c 'print("2" * 40)')"
    BACKEND_SHA="$(python3 -c 'print("1" * 40)')"
    ISOLATION_RUN_ID='0123456789abcdef0123456789abcdef'
    PROBE_INVOCATION_ID='fedcba9876543210fedcba9876543210'
    [[ "$ISOLATION_RUN_ID" =~ ^[a-f0-9]{32}$ ]] || exit 1
    [[ "$PROBE_INVOCATION_ID" =~ ^[a-f0-9]{32}$ ]] || exit 1
    audit 'ISOLATION_IDS_PASS'
    local db_file="$root/db.json"
    DB_EVIDENCE_FILE="$db_file"
    SERIAL_VALUE='R58PHYSICAL001'
    DB_EVIDENCE_STATE_DIR="$root/state"
    mkdir -m 700 "$DB_EVIDENCE_STATE_DIR"
    DB_EVIDENCE_COMMAND="$root/evidence-hook.sh"
    printf '%s\n' \
      '#!/usr/bin/env bash' \
      'set -Eeuo pipefail' \
      'phase="${QA_ALIPAY_PHYSICAL_EVIDENCE_PHASE:?}"' \
      'state="${QA_ALIPAY_PHYSICAL_EVIDENCE_STATE_DIR:?}"' \
      'printf "%s\\n" "$phase" >>"$state/phases"' \
      'if [[ "$phase" == start ]]; then' \
      '  printf "%s\\n" baseline >"$QA_ALIPAY_PHYSICAL_EVIDENCE_BASELINE_FILE"' \
      '  exit 0' \
      'fi' \
      '[[ "$phase" == collect && -f "$QA_ALIPAY_PHYSICAL_EVIDENCE_BASELINE_FILE" ]] || exit 1' \
      'observed="$(python3 -c "import time; print(int(time.time()))")"' \
      'printf "%s\\n" "{\"schema\":\"$QA_ALIPAY_PHYSICAL_EVIDENCE_SCHEMA\",\"status\":\"OK\",\"serial\":\"$QA_ALIPAY_PHYSICAL_SERIAL\",\"flutterSha\":\"$QA_ALIPAY_PHYSICAL_FLUTTER_SHA\",\"backendSha\":\"$QA_ALIPAY_PHYSICAL_BACKEND_SHA\",\"runId\":\"$QA_ALIPAY_PHYSICAL_RUN_ID\",\"runStartedAt\":$QA_ALIPAY_PHYSICAL_RUN_STARTED_AT,\"observedAt\":$observed,\"evidenceSource\":\"read-only-db\",\"payment\":{\"provider\":\"alipay-sandbox\",\"status\":\"CANCELED\",\"databaseStatus\":\"CANCELLED\",\"canceledOrderCount\":1},\"writeCounters\":{\"payment_provider_events\":0,\"wallet_transactions\":0,\"ledger_journals\":0,\"ledger_entries\":0},\"secrets\":false}" >"$QA_ALIPAY_PHYSICAL_DB_EVIDENCE_FILE"' \
      >"$DB_EVIDENCE_COMMAND"
    chmod 700 "$DB_EVIDENCE_COMMAND"
    run_db_evidence_hook start || exit 1
    grep -Fqx 'start' "$DB_EVIDENCE_STATE_DIR/phases" || exit 1
    [[ -f "$DB_EVIDENCE_STATE_DIR/baseline.json" && ! -L "$DB_EVIDENCE_STATE_DIR/baseline.json" ]] || exit 1
    [[ ! -e "$db_file" && ! -L "$db_file" ]] || exit 1
    audit 'DB_START_BEFORE_FLUTTER_PASS'
    run_db_evidence_hook collect || exit 1
    grep -Fqx 'collect' "$DB_EVIDENCE_STATE_DIR/phases" || exit 1
    verify_zero_mutations || exit 1
    audit 'DB_COLLECT_AFTER_CANCEL_PASS'
    local failing_hook="$root/failing-hook.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 1' >"$failing_hook"
    chmod 700 "$failing_hook"
    DB_EVIDENCE_COMMAND="$failing_hook"
    run_db_evidence_hook start && exit 1
    run_db_evidence_hook collect && exit 1
    audit 'DB_HOOK_FAILURE_FAIL_CLOSED_PASS'
    artifact="$root/artifact"
    mkdir -m 700 "$artifact"
    ARTIFACT_DIR="$artifact"
    FLUTTER_LOG_PATH="$root/success-flutter.log"
    printf '%s\n' \
      "$(isolation_marker "$EXPECTED_ISOLATION_ENTER_MARKER_PREFIX")" \
      "$(isolation_marker "$EXPECTED_PAYLOAD_STAGED_MARKER_PREFIX")" \
      "$(isolation_marker "$EXPECTED_ISOLATION_START_MARKER_PREFIX")" \
      "$(isolation_marker "$EXPECTED_ISOLATION_LAUNCH_CALL_MARKER_PREFIX")" \
      "$(isolation_marker "$EXPECTED_ISOLATION_LAUNCH_RETURN_MARKER_PREFIX")" \
      "$(isolation_marker "$EXPECTED_ISOLATION_RETURN_MARKER_PREFIX")::resultStatus=6001::sdkCompleted=0" \
      "$(probe_marker START)" \
      "$(probe_marker RETURN)" \
      "$EXPECTED_NATIVE_MARKER" \
      "$EXPECTED_BRIDGE_MARKER" \
      'M5_ALIPAY_FOCUSED::catalog::PASS' \
      'M5_ALIPAY_FOCUSED::order::PASS' \
      'M5_ALIPAY_FOCUSED::native_launcher::START' \
      'M5_ALIPAY_FOCUSED::native_launcher::PASS' \
      'M5_ALIPAY_FOCUSED::query_reconcile::PASS' \
      'M5_ALIPAY_FOCUSED::complete::PASS' >"$FLUTTER_LOG_PATH"
    evaluate_marker_contract || exit 1
    audit 'ISOLATION_MARKER_FILTER_PASS'
    OPERATOR_LOG_PATH="$root/success-operator.log"
    : >"$OPERATOR_LOG_PATH"
    SCREEN_WIDTH=1440
    SCREEN_HEIGHT=3200
    RUN_RESULT='PASS'
    FAIL_REASON='none'
    CANCEL_CONTRACT_VERIFIED=true
    DB_START_COMPLETED=true
    DB_COLLECT_COMPLETED=true
    DB_STATUS='PASS'
    DB_PROVIDER_EVENTS=0
    DB_WALLET_TRANSACTIONS=0
    DB_LEDGER_JOURNALS=0
    DB_LEDGER_ENTRIES=0
    BACK_COUNT=1
    FLUTTER_STATUS=0
    OPERATOR_STATUS=0
    write_summary
    grep -Fqx 'conclusion=PHYSICAL_DEVICE_DIAGNOSTIC_PASS' "$artifact/summary.txt" || exit 1
    grep -Fqx 'native_result=sdkCompleted=0,resultStatus=6001,bridge=pay_task_returned' "$artifact/summary.txt" || exit 1
    grep -Fqx 'payment_status=CANCELED' "$artifact/summary.txt" || exit 1
    grep -Fqx 'canceled_order_count=1' "$artifact/summary.txt" || exit 1
    grep -Fqx 'db_zero_mutations=PASS' "$artifact/summary.txt" || exit 1
    grep -Fqx 'acceptance_gate=true' "$artifact/summary.txt" || exit 1

    FLUTTER_LOG_PATH="$root/isolation-marker-input.log"
    local stale_isolation_id='ffffffffffffffffffffffffffffffff'
    printf '%s\n' \
      "I/flutter ( 101): $(isolation_marker "$EXPECTED_PAYLOAD_STAGED_MARKER_PREFIX")" \
      "I/VoiceAlipayIsolation( 102): $(isolation_marker "$EXPECTED_ISOLATION_START_MARKER_PREFIX")" \
      "I/VoiceAlipayIsolation( 102): $(isolation_marker "$EXPECTED_ISOLATION_RETURN_MARKER_PREFIX")::resultStatus=6001::sdkCompleted=0" \
      "I/flutter ( 101): $(probe_marker START)" \
      "I/flutter ( 101): ${EXPECTED_PAYLOAD_STAGED_MARKER_PREFIX}${stale_isolation_id}" \
      'I/flutter ( 101): raw-private-value-must-not-escape' \
      "I/VoiceAlipayIsolation( 102): $(isolation_marker "$EXPECTED_ISOLATION_RETURN_MARKER_PREFIX")::resultStatus=6001::sdkCompleted=0::private=raw-private-value" >"$FLUTTER_LOG_PATH"
    local filtered="$root/isolation-filtered.log"
    safe_flutter_log_filter <"$FLUTTER_LOG_PATH" >"$filtered"
    grep -Fqx "$(isolation_marker "$EXPECTED_PAYLOAD_STAGED_MARKER_PREFIX")" "$filtered" || exit 1
    grep -Fqx "$(isolation_marker "$EXPECTED_ISOLATION_START_MARKER_PREFIX")" "$filtered" || exit 1
    grep -Fqx "$(isolation_marker "$EXPECTED_ISOLATION_RETURN_MARKER_PREFIX")::resultStatus=6001::sdkCompleted=0" "$filtered" || exit 1
    grep -Fq "$stale_isolation_id" "$filtered" && exit 1 || true
    grep -Fq 'raw-private-value' "$filtered" && exit 1 || true
    audit 'ISOLATION_MARKER_FILTER_PASS'

    FLUTTER_LOG_PATH="$root/isolation-negative.log"
    printf '%s\n' \
      "$(isolation_marker "$EXPECTED_ISOLATION_ENTER_MARKER_PREFIX")" \
      "$(isolation_marker "$EXPECTED_PAYLOAD_STAGED_MARKER_PREFIX")" \
      "$(isolation_marker "$EXPECTED_ISOLATION_START_MARKER_PREFIX")" \
      "$(isolation_marker "$EXPECTED_ISOLATION_LAUNCH_CALL_MARKER_PREFIX")" \
      "$(isolation_marker "$EXPECTED_ISOLATION_LAUNCH_RETURN_MARKER_PREFIX")" \
      "$(isolation_marker "$EXPECTED_ISOLATION_FAIL_MARKER_PREFIX")::reason=NATIVE_EXCEPTION" >"$FLUTTER_LOG_PATH"
    evaluate_marker_contract && exit 1 || true
    [[ "$FAIL_REASON" == 'isolation_activity_failed' ]] || exit 1
    audit 'ISOLATION_NEGATIVE_MARKER_PASS'

    FLUTTER_LOG_PATH="$root/isolation-early-fail.log"
    FLUTTER_STATUS_PATH="$root/isolation-early-fail.status"
    : >"$FLUTTER_STATUS_PATH"
    printf '%s\n' \
      "$(isolation_marker "$EXPECTED_ISOLATION_FAIL_MARKER_PREFIX")::reason=EXECUTOR_UNAVAILABLE" \
      >"$FLUTTER_LOG_PATH"
    set +e
    (
      wait_for_isolation_marker \
        "$(isolation_marker "$EXPECTED_ISOLATION_START_MARKER_PREFIX")" \
        'MUST_NOT_PASS' 10
    ) >/dev/null 2>&1
    local early_fail_status=$?
    set -e
    [[ "$early_fail_status" == "$EXIT_MARKER" ]] || exit 1
    audit 'ISOLATION_EARLY_FAIL_FAST_PASS'

    FLUTTER_LOG_PATH="$root/flutter-drive.log"
    printf '%s\n%s\n%s\n' \
      'M5_ALIPAY_NATIVE_RESULT::sdkCompleted=0::resultStatus=none' \
      'M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::dart_watchdog_timeout' \
      'M5_ALIPAY_FOCUSED::complete::FAIL' >"$FLUTTER_LOG_PATH"
    OPERATOR_LOG_PATH="$root/cancel-operator.log"
    printf '%s\n' \
      'PHYSICAL_DEVICE_DIAGNOSTIC operator: physical device rejected (Alipay cashier UI contains unsafe state)' \
      >"$OPERATOR_LOG_PATH"
    SCREEN_WIDTH=1440
    SCREEN_HEIGHT=3200
    RUN_RESULT='FAIL'
    FAIL_REASON='physical cancellation operator failed'
    CANCEL_CONTRACT_VERIFIED=false
    DB_START_COMPLETED=true
    DB_COLLECT_COMPLETED=false
    DB_STATUS='NOT_PROVEN'
    DB_PROVIDER_EVENTS='NOT_PROVEN'
    DB_WALLET_TRANSACTIONS='NOT_PROVEN'
    DB_LEDGER_JOURNALS='NOT_PROVEN'
    DB_LEDGER_ENTRIES='NOT_PROVEN'
    BACK_COUNT=1
    FLUTTER_STATUS='TIMEOUT'
    OPERATOR_STATUS=69
    write_summary
    grep -Fqx 'lane=PHYSICAL_DEVICE_DIAGNOSTIC' "$artifact/summary.txt" || exit 1
    grep -Fqx 'device_class=physical' "$artifact/summary.txt" || exit 1
    grep -Fqx 'serial=redacted' "$artifact/summary.txt" || exit 1
    grep -Fqx 'native_result=sdkCompleted=0,resultStatus=none,bridge=dart_watchdog_timeout' "$artifact/summary.txt" || exit 1
    grep -Fqx 'flutter_failure=dart_watchdog_timeout' "$artifact/summary.txt" || exit 1
    grep -Fqx 'operator_failure=unsafe_cashier_ui' "$artifact/summary.txt" || exit 1
    grep -Fqx 'payment_status=NOT_PROVEN' "$artifact/summary.txt" || exit 1
    grep -Fqx 'canceled_order_count=NOT_PROVEN' "$artifact/summary.txt" || exit 1
    grep -Fqx 'payment_provider_events=NOT_PROVEN' "$artifact/summary.txt" || exit 1
    grep -Fqx 'wallet_transactions=NOT_PROVEN' "$artifact/summary.txt" || exit 1
    grep -Fqx 'ledger_journals=NOT_PROVEN' "$artifact/summary.txt" || exit 1
    grep -Fqx 'ledger_entries=NOT_PROVEN' "$artifact/summary.txt" || exit 1
    grep -Fqx 'db_zero_mutations=NOT_PROVEN' "$artifact/summary.txt" || exit 1
    grep -Fqx 'db_evidence_phases=start' "$artifact/summary.txt" || exit 1
    grep -Fqx 'acceptance_gate=false' "$artifact/summary.txt" || exit 1
    grep -Fq 'native_cancel=sdkCompleted=0,resultStatus=6001' "$artifact/summary.txt" && exit 1 || true
    grep -Fq 'payment_status=CANCELED' "$artifact/summary.txt" && exit 1 || true
    grep -Fq 'canceled_order_count=1' "$artifact/summary.txt" && exit 1 || true
    grep -Fq 'db_zero_mutations=PASS' "$artifact/summary.txt" && exit 1 || true
    grep -Fqi 'emulator_pass' "$artifact/summary.txt" && exit 1 || true
    grep -Fqi 'R58PHYSICAL001' "$artifact/summary.txt" && exit 1 || true
    safe_artifact_scan || exit 1
    grep -E '^(native_result|flutter_failure|operator_failure|payment_status|canceled_order_count|payment_provider_events|wallet_transactions|ledger_journals|ledger_entries|db_zero_mutations|db_evidence_phases|acceptance_gate)=' "$artifact/summary.txt"
    audit 'ISOLATION_WATCHDOG_FAIL_CLOSED_PASS'
    audit 'SUMMARY_FAIL_CLOSED_PASS'
    audit 'ARTIFACT_REDACTION_PASS'
    audit 'PHYSICAL_DEVICE_DIAGNOSTIC_PASS'
  )
  printf 'SELF_TEST::PASS\n'
}

parse_args "$@"
if [[ "$SELF_TEST" == true ]]; then
  self_test
  exit 0
fi

validate_serial
validate_bounds
[[ "$CONFIRM_CANCEL" == I_UNDERSTAND_SANDBOX_CANCEL ]] || fail_configuration 'explicit --confirm-cancel acknowledgement is required'
resolve_db_evidence_path
resolve_db_evidence_command
require_public_oauth_client_id
[[ -x "$OPERATOR_SCRIPT" ]] || fail_configuration 'physical cancellation operator is missing or not executable'
[[ -f "$PROJECT_ROOT/pubspec.yaml" && -f "$PROJECT_ROOT/$INTEGRATION_TARGET" && -f "$PROJECT_ROOT/$DRIVER_TARGET" ]] || fail_configuration 'physical Flutter target is missing'
resolve_commands
create_safe_directory
FLUTTER_LOG_PATH="$ARTIFACT_DIR/flutter-drive.log"
FLUTTER_STATUS_PATH="$ARTIFACT_DIR/flutter-drive.status"
OPERATOR_LOG_PATH="$ARTIFACT_DIR/cancel-operator.log"
OPERATOR_STATUS_PATH="$ARTIFACT_DIR/cancel-operator.status"
: >"$FLUTTER_LOG_PATH"
: >"$FLUTTER_STATUS_PATH"
: >"$OPERATOR_LOG_PATH"
: >"$OPERATOR_STATUS_PATH"
trap cleanup EXIT

git_status="$(git -C "$PROJECT_ROOT" status --porcelain=v1 --untracked-files=all --ignore-submodules=none)" || fail_configuration 'Flutter checkout status is unavailable'
[[ -z "$git_status" ]] || fail_configuration 'Flutter checkout must be clean for physical acceptance'
resolve_backend_sha
initialize_run_binding
DB_EVIDENCE_STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/voice-social-alipay-physical-evidence.XXXXXX")" ||
  fail_configuration 'DB evidence state directory could not be created'
chmod 700 "$DB_EVIDENCE_STATE_DIR" || fail_configuration 'DB evidence state permissions failed'
DB_EVIDENCE_STATE_DIR="$(cd "$DB_EVIDENCE_STATE_DIR" && pwd -P)" ||
  fail_configuration 'DB evidence state canonicalization failed'
run_db_evidence_hook start || fail_device "$FAIL_REASON"
[[ -f "$DB_EVIDENCE_STATE_DIR/baseline.json" && ! -L "$DB_EVIDENCE_STATE_DIR/baseline.json" ]] ||
  fail_device 'DB evidence start phase did not publish a private baseline'
[[ ! -e "$DB_EVIDENCE_FILE" && ! -L "$DB_EVIDENCE_FILE" ]] ||
  fail_device 'DB evidence start phase wrote final output too early'

adb_get_state
verify_physical_device
verify_reverse
read_screen_size
require_sandbox_wallet
attest_flutter_sdk
force_stop_flutter_app
prepare_android_host

audit 'START'
audit 'SINGLE_EXPLICIT_SERIAL'
audit 'CANCEL_ONLY'
audit 'NO_REAL_DEBIT'
run_flutter_target &
FLUTTER_PID=$!
wait_for_isolation_payload_staged
wait_for_isolation_start
start_operator
if ! wait_for_completion; then
  RUN_RESULT='FAIL'
  FAIL_REASON='post_launch_watchdog_timeout'
  FLUTTER_STATUS='TIMEOUT'
  OPERATOR_STATUS='TIMEOUT'
  fail_timeout 'Flutter/operator completion watchdog'
fi
if [[ -s "$FLUTTER_STATUS_PATH" ]]; then FLUTTER_STATUS="$(tr -d '[:space:]' <"$FLUTTER_STATUS_PATH")"; fi
if [[ -n "$OPERATOR_PID" ]]; then
  wait "$OPERATOR_PID" || true
  if [[ -s "$OPERATOR_STATUS_PATH" ]]; then OPERATOR_STATUS="$(tr -d '[:space:]' <"$OPERATOR_STATUS_PATH")"; fi
fi
if [[ -s "$FLUTTER_STATUS_PATH" && "$FLUTTER_STATUS" != 0 ]]; then
  FAIL_REASON='focused_flutter_target_failed'
  fail_marker 'Flutter target failed'
fi
evaluate_marker_contract || fail_marker "$FAIL_REASON"
[[ "$OPERATOR_STATUS" == 0 ]] || fail_marker 'physical cancellation operator failed'
CANCEL_CONTRACT_VERIFIED=true
BACK_COUNT="$(awk -F= '/^PHYSICAL_DEVICE_DIAGNOSTIC::KEYCODE_BACK_SENT::attempt=/ { value = $NF } END { print value + 0 }' "$OPERATOR_LOG_PATH")"
run_db_evidence_hook collect || fail_device "$FAIL_REASON"
verify_zero_mutations || fail_device "$FAIL_REASON"
RUN_RESULT='PASS'
FAIL_REASON='none'
audit 'PASS'
exit 0
