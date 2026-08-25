#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

# This is the only script allowed to turn two per-AVD M4 results into a live
# aggregate verdict.  It is intentionally strict: missing, stale, partial,
# or provider-tainted evidence is a failure, never a fallback to an older run.

required() {
  local name="$1"
  local value
  value="$(printenv "$name" || true)"
  [[ -n "$value" ]] || {
    printf '%s is required\n' "$name" >&2
    exit 64
  }
  printf '%s' "$value"
}

readonly ARTIFACT_ROOT="$(required QA_ARTIFACT_ROOT)"
readonly EXPECTED_FLUTTER_SHA="$(required QA_FLUTTER_SHA)"
readonly EXPECTED_BACKEND_SHA="$(required QA_BACKEND_SHA)"
readonly EXPECTED_RUN_ID="$(required QA_RUN_ID)"
readonly EXPECTED_FIXTURE_ID="$(required QA_M4_FIXTURE_ID)"
readonly EXPECTED_FIXTURE_STATUS="$(required QA_M4_FIXTURE_STATUS)"
readonly EXPECTED_FLUTTER_VERSION='3.44.7'
readonly EXPECTED_DART_VERSION='3.12.2'
readonly EXPECTED_FLUTTER_REVISION='84fc5cbb223bc12f83d65b647ff8a56caf779ffd'
readonly AGGREGATE_TEXT="$ARTIFACT_ROOT/aggregate-verdict.txt"
readonly AGGREGATE_JSON="$ARTIFACT_ROOT/aggregate-verdict.json"

[[ "$EXPECTED_FLUTTER_SHA" =~ ^[0-9a-f]{40}$ ]] || {
  printf 'QA_FLUTTER_SHA must be a 40-character lowercase commit SHA\n' >&2
  exit 64
}
[[ "$EXPECTED_BACKEND_SHA" =~ ^[0-9a-f]{40}$ ]] || {
  printf 'QA_BACKEND_SHA must be a 40-character lowercase commit SHA\n' >&2
  exit 64
}
[[ "$EXPECTED_RUN_ID" =~ ^[A-Za-z0-9_.:-]{1,80}$ ]] || {
  printf 'QA_RUN_ID contains unsafe characters\n' >&2
  exit 64
}
[[ "$EXPECTED_FIXTURE_ID" =~ ^m4-fresh-[A-Za-z0-9_.:-]{1,64}$ ]] || {
  printf 'QA_M4_FIXTURE_ID must identify a fresh M4 fixture\n' >&2
  exit 64
}
[[ "$EXPECTED_FIXTURE_STATUS" == 'fresh_dedicated' ]] || {
  printf 'QA_M4_FIXTURE_STATUS must be fresh_dedicated\n' >&2
  exit 64
}
[[ -d "$ARTIFACT_ROOT" ]] || {
  printf 'QA_ARTIFACT_ROOT does not exist\n' >&2
  exit 64
}

reasons=()
avd_results=()
android_host_source_sha256=''

field() {
  local file="$1"
  local name="$2"
  sed -n "s/^${name}=//p" "$file" | head -n 1
}

add_reason() {
  reasons+=("$1")
}

validate_db_evidence() {
  local file="$1"
  local avd="$2"
  local expected_nonce="$3"
  [[ -s "$file" ]] || return 1
  python3 - "$file" "$avd" "$expected_nonce" "$EXPECTED_RUN_ID" "$EXPECTED_FIXTURE_ID" <<'PY'
import json
import sys

path, expected_avd, expected_nonce, expected_run_id, expected_fixture_id = sys.argv[1:]
with open(path, encoding="utf-8") as stream:
    payload = json.load(stream)
if not isinstance(payload, dict):
    raise SystemExit(1)
required_counter_keys = {
    "auth_sessions",
    "room_activity",
    "commerce_activity",
    "social_community_messages",
    "social_user_reports",
    "idempotency_audit",
}
required_scoped_counter_keys = {
    "refresh_session_user",
    "user_report_reporter",
    "operation_idempotency_actor",
}
required_invariant_keys = {
    "core_schema_present",
    "provider_outbox_allowed_states",
    "provider_outbox_attempts_zero",
    "private_message_delivery_blocked",
    "adapter_status_projection_blocked",
    "backend_environment_development",
    "backend_profile_development",
    "development_outbox_or_blocked_sms",
    "formal_vendor_adapters_blocked",
    "provider_invocation_rows_zero",
    "first_party_writes_observed_since_start",
    "expected_backend_sha_matches",
}
if set(payload) != {
    "status",
    "writeCounters",
    "authorityInvariants",
    "providerCalls",
    "secrets",
    "evidenceBinding",
    "scopedCounters",
}:
    raise SystemExit(1)
if payload.get("status") != "OK":
    raise SystemExit(1)
if not isinstance(payload.get("writeCounters"), dict):
    raise SystemExit(1)
if set(payload["writeCounters"]) != required_counter_keys:
    raise SystemExit(1)
if any(type(value) is not int or value < 0 for value in payload["writeCounters"].values()):
    raise SystemExit(1)
if sum(payload["writeCounters"].values()) <= 0:
    raise SystemExit(1)
if payload["writeCounters"]["social_user_reports"] <= 0:
    raise SystemExit(1)
if set(payload["scopedCounters"]) != required_scoped_counter_keys:
    raise SystemExit(1)
if any(type(value) is not int or value <= 0 for value in payload["scopedCounters"].values()):
    raise SystemExit(1)
if not isinstance(payload.get("authorityInvariants"), dict):
    raise SystemExit(1)
actual_invariant_keys = set(payload["authorityInvariants"])
if actual_invariant_keys != required_invariant_keys:
    raise SystemExit(1)
if payload["authorityInvariants"].get("first_party_writes_observed_since_start") is not True:
    raise SystemExit(1)
if any(value is not True for value in payload["authorityInvariants"].values()):
    raise SystemExit(1)
if payload.get("providerCalls") not in (0, False, "0"):
    raise SystemExit(1)
if payload.get("secrets") is not False:
    raise SystemExit(1)
binding = payload.get("evidenceBinding")
if not isinstance(binding, dict) or set(binding) != {
    "runId", "avd", "startNonce", "fixtureId", "fixtureAccountState", "mutationKeys"
}:
    raise SystemExit(1)
if binding["runId"] != expected_run_id or binding["avd"] != expected_avd:
    raise SystemExit(1)
if binding["startNonce"] != expected_nonce:
    raise SystemExit(1)
if binding["fixtureId"] != expected_fixture_id:
    raise SystemExit(1)
expected_fixture_state = (
    "created_during_run" if expected_avd == "AVD-A" else "preexisting_fixture"
)
if binding["fixtureAccountState"] != expected_fixture_state:
    raise SystemExit(1)
if binding["mutationKeys"] != [
    "auth_sessions",
    "room_activity",
    "commerce_activity",
    "social_community_messages",
    "social_user_reports",
    "idempotency_audit",
]:
    raise SystemExit(1)
PY
}

validate_log_evidence() {
  local dir="$1"
  local log="$dir/logs/flutter-drive.log"
  [[ -s "$log" ]] || return 1
  local acceptance_count provider_count provider_nonzero bad_status
  acceptance_count="$(grep -Ec '(^|[[:space:]])M4_ACCEPTANCE::PASS($|[[:space:]])' "$log" || true)"
  provider_count="$(grep -Ec '(^|[[:space:]])M4_PROVIDER_CALLS::0($|[[:space:]])' "$log" || true)"
  provider_nonzero="$(awk '/M4_PROVIDER_CALLS::/ && $0 !~ /M4_PROVIDER_CALLS::0([[:space:]]|$)/ {count += 1} END {print count + 0}' "$log")"
  bad_status="$(awk -F '::' '/M4_ROUTE_STATUS::/ {if ($5 !~ /^[2-4][0-9][0-9]$/) count += 1} END {print count + 0}' "$log")"
  [[ "$acceptance_count" -eq 1 ]] || return 1
  [[ "$provider_count" -eq 1 && "$provider_nonzero" -eq 0 ]] || return 1
  [[ "$bad_status" -eq 0 ]] || return 1
  [[ "$(grep -Ec '(^|[[:space:]])M4_ACCEPTANCE::FAIL($|[[:space:]])' "$log" || true)" -eq 0 ]] || return 1
  return 0
}

validate_avd() {
  local avd="$1"
  local dir="$ARTIFACT_ROOT/$avd"
  local result="$dir/result.txt"
  local avd_android_host_source_sha256
  [[ -f "$result" ]] || { add_reason "$avd:result_missing"; return; }
  [[ "$(field "$result" result)" == PASS ]] || { add_reason "$avd:result_not_pass"; return; }
  [[ "$(field "$result" acceptance_status)" == PASS ]] || { add_reason "$avd:acceptance_not_pass"; return; }
  [[ "$(field "$result" run_id)" == "$EXPECTED_RUN_ID" ]] || add_reason "$avd:run_id_mismatch"
  [[ "$(field "$result" fixture_id)" == "$EXPECTED_FIXTURE_ID" ]] || add_reason "$avd:fixture_id_mismatch"
  [[ "$(field "$result" fixture_status)" == "$EXPECTED_FIXTURE_STATUS" ]] || add_reason "$avd:fixture_status_mismatch"
  [[ "$(field "$result" db_start_nonce)" =~ ^[A-Za-z0-9_.~=-]{16,255}$ ]] || add_reason "$avd:db_start_nonce_missing"
  [[ "$(field "$result" tested_git_sha)" == "$EXPECTED_FLUTTER_SHA" ]] || add_reason "$avd:tested_git_sha_mismatch"
  [[ "$(field "$result" flutter_sha)" == "$EXPECTED_FLUTTER_SHA" ]] || add_reason "$avd:flutter_sha_mismatch"
  [[ "$(field "$result" backend_sha)" == "$EXPECTED_BACKEND_SHA" ]] || add_reason "$avd:backend_sha_mismatch"
  [[ "$(field "$result" flutter_version)" == "$EXPECTED_FLUTTER_VERSION" ]] || add_reason "$avd:flutter_version_mismatch"
  [[ "$(field "$result" dart_version)" == "$EXPECTED_DART_VERSION" ]] || add_reason "$avd:dart_version_mismatch"
  [[ "$(field "$result" flutter_revision)" == "$EXPECTED_FLUTTER_REVISION" ]] || add_reason "$avd:flutter_revision_mismatch"
  avd_android_host_source_sha256="$(field "$result" android_host_source_sha256)"
  if [[ ! "$avd_android_host_source_sha256" =~ ^[0-9a-f]{64}$ ]]; then
    add_reason "$avd:android_host_source_attestation_missing"
  elif [[ -z "$android_host_source_sha256" ]]; then
    android_host_source_sha256="$avd_android_host_source_sha256"
  elif [[ "$avd_android_host_source_sha256" != "$android_host_source_sha256" ]]; then
    add_reason "$avd:android_host_source_attestation_mismatch"
  fi
  [[ "$(field "$result" provider_calls_made)" == false ]] || add_reason "$avd:provider_calls_not_zero"
  [[ "$(field "$result" db_evidence)" == COLLECTED ]] || add_reason "$avd:db_evidence_not_collected"
  [[ "$(field "$result" secret_scan)" == PASS ]] || add_reason "$avd:secret_scan_not_pass"
  [[ "$(field "$result" apk_secret_scan)" == PASS ]] || add_reason "$avd:apk_secret_scan_not_pass"
  [[ "$(field "$result" hard_finding_count)" == 0 ]] || add_reason "$avd:hard_findings_nonzero"
  [[ "$(field "$result" crash_anr_count)" == 0 ]] || add_reason "$avd:crash_or_anr_nonzero"
  [[ "$(field "$result" screenshot_count)" =~ ^[0-9]+$ && "$(field "$result" screenshot_count)" -ge 4 ]] || add_reason "$avd:screenshots_missing"
  [[ "$(field "$result" http_route_marker_count)" =~ ^[0-9]+$ && "$(field "$result" http_route_marker_count)" -ge 10 ]] || add_reason "$avd:route_evidence_missing"
  [[ "$(field "$result" authority_invariant_count)" =~ ^[0-9]+$ && "$(field "$result" authority_invariant_count)" -ge 5 ]] || add_reason "$avd:authority_evidence_missing"
  [[ -s "$dir/http-route-coverage.csv" ]] || add_reason "$avd:route_csv_missing"
  [[ -s "$dir/authority-invariants.txt" ]] || add_reason "$avd:authority_invariants_missing"
  [[ -s "$dir/db-write-counters.txt" ]] || add_reason "$avd:db_write_counters_missing"
  [[ -f "$dir/logs/flutter-errors.txt" && ! -s "$dir/logs/flutter-errors.txt" ]] || add_reason "$avd:flutter_error_log_not_clean"
  [[ -f "$dir/logs/crash-anr.txt" && ! -s "$dir/logs/crash-anr.txt" ]] || add_reason "$avd:crash_anr_log_not_clean"
  validate_log_evidence "$dir" || add_reason "$avd:log_evidence_not_strict"
  validate_db_evidence "$dir/db-evidence.json" "$avd" "$(field "$result" db_start_nonce)" || add_reason "$avd:db_evidence_contract_invalid"
  avd_results+=("$avd=PASS")
}

validate_avd AVD-A
validate_avd AVD-B

conclusion='ANDROID_EMULATOR_PASS'
if ((${#reasons[@]} > 0)) || ((${#avd_results[@]} != 2)); then
  conclusion='ANDROID_EMULATOR_FAIL'
fi

python3 - "$AGGREGATE_JSON" "$conclusion" "$EXPECTED_FLUTTER_SHA" "$EXPECTED_BACKEND_SHA" "$android_host_source_sha256" "$EXPECTED_FLUTTER_VERSION" "$EXPECTED_DART_VERSION" "$EXPECTED_FLUTTER_REVISION" "$EXPECTED_RUN_ID" "$EXPECTED_FIXTURE_ID" "$EXPECTED_FIXTURE_STATUS" "${reasons[*]-}" <<'PY'
import json
import sys

path, conclusion, flutter_sha, backend_sha, android_host_source_sha256, flutter_version, dart_version, flutter_revision, run_id, fixture_id, fixture_status, raw_reasons = sys.argv[1:]
reasons = [item for item in raw_reasons.splitlines() if item]
payload = {
    "conclusion": conclusion,
    "tested_git_sha": flutter_sha,
    "backend_sha": backend_sha,
    "android_host_source_sha256": android_host_source_sha256,
    "flutter_version": flutter_version,
    "dart_version": dart_version,
    "flutter_revision": flutter_revision,
    "run_id": run_id,
    "fixture_id": fixture_id,
    "fixture_status": fixture_status,
    "avd": {
        "AVD-A": "PASS" if not any(item.startswith("AVD-A:") for item in reasons) else "FAIL",
        "AVD-B": "PASS" if not any(item.startswith("AVD-B:") for item in reasons) else "FAIL",
    },
    "reasons": reasons,
    "providerCalls": 0,
    "secrets": False,
}
with open(path, "w", encoding="utf-8") as stream:
    json.dump(payload, stream, ensure_ascii=False, sort_keys=True, indent=2)
    stream.write("\n")
PY

{
  printf 'M4 authoritative live AVD aggregate\n'
  printf 'conclusion=%s\n' "$conclusion"
  printf 'run_id=%s\nfixture_id=%s\nfixture_status=%s\n' "$EXPECTED_RUN_ID" "$EXPECTED_FIXTURE_ID" "$EXPECTED_FIXTURE_STATUS"
  printf 'tested_git_sha=%s\nbackend_sha=%s\n' "$EXPECTED_FLUTTER_SHA" "$EXPECTED_BACKEND_SHA"
  printf 'android_host_source_sha256=%s\n' "$android_host_source_sha256"
  printf 'flutter_version=%s\ndart_version=%s\nflutter_revision=%s\n' \
    "$EXPECTED_FLUTTER_VERSION" "$EXPECTED_DART_VERSION" "$EXPECTED_FLUTTER_REVISION"
  printf 'AVD-A=%s\nAVD-B=%s\n' \
    "$(if printf '%s\n' "${reasons[@]-}" | grep -q '^AVD-A:'; then printf FAIL; else printf PASS; fi)" \
    "$(if printf '%s\n' "${reasons[@]-}" | grep -q '^AVD-B:'; then printf FAIL; else printf PASS; fi)"
  printf 'providerCalls=0\nsecrets=false\n'
  if ((${#reasons[@]} > 0)); then
    printf 'reasons=%s\n' "$(IFS=';'; printf '%s' "${reasons[*]}")"
  fi
} >"$AGGREGATE_TEXT"

if [[ "$conclusion" != ANDROID_EMULATOR_PASS ]]; then
  printf '%s\n' "M4 aggregate failed; see $AGGREGATE_TEXT" >&2
  exit 1
fi
printf '%s\n' "M4 aggregate PASS: both AVDs and both candidate SHAs matched."
