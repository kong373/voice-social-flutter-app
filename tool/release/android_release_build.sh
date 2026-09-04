#!/usr/bin/env bash
set -euo pipefail

umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly PROJECT_ROOT
readonly VALIDATOR="$SCRIPT_DIR/android_release_validator.sh"
readonly GRADLEW="$PROJECT_ROOT/android/gradlew"
readonly GENERATED_REGISTRANT_RELATIVE="android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java"
readonly GENERATED_REGISTRANT="$PROJECT_ROOT/$GENERATED_REGISTRANT_RELATIVE"

FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
OUTPUT_DIR="$PROJECT_ROOT/build/android-release"
SELF_TEST=0

usage() {
  cat <<'USAGE'
Usage:
  android_release_build.sh [--flutter-bin PATH] [--output-dir PATH]
  android_release_build.sh --self-test

Builds and validates both the signed release APK and AAB. Android release
signing material must be supplied through the Gradle environment contract or
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
  "$VALIDATOR" --self-test >/dev/null
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
"$FLUTTER_BIN" build apk --release --no-pub
"$FLUTTER_BIN" build appbundle --release --no-pub

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
