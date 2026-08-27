#!/usr/bin/env bash
set -euo pipefail

# Safe entry point for first-party development integration. This script is
# deliberately narrower than a general Flutter wrapper: it owns the live /
# development defines and never accepts confidential client or vendor keys.

readonly SCRIPT_NAME="live-development"
readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REQUIRED_FLUTTER_VERSION='3.44.7'
readonly REQUIRED_DART_VERSION='3.12.2'
readonly LIVE_APK_OUTPUT_DIR="${ROOT_DIR}/build/live-development"
readonly LIVE_APK_OUTPUT_PATH="${LIVE_APK_OUTPUT_DIR}/app-debug.apk"
readonly LIVE_APK_SHA256_PATH="${LIVE_APK_OUTPUT_DIR}/app-debug.apk.sha256"
cd "$ROOT_DIR"

usage() {
  cat <<'EOF'
Usage:
  ./tool/live_development.sh run --target android-emulator [options]
  ./tool/live_development.sh build-apk --target android-emulator [options]

Required environment:
  API_BASE_URL       Development gateway URL.
  OAUTH_CLIENT_ID    Public OAuth client identifier only.

Targets:
  android-emulator   Use http://10.0.2.2:<port>/ to reach the Mac host from
                     an Android Emulator or BlueStacks instance.
  host               Use http://127.0.0.1:<port>/ when Flutter runs on this
                     Mac; 127.0.0.1 is not reachable from an Android Emulator.

Options:
  --target <name>    Required target selector; also accepts --target=<name>.
  --device <id>      Required Flutter device id for `run`; rejected by
                     `build-apk`.
  --enable-agora-rtc Explicitly opt into the first-party server-issued Agora
                     audio transport. Without this switch the value is false.
  --enable-alipay-app-pay Explicitly opt into the first-party Android Alipay
                     App Pay bridge. It still requires a server-issued order
                     string; no Alipay credential is accepted by this wrapper.
  --enable-tencent-im Explicitly opt into the first-party server-issued
                      Tencent Cloud IM session. Without this switch the value
                      is false.
  --dry-run          Validate configuration and print a redacted plan only.
  --help             Show this help.

The wrapper always sets BACKEND_MODE=live, APP_ENV=development,
ENABLE_QA_CONSOLE=false, ENABLE_VIDEO_RUNTIME_DEMO=false, and
ALLOW_INSECURE_HTTP=true for the explicitly local development targets. APK
builds are restricted to android-emulator because an Android APK cannot reach
the Mac through 127.0.0.1.
Successful APK builds are retained as build/live-development/app-debug.apk
with a matching app-debug.apk.sha256 sidecar before the isolated host is
removed.
It rejects OAuth Client Secrets, vendor secrets, user Dart-define aliases, and
--dart-define-from-file. API_BASE_URL is an origin with an optional root `/`;
the client metadata, ENABLE_AGORA_RTC, ENABLE_ALIPAY_APP_PAY, and
ENABLE_TENCENT_IM defines are fixed by this wrapper.
Only non-defining diagnostic flags (--verbose, --quiet, --wrap, --no-wrap,
--color, --no-color, --suppress-analytics, --disable-analytics) may be passed
after `--`; runtime defines, device selection, and project arguments belong to
this wrapper and cannot be overridden.
Use a protected shell environment for API_BASE_URL and OAUTH_CLIENT_ID; never
commit them to source control.
EOF
}

fail() {
  printf '%s: %s\n' "$SCRIPT_NAME" "$1" >&2
  exit 2
}

is_hard_confidential_name() {
  local normalized_name
  normalized_name="$(printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
  [[ "$normalized_name" =~ (^|_)(oauth_client_secret|client_secret|secret|password|private_key|access_key|api_key|apikey|credential|credentials|pat)(_|$) ||
    "$normalized_name" =~ (^|_)(auth|bearer)$ ]]
}

is_token_name() {
  local normalized_name
  normalized_name="$(printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
  [[ "$normalized_name" =~ (^|_)token(_|$) ]]
}

is_runtime_define_environment_name() {
  local normalized_name
  normalized_name="$(printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
  [[ "$normalized_name" == 'enable_agora_rtc' ||
    "$normalized_name" == 'enable_alipay_app_pay' ||
    "$normalized_name" == 'agora_rtc' ||
    "$normalized_name" == 'agora_enable_rtc' ||
    "$normalized_name" == 'enable_tencent_im' ||
    "$normalized_name" == 'tencent_im' ||
    "$normalized_name" == 'tencent_enable_im' ||
    "$normalized_name" == 'dart_define' ||
    "$normalized_name" == 'dart_defines' ||
    "$normalized_name" == 'dart_define_from_file' ||
    "$normalized_name" == 'dart_defines_from_file' ||
    "$normalized_name" == 'flutter_dart_define' ||
    "$normalized_name" == 'flutter_dart_defines' ||
    "$normalized_name" == 'flutter_dart_define_from_file' ||
    "$normalized_name" == 'flutter_dart_defines_from_file' ||
    "$normalized_name" == 'flutter_tool_args' ||
    "$normalized_name" == 'gradle_opts' ||
    "$normalized_name" == 'org_gradle_project_'* ]]
}

reject_confidential_environment() {
  local name
  SECRET_LIKE_ENV_NAMES=''
  while IFS='=' read -r name _; do
    if is_hard_confidential_name "$name"; then
      fail "confidential credential environment variables are not accepted"
    fi
    if is_token_name "$name"; then
      SECRET_LIKE_ENV_NAMES+="${name}"$'\n'
    fi
  done < <(env)
}

reject_runtime_define_environment() {
  local name
  local normalized_name
  while IFS='=' read -r name _; do
    if is_runtime_define_environment_name "$name"; then
      normalized_name="$(printf '%s' "$name" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
      if [[ "$normalized_name" == 'enable_agora_rtc' ||
        "$normalized_name" == 'agora_rtc' ||
        "$normalized_name" == 'agora_enable_rtc' ]]; then
        fail 'ENABLE_AGORA_RTC is controlled only by --enable-agora-rtc'
      fi
      if [[ "$normalized_name" == 'enable_alipay_app_pay' ]]; then
        fail 'ENABLE_ALIPAY_APP_PAY is controlled only by --enable-alipay-app-pay'
      fi
      if [[ "$normalized_name" == 'enable_tencent_im' ||
        "$normalized_name" == 'tencent_im' ||
        "$normalized_name" == 'tencent_enable_im' ]]; then
        fail 'ENABLE_TENCENT_IM is controlled only by --enable-tencent-im'
      fi
      fail 'runtime defines are owned by this wrapper and cannot come from the environment'
    fi
  done < <(env)
}

build_clean_environment() {
  CLEAN_ENV=(env -i)
  local environment_name
  for environment_name in \
    PATH HOME USER LOGNAME TMPDIR SHELL JAVA_HOME \
    ANDROID_HOME ANDROID_SDK_ROOT ANDROID_SDK_HOME ANDROID_USER_HOME \
    ANDROID_AVD_HOME ANDROID_EMULATOR_HOME ANDROID_NDK_HOME ANDROID_NDK_ROOT \
    PUB_CACHE GRADLE_USER_HOME KOTLIN_HOME TERM COLORTERM \
    DEVELOPER_DIR SDKROOT MACOSX_DEPLOYMENT_TARGET IPHONEOS_DEPLOYMENT_TARGET; do
    if [[ -n "${!environment_name+x}" ]]; then
      CLEAN_ENV+=("${environment_name}=${!environment_name}")
    fi
  done
  while IFS='=' read -r environment_name _; do
    if [[ "$environment_name" == LC_* && -n "${!environment_name+x}" ]]; then
      CLEAN_ENV+=("${environment_name}=${!environment_name}")
    fi
  done < <(env)
}

reject_confidential_argument() {
  local argument="$1"
  local normalized_argument
  normalized_argument="$(printf '%s' "$argument" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
  if [[ "$argument" == *$'\n'* || "$argument" == *$'\r'* ]]; then
    fail "confidential credential arguments are not accepted"
  fi
  if [[ "$normalized_argument" == --dart-define-from-file* ]]; then
    fail "--dart-define-from-file is not accepted; it could carry confidential credentials"
  fi
  if [[ "$argument" == '-D' || "$argument" == -D* ||
    "$argument" == '-P' || "$argument" == -P* ||
    "$normalized_argument" == --dartdefines* ||
    "$normalized_argument" == --dart-defines* ||
    "$normalized_argument" == --dart_defines* ||
    "$normalized_argument" == --android-project-arg ||
    "$normalized_argument" == --android-project-arg=* ]]; then
    fail "additional runtime defines are not accepted; runtime defines are owned by this wrapper"
  fi
  if [[ "$normalized_argument" == *client_secret* ||
    "$normalized_argument" == *secret* ||
    "$normalized_argument" == *private_key* ||
    "$normalized_argument" == *access_key* ||
    "$normalized_argument" == *password* ||
    "$normalized_argument" == *token* ]]; then
    fail "confidential credential arguments are not accepted"
  fi
  if [[ "$normalized_argument" =~ (^|[-_])(api[-_]?key|credentials?|pat|auth|bearer)([-_=]|$) ]]; then
    fail "confidential credential arguments are not accepted"
  fi
  if [[ "$normalized_argument" == --dart-define ||
    "$normalized_argument" == --dart-define=* ]]; then
    fail "additional --dart-define arguments are not accepted; runtime defines are owned by this wrapper"
  fi
}

validate_flutter_argument() {
  local argument="$1"
  reject_confidential_argument "$argument"
  case "$argument" in
    --verbose|-v|--quiet|--wrap|--no-wrap|--color|--no-color|--suppress-analytics|--disable-analytics)
      ;;
    *)
      fail "additional Flutter arguments are restricted to non-defining diagnostic flags"
      ;;
  esac
}

require_value() {
  local name="$1"
  local value="$2"
  [[ -n "$value" ]] || fail "$name is required"
}

validate_public_client_id() {
  local value="$1"
  [[ "$value" != *[[:space:]]* ]] ||
    fail "OAUTH_CLIENT_ID must not contain whitespace"
  [[ "$value" != *'='* ]] || fail "OAUTH_CLIENT_ID must not contain '='"
}

parse_api_url() {
  local value="$1"
  [[ "$value" != *[[:space:]]* ]] ||
    fail 'API_BASE_URL must not contain whitespace'
  # Development targets intentionally accept only a simple HTTP(S) origin with
  # no userinfo, query, fragment, path, or hidden credential in the authority.
  if [[ ! "$value" =~ ^(https?)://([^/@?#:]+)(:[0-9]+)?/?$ ]]; then
    fail "API_BASE_URL must be an absolute HTTP(S) origin without credentials, query, fragment, or path"
  fi
  API_SCHEME="${BASH_REMATCH[1]}"
  API_HOST="${BASH_REMATCH[2]}"
  API_PORT="${BASH_REMATCH[3]:-}"
  if [[ -n "$API_PORT" ]]; then
    local port_number="${API_PORT#:}"
    if ((10#$port_number < 1 || 10#$port_number > 65535)); then
      fail 'API_BASE_URL port must be between 1 and 65535'
    fi
  fi
  API_ORIGIN="${API_SCHEME}://${API_HOST}${API_PORT}"
}

validate_target_url() {
  case "$TARGET" in
    android-emulator)
      [[ "$API_HOST" == '10.0.2.2' ]] ||
        fail "android-emulator target requires API_BASE_URL host 10.0.2.2 (127.0.0.1 is the Mac host only)"
      ;;
    host)
      [[ "$API_HOST" == '127.0.0.1' ]] ||
        fail "host target requires API_BASE_URL host 127.0.0.1 (10.0.2.2 is the Android Emulator alias)"
      ;;
    *)
      fail "target must be android-emulator or host"
      ;;
  esac
  [[ "$API_SCHEME" == 'http' || "$API_SCHEME" == 'https' ]] ||
    fail "API_BASE_URL must use HTTP or HTTPS"
}

is_android_emulator_selector() {
  local selector="$1"
  [[ "$selector" =~ ^emulator-[0-9]+$ ||
    "$selector" =~ ^(127\.0\.0\.1|localhost):[0-9]+$ ]]
}

validate_target_device() {
  if [[ "$COMMAND" == 'build-apk' && -n "$DEVICE_ID" ]]; then
    fail '--device is only valid for run'
  fi
  if [[ "$COMMAND" != 'run' ]]; then
    return 0
  fi
  if [[ -z "$DEVICE_ID" ]]; then
    fail "$TARGET target requires --device"
  fi
  if [[ "$TARGET" == 'android-emulator' ]]; then
    is_android_emulator_selector "$DEVICE_ID" ||
      fail 'android-emulator target requires an Android emulator device selector'
  elif is_android_emulator_selector "$DEVICE_ID"; then
    fail 'host target cannot use an Android emulator device selector'
  fi
}

check_flutter() {
  FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
  command -v "$FLUTTER_BIN" >/dev/null 2>&1 ||
    fail "Flutter executable was not found; install Flutter 3.44.7 or set FLUTTER_BIN"

  local version_json
  version_json="$("${CLEAN_ENV[@]}" "$FLUTTER_BIN" --version --machine)" ||
    fail "unable to verify the Flutter SDK version"

  local compact_version
  compact_version="$(printf '%s' "$version_json" | LC_ALL=C tr -d '[:space:]')"
  [[ "$compact_version" == *"\"frameworkVersion\":\"${REQUIRED_FLUTTER_VERSION}\""* ]] ||
    fail "Flutter ${REQUIRED_FLUTTER_VERSION} is required"
  [[ "$compact_version" == *"\"dartSdkVersion\":\"${REQUIRED_DART_VERSION}\""* ]] ||
    fail "Dart ${REQUIRED_DART_VERSION} is required"
}

print_plan() {
  printf 'live-development dry-run\n'
  printf 'command=%s\n' "$COMMAND"
  printf 'target=%s\n' "$TARGET"
  printf 'api_origin=%s\n' "$API_ORIGIN"
  printf 'backend_mode=live\n'
  printf 'app_env=development\n'
  printf 'qa_console=false\n'
  printf 'video_runtime_demo=false\n'
  printf 'enable_agora_rtc=%s\n' "$ENABLE_AGORA_RTC"
  printf 'enable_alipay_app_pay=%s\n' "$ENABLE_ALIPAY_APP_PAY"
  printf 'enable_tencent_im=%s\n' "$ENABLE_TENCENT_IM"
  printf 'oauth_client_id_configured=true\n'
  if [[ "$COMMAND" == 'run' ]]; then
    printf 'flutter_action=flutter run --no-pub\n'
  else
    printf 'flutter_action=flutter build apk --debug --no-pub\n'
  fi
}

ANDROID_HOST_DIR=''
APK_COPY_TEMP=''
APK_HASH_TEMP=''
APK_PUBLISH_IN_PROGRESS=false

cleanup_android_host() {
  if [[ -n "${ANDROID_HOST_DIR:-}" && -d "$ANDROID_HOST_DIR" ]]; then
    rm -rf "$ANDROID_HOST_DIR"
  fi
}

cleanup_live_temporary_files() {
  if [[ -n "${APK_COPY_TEMP:-}" && ( -e "$APK_COPY_TEMP" || -L "$APK_COPY_TEMP" ) ]]; then
    rm -f "$APK_COPY_TEMP"
  fi
  if [[ -n "${APK_HASH_TEMP:-}" && ( -e "$APK_HASH_TEMP" || -L "$APK_HASH_TEMP" ) ]]; then
    rm -f "$APK_HASH_TEMP"
  fi
  if [[ "${APK_PUBLISH_IN_PROGRESS:-false}" == true ]]; then
    if [[ -f "$LIVE_APK_OUTPUT_PATH" || -L "$LIVE_APK_OUTPUT_PATH" ]]; then
      rm -f "$LIVE_APK_OUTPUT_PATH"
    fi
    if [[ -f "$LIVE_APK_SHA256_PATH" || -L "$LIVE_APK_SHA256_PATH" ]]; then
      rm -f "$LIVE_APK_SHA256_PATH"
    fi
  fi
}

cleanup_live_runtime() {
  cleanup_live_temporary_files
  cleanup_android_host
}

ensure_real_directory() {
  local path="$1"
  local label="$2"
  if [[ -e "$path" || -L "$path" ]]; then
    [[ ! -L "$path" && -d "$path" ]] ||
      fail "$label must be a real directory and not a symbolic link"
    return 0
  fi
  mkdir "$path" || fail "unable to create $label"
  [[ ! -L "$path" && -d "$path" ]] ||
    fail "$label must be a real directory and not a symbolic link"
}

validate_live_apk_output_targets() {
  local output_path
  for output_path in "$LIVE_APK_OUTPUT_PATH" "$LIVE_APK_SHA256_PATH"; do
    [[ ! -L "$output_path" ]] ||
      fail 'live APK output files must not be symbolic links'
    [[ ! -e "$output_path" || -f "$output_path" ]] ||
      fail 'live APK output files must be regular files'
  done
}

prepare_live_apk_output_directory() {
  command -v shasum >/dev/null 2>&1 ||
    fail 'shasum is required to retain the live APK checksum'
  ensure_real_directory "$ROOT_DIR/build" 'live APK build parent'
  ensure_real_directory "$LIVE_APK_OUTPUT_DIR" 'live APK output directory'
  validate_live_apk_output_targets
}

clear_live_apk_output() {
  validate_live_apk_output_targets
  rm -f "$LIVE_APK_OUTPUT_PATH" "$LIVE_APK_SHA256_PATH" ||
    fail 'unable to clear the previous live APK output'
}

publish_live_apk() {
  local source_apk="${ANDROID_HOST_DIR}/build/app/outputs/flutter-apk/app-debug.apk"
  [[ -f "$source_apk" && ! -L "$source_apk" && -s "$source_apk" ]] ||
    fail 'expected Flutter APK was not produced as a non-empty regular file'

  prepare_live_apk_output_directory
  APK_COPY_TEMP="$(mktemp "${LIVE_APK_OUTPUT_DIR}/.app-debug.apk.XXXXXX")" ||
    fail 'unable to create the temporary live APK output'
  APK_HASH_TEMP="$(mktemp "${LIVE_APK_OUTPUT_DIR}/.app-debug.apk.sha256.XXXXXX")" ||
    fail 'unable to create the temporary live APK checksum output'

  cp "$source_apk" "$APK_COPY_TEMP" || fail 'unable to copy the live APK output'
  chmod 600 "$APK_COPY_TEMP" || fail 'unable to secure the live APK output'

  local checksum_line
  local checksum
  checksum_line="$(shasum -a 256 "$APK_COPY_TEMP")" ||
    fail 'unable to compute the live APK SHA-256'
  checksum="${checksum_line%% *}"
  [[ "$checksum" =~ ^[0-9a-f]{64}$ ]] ||
    fail 'live APK SHA-256 output was invalid'
  printf '%s  app-debug.apk\n' "$checksum" >"$APK_HASH_TEMP" ||
    fail 'unable to write the live APK SHA-256 sidecar'
  chmod 600 "$APK_HASH_TEMP" ||
    fail 'unable to secure the live APK SHA-256 sidecar'

  # Revalidate immediately before replacing the two fixed output files. The
  # temporary names are created inside the validated directory, so neither the
  # APK bytes nor their checksum are copied through a user-controlled path.
  validate_live_apk_output_targets
  APK_PUBLISH_IN_PROGRESS=true
  mv -f "$APK_COPY_TEMP" "$LIVE_APK_OUTPUT_PATH" ||
    fail 'unable to retain the live APK output'
  APK_COPY_TEMP=''
  if ! mv -f "$APK_HASH_TEMP" "$LIVE_APK_SHA256_PATH"; then
    rm -f "$LIVE_APK_OUTPUT_PATH"
    fail 'unable to retain the live APK SHA-256 sidecar'
  fi
  APK_HASH_TEMP=''
  APK_PUBLISH_IN_PROGRESS=false

  printf 'live_apk_path=%s\n' "$LIVE_APK_OUTPUT_PATH"
  printf 'live_apk_sha256=%s\n' "$checksum"
}

prepare_android_host() {
  local temp_root="${TMPDIR:-/tmp}"
  command -v git >/dev/null 2>&1 ||
    fail 'git is required to create the isolated Android host'
  command -v tar >/dev/null 2>&1 ||
    fail 'tar is required to create the isolated Android host'
  command -v python3 >/dev/null 2>&1 ||
    fail 'python3 is required to apply the audio-only Android manifest'
  [[ -d "$temp_root" ]] || mkdir -p "$temp_root" ||
    fail 'unable to create the temporary directory for the Android host'

  ANDROID_HOST_DIR="$(mktemp -d "$temp_root/voice-social-live-android.XXXXXX")" ||
    fail 'unable to create an isolated Android host directory'
  trap cleanup_live_runtime EXIT HUP INT TERM

  # Create the platform host in a temporary directory first.  Overlaying the
  # tracked checkout afterwards preserves this project's pubspec and sources
  # while ensuring the generated android/ directory never appears in the
  # checkout (it is intentionally ignored there).
  "${CLEAN_ENV[@]}" "$FLUTTER_BIN" create \
    --platforms=android \
    --org=com.kong373 \
    --project-name=voice_social_app \
    --no-pub \
    "$ANDROID_HOST_DIR"
  git -C "$ROOT_DIR" archive --format=tar HEAD |
    tar -x -C "$ANDROID_HOST_DIR"
  python3 "$ROOT_DIR/tool/prepare_android_audio_manifest.py" "$ANDROID_HOST_DIR"
  (
    cd "$ANDROID_HOST_DIR"
    "${CLEAN_ENV[@]}" "$FLUTTER_BIN" pub get --enforce-lockfile
  )
}

require_clean_checkout_for_android() {
  local status
  status="$(git -C "$ROOT_DIR" status --porcelain --untracked-files=normal)" ||
    fail 'unable to verify that the checkout is clean before Android live launch'
  [[ -z "$status" ]] ||
    fail 'Android live launch requires a clean checkout; commit or remove local changes first'
}

COMMAND="${1:-}"
if [[ -z "$COMMAND" || "$COMMAND" == '--help' || "$COMMAND" == '-h' || "$COMMAND" == 'help' ]]; then
  usage
  exit 0
fi
shift

case "$COMMAND" in
  run|build-apk) ;;
  *) fail "unknown command; use run, build-apk, or help" ;;
esac

TARGET="${LIVE_DEVELOPMENT_TARGET:-}"
API_BASE_URL_VALUE="${API_BASE_URL:-}"
OAUTH_CLIENT_ID_VALUE="${OAUTH_CLIENT_ID:-}"
DEVICE_ID=''
ENABLE_AGORA_RTC=false
ENABLE_ALIPAY_APP_PAY=false
ENABLE_TENCENT_IM=false
DRY_RUN=false
EXTRA_ARGS=()

reject_confidential_environment
reject_runtime_define_environment
build_clean_environment

if [[ -n "${BACKEND_MODE:-}" && "${BACKEND_MODE}" != 'live' ]]; then
  fail 'BACKEND_MODE must be live when supplied'
fi
if [[ -n "${APP_ENV:-}" && "${APP_ENV}" != 'development' ]]; then
  fail 'APP_ENV must be development when supplied'
fi

while (($# > 0)); do
  reject_confidential_argument "$1"
  case "$1" in
    --target)
      (($# >= 2)) || fail '--target requires a value'
      TARGET="$2"
      shift 2
      ;;
    --target=*)
      TARGET="${1#*=}"
      shift
      ;;
    --api-base-url)
      (($# >= 2)) || fail '--api-base-url requires a value'
      API_BASE_URL_VALUE="$2"
      shift 2
      ;;
    --api-base-url=*)
      API_BASE_URL_VALUE="${1#*=}"
      shift
      ;;
    --oauth-client-id)
      (($# >= 2)) || fail '--oauth-client-id requires a value'
      reject_confidential_argument "$2"
      OAUTH_CLIENT_ID_VALUE="$2"
      shift 2
      ;;
    --oauth-client-id=*)
      OAUTH_CLIENT_ID_VALUE="${1#*=}"
      shift
      ;;
    --device)
      (($# >= 2)) || fail '--device requires a value'
      DEVICE_ID="$2"
      shift 2
      ;;
    --device=*)
      DEVICE_ID="${1#*=}"
      shift
      ;;
    --enable-agora-rtc)
      ENABLE_AGORA_RTC=true
      shift
      ;;
    --enable-agora-rtc=*)
      fail '--enable-agora-rtc is a flag and does not accept a value'
      ;;
    --enable-alipay-app-pay)
      ENABLE_ALIPAY_APP_PAY=true
      shift
      ;;
    --enable-alipay-app-pay=*)
      fail '--enable-alipay-app-pay is a flag and does not accept a value'
      ;;
    --enable-tencent-im)
      ENABLE_TENCENT_IM=true
      shift
      ;;
    --enable-tencent-im=*)
      fail '--enable-tencent-im is a flag and does not accept a value'
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      while (($# > 0)); do
        validate_flutter_argument "$1"
        EXTRA_ARGS+=("$1")
        shift
      done
      ;;
    *)
      validate_flutter_argument "$1"
      EXTRA_ARGS+=("$1")
      shift
      ;;
  esac
done

require_value 'API_BASE_URL' "$API_BASE_URL_VALUE"
require_value 'OAUTH_CLIENT_ID' "$OAUTH_CLIENT_ID_VALUE"
require_value '--target' "$TARGET"
if [[ "$COMMAND" == 'build-apk' && "$TARGET" != 'android-emulator' ]]; then
  fail 'build-apk only supports android-emulator; host is valid only for run'
fi
reject_confidential_argument "$OAUTH_CLIENT_ID_VALUE"
validate_public_client_id "$OAUTH_CLIENT_ID_VALUE"
parse_api_url "$API_BASE_URL_VALUE"
validate_target_url
validate_target_device

if [[ "$DRY_RUN" == true ]]; then
  print_plan
  exit 0
fi

if [[ "$TARGET" == 'android-emulator' ]]; then
  require_clean_checkout_for_android
fi

check_flutter

if [[ "$COMMAND" == 'build-apk' ]]; then
  prepare_live_apk_output_directory
  clear_live_apk_output
fi

if [[ "$TARGET" == 'android-emulator' ]]; then
  prepare_android_host
fi

DEFINES=(
  "--dart-define=BACKEND_MODE=live"
  "--dart-define=APP_ENV=development"
  '--dart-define=ENABLE_QA_CONSOLE=false'
  '--dart-define=ENABLE_VIDEO_RUNTIME_DEMO=false'
  "--dart-define=ENABLE_AGORA_RTC=${ENABLE_AGORA_RTC}"
  "--dart-define=ENABLE_ALIPAY_APP_PAY=${ENABLE_ALIPAY_APP_PAY}"
  "--dart-define=ENABLE_TENCENT_IM=${ENABLE_TENCENT_IM}"
  "--dart-define=API_BASE_URL=${API_BASE_URL_VALUE}"
  '--dart-define=ALLOW_INSECURE_HTTP=true'
  "--dart-define=OAUTH_CLIENT_ID=${OAUTH_CLIENT_ID_VALUE}"
  '--dart-define=CLIENT_TYPE=Android'
  '--dart-define=CLIENT_INNER_VERSION=6'
  '--dart-define=API_TIMEOUT_SECONDS=15'
  '--dart-define=LIVE_PROBE_PATH=/'
)

if [[ "$COMMAND" == 'run' ]]; then
  FLUTTER_ARGS=(run --no-pub)
  if [[ -n "$DEVICE_ID" ]]; then
    FLUTTER_ARGS+=(-d "$DEVICE_ID")
  fi
else
  FLUTTER_ARGS=(build apk --debug --no-pub)
fi

(
  # The child receives an explicit SDK/runtime allowlist. This strips ordinary
  # host tokens and unknown cloud/profile/config variables without relying on a
  # never-complete credential-name denylist.
  if [[ -n "$ANDROID_HOST_DIR" ]]; then
    cd "$ANDROID_HOST_DIR"
  fi
  if ((${#EXTRA_ARGS[@]} > 0)); then
    "${CLEAN_ENV[@]}" "$FLUTTER_BIN" "${FLUTTER_ARGS[@]}" "${DEFINES[@]}" "${EXTRA_ARGS[@]}"
  else
    "${CLEAN_ENV[@]}" "$FLUTTER_BIN" "${FLUTTER_ARGS[@]}" "${DEFINES[@]}"
  fi
)

if [[ "$COMMAND" == 'build-apk' ]]; then
  publish_live_apk
fi
