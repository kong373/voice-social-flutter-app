#!/usr/bin/env bash
set -euo pipefail

umask 077

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
readonly SCRIPT_PATH="$SCRIPT_DIR/ios_release_validator.sh"

ARCHIVE_PATH=""
IPA_PATH=""
EXPECTED_BUNDLE_ID=""
EXPECTED_VERSION=""
EXPECTED_BUILD=""
EXPECTED_TEAM_ID=""
SELF_TEST=0
TMP_ROOT=""

PLUTIL_BIN="${IOS_PLUTIL_BIN:-plutil}"
PLISTBUDDY_BIN="${IOS_PLISTBUDDY_BIN:-/usr/libexec/PlistBuddy}"
CODESIGN_BIN="${IOS_CODESIGN_BIN:-codesign}"
SECURITY_BIN="${IOS_SECURITY_BIN:-security}"
FILE_BIN="${IOS_FILE_BIN:-file}"
OTOOL_BIN="${IOS_OTOOL_BIN:-otool}"
UNZIP_BIN="${IOS_UNZIP_BIN:-unzip}"
ZIPINFO_BIN="${IOS_ZIPINFO_BIN:-zipinfo}"
SHASUM_BIN="${IOS_SHASUM_BIN:-}"

ARCHIVE_SIGNING_IDENTITY=""
ARCHIVE_APP_SHA256=""
ARCHIVE_EXECUTABLE_SHA256=""
ARCHIVE_EXECUTABLE_CONTENT_SHA256=""
ARCHIVE_INFO_SHA256=""
ARCHIVE_BUNDLE_ID=""
ARCHIVE_VERSION=""
ARCHIVE_BUILD=""
ARCHIVE_DECLARED_APP_NAME=""
ARCHIVE_EXECUTABLE_NAME=""
IPA_APP_NAME=""
IPA_FILE_SHA256=""
IPA_APP_SHA256=""
IPA_EXECUTABLE_SHA256=""
IPA_EXECUTABLE_CONTENT_SHA256=""

CURRENT_TEAM_IDENTIFIER=""
CURRENT_APP_SHA256=""
CURRENT_EXECUTABLE_SHA256=""
CURRENT_EXECUTABLE_CONTENT_SHA256=""
CURRENT_EXECUTABLE_NAME=""
CURRENT_BUNDLE_ID=""
CURRENT_VERSION=""
CURRENT_BUILD=""

usage() {
  cat <<'USAGE'
Usage:
  ios_release_validator.sh --archive PATH \
    --expected-bundle-id ID --expected-version VERSION \
    --expected-build BUILD --expected-team-id TEAM_ID [--ipa PATH]
  ios_release_validator.sh --self-test

The validator reads an explicit archive and, when supplied, an IPA. It emits
only fixed status labels and SHA-256 digests. Tool output is kept in temporary
files and is never copied to the terminal.
USAGE
}

fail() {
  printf 'ios-release-validation=FAIL reason=%s\n' "$1" >&2
  exit 1
}

cleanup() {
  local exit_code=$?
  if [[ -n "$TMP_ROOT" && -d "$TMP_ROOT" && ! -L "$TMP_ROOT" ]]; then
    rm -rf -- "$TMP_ROOT" >/dev/null 2>&1 || true
  fi
  return "$exit_code"
}

trap cleanup EXIT

while (($# > 0)); do
  case "$1" in
    --archive|--xcarchive)
      (($# >= 2)) || fail missing_archive_path
      ARCHIVE_PATH="$2"
      shift 2
      ;;
    --ipa)
      (($# >= 2)) || fail missing_ipa_path
      IPA_PATH="$2"
      shift 2
      ;;
    --expected-bundle-id|--bundle-id)
      (($# >= 2)) || fail missing_expected_bundle_id
      EXPECTED_BUNDLE_ID="$2"
      shift 2
      ;;
    --expected-version|--version)
      (($# >= 2)) || fail missing_expected_version
      EXPECTED_VERSION="$2"
      shift 2
      ;;
    --expected-build|--build)
      (($# >= 2)) || fail missing_expected_build
      EXPECTED_BUILD="$2"
      shift 2
      ;;
    --expected-team-id|--team-id)
      (($# >= 2)) || fail missing_expected_team_id
      EXPECTED_TEAM_ID="$2"
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
      fail unknown_argument
      ;;
  esac
done

if ((SELF_TEST == 1)) && [[ -n "$ARCHIVE_PATH" || -n "$IPA_PATH" ||
  -n "$EXPECTED_BUNDLE_ID" || -n "$EXPECTED_VERSION" ||
  -n "$EXPECTED_BUILD" || -n "$EXPECTED_TEAM_ID" ]]; then
  fail self_test_arguments_invalid
fi

resolve_tool() {
  local requested="$1"
  local command_name="$2"
  local resolved=""

  if [[ -n "$requested" ]]; then
    if [[ "$requested" == */* ]]; then
      [[ -x "$requested" && ! -L "$requested" ]] ||
        fail "missing_${command_name}_tool"
      printf '%s\n' "$requested"
      return 0
    fi
    resolved="$(command -v "$requested" 2>/dev/null || true)"
    [[ -n "$resolved" ]] || fail "missing_${command_name}_tool"
    printf '%s\n' "$resolved"
    return 0
  fi

  resolved="$(command -v "$command_name" 2>/dev/null || true)"
  [[ -n "$resolved" ]] || fail "missing_${command_name}_tool"
  printf '%s\n' "$resolved"
}

validate_expected_values() {
  [[ "$EXPECTED_BUNDLE_ID" =~ ^[A-Za-z0-9]+([.][-A-Za-z0-9]+)+$ ]] ||
    fail invalid_expected_bundle_id
  [[ "$EXPECTED_VERSION" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] ||
    fail invalid_expected_version
  [[ "$EXPECTED_BUILD" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] ||
    fail invalid_expected_build
  [[ "$EXPECTED_TEAM_ID" =~ ^[A-Za-z0-9]{1,64}$ ]] ||
    fail invalid_expected_team_id
}

canonical_directory() {
  local input="$1"
  local canonical=""
  canonical="$(cd -P -- "$input" 2>/dev/null && pwd -P)" || return 1
  [[ -n "$canonical" ]] || return 1
  printf '%s\n' "$canonical"
}

canonical_file() {
  local input="$1"
  local parent=""
  local base=""
  parent="$(dirname -- "$input")" || return 1
  base="$(basename -- "$input")" || return 1
  parent="$(canonical_directory "$parent")" || return 1
  printf '%s/%s\n' "$parent" "$base"
}

validate_input_paths() {
  [[ -n "$ARCHIVE_PATH" ]] || fail missing_archive_path
  [[ -n "$EXPECTED_BUNDLE_ID" ]] || fail missing_expected_bundle_id
  [[ -n "$EXPECTED_VERSION" ]] || fail missing_expected_version
  [[ -n "$EXPECTED_BUILD" ]] || fail missing_expected_build
  [[ -n "$EXPECTED_TEAM_ID" ]] || fail missing_expected_team_id
  [[ "$ARCHIVE_PATH" == *.xcarchive ]] || fail archive_extension_required
  if [[ -n "$IPA_PATH" ]]; then
    [[ "$IPA_PATH" == *.ipa ]] || fail ipa_extension_required
  fi

  [[ -d "$ARCHIVE_PATH" && ! -L "$ARCHIVE_PATH" ]] ||
    fail archive_missing_or_not_directory
  ARCHIVE_PATH="$(canonical_directory "$ARCHIVE_PATH")" ||
    fail archive_path_unreadable

  if [[ -n "$IPA_PATH" ]]; then
    [[ -f "$IPA_PATH" && ! -L "$IPA_PATH" ]] ||
      fail ipa_missing_or_symlink
    IPA_PATH="$(canonical_file "$IPA_PATH")" || fail ipa_path_unreadable
    [[ -f "$IPA_PATH" && ! -L "$IPA_PATH" ]] ||
      fail ipa_missing_or_symlink
  fi
}

require_regular_file() {
  local path="$1"
  local reason="$2"
  [[ -f "$path" && ! -L "$path" && -s "$path" ]] || fail "$reason"
}

require_directory() {
  local path="$1"
  local reason="$2"
  [[ -d "$path" && ! -L "$path" ]] || fail "$reason"
}

validate_tree_safety() {
  local root="$1"
  local special_reason="$2"
  local name_reason="$3"
  local path_list=""
  local special_probe=""
  local path=""

  path_list="$(mktemp "$TMP_ROOT/tree-paths.XXXXXX" 2>/dev/null)" ||
    fail temporary_file_unavailable
  find -P "$root" -print0 >"$path_list" 2>/dev/null ||
    fail tree_inventory_failed
  while IFS= read -r -d '' path; do
    case "$path" in
      *$'\n'*|*$'\r'*) fail "$name_reason" ;;
    esac
  done <"$path_list"

  special_probe="$(mktemp "$TMP_ROOT/tree-special.XXXXXX" 2>/dev/null)" ||
    fail temporary_file_unavailable
  find -P "$root" \( ! -type f -a ! -type d -a ! -type l \) -print -quit \
    >"$special_probe" 2>/dev/null || fail tree_inventory_failed
  [[ ! -s "$special_probe" ]] || fail "$special_reason"
}

plist_lint() {
  local plist="$1"
  local reason="$2"
  "$PLUTIL_BIN" -lint -- "$plist" > /dev/null 2>&1 ||
    fail "$reason"
}

plist_raw() {
  local plist="$1"
  local key_path="$2"
  local value=""
  value="$("$PLUTIL_BIN" -extract "$key_path" raw -o - -- "$plist" \
    2>/dev/null)" || return 1
  printf '%s\n' "$value"
}

plist_buddy_print() {
  local plist="$1"
  local key="$2"
  local value=""
  value="$("$PLISTBUDDY_BIN" -c "Print :$key" "$plist" 2>/dev/null)" ||
    return 1
  printf '%s\n' "$value"
}

plist_entry_type() {
  local plist="$1"
  local key="$2"
  local value=""
  value="$(plist_buddy_print "$plist" "$key")" || return 1
  case "$value" in
    'Array {'*) printf 'array\n' ;;
    'Dict {'*) printf 'dict\n' ;;
    true|false) printf 'bool\n' ;;
    *) printf 'scalar\n' ;;
  esac
}

plist_is_dictionary() {
  local plist="$1"
  local value=""
  value="$("$PLISTBUDDY_BIN" -c 'Print' "$plist" 2>/dev/null)" ||
    return 1
  [[ "$value" == 'Dict {'* ]]
}

write_entitlements_xml() {
  local source="$1"
  local destination="$2"
  "$PLUTIL_BIN" -convert xml1 -o "$destination" -- "$source" > /dev/null \
    2>&1 || return 1
  [[ -f "$destination" && ! -L "$destination" && -s "$destination" ]]
}

write_profile_entitlements() {
  local profile="$1"
  local destination="$2"
  "$PLUTIL_BIN" -extract Entitlements xml1 -o "$destination" -- "$profile" \
    > /dev/null 2>&1 || return 1
  [[ -f "$destination" && ! -L "$destination" && -s "$destination" ]]
}

plist_top_level_keys() {
  local plist="$1"
  local xml="$2"
  write_entitlements_xml "$plist" "$xml" || return 1
  awk '
    /<dict>/ { depth += 1 }
    depth == 1 && /<key>/ {
      key = $0
      sub(/^.*<key>/, "", key)
      sub(/<\/key>.*$/, "", key)
      print key
    }
    /<\/dict>/ { depth -= 1 }
  ' "$xml"
}

plist_array_values() {
  local plist="$1"
  local key="$2"
  local index=0
  local value=""
  while ((index < 256)); do
    if ! value="$("$PLISTBUDDY_BIN" -c "Print :$key:$index" "$plist" \
      2>/dev/null)"; then
      break
    fi
    printf '%s\n' "$value"
    ((index += 1))
  done
}

compare_array_subset() {
  local app_entitlements="$1"
  local profile_entitlements="$2"
  local key="$3"
  local app_values=""
  local profile_values=""
  local value=""

  app_values="$(mktemp "$TMP_ROOT/app-array.XXXXXX" 2>/dev/null)" ||
    fail temporary_file_unavailable
  profile_values="$(mktemp "$TMP_ROOT/profile-array.XXXXXX" 2>/dev/null)" ||
    fail temporary_file_unavailable
  plist_array_values "$app_entitlements" "$key" >"$app_values" ||
    fail signed_entitlement_array_unreadable
  plist_array_values "$profile_entitlements" "$key" >"$profile_values" ||
    fail profile_entitlement_array_unreadable

  while IFS= read -r value; do
    [[ -n "$value" ]] || fail signed_entitlement_array_invalid
    grep -Fqx -- "$value" "$profile_values" ||
      fail entitlement_not_in_profile
  done <"$app_values"
}

compare_signed_entitlements() {
  local app_entitlements="$1"
  local profile_entitlements="$2"
  local keys_xml=""
  local keys_file=""
  local key=""
  local app_type=""
  local profile_type=""
  local app_value=""
  local profile_value=""

  plist_is_dictionary "$app_entitlements" || fail signed_entitlements_not_dictionary
  plist_is_dictionary "$profile_entitlements" || fail profile_entitlements_not_dictionary

  keys_xml="$(mktemp "$TMP_ROOT/entitlement-keys-xml.XXXXXX" 2>/dev/null)" ||
    fail temporary_file_unavailable
  keys_file="$(mktemp "$TMP_ROOT/entitlement-keys.XXXXXX" 2>/dev/null)" ||
    fail temporary_file_unavailable
  plist_top_level_keys "$app_entitlements" "$keys_xml" >"$keys_file" ||
    fail signed_entitlements_unreadable
  [[ -s "$keys_file" ]] || fail signed_entitlements_empty

  while IFS= read -r key; do
    [[ "$key" =~ ^[A-Za-z0-9]+([._-][A-Za-z0-9]+)*$ ]] ||
      fail entitlement_key_invalid
    app_type="$(plist_entry_type "$app_entitlements" "$key")" ||
      fail signed_entitlement_unreadable
    profile_type="$(plist_entry_type "$profile_entitlements" "$key")" ||
      fail entitlement_not_in_profile
    [[ "$app_type" == "$profile_type" ]] || fail entitlement_type_mismatch

    case "$app_type" in
      array)
        compare_array_subset "$app_entitlements" "$profile_entitlements" "$key"
        ;;
      dict)
        fail entitlement_dictionary_not_provable
        ;;
      scalar|bool)
        app_value="$(plist_buddy_print "$app_entitlements" "$key")" ||
          fail signed_entitlement_unreadable
        profile_value="$(plist_buddy_print "$profile_entitlements" "$key")" ||
          fail profile_entitlement_unreadable
        [[ "$app_value" == "$profile_value" ]] ||
          fail entitlement_value_mismatch
        ;;
      *)
        fail entitlement_type_unknown
        ;;
    esac
  done <"$keys_file"
}

sha256_file() {
  local file="$1"
  local result=""
  result="$("$SHASUM_BIN" -a 256 "$file" 2>/dev/null)" || return 1
  result="$(printf '%s\n' "$result" | awk 'NF { print $1; exit }')"
  [[ "$result" =~ ^[0-9a-fA-F]{64}$ ]] || return 1
  printf '%s\n' "$result" | tr 'A-F' 'a-f'
}

sha256_app_bundle() {
  local app="$1"
  local files=""
  local sorted_files=""
  local manifest=""
  local relative=""
  local digest=""

  files="$(mktemp "$TMP_ROOT/app-files.XXXXXX" 2>/dev/null)" ||
    fail temporary_file_unavailable
  sorted_files="$(mktemp "$TMP_ROOT/app-files-sorted.XXXXXX" 2>/dev/null)" ||
    fail temporary_file_unavailable
  manifest="$(mktemp "$TMP_ROOT/app-manifest.XXXXXX" 2>/dev/null)" ||
    fail temporary_file_unavailable
  (
    cd -P -- "$app" || exit 1
    find -P . -type f -print
  ) >"$files" 2>/dev/null || fail app_file_inventory_failed
  LC_ALL=C sort "$files" >"$sorted_files" || fail app_file_inventory_failed
  : >"$manifest"
  while IFS= read -r relative; do
    [[ -n "$relative" ]] || continue
    relative="${relative#./}"
    digest="$(sha256_file "$app/$relative")" || fail app_file_hash_failed
    printf '%s  %s\n' "$digest" "$relative" >>"$manifest"
  done <"$sorted_files"
  sha256_file "$manifest" || fail app_bundle_hash_failed
}

parse_epoch() {
  local value="$1"
  local parsed=""
  parsed="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$value" '+%s' \
    2>/dev/null || true)"
  if [[ -z "$parsed" ]]; then
    parsed="$(date -j -u -f '%Y-%m-%dT%H:%M:%S%z' "$value" '+%s' \
      2>/dev/null || true)"
  fi
  if [[ -z "$parsed" ]]; then
    parsed="$(date -u -d "$value" '+%s' 2>/dev/null || true)"
  fi
  [[ "$parsed" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$parsed"
}

validate_distribution_identity() {
  local identity="$1"
  case "$identity" in
    *'Apple Development'*|*'iPhone Developer'*|*'[DEBUG]'*)
      fail debug_signing_not_allowed
      ;;
    *)
      ;;
  esac
  case "$identity" in
    'Apple Distribution:'*|'iPhone Distribution:'*)
      ;;
    *)
      fail distribution_signing_required
      ;;
  esac
  [[ "$identity" == *"($EXPECTED_TEAM_ID)" ]] ||
    fail signing_team_mismatch
}

validate_non_simulator_executable() {
  local executable="$1"
  local file_report=""
  local load_commands=""

  file_report="$(mktemp "$TMP_ROOT/file-report.XXXXXX" 2>/dev/null)" ||
    fail temporary_file_unavailable
  load_commands="$(mktemp "$TMP_ROOT/load-commands.XXXXXX" 2>/dev/null)" ||
    fail temporary_file_unavailable
  "$FILE_BIN" -b "$executable" >"$file_report" 2>&1 ||
    fail executable_file_inspection_failed
  grep -Eiq 'Mach-O' "$file_report" || fail executable_not_macho
  grep -Eiq 'Mach-O.*(executable|universal binary)' "$file_report" ||
    fail executable_not_macho
  if grep -Eiq 'simulator|i386|x86_64' "$file_report"; then
    fail app_is_simulator
  fi
  grep -Eiq '(^|[^[:alnum:]_])arm64(e)?([^[:alnum:]_]|$)' "$file_report" ||
    fail device_architecture_not_supported

  "$OTOOL_BIN" -l "$executable" >"$load_commands" 2>&1 ||
    fail executable_load_commands_failed
  if grep -Eiq 'IOSSIMULATOR|IOS_SIMULATOR|platform[[:space:]]+IOSSIMULATOR' \
    "$load_commands"; then
    fail app_is_simulator
  fi
  grep -Eiq 'platform[[:space:]]+IOS([[:space:]]|$)|LC_VERSION_MIN_IPHONEOS' \
    "$load_commands" || fail device_platform_not_proven
}

sha256_executable_content() {
  local executable="$1"
  local normalized=""

  normalized="$(mktemp "$TMP_ROOT/executable-content.XXXXXX" 2>/dev/null)" ||
    fail temporary_file_unavailable
  cp -p -- "$executable" "$normalized" >/dev/null 2>&1 ||
    fail executable_copy_failed
  "$CODESIGN_BIN" --remove-signature "$normalized" >/dev/null 2>&1 ||
    fail executable_signature_normalization_failed
  require_regular_file "$normalized" executable_normalization_missing
  sha256_file "$normalized" || fail executable_content_sha256_failed
}

validate_archive_info() {
  local info="$ARCHIVE_PATH/Info.plist"
  local archive_application_path=""
  local archive_version_marker=""

  require_regular_file "$info" archive_info_missing
  plist_lint "$info" archive_info_invalid
  archive_version_marker="$(plist_raw "$info" ArchiveVersion 2>/dev/null || true)"
  [[ "$archive_version_marker" == 2 ]] || fail archive_version_invalid
  ARCHIVE_BUNDLE_ID="$(plist_raw "$info" ApplicationProperties.CFBundleIdentifier \
    2>/dev/null || true)"
  ARCHIVE_VERSION="$(plist_raw "$info" ApplicationProperties.CFBundleShortVersionString \
    2>/dev/null || true)"
  ARCHIVE_BUILD="$(plist_raw "$info" ApplicationProperties.CFBundleVersion \
    2>/dev/null || true)"
  ARCHIVE_SIGNING_IDENTITY="$(plist_raw "$info" ApplicationProperties.SigningIdentity \
    2>/dev/null || true)"
  local archive_team=""
  archive_team="$(plist_raw "$info" ApplicationProperties.Team 2>/dev/null || true)"
  [[ -n "$ARCHIVE_BUNDLE_ID" ]] || fail archive_bundle_id_missing
  [[ -n "$ARCHIVE_VERSION" ]] || fail archive_version_missing
  [[ -n "$ARCHIVE_BUILD" ]] || fail archive_build_missing
  [[ -n "$ARCHIVE_SIGNING_IDENTITY" ]] || fail archive_signing_identity_missing
  [[ -n "$archive_team" ]] || fail archive_team_missing
  [[ "$ARCHIVE_BUNDLE_ID" == "$EXPECTED_BUNDLE_ID" ]] ||
    fail archive_bundle_id_mismatch
  [[ "$ARCHIVE_VERSION" == "$EXPECTED_VERSION" ]] ||
    fail archive_version_mismatch
  [[ "$ARCHIVE_BUILD" == "$EXPECTED_BUILD" ]] || fail archive_build_mismatch
  [[ "$archive_team" == "$EXPECTED_TEAM_ID" ]] || fail archive_team_mismatch
  validate_distribution_identity "$ARCHIVE_SIGNING_IDENTITY"

  archive_application_path="$(plist_raw "$info" ApplicationProperties.ApplicationPath \
    2>/dev/null || true)"
  [[ -n "$archive_application_path" ]] || fail archive_application_path_missing
  ARCHIVE_DECLARED_APP_NAME="${archive_application_path##*/}"
  [[ "$ARCHIVE_DECLARED_APP_NAME" == *.app &&
    "$archive_application_path" == "Applications/$ARCHIVE_DECLARED_APP_NAME" ]] ||
    fail archive_application_path_invalid
  ARCHIVE_INFO_SHA256="$(sha256_file "$info")" || fail archive_info_hash_failed
}

find_archive_app() {
  local applications="$ARCHIVE_PATH/Products/Applications"
  local candidates=""
  local candidate=""
  local count=0
  local symlink_probe=""

  require_directory "$ARCHIVE_PATH/Products" archive_products_missing
  require_directory "$applications" archive_applications_missing
  validate_tree_safety "$ARCHIVE_PATH" archive_special_file_detected \
    archive_path_invalid
  symlink_probe="$(mktemp "$TMP_ROOT/archive-symlinks.XXXXXX" 2>/dev/null)" ||
    fail temporary_file_unavailable
  find -P "$ARCHIVE_PATH" -type l -print -quit >"$symlink_probe" 2>/dev/null ||
    fail archive_inventory_failed
  [[ ! -s "$symlink_probe" ]] || fail archive_symlink_detected

  candidates="$(mktemp "$TMP_ROOT/archive-apps.XXXXXX" 2>/dev/null)" ||
    fail temporary_file_unavailable
  find -P "$applications" -mindepth 1 -maxdepth 1 -type d -name '*.app' \
    -print >"$candidates" 2>/dev/null || fail archive_app_inventory_failed
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    [[ ! -L "$candidate" ]] || fail archive_app_symlink_detected
    ARCHIVE_APP_PATH="$candidate"
    ((count += 1))
  done <"$candidates"
  [[ "$count" -eq 1 ]] || fail archive_app_count_invalid
  require_directory "$ARCHIVE_APP_PATH" archive_app_missing
  [[ "${ARCHIVE_APP_PATH##*/}" == "$ARCHIVE_DECLARED_APP_NAME" ]] ||
    fail archive_application_path_mismatch
}

validate_profile() {
  local app="$1"
  local profile="$app/embedded.mobileprovision"
  local decoded_profile=""
  local profile_entitlements=""
  local profile_app_id=""
  local profile_team=""
  local profile_team_list=""
  local profile_prefix=""
  local profile_get_task_allow=""
  local profile_expiration=""
  local profile_expiration_epoch=""
  local now_epoch=""

  require_regular_file "$profile" profile_missing_or_symlink
  decoded_profile="$(mktemp "$TMP_ROOT/profile-decoded.XXXXXX" 2>/dev/null)" ||
    fail temporary_file_unavailable
  "$SECURITY_BIN" cms -D -i "$profile" >"$decoded_profile" 2>/dev/null ||
    fail profile_decode_failed
  require_regular_file "$decoded_profile" profile_decode_empty
  plist_lint "$decoded_profile" profile_invalid

  profile_entitlements="$(mktemp "$TMP_ROOT/profile-entitlements.XXXXXX" 2>/dev/null)" ||
    fail temporary_file_unavailable
  write_profile_entitlements "$decoded_profile" "$profile_entitlements" ||
    fail profile_entitlements_missing
  plist_lint "$profile_entitlements" profile_entitlements_invalid
  plist_is_dictionary "$profile_entitlements" ||
    fail profile_entitlements_not_dictionary

  profile_app_id="$(plist_buddy_print "$profile_entitlements" \
    'application-identifier' 2>/dev/null || true)"
  profile_team="$(plist_buddy_print "$profile_entitlements" \
    'com.apple.developer.team-identifier' 2>/dev/null || true)"
  profile_get_task_allow="$(plist_buddy_print "$profile_entitlements" \
    'get-task-allow' 2>/dev/null || true)"
  [[ "$profile_app_id" == "$EXPECTED_TEAM_ID.$EXPECTED_BUNDLE_ID" ]] ||
    fail profile_application_identifier_mismatch
  [[ "$profile_team" == "$EXPECTED_TEAM_ID" ]] || fail profile_team_mismatch
  [[ "$profile_get_task_allow" == false ]] || fail profile_get_task_allow_enabled

  profile_team_list="$(plist_raw "$decoded_profile" TeamIdentifier.0 \
    2>/dev/null || true)"
  [[ "$profile_team_list" == "$EXPECTED_TEAM_ID" ]] ||
    fail profile_team_list_mismatch
  profile_prefix="$(plist_raw "$decoded_profile" ApplicationIdentifierPrefix.0 \
    2>/dev/null || true)"
  [[ "$profile_prefix" == "$EXPECTED_TEAM_ID" ]] ||
    fail profile_application_prefix_mismatch

  profile_expiration="$(plist_raw "$decoded_profile" ExpirationDate \
    2>/dev/null || true)"
  [[ -n "$profile_expiration" ]] || fail profile_expiration_missing
  profile_expiration_epoch="$(parse_epoch "$profile_expiration" 2>/dev/null || true)"
  [[ "$profile_expiration_epoch" =~ ^[0-9]+$ ]] ||
    fail profile_expiration_unreadable
  now_epoch="$(date -u '+%s' 2>/dev/null || true)"
  [[ "$now_epoch" =~ ^[0-9]+$ ]] || fail clock_unavailable
  ((profile_expiration_epoch > now_epoch)) || fail profile_expired

  PROFILE_ENTITLEMENTS_PATH="$profile_entitlements"
}

validate_app() {
  local app="$1"
  local info="$app/Info.plist"
  local executable_name=""
  local executable=""
  local package_type=""
  local platform_name=""
  local sdk_name=""
  local display_report=""
  local entitlements_file=""
  local authority=""
  local team_identifier=""
  local profile_entitlements=""
  local signed_application_identifier=""
  local signed_team_identifier=""
  local signed_get_task_allow=""
  local privacy_manifest="$app/PrivacyInfo.xcprivacy"
  local symlink_probe=""

  require_directory "$app" app_bundle_missing
  validate_tree_safety "$app" app_special_file_detected app_path_invalid
  symlink_probe="$(mktemp "$TMP_ROOT/app-symlinks.XXXXXX" 2>/dev/null)" ||
    fail temporary_file_unavailable
  find -P "$app" -type l -print -quit >"$symlink_probe" 2>/dev/null ||
    fail app_inventory_failed
  [[ ! -s "$symlink_probe" ]] || fail app_symlink_detected

  require_regular_file "$info" app_info_missing
  plist_lint "$info" app_info_invalid
  CURRENT_BUNDLE_ID="$(plist_raw "$info" CFBundleIdentifier 2>/dev/null || true)"
  CURRENT_VERSION="$(plist_raw "$info" CFBundleShortVersionString 2>/dev/null || true)"
  CURRENT_BUILD="$(plist_raw "$info" CFBundleVersion 2>/dev/null || true)"
  executable_name="$(plist_raw "$info" CFBundleExecutable 2>/dev/null || true)"
  package_type="$(plist_raw "$info" CFBundlePackageType 2>/dev/null || true)"
  platform_name="$(plist_raw "$info" DTPlatformName 2>/dev/null || true)"
  sdk_name="$(plist_raw "$info" DTSDKName 2>/dev/null || true)"
  [[ "$CURRENT_BUNDLE_ID" == "$EXPECTED_BUNDLE_ID" ]] || fail app_bundle_id_mismatch
  [[ "$CURRENT_VERSION" == "$EXPECTED_VERSION" ]] || fail app_version_mismatch
  [[ "$CURRENT_BUILD" == "$EXPECTED_BUILD" ]] || fail app_build_mismatch
  [[ "$package_type" == APPL ]] || fail app_package_type_invalid
  [[ "$platform_name" == iphoneos ]] || fail app_is_simulator
  [[ "$sdk_name" == iphoneos* ]] || fail app_sdk_not_device
  [[ "$executable_name" =~ ^[A-Za-z0-9._-]+$ ]] || fail executable_name_invalid
  [[ "$executable_name" != . && "$executable_name" != .. ]] ||
    fail executable_name_invalid
  executable="$app/$executable_name"
  require_regular_file "$executable" executable_missing_or_symlink
  [[ -x "$executable" ]] || fail executable_not_executable
  validate_non_simulator_executable "$executable"
  require_regular_file "$privacy_manifest" privacy_manifest_missing_or_symlink
  plist_lint "$privacy_manifest" privacy_manifest_invalid
  plist_is_dictionary "$privacy_manifest" || fail privacy_manifest_not_dictionary

  display_report="$(mktemp "$TMP_ROOT/codesign-display.XXXXXX" 2>/dev/null)" ||
    fail temporary_file_unavailable
  "$CODESIGN_BIN" --display --verbose=4 "$app" >"$display_report" 2>&1 ||
    fail codesign_display_failed
  if grep -Eiq 'Signature[[:space:]]*=[[:space:]]*(adhoc|none)' \
    "$display_report"; then
    fail ad_hoc_signing_not_allowed
  fi
  if grep -Eiq 'Apple Development|iPhone Developer|debug' "$display_report"; then
    fail debug_signing_not_allowed
  fi
  authority="$(sed -n 's/^Authority=//p' "$display_report" | head -n 1)"
  team_identifier="$(sed -n 's/^TeamIdentifier=//p' "$display_report" | head -n 1)"
  [[ -n "$authority" ]] || fail signing_identity_missing
  [[ "$team_identifier" == "$EXPECTED_TEAM_ID" ]] ||
    fail signing_team_mismatch
  validate_distribution_identity "$authority"

  local verify_report=""
  local entitlements_stderr=""
  verify_report="$(mktemp "$TMP_ROOT/codesign-verify.XXXXXX" 2>/dev/null)" ||
    fail temporary_file_unavailable
  entitlements_stderr="$(mktemp "$TMP_ROOT/codesign-entitlements-stderr.XXXXXX" 2>/dev/null)" ||
    fail temporary_file_unavailable
  "$CODESIGN_BIN" --verify --deep --strict --verbose=2 "$app" \
    >"$verify_report" 2>&1 || fail codesign_invalid
  entitlements_file="$(mktemp "$TMP_ROOT/signed-entitlements.XXXXXX" 2>/dev/null)" ||
    fail temporary_file_unavailable
  "$CODESIGN_BIN" --display --entitlements :- "$app" >"$entitlements_file" \
    2>"$entitlements_stderr" || fail signed_entitlements_failed
  require_regular_file "$entitlements_file" signed_entitlements_empty
  plist_lint "$entitlements_file" signed_entitlements_invalid

  validate_profile "$app"
  profile_entitlements="$PROFILE_ENTITLEMENTS_PATH"
  compare_signed_entitlements "$entitlements_file" "$profile_entitlements"
  signed_application_identifier="$(plist_buddy_print "$entitlements_file" \
    'application-identifier' 2>/dev/null || true)"
  signed_team_identifier="$(plist_buddy_print "$entitlements_file" \
    'com.apple.developer.team-identifier' 2>/dev/null || true)"
  signed_get_task_allow="$(plist_buddy_print "$entitlements_file" \
    'get-task-allow' 2>/dev/null || true)"
  [[ "$signed_application_identifier" == "$EXPECTED_TEAM_ID.$EXPECTED_BUNDLE_ID" ]] ||
    fail signed_application_identifier_mismatch
  [[ "$signed_team_identifier" == "$EXPECTED_TEAM_ID" ]] ||
    fail signed_team_identifier_mismatch
  [[ "$signed_get_task_allow" == false ]] || fail signed_get_task_allow_enabled
  CURRENT_TEAM_IDENTIFIER="$team_identifier"
  CURRENT_EXECUTABLE_NAME="$executable_name"
  CURRENT_EXECUTABLE_SHA256="$(sha256_file "$executable")" ||
    fail executable_sha256_failed
  CURRENT_EXECUTABLE_CONTENT_SHA256="$(sha256_executable_content "$executable")"
  CURRENT_APP_SHA256="$(sha256_app_bundle "$app")"
}

validate_ipa_structure() {
  local ipa="$1"
  local entries=""
  local duplicates=""
  local zip_listing=""
  local app_names=""
  local app_name=""
  local count=0
  local entry=""
  local component=""
  local components=()

  require_regular_file "$ipa" ipa_missing_or_symlink
  entries="$(mktemp "$TMP_ROOT/ipa-entries.XXXXXX" 2>/dev/null)" ||
    fail temporary_file_unavailable
  "$UNZIP_BIN" -Z1 "$ipa" >"$entries" 2>/dev/null || fail ipa_not_zip
  [[ -s "$entries" ]] || fail ipa_empty
  duplicates="$(mktemp "$TMP_ROOT/ipa-duplicates.XXXXXX" 2>/dev/null)" ||
    fail temporary_file_unavailable
  LC_ALL=C sort "$entries" | uniq -d >"$duplicates" ||
    fail ipa_entry_inventory_failed
  [[ ! -s "$duplicates" ]] || fail ipa_duplicate_entry
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || fail ipa_entry_invalid
    case "$entry" in
      *$'\r'*) fail ipa_entry_invalid ;;
      /*|*\\*|*//* ) fail ipa_path_traversal ;;
    esac
    IFS='/' read -r -a components <<<"$entry"
    for component in "${components[@]}"; do
      [[ "$component" != . && "$component" != .. ]] || fail ipa_path_traversal
    done
    case "$entry" in
      Payload|Payload/*) ;;
      *) fail ipa_entry_outside_payload ;;
    esac
  done <"$entries"

  zip_listing="$(mktemp "$TMP_ROOT/ipa-zip-listing.XXXXXX" 2>/dev/null)" ||
    fail temporary_file_unavailable
  "$ZIPINFO_BIN" -l "$ipa" >"$zip_listing" 2>/dev/null ||
    fail ipa_zip_metadata_unavailable
  if awk 'length($1) == 10 && substr($1, 1, 1) == "l" { found = 1 }
    END { exit found ? 0 : 1 }' "$zip_listing"; then
    fail ipa_symlink_detected
  fi
  if awk 'length($1) == 10 && substr($1, 1, 1) !~ /^[-d]$/ { found = 1 }
    END { exit found ? 0 : 1 }' "$zip_listing"; then
    fail ipa_special_file_detected
  fi

  app_names="$(mktemp "$TMP_ROOT/ipa-app-names.XXXXXX" 2>/dev/null)" ||
    fail temporary_file_unavailable
  awk -F/ '$1 == "Payload" && $2 ~ /\.app$/ { print $2 }' "$entries" |
    LC_ALL=C sort -u >"$app_names"
  while IFS= read -r app_name; do
    [[ -n "$app_name" ]] || continue
    ((count += 1))
  done <"$app_names"
  [[ "$count" -eq 1 ]] || fail ipa_multiple_apps
  IPA_APP_NAME="$(head -n 1 "$app_names")"
  [[ -n "$IPA_APP_NAME" ]] || fail ipa_app_missing
  while IFS= read -r entry; do
    case "$entry" in
      Payload|Payload/|"Payload/$IPA_APP_NAME"|"Payload/$IPA_APP_NAME/"*) ;;
      *) fail ipa_entry_outside_single_app ;;
    esac
  done <"$entries"
}

extract_ipa_app() {
  local ipa="$1"
  local extract_root=""
  local symlink_probe=""
  local special_probe=""

  extract_root="$(mktemp -d "$TMP_ROOT/ipa-extract.XXXXXX" 2>/dev/null)" ||
    fail temporary_directory_unavailable
  "$UNZIP_BIN" -q -n "$ipa" -d "$extract_root" > /dev/null 2>&1 ||
    fail ipa_extract_failed
  symlink_probe="$(mktemp "$TMP_ROOT/ipa-extracted-symlinks.XXXXXX" 2>/dev/null)" ||
    fail temporary_file_unavailable
  find -P "$extract_root" -type l -print -quit >"$symlink_probe" 2>/dev/null ||
    fail ipa_extracted_inventory_failed
  [[ ! -s "$symlink_probe" ]] || fail ipa_symlink_detected
  special_probe="$(mktemp "$TMP_ROOT/ipa-extracted-special.XXXXXX" 2>/dev/null)" ||
    fail temporary_file_unavailable
  find -P "$extract_root" \( ! -type f -a ! -type d \) -print -quit \
    >"$special_probe" 2>/dev/null || fail ipa_extracted_inventory_failed
  [[ ! -s "$special_probe" ]] || fail ipa_special_file_detected
  IPA_APP_PATH="$extract_root/Payload/$IPA_APP_NAME"
  require_directory "$IPA_APP_PATH" ipa_app_missing
}

validate_ipa() {
  local ipa="$1"
  local ipa_app_path=""
  local ipa_file_sha256=""
  local ipa_digest_before=""
  local ipa_digest_after_structure=""
  local ipa_digest_after_validation=""

  ipa_digest_before="$(sha256_file "$ipa")" || fail ipa_sha256_failed
  validate_ipa_structure "$ipa"
  ipa_digest_after_structure="$(sha256_file "$ipa")" || fail ipa_sha256_failed
  [[ "$ipa_digest_after_structure" == "$ipa_digest_before" ]] ||
    fail ipa_changed_during_validation
  extract_ipa_app "$ipa"
  ipa_app_path="$IPA_APP_PATH"
  validate_app "$ipa_app_path"
  [[ "$CURRENT_BUNDLE_ID" == "$ARCHIVE_BUNDLE_ID" ]] ||
    fail ipa_bundle_id_mismatch
  [[ "$CURRENT_VERSION" == "$ARCHIVE_VERSION" ]] || fail ipa_version_mismatch
  [[ "$CURRENT_BUILD" == "$ARCHIVE_BUILD" ]] || fail ipa_build_mismatch
  [[ "$CURRENT_TEAM_IDENTIFIER" == "$EXPECTED_TEAM_ID" ]] ||
    fail ipa_team_mismatch
  [[ "$IPA_APP_NAME" == "$ARCHIVE_DECLARED_APP_NAME" ]] ||
    fail ipa_app_name_mismatch
  [[ "$CURRENT_EXECUTABLE_NAME" == "$ARCHIVE_EXECUTABLE_NAME" ]] ||
    fail ipa_executable_name_mismatch
  [[ "$CURRENT_EXECUTABLE_CONTENT_SHA256" == \
    "$ARCHIVE_EXECUTABLE_CONTENT_SHA256" ]] ||
    fail ipa_executable_content_hash_mismatch
  ipa_digest_after_validation="$(sha256_file "$ipa")" || fail ipa_sha256_failed
  [[ "$ipa_digest_after_validation" == "$ipa_digest_before" ]] ||
    fail ipa_changed_during_validation
  ipa_file_sha256="$ipa_digest_after_validation"
  IPA_FILE_SHA256="$ipa_file_sha256"
  IPA_APP_SHA256="$CURRENT_APP_SHA256"
  IPA_EXECUTABLE_SHA256="$CURRENT_EXECUTABLE_SHA256"
  IPA_EXECUTABLE_CONTENT_SHA256="$CURRENT_EXECUTABLE_CONTENT_SHA256"
}

write_self_test_profile() {
  local destination="$1"
  local expiration="$2"
  local get_task_allow="$3"
  local application_id="$4"
  local team_id="$5"
  local task_node='<false/>'
  if [[ "$get_task_allow" == true ]]; then
    task_node='<true/>'
  fi
  cat >"$destination" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>ApplicationIdentifierPrefix</key><array><string>${team_id}</string></array>
<key>Entitlements</key><dict>
<key>application-identifier</key><string>${application_id}</string>
<key>com.apple.developer.associated-domains</key><array><string>applinks:example.com</string></array>
<key>com.apple.developer.team-identifier</key><string>${team_id}</string>
<key>get-task-allow</key>${task_node}
<key>keychain-access-groups</key><array><string>${application_id}</string></array>
</dict>
<key>ExpirationDate</key><date>${expiration}</date>
<key>TeamIdentifier</key><array><string>${team_id}</string></array>
</dict></plist>
PLIST
}

write_self_test_app_info() {
  local destination="$1"
  local bundle_id="$2"
  local version="$3"
  local build="$4"
  local executable_name="$5"
  cat >"$destination" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>${executable_name}</string>
<key>CFBundleIdentifier</key><string>${bundle_id}</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>${version}</string>
<key>CFBundleVersion</key><string>${build}</string>
<key>DTPlatformName</key><string>iphoneos</string>
<key>DTSDKName</key><string>iphoneos18.6</string>
</dict></plist>
PLIST
}

write_self_test_archive_info() {
  local destination="$1"
  local bundle_id="$2"
  local version="$3"
  local build="$4"
  local team_id="$5"
  local identity="$6"
  cat >"$destination" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>ApplicationProperties</key><dict>
<key>ApplicationPath</key><string>Applications/VoiceSocial.app</string>
<key>CFBundleIdentifier</key><string>${bundle_id}</string>
<key>CFBundleShortVersionString</key><string>${version}</string>
<key>CFBundleVersion</key><string>${build}</string>
<key>SigningIdentity</key><string>${identity}</string>
<key>Team</key><string>${team_id}</string>
</dict>
<key>ArchiveVersion</key><integer>2</integer>
</dict></plist>
PLIST
}

write_self_test_commands() {
  local fixture_bin="$1"
  local fake_codesign="$fixture_bin/codesign"
  local fake_security="$fixture_bin/security"
  local fake_file="$fixture_bin/file"
  local fake_otool="$fixture_bin/otool"

  cat >"$fake_codesign" <<'FAKE_CODESIGN'
#!/usr/bin/env bash
set -euo pipefail
mode="${IOS_FAKE_MODE:-valid}"
if [[ "${1:-}" == --verify ]]; then
  [[ "$mode" != invalid ]] || exit 1
  exit 0
fi
if [[ "${1:-}" == --remove-signature ]]; then
  exit 0
fi
if [[ "${1:-}" == --display && "${2:-}" == --entitlements ]]; then
  domain='applinks:example.com'
  [[ "$mode" == entitlement-mismatch ]] && domain='applinks:bad.example.com'
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>application-identifier</key><string>${IOS_FAKE_TEAM_ID}.${IOS_FAKE_BUNDLE_ID}</string>
<key>com.apple.developer.associated-domains</key><array><string>${domain}</string></array>
<key>com.apple.developer.team-identifier</key><string>${IOS_FAKE_TEAM_ID}</string>
<key>get-task-allow</key><false/>
<key>keychain-access-groups</key><array><string>${IOS_FAKE_TEAM_ID}.${IOS_FAKE_BUNDLE_ID}</string></array>
</dict></plist>
PLIST
  exit 0
fi
if [[ "${1:-}" == --display ]]; then
  printf 'Executable=%s\n' "${IOS_FAKE_EXECUTABLE}"
  case "$mode" in
    debug) printf 'Authority=Apple Development: Fixture (%s)\n' "${IOS_FAKE_TEAM_ID}" ;;
    adhoc) printf 'Signature=adhoc\n' ;;
    *) printf 'Authority=Apple Distribution: Fixture (%s)\n' "${IOS_FAKE_TEAM_ID}" ;;
  esac
  printf 'TeamIdentifier=%s\n' "${IOS_FAKE_TEAM_ID}"
  exit 0
fi
exit 2
FAKE_CODESIGN

  cat >"$fake_security" <<'FAKE_SECURITY'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == cms && "${2:-}" == -D && "${3:-}" == -i ]] || exit 2
cat "${IOS_FAKE_PROFILE_FILE:?}"
FAKE_SECURITY

  cat >"$fake_file" <<'FAKE_FILE'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${IOS_FAKE_MODE:-valid}" == simulator ]]; then
  printf 'Mach-O 64-bit executable x86_64 simulator\n'
else
  printf 'Mach-O 64-bit executable arm64\n'
fi
FAKE_FILE

  cat >"$fake_otool" <<'FAKE_OTOOL'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${IOS_FAKE_MODE:-valid}" == simulator ]]; then
  printf 'platform IOSSIMULATOR\n'
else
  printf 'platform IOS\n'
fi
FAKE_OTOOL
  chmod 700 "$fake_codesign" "$fake_security" "$fake_file" "$fake_otool"
}

self_test_run_case() {
  local mode="$1"
  local profile="$2"
  local expected_status="$3"
  local expected_reason="$4"
  local output=""
  local error_output=""
  local archive_app_hash=""
  local ipa_app_hash=""
  local status=0
  local ipa_path="${5:-}"
  local validator_args=(
    --archive "$SELF_TEST_ARCHIVE"
    --expected-bundle-id "$SELF_TEST_BUNDLE"
    --expected-version "$SELF_TEST_VERSION"
    --expected-build "$SELF_TEST_BUILD"
    --expected-team-id "$SELF_TEST_TEAM"
  )
  if [[ -n "$ipa_path" ]]; then
    validator_args+=(--ipa "$ipa_path")
  fi

  output="$(mktemp "$TMP_ROOT/self-test-output.XXXXXX" 2>/dev/null)" ||
    fail temporary_file_unavailable
  error_output="$(mktemp "$TMP_ROOT/self-test-error.XXXXXX" 2>/dev/null)" ||
    fail temporary_file_unavailable
  set +e
  IOS_CODESIGN_BIN="$SELF_TEST_CODESIGN" \
  IOS_SECURITY_BIN="$SELF_TEST_SECURITY" \
  IOS_FILE_BIN="$SELF_TEST_FILE" \
  IOS_OTOOL_BIN="$SELF_TEST_OTOOL" \
  IOS_PLUTIL_BIN="$SELF_TEST_PLUTIL" \
  IOS_PLISTBUDDY_BIN="$SELF_TEST_PLISTBUDDY" \
  IOS_SHASUM_BIN="$SELF_TEST_SHASUM" \
  IOS_UNZIP_BIN="$SELF_TEST_UNZIP" \
  IOS_ZIPINFO_BIN="$SELF_TEST_ZIPINFO" \
  IOS_FAKE_MODE="$mode" \
  IOS_FAKE_PROFILE_FILE="$profile" \
  IOS_FAKE_TEAM_ID="$SELF_TEST_TEAM" \
  IOS_FAKE_BUNDLE_ID="$SELF_TEST_BUNDLE" \
  IOS_FAKE_EXECUTABLE="$SELF_TEST_EXECUTABLE" \
  "$SCRIPT_PATH" "${validator_args[@]}" >"$output" 2>"$error_output"
  status=$?
  set -e

  if [[ "$expected_status" == pass ]]; then
    [[ "$status" -eq 0 ]] || fail self_test_success_case_failed
    grep -Fxq 'ios-release-validation=PASS' "$output" ||
      fail self_test_success_status_missing
    grep -Eq '^archive_info_sha256=[0-9a-f]{64}$' "$output" ||
      fail self_test_archive_info_hash_missing
    grep -Eq '^archive_app_sha256=[0-9a-f]{64}$' "$output" ||
      fail self_test_archive_hash_missing
    grep -Eq '^archive_executable_sha256=[0-9a-f]{64}$' "$output" ||
      fail self_test_archive_executable_hash_missing
    grep -Eq '^archive_executable_content_sha256=[0-9a-f]{64}$' "$output" ||
      fail self_test_archive_executable_content_hash_missing
    if [[ -n "$ipa_path" ]]; then
      grep -Eq '^ipa_sha256=[0-9a-f]{64}$' "$output" ||
        fail self_test_ipa_hash_missing
      grep -Eq '^ipa_app_sha256=[0-9a-f]{64}$' "$output" ||
        fail self_test_ipa_app_hash_missing
      archive_app_hash="$(sed -n 's/^archive_app_sha256=//p' "$output")"
      ipa_app_hash="$(sed -n 's/^ipa_app_sha256=//p' "$output")"
      [[ -n "$archive_app_hash" && "$archive_app_hash" != "$ipa_app_hash" ]] ||
        fail self_test_exported_app_hash_not_changed
      grep -Eq '^ipa_executable_sha256=[0-9a-f]{64}$' "$output" ||
        fail self_test_ipa_executable_hash_missing
      grep -Eq '^ipa_executable_content_sha256=[0-9a-f]{64}$' "$output" ||
        fail self_test_ipa_executable_content_hash_missing
    else
      grep -Eq '^ipa_' "$output" && fail self_test_optional_ipa_leaked
    fi
    [[ ! -s "$error_output" ]] || fail self_test_success_error_output
  else
    [[ "$status" -ne 0 ]] || fail "self_test_case_accepted_${expected_reason}"
    grep -Fqx "ios-release-validation=FAIL reason=$expected_reason" \
      "$error_output" || fail "self_test_case_reason_${expected_reason}"
    [[ ! -s "$output" ]] || fail "self_test_case_stdout_${expected_reason}"
  fi
}

self_test() {
  local fixture_root=""
  local fixture_bin=""
  local archive=""
  local app=""
  local payload_root=""
  local ipa_root=""
  local ipa=""
  local profile_valid=""
  local profile_task_allow=""
  local profile_expired=""
  local profile_mismatch=""
  local profile_exported=""
  local multi_root=""
  local multi_ipa=""
  local symlink_root=""
  local symlink_ipa=""
  local traversal_ipa=""
  local outside_file=""
  local zip_bin=""
  local plutil_bin=""
  local plistbuddy_bin=""
  local shasum_bin=""
  local unzip_bin=""
  local zipinfo_bin=""
  local identity=""

  TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ios-release-self-test.XXXXXX" 2>/dev/null || \
    mktemp -d 2>/dev/null)" || fail temporary_directory_unavailable
  fixture_root="$TMP_ROOT/fixture"
  fixture_bin="$fixture_root/bin"
  archive="$fixture_root/VoiceSocial.xcarchive"
  app="$archive/Products/Applications/VoiceSocial.app"
  payload_root="$fixture_root/payload-source"
  ipa_root="$payload_root/Payload"
  ipa="$fixture_root/VoiceSocial.ipa"
  profile_valid="$fixture_root/profile-valid.plist"
  profile_task_allow="$fixture_root/profile-task-allow.plist"
  profile_expired="$fixture_root/profile-expired.plist"
  profile_mismatch="$fixture_root/profile-mismatch.plist"
  profile_exported="$fixture_root/profile-exported.plist"
  multi_root="$fixture_root/multiple-source"
  multi_ipa="$fixture_root/multiple.ipa"
  symlink_root="$fixture_root/symlink-source"
  symlink_ipa="$fixture_root/symlink.ipa"
  traversal_ipa="$fixture_root/traversal.ipa"
  outside_file="$fixture_root/outside.txt"

  SELF_TEST_TEAM='TEAMID1234'
  SELF_TEST_BUNDLE='com.example.voiceSocial'
  SELF_TEST_VERSION='1.2.3'
  SELF_TEST_BUILD='42'
  SELF_TEST_EXECUTABLE='VoiceSocial'
  identity="Apple Distribution: Fixture (${SELF_TEST_TEAM})"
  mkdir -p "$fixture_bin" "$app" "$ipa_root" || fail self_test_fixture_setup_failed
  plutil_bin="$(command -v plutil 2>/dev/null || true)"
  plistbuddy_bin='/usr/libexec/PlistBuddy'
  shasum_bin="$(command -v shasum 2>/dev/null || true)"
  unzip_bin="$(command -v unzip 2>/dev/null || true)"
  zipinfo_bin="$(command -v zipinfo 2>/dev/null || true)"
  zip_bin="$(command -v zip 2>/dev/null || true)"
  [[ -n "$plutil_bin" && -x "$plistbuddy_bin" && -n "$shasum_bin" &&
    -n "$unzip_bin" && -n "$zipinfo_bin" && -n "$zip_bin" ]] ||
    fail self_test_tool_unavailable
  SELF_TEST_PLUTIL="$plutil_bin"
  SELF_TEST_PLISTBUDDY="$plistbuddy_bin"
  SELF_TEST_SHASUM="$shasum_bin"
  SELF_TEST_UNZIP="$unzip_bin"
  SELF_TEST_ZIPINFO="$zipinfo_bin"
  SELF_TEST_CODESIGN="$fixture_bin/codesign"
  SELF_TEST_SECURITY="$fixture_bin/security"
  SELF_TEST_FILE="$fixture_bin/file"
  SELF_TEST_OTOOL="$fixture_bin/otool"
  SELF_TEST_ARCHIVE="$archive"
  write_self_test_commands "$fixture_bin"

  write_self_test_app_info "$app/Info.plist" "$SELF_TEST_BUNDLE" \
    "$SELF_TEST_VERSION" "$SELF_TEST_BUILD" "$SELF_TEST_EXECUTABLE"
  printf 'temporary executable fixture\n' >"$app/$SELF_TEST_EXECUTABLE"
  chmod 700 "$app/$SELF_TEST_EXECUTABLE"
  cat >"$app/PrivacyInfo.xcprivacy" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict/></plist>
PLIST
  write_self_test_profile "$profile_valid" '2037-01-01T00:00:00Z' false \
    "$SELF_TEST_TEAM.$SELF_TEST_BUNDLE" "$SELF_TEST_TEAM"
  cp -- "$profile_valid" "$app/embedded.mobileprovision"
  write_self_test_archive_info "$archive/Info.plist" "$SELF_TEST_BUNDLE" \
    "$SELF_TEST_VERSION" "$SELF_TEST_BUILD" "$SELF_TEST_TEAM" "$identity"

  cp -R -- "$app" "$ipa_root/VoiceSocial.app"
  write_self_test_profile "$profile_exported" '2038-01-01T00:00:00Z' false \
    "$SELF_TEST_TEAM.$SELF_TEST_BUNDLE" "$SELF_TEST_TEAM"
  cp -- "$profile_exported" "$ipa_root/VoiceSocial.app/embedded.mobileprovision"
  (cd "$payload_root" && "$zip_bin" -q -r "$ipa" Payload) >/dev/null 2>&1 ||
    fail self_test_ipa_fixture_failed

  self_test_run_case valid "$profile_valid" pass none "$ipa"
  self_test_run_case valid "$profile_valid" pass none
  self_test_run_case simulator "$profile_valid" fail app_is_simulator
  self_test_run_case invalid "$profile_valid" fail codesign_invalid
  self_test_run_case adhoc "$profile_valid" fail ad_hoc_signing_not_allowed
  self_test_run_case debug "$profile_valid" fail debug_signing_not_allowed

  write_self_test_profile "$profile_task_allow" '2037-01-01T00:00:00Z' true \
    "$SELF_TEST_TEAM.$SELF_TEST_BUNDLE" "$SELF_TEST_TEAM"
  self_test_run_case valid "$profile_task_allow" fail profile_get_task_allow_enabled
  write_self_test_profile "$profile_expired" '2000-01-01T00:00:00Z' false \
    "$SELF_TEST_TEAM.$SELF_TEST_BUNDLE" "$SELF_TEST_TEAM"
  self_test_run_case valid "$profile_expired" fail profile_expired
  write_self_test_profile "$profile_mismatch" '2037-01-01T00:00:00Z' false \
    "$SELF_TEST_TEAM.com.example.other" "$SELF_TEST_TEAM"
  self_test_run_case valid "$profile_mismatch" fail profile_application_identifier_mismatch
  self_test_run_case entitlement-mismatch "$profile_valid" fail entitlement_not_in_profile

  local saved_privacy_manifest="$fixture_root/PrivacyInfo.xcprivacy.saved"
  mv -- "$app/PrivacyInfo.xcprivacy" "$saved_privacy_manifest" ||
    fail self_test_privacy_setup_failed
  self_test_run_case valid "$profile_valid" fail privacy_manifest_missing_or_symlink
  printf 'not a plist\n' >"$app/PrivacyInfo.xcprivacy"
  self_test_run_case valid "$profile_valid" fail privacy_manifest_invalid
  rm -f -- "$app/PrivacyInfo.xcprivacy"
  mv -- "$saved_privacy_manifest" "$app/PrivacyInfo.xcprivacy" ||
    fail self_test_privacy_restore_failed

  mkdir -p "$multi_root/Payload" || fail self_test_multiple_setup_failed
  cp -R -- "$app" "$multi_root/Payload/VoiceSocial.app"
  cp -R -- "$app" "$multi_root/Payload/Other.app"
  (cd "$multi_root" && "$zip_bin" -q -r "$multi_ipa" Payload) >/dev/null 2>&1 ||
    fail self_test_multiple_ipa_fixture_failed
  self_test_run_case valid "$profile_valid" fail ipa_multiple_apps "$multi_ipa"

  rm -f -- "$multi_ipa"
  (cd "$payload_root" && "$zip_bin" -q -r "$multi_ipa" Payload) >/dev/null 2>&1 ||
    fail self_test_ipa_rebuild_failed

  mkdir -p "$symlink_root/Payload" || fail self_test_symlink_setup_failed
  cp -R -- "$app" "$symlink_root/Payload/VoiceSocial.app"
  ln -s -- 'Info.plist' "$symlink_root/Payload/VoiceSocial.app/linked-file"
  (cd "$symlink_root" && "$zip_bin" -q -y -r "$symlink_ipa" Payload) \
    >/dev/null 2>&1 || fail self_test_symlink_ipa_fixture_failed
  self_test_run_case valid "$profile_valid" fail ipa_symlink_detected "$symlink_ipa"

  printf 'path traversal fixture\n' >"$outside_file"
  cp -- "$ipa" "$traversal_ipa"
  (cd "$payload_root" && "$zip_bin" -q "$traversal_ipa" '../outside.txt') \
    >/dev/null 2>&1 || true
  self_test_run_case valid "$profile_valid" fail ipa_path_traversal "$traversal_ipa"

  printf 'ios-release-validator=self-test-PASS\n'
}

if ((SELF_TEST == 1)); then
  self_test
  exit 0
fi

validate_expected_values
validate_input_paths

PLUTIL_BIN="$(resolve_tool "$PLUTIL_BIN" plutil)"
PLISTBUDDY_BIN="$(resolve_tool "$PLISTBUDDY_BIN" PlistBuddy)"
CODESIGN_BIN="$(resolve_tool "$CODESIGN_BIN" codesign)"
SECURITY_BIN="$(resolve_tool "$SECURITY_BIN" security)"
FILE_BIN="$(resolve_tool "$FILE_BIN" file)"
OTOOL_BIN="$(resolve_tool "$OTOOL_BIN" otool)"
SHASUM_BIN="$(resolve_tool "$SHASUM_BIN" shasum 2>/dev/null || true)"
if [[ -z "$SHASUM_BIN" ]]; then
  SHASUM_BIN="$(resolve_tool "" sha256sum)"
fi
UNZIP_BIN="$(resolve_tool "$UNZIP_BIN" unzip)"
ZIPINFO_BIN="$(resolve_tool "$ZIPINFO_BIN" zipinfo)"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ios-release-validation.XXXXXX" 2>/dev/null || \
  mktemp -d 2>/dev/null)" || fail temporary_directory_unavailable
require_directory "$TMP_ROOT" temporary_directory_unavailable

validate_archive_info
find_archive_app
validate_app "$ARCHIVE_APP_PATH"
ARCHIVE_APP_SHA256="$CURRENT_APP_SHA256"
ARCHIVE_EXECUTABLE_SHA256="$CURRENT_EXECUTABLE_SHA256"
ARCHIVE_EXECUTABLE_CONTENT_SHA256="$CURRENT_EXECUTABLE_CONTENT_SHA256"
ARCHIVE_EXECUTABLE_NAME="$CURRENT_EXECUTABLE_NAME"

if [[ -n "$IPA_PATH" ]]; then
  validate_ipa "$IPA_PATH"
fi

printf 'ios-release-validation=PASS\n'
printf 'archive_info_sha256=%s\n' "$ARCHIVE_INFO_SHA256"
printf 'archive_app_sha256=%s\n' "$ARCHIVE_APP_SHA256"
printf 'archive_executable_sha256=%s\n' "$ARCHIVE_EXECUTABLE_SHA256"
printf 'archive_executable_content_sha256=%s\n' \
  "$ARCHIVE_EXECUTABLE_CONTENT_SHA256"
if [[ -n "$IPA_PATH" ]]; then
  printf 'ipa_sha256=%s\n' "$IPA_FILE_SHA256"
  printf 'ipa_app_sha256=%s\n' "$IPA_APP_SHA256"
  printf 'ipa_executable_sha256=%s\n' "$IPA_EXECUTABLE_SHA256"
  printf 'ipa_executable_content_sha256=%s\n' \
    "$IPA_EXECUTABLE_CONTENT_SHA256"
fi
