#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

# This script is intentionally host-agnostic apart from requiring a running,
# hardware-accelerated Android emulator. GitHub Actions supplies all QA_*
# inputs; no production endpoint or credential is accepted.

readonly PROJECT_ROOT="$(pwd -P)"
readonly ARTIFACT_ROOT="${QA_ARTIFACT_ROOT:?QA_ARTIFACT_ROOT is required}"
readonly AVD_ID="${QA_AVD_ID:?QA_AVD_ID is required}"
readonly API_LEVEL="${QA_API_LEVEL:?QA_API_LEVEL is required}"
readonly AVD_PROFILE="${QA_PROFILE:?QA_PROFILE is required}"
readonly QA_SCOPE_VALUE="${QA_SCOPE:?QA_SCOPE is required}"
readonly BACKEND_MODE_VALUE="${QA_BACKEND_MODE:?QA_BACKEND_MODE is required}"
readonly BASELINE_REQUIRED="${QA_BASELINE_REQUIRED:-false}"
readonly BASELINE_ARTIFACT_DIR="${QA_BASELINE_ARTIFACT_DIR:-}"
readonly BASELINE_ARTIFACT_NAME="${QA_BASELINE_ARTIFACT_NAME:-voice-social-app-debug}"
readonly BASELINE_RUN_ID="${QA_BASELINE_RUN_ID:-unknown}"
readonly EXPECTED_BASELINE_SHA256="${QA_EXPECTED_BASELINE_SHA256:-}"
readonly APPROVED_BASELINE_SHA256="6e1f7d70a22b1b754b60df9555dffb80d839c5c82aaa6c3628d7104ff77631b3"
readonly APPROVED_BASELINE_RUN_ID="31873662636"
readonly APPROVED_BASELINE_ARTIFACT="voice-social-app-debug"
readonly GIT_SHA_VALUE="${QA_GIT_SHA:-$(git rev-parse HEAD 2>/dev/null || printf 'unknown')}"
readonly RUN_ID_VALUE="${QA_RUN_ID:-local}"
readonly RUN_ATTEMPT_VALUE="${QA_RUN_ATTEMPT:-1}"
readonly MONKEY_EVENTS="${QA_MONKEY_EVENTS:-0}"
readonly OFFLINE_SOAK_SECONDS="${QA_OFFLINE_SOAK_SECONDS:-1800}"
readonly QUALITY_RESULT="${QA_QUALITY_RESULT:-unknown}"

readonly LOG_DIR="$ARTIFACT_ROOT/logs"
readonly SCREENSHOT_DIR="$ARTIFACT_ROOT/screenshots"
readonly VIDEO_DIR="$ARTIFACT_ROOT/videos"
readonly DUMP_DIR="$ARTIFACT_ROOT/dumps"
readonly PERF_DIR="$ARTIFACT_ROOT/performance"
readonly APK_DIR="$ARTIFACT_ROOT/apk"
readonly TEST_RESULT_DIR="$ARTIFACT_ROOT/test-results"
readonly RUNNER_PROGRESS_FILE="$ARTIFACT_ROOT/runner-progress.log"

readonly ENVIRONMENT_FILE="$ARTIFACT_ROOT/environment.txt"
readonly BUILD_INFO_FILE="$ARTIFACT_ROOT/build_info.txt"
readonly APK_SHA_FILE="$ARTIFACT_ROOT/apk_sha256.txt"
readonly AVD_MATRIX_FILE="$ARTIFACT_ROOT/avd_matrix.csv"
readonly PAGE_COVERAGE_FILE="$ARTIFACT_ROOT/page_coverage.csv"
readonly STATE_MATRIX_FILE="$ARTIFACT_ROOT/state_matrix.csv"
readonly ROLE_MATRIX_FILE="$ARTIFACT_ROOT/role_matrix.csv"
readonly TEST_CASES_FILE="$ARTIFACT_ROOT/test_cases.csv"
readonly DEFECTS_FILE="$ARTIFACT_ROOT/defects.csv"
readonly P1_REGRESSION_FILE="$ARTIFACT_ROOT/p1_regression.csv"
readonly LOGCAT_FILE="$ARTIFACT_ROOT/logcat-full.txt"
readonly PERFORMANCE_FILE="$ARTIFACT_ROOT/performance.txt"
readonly SUMMARY_FILE="$ARTIFACT_ROOT/summary.txt"

readonly PACKAGE_VERSION_VALUE="0.5.0+5"
readonly REMOTE_VIDEO_PREFIX="/sdcard/m24-${AVD_ID}"

FAIL_COUNT=0
DEFECT_COUNTER=0
LAST_DEFECT_ID=""
DEVICE_ID=""
LOGCAT_PID=""
SCREENRECORD_PID=""
SCREENRECORD_REMOTE=""
SCREENRECORD_LOCAL=""
BASELINE_APK=""
BASELINE_PACKAGE=""
QA_APK=""
QA_PACKAGE=""
MOCK_DEBUG_APK=""
MOCK_DEBUG_PACKAGE=""
MOCK_DEBUG_SHA256=""
MOCK_DEBUG_TEMP_DIR=""
APK_ANALYZER=""
AAPT_TOOL=""
PAGE_COVERAGE_STATUS="NOT_RUN"
OFFLINE_STATUS="NOT_RUN"
EXPECTED_PHYSICAL_SIZE=""
EXPECTED_DENSITY=""
EXPECTED_VIEWPORT=""
EXPECTED_DPR=""
ACTUAL_MEDIA_QUERY="NOT_CAPTURED"
ACTUAL_DPR="NOT_CAPTURED"
ACTUAL_FONT_SCALE="NOT_CAPTURED"
INTEGRATION_SUITE_STARTED=0
declare -A INTEGRATION_RESULTS=()
declare -A INTEGRATION_DEFECTS=()

mkdir -p \
  "$ARTIFACT_ROOT" \
  "$LOG_DIR" \
  "$SCREENSHOT_DIR" \
  "$VIDEO_DIR" \
  "$DUMP_DIR" \
  "$PERF_DIR" \
  "$APK_DIR" \
  "$TEST_RESULT_DIR"

touch \
  "$ENVIRONMENT_FILE" \
  "$BUILD_INFO_FILE" \
  "$APK_SHA_FILE" \
  "$LOGCAT_FILE" \
  "$PERFORMANCE_FILE" \
  "$RUNNER_PROGRESS_FILE"

csv_row() {
  local output_file="$1"
  shift
  local value
  local escaped
  local separator=""
  for value in "$@"; do
    escaped="${value//\"/\"\"}"
    printf '%s"%s"' "$separator" "$escaped" >>"$output_file"
    separator=","
  done
  printf '\n' >>"$output_file"
}

initialize_csv_files() {
  : >"$AVD_MATRIX_FILE"
  csv_row "$AVD_MATRIX_FILE" \
    avd api_level android_version abi device_model physical_resolution density \
    media_query_size device_pixel_ratio font_scale locale timezone free_storage \
    result notes

  : >"$PAGE_COVERAGE_FILE"
  csv_row "$PAGE_COVERAGE_FILE" \
    page_id page_name widget_class source_path user_entry qa_entry required_role \
    precondition required_states implemented avd_a_open avd_b_open \
    all_buttons_clicked viewport_360x800 viewport_390x844 font_scale_1_3 \
    keyboard scroll screenshot video log result defect_id notes

  : >"$STATE_MATRIX_FILE"
  csv_row "$STATE_MATRIX_FILE" \
    page_id state required precondition expected result evidence notes

  : >"$ROLE_MATRIX_FILE"
  csv_row "$ROLE_MATRIX_FILE" \
    page_id role allowed_actions denied_actions expected result evidence notes

  : >"$TEST_CASES_FILE"
  csv_row "$TEST_CASES_FILE" \
    test_case_id page_id module avd api_level viewport font_scale role state \
    precondition steps expected actual result severity defect_id screenshot \
    video log notes

  : >"$DEFECTS_FILE"
  csv_row "$DEFECTS_FILE" \
    defect_id severity status page_id flow_id title role state precondition steps \
    expected actual repro_rate avd api_level screenshot video log fix_commit \
    regression_test result notes

  : >"$P1_REGRESSION_FILE"
  csv_row "$P1_REGRESSION_FILE" \
    existing_p1_id page_flow title avd result evidence notes
}

initialize_csv_files

record_defect() {
  local severity="$1"
  local module="$2"
  local summary="$3"
  local reproduction="$4"
  local evidence="$5"
  local page_id="${6:-}"
  local flow_id="${7:-}"
  ((DEFECT_COUNTER += 1))
  printf -v LAST_DEFECT_ID 'M24-EMU-%03d' "$DEFECT_COUNTER"
  csv_row "$DEFECTS_FILE" \
    "$LAST_DEFECT_ID" "$severity" "OPEN" "$page_id" "$flow_id" "$summary" \
    "scenario-defined" "normal" "BACKEND_MODE=mock; emulator offline" \
    "$reproduction" "Acceptance requirement passes" "$summary" \
    "Observed in this deterministic CI run" "$AVD_ID" "$API_LEVEL" \
    "" "" "$evidence" "" "Re-run the same test after a fix" "FAIL" "$module"
  ((FAIL_COUNT += 1))
}

record_case() {
  local test_case_id="$1"
  local page_id="$2"
  local module="$3"
  local expected="$4"
  local actual="$5"
  local result="$6"
  local severity="$7"
  local defect_id="$8"
  local screenshot="$9"
  local video="${10}"
  local log_file="${11}"
  local notes="${12}"
  local precondition="BACKEND_MODE=mock; device offline"
  case "$module" in
    baseline)
      precondition="SHA-verified immutable reference APK; device offline"
      ;;
    environment | viewport | apk-compatibility)
      precondition="Hardware-accelerated emulator; immutable tested commit"
      ;;
  esac
  csv_row "$TEST_CASES_FILE" \
    "$test_case_id" "$page_id" "$module" "$AVD_ID" "$API_LEVEL" \
    "actual-emulator" "system" "scenario-defined" "normal" "$precondition" \
    "automated interaction and assertion" "$expected" "$actual" "$result" \
    "$severity" "$defect_id" "$screenshot" "$video" "$log_file" "$notes"
}

safe_label() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_'
}

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    record_defect \
      "P0" "environment" "Required command is unavailable: $command_name" \
      "Start the $AVD_ID CI job." "$ENVIRONMENT_FILE"
    printf 'Required command is unavailable: %s\n' "$command_name" >&2
    exit 69
  fi
}

configure_android_tool_path() {
  local sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  local tool_dir
  if [[ -z "$sdk_root" ]]; then
    return
  fi
  for tool_dir in \
    "$sdk_root/emulator" \
    "$sdk_root/platform-tools" \
    "$sdk_root/cmdline-tools/latest/bin"; do
    if [[ -d "$tool_dir" ]]; then
      PATH="$tool_dir:$PATH"
    fi
  done
  export PATH
}

adb_device() {
  adb -s "$DEVICE_ID" "$@"
}

adb_device_bounded() {
  local duration="$1"
  shift
  timeout --signal=TERM --kill-after=5s "$duration" \
    adb -s "$DEVICE_ID" "$@"
}

progress_event() {
  local event="$1"
  local detail="${2:-}"
  printf '%s event=%s avd=%s detail=%s\n' \
    "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$event" "$AVD_ID" "$detail" | \
    tee -a "$RUNNER_PROGRESS_FILE"
}

stop_host_process_bounded() {
  local pid="$1"
  local initial_signal="${2:-TERM}"
  local attempt
  [[ -n "$pid" ]] || return 0
  if ! kill -0 "$pid" 2>/dev/null; then
    wait "$pid" 2>/dev/null || true
    return 0
  fi
  kill -s "$initial_signal" "$pid" 2>/dev/null || true
  for attempt in {1..20}; do
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid" 2>/dev/null || true
      return 0
    fi
    if [[ "$(ps -o stat= -p "$pid" 2>/dev/null)" == Z* ]]; then
      wait "$pid" 2>/dev/null || true
      return 0
    fi
    sleep 0.25
  done
  kill -KILL "$pid" 2>/dev/null || true
  for attempt in {1..20}; do
    if ! kill -0 "$pid" 2>/dev/null || \
        [[ "$(ps -o stat= -p "$pid" 2>/dev/null)" == Z* ]]; then
      wait "$pid" 2>/dev/null || true
      return 0
    fi
    sleep 0.25
  done
  # A kernel-uninterruptible process must not prevent the EXIT trap and the
  # following always() artifact step from running.
  printf '%s unreaped_host_pid=%s signal=%s\n' \
    "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$pid" "$initial_signal" \
    >>"$RUNNER_PROGRESS_FILE"
  return 0
}

run_logged() {
  local log_file="$1"
  shift
  local status
  set +e
  "$@" > >(tee "$log_file") 2>&1
  status=$?
  set -e
  return "$status"
}

discover_android_tools() {
  if command -v apkanalyzer >/dev/null 2>&1; then
    APK_ANALYZER="$(command -v apkanalyzer)"
  elif [[ -n "${ANDROID_SDK_ROOT:-}" && \
          -x "${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/apkanalyzer" ]]; then
    APK_ANALYZER="${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/apkanalyzer"
  elif [[ -n "${ANDROID_HOME:-}" && \
          -x "${ANDROID_HOME}/cmdline-tools/latest/bin/apkanalyzer" ]]; then
    APK_ANALYZER="${ANDROID_HOME}/cmdline-tools/latest/bin/apkanalyzer"
  fi

  if command -v aapt >/dev/null 2>&1; then
    AAPT_TOOL="$(command -v aapt)"
  else
    local sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
    if [[ -n "$sdk_root" && -d "$sdk_root/build-tools" ]]; then
      AAPT_TOOL="$(find "$sdk_root/build-tools" -type f -name aapt -perm -u+x \
        -print | sort -V | tail -n 1)"
    fi
  fi

  if [[ -z "$APK_ANALYZER" && -z "$AAPT_TOOL" ]]; then
    record_defect \
      "P0" "environment" "Neither apkanalyzer nor aapt is available" \
      "Start the Android SDK runner." "$ENVIRONMENT_FILE"
    exit 69
  fi
}

apk_badging() {
  local apk_path="$1"
  if [[ -n "$AAPT_TOOL" ]]; then
    "$AAPT_TOOL" dump badging "$apk_path"
  else
    return 1
  fi
}

apk_manifest_value() {
  local key="$1"
  local apk_path="$2"
  local value=""
  if [[ -n "$APK_ANALYZER" ]]; then
    value="$("$APK_ANALYZER" manifest "$key" "$apk_path" 2>/dev/null || true)"
  fi
  if [[ -z "$value" && -n "$AAPT_TOOL" ]]; then
    case "$key" in
      application-id)
        value="$(apk_badging "$apk_path" | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -n 1)"
        ;;
      min-sdk)
        value="$(apk_badging "$apk_path" | sed -n "s/^sdkVersion:'\([^']*\)'.*/\1/p" | head -n 1)"
        ;;
      target-sdk)
        value="$(apk_badging "$apk_path" | sed -n "s/^targetSdkVersion:'\([^']*\)'.*/\1/p" | head -n 1)"
        ;;
      version-code)
        value="$(apk_badging "$apk_path" | sed -n "s/^package:.*versionCode='\([^']*\)'.*/\1/p" | head -n 1)"
        ;;
      version-name)
        value="$(apk_badging "$apk_path" | sed -n "s/^package:.*versionName='\([^']*\)'.*/\1/p" | head -n 1)"
        ;;
    esac
  fi
  printf '%s' "$value" | tr -d '\r\n'
}

apk_launchable_activity() {
  local apk_path="$1"
  local activity=""
  if [[ -n "$AAPT_TOOL" ]]; then
    activity="$(apk_badging "$apk_path" | \
      sed -n "s/^launchable-activity: name='\([^']*\)'.*/\1/p" | head -n 1)"
  fi
  printf '%s' "$activity" | tr -d '\r\n'
}

apk_abis() {
  local apk_path="$1"
  unzip -Z1 "$apk_path" 2>/dev/null | \
    awk -F/ '/^lib\/[A-Za-z0-9_-]+\/.*\.so$/ {print $2}' | \
    sort -u | paste -sd ';' -
}

write_apk_metadata() {
  local label="$1"
  local apk_path="$2"
  local output_file="$3"
  {
    printf 'label=%s\n' "$label"
    printf 'path=%s\n' "$apk_path"
    printf 'sha256=%s\n' "$(sha256sum "$apk_path" | awk '{print $1}')"
    printf 'application_id=%s\n' "$(apk_manifest_value application-id "$apk_path")"
    printf 'min_sdk=%s\n' "$(apk_manifest_value min-sdk "$apk_path")"
    printf 'target_sdk=%s\n' "$(apk_manifest_value target-sdk "$apk_path")"
    printf 'version_code=%s\n' "$(apk_manifest_value version-code "$apk_path")"
    printf 'version_name=%s\n' "$(apk_manifest_value version-name "$apk_path")"
    printf 'abis=%s\n' "$(apk_abis "$apk_path")"
    printf 'launchable_activity=%s\n' "$(apk_launchable_activity "$apk_path")"
  } >>"$output_file"
}

validate_apk_sdk_compatibility() {
  local label="$1"
  local apk_path="$2"
  local min_sdk target_sdk
  min_sdk="$(apk_manifest_value min-sdk "$apk_path")"
  target_sdk="$(apk_manifest_value target-sdk "$apk_path")"
  if [[ ! "$min_sdk" =~ ^[0-9]+$ || ! "$target_sdk" =~ ^[0-9]+$ ]]; then
    record_defect \
      "P0" "apk-metadata" "Could not parse numeric minSdk/targetSdk for $label" \
      "Inspect the APK with apkanalyzer or aapt before selecting an AVD." \
      "$BUILD_INFO_FILE"
    exit 65
  fi
  if (( API_LEVEL < min_sdk )); then
    record_defect \
      "P0" "apk-compatibility" \
      "$label requires minSdk $min_sdk but $AVD_ID is API $API_LEVEL" \
      "Select an AVD at or above the APK minSdk." "$BUILD_INFO_FILE"
    exit 65
  fi
  if [[ "$AVD_ID" == "AVD-A" ]] && (( API_LEVEL < target_sdk )); then
    record_defect \
      "P0" "apk-compatibility" \
      "$label targets API $target_sdk but AVD-A is only API $API_LEVEL" \
      "Use a stable Google APIs image at or above targetSdk." "$BUILD_INFO_FILE"
    exit 65
  fi
  record_case \
    "M24-SDK-${label}" "" "apk-compatibility" \
    "AVD API satisfies minSdk and AVD-A also satisfies targetSdk" \
    "api=$API_LEVEL minSdk=$min_sdk targetSdk=$target_sdk" \
    "PASS" "" "" "" "" "$BUILD_INFO_FILE" \
    "AVD selection is validated from the actual APK manifest, not guessed."
}

verify_tested_source() {
  local actual_sha
  local worktree_status
  actual_sha="$(git rev-parse HEAD 2>/dev/null || true)"
  worktree_status="$(git status --porcelain=v1 --untracked-files=normal 2>/dev/null || true)"
  if [[ -z "$actual_sha" || "$actual_sha" != "$GIT_SHA_VALUE" ]]; then
    record_defect \
      "P0" "provenance" "The tested checkout does not match QA_GIT_SHA" \
      "Compare git rev-parse HEAD with the workflow-provided commit." \
      "$BUILD_INFO_FILE"
    printf 'expected_git_sha=%s\nactual_git_sha=%s\n' \
      "$GIT_SHA_VALUE" "$actual_sha" >>"$BUILD_INFO_FILE"
    exit 64
  fi
  if [[ -n "$worktree_status" ]]; then
    record_defect \
      "P0" "provenance" "The tested Git worktree is not clean" \
      "Commit the exact source under test; generated .ci_app and evidence paths must remain ignored." \
      "$BUILD_INFO_FILE"
    printf 'git_status_begin\n%s\ngit_status_end\n' \
      "$worktree_status" >>"$BUILD_INFO_FILE"
    exit 64
  fi
}

write_build_provenance() {
  {
    printf 'tested_git_sha=%s\n' "$GIT_SHA_VALUE"
    printf 'git_status_clean=true\n'
    printf 'package_version=%s\n' "$PACKAGE_VERSION_VALUE"
    printf 'backend_mode=%s\n' "$BACKEND_MODE_VALUE"
    printf 'qa_console_apk=true\n'
    printf 'qa_console_integration_tests=false\n'
    printf 'network_scenario=offline\n'
    printf 'quality_job_result=%s\n' "$QUALITY_RESULT"
    printf 'avd=%s\n' "$AVD_ID"
    printf 'api_level=%s\n' "$API_LEVEL"
    printf 'scope=%s\n' "$QA_SCOPE_VALUE"
  } >"$BUILD_INFO_FILE"
}

write_environment() {
  {
    printf 'timestamp_utc=%s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    printf 'repository=%s\n' "${GITHUB_REPOSITORY:-unknown}"
    printf 'git_sha=%s\n' "$GIT_SHA_VALUE"
    printf 'git_branch=%s\n' "${GITHUB_REF_NAME:-unknown}"
    printf 'run_id=%s\n' "$RUN_ID_VALUE"
    printf 'run_attempt=%s\n' "$RUN_ATTEMPT_VALUE"
    printf 'avd_id=%s\n' "$AVD_ID"
    printf 'api_level_requested=%s\n' "$API_LEVEL"
    printf 'profile=%s\n' "$AVD_PROFILE"
    printf 'scope=%s\n' "$QA_SCOPE_VALUE"
    printf 'backend_mode=%s\n' "$BACKEND_MODE_VALUE"
    printf 'baseline_run_id=%s\n' "$BASELINE_RUN_ID"
    printf 'baseline_artifact=%s\n' "$BASELINE_ARTIFACT_NAME"
    printf 'quality_job_result=%s\n' "$QUALITY_RESULT"
    printf 'runner_os=%s\n' "${RUNNER_OS:-unknown}"
    printf 'runner_arch=%s\n' "${RUNNER_ARCH:-unknown}"
    printf 'runner_image_os=%s\n' "${ImageOS:-unknown}"
    printf 'runner_image_version=%s\n' "${ImageVersion:-unknown}"
    printf 'git_status_begin\n'; git status --short --branch 2>&1 || true
    printf 'git_status_end\n'
    printf 'git_commit_begin\n'; git show -s --format=fuller HEAD 2>&1 || true
    printf 'git_commit_end\n'
    printf 'git_recent_begin\n'; git log -5 --oneline --decorate 2>&1 || true
    printf 'git_recent_end\n'
    printf 'kernel='; uname -a
    printf 'machine='; uname -m
    printf 'cpu_count=%s\n' "$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
    printf 'memory_begin\n'; free -h 2>&1 || true
    printf 'memory_end\n'
    printf 'disk_begin\n'; df -h 2>&1 || true
    printf 'disk_end\n'
    printf 'kvm='; ls -l /dev/kvm 2>/dev/null || printf 'ABSENT\n'
    printf 'java_version='; java -version 2>&1 | head -n 1 || true
    printf 'dart_version='; dart --version 2>&1 || true
    printf 'flutter_version_begin\n'; flutter --version 2>&1 || true
    printf 'flutter_version_end\n'
    printf 'flutter_doctor_begin\n'; flutter doctor -v 2>&1 || true
    printf 'flutter_doctor_end\n'
    printf 'adb_version_begin\n'; adb version 2>&1 || true
    printf 'adb_version_end\n'
    printf 'emulator_version_begin\n'; emulator -version 2>&1 || true
    printf 'emulator_version_end\n'
    printf 'gradle_version_begin\n'; ./android/gradlew --version 2>&1 || true
    printf 'gradle_version_end\n'
    printf 'sdkmanager_path=%s\n' "$(command -v sdkmanager 2>/dev/null || true)"
    printf 'avdmanager_path=%s\n' "$(command -v avdmanager 2>/dev/null || true)"
    printf 'sdkmanager_installed_begin\n'
    if command -v sdkmanager >/dev/null 2>&1; then
      sdkmanager --list_installed 2>&1 || sdkmanager --list 2>&1 || true
    fi
    printf 'sdkmanager_installed_end\n'
    printf 'emulator_avds_begin\n'; emulator -list-avds 2>&1 || true
    printf 'emulator_avds_end\n'
    printf 'avdmanager_list_begin\n'
    if command -v avdmanager >/dev/null 2>&1; then
      avdmanager list avd 2>&1 || true
    fi
    printf 'avdmanager_list_end\n'
    printf 'android_home=%s\n' "${ANDROID_HOME:-}"
    printf 'android_sdk_root=%s\n' "${ANDROID_SDK_ROOT:-}"
  } >"$ENVIRONMENT_FILE"
}

select_device() {
  local -a devices=()
  mapfile -t devices < <(adb devices | awk '$2 == "device" && $1 ~ /^emulator-/ {print $1}')
  if (( ${#devices[@]} != 1 )); then
    record_defect \
      "P0" "environment" "Expected exactly one ready emulator, found ${#devices[@]}" \
      "Run adb devices after emulator startup." "$ENVIRONMENT_FILE"
    adb devices -l >>"$ENVIRONMENT_FILE" 2>&1 || true
    exit 70
  fi
  DEVICE_ID="${devices[0]}"
  printf 'device_id=%s\n' "$DEVICE_ID" >>"$ENVIRONMENT_FILE"
}

configure_exact_viewport() {
  case "$AVD_ID" in
    AVD-A)
      if [[ "$API_LEVEL" != "36" || "$AVD_PROFILE" != "pixel_7_pro" || \
            "$QA_SCOPE_VALUE" != "full" ]]; then
        record_defect \
          "P0" "viewport" "AVD-A must be API 36, pixel_7_pro, full scope" \
          "Use the approved AVD-A workflow inputs." "$ENVIRONMENT_FILE"
        exit 64
      fi
      EXPECTED_PHYSICAL_SIZE="1170x2532"
      EXPECTED_DENSITY="480"
      EXPECTED_VIEWPORT="390x844"
      EXPECTED_DPR="3.00"
      ;;
    AVD-B)
      if [[ "$API_LEVEL" != "35" || "$AVD_PROFILE" != "pixel_2" || \
            "$QA_SCOPE_VALUE" != "full" ]]; then
        record_defect \
          "P0" "viewport" "AVD-B must be API 35, pixel_2, full scope" \
          "Use the approved AVD-B workflow inputs." "$ENVIRONMENT_FILE"
        exit 64
      fi
      EXPECTED_PHYSICAL_SIZE="864x1920"
      EXPECTED_DENSITY="384"
      EXPECTED_VIEWPORT="360x800"
      EXPECTED_DPR="2.40"
      ;;
    *)
      record_defect \
        "P0" "viewport" "No exact viewport mapping exists for $AVD_ID" \
        "Use AVD-A or AVD-B from the approved matrix." "$ENVIRONMENT_FILE"
      exit 64
      ;;
  esac

  local viewport_log="$LOG_DIR/exact-viewport.log"
  {
    printf 'expected_physical_size=%s\n' "$EXPECTED_PHYSICAL_SIZE"
    printf 'expected_density=%s\n' "$EXPECTED_DENSITY"
    printf 'expected_logical_viewport=%s\n' "$EXPECTED_VIEWPORT"
    printf 'expected_dpr=%s\n' "$EXPECTED_DPR"
    adb_device shell settings put system accelerometer_rotation 0
    adb_device shell settings put system user_rotation 0
    adb_device shell wm size "$EXPECTED_PHYSICAL_SIZE"
    adb_device shell wm density "$EXPECTED_DENSITY"
    sleep 2
    printf 'wm_size='; adb_device shell wm size
    printf 'wm_density='; adb_device shell wm density
    printf 'rotation='; adb_device shell settings get system user_rotation
  } >"$viewport_log" 2>&1

  local size_output density_output rotation_output
  size_output="$(adb_device shell wm size | tr -d '\r')"
  density_output="$(adb_device shell wm density | tr -d '\r')"
  rotation_output="$(adb_device shell settings get system user_rotation | tr -d '\r')"
  if [[ "$size_output" != *"$EXPECTED_PHYSICAL_SIZE"* || \
        "$density_output" != *"$EXPECTED_DENSITY"* || \
        "$rotation_output" != "0" ]]; then
    record_defect \
      "P1" "viewport" "Android rejected the exact portrait viewport override" \
      "Apply wm size $EXPECTED_PHYSICAL_SIZE, wm density $EXPECTED_DENSITY, and user_rotation 0." \
      "$viewport_log"
    record_case \
      "M24-EXACT-VIEWPORT" "" "viewport" \
      "$EXPECTED_VIEWPORT from $EXPECTED_PHYSICAL_SIZE at density $EXPECTED_DENSITY" \
      "size=$size_output density=$density_output rotation=$rotation_output" \
      "FAIL" "P1" "$LAST_DEFECT_ID" "" "" "$viewport_log" \
      "The run stops rather than downgrading to an approximate viewport."
    exit 68
  fi
  record_case \
    "M24-EXACT-VIEWPORT" "" "viewport" \
    "$EXPECTED_VIEWPORT from $EXPECTED_PHYSICAL_SIZE at density $EXPECTED_DENSITY" \
    "size=$size_output density=$density_output rotation=$rotation_output" \
    "PASS" "" "" "" "" "$viewport_log" \
    "Page screenshot filenames provide the later Flutter MediaQuery verification."
}

write_avd_matrix() {
  local android_version abi model physical_size density font_scale locale timezone free_storage
  local matrix_result="PENDING"
  android_version="$(adb_device shell getprop ro.build.version.release | tr -d '\r')"
  abi="$(adb_device shell getprop ro.product.cpu.abi | tr -d '\r')"
  model="$(adb_device shell getprop ro.product.model | tr -d '\r')"
  physical_size="$(adb_device shell wm size | tr '\n\r' ' ' | sed 's/[[:space:]]\+/ /g')"
  density="$(adb_device shell wm density | tr '\n\r' ' ' | sed 's/[[:space:]]\+/ /g')"
  font_scale="$(adb_device shell settings get system font_scale | tr -d '\r')"
  locale="$(adb_device shell getprop persist.sys.locale | tr -d '\r')"
  [[ -n "$locale" ]] || locale="$(adb_device shell getprop ro.product.locale | tr -d '\r')"
  timezone="$(adb_device shell getprop persist.sys.timezone | tr -d '\r')"
  free_storage="$(adb_device shell df -h /data | tail -n 1 | tr '\n\r' ' ')"
  if [[ "$ACTUAL_MEDIA_QUERY" == "$EXPECTED_VIEWPORT" && \
        "$ACTUAL_DPR" == "$EXPECTED_DPR" ]]; then
    matrix_result="PASS"
  elif [[ "$ACTUAL_MEDIA_QUERY" != "NOT_CAPTURED" ]]; then
    matrix_result="FAIL"
  fi
  : >"$AVD_MATRIX_FILE"
  csv_row "$AVD_MATRIX_FILE" \
    avd api_level android_version abi device_model physical_resolution density \
    media_query_size device_pixel_ratio font_scale locale timezone free_storage \
    result notes
  csv_row "$AVD_MATRIX_FILE" \
    "$AVD_ID" "$API_LEVEL" "$android_version" "$abi" "$model" \
    "$physical_size" "$density" "$ACTUAL_MEDIA_QUERY" \
    "$ACTUAL_DPR" "$ACTUAL_FONT_SCALE" "$locale" "$timezone" \
    "$free_storage" "$matrix_result" \
    "profile=$AVD_PROFILE; expected logical viewport=$EXPECTED_VIEWPORT; exact wm override verified"

  {
    printf 'device_properties_begin\n'
    adb_device shell getprop
    printf 'device_properties_end\n'
    printf 'wm_size='; adb_device shell wm size
    printf 'wm_density='; adb_device shell wm density
    printf 'expected_logical_viewport=%s\n' "$EXPECTED_VIEWPORT"
    printf 'font_scale='; adb_device shell settings get system font_scale
    printf 'storage_begin\n'; adb_device shell df -h /data
    printf 'storage_end\n'
  } >>"$ENVIRONMENT_FILE" 2>&1
}

start_logcat() {
  adb_device logcat -c || true
  adb_device logcat -v threadtime >"$LOGCAT_FILE" 2>&1 &
  LOGCAT_PID=$!
  printf 'logcat_pid=%s\n' "$LOGCAT_PID" >>"$ENVIRONMENT_FILE"
}

stop_logcat() {
  if [[ -n "$LOGCAT_PID" ]] && kill -0 "$LOGCAT_PID" 2>/dev/null; then
    stop_host_process_bounded "$LOGCAT_PID" TERM
  fi
  LOGCAT_PID=""
}

capture_snapshot() {
  local label
  local snapshot_log
  label="$(safe_label "$1")"
  [[ -n "$DEVICE_ID" ]] || return 0
  snapshot_log="$LOG_DIR/${label}-snapshot.log"
  : >"$snapshot_log"

  adb_device_bounded 20s exec-out screencap -p \
    >"$SCREENSHOT_DIR/${label}.png" 2>>"$snapshot_log" || \
    printf 'screencap=TIMEOUT_OR_FAILURE\n' >>"$snapshot_log"
  adb_device_bounded 20s shell dumpsys activity activities \
    >"$DUMP_DIR/${label}-activity.txt" 2>>"$snapshot_log" || \
    printf 'activity_dump=TIMEOUT_OR_FAILURE\n' >>"$snapshot_log"
  adb_device_bounded 20s shell dumpsys window displays \
    >"$DUMP_DIR/${label}-window.txt" 2>>"$snapshot_log" || \
    printf 'window_dump=TIMEOUT_OR_FAILURE\n' >>"$snapshot_log"
  adb_device_bounded 20s shell dumpsys connectivity \
    >"$DUMP_DIR/${label}-connectivity.txt" 2>>"$snapshot_log" || \
    printf 'connectivity_dump=TIMEOUT_OR_FAILURE\n' >>"$snapshot_log"
  adb_device_bounded 20s shell dumpsys meminfo \
    "${QA_PACKAGE:-${BASELINE_PACKAGE:-}}" \
    >"$DUMP_DIR/${label}-meminfo.txt" 2>>"$snapshot_log" || \
    printf 'meminfo_dump=TIMEOUT_OR_FAILURE\n' >>"$snapshot_log"
  adb_device_bounded 20s shell uiautomator dump "/sdcard/${label}.xml" \
    >"$LOG_DIR/${label}-uiautomator.log" 2>>"$snapshot_log" || \
    printf 'uiautomator_dump=TIMEOUT_OR_FAILURE\n' >>"$snapshot_log"
  adb_device_bounded 20s pull "/sdcard/${label}.xml" \
    "$DUMP_DIR/${label}-ui.xml" \
    >>"$LOG_DIR/${label}-uiautomator.log" 2>>"$snapshot_log" || \
    printf 'uiautomator_pull=TIMEOUT_OR_FAILURE\n' >>"$snapshot_log"
  adb_device_bounded 10s shell rm -f "/sdcard/${label}.xml" \
    >/dev/null 2>>"$snapshot_log" || true
}

start_screen_recording() {
  local label
  label="$(safe_label "$1")"
  stop_screen_recording
  SCREENRECORD_REMOTE="${REMOTE_VIDEO_PREFIX}-${label}.mp4"
  SCREENRECORD_LOCAL="$VIDEO_DIR/${label}.mp4"
  adb_device shell rm -f "$SCREENRECORD_REMOTE" >/dev/null 2>&1 || true
  adb_device shell screenrecord \
    --bit-rate 4000000 \
    --time-limit 180 \
    "$SCREENRECORD_REMOTE" \
    >"$LOG_DIR/${label}-screenrecord.log" 2>&1 &
  SCREENRECORD_PID=$!
}

stop_screen_recording() {
  if [[ -z "$SCREENRECORD_REMOTE" ]]; then
    return 0
  fi

  if [[ -n "$DEVICE_ID" ]]; then
    adb_device_bounded 10s shell pkill -2 screenrecord >/dev/null 2>&1 || \
      adb_device_bounded 10s shell killall -2 screenrecord \
        >/dev/null 2>&1 || true
  fi
  if [[ -n "$SCREENRECORD_PID" ]] && kill -0 "$SCREENRECORD_PID" 2>/dev/null; then
    kill -INT "$SCREENRECORD_PID" 2>/dev/null || true
  fi
  if [[ -n "$SCREENRECORD_PID" ]]; then
    stop_host_process_bounded "$SCREENRECORD_PID" INT
  fi
  if [[ -n "$DEVICE_ID" ]]; then
    adb_device_bounded 30s pull "$SCREENRECORD_REMOTE" "$SCREENRECORD_LOCAL" \
      >"$LOG_DIR/$(basename "$SCREENRECORD_LOCAL").pull.log" 2>&1 || true
    adb_device_bounded 10s shell rm -f "$SCREENRECORD_REMOTE" \
      >/dev/null 2>&1 || true
  fi
  SCREENRECORD_PID=""
  SCREENRECORD_REMOTE=""
  SCREENRECORD_LOCAL=""
}

enable_offline_mode() {
  local airplane_mode
  local ping_status
  local ping_output
  local connectivity_log="$LOG_DIR/offline-connectivity.log"
  : >"$connectivity_log"

  if ! adb_device shell cmd connectivity airplane-mode enable \
      >>"$connectivity_log" 2>&1; then
    adb_device shell settings put global airplane_mode_on 1 \
      >>"$connectivity_log" 2>&1 || true
    adb_device shell am broadcast \
      -a android.intent.action.AIRPLANE_MODE \
      --ez state true >>"$connectivity_log" 2>&1 || true
  fi
  adb_device shell svc wifi disable >>"$connectivity_log" 2>&1 || true
  adb_device shell svc data disable >>"$connectivity_log" 2>&1 || true
  sleep 2

  airplane_mode="$(adb_device shell settings get global airplane_mode_on | tr -d '\r')"
  set +e
  ping_output="$(adb_device shell 'ping -c 1 -W 2 8.8.8.8' 2>&1)"
  ping_status=$?
  set -e
  printf 'ping_exit=%s\nping_output_begin\n%s\nping_output_end\n' \
    "$ping_status" "$ping_output" >>"$connectivity_log"
  adb_device shell dumpsys connectivity >>"$connectivity_log" 2>&1 || true

  if [[ "$airplane_mode" == "1" && "$ping_status" -ne 0 && \
        "$ping_output" != *"not found"* && \
        "$ping_output" != *"inaccessible"* ]]; then
    OFFLINE_STATUS="PASS"
    record_case \
      "M24-OFFLINE-GATE" "" "offline" \
      "Airplane mode enabled and public network unreachable" \
      "airplane_mode=$airplane_mode ping_exit=$ping_status" \
      "PASS" "" "" "" "" "$connectivity_log" \
      "ADB remains available while device networking is disabled."
  else
    OFFLINE_STATUS="FAIL"
    record_defect \
      "P1" "offline" "Could not prove that the emulator is offline" \
      "Enable airplane mode, disable Wi-Fi/data, and ping 8.8.8.8." \
      "$connectivity_log"
    record_case \
      "M24-OFFLINE-GATE" "" "offline" \
      "Airplane mode enabled and public network unreachable" \
      "airplane_mode=$airplane_mode ping_exit=$ping_status" \
      "FAIL" "P1" "$LAST_DEFECT_ID" "" "" "$connectivity_log" \
      "The run continues for evidence, but cannot claim offline PASS."
  fi
}

restore_network_mode() {
  [[ -n "$DEVICE_ID" ]] || return 0
  adb_device_bounded 10s shell cmd connectivity airplane-mode disable \
    >/dev/null 2>&1 || {
    adb_device_bounded 10s shell settings put global airplane_mode_on 0 \
      >/dev/null 2>&1 || true
    adb_device_bounded 10s shell am broadcast \
      -a android.intent.action.AIRPLANE_MODE \
      --ez state false >/dev/null 2>&1 || true
  }
  adb_device_bounded 10s shell svc wifi enable >/dev/null 2>&1 || true
  adb_device_bounded 10s shell svc data enable >/dev/null 2>&1 || true
}

find_baseline_apk() {
  local -a candidates=()
  if [[ ! -d "$BASELINE_ARTIFACT_DIR" ]]; then
    record_defect \
      "P0" "baseline" "Baseline artifact directory is missing" \
      "Download run $BASELINE_RUN_ID artifact $BASELINE_ARTIFACT_NAME." \
      "$BASELINE_ARTIFACT_DIR"
    exit 66
  fi
  mapfile -d '' -t candidates < <(
    find "$BASELINE_ARTIFACT_DIR" -type f -iname '*.apk' -print0
  )
  if (( ${#candidates[@]} != 1 )); then
    record_defect \
      "P0" "baseline" "Expected exactly one APK in baseline artifact; found ${#candidates[@]}" \
      "Inspect run $BASELINE_RUN_ID artifact $BASELINE_ARTIFACT_NAME." \
      "$BASELINE_ARTIFACT_DIR"
    exit 66
  fi
  BASELINE_APK="${candidates[0]}"
}

install_apk_with_signature_recovery() {
  local apk_path="$1"
  local package_name="$2"
  local log_prefix="$3"
  local first_log="$LOG_DIR/${log_prefix}-install-first.log"
  local retry_log="$LOG_DIR/${log_prefix}-install-retry.log"

  if run_logged "$first_log" adb_device install -r "$apk_path"; then
    return 0
  fi
  if grep -Eq \
      'INSTALL_FAILED_UPDATE_INCOMPATIBLE|signatures do not match|signature' \
      "$first_log"; then
    adb_device uninstall "$package_name" >>"$retry_log" 2>&1 || true
    run_logged "$retry_log" adb_device install "$apk_path"
    return $?
  fi
  return 1
}

launch_apk() {
  local apk_path="$1"
  local package_name="$2"
  local log_file="$3"
  local activity
  activity="$(apk_launchable_activity "$apk_path")"
  adb_device shell am force-stop "$package_name" >>"$log_file" 2>&1 || true
  if [[ -n "$activity" ]]; then
    run_logged "$log_file" adb_device shell am start -W \
      -n "${package_name}/${activity}"
  else
    run_logged "$log_file" adb_device shell monkey \
      -p "$package_name" -c android.intent.category.LAUNCHER 1
  fi
}

run_baseline_black_box() {
  [[ "$BASELINE_REQUIRED" == "true" ]] || return 0
  find_baseline_apk

  local actual_sha baseline_log baseline_screenshot baseline_video baseline_ui_dump
  actual_sha="$(sha256sum "$BASELINE_APK" | awk '{print $1}')"
  printf 'baseline_expected=%s\n' "$EXPECTED_BASELINE_SHA256" >>"$APK_SHA_FILE"
  printf 'baseline_actual=%s\n' "$actual_sha" >>"$APK_SHA_FILE"

  if [[ -z "$EXPECTED_BASELINE_SHA256" || \
        "$actual_sha" != "$EXPECTED_BASELINE_SHA256" ]]; then
    record_defect \
      "P0" "baseline" "BLOCKED_APK_HASH_MISMATCH" \
      "Download run $BASELINE_RUN_ID artifact $BASELINE_ARTIFACT_NAME and hash its inner APK." \
      "$APK_SHA_FILE"
    record_case \
      "M24-BASELINE-HASH" "" "baseline" \
      "$EXPECTED_BASELINE_SHA256" "$actual_sha" "FAIL" "P0" \
      "$LAST_DEFECT_ID" "" "" "$APK_SHA_FILE" \
      "The wrong APK is never installed or substituted."
    exit 65
  fi

  write_apk_metadata "baseline" "$BASELINE_APK" "$BUILD_INFO_FILE"
  validate_apk_sdk_compatibility "baseline" "$BASELINE_APK"
  record_case \
    "M24-BASELINE-HASH" "" "baseline" \
    "$EXPECTED_BASELINE_SHA256" "$actual_sha" "PASS" "" "" \
    "" "" "$APK_SHA_FILE" "Inner APK matches the immutable expected SHA."

  BASELINE_PACKAGE="$(apk_manifest_value application-id "$BASELINE_APK")"
  if [[ -z "$BASELINE_PACKAGE" ]]; then
    record_defect \
      "P0" "baseline" "Could not read baseline applicationId" \
      "Run apkanalyzer manifest application-id on the verified APK." \
      "$BUILD_INFO_FILE"
    exit 65
  fi

  adb_device shell dumpsys package "$BASELINE_PACKAGE" \
    >"$DUMP_DIR/baseline-existing-package.txt" 2>&1 || true
  baseline_log="$LOG_DIR/baseline-black-box.log"
  baseline_screenshot="$SCREENSHOT_DIR/baseline-black-box-${AVD_ID}.png"
  baseline_video="$VIDEO_DIR/baseline-black-box-${AVD_ID}.mp4"
  baseline_ui_dump="$DUMP_DIR/baseline-black-box-${AVD_ID}-ui.xml"

  if ! install_apk_with_signature_recovery \
      "$BASELINE_APK" "$BASELINE_PACKAGE" "baseline"; then
    record_defect \
      "P0" "baseline" "Verified baseline APK could not be installed" \
      "adb install -r the SHA-verified baseline APK." \
      "$LOG_DIR/baseline-install-first.log"
    record_case \
      "M24-BASELINE-BLACKBOX" "" "baseline" \
      "Verified APK installs and launches" "Installation failed" "FAIL" \
      "P0" "$LAST_DEFECT_ID" "" "" \
      "$LOG_DIR/baseline-install-first.log" "QA source testing continues only if possible."
    return 0
  fi

  start_screen_recording "baseline-black-box-${AVD_ID}"
  if ! launch_apk "$BASELINE_APK" "$BASELINE_PACKAGE" "$baseline_log"; then
    stop_screen_recording
    capture_snapshot "baseline-launch-failure-${AVD_ID}"
    record_defect \
      "P0" "baseline" "Verified baseline APK did not launch" \
      "Force-stop and start the detected launcher activity." "$baseline_log"
    record_case \
      "M24-BASELINE-BLACKBOX" "" "baseline" \
      "Verified APK installs and launches" "Launch failed" "FAIL" "P0" \
      "$LAST_DEFECT_ID" "$baseline_screenshot" "$baseline_video" \
      "$baseline_log" "Package was detected from the APK, not guessed."
    return 0
  fi

  sleep 5
  capture_snapshot "baseline-black-box-${AVD_ID}"
  stop_screen_recording
  if ! adb_device shell pidof "$BASELINE_PACKAGE" >/dev/null 2>&1; then
    record_defect \
      "P0" "baseline" "Baseline process was not alive after launch" \
      "Install, start, and wait five seconds." "$baseline_log"
    record_case \
      "M24-BASELINE-BLACKBOX" "" "baseline" \
      "Process remains alive without immediate crash" "Process exited" \
      "FAIL" "P0" "$LAST_DEFECT_ID" "$baseline_screenshot" \
      "$baseline_video" "$baseline_log" "ANDROID_EMULATOR_FAIL"
  elif [[ ! -s "$baseline_screenshot" || ! -s "$baseline_ui_dump" ]] || \
      ! grep -Eq 'text="[^"]+"|content-desc="[^"]+"' "$baseline_ui_dump"; then
    record_defect \
      "P1" "baseline" \
      "Baseline stayed alive but produced no meaningful UIAutomator content" \
      "Inspect the retained screenshot for white screen or indefinite offline loading." \
      "$baseline_screenshot;$baseline_ui_dump;$baseline_log"
    record_case \
      "M24-BASELINE-BLACKBOX" "" "baseline" \
      "Visible non-blank content while offline" \
      "No meaningful text/content description was found" \
      "FAIL" "P1" "$LAST_DEFECT_ID" "$baseline_screenshot" \
      "$baseline_video" "$baseline_log" \
      "The process-alive check alone is not treated as a visual PASS."
  else
    record_case \
      "M24-BASELINE-BLACKBOX" "" "baseline" \
      "Verified APK installs, launches, and stays alive" \
      "Installed package $BASELINE_PACKAGE and process remained alive" \
      "PASS" "" "" "$baseline_screenshot" "$baseline_video" \
      "$baseline_log" "Visual screenshot and UIAutomator evidence retained."
  fi

  adb_device uninstall "$BASELINE_PACKAGE" \
    >"$LOG_DIR/baseline-uninstall.log" 2>&1 || true
}

qa_dart_defines() {
  local qa_console_enabled="${1:-false}"
  local critical_only="false"
  local framework_screenshots="false"
  if [[ "$QA_SCOPE_VALUE" == "critical" ]]; then
    critical_only="true"
  fi
  if (( API_LEVEL < 26 )); then
    framework_screenshots="true"
  fi
  printf '%s\n' \
    "--dart-define=BACKEND_MODE=mock" \
    "--dart-define=ENABLE_QA_CONSOLE=$qa_console_enabled" \
    "--dart-define=GIT_COMMIT=$GIT_SHA_VALUE" \
    "--dart-define=PACKAGE_VERSION=$PACKAGE_VERSION_VALUE" \
    "--dart-define=QA_AVD_ID=$AVD_ID" \
    "--dart-define=QA_CRITICAL_ONLY=$critical_only" \
    "--dart-define=QA_FRAMEWORK_SCREENSHOTS=$framework_screenshots" \
    "--dart-define=QA_NETWORK_SCENARIO=offline"
}

build_qa_apk() {
  local -a defines=()
  local -a mock_main_defines=()
  local build_log="$LOG_DIR/qa-apk-build.log"
  local mock_main_build_log="$LOG_DIR/session-restore-mock-apk-build.log"
  mapfile -t defines < <(qa_dart_defines true)

  if ! run_logged "$build_log" flutter build apk \
      --debug \
      --no-pub \
      "${defines[@]}"; then
    record_defect \
      "P0" "build" "Mock QA APK failed to build" \
      "Build debug APK with BACKEND_MODE=mock and ENABLE_QA_CONSOLE=true." \
      "$build_log"
    record_case \
      "M24-QA-BUILD" "" "build" "Mock QA APK builds" "Build failed" \
      "FAIL" "P0" "$LAST_DEFECT_ID" "" "" "$build_log" \
      "No live configuration is permitted."
    exit 67
  fi

  QA_APK="$PROJECT_ROOT/build/app/outputs/flutter-apk/app-debug.apk"
  if [[ ! -f "$QA_APK" ]]; then
    record_defect \
      "P0" "build" "Flutter reported success but app-debug.apk is missing" \
      "Inspect the Flutter build output directory." "$build_log"
    exit 67
  fi

  cp "$QA_APK" "$APK_DIR/voice-social-app-m2.4-qa-debug.apk"
  QA_APK="$APK_DIR/voice-social-app-m2.4-qa-debug.apk"
  printf 'qa=%s\n' "$(sha256sum "$QA_APK" | awk '{print $1}')" >>"$APK_SHA_FILE"
  write_apk_metadata "qa-debug" "$QA_APK" "$BUILD_INFO_FILE"
  validate_apk_sdk_compatibility "qa-debug" "$QA_APK"
  QA_PACKAGE="$(apk_manifest_value application-id "$QA_APK")"
  if [[ -z "$QA_PACKAGE" ]]; then
    record_defect \
      "P0" "build" "Could not read QA APK applicationId" \
      "Run apkanalyzer on the generated QA APK." "$BUILD_INFO_FILE"
    exit 67
  fi

  # Keep a same-signature, console-disabled main APK outside the evidence tree.
  # flutter drive replaces the installed application with an integration
  # target; FLOW-003 must relaunch the ordinary app without clearing the secure
  # storage established by FLOW-001. This temporary APK is deliberately not a
  # long-lived artifact.
  mapfile -t mock_main_defines < <(qa_dart_defines false)
  if run_logged "$mock_main_build_log" flutter build apk \
      --debug \
      --no-pub \
      "${mock_main_defines[@]}" && \
      [[ -f "$PROJECT_ROOT/build/app/outputs/flutter-apk/app-debug.apk" ]]; then
    local temp_parent="${RUNNER_TEMP:-/tmp}"
    [[ -d "$temp_parent" ]] || temp_parent="/tmp"
    MOCK_DEBUG_TEMP_DIR="$(
      mktemp -d "$temp_parent/m24-session-restore-${AVD_ID}.XXXXXX"
    )"
    MOCK_DEBUG_APK="$MOCK_DEBUG_TEMP_DIR/app-debug.apk"
    cp "$PROJECT_ROOT/build/app/outputs/flutter-apk/app-debug.apk" \
      "$MOCK_DEBUG_APK"
    MOCK_DEBUG_PACKAGE="$(apk_manifest_value application-id "$MOCK_DEBUG_APK")"
    MOCK_DEBUG_SHA256="$(sha256sum "$MOCK_DEBUG_APK" | awk '{print $1}')"
    printf 'session_restore_mock_debug=%s\n' "$MOCK_DEBUG_SHA256" \
      >>"$APK_SHA_FILE"
    {
      printf 'purpose=FLOW-003 ordinary mock main reinstall\n'
      printf 'qa_console_enabled=false\n'
      printf 'application_id=%s\n' "$MOCK_DEBUG_PACKAGE"
      printf 'launchable_activity=%s\n' \
        "$(apk_launchable_activity "$MOCK_DEBUG_APK")"
      printf 'sha256=%s\n' "$MOCK_DEBUG_SHA256"
      printf 'temporary_apk=%s\n' "$MOCK_DEBUG_APK"
      printf 'retained_artifact=false\n'
    } >>"$mock_main_build_log"
    if [[ -z "$MOCK_DEBUG_PACKAGE" || \
          "$MOCK_DEBUG_PACKAGE" != "$QA_PACKAGE" ]]; then
      printf 'package_validation=FAIL expected=%s actual=%s\n' \
        "$QA_PACKAGE" "${MOCK_DEBUG_PACKAGE:-missing}" \
        >>"$mock_main_build_log"
      MOCK_DEBUG_PACKAGE=""
    else
      printf 'package_validation=PASS\n' >>"$mock_main_build_log"
    fi
  else
    printf 'temporary_mock_main=BUILD_FAILED_OR_MISSING\n' \
      >>"$mock_main_build_log"
  fi

  record_case \
    "M24-QA-BUILD" "" "build" \
    "Debug APK uses mock mode and exposes the debug-only QA console" \
    "Built $QA_APK for $QA_PACKAGE" "PASS" "" "" "" "" \
    "$build_log" "Dart defines are recorded in the workflow and build log."
}

verify_qa_console_metrics() {
  local ui_dump="$1"
  local media_text dpr_text font_text metrics_log
  metrics_log="$LOG_DIR/qa-console-metrics.log"
  media_text="$(grep -m1 -oE 'MediaQuery: [0-9]+(×|x)[0-9]+' \
    "$ui_dump" 2>/dev/null || true)"
  dpr_text="$(grep -m1 -oE 'DPR: [0-9]+\.[0-9]+' \
    "$ui_dump" 2>/dev/null || true)"
  font_text="$(grep -m1 -oE 'Font: [0-9]+\.[0-9]+(×|x)' \
    "$ui_dump" 2>/dev/null || true)"
  ACTUAL_MEDIA_QUERY="$(printf '%s' "${media_text#MediaQuery: }" | sed 's/×/x/g')"
  ACTUAL_DPR="${dpr_text#DPR: }"
  ACTUAL_FONT_SCALE="$(printf '%s' "${font_text#Font: }" | sed 's/×/x/g')"
  [[ -n "$ACTUAL_MEDIA_QUERY" ]] || ACTUAL_MEDIA_QUERY="NOT_CAPTURED"
  [[ -n "$ACTUAL_DPR" ]] || ACTUAL_DPR="NOT_CAPTURED"
  [[ -n "$ACTUAL_FONT_SCALE" ]] || ACTUAL_FONT_SCALE="NOT_CAPTURED"
  {
    printf 'expected_media_query=%s\n' "$EXPECTED_VIEWPORT"
    printf 'actual_media_query=%s\n' "$ACTUAL_MEDIA_QUERY"
    printf 'expected_dpr=%s\n' "$EXPECTED_DPR"
    printf 'actual_dpr=%s\n' "$ACTUAL_DPR"
    printf 'actual_font_scale=%s\n' "$ACTUAL_FONT_SCALE"
    printf 'ui_dump=%s\n' "$ui_dump"
  } >"$metrics_log"
  write_avd_matrix

  if [[ "$ACTUAL_MEDIA_QUERY" == "$EXPECTED_VIEWPORT" && \
        "$ACTUAL_DPR" == "$EXPECTED_DPR" && \
        "$ACTUAL_FONT_SCALE" == "1.00x" ]]; then
    record_case \
      "M24-MEDIAQUERY" "" "viewport" \
      "MediaQuery=$EXPECTED_VIEWPORT DPR=$EXPECTED_DPR Font=1.00x" \
      "MediaQuery=$ACTUAL_MEDIA_QUERY DPR=$ACTUAL_DPR Font=$ACTUAL_FONT_SCALE" \
      "PASS" "" "" "$SCREENSHOT_DIR/qa-console-${AVD_ID}.png" "" \
      "$metrics_log" "Values come from Flutter MediaQuery, not wm size inference."
  else
    record_defect \
      "P1" "viewport" "Flutter MediaQuery/DPR did not match the approved exact viewport" \
      "Apply the AVD wm override, launch QA Console, and read its MediaQuery card." \
      "$metrics_log"
    record_case \
      "M24-MEDIAQUERY" "" "viewport" \
      "MediaQuery=$EXPECTED_VIEWPORT DPR=$EXPECTED_DPR Font=1.00x" \
      "MediaQuery=$ACTUAL_MEDIA_QUERY DPR=$ACTUAL_DPR Font=$ACTUAL_FONT_SCALE" \
      "FAIL" "P1" "$LAST_DEFECT_ID" \
      "$SCREENSHOT_DIR/qa-console-${AVD_ID}.png" "" "$metrics_log" \
      "The workflow does not infer logical viewport from wm size."
  fi
}

exercise_qa_console_system_input() {
  local initial_ui_dump="$1"
  local interaction_log="$LOG_DIR/qa-console-system-input.log"
  local input_node reset_node filtered_ui expanded_ui page_ui returned_ui
  local input_x input_y reset_x reset_y card_x card_y open_x open_y
  local physical_height scroll_bottom scroll_top
  local card_node open_node
  local bounds_re='bounds="\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\]"'
  local passed=1

  physical_height="${EXPECTED_PHYSICAL_SIZE#*x}"
  scroll_bottom=$(( physical_height * 85 / 100 ))
  scroll_top=$(( physical_height * 35 / 100 ))

  input_node="$(
    grep -oE \
      'class="android.widget.EditText"[^>]*bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' \
      "$initial_ui_dump" | head -n 1 || true
  )"
  reset_node="$(
    grep -oE \
      'content-desc="重置 Mock 数据"[^>]*bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' \
      "$initial_ui_dump" | head -n 1 || true
  )"
  if [[ ! "$input_node" =~ $bounds_re ]]; then
    printf 'search_bounds=NOT_FOUND\n' >"$interaction_log"
    passed=0
  else
    input_x=$(( (BASH_REMATCH[1] + BASH_REMATCH[3]) / 2 ))
    input_y=$(( (BASH_REMATCH[2] + BASH_REMATCH[4]) / 2 ))
  fi
  if [[ ! "$reset_node" =~ $bounds_re ]]; then
    printf 'reset_bounds=NOT_FOUND\n' >>"$interaction_log"
    passed=0
  else
    reset_x=$(( (BASH_REMATCH[1] + BASH_REMATCH[3]) / 2 ))
    reset_y=$(( (BASH_REMATCH[2] + BASH_REMATCH[4]) / 2 ))
  fi

  if (( passed == 1 )); then
    adb_device logcat -c >/dev/null 2>&1 || true
    start_screen_recording "qa-console-system-input-${AVD_ID}"
    adb_device shell input tap "$input_x" "$input_y" >>"$interaction_log" 2>&1 || passed=0
    sleep 2
    adb_device shell dumpsys input_method >>"$interaction_log" 2>&1 || true
    capture_snapshot "qa-console-system-keyboard-${AVD_ID}"
    if ! grep -Eq \
        'mInputShown=true|isInputViewShown=true|mInputViewShown=true' \
        "$interaction_log"; then
      printf 'system_keyboard=NOT_CONFIRMED\n' >>"$interaction_log"
      passed=0
    else
      printf 'system_keyboard=PASS\n' >>"$interaction_log"
    fi

    adb_device shell input text 'AC-004' >>"$interaction_log" 2>&1 || passed=0
    sleep 2
    adb_device shell input keyevent KEYCODE_BACK >>"$interaction_log" 2>&1 || passed=0
    sleep 1
    capture_snapshot "qa-console-system-filtered-${AVD_ID}"
    filtered_ui="$DUMP_DIR/qa-console-system-filtered-${AVD_ID}-ui.xml"
    if ! grep -q '1 / 69' "$filtered_ui"; then
      printf 'filtered_count=FAIL\n' >>"$interaction_log"
      passed=0
    else
      printf 'filtered_count=PASS\n' >>"$interaction_log"
    fi

    card_node="$(
      grep -oE \
        'content-desc="[^"]*AC-004[^"]*"[^>]*bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' \
        "$filtered_ui" | head -n 1 || true
    )"
    if [[ "$card_node" =~ $bounds_re ]]; then
      card_x=$(( (BASH_REMATCH[1] + BASH_REMATCH[3]) / 2 ))
      card_y=$(( (BASH_REMATCH[2] + BASH_REMATCH[4]) / 2 ))
      adb_device shell input tap "$card_x" "$card_y" >>"$interaction_log" 2>&1 || passed=0
      sleep 1
      capture_snapshot "qa-console-system-expanded-${AVD_ID}"
      expanded_ui="$DUMP_DIR/qa-console-system-expanded-${AVD_ID}-ui.xml"
      open_node="$(
        grep -oE \
          'content-desc="直接打开真实页面"[^>]*bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' \
          "$expanded_ui" | head -n 1 || true
      )"
      if [[ -z "$open_node" ]]; then
        adb_device shell input swipe \
          "$input_x" "$scroll_bottom" "$input_x" "$scroll_top" 500 \
          >>"$interaction_log" 2>&1 || passed=0
        sleep 1
        capture_snapshot "qa-console-system-expanded-${AVD_ID}"
        open_node="$(
          grep -oE \
            'content-desc="直接打开真实页面"[^>]*bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' \
            "$expanded_ui" | head -n 1 || true
        )"
      fi
      if [[ "$open_node" =~ $bounds_re ]]; then
        open_x=$(( (BASH_REMATCH[1] + BASH_REMATCH[3]) / 2 ))
        open_y=$(( (BASH_REMATCH[2] + BASH_REMATCH[4]) / 2 ))
        adb_device shell input tap "$open_x" "$open_y" >>"$interaction_log" 2>&1 || passed=0
        sleep 2
        capture_snapshot "qa-console-system-real-page-${AVD_ID}"
        page_ui="$DUMP_DIR/qa-console-system-real-page-${AVD_ID}-ui.xml"
        if ! grep -q 'QA 当前场景：AC-004' "$page_ui" || \
            ! grep -q '第三方账号绑定与分享授权' "$page_ui"; then
          printf 'real_page=FAIL\n' >>"$interaction_log"
          passed=0
        else
          printf 'real_page=PASS\n' >>"$interaction_log"
        fi

        adb_device shell input keyevent KEYCODE_BACK >>"$interaction_log" 2>&1 || passed=0
        sleep 2
        capture_snapshot "qa-console-system-back-${AVD_ID}"
        returned_ui="$DUMP_DIR/qa-console-system-back-${AVD_ID}-ui.xml"
        if ! grep -q 'M2.4 QA Console' "$returned_ui" || \
            ! grep -q '1 / 69' "$returned_ui"; then
          printf 'android_system_back=FAIL\n' >>"$interaction_log"
          passed=0
        else
          printf 'android_system_back=PASS\n' >>"$interaction_log"
        fi
      else
        printf 'open_real_page_bounds=NOT_FOUND\n' >>"$interaction_log"
        passed=0
      fi
    else
      printf 'AC-004_card_bounds=NOT_FOUND\n' >>"$interaction_log"
      passed=0
    fi

    adb_device shell input swipe \
      "$input_x" "$scroll_bottom" "$input_x" "$scroll_top" 500 \
      >>"$interaction_log" 2>&1 || passed=0
    sleep 1
    adb_device shell input swipe \
      "$input_x" "$scroll_top" "$input_x" "$scroll_bottom" 500 \
      >>"$interaction_log" 2>&1 || passed=0
    sleep 1
    adb_device shell input tap "$reset_x" "$reset_y" >>"$interaction_log" 2>&1 || passed=0
    sleep 2
    capture_snapshot "qa-console-system-reset-${AVD_ID}"
    adb_device logcat -d >>"$interaction_log" 2>&1 || true
    stop_screen_recording
    if grep -Eqi \
        'setState\(\).*during build|setState\(\) called after dispose|markNeedsBuild\(\).*during build|MissingPluginException|FATAL EXCEPTION|ANR in com\.kong373\.voice_social_app' \
        "$interaction_log"; then
      printf 'hard_finding=FAIL\n' >>"$interaction_log"
      passed=0
    else
      printf 'hard_finding=PASS\n' >>"$interaction_log"
    fi
  fi

  if (( passed == 1 )); then
    record_case \
      "M24-QA-SYSTEM-INPUT" "AC-004" "qa-smoke" \
      "Real Android keyboard, scrolling, system back, real-page route, and reset complete without a hard finding" \
      "AC-004 filtered to 1/69, opened, returned with KEYCODE_BACK, scrolled, and reset" \
      "PASS" "" "" \
      "$SCREENSHOT_DIR/qa-console-system-reset-${AVD_ID}.png" \
      "$VIDEO_DIR/qa-console-system-input-${AVD_ID}.mp4" \
      "$interaction_log" "All input events were sent by adb to the running Android package."
  else
    record_defect \
      "P1" "qa-smoke" "QA Console Android system input or reset evidence was incomplete" \
      "Use UIAutomator bounds to exercise the real keyboard, AC-004 route, Android back, scrolling, and reset." \
      "$interaction_log"
    record_case \
      "M24-QA-SYSTEM-INPUT" "AC-004" "qa-smoke" \
      "Real Android keyboard, scrolling, system back, real-page route, and reset complete without a hard finding" \
      "One or more host-driven assertions failed" "FAIL" "P1" "$LAST_DEFECT_ID" \
      "$SCREENSHOT_DIR/qa-console-system-reset-${AVD_ID}.png" \
      "$VIDEO_DIR/qa-console-system-input-${AVD_ID}.mp4" \
      "$interaction_log" "Infrastructure failure is retained and cannot be converted to a product PASS."
  fi
}

run_qa_launch_smoke() {
  local install_log="$LOG_DIR/qa-install.log"
  local launch_log="$LOG_DIR/qa-launch.log"
  local cold_log="$PERF_DIR/qa-cold-start.txt"
  local warm_log="$PERF_DIR/qa-warm-start.txt"
  local cold_ms warm_ms
  local activity
  activity="$(apk_launchable_activity "$QA_APK")"

  adb_device uninstall "$QA_PACKAGE" >>"$install_log" 2>&1 || true
  if ! run_logged "$install_log" adb_device install "$QA_APK"; then
    record_defect \
      "P0" "qa-smoke" "QA APK could not be installed" \
      "Install the newly built QA APK on $AVD_ID." "$install_log"
    record_case \
      "M24-QA-SMOKE" "" "qa-smoke" "QA console installs and launches" \
      "Installation failed" "FAIL" "P0" "$LAST_DEFECT_ID" "" "" \
      "$install_log" ""
    return 0
  fi

  start_screen_recording "qa-console-${AVD_ID}"
  if ! launch_apk "$QA_APK" "$QA_PACKAGE" "$launch_log"; then
    stop_screen_recording
    capture_snapshot "qa-console-launch-failure-${AVD_ID}"
    record_defect \
      "P0" "qa-smoke" "QA APK did not launch" \
      "Start the QA APK launcher activity." "$launch_log"
    record_case \
      "M24-QA-SMOKE" "" "qa-smoke" "QA console installs and launches" \
      "Launch failed" "FAIL" "P0" "$LAST_DEFECT_ID" \
      "$SCREENSHOT_DIR/qa-console-launch-failure-${AVD_ID}.png" \
      "$VIDEO_DIR/qa-console-${AVD_ID}.mp4" "$launch_log" ""
    return 0
  fi
  sleep 4
  capture_snapshot "qa-console-${AVD_ID}"
  stop_screen_recording

  local ui_dump="$DUMP_DIR/qa-console-${AVD_ID}-ui.xml"
  local system_component_anr_pattern="(System UI|Pixel Launcher) (isn't|is not|isn’t) responding|系统界面.*无响应|Pixel Launcher.*无响应|Pixel 启动器.*无响应"
  if [[ -s "$ui_dump" ]] && \
      grep -Eq "$system_component_anr_pattern" "$ui_dump"; then
    local anr_ui_dump="$DUMP_DIR/qa-console-systemui-anr-${AVD_ID}-ui.xml"
    local anr_screenshot="$SCREENSHOT_DIR/qa-console-systemui-anr-${AVD_ID}.png"
    local anr_match_log="$LOG_DIR/qa-console-system-component-anr-${AVD_ID}.log"
    cp "$ui_dump" "$anr_ui_dump"
    if [[ -f "$SCREENSHOT_DIR/qa-console-${AVD_ID}.png" ]]; then
      cp "$SCREENSHOT_DIR/qa-console-${AVD_ID}.png" "$anr_screenshot"
    fi
    grep -Eo "$system_component_anr_pattern" "$anr_ui_dump" \
      >"$anr_match_log" 2>&1 || true
    record_defect \
      "P2" "environment" "Android system component ANR dialog obscured the QA launch" \
      "Dismiss the System UI or Pixel Launcher dialog, wait for the system component to stabilize, and relaunch the same QA APK." \
      "$anr_ui_dump"

    # AOSP's ANR dialog for the explicitly allow-listed System UI and Pixel
    # Launcher components is non-cancelable, so KEYCODE_BACK cannot reliably
    # dismiss it. App ANRs are intentionally not matched or dismissed here.
    # Select the stable aerr_wait control from its captured bounds instead of
    # hard-coding coordinates for one emulator density.
    local wait_node=""
    wait_node="$(
      grep -oE \
        'resource-id="android:id/aerr_wait"[^>]*bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' \
        "$anr_ui_dump" | head -n 1 || true
    )"
    if [[ "$wait_node" =~ bounds=\"\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\]\" ]]; then
      local wait_x=$(( (BASH_REMATCH[1] + BASH_REMATCH[3]) / 2 ))
      local wait_y=$(( (BASH_REMATCH[2] + BASH_REMATCH[4]) / 2 ))
      adb_device shell input tap "$wait_x" "$wait_y" >/dev/null 2>&1 || true
    fi
    sleep 6
    adb_device shell am force-stop "$QA_PACKAGE" >/dev/null 2>&1 || true
    launch_apk "$QA_APK" "$QA_PACKAGE" "$launch_log" || true
    sleep 4
    capture_snapshot "qa-console-${AVD_ID}"
  fi

  exercise_qa_console_system_input "$ui_dump"

  if [[ -n "$activity" ]]; then
    adb_device shell am force-stop "$QA_PACKAGE" >/dev/null 2>&1 || true
    adb_device shell am start -W -n "${QA_PACKAGE}/${activity}" \
      >"$cold_log" 2>&1 || true
    adb_device shell input keyevent KEYCODE_HOME >/dev/null 2>&1 || true
    adb_device shell am start -W -n "${QA_PACKAGE}/${activity}" \
      >"$warm_log" 2>&1 || true
  fi
  {
    printf 'cold_start_begin\n'; cat "$cold_log" 2>/dev/null || true
    printf 'cold_start_end\n'
    printf 'warm_start_begin\n'; cat "$warm_log" 2>/dev/null || true
    printf 'warm_start_end\n'
    printf 'initial_meminfo_begin\n'
    adb_device shell dumpsys meminfo "$QA_PACKAGE" || true
    printf 'initial_meminfo_end\n'
  } >>"$PERFORMANCE_FILE" 2>&1

  cold_ms="$(awk -F: '
    /TotalTime/ {gsub(/[[:space:]]/, "", $2); total=$2}
    /WaitTime/ {gsub(/[[:space:]]/, "", $2); wait=$2}
    END {print total != "" ? total : wait}
  ' \
    "$cold_log" 2>/dev/null || true)"
  warm_ms="$(awk -F: '
    /TotalTime/ {gsub(/[[:space:]]/, "", $2); total=$2}
    /WaitTime/ {gsub(/[[:space:]]/, "", $2); wait=$2}
    END {print total != "" ? total : wait}
  ' \
    "$warm_log" 2>/dev/null || true)"
  if [[ "$cold_ms" =~ ^[0-9]+$ && "$warm_ms" =~ ^[0-9]+$ ]]; then
    local timing_note="Emulator performance is recorded as a regression baseline, not a real-device claim or a functional gate."
    if (( cold_ms > 5000 || warm_ms > 2500 )); then
      timing_note="Hosted-emulator guidance exceeded; investigate the trend, but do not convert a successful install/cold launch into a product failure."
    fi
    record_case \
      "M24-STARTUP-PERF" "" "performance" \
      "Cold and warm startup timings are captured on the same runner/AVD" \
      "cold=${cold_ms}ms warm=${warm_ms}ms" "PASS" "" "" "" "" \
      "$PERFORMANCE_FILE" "$timing_note"
  else
    record_defect \
      "P1" "performance" "Startup timing evidence was missing" \
      "Measure am start -W cold and warm launch on the same runner/AVD." \
      "$PERFORMANCE_FILE"
    record_case \
      "M24-STARTUP-PERF" "" "performance" \
      "Cold and warm startup timings are captured on the same runner/AVD" \
      "cold=${cold_ms:-missing}ms warm=${warm_ms:-missing}ms" \
      "FAIL" "P1" "$LAST_DEFECT_ID" "" "" "$PERFORMANCE_FILE" \
      "Missing evidence is an infrastructure failure; measured outliers remain visible observations."
  fi

  verify_qa_console_metrics "$ui_dump"
  if [[ -f "$ui_dump" ]] && grep -q 'M2.4 QA Console' "$ui_dump"; then
    record_case \
      "M24-QA-SMOKE" "" "qa-smoke" \
      "Debug-only M2.4 QA Console is visible" "QA Console found in UI tree" \
      "PASS" "" "" "$SCREENSHOT_DIR/qa-console-${AVD_ID}.png" \
      "$VIDEO_DIR/qa-console-${AVD_ID}.mp4" "$launch_log" \
      "The overlay records actual MediaQuery and devicePixelRatio."
  else
    record_defect \
      "P1" "qa-smoke" "QA Console was not found after launching QA APK" \
      "Install and launch the mock debug build with ENABLE_QA_CONSOLE=true." \
      "$ui_dump"
    record_case \
      "M24-QA-SMOKE" "" "qa-smoke" \
      "Debug-only M2.4 QA Console is visible" "QA Console absent from UI tree" \
      "FAIL" "P1" "$LAST_DEFECT_ID" \
      "$SCREENSHOT_DIR/qa-console-${AVD_ID}.png" \
      "$VIDEO_DIR/qa-console-${AVD_ID}.mp4" "$launch_log" \
      "Screenshot is retained for manual white-screen/layout review."
  fi
  adb_device uninstall "$QA_PACKAGE" >"$LOG_DIR/qa-smoke-uninstall.log" 2>&1 || true
}

run_release_qa_gate() {
  [[ "$AVD_ID" == "AVD-A" && "$QA_SCOPE_VALUE" == "full" ]] || return 0
  local -a defines=()
  local build_log="$LOG_DIR/release-qa-gate-build.log"
  local install_log="$LOG_DIR/release-qa-gate-install.log"
  local launch_log="$LOG_DIR/release-qa-gate-launch.log"
  local release_apk="$PROJECT_ROOT/build/app/outputs/flutter-apk/app-release.apk"
  local release_package ui_dump
  mapfile -t defines < <(qa_dart_defines true)

  # A preceding debug build registers the dev-only integration_test plugin.
  # Regenerate the Android registrant for release so the dev plugin is not
  # referenced from the release Java classpath.
  if ! run_logged "$LOG_DIR/release-qa-gate-clean.log" flutter clean; then
    record_defect \
      "P0" "qa-security" "Release QA gate cleanup failed" \
      "Run flutter clean before the release-only QA gate build." \
      "$LOG_DIR/release-qa-gate-clean.log"
    return 0
  fi
  if ! run_logged "$LOG_DIR/release-qa-gate-pub-get.log" \
      flutter pub get --enforce-lockfile; then
    record_defect \
      "P0" "qa-security" "Release QA gate dependency restore failed" \
      "Restore the locked dependency graph after flutter clean." \
      "$LOG_DIR/release-qa-gate-pub-get.log"
    return 0
  fi

  # Do not pass --no-pub here. Flutter's release build must regenerate the
  # platform registrant in release mode so the dev-only integration_test
  # plugin is removed from the Java source before javac runs.
  if ! run_logged "$build_log" flutter build apk \
      --release "${defines[@]}"; then
    record_defect \
      "P0" "qa-security" "Release QA-console gate APK failed to build" \
      "Build release with ENABLE_QA_CONSOLE=true to prove kDebugMode keeps it unreachable." \
      "$build_log"
    return 0
  fi
  if [[ ! -f "$release_apk" ]]; then
    record_defect \
      "P0" "qa-security" "Release build succeeded without app-release.apk" \
      "Inspect the Flutter release output directory." "$build_log"
    return 0
  fi
  printf 'release_gate=%s\n' "$(sha256sum "$release_apk" | awk '{print $1}')" \
    >>"$APK_SHA_FILE"
  write_apk_metadata "release-qa-gate" "$release_apk" "$BUILD_INFO_FILE"
  validate_apk_sdk_compatibility "release-qa-gate" "$release_apk"
  release_package="$(apk_manifest_value application-id "$release_apk")"
  if [[ -z "$release_package" ]]; then
    record_defect \
      "P0" "qa-security" "Could not read release gate applicationId" \
      "Inspect app-release.apk with apkanalyzer or aapt." "$BUILD_INFO_FILE"
    return 0
  fi

  adb_device uninstall "$release_package" >>"$install_log" 2>&1 || true
  if ! run_logged "$install_log" adb_device install "$release_apk"; then
    record_defect \
      "P0" "qa-security" "Release gate APK could not be installed" \
      "Install the locally built release APK on AVD-A." "$install_log"
    return 0
  fi
  if ! launch_apk "$release_apk" "$release_package" "$launch_log"; then
    capture_snapshot "release-qa-gate-launch-failure-${AVD_ID}"
    record_defect \
      "P0" "qa-security" "Release gate APK did not launch" \
      "Launch the release APK with the detected activity." "$launch_log"
    adb_device uninstall "$release_package" >>"$install_log" 2>&1 || true
    return 0
  fi
  sleep 5
  capture_snapshot "release-qa-gate-${AVD_ID}"
  ui_dump="$DUMP_DIR/release-qa-gate-${AVD_ID}-ui.xml"

  if [[ -s "$ui_dump" ]] && \
      ! grep -q 'M2.4 QA Console' "$ui_dump" && \
      grep -q '同意并继续' "$ui_dump"; then
    record_case \
      "M24-RELEASE-QA-GATE" "AC-002" "qa-security" \
      "Release never exposes QA Console even when the compile-time flag is true" \
      "QA Console absent and normal consent entry visible" "PASS" "" "" \
      "$SCREENSHOT_DIR/release-qa-gate-${AVD_ID}.png" "" "$launch_log" \
      "The release APK is not copied into long-lived artifacts."
  else
    record_defect \
      "P0" "qa-security" \
      "Release QA gate was reachable or the normal AppGate entry was absent" \
      "Build release with ENABLE_QA_CONSOLE=true, launch from clean data, and inspect the UI dump." \
      "$ui_dump" "AC-002"
    record_case \
      "M24-RELEASE-QA-GATE" "AC-002" "qa-security" \
      "QA Console absent; normal consent entry visible" \
      "UI gate assertion failed" "FAIL" "P0" "$LAST_DEFECT_ID" \
      "$SCREENSHOT_DIR/release-qa-gate-${AVD_ID}.png" "" "$launch_log" ""
  fi
  adb_device uninstall "$release_package" >>"$install_log" 2>&1 || true
}

pull_framework_screenshots() {
  local test_name="$1"
  (( API_LEVEL < 26 )) || return 0
  [[ -n "$QA_PACKAGE" ]] || return 0
  local remote_directory="cache/m24-framework-screenshots"
  local pull_log="$LOG_DIR/${test_name}-framework-screenshot-pull.log"
  local listing=""
  local remote_name destination partial magic
  local pulled=0
  : >"$pull_log"

  set +e
  listing="$(
    adb_device_bounded 20s shell run-as "$QA_PACKAGE" \
      ls -1 "$remote_directory" 2>>"$pull_log"
  )"
  local list_status=$?
  set -e
  printf 'list_exit=%s\n' "$list_status" >>"$pull_log"
  if (( list_status != 0 )); then
    progress_event screenshot_pull \
      "test=$test_name status=list_failed exit=$list_status"
    adb_device_bounded 20s shell run-as "$QA_PACKAGE" \
      rm -rf "$remote_directory" >>"$pull_log" 2>&1 || true
    return 0
  fi

  while IFS= read -r remote_name; do
    remote_name="${remote_name//$'\r'/}"
    [[ "$remote_name" =~ ^[A-Za-z0-9_.-]+\.png$ ]] || {
      printf 'ignored_remote_name=%q\n' "$remote_name" >>"$pull_log"
      continue
    }
    destination="$SCREENSHOT_DIR/$remote_name"
    partial="$destination.partial"
    if adb_device_bounded 30s exec-out run-as "$QA_PACKAGE" \
        cat "$remote_directory/$remote_name" >"$partial" 2>>"$pull_log" && \
        [[ -s "$partial" ]]; then
      magic="$(od -An -tx1 -N8 "$partial" | tr -d '[:space:]')"
      if [[ "$magic" == "89504e470d0a1a0a" ]]; then
        mv -f -- "$partial" "$destination"
        ((pulled += 1))
        printf 'pulled=%s sha256=%s\n' \
          "$remote_name" "$(sha256sum "$destination" | awk '{print $1}')" \
          >>"$pull_log"
      else
        rm -f -- "$partial"
        printf 'invalid_png=%s magic=%s\n' "$remote_name" "$magic" \
          >>"$pull_log"
      fi
    else
      rm -f -- "$partial"
      printf 'pull_failed=%s\n' "$remote_name" >>"$pull_log"
    fi
  done <<<"$listing"
  adb_device_bounded 20s shell run-as "$QA_PACKAGE" \
    rm -rf "$remote_directory" >>"$pull_log" 2>&1 || true
  printf 'pulled_count=%s\n' "$pulled" >>"$pull_log"
  progress_event screenshot_pull "test=$test_name count=$pulled"
}

recover_after_integration() {
  local test_name="$1"
  local recovery_log="$LOG_DIR/${test_name}-post-drive-recovery.log"
  local attempt state="" boot_completed=""
  progress_event target_cleanup "test=$test_name phase=start"
  {
    printf 'timestamp=%s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    printf 'host_processes_begin\n'
    pgrep -af 'flutter_tools|flutter drive|dart.*test|GradleDaemon' || true
    printf 'host_processes_end\n'
    printf 'listening_ports_begin\n'
    ss -ltnp 2>/dev/null || true
    printf 'listening_ports_end\n'
  } >"$recovery_log" 2>&1

  # timeout owns the flutter-drive process group. Remove the device-side app
  # and VM-service forwarding state before the next target so one timed-out
  # target cannot poison all later critical flows.
  if [[ -n "$QA_PACKAGE" ]]; then
    adb_device_bounded 20s shell am force-stop "$QA_PACKAGE" \
      >>"$recovery_log" 2>&1 || true
  fi
  adb_device_bounded 20s forward --remove-all >>"$recovery_log" 2>&1 || true
  adb_device_bounded 20s reverse --remove-all >>"$recovery_log" 2>&1 || true

  for attempt in {1..3}; do
    state="$(adb_device_bounded 15s get-state 2>>"$recovery_log" || true)"
    boot_completed="$(
      adb_device_bounded 15s shell getprop sys.boot_completed \
        2>>"$recovery_log" | tr -d '\r' || true
    )"
    printf 'attempt=%s state=%s boot_completed=%s\n' \
      "$attempt" "$state" "$boot_completed" >>"$recovery_log"
    if [[ "$state" == "device" && "$boot_completed" == "1" ]]; then
      progress_event target_cleanup "test=$test_name status=healthy"
      return 0
    fi
    sleep 2
  done

  record_defect \
    "P0" "runner" "Emulator was unhealthy after $test_name" \
    "Inspect the bounded flutter-drive and post-drive recovery logs." \
    "$recovery_log"
  progress_event target_cleanup "test=$test_name status=unhealthy"
  return 1
}

run_integration_file() {
  local test_file="$1"
  local timeout_value="$2"
  local test_name
  local test_id
  local log_file
  local status
  local drive_guard_pid
  local log_stream_pid
  local -a defines=()
  local -a lifecycle_args=()
  test_name="$(basename "$test_file" .dart)"
  test_id="M24-INT-${test_name#m2_4_}"
  log_file="$LOG_DIR/${test_name}.log"
  # Only the dedicated console target enables the QA root. Flow tests call
  # VoiceSocialApp directly and must retain the normal AppGate entry.
  if [[ "$test_name" == "m2_4_qa_console_flow_test" ]]; then
    mapfile -t defines < <(qa_dart_defines true)
  else
    mapfile -t defines < <(qa_dart_defines false)
  fi

  if [[ "$test_name" == "m2_4_offline_emulator_test" ]]; then
    start_screen_recording "${test_name}-${AVD_ID}"
  fi
  if [[ "$test_name" == "m2_4_offline_emulator_test" ]] || \
      (( API_LEVEL < 26 )); then
    # API24 flow screenshots are written into the debuggable package cache and
    # pulled immediately after drive exits. Flutter drive normally uninstalls
    # the package during stop(), which would erase that cache before the host
    # can collect it, so keep the package only for this bounded pull/cleanup.
    lifecycle_args+=(--keep-app-running)
  fi

  : >"$log_file"
  progress_event target_start "test=$test_name timeout=$timeout_value"
  set +e
  # Let timeout own a separate process group and write directly to the log.
  # Using --foreground with a `| tee` pipeline can leave Gradle/Dart children
  # holding the pipe open after the Flutter parent is terminated.
  QA_SCREENSHOT_DIR="$SCREENSHOT_DIR" \
    timeout --signal=TERM --kill-after=30s "$timeout_value" \
    flutter drive \
      --driver=test_driver/integration_test.dart \
      --target="$test_file" \
      --device-id="$DEVICE_ID" \
      --debug \
      --no-pub \
      "${lifecycle_args[@]}" \
      "${defines[@]}" \
      >"$log_file" 2>&1 &
  drive_guard_pid=$!
  tail --pid="$drive_guard_pid" --sleep-interval=1 -n +1 -F "$log_file" &
  log_stream_pid=$!
  wait "$drive_guard_pid"
  status=$?
  stop_host_process_bounded "$log_stream_pid" TERM
  set -e
  progress_event target_end "test=$test_name exit=$status"

  # API 24 writes Flutter-layer PNGs into the debuggable package cache to
  # avoid transporting large byte arrays through integrationDriver JSON.
  # Pull even after a timeout so completed flow steps remain auditable.
  pull_framework_screenshots "$test_name"

  if [[ "$test_name" == "m2_4_offline_emulator_test" ]]; then
    stop_screen_recording
  fi

  if (( status == 0 )); then
    INTEGRATION_RESULTS["$test_name"]="PASS"
    INTEGRATION_DEFECTS["$test_name"]=""
    record_case \
      "$test_id" "" "integration" "$test_file passes on $AVD_ID" \
      "flutter drive exit 0" "PASS" "" "" "" \
      "$VIDEO_DIR/${test_name}-${AVD_ID}.mp4" "$log_file" \
      "BACKEND_MODE=mock; device networking remains disabled."
    if [[ "$test_name" == "m2_4_page_coverage_test" ]]; then
      PAGE_COVERAGE_STATUS="PASS"
    fi
  else
    capture_snapshot "failure-${test_name}-${AVD_ID}"
    record_defect \
      "P1" "integration" "$test_file failed with exit $status" \
      "Run the same flutter drive target on $AVD_ID." "$log_file"
    INTEGRATION_RESULTS["$test_name"]="FAIL"
    INTEGRATION_DEFECTS["$test_name"]="$LAST_DEFECT_ID"
    record_case \
      "$test_id" "" "integration" "$test_file passes on $AVD_ID" \
      "flutter drive exit $status" "FAIL" "P1" "$LAST_DEFECT_ID" \
      "$SCREENSHOT_DIR/failure-${test_name}-${AVD_ID}.png" \
      "$VIDEO_DIR/${test_name}-${AVD_ID}.mp4" "$log_file" \
      "Failure does not skip later integration files."
    if [[ "$test_name" == "m2_4_page_coverage_test" ]]; then
      PAGE_COVERAGE_STATUS="FAIL"
    fi
  fi

  recover_after_integration "$test_name"
}

run_session_restore_smoke() {
  local source_result="${INTEGRATION_RESULTS[m2_4_offline_emulator_test]:-NOT_TESTED}"
  [[ "$source_result" == "PASS" ]] || {
    INTEGRATION_RESULTS[session_restore]="FAIL"
    INTEGRATION_DEFECTS[session_restore]="${INTEGRATION_DEFECTS[m2_4_offline_emulator_test]:-}"
    return 0
  }
  local launch_log="$LOG_DIR/session-restore-launch.log"
  local install_log="$LOG_DIR/session-restore-mock-apk-install.log"
  local ui_dump="$DUMP_DIR/FLOW-003-session-restore-${AVD_ID}-ui.xml"
  if [[ -z "$MOCK_DEBUG_APK" || ! -f "$MOCK_DEBUG_APK" || \
        -z "$MOCK_DEBUG_PACKAGE" || \
        "$MOCK_DEBUG_PACKAGE" != "$QA_PACKAGE" ]]; then
    record_defect \
      "P1" "lifecycle" "Ordinary mock debug APK is unavailable for session restore" \
      "Build and retain the console-disabled mock main APK before flutter drive." \
      "$LOG_DIR/session-restore-mock-apk-build.log" "AC-001" "FLOW-003"
    INTEGRATION_RESULTS[session_restore]="FAIL"
    INTEGRATION_DEFECTS[session_restore]="$LAST_DEFECT_ID"
    return 0
  fi

  # Replace the integration target in place. `adb install -r` is intentional:
  # uninstalling would erase the secure-storage session FLOW-001 just created,
  # while a signature mismatch must fail rather than silently clear data.
  if ! run_logged "$install_log" adb_device install -r "$MOCK_DEBUG_APK"; then
    {
      printf 'sha256=%s\n' "$MOCK_DEBUG_SHA256"
      printf 'application_id=%s\n' "$MOCK_DEBUG_PACKAGE"
      printf 'preserve_data=true\n'
    } >>"$install_log"
    capture_snapshot "FLOW-003-session-restore-install-failure-${AVD_ID}"
    record_defect \
      "P1" "lifecycle" "Ordinary mock main APK could not replace the integration target" \
      "Use the same debug signing identity and adb install -r so secure storage is preserved." \
      "$install_log" "AC-001" "FLOW-003"
    INTEGRATION_RESULTS[session_restore]="FAIL"
    INTEGRATION_DEFECTS[session_restore]="$LAST_DEFECT_ID"
    return 0
  fi
  {
    printf 'sha256=%s\n' "$MOCK_DEBUG_SHA256"
    printf 'application_id=%s\n' "$MOCK_DEBUG_PACKAGE"
    printf 'preserve_data=true\n'
    printf 'install_result=PASS\n'
  } >>"$install_log"

  adb_device shell am force-stop "$MOCK_DEBUG_PACKAGE" \
    >>"$launch_log" 2>&1 || true
  if ! launch_apk "$MOCK_DEBUG_APK" "$MOCK_DEBUG_PACKAGE" "$launch_log"; then
    capture_snapshot "FLOW-003-session-restore-launch-failure-${AVD_ID}"
    record_defect \
      "P1" "lifecycle" "Authenticated mock session did not relaunch" \
      "After FLOW-001, install -r and relaunch the ordinary console-disabled mock main." \
      "$launch_log" "AC-001" "FLOW-003"
    INTEGRATION_RESULTS[session_restore]="FAIL"
    INTEGRATION_DEFECTS[session_restore]="$LAST_DEFECT_ID"
    return 0
  fi
  local attempt
  for attempt in {1..10}; do
    sleep 2
    capture_snapshot "FLOW-003-session-restore-${AVD_ID}"
    if [[ -s "$ui_dump" ]] && grep -q '此刻适合你的房间' "$ui_dump"; then
      break
    fi
  done
  if [[ -s "$ui_dump" ]] && grep -q '此刻适合你的房间' "$ui_dump" && \
      ! grep -q 'M2.4 QA Console' "$ui_dump"; then
    INTEGRATION_RESULTS[session_restore]="PASS"
    INTEGRATION_DEFECTS[session_restore]=""
    record_case \
      "M24-SESSION-RESTORE" "AC-001" "lifecycle" \
      "Force-stop/relaunch restores the authenticated mock home" \
      "Home restored and QA Console remained absent" "PASS" "" "" \
      "$SCREENSHOT_DIR/FLOW-003-session-restore-${AVD_ID}.png" "" "$launch_log" \
      "Runs after same-signature install -r replaces the integration target with the ordinary mock main."
  else
    record_defect \
      "P1" "lifecycle" "Force-stop/relaunch did not restore the mock home" \
      "Complete FLOW-001, force-stop, relaunch, and inspect the UI hierarchy." \
      "$ui_dump" "AC-001" "FLOW-003"
    INTEGRATION_RESULTS[session_restore]="FAIL"
    INTEGRATION_DEFECTS[session_restore]="$LAST_DEFECT_ID"
    record_case \
      "M24-SESSION-RESTORE" "AC-001" "lifecycle" \
      "Force-stop/relaunch restores the authenticated mock home" \
      "Expected home text was absent" "FAIL" "P1" "$LAST_DEFECT_ID" \
      "$SCREENSHOT_DIR/FLOW-003-session-restore-${AVD_ID}.png" "" "$launch_log" ""
  fi
}

run_page_coverage_shards() {
  local target="integration_test/m2_4_page_coverage_test.dart"
  local aggregate_log="$LOG_DIR/m2_4_page_coverage_test.log"
  local scale shard scale_label shard_log status
  local failures=0
  local first_defect=""
  local count_one count_one_three
  local -a defines=()
  : >"$aggregate_log"
  PAGE_COVERAGE_STATUS="PASS"

  if [[ ! -f "$target" ]]; then
    record_defect \
      "P1" "page-coverage" "Page coverage integration target is missing" \
      "Check out $target before starting the 10-process shard matrix." "$target"
    PAGE_COVERAGE_STATUS="FAIL"
    INTEGRATION_RESULTS[m2_4_page_coverage_test]="FAIL"
    INTEGRATION_DEFECTS[m2_4_page_coverage_test]="$LAST_DEFECT_ID"
    return 0
  fi

  for scale in 1.0 1.3; do
    scale_label="${scale//./_}"
    for shard in 1 2 3 4 5; do
      shard_log="$LOG_DIR/m2_4_page_coverage_test-scale-${scale}-shard-${shard}.log"
      mapfile -t defines < <(qa_dart_defines false)
      defines+=(
        "--dart-define=QA_PAGE_SHARD=$shard"
        "--dart-define=QA_TEXT_SCALE=$scale"
      )
      set +e
      QA_SCREENSHOT_DIR="$SCREENSHOT_DIR" \
        timeout --foreground --signal=TERM --kill-after=30s 20m \
        flutter drive \
          --driver=test_driver/integration_test.dart \
          --target="$target" \
          --device-id="$DEVICE_ID" \
          --debug --no-pub "${defines[@]}" \
          2>&1 | tee "$shard_log"
      status=${PIPESTATUS[0]}
      set -e
      printf 'scale=%s shard=%s exit=%s log=%s\n' \
        "$scale" "$shard" "$status" "$shard_log" >>"$aggregate_log"
      if (( status == 0 )); then
        record_case \
          "M24-PAGES-${scale_label}-S${shard}" "" "page-coverage" \
          "Shard $shard/5 at ${scale}x renders and captures" \
          "flutter drive exit 0" "PASS" "" "" "" "" "$shard_log" \
          "ENABLE_QA_CONSOLE=false; one shard and one text scale per process."
      else
        ((failures += 1))
        capture_snapshot "failure-pages-${scale_label}-shard-${shard}-${AVD_ID}"
        record_defect \
          "P1" "page-coverage" \
          "Page coverage shard $shard/5 at ${scale}x failed with exit $status" \
          "Run only QA_PAGE_SHARD=$shard and QA_TEXT_SCALE=$scale." "$shard_log"
        [[ -n "$first_defect" ]] || first_defect="$LAST_DEFECT_ID"
        record_case \
          "M24-PAGES-${scale_label}-S${shard}" "" "page-coverage" \
          "Shard $shard/5 at ${scale}x renders and captures" \
          "flutter drive exit $status" "FAIL" "P1" "$LAST_DEFECT_ID" \
          "$SCREENSHOT_DIR/failure-pages-${scale_label}-shard-${shard}-${AVD_ID}.png" \
          "" "$shard_log" "Later shards still execute for complete evidence."
      fi
    done
  done

  count_one="$(find "$SCREENSHOT_DIR" -maxdepth 1 -type f \
    -name "*-normal-${AVD_ID}-*-1.0x.png" -print | wc -l | tr -d ' ')"
  count_one_three="$(find "$SCREENSHOT_DIR" -maxdepth 1 -type f \
    -name "*-normal-${AVD_ID}-*-1.3x.png" -print | wc -l | tr -d ' ')"
  printf 'screenshots_1.0x=%s\nscreenshots_1.3x=%s\n' \
    "$count_one" "$count_one_three" >>"$aggregate_log"
  if (( failures == 0 && count_one == 69 && count_one_three == 69 )); then
    PAGE_COVERAGE_STATUS="PASS"
    INTEGRATION_RESULTS[m2_4_page_coverage_test]="PASS"
    INTEGRATION_DEFECTS[m2_4_page_coverage_test]=""
    record_case \
      "M24-PAGE-SHARDS" "" "page-coverage" \
      "10/10 shard processes pass and emit exactly 69 screenshots per scale" \
      "failures=0; 1.0x=$count_one; 1.3x=$count_one_three" \
      "PASS" "" "" "$SCREENSHOT_DIR" "" "$aggregate_log" \
      "The default all/all mode is never used in CI."
  else
    PAGE_COVERAGE_STATUS="FAIL"
    if [[ -z "$first_defect" ]]; then
      record_defect \
        "P1" "page-coverage" \
        "Page shard screenshot cardinality is not exactly 69 at both scales" \
        "Run all five shards separately for 1.0x and 1.3x." "$aggregate_log"
      first_defect="$LAST_DEFECT_ID"
    fi
    INTEGRATION_RESULTS[m2_4_page_coverage_test]="FAIL"
    INTEGRATION_DEFECTS[m2_4_page_coverage_test]="$first_defect"
    record_case \
      "M24-PAGE-SHARDS" "" "page-coverage" \
      "10/10 shard processes pass and emit exactly 69 screenshots per scale" \
      "failures=$failures; 1.0x=$count_one; 1.3x=$count_one_three" \
      "FAIL" "P1" "$first_defect" "$SCREENSHOT_DIR" "" "$aggregate_log" \
      "No partial shard matrix is promoted to PASS."
  fi
}

run_integration_suite() {
  INTEGRATION_SUITE_STARTED=1
  local -a tests=()
  if [[ "$QA_SCOPE_VALUE" == "full" ]]; then
    tests=(
      "integration_test/m2_4_qa_console_flow_test.dart:8m"
      "integration_test/m2_4_fixture_authority_flow_test.dart:8m"
      "integration_test/m2_4_offline_emulator_test.dart:20m"
      "integration_test/m2_4_room_flow_test.dart:25m"
      "integration_test/m2_4_commerce_flow_test.dart:20m"
      "integration_test/m2_4_message_flow_test.dart:20m"
      "integration_test/m2_4_community_flow_test.dart:20m"
    )
  elif [[ "$QA_SCOPE_VALUE" == "critical" ]]; then
    tests=(
      "integration_test/m2_4_qa_console_flow_test.dart:8m"
      "integration_test/m2_4_fixture_authority_flow_test.dart:8m"
      "integration_test/m2_4_offline_emulator_test.dart:12m"
      "integration_test/m2_4_room_flow_test.dart:15m"
      "integration_test/m2_4_commerce_flow_test.dart:12m"
      "integration_test/m2_4_message_flow_test.dart:10m"
      "integration_test/m2_4_community_flow_test.dart:12m"
    )
  else
    record_defect \
      "P0" "configuration" "Unknown QA_SCOPE: $QA_SCOPE_VALUE" \
      "Use full or critical." "$ENVIRONMENT_FILE"
    exit 64
  fi

  local entry test_file timeout_value
  for entry in "${tests[@]}"; do
    test_file="${entry%%:*}"
    timeout_value="${entry##*:}"
    if [[ ! -f "$test_file" ]]; then
      local missing_name
      missing_name="$(basename "$test_file" .dart)"
      record_defect \
        "P1" "integration" "Required integration test is missing: $test_file" \
        "Check out all M2.4 integration_test sources." "$test_file"
      record_case \
        "M24-INT-MISSING" "" "integration" "$test_file exists" \
        "File missing" "FAIL" "P1" "$LAST_DEFECT_ID" "" "" "" ""
      INTEGRATION_RESULTS["$missing_name"]="FAIL"
      INTEGRATION_DEFECTS["$missing_name"]="$LAST_DEFECT_ID"
      continue
    fi
    if ! run_integration_file "$test_file" "$timeout_value"; then
      # The remaining flows are not executed on an unhealthy emulator. They
      # are later emitted as explicit FAIL/NOT_TESTED records by the critical
      # flow inventory; this is never promoted to a pass.
      break
    fi
    if [[ "$test_file" == "integration_test/m2_4_offline_emulator_test.dart" ]]; then
      run_session_restore_smoke
    fi
  done
  if [[ "$QA_SCOPE_VALUE" == "full" ]]; then
    run_page_coverage_shards
  fi
}

record_flow_inventory() {
  local index flow_id title source_key source_result source_defect
  local result actual defect_id log_file screenshot notes
  for ((index = 1; index <= 15; index += 1)); do
    printf -v flow_id 'FLOW-%03d' "$index"
    source_key=""
    case "$flow_id" in
      FLOW-001) title="First-install login"; source_key="m2_4_offline_emulator_test" ;;
      FLOW-002) title="Unregistered-account onboarding"; source_key="m2_4_offline_emulator_test" ;;
      FLOW-003) title="Authenticated session restore"; source_key="session_restore" ;;
      FLOW-004) title="Home-to-room direct entry"; source_key="m2_4_room_flow_test" ;;
      FLOW-005) title="Room core actions"; source_key="m2_4_room_flow_test" ;;
      FLOW-006) title="Search direct entry and invalid recovery"; source_key="m2_4_room_flow_test" ;;
      FLOW-007) title="Host moderation"; source_key="m2_4_room_flow_test" ;;
      FLOW-008) title="Room PK lifecycle"; source_key="m2_4_room_flow_test" ;;
      FLOW-009) title="Dynamic publishing and engagement"; source_key="m2_4_community_flow_test" ;;
      FLOW-010) title="Social follow/block/report"; source_key="m2_4_message_flow_test" ;;
      FLOW-011) title="Account compliance boundaries"; source_key="m2_4_offline_emulator_test" ;;
      FLOW-012) title="Commerce lifecycle"; source_key="m2_4_commerce_flow_test" ;;
      FLOW-013) title="Messaging and notifications"; source_key="m2_4_message_flow_test" ;;
      FLOW-014) title="Guild and community relationships"; source_key="m2_4_community_flow_test" ;;
      FLOW-015) title="Ten room entry/exit stability loops"; source_key="m2_4_room_flow_test" ;;
    esac
    source_result="NOT_TESTED"
    source_defect=""
    log_file=""
    if [[ -n "$source_key" ]]; then
      source_result="${INTEGRATION_RESULTS[$source_key]:-NOT_TESTED}"
      source_defect="${INTEGRATION_DEFECTS[$source_key]:-}"
      if [[ "$source_key" == "session_restore" ]]; then
        log_file="$LOG_DIR/session-restore-launch.log"
      else
        log_file="$LOG_DIR/${source_key}.log"
      fi
    fi
    screenshot="$(find "$SCREENSHOT_DIR" -maxdepth 1 -type f \
      -name "${flow_id}-*" -print -quit 2>/dev/null || true)"
    defect_id=""

    if [[ "$QA_SCOPE_VALUE" == "critical" ]]; then
      case "$flow_id" in
        FLOW-001 | FLOW-002 | FLOW-003 | FLOW-004 | FLOW-005 | FLOW-006 | \
          FLOW-007 | FLOW-008 | FLOW-011 | FLOW-012 | FLOW-013 | FLOW-014 | \
          FLOW-015)
          if [[ "$source_result" == "PASS" && -n "$screenshot" ]]; then
            result="PASS"
            actual="Required API-24 critical regression subset passed"
            notes="AVD-B result is a critical-path regression, not full-flow acceptance."
          else
            result="FAIL"
            actual="Critical source result=$source_result screenshot=${screenshot:-MISSING}"
            defect_id="$source_defect"
            if [[ -z "$defect_id" ]]; then
              record_defect \
                "P1" "flow-coverage" "$flow_id critical regression is missing" \
                "Execute the mapped API-24 integration or lifecycle target." \
                "${log_file:-$TEST_CASES_FILE}" "" "$flow_id"
              defect_id="$LAST_DEFECT_ID"
            fi
            notes="AVD-B cannot pass its required critical subset."
          fi
          ;;
        *)
          result="NOT_APPLICABLE"
          actual="Not in the approved AVD-B critical subset"
          notes="Full end-to-end flow acceptance runs on AVD-A."
          ;;
      esac
    else
      if [[ "$source_result" == "PASS" && -n "$screenshot" ]]; then
        result="PASS"
        actual="All currently specified steps for this flow passed"
        notes="Evidence is linked to the mapped lifecycle/integration target."
      else
        result="FAIL"
        actual="source_result=$source_result; full end-to-end evidence incomplete"
        defect_id="$source_defect"
        if [[ -z "$defect_id" ]]; then
          record_defect \
            "P1" "flow-coverage" "$flow_id is not fully automated end to end" \
            "Complete every acceptance step for $title and attach screenshot/video/log evidence." \
            "${log_file:-$TEST_CASES_FILE}" "" "$flow_id"
          defect_id="$LAST_DEFECT_ID"
        fi
        notes="A passing skeleton target is not promoted to full-flow PASS."
      fi
    fi

    record_case \
      "$flow_id" "" "flow" "$title completes with all specified assertions" \
      "$actual" "$result" "$([[ "$result" == "FAIL" ]] && printf 'P1' || true)" \
      "$defect_id" "$screenshot" "" "$log_file" "$notes"
  done
}

run_monkey() {
  if [[ "$MONKEY_EVENTS" == "0" ]]; then
    return 0
  fi
  local install_log="$LOG_DIR/monkey-install.log"
  local monkey_log="$LOG_DIR/monkey-${MONKEY_EVENTS}.log"
  local status

  adb_device uninstall "$QA_PACKAGE" >>"$install_log" 2>&1 || true
  if ! run_logged "$install_log" adb_device install "$QA_APK"; then
    record_defect \
      "P1" "monkey" "QA APK could not be installed for Monkey" \
      "Install the same SHA-recorded QA APK." "$install_log"
    return 0
  fi
  launch_apk "$QA_APK" "$QA_PACKAGE" "$LOG_DIR/monkey-launch.log" || true
  start_screen_recording "monkey-${MONKEY_EVENTS}-${AVD_ID}"

  set +e
  timeout --foreground --signal=TERM --kill-after=30s 15m \
    adb -s "$DEVICE_ID" shell monkey \
      -p "$QA_PACKAGE" \
      -s 240815 \
      --throttle 50 \
      --pct-syskeys 0 \
      --pct-appswitch 0 \
      "$MONKEY_EVENTS" \
      2>&1 | tee "$monkey_log"
  status=${PIPESTATUS[0]}
  set -e
  stop_screen_recording
  capture_snapshot "monkey-after-${MONKEY_EVENTS}-${AVD_ID}"

  {
    printf 'post_monkey_meminfo_begin\n'
    adb_device shell dumpsys meminfo "$QA_PACKAGE" || true
    printf 'post_monkey_meminfo_end\n'
    printf 'post_monkey_cpuinfo_begin\n'
    adb_device shell dumpsys cpuinfo || true
    printf 'post_monkey_cpuinfo_end\n'
    printf 'post_monkey_top_begin\n'
    adb_device shell top -b -n 1 -o PID,CPU,RES,NAME 2>/dev/null || \
      adb_device shell top -n 1 2>/dev/null || true
    printf 'post_monkey_top_end\n'
  } >>"$PERFORMANCE_FILE" 2>&1

  if (( status == 0 )) && adb_device shell pidof "$QA_PACKAGE" >/dev/null 2>&1; then
    record_case \
      "M24-MONKEY-${MONKEY_EVENTS}" "" "stability" \
      "$MONKEY_EVENTS deterministic package-scoped events without crash/ANR" \
      "Monkey exit 0 and process alive" "PASS" "" "" \
      "$SCREENSHOT_DIR/monkey-after-${MONKEY_EVENTS}-${AVD_ID}.png" \
      "$VIDEO_DIR/monkey-${MONKEY_EVENTS}-${AVD_ID}.mp4" "$monkey_log" \
      "Monkey supplements, but does not replace, business flows."
  else
    record_defect \
      "P1" "stability" "Monkey failed or terminated the QA process" \
      "Run the deterministic package-scoped Monkey command." "$monkey_log"
    record_case \
      "M24-MONKEY-${MONKEY_EVENTS}" "" "stability" \
      "$MONKEY_EVENTS deterministic package-scoped events without crash/ANR" \
      "Monkey exit $status or process absent" "FAIL" "P1" \
      "$LAST_DEFECT_ID" \
      "$SCREENSHOT_DIR/monkey-after-${MONKEY_EVENTS}-${AVD_ID}.png" \
      "$VIDEO_DIR/monkey-${MONKEY_EVENTS}-${AVD_ID}.mp4" "$monkey_log" ""
  fi
}

run_offline_soak() {
  [[ "$QA_SCOPE_VALUE" == "full" ]] || return 0
  if [[ ! "$OFFLINE_SOAK_SECONDS" =~ ^[0-9]+$ || \
        "$OFFLINE_SOAK_SECONDS" -lt 1800 ]]; then
    record_defect \
      "P0" "stability" \
      "Full acceptance requires at least 1800 seconds of offline operation" \
      "Set QA_OFFLINE_SOAK_SECONDS to 1800 or more." "$ENVIRONMENT_FILE"
    return 0
  fi

  local soak_log="$LOG_DIR/offline-soak-${OFFLINE_SOAK_SECONDS}s.log"
  local start_time now elapsed iteration status
  local soak_failed=0
  : >"$soak_log"
  if [[ -z "$QA_PACKAGE" || -z "$QA_APK" ]]; then
    record_defect \
      "P1" "stability" "QA APK is unavailable for the offline soak" \
      "Build and install the mock QA APK before the soak." "$soak_log"
    return 0
  fi
  if ! adb_device shell pidof "$QA_PACKAGE" >/dev/null 2>&1; then
    launch_apk "$QA_APK" "$QA_PACKAGE" "$LOG_DIR/offline-soak-launch.log" || true
  fi

  capture_snapshot "offline-soak-start-${AVD_ID}"
  start_screen_recording "offline-soak-start-${AVD_ID}"
  start_time="$(date +%s)"
  iteration=0
  while :; do
    now="$(date +%s)"
    elapsed=$((now - start_time))
    (( elapsed >= OFFLINE_SOAK_SECONDS )) && break
    ((iteration += 1))
    printf 'iteration=%s elapsed=%s timestamp=%s\n' \
      "$iteration" "$elapsed" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" >>"$soak_log"

    set +e
    timeout --foreground --signal=TERM --kill-after=5s 30s \
      adb -s "$DEVICE_ID" shell monkey \
        -p "$QA_PACKAGE" -s "$((240815 + iteration))" --throttle 100 \
        --pct-syskeys 0 --pct-appswitch 0 10 >>"$soak_log" 2>&1
    status=$?
    set -e
    if (( status != 0 )); then
      printf 'monkey_batch_exit=%s\n' "$status" >>"$soak_log"
      soak_failed=1
    fi
    if ! adb_device shell pidof "$QA_PACKAGE" >>"$soak_log" 2>&1; then
      printf 'qa_process_missing=true\n' >>"$soak_log"
      soak_failed=1
      break
    fi
    if [[ "$(adb_device shell settings get global airplane_mode_on | tr -d '\r')" != "1" ]]; then
      printf 'airplane_mode_lost=true\n' >>"$soak_log"
      soak_failed=1
      break
    fi
    {
      printf 'meminfo_begin\n'
      adb_device shell dumpsys meminfo "$QA_PACKAGE" || true
      printf 'meminfo_end\n'
    } >>"$soak_log" 2>&1
    sleep 50
  done
  stop_screen_recording
  capture_snapshot "offline-soak-end-${AVD_ID}"
  elapsed=$(($(date +%s) - start_time))
  printf 'elapsed_total=%s\n' "$elapsed" >>"$soak_log"

  if (( soak_failed == 0 && elapsed >= OFFLINE_SOAK_SECONDS )); then
    record_case \
      "M24-OFFLINE-SOAK" "" "stability" \
      "At least ${OFFLINE_SOAK_SECONDS}s offline operation without process loss" \
      "elapsed=${elapsed}s; process stayed alive; airplane mode stayed enabled" \
      "PASS" "" "" "$SCREENSHOT_DIR/offline-soak-end-${AVD_ID}.png" \
      "$VIDEO_DIR/offline-soak-start-${AVD_ID}.mp4" "$soak_log" \
      "Deterministic package-scoped interactions and periodic meminfo were retained."
  else
    record_defect \
      "P1" "stability" "Offline soak failed before its acceptance duration" \
      "Repeat deterministic offline interaction for at least ${OFFLINE_SOAK_SECONDS}s." \
      "$soak_log"
    record_case \
      "M24-OFFLINE-SOAK" "" "stability" \
      "At least ${OFFLINE_SOAK_SECONDS}s offline operation without process loss" \
      "elapsed=${elapsed}s soak_failed=$soak_failed" "FAIL" "P1" \
      "$LAST_DEFECT_ID" "$SCREENSHOT_DIR/offline-soak-end-${AVD_ID}.png" \
      "$VIDEO_DIR/offline-soak-start-${AVD_ID}.mp4" "$soak_log" ""
  fi
}

extract_viewport_from_screenshot() {
  local filename="$1"
  if [[ "$filename" =~ -([0-9]+x[0-9]+)-(1\.0x|1\.3x)\.png$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  fi
}

coverage_doc_column() {
  local page_id="$1"
  local column="$2"
  [[ -f docs/qa/m2.4-page-coverage.md ]] || return 0
  awk -F'|' -v wanted="$page_id" -v column="$column" '
    {
      id = $2
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
      if (id == wanted) {
        value = $column
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        print value
        exit
      }
    }
  ' docs/qa/m2.4-page-coverage.md
}

generate_page_coverage() {
  local -a page_ids=()
  mapfile -t page_ids < <(
    grep -oE "id: '[A-Z]{2}-[0-9]{3}'" lib/app/page_manifest.dart | \
      cut -d"'" -f2
  )
  local page_id page_name implementation widget_class source_path user_entry
  local one_file one_three_file viewport_one viewport_one_three
  local avd_a_open avd_b_open render_result font_scale_result
  local viewport_360_status viewport_390_status
  local screenshot_evidence page_result defect_id notes state_result role_result
  local interaction_line interaction_count button_status keyboard_status scroll_status
  local page_log="$LOG_DIR/m2_4_page_coverage_test.log"
  local coverage_gap_defect=""
  local -a one_matches=()
  local -a one_three_matches=()

  interaction_count="$(
    {
      grep -h -oE 'QA_PAGE_INTERACTION_PASS page=[A-Z]{2}-[0-9]{3}' \
        "$LOG_DIR"/m2_4_page_coverage_test-scale-1.0-shard-*.log \
        2>/dev/null || true
    } | sort -u | wc -l | tr -d ' '
  )"
  if [[ "$QA_SCOPE_VALUE" == "full" && "$INTEGRATION_SUITE_STARTED" == "1" && \
        "$interaction_count" != "69" ]]; then
    record_defect \
      "P1" "page-coverage" \
      "The Android catalog pass did not emit all 69 per-page interaction markers" \
      "Run every 1.0x shard and require real button taps, enabled field entry, and top/middle/bottom scroll probes." \
      "$PAGE_COVERAGE_FILE"
    coverage_gap_defect="$LAST_DEFECT_ID"
  fi

  for page_id in "${page_ids[@]}"; do
    page_name="$(coverage_doc_column "$page_id" 3)"
    implementation="$(coverage_doc_column "$page_id" 4)"
    user_entry="$(coverage_doc_column "$page_id" 5)"
    if [[ "$implementation" == *" — "* ]]; then
      widget_class="${implementation%% — *}"
      source_path="${implementation##* — }"
    else
      widget_class="DECLARED_IN_QA_CATALOG"
      source_path="lib/debug/qa_console/qa_page_catalog.dart"
    fi
    [[ -n "$page_name" ]] || page_name="$page_id"
    [[ -n "$user_entry" ]] || user_entry="See QaPageEntry.userEntry"

    one_matches=()
    one_three_matches=()
    mapfile -t one_matches < <(
      find "$SCREENSHOT_DIR" -maxdepth 1 -type f \
        -name "${page_id}-normal-${AVD_ID}-*-1.0x.png" -print
    )
    mapfile -t one_three_matches < <(
      find "$SCREENSHOT_DIR" -maxdepth 1 -type f \
        -name "${page_id}-normal-${AVD_ID}-*-1.3x.png" -print
    )
    one_file="${one_matches[0]:-}"
    one_three_file="${one_three_matches[0]:-}"
    viewport_one="$(extract_viewport_from_screenshot "$one_file")"
    viewport_one_three="$(extract_viewport_from_screenshot "$one_three_file")"
    screenshot_evidence="${one_file:-MISSING};${one_three_file:-MISSING}"

    if [[ -n "$one_file" && -n "$one_three_file" && \
          "$viewport_one" == "$EXPECTED_VIEWPORT" && \
          "$viewport_one_three" == "$EXPECTED_VIEWPORT" ]]; then
      render_result="PASS"
      font_scale_result="PASS"
    else
      render_result="FAIL"
      font_scale_result="FAIL"
    fi

    interaction_line="$(
      grep -h -m1 "QA_PAGE_INTERACTION_PASS page=${page_id} " \
        "$LOG_DIR"/m2_4_page_coverage_test-scale-1.0-shard-*.log \
        2>/dev/null || true
    )"
    if [[ -n "$interaction_line" ]]; then
      button_status="PASS"
      if [[ "$interaction_line" =~ keyboard=([0-9]+) ]]; then
        if (( BASH_REMATCH[1] > 0 )); then
          keyboard_status="PASS_WIDGET_INPUT"
        else
          keyboard_status="NOT_APPLICABLE"
        fi
      else
        keyboard_status="FAIL"
      fi
      if [[ "$interaction_line" == *"scroll=PASS"* ]]; then
        scroll_status="PASS"
      else
        scroll_status="NOT_APPLICABLE"
      fi
    else
      button_status="FAIL"
      keyboard_status="FAIL"
      scroll_status="FAIL"
    fi

    if [[ "$AVD_ID" == "AVD-A" ]]; then
      avd_a_open="$render_result"
      avd_b_open="PENDING_SEPARATE_ARTIFACT"
      viewport_360_status="$([[ "$QUALITY_RESULT" == "success" ]] && \
        printf 'PASS_QUALITY_JOB' || printf 'FAIL_OR_NOT_RUN_QUALITY_JOB')"
      viewport_390_status="$render_result"
      if [[ "$INTEGRATION_SUITE_STARTED" == "1" && \
            "$render_result" == "PASS" && "$button_status" == "PASS" ]]; then
        page_result="PASS"
        defect_id=""
        notes="The real catalog-mapped widget opened at both scales; enabled visible buttons were tapped at top/middle/bottom probes. Text input and scrolling are recorded as PASS only where applicable."
        state_result="$render_result"
        role_result="$render_result"
      elif [[ "$INTEGRATION_SUITE_STARTED" == "1" ]]; then
        page_result="FAIL"
        defect_id="$coverage_gap_defect"
        notes="Rendering or the per-page Android interaction marker is missing; no page PASS is fabricated."
        state_result="$render_result"
        role_result="$render_result"
      else
        page_result="BLOCKED"
        defect_id=""
        notes="The run stopped before the integration suite; page evidence was not fabricated."
        state_result="BLOCKED"
        role_result="BLOCKED"
      fi
    else
      avd_a_open="PENDING_SEPARATE_ARTIFACT"
      avd_b_open="$render_result"
      viewport_360_status="$render_result"
      viewport_390_status="NOT_APPLICABLE_AVD_B"
      if [[ "$INTEGRATION_SUITE_STARTED" == "1" && \
            "$render_result" == "PASS" && "$button_status" == "PASS" ]]; then
        page_result="PASS"
        defect_id=""
        notes="The real catalog-mapped widget opened at both scales; enabled visible buttons were tapped at top/middle/bottom probes. Text input and scrolling are recorded as PASS only where applicable."
        state_result="$render_result"
        role_result="$render_result"
      elif [[ "$INTEGRATION_SUITE_STARTED" == "1" ]]; then
        page_result="FAIL"
        defect_id="$coverage_gap_defect"
        notes="Rendering or the per-page Android interaction marker is missing; no page PASS is fabricated."
        state_result="$render_result"
        role_result="$render_result"
      else
        page_result="BLOCKED"
        defect_id=""
        notes="The run stopped before the integration suite; page evidence was not fabricated."
        state_result="BLOCKED"
        role_result="BLOCKED"
      fi
    fi

    csv_row "$PAGE_COVERAGE_FILE" \
      "$page_id" "$page_name" "$widget_class" "$source_path" "$user_entry" \
      "QA Console > $page_id" "registeredUser" \
      "BACKEND_MODE=mock; device offline; catalog fixture" "normal" "DECLARED" \
      "$avd_a_open" "$avd_b_open" "$button_status" "$viewport_360_status" \
      "$viewport_390_status" "$font_scale_result" "$keyboard_status" "$scroll_status" \
      "$screenshot_evidence" "" "$page_log" "$page_result" "$defect_id" "$notes"

    csv_row "$STATE_MATRIX_FILE" \
      "$page_id" "normal" "true" \
      "BACKEND_MODE=mock; registeredUser; offline emulator" \
      "The real widget renders without crash or overflow" "$state_result" \
      "$screenshot_evidence;$page_log" \
      "Only normal state is automated here; QaPageEntry.requiredStates still requires explicit applicability coverage."
    csv_row "$ROLE_MATRIX_FILE" \
      "$page_id" "registeredUser" "Open the catalog-mapped real widget" \
      "Live/vendor success and actions outside the selected role" \
      "Role-visible content renders and restricted actions remain honest" \
      "$role_result" "$screenshot_evidence;$page_log" \
      "This render check is not exhaustive role-permission coverage."
  done
}

record_existing_p1_case() {
  local existing_id="$1"
  local page_flow="$2"
  local title="$3"
  shift 3
  local pattern match
  local evidence=""
  local missing=""
  local -a matches=()
  for pattern in "$@"; do
    matches=()
    mapfile -t matches < <(compgen -G "$pattern" || true)
    match="${matches[0]:-}"
    if [[ -z "$match" || ! -s "$match" ]]; then
      missing="${missing:+$missing;}$pattern"
    else
      evidence="${evidence:+$evidence;}$match"
    fi
  done

  if [[ -z "$missing" ]]; then
    csv_row "$P1_REGRESSION_FILE" \
      "$existing_id" "$page_flow" "$title" "$AVD_ID" "PASS" \
      "$evidence" "Required emulator checkpoints were materialized."
    record_case \
      "M24-P1-${existing_id##*-}" "$page_flow" "p1-regression" \
      "$title has direct $AVD_ID evidence" \
      "All required evidence files exist and are non-empty" \
      "PASS" "" "" "${evidence%%;*}" "" "$evidence" \
      "This is one-AVD evidence; closure requires the matching row from the other AVD."
  else
    record_defect \
      "P1" "p1-regression" \
      "$existing_id lacks complete $AVD_ID regression evidence: $title" \
      "Run the dedicated ordinary-entry or authoritative-state Android integration path." \
      "$missing" "$page_flow"
    csv_row "$P1_REGRESSION_FILE" \
      "$existing_id" "$page_flow" "$title" "$AVD_ID" "FAIL" \
      "$evidence" "Missing: $missing"
    record_case \
      "M24-P1-${existing_id##*-}" "$page_flow" "p1-regression" \
      "$title has direct $AVD_ID evidence" \
      "Missing required evidence: $missing" \
      "FAIL" "P1" "$LAST_DEFECT_ID" "${evidence%%;*}" "" "$missing" \
      "A local/widget result is never substituted for missing emulator evidence."
  fi
}

record_existing_p1_inventory() {
  [[ "$QA_SCOPE_VALUE" == "full" && "$INTEGRATION_SUITE_STARTED" == "1" ]] || return 0
  local suffix="${AVD_ID}"

  record_existing_p1_case "M24-EMU-001" "AC-004/FLOW-011" \
    "AC-004 real page is reachable from the ordinary account-security entry" \
    "$SCREENSHOT_DIR/P1-M24-EMU-001-ordinary-AC-004-${suffix}.png"
  record_existing_p1_case "M24-EMU-002" "DS-003/US-003" \
    "Global search opens the real public profile" \
    "$SCREENSHOT_DIR/P1-M24-EMU-002-search-user-public-profile-${suffix}.png"
  record_existing_p1_case "M24-EMU-003" "RM-006/US-003" \
    "Room member action opens the exact public profile" \
    "$SCREENSHOT_DIR/FLOW-005-online-member-20002-profile-${suffix}.png"
  record_existing_p1_case "M24-EMU-004" "RM-006/MS-002" \
    "Room member action opens the exact private chat" \
    "$SCREENSHOT_DIR/P1-M24-EMU-004-room-member-private-chat-${suffix}.png"
  record_existing_p1_case "M24-EMU-005" "RM-006/US-008" \
    "Room member action opens the exact user report" \
    "$SCREENSHOT_DIR/P1-M24-EMU-005-room-member-report-${suffix}.png"
  record_existing_p1_case "M24-EMU-006" "RM-004/US-008" \
    "Room more menu opens the exact room report" \
    "$SCREENSHOT_DIR/P1-M24-EMU-006-room-report-${suffix}.png"
  record_existing_p1_case "M24-EMU-007" "DS/RM/SC" \
    "Visible retired-feature deny-list remains empty across all 69 catalog pages" \
    "$LOG_DIR/m2_4_page_coverage_test.log" \
    "$SCREENSHOT_DIR/AC-001-normal-${suffix}-*-1.0x.png"
  record_existing_p1_case "M24-EMU-008" "QA Console" \
    "QA Console reset completes without a framework assertion" \
    "$SCREENSHOT_DIR/P1-M24-EMU-008-qa-console-reset-${suffix}.png" \
    "$LOG_DIR/m2_4_qa_console_flow_test.log"
  record_existing_p1_case "M24-EMU-009" "US-010/CM-004/006/008/RM-014" \
    "Seeded QA objects and detail actions share authoritative repositories" \
    "$SCREENSHOT_DIR/P1-M24-EMU-009-US-010-authoritative-ticket-${suffix}.png" \
    "$SCREENSHOT_DIR/P1-M24-EMU-009-CM-004-authoritative-recharge-${suffix}.png" \
    "$SCREENSHOT_DIR/P1-M24-EMU-009-CM-006-authoritative-order-${suffix}.png" \
    "$SCREENSHOT_DIR/P1-M24-EMU-009-CM-008-authoritative-refund-${suffix}.png" \
    "$SCREENSHOT_DIR/P1-M24-EMU-009-RM-014-authoritative-pk-${suffix}.png"
  record_existing_p1_case "M24-EMU-010" "RM-004/RM-013/014" \
    "PK repository uses canonical room IDs through the ordinary flow" \
    "$SCREENSHOT_DIR/FLOW-008-room-pk-settlement-${suffix}.png"
  record_existing_p1_case "M24-EMU-011" "RM-014/RM-004" \
    "PK completion returns directly to the active RoomPage" \
    "$SCREENSHOT_DIR/FLOW-008-room-pk-returned-to-room-${suffix}.png"
  record_existing_p1_case "M24-EMU-012" "integration_test" \
    "All Android integration bindings capture without MissingPluginException" \
    "$SCREENSHOT_DIR/FLOW-011-account-compliance-boundaries-${suffix}.png" \
    "$SCREENSHOT_DIR/FLOW-008-room-pk-returned-to-room-${suffix}.png" \
    "$SCREENSHOT_DIR/FLOW-012-08-withdrawal-confirmed-${suffix}.png" \
    "$SCREENSHOT_DIR/FLOW-013-04-permission-recovery-${suffix}.png" \
    "$SCREENSHOT_DIR/FLOW-014-cp-authoritative-state-${suffix}.png" \
    "$SCREENSHOT_DIR/AC-001-normal-${suffix}-*-1.3x.png"
  record_existing_p1_case "M24-EMU-013" "CM-004/005/006" \
    "Created recharge order remains the same authoritative order in detail and reconciliation" \
    "$SCREENSHOT_DIR/FLOW-012-05-order-detail-reconciled-${suffix}.png"
  record_existing_p1_case "M24-EMU-014" "RM-007" \
    "Taking a member off mic refreshes authoritative UI state" \
    "$SCREENSHOT_DIR/FLOW-007-member-taken-off-mic-${suffix}.png"
  record_existing_p1_case "M24-EMU-015" "RM-007" \
    "Mic management at the exact viewport has no 49 px overflow" \
    "$SCREENSHOT_DIR/FLOW-007-seat-4-locked-${suffix}.png" \
    "$SCREENSHOT_DIR/FLOW-007-seat-4-unlocked-${suffix}.png"
  record_existing_p1_case "M24-EMU-016" "RM-008/RM-004" \
    "Saved room announcement is rendered from authoritative state" \
    "$SCREENSHOT_DIR/FLOW-007-announcement-authoritative-${suffix}.png"
  record_existing_p1_case "M24-EMU-017" "SC-004" \
    "Duplicate CP invitation is rejected while accept and reject states persist" \
    "$SCREENSHOT_DIR/FLOW-014-cp-authoritative-state-${suffix}.png"
  record_existing_p1_case "M24-EMU-018" "RM-005" \
    "Ordinary mock room produces authoritative on-mic state" \
    "$SCREENSHOT_DIR/FLOW-005-up-mic-seat-4-${suffix}.png"
}

scan_logs() {
  local findings_file="$ARTIFACT_ROOT/logcat-findings.txt"
  local hard_findings_file="$ARTIFACT_ROOT/logcat-hard-findings.txt"
  local all_pattern='FATAL EXCEPTION|ANR|RenderFlex overflow|A RenderFlex overflowed|setState\(\) called after dispose|Looking up a deactivated widget|Unhandled Exception|Null check operator used on a null value|Bad state|LateInitializationError|PlatformException|MissingPluginException|SocketException|TimeoutException'
  local hard_pattern='FATAL EXCEPTION|ANR in|A RenderFlex overflowed|setState\(\) called after dispose|Looking up a deactivated widget|Unhandled Exception|Null check operator used on a null value|LateInitializationError|MissingPluginException'

  grep -En "$all_pattern" "$LOGCAT_FILE" >"$findings_file" 2>/dev/null || true
  grep -En "$hard_pattern" "$LOGCAT_FILE" 2>/dev/null |
    awk '!/ANR in/ || /ANR in com\\.kong373\\.voice_social_app/' \
      >"$hard_findings_file" || true
  if [[ -s "$hard_findings_file" ]]; then
    record_defect \
      "P1" "logcat" "Crash, ANR, lifecycle, or layout signature found in Logcat" \
      "Search the full threadtime Logcat using the documented hard-failure patterns." \
      "$hard_findings_file"
    record_case \
      "M24-LOGCAT-SCAN" "" "stability" "No hard failure signatures" \
      "Hard signatures found" "FAIL" "P1" "$LAST_DEFECT_ID" "" "" \
      "$hard_findings_file" "Expected vendor-boundary exceptions are retained separately for review."
  else
    record_case \
      "M24-LOGCAT-SCAN" "" "stability" "No hard failure signatures" \
      "No hard signatures found" "PASS" "" "" "" "" \
      "$findings_file" "All broader keyword hits remain available for manual association."
  fi
}

redact_text_artifacts() {
  local text_file
  while IFS= read -r -d '' text_file; do
    sed -E -i \
      -e 's/(Bearer[[:space:]]+)[A-Za-z0-9._~+\/-]+/\1[REDACTED_TOKEN]/g' \
      -e 's/1[3-9][0-9]{9}/[REDACTED_PHONE]/g' \
      -e 's/123456/[REDACTED_CODE]/g' \
      "$text_file" 2>/dev/null || true
  done < <(
    find "$ARTIFACT_ROOT" -type f \
      \( -name '*.txt' -o -name '*.log' -o -name '*.csv' -o -name '*.xml' \) \
      -print0
  )
}

write_summary() {
  local conclusion="ANDROID_EMULATOR_PASS"
  if (( FAIL_COUNT > 0 )); then
    conclusion="ANDROID_EMULATOR_FAIL"
  fi
  {
    printf 'M2.4 Android Emulator QA\n'
    printf 'conclusion=%s\n' "$conclusion"
    printf 'avd=%s\n' "$AVD_ID"
    printf 'api_level=%s\n' "$API_LEVEL"
    printf 'scope=%s\n' "$QA_SCOPE_VALUE"
    printf 'offline=%s\n' "$OFFLINE_STATUS"
    printf 'page_coverage=%s\n' "$PAGE_COVERAGE_STATUS"
    printf 'failures=%s\n' "$FAIL_COUNT"
    printf 'baseline_required=%s\n' "$BASELINE_REQUIRED"
    printf 'real_device=REAL_DEVICE_PENDING\n'
    printf 'ios=IOS_PENDING\n'
    printf 'vendor_status=VENDOR_BLOCKED\n'
    printf 'evidence_root=%s\n' "$ARTIFACT_ROOT"
  } >"$SUMMARY_FILE"
}

finalize() {
  local original_status=$?
  local final_status=$original_status
  trap - EXIT
  set +e

  # Materialize an honest partial verdict before any best-effort ADB evidence
  # collection. If the emulator is kernel-stuck and the outer watchdog later
  # escalates to KILL, the always() upload still has a summary and progress log.
  if (( original_status != 0 && FAIL_COUNT == 0 )); then
    record_defect \
      "P0" "runner" "QA runner exited unexpectedly with status $original_status" \
      "Inspect workflow and runner logs." "$ARTIFACT_ROOT"
  fi
  write_summary
  progress_event runner_finalize "original_status=$original_status phase=start"

  stop_screen_recording
  if [[ -n "$DEVICE_ID" ]]; then
    capture_snapshot "final-${AVD_ID}"
  fi
  stop_logcat
  if [[ -s "$LOGCAT_FILE" ]]; then
    scan_logs
  fi
  if [[ -f lib/app/page_manifest.dart ]]; then
    generate_page_coverage
  fi
  record_existing_p1_inventory
  restore_network_mode

  if [[ -n "$MOCK_DEBUG_APK" && -f "$MOCK_DEBUG_APK" ]]; then
    rm -f -- "$MOCK_DEBUG_APK"
  fi
  if [[ -n "$MOCK_DEBUG_TEMP_DIR" && -d "$MOCK_DEBUG_TEMP_DIR" ]]; then
    rmdir -- "$MOCK_DEBUG_TEMP_DIR" 2>/dev/null || true
  fi

  write_summary
  redact_text_artifacts

  if (( FAIL_COUNT > 0 && final_status == 0 )); then
    final_status=1
  fi
  progress_event runner_finalize \
    "original_status=$original_status final_status=$final_status phase=complete"
  exit "$final_status"
}

trap finalize EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

main() {
  if [[ "$PROJECT_ROOT" != *"/.ci_app" || ! -f pubspec.yaml || \
        ! -d android || ! -d integration_test ]]; then
    record_defect \
      "P0" "environment" "Runner is not inside the isolated Flutter Android host" \
      "Generate .ci_app and run this script as its working directory." "$PROJECT_ROOT"
    exit 64
  fi

  if [[ "$BACKEND_MODE_VALUE" != "mock" || \
        -n "${API_BASE_URL:-}" || \
        -n "${OAUTH_CLIENT_ID:-}" || \
        -n "${OAUTH_CLIENT_SECRET:-}" || \
        -n "${ROOM_REALTIME_ENDPOINT:-}" ]]; then
    record_defect \
      "P0" "security" "Live configuration or endpoint material was supplied to QA" \
      "Run only with QA_BACKEND_MODE=mock and empty live configuration." \
      "$ENVIRONMENT_FILE"
    exit 64
  fi

  if [[ "$AVD_ID" == "AVD-A" && \
        ( "$BASELINE_REQUIRED" != "true" || \
          "$BASELINE_RUN_ID" != "$APPROVED_BASELINE_RUN_ID" || \
          "$BASELINE_ARTIFACT_NAME" != "$APPROVED_BASELINE_ARTIFACT" || \
          "$EXPECTED_BASELINE_SHA256" != "$APPROVED_BASELINE_SHA256" ) ]]; then
    record_defect \
      "P0" "baseline" "AVD-A baseline identity does not match the approved immutable input" \
      "Use run $APPROVED_BASELINE_RUN_ID artifact $APPROVED_BASELINE_ARTIFACT and its approved inner APK SHA." \
      "$APK_SHA_FILE"
    exit 64
  fi
  if [[ "$AVD_ID" == "AVD-B" && "$BASELINE_REQUIRED" != "false" ]]; then
    record_defect \
      "P0" "baseline" "AVD-B must not repeat or substitute the AVD-A baseline round" \
      "Set QA_BASELINE_REQUIRED=false for AVD-B." "$ENVIRONMENT_FILE"
    exit 64
  fi

  if [[ ! -c /dev/kvm || ! -r /dev/kvm || ! -w /dev/kvm ]]; then
    record_defect \
      "P0" "environment" "KVM is unavailable; refusing to pretend software emulation is acceptance" \
      "Use a Linux runner exposing a readable and writable /dev/kvm." "/dev/kvm"
    exit 69
  fi

  configure_android_tool_path
  require_command adb
  require_command dart
  require_command emulator
  require_command flutter
  require_command java
  require_command od
  require_command sha256sum
  require_command timeout
  require_command unzip

  progress_event runner_start "api=$API_LEVEL scope=$QA_SCOPE_VALUE"

  write_environment
  verify_tested_source
  write_build_provenance
  discover_android_tools
  select_device
  configure_exact_viewport
  write_avd_matrix
  start_logcat
  enable_offline_mode
  progress_event phase_start baseline
  run_baseline_black_box
  progress_event phase_start qa_build
  build_qa_apk
  progress_event phase_start qa_smoke
  run_qa_launch_smoke
  progress_event phase_start integration_suite
  run_integration_suite
  # The release gate regenerates Android plugin tooling without dev-only
  # integration_test. Run it only after every flutter drive/page shard so the
  # release registrant cannot contaminate the debug integration environment.
  run_release_qa_gate
  progress_event phase_start flow_inventory
  record_flow_inventory
  progress_event phase_start monkey
  run_monkey
  run_offline_soak
  progress_event runner_complete "failures=$FAIL_COUNT"
}

main "$@"
