#!/usr/bin/env bash
set -euo pipefail

# Safe entry point for first-party development integration. This script is
# deliberately narrower than a general Flutter wrapper: it owns the live /
# development defines and never accepts confidential client or vendor keys.

readonly SCRIPT_NAME="live-development"
readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'EOF'
Usage:
  ./tool/live_development.sh run --target android-emulator [options] [-- flutter-options]
  ./tool/live_development.sh build-apk --target android-emulator [options] [-- flutter-options]

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
  --device <id>     Flutter device id for `run`.
  --dry-run          Validate configuration and print a redacted plan only.
  --help             Show this help.

The wrapper always sets BACKEND_MODE=live, APP_ENV=development, and
ALLOW_INSECURE_HTTP=true for the explicitly local development targets. APK
builds are restricted to android-emulator because an Android APK cannot reach
the Mac through 127.0.0.1.
It rejects OAuth Client Secrets, vendor secrets, and --dart-define-from-file.
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
  [[ "$normalized_name" =~ (^|_)(oauth_client_secret|client_secret|secret|password|private_key|access_key)(_|$) ]]
}

is_token_name() {
  local normalized_name
  normalized_name="$(printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
  [[ "$normalized_name" =~ (^|_)token(_|$) ]]
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

reject_confidential_argument() {
  local argument="$1"
  local normalized_argument
  normalized_argument="$(printf '%s' "$argument" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
  if [[ "$normalized_argument" == --dart-define-from-file* ]]; then
    fail "--dart-define-from-file is not accepted; it could carry confidential credentials"
  fi
  if [[ "$normalized_argument" == *client_secret* ||
    "$normalized_argument" == *secret* ||
    "$normalized_argument" == *private_key* ||
    "$normalized_argument" == *access_key* ||
    "$normalized_argument" == *password* ||
    "$normalized_argument" == *token* ]]; then
    fail "confidential credential arguments are not accepted"
  fi
  if [[ "$normalized_argument" == --dart-define ||
    "$normalized_argument" == --dart-define=* ]]; then
    fail "additional --dart-define arguments are not accepted; runtime defines are owned by this wrapper"
  fi
}

require_value() {
  local name="$1"
  local value="$2"
  [[ -n "$value" ]] || fail "$name is required"
}

validate_public_client_id() {
  local value="$1"
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* && "$value" != *' '* ]] ||
    fail "OAUTH_CLIENT_ID must not contain whitespace"
  [[ "$value" != *'='* ]] || fail "OAUTH_CLIENT_ID must not contain '='"
}

parse_api_url() {
  local value="$1"
  # Development targets intentionally accept only a simple HTTP(S) URL with
  # no userinfo, query, fragment, or hidden credential in the authority.
  if [[ ! "$value" =~ ^(https?)://([^/@?#:]+)(:[0-9]+)?(/[^?#]*)?$ ]]; then
    fail "API_BASE_URL must be an absolute HTTP(S) URL without credentials, query, or fragment"
  fi
  API_SCHEME="${BASH_REMATCH[1]}"
  API_HOST="${BASH_REMATCH[2]}"
  API_PORT="${BASH_REMATCH[3]:-}"
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

check_flutter() {
  FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
  command -v "$FLUTTER_BIN" >/dev/null 2>&1 ||
    fail "Flutter executable was not found; install Flutter 3.44.7 or set FLUTTER_BIN"
}

print_plan() {
  printf 'live-development dry-run\n'
  printf 'command=%s\n' "$COMMAND"
  printf 'target=%s\n' "$TARGET"
  printf 'api_origin=%s\n' "$API_ORIGIN"
  printf 'backend_mode=live\n'
  printf 'app_env=development\n'
  printf 'oauth_client_id_configured=true\n'
  if [[ "$COMMAND" == 'run' ]]; then
    printf 'flutter_action=flutter run --no-pub\n'
  else
    printf 'flutter_action=flutter build apk --debug --no-pub\n'
  fi
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
DRY_RUN=false
EXTRA_ARGS=()

reject_confidential_environment

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
        reject_confidential_argument "$1"
        EXTRA_ARGS+=("$1")
        shift
      done
      ;;
    *)
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
validate_public_client_id "$OAUTH_CLIENT_ID_VALUE"
parse_api_url "$API_BASE_URL_VALUE"
validate_target_url

if [[ "$DRY_RUN" == true ]]; then
  print_plan
  exit 0
fi

check_flutter

DEFINES=(
  "--dart-define=BACKEND_MODE=live"
  "--dart-define=APP_ENV=development"
  "--dart-define=API_BASE_URL=${API_BASE_URL_VALUE}"
  '--dart-define=ALLOW_INSECURE_HTTP=true'
  "--dart-define=OAUTH_CLIENT_ID=${OAUTH_CLIENT_ID_VALUE}"
  "--dart-define=CLIENT_TYPE=${CLIENT_TYPE:-Android}"
  "--dart-define=CLIENT_INNER_VERSION=${CLIENT_INNER_VERSION:-6}"
  "--dart-define=API_TIMEOUT_SECONDS=${API_TIMEOUT_SECONDS:-15}"
  "--dart-define=LIVE_PROBE_PATH=${LIVE_PROBE_PATH:-/}"
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
  # A generic host token may be unrelated to this app, but Flutter does not
  # need it for this --no-pub entry point. Strip it from the child process so
  # it can never become an accidental artifact or plugin credential.
  local_name=''
  while IFS= read -r local_name; do
    if [[ -n "$local_name" ]]; then
      unset "$local_name"
    fi
  done <<< "$SECRET_LIKE_ENV_NAMES"
  if ((${#EXTRA_ARGS[@]} > 0)); then
    "$FLUTTER_BIN" "${FLUTTER_ARGS[@]}" "${DEFINES[@]}" "${EXTRA_ARGS[@]}"
  else
    "$FLUTTER_BIN" "${FLUTTER_ARGS[@]}" "${DEFINES[@]}"
  fi
)
