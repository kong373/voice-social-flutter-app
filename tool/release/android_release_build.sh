#!/usr/bin/env bash
set -euo pipefail

umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly PROJECT_ROOT
readonly VALIDATOR="$SCRIPT_DIR/android_release_validator.sh"
readonly CONFIG_VALIDATOR="$SCRIPT_DIR/android_release_config_validator.py"
readonly GRADLEW="$PROJECT_ROOT/android/gradlew"
readonly GENERATED_REGISTRANT_RELATIVE="android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java"
readonly GENERATED_REGISTRANT="$PROJECT_ROOT/$GENERATED_REGISTRANT_RELATIVE"
readonly PYTHON_BIN="${PYTHON_BIN:-python3}"

FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
OUTPUT_DIR="$PROJECT_ROOT/build/android-release"
CONFIG_FILE=""
SELF_TEST=0

usage() {
  cat <<'USAGE'
Usage:
  android_release_build.sh --config-file ABS_PUBLIC_JSON \
    [--flutter-bin PATH] [--output-dir PATH]
  android_release_build.sh --self-test

Builds and validates both the signed release APK and AAB. Android release
runtime configuration must be supplied as a public JSON file; it is validated
before Gradle or Flutter starts, then passed through one private canonical
snapshot to both builds. Android signing material must be supplied through
the Gradle environment contract or
the ignored android/key.properties file; this script never prints its values.
USAGE
}

fail() {
  printf 'android-release-build=FAIL reason=%s\n' "$1" >&2
  exit 1
}

while (($# > 0)); do
  case "$1" in
    --flutter-bin)
      (($# >= 2)) || fail 'missing_flutter_path'
      FLUTTER_BIN="$2"
      shift 2
      ;;
    --output-dir)
      (($# >= 2)) || fail 'missing_output_path'
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --config-file)
      (($# >= 2)) || fail 'missing_config_file'
      [[ -z "$CONFIG_FILE" ]] || fail 'config_file_supplied_more_than_once'
      [[ -n "$2" ]] || fail 'missing_config_file'
      CONFIG_FILE="$2"
      shift 2
      ;;
    --config-file=*)
      [[ -z "$CONFIG_FILE" ]] || fail 'config_file_supplied_more_than_once'
      CONFIG_FILE="${1#--config-file=}"
      [[ -n "$CONFIG_FILE" ]] || fail 'missing_config_file'
      shift
      ;;
    --self-test)
      SELF_TEST=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail 'unknown_argument'
      ;;
  esac
done

self_test() {
  [[ -x "$VALIDATOR" ]] || fail 'validator_not_executable'
  [[ -f "$CONFIG_VALIDATOR" ]] || fail 'config_validator_missing'
  [[ -x "$PYTHON_BIN" || -n "$(command -v "$PYTHON_BIN" 2>/dev/null || true)" ]] ||
    fail 'python_unavailable'
  "$VALIDATOR" --self-test >/dev/null
  "$PYTHON_BIN" "$CONFIG_VALIDATOR" --self-test >/dev/null
  local gradle_source="$PROJECT_ROOT/android/app/build.gradle.kts"
  [[ -f "$gradle_source" ]] || fail 'android_host_missing'
  grep -Fq 'signingConfig = signingConfigs.getByName("release")' "$gradle_source" ||
    fail 'release_signing_config_missing'
  if grep -Fq 'signingConfigs.getByName("debug")' "$gradle_source"; then
    fail 'debug_release_signing_detected'
  fi

  local probe_dir probe_log probe_code
  probe_dir="$(mktemp -d)"
  probe_log="$probe_dir/gradle.log"
  set +e
  (
    cd "$PROJECT_ROOT/android"
    env \
      -u ANDROID_RELEASE_SIGNING_PROPERTIES_FILE \
      -u ANDROID_RELEASE_STORE_FILE \
      -u ANDROID_RELEASE_STORE_PASSWORD \
      -u ANDROID_RELEASE_KEY_ALIAS \
      -u ANDROID_RELEASE_KEY_PASSWORD \
      ANDROID_RELEASE_SIGNING_PROPERTIES_FILE="$probe_dir/missing.properties" \
      "$GRADLEW" :app:validateReleaseSigning --no-daemon --console=plain --quiet
  ) >"$probe_log" 2>&1
  probe_code=$?
  set -e
  if ((probe_code == 0)) || ! grep -Fq 'required release signing material' "$probe_log"; then
    rm -rf "$probe_dir"
    fail 'missing_signing_material_did_not_fail_closed'
  fi
  rm -rf "$probe_dir"
  printf 'android-release-build=self-test-PASS\n'
}

if ((SELF_TEST == 1)); then
  self_test
  exit 0
fi

# Runtime configuration is a public input, but it is still a release gate:
# only the allowlisted AppEnvironment defines may reach Flutter. Keep this
# before tool checks, generated-source cleanup, Gradle, and either build.
[[ -n "$CONFIG_FILE" ]] || fail 'config_file_required'
[[ -f "$CONFIG_VALIDATOR" ]] || fail 'config_validator_missing'
[[ -x "$PYTHON_BIN" || -n "$(command -v "$PYTHON_BIN" 2>/dev/null || true)" ]] ||
  fail 'python_unavailable'

# The validator reads the public file once and writes a fresh, canonical 0600
# snapshot into a private 0700 directory. Every later build reads that same
# snapshot, so changes to the public path cannot become a build-input TOCTOU.
CONFIG_SNAPSHOT_DIR="$(mktemp -d)" || fail 'snapshot_directory_unavailable'
chmod 700 "$CONFIG_SNAPSHOT_DIR" || fail 'snapshot_directory_not_private'
readonly CONFIG_SNAPSHOT_DIR
readonly CONFIG_SNAPSHOT="$CONFIG_SNAPSHOT_DIR/config.json"
cleanup_config_snapshot() {
  rm -rf -- "$CONFIG_SNAPSHOT_DIR"
}
trap cleanup_config_snapshot EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

"$PYTHON_BIN" "$CONFIG_VALIDATOR" \
  --config-file "$CONFIG_FILE" \
  --snapshot-file "$CONFIG_SNAPSHOT" >/dev/null

[[ -x "$FLUTTER_BIN" || -n "$(command -v "$FLUTTER_BIN" 2>/dev/null || true)" ]] ||
  fail 'flutter_unavailable'
[[ -x "$GRADLEW" ]] || fail 'gradle_wrapper_unavailable'

# A preceding debug or integration-test build can leave a dev-only plugin in
# this generated source file. Flutter's release injection must start without
# that stale source. Delete only the exact path after Git proves that it is a
# generated, ignored file; a tracked or unexpectedly unignored file is never
# removed by this script.
if [[ -e "$GENERATED_REGISTRANT" ]]; then
  git -C "$PROJECT_ROOT" check-ignore --quiet -- "$GENERATED_REGISTRANT_RELATIVE" ||
    fail 'generated_registrant_is_not_ignored'
  rm -f -- "$GENERATED_REGISTRANT"
fi

# Validate signing before Flutter starts either expensive release build. The
# Gradle task reads only the protected signing contract and emits no material.
(
  cd "$PROJECT_ROOT/android"
  "$GRADLEW" :app:validateReleaseSigning --no-daemon --console=plain --quiet
)

mkdir -p "$OUTPUT_DIR"
"$FLUTTER_BIN" build apk --release --no-pub \
  --dart-define-from-file="$CONFIG_SNAPSHOT"
"$FLUTTER_BIN" build appbundle --release --no-pub \
  --dart-define-from-file="$CONFIG_SNAPSHOT"

readonly BUILT_APK="$PROJECT_ROOT/build/app/outputs/flutter-apk/app-release.apk"
readonly BUILT_AAB="$PROJECT_ROOT/build/app/outputs/bundle/release/app-release.aab"
[[ -f "$BUILT_APK" && -s "$BUILT_APK" ]] || fail 'release_apk_missing'
[[ -f "$BUILT_AAB" && -s "$BUILT_AAB" ]] || fail 'release_aab_missing'

cp -- "$BUILT_APK" "$OUTPUT_DIR/app-release.apk"
cp -- "$BUILT_AAB" "$OUTPUT_DIR/app-release.aab"
"$VALIDATOR" --apk "$OUTPUT_DIR/app-release.apk" --aab "$OUTPUT_DIR/app-release.aab"

sha256_file() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
    return 0
  fi
  fail 'sha256_tool_unavailable'
}

printf 'android-release-build=PASS\n'
printf 'apk=%s\n' "$OUTPUT_DIR/app-release.apk"
printf 'aab=%s\n' "$OUTPUT_DIR/app-release.aab"
printf 'apk_sha256=%s\n' "$(sha256_file "$OUTPUT_DIR/app-release.apk")"
printf 'aab_sha256=%s\n' "$(sha256_file "$OUTPUT_DIR/app-release.aab")"
