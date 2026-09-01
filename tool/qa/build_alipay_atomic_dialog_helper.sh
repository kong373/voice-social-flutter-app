#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
readonly PROJECT_ROOT
readonly SOURCE_FILE="$PROJECT_ROOT/tool/qa/alipay_atomic_dialog/AlipayConfigErrorDismissTest.java"
readonly DEFAULT_PLATFORM='36'
readonly DEFAULT_BUILD_TOOLS='36.0.0'

SDK_ROOT=''
JAVA_HOME_VALUE=''
OUTPUT_PATH=''
PLATFORM_VERSION="$DEFAULT_PLATFORM"
BUILD_TOOLS_VERSION="$DEFAULT_BUILD_TOOLS"

fail() {
  printf 'ALIPAY_ATOMIC_HELPER_BUILD: configuration rejected (%s)\n' "$1" >&2
  exit 64
}

usage() {
  cat <<'USAGE'
Usage: build_alipay_atomic_dialog_helper.sh --sdk-root PATH --java-home PATH --output PATH

Builds the tracked device-side UiAutomator test into one private dexed jar.
It never connects to a device or invokes a payment API.
USAGE
}

while (($# > 0)); do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --sdk-root)
      (($# >= 2)) || fail 'SDK root is missing'
      [[ -z "$SDK_ROOT" ]] || fail 'SDK root supplied more than once'
      SDK_ROOT="$2"; shift 2 ;;
    --output)
      (($# >= 2)) || fail 'output path is missing'
      [[ -z "$OUTPUT_PATH" ]] || fail 'output path supplied more than once'
      OUTPUT_PATH="$2"; shift 2 ;;
    --java-home)
      (($# >= 2)) || fail 'Java home is missing'
      [[ -z "$JAVA_HOME_VALUE" ]] || fail 'Java home supplied more than once'
      JAVA_HOME_VALUE="$2"; shift 2 ;;
    *) fail 'unknown option' ;;
  esac
done

[[ "$SDK_ROOT" == /* && -d "$SDK_ROOT" && ! -L "$SDK_ROOT" ]] ||
  fail 'SDK root must be an absolute real directory'
[[ "$JAVA_HOME_VALUE" == /* && -d "$JAVA_HOME_VALUE" && ! -L "$JAVA_HOME_VALUE" ]] ||
  fail 'Java home must be an absolute real directory'
[[ "$OUTPUT_PATH" == /* && "$OUTPUT_PATH" != *$'\n'* && "$OUTPUT_PATH" != *$'\r'* &&
  "$OUTPUT_PATH" != *$'\t'* && "$OUTPUT_PATH" != *'..'* && "$OUTPUT_PATH" == *.jar ]] ||
  fail 'output must be a safe absolute jar path'
[[ ! -e "$OUTPUT_PATH" && ! -L "$OUTPUT_PATH" ]] || fail 'output path already exists'
[[ -f "$SOURCE_FILE" && ! -L "$SOURCE_FILE" ]] || fail 'tracked Java source is unavailable'

android_jar="$SDK_ROOT/platforms/android-$PLATFORM_VERSION/android.jar"
uiautomator_jar="$SDK_ROOT/platforms/android-$PLATFORM_VERSION/uiautomator.jar"
test_base_jar="$SDK_ROOT/platforms/android-$PLATFORM_VERSION/optional/android.test.base.jar"
d8_bin="$SDK_ROOT/build-tools/$BUILD_TOOLS_VERSION/d8"
javac_bin="$JAVA_HOME_VALUE/bin/javac"
jar_bin="$JAVA_HOME_VALUE/bin/jar"
[[ -f "$android_jar" && -f "$uiautomator_jar" && -f "$test_base_jar" && -x "$d8_bin" ]] ||
  fail 'Android 36 platform or build tools are unavailable'
[[ -n "$javac_bin" && -x "$javac_bin" && -n "$jar_bin" && -x "$jar_bin" ]] ||
  fail 'Java compiler tools are unavailable'

output_parent="$(dirname "$OUTPUT_PATH")"
[[ -d "$output_parent" && ! -L "$output_parent" && -w "$output_parent" ]] ||
  fail 'output directory is unavailable'
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/voice-social-alipay-atomic-build.XXXXXX")" ||
  fail 'private build directory could not be created'
trap 'rm -rf -- "$work_dir"' EXIT
chmod 700 "$work_dir"
mkdir "$work_dir/classes" "$work_dir/dex"

"$javac_bin" -encoding UTF-8 -source 8 -target 8 \
  -bootclasspath "$android_jar" \
  -classpath "$android_jar:$uiautomator_jar:$test_base_jar" \
  -d "$work_dir/classes" "$SOURCE_FILE" >/dev/null 2>&1 ||
  fail 'Java helper compilation failed'
"$jar_bin" cf "$work_dir/helper-classes.jar" -C "$work_dir/classes" . >/dev/null 2>&1 ||
  fail 'Java helper archive failed'
JAVA_HOME="$JAVA_HOME_VALUE" PATH="$JAVA_HOME_VALUE/bin:$PATH" \
  "$d8_bin" --min-api 21 --lib "$android_jar" --lib "$test_base_jar" --output "$work_dir/dex" \
  "$work_dir/helper-classes.jar" >/dev/null 2>&1 || fail 'dex compilation failed'
[[ -f "$work_dir/dex/classes.dex" ]] || fail 'dex output is missing'
"$jar_bin" cf "$OUTPUT_PATH" -C "$work_dir/dex" classes.dex >/dev/null 2>&1 ||
  fail 'dex jar creation failed'
chmod 600 "$OUTPUT_PATH"
[[ -f "$OUTPUT_PATH" && ! -L "$OUTPUT_PATH" && -s "$OUTPUT_PATH" ]] ||
  fail 'private dex jar is invalid'

printf 'ALIPAY_ATOMIC_HELPER_BUILD::PASS\n'
