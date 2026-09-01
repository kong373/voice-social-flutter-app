#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
readonly PROJECT_ROOT
readonly HELPER_PROJECT_DIR="$PROJECT_ROOT/tool/qa/alipay_androidx_dialog_helper"
readonly GRADLE_WRAPPER="$PROJECT_ROOT/android/gradlew"

SDK_ROOT=''
JAVA_HOME_VALUE=''
OUTPUT_DIR=''
APKANALYZER=''

fail() {
  printf 'ALIPAY_ANDROIDX_HELPER_BUILD: configuration rejected (%s)\n' "$1" >&2
  exit 64
}

usage() {
  cat <<'USAGE'
Usage: build_alipay_androidx_dialog_helper.sh \
  --sdk-root PATH --java-home PATH --output-dir PATH

Builds a fresh standalone helper base APK and AndroidX instrumentation APK.
The helper targets only its own inert application and never connects to a
device, starts an app, or invokes a payment API.
USAGE
}

while (($# > 0)); do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --sdk-root)
      (($# >= 2)) || fail 'SDK root is missing'
      [[ -z "$SDK_ROOT" ]] || fail 'SDK root supplied more than once'
      SDK_ROOT="$2"; shift 2 ;;
    --java-home)
      (($# >= 2)) || fail 'Java home is missing'
      [[ -z "$JAVA_HOME_VALUE" ]] || fail 'Java home supplied more than once'
      JAVA_HOME_VALUE="$2"; shift 2 ;;
    --output-dir)
      (($# >= 2)) || fail 'output directory is missing'
      [[ -z "$OUTPUT_DIR" ]] || fail 'output directory supplied more than once'
      OUTPUT_DIR="$2"; shift 2 ;;
    *) fail 'unknown option' ;;
  esac
done

[[ "$SDK_ROOT" == /* && -d "$SDK_ROOT" && ! -L "$SDK_ROOT" &&
  "$SDK_ROOT" != *'..'* && "$SDK_ROOT" != *$'\n'* && "$SDK_ROOT" != *$'\r'* &&
  "$SDK_ROOT" != *$'\t'* ]] || fail 'SDK root is unsafe or unavailable'
[[ "$JAVA_HOME_VALUE" == /* && -d "$JAVA_HOME_VALUE" && ! -L "$JAVA_HOME_VALUE" &&
  "$JAVA_HOME_VALUE" != *'..'* && -x "$JAVA_HOME_VALUE/bin/java" &&
  -x "$JAVA_HOME_VALUE/bin/javac" && -x "$JAVA_HOME_VALUE/bin/jar" ]] ||
  fail 'Java home is unsafe or incomplete'
java_major_version="$($JAVA_HOME_VALUE/bin/java -version 2>&1 |
  sed -n 's/.*version "\([0-9][0-9]*\)\..*/\1/p' | head -n 1)"
[[ "$java_major_version" == '21' ]] || fail 'Java 21 is required'
[[ "$OUTPUT_DIR" == /* && "$OUTPUT_DIR" != *'..'* &&
  "$OUTPUT_DIR" != *$'\n'* && "$OUTPUT_DIR" != *$'\r'* && "$OUTPUT_DIR" != *$'\t'* ]] ||
  fail 'output directory is unsafe'
[[ -f "$GRADLE_WRAPPER" && -x "$GRADLE_WRAPPER" ]] ||
  fail 'Gradle wrapper is unavailable'
[[ -f "$HELPER_PROJECT_DIR/settings.gradle.kts" &&
  -f "$HELPER_PROJECT_DIR/build.gradle.kts" &&
  -f "$HELPER_PROJECT_DIR/helper/build.gradle.kts" ]] ||
  fail 'standalone helper project is incomplete'

for apkanalyzer_candidate in \
  "$SDK_ROOT/cmdline-tools/latest/bin/apkanalyzer" \
  "$SDK_ROOT/cmdline-tools/bin/apkanalyzer"; do
  if [[ -x "$apkanalyzer_candidate" && ! -L "$apkanalyzer_candidate" ]]; then
    APKANALYZER="$apkanalyzer_candidate"
    break
  fi
done
[[ -n "$APKANALYZER" ]] || fail 'apkanalyzer is unavailable in the Android SDK'

if [[ -e "$OUTPUT_DIR" || -L "$OUTPUT_DIR" ]]; then
  [[ -d "$OUTPUT_DIR" && ! -L "$OUTPUT_DIR" ]] || fail 'output path is not a directory'
  [[ -z "$(find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]] ||
    fail 'output directory must be empty'
else
  mkdir -p -- "$OUTPUT_DIR"
fi
chmod 700 "$OUTPUT_DIR"

gradle_build_root="$OUTPUT_DIR/gradle-build"
mkdir -- "$gradle_build_root"
chmod 700 "$gradle_build_root"

ANDROID_SDK_ROOT="$SDK_ROOT" ANDROID_HOME="$SDK_ROOT" \
  JAVA_HOME="$JAVA_HOME_VALUE" PATH="$JAVA_HOME_VALUE/bin:$PATH" \
  "$GRADLE_WRAPPER" --no-daemon --console=plain --max-workers=2 \
  --project-dir "$HELPER_PROJECT_DIR" \
  -PhelperBuildRoot="$gradle_build_root" \
  :helper:assembleDebug :helper:assembleDebugAndroidTest >/dev/null

base_apk="$gradle_build_root/helper/outputs/apk/debug/helper-debug.apk"
test_apk="$gradle_build_root/helper/outputs/apk/androidTest/debug/helper-debug-androidTest.apk"
[[ -f "$base_apk" && ! -L "$base_apk" && -s "$base_apk" ]] ||
  fail 'fresh helper base APK is missing'
[[ -f "$test_apk" && ! -L "$test_apk" && -s "$test_apk" ]] ||
  fail 'fresh AndroidX instrumentation APK is missing'

assert_minimal_manifest() {
  local apk="$1" kind="$2" manifest=''
  manifest="$(JAVA_HOME="$JAVA_HOME_VALUE" PATH="$JAVA_HOME_VALUE/bin:$PATH" \
    "$APKANALYZER" manifest print "$apk" 2>/dev/null)" ||
    fail "$kind APK manifest could not be inspected"
  if grep -Eiq '<(uses-permission|service|provider|receiver|activity(-alias)?)([[:space:]>]|$)' <<<"$manifest"; then
    fail "$kind APK contains a forbidden component or permission"
  fi
  if [[ "$kind" == 'base' ]]; then
    [[ "$manifest" == *'package="com.kong373.voicesocial.qa.alipayhelper"'* ]] ||
      fail 'base APK package attestation failed'
  else
    [[ "$manifest" == *'package="com.kong373.voicesocial.qa.alipayhelper.test"'* &&
      "$manifest" == *'android:targetPackage="com.kong373.voicesocial.qa.alipayhelper"'* ]] ||
      fail 'AndroidX test APK target attestation failed'
  fi
}

assert_minimal_manifest "$base_apk" 'base'
assert_minimal_manifest "$test_apk" 'AndroidX test'
cp -- "$base_apk" "$OUTPUT_DIR/alipay-androidx-dialog-helper.apk"
cp -- "$test_apk" "$OUTPUT_DIR/alipay-androidx-dialog-helper-androidTest.apk"
chmod 600 "$OUTPUT_DIR/alipay-androidx-dialog-helper.apk" \
  "$OUTPUT_DIR/alipay-androidx-dialog-helper-androidTest.apk"
rm -rf -- "$gradle_build_root"

printf 'ALIPAY_ANDROIDX_HELPER_BUILD::PASS\n'
