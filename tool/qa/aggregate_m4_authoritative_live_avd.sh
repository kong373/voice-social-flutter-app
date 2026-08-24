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
[[ -d "$ARTIFACT_ROOT" ]] || {
  printf 'QA_ARTIFACT_ROOT does not exist\n' >&2
  exit 64
}

reasons=()
avd_results=()

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
  [[ -s "$file" ]] || return 1
  python3 - "$file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    payload = json.load(stream)
if not isinstance(payload, dict):
    raise SystemExit(1)
if payload.get("status") != "OK":
    raise SystemExit(1)
if not isinstance(payload.get("writeCounters"), dict) or not payload["writeCounters"]:
    raise SystemExit(1)
if not isinstance(payload.get("authorityInvariants"), dict) or not payload["authorityInvariants"]:
    raise SystemExit(1)
if payload.get("providerCalls") not in (0, False, "0"):
    raise SystemExit(1)
if payload.get("secrets") is not False:
    raise SystemExit(1)
# The endpoint is an aggregate-only evidence contract.  It must not return
# row-level data, credentials, or arbitrary fields that can smuggle PII.
if set(payload) != {"status", "writeCounters", "authorityInvariants", "providerCalls", "secrets"}:
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
  [[ -f "$result" ]] || { add_reason "$avd:result_missing"; return; }
  [[ "$(field "$result" result)" == PASS ]] || { add_reason "$avd:result_not_pass"; return; }
  [[ "$(field "$result" acceptance_status)" == PASS ]] || { add_reason "$avd:acceptance_not_pass"; return; }
  [[ "$(field "$result" run_id)" == "$EXPECTED_RUN_ID" ]] || add_reason "$avd:run_id_mismatch"
  [[ "$(field "$result" tested_git_sha)" == "$EXPECTED_FLUTTER_SHA" ]] || add_reason "$avd:tested_git_sha_mismatch"
  [[ "$(field "$result" flutter_sha)" == "$EXPECTED_FLUTTER_SHA" ]] || add_reason "$avd:flutter_sha_mismatch"
  [[ "$(field "$result" backend_sha)" == "$EXPECTED_BACKEND_SHA" ]] || add_reason "$avd:backend_sha_mismatch"
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
  validate_db_evidence "$dir/db-evidence.json" || add_reason "$avd:db_evidence_contract_invalid"
  avd_results+=("$avd=PASS")
}

validate_avd AVD-A
validate_avd AVD-B

conclusion='ANDROID_EMULATOR_PASS'
if ((${#reasons[@]} > 0)) || ((${#avd_results[@]} != 2)); then
  conclusion='ANDROID_EMULATOR_FAIL'
fi

python3 - "$AGGREGATE_JSON" "$conclusion" "$EXPECTED_FLUTTER_SHA" "$EXPECTED_BACKEND_SHA" "${reasons[*]-}" <<'PY'
import json
import sys

path, conclusion, flutter_sha, backend_sha, raw_reasons = sys.argv[1:]
reasons = [item for item in raw_reasons.splitlines() if item]
payload = {
    "conclusion": conclusion,
    "tested_git_sha": flutter_sha,
    "backend_sha": backend_sha,
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
  printf 'tested_git_sha=%s\nbackend_sha=%s\n' "$EXPECTED_FLUTTER_SHA" "$EXPECTED_BACKEND_SHA"
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
