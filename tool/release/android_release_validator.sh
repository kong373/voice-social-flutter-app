#!/usr/bin/env bash
set -euo pipefail

umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly PROJECT_ROOT

readonly DEFAULT_PACKAGE="com.kong373.voice_social_app"
readonly DEFAULT_APK_NAME="app-release.apk"
readonly DEFAULT_AAB_NAME="app-release.aab"

EXPECTED_PACKAGE="$DEFAULT_PACKAGE"
APK_PATH=""
AAB_PATH=""
SELF_TEST=0

usage() {
  cat <<'USAGE'
Usage:
  android_release_validator.sh --apk PATH --aab PATH [--expected-package ID]
  android_release_validator.sh --self-test

The validator emits only non-sensitive artifact status. It never prints signing
metadata, certificates, keystore paths, or credential values.
USAGE
}

fail() {
  printf 'android-release-validation=FAIL reason=%s\n' "$1" >&2
  exit 1
}

while (($# > 0)); do
  case "$1" in
    --apk)
      (($# >= 2)) || fail 'missing_apk_path'
      APK_PATH="$2"
      shift 2
      ;;
    --aab)
      (($# >= 2)) || fail 'missing_aab_path'
      AAB_PATH="$2"
      shift 2
      ;;
    --expected-package)
      (($# >= 2)) || fail 'missing_expected_package'
      EXPECTED_PACKAGE="$2"
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

[[ "$EXPECTED_PACKAGE" =~ ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$ ]] ||
  fail 'invalid_expected_package'

contains_forbidden_surface() {
  local source_file="$1"
  grep -Fq 'NativeAlipayIsolationActivity' "$source_file" && return 0
  grep -Fq 'AlipayConfigErrorDismissTest' "$source_file" && return 0
  return 1
}

contains_debug_certificate() {
  local source_file="$1"
  grep -Eiq 'Android Debug|debug\.keystore|CN=Android Debug' "$source_file"
}

contains_debuggable_marker() {
  local source_file="$1"
  grep -Fq 'application-debuggable' "$source_file" && return 0
  grep -Eiq "debuggable[[:space:]]*=[[:space:]]*['\"]?(true|0x?ffffffff)" "$source_file"
}

contains_jar_signature_metadata() {
  local source_file="$1"
  grep -Eiq '^META-INF/[^/]+\.SF$' "$source_file" &&
    grep -Eiq '^META-INF/[^/]+\.(RSA|DSA|EC)$' "$source_file"
}

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

resolve_command() {
  local requested="$1"
  local command_name="$2"
  if [[ -n "$requested" ]]; then
    [[ -x "$requested" ]] || fail "missing_${command_name}_tool"
    printf '%s\n' "$requested"
    return 0
  fi
  command -v "$command_name" 2>/dev/null || true
}

resolve_sdk_tool() {
  local tool_name="$1"
  local sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  if [[ -z "$sdk_root" ]]; then
    local local_properties="$PROJECT_ROOT/android/local.properties"
    if [[ -f "$local_properties" ]]; then
      sdk_root="$(sed -n 's/^sdk\.dir=//p' "$local_properties" | head -n 1)"
      sdk_root="${sdk_root//\\:/:}"
      sdk_root="${sdk_root//\\\\/\\}"
    fi
  fi
  [[ -n "$sdk_root" && -d "$sdk_root/build-tools" ]] || return 0
  find "$sdk_root/build-tools" -maxdepth 2 -type f -name "$tool_name" -perm -111 \
    -print 2>/dev/null | sort | tail -n 1
}

validate_apk() {
  local apk="$1"
  [[ -f "$apk" && -s "$apk" ]] || fail 'apk_missing_or_empty'

  local aapt2_bin
  aapt2_bin="$(resolve_command "${AAPT2_BIN:-}" aapt2)"
  [[ -n "$aapt2_bin" ]] || aapt2_bin="$(resolve_sdk_tool aapt2)"
  [[ -n "$aapt2_bin" ]] || fail 'aapt2_unavailable'

  local apksigner_bin
  apksigner_bin="$(resolve_command "${APKSIGNER_BIN:-}" apksigner)"
  [[ -n "$apksigner_bin" ]] || apksigner_bin="$(resolve_sdk_tool apksigner)"
  [[ -n "$apksigner_bin" ]] || fail 'apksigner_unavailable'

  local badging_file manifest_file cert_file dex_file entry_file
  badging_file="$(mktemp)"
  manifest_file="$(mktemp)"
  cert_file="$(mktemp)"
  entry_file="$(mktemp)"
  trap 'rm -f "$badging_file" "$manifest_file" "$cert_file" "$entry_file"' RETURN

  unzip -Z1 "$apk" >"$entry_file" 2>/dev/null || fail 'apk_not_zip'
  if contains_forbidden_surface "$entry_file"; then
    fail 'debug_only_surface_in_apk'
  fi

  "$aapt2_bin" dump badging "$apk" >"$badging_file" 2>/dev/null ||
    fail 'apk_badging_failed'
  grep -Fq "package: name='$EXPECTED_PACKAGE'" "$badging_file" ||
    fail 'apk_package_mismatch'
  contains_debuggable_marker "$badging_file" &&
    fail 'apk_is_debuggable'

  "$aapt2_bin" dump xmltree "$apk" --file AndroidManifest.xml >"$manifest_file" 2>/dev/null ||
    fail 'apk_manifest_failed'
  if contains_forbidden_surface "$manifest_file"; then
    fail 'debug_only_surface_in_apk_manifest'
  fi

  while IFS= read -r dex_file; do
    [[ -n "$dex_file" ]] || continue
    if unzip -p "$apk" "$dex_file" 2>/dev/null | strings | grep -Fq 'NativeAlipayIsolationActivity'; then
      fail 'debug_only_surface_in_apk_code'
    fi
    if unzip -p "$apk" "$dex_file" 2>/dev/null | strings | grep -Fq 'AlipayConfigErrorDismissTest'; then
      fail 'debug_only_surface_in_apk_code'
    fi
  done < <(grep -E '^classes([0-9]+)?\.dex$' "$entry_file" || true)

  "$apksigner_bin" verify --verbose --print-certs "$apk" >"$cert_file" 2>&1 ||
    fail 'apk_signature_invalid'
  if contains_debug_certificate "$cert_file"; then
    fail 'apk_uses_debug_certificate'
  fi

  trap - RETURN
  rm -f "$badging_file" "$manifest_file" "$cert_file" "$entry_file"
}

validate_aab() {
  local aab="$1"
  [[ -f "$aab" && -s "$aab" ]] || fail 'aab_missing_or_empty'

  local entry_file signature_file manifest_file bundletool_bin
  entry_file="$(mktemp)"
  signature_file="$(mktemp)"
  manifest_file="$(mktemp)"
  trap 'rm -f "$entry_file" "$signature_file" "$manifest_file"' RETURN

  unzip -Z1 "$aab" >"$entry_file" 2>/dev/null || fail 'aab_not_zip'
  grep -Fxq 'BundleConfig.pb' "$entry_file" || fail 'aab_bundle_config_missing'
  grep -Fxq 'base/manifest/AndroidManifest.xml' "$entry_file" ||
    fail 'aab_base_manifest_missing'
  contains_jar_signature_metadata "$entry_file" ||
    fail 'aab_signature_metadata_missing'
  if contains_forbidden_surface "$entry_file"; then
    fail 'debug_only_surface_in_aab'
  fi
  local dex_file
  while IFS= read -r dex_file; do
    [[ -n "$dex_file" ]] || continue
    if unzip -p "$aab" "$dex_file" 2>/dev/null | strings | grep -Fq 'NativeAlipayIsolationActivity'; then
      fail 'debug_only_surface_in_aab_code'
    fi
    if unzip -p "$aab" "$dex_file" 2>/dev/null | strings | grep -Fq 'AlipayConfigErrorDismissTest'; then
      fail 'debug_only_surface_in_aab_code'
    fi
  done < <(grep -E '^base/dex/classes([0-9]+)?\.dex$' "$entry_file" || true)

  bundletool_bin="$(resolve_command "${BUNDLETOOL_BIN:-}" bundletool)"
  if [[ -n "$bundletool_bin" ]]; then
    "$bundletool_bin" dump manifest --bundle="$aab" >"$manifest_file" 2>/dev/null ||
      fail 'aab_manifest_failed'
    grep -Fq "package=\"$EXPECTED_PACKAGE\"" "$manifest_file" ||
      fail 'aab_package_mismatch'
    if contains_forbidden_surface "$manifest_file"; then
      fail 'debug_only_surface_in_aab_manifest'
    fi
    contains_debuggable_marker "$manifest_file" &&
      fail 'aab_is_debuggable'
  else
    # Package-only parsing is not enough to prove the AAB is non-debuggable.
    # Require bundletool so the release manifest is inspected fail-closed.
    fail 'bundletool_unavailable_for_aab_debug_validation'
  fi

  local jarsigner_bin
  jarsigner_bin="$(resolve_command "${JARSIGNER_BIN:-}" jarsigner)"
  [[ -n "$jarsigner_bin" ]] || fail 'jarsigner_unavailable'
  # `-certs` only includes signer certificate details together with verbose
  # entry output. Without `-verbose`, a debug-signed bundle can look like a
  # valid JAR while hiding the signer subject from the check below.
  # Android app-signing/upload keys are normally self-signed. `-strict` turns
  # the expected PKIX trust-chain warning into exit 4 even when every AAB entry
  # is cryptographically verified. Require JAR signature metadata above, then
  # use jarsigner's normal cryptographic verification here.
  "$jarsigner_bin" -verify -verbose -certs "$aab" >"$signature_file" 2>&1 ||
    fail 'aab_signature_invalid'
  if contains_debug_certificate "$signature_file"; then
    fail 'aab_uses_debug_certificate'
  fi

  trap - RETURN
  rm -f "$entry_file" "$signature_file" "$manifest_file"
}

self_test() {
  local safe_entries forbidden_entries safe_file forbidden_file
  [[ "$DEFAULT_APK_NAME" == 'app-release.apk' &&
    "$DEFAULT_AAB_NAME" == 'app-release.aab' ]] ||
    fail 'self_test_artifact_names_changed'
  safe_entries="base/manifest/AndroidManifest.xml
BundleConfig.pb
META-INF/VOICE-SO.SF
META-INF/VOICE-SO.RSA"
  forbidden_entries="base/manifest/AndroidManifest.xml
NativeAlipayIsolationActivity.class"
  safe_file="$(mktemp)"
  forbidden_file="$(mktemp)"
  printf '%s\n' "$safe_entries" >"$safe_file"
  printf '%s\n' "$forbidden_entries" >"$forbidden_file"
  if contains_forbidden_surface "$safe_file"; then
    fail 'self_test_safe_surface_false_positive'
  fi
  if ! contains_forbidden_surface "$forbidden_file"; then
    rm -f "$safe_file" "$forbidden_file"
    fail 'self_test_forbidden_surface_not_detected'
  fi
  if ! contains_jar_signature_metadata "$safe_file"; then
    fail 'self_test_jar_signature_metadata_not_detected'
  fi
  printf 'META-INF/VOICE-SO.SF\n' >"$forbidden_file"
  if contains_jar_signature_metadata "$forbidden_file"; then
    fail 'self_test_partial_jar_signature_metadata_accepted'
  fi
  local safe_certificate debug_certificate safe_manifest debug_manifest
  safe_certificate="$(mktemp)"
  debug_certificate="$(mktemp)"
  safe_manifest="$(mktemp)"
  debug_manifest="$(mktemp)"
  printf 'Signer: CN=Voice Social Release\n' >"$safe_certificate"
  printf 'Signer: CN=Android Debug, O=Android\n' >"$debug_certificate"
  printf 'application: label=Voice Social\n' >"$safe_manifest"
  printf 'application-debuggable\n' >"$debug_manifest"
  if contains_debug_certificate "$safe_certificate"; then
    fail 'self_test_safe_certificate_false_positive'
  fi
  if ! contains_debug_certificate "$debug_certificate"; then
    fail 'self_test_debug_certificate_not_detected'
  fi
  if contains_debuggable_marker "$safe_manifest"; then
    fail 'self_test_safe_manifest_false_positive'
  fi
  if ! contains_debuggable_marker "$debug_manifest"; then
    fail 'self_test_debuggable_marker_not_detected'
  fi
  rm -f "$safe_file" "$forbidden_file" "$safe_certificate" "$debug_certificate" \
    "$safe_manifest" "$debug_manifest"
  printf 'android-release-validator=self-test-PASS\n'
}

if ((SELF_TEST == 1)); then
  [[ -z "$APK_PATH" && -z "$AAB_PATH" ]] || fail 'self_test_does_not_accept_artifacts'
  self_test
  exit 0
fi

[[ -n "$APK_PATH" && -n "$AAB_PATH" ]] || {
  usage >&2
  fail 'both_apk_and_aab_are_required'
}

validate_apk "$APK_PATH"
validate_aab "$AAB_PATH"
printf 'android-release-validation=PASS\n'
printf 'apk=PASS non_debuggable=PASS non_debug_certificate=PASS sha256=%s\n' "$(sha256_file "$APK_PATH")"
printf 'aab=PASS non_debuggable=PASS non_debug_certificate=PASS sha256=%s\n' "$(sha256_file "$AAB_PATH")"
