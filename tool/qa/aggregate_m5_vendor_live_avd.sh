#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

# M5 aggregation accepts only two complete provider-live AVD runs. A legacy
# zero-provider result is never interpreted as a provider PASS here.
env_value() { printenv "$1" || true; }
is_true() { [[ "${1:-}" == 'true' || "${1:-}" == '1' || "${1:-}" == 'yes' ]]; }
required() {
  local value
  value="$(env_value "$1")"
  [[ -n "$value" ]] || { printf '%s is required\n' "$1" >&2; exit 64; }
  printf '%s' "$value"
}

readonly ARTIFACT_ROOT="$(required QA_ARTIFACT_ROOT)"
readonly EXPECTED_FLUTTER_SHA="$(required QA_FLUTTER_SHA)"
readonly EXPECTED_BACKEND_SHA="$(required QA_BACKEND_SHA)"
readonly EXPECTED_BACKEND_DIGEST="$(required QA_BACKEND_DIGEST)"
readonly EXPECTED_RUN_ID="$(required QA_M5_RUN_ID)"
readonly EXPECTED_FIXTURE_ID="$(required QA_M5_FIXTURE_ID)"
readonly PAYMENT_OPT_IN="$(is_true "$(env_value QA_M5_ALLOW_EXTERNAL_PAYMENT)" && printf true || printf false)"
readonly PAYMENT_SCENARIO_RAW="$(env_value QA_M5_ALIPAY_SCENARIO)"
readonly PAYMENT_SCENARIO="${PAYMENT_SCENARIO_RAW:-none}"
readonly PAYMENT_SUCCESS_CONFIRMATION="$(env_value QA_M5_SUCCESS_CONFIRMATION)"
readonly PAYMENT_CANCEL_ONLY="$([[ "$PAYMENT_OPT_IN" == true && "$PAYMENT_SCENARIO" == cancel ]] && printf true || printf false)"
readonly PAYMENT_SUCCESS="$([[ "$PAYMENT_OPT_IN" == true && "$PAYMENT_SCENARIO" == success ]] && printf true || printf false)"
readonly AGGREGATE_TEXT="$ARTIFACT_ROOT/aggregate-verdict.txt"
readonly AGGREGATE_JSON="$ARTIFACT_ROOT/aggregate-verdict.json"
readonly EXPECTED_FLUTTER_VERSION='3.44.7'
readonly EXPECTED_DART_VERSION='3.12.2'
readonly EXPECTED_FLUTTER_REVISION='84fc5cbb223bc12f83d65b647ff8a56caf779ffd'

[[ "$EXPECTED_FLUTTER_SHA" =~ ^[0-9a-f]{40}$ ]] || { printf 'invalid QA_FLUTTER_SHA\n' >&2; exit 64; }
[[ "$EXPECTED_BACKEND_SHA" =~ ^[0-9a-f]{40}$ ]] || { printf 'invalid QA_BACKEND_SHA\n' >&2; exit 64; }
[[ "$EXPECTED_BACKEND_DIGEST" =~ ^[0-9a-f]{64}$ ]] || { printf 'invalid QA_BACKEND_DIGEST\n' >&2; exit 64; }
[[ "$EXPECTED_RUN_ID" =~ ^[A-Za-z0-9_.:-]{1,80}$ ]] || { printf 'invalid QA_M5_RUN_ID\n' >&2; exit 64; }
[[ "$EXPECTED_FIXTURE_ID" =~ ^m5-fresh-[A-Za-z0-9_.:-]{1,64}$ ]] || { printf 'invalid QA_M5_FIXTURE_ID\n' >&2; exit 64; }
[[ -d "$ARTIFACT_ROOT" ]] || { printf 'QA_ARTIFACT_ROOT does not exist\n' >&2; exit 64; }

declare -a REASONS=()
AVD_A_RESULT=''
AVD_B_RESULT=''
AVD_A_APK_SHA=''
AVD_B_APK_SHA=''
AVD_A_TENCENT_CALLS=0
AVD_B_TENCENT_CALLS=0
AVD_A_ALIPAY_CALLS=0
AVD_B_ALIPAY_CALLS=0
ANDROID_HOST_SHA=''

add_reason() { REASONS+=("$1"); }
field() {
  local file="$1" name="$2"
  sed -n "s/^${name}=//p" "$file" 2>/dev/null | head -n 1
}

validate_log() {
  local dir="$1" log="$1/logs/flutter-drive.log"
  [[ -s "$log" ]] || return 1
  [[ "$(grep -Ec '^M5_ACCEPTANCE::(PASS|NO_PAY|PARTIAL|FAIL)$' "$log" || true)" -eq 1 ]] || return 1
  [[ "$(grep -Ec '^M5_ACCEPTANCE::FAIL$' "$log" || true)" -eq 0 ]] || return 1
  if [[ "$PAYMENT_OPT_IN" == 'true' ]]; then
    if [[ "$PAYMENT_CANCEL_ONLY" == 'true' ]]; then
      # Cancel-only is an intentionally non-successful financial verdict: the
      # SDK callback and authoritative canceled query are evidence, not proof
      # of a completed payment.
      [[ "$(grep -Ec '^M5_ACCEPTANCE::PARTIAL$' "$log" || true)" -eq 1 ]] || return 1
    else
      [[ "$(grep -Ec '^M5_ACCEPTANCE::PASS$' "$log" || true)" -eq 1 ]] || return 1
    fi
    if [[ "${dir##*/}" == 'AVD-A' ]]; then
      [[ "$(grep -Ec '^M5_PROVIDER_CALLS::[1-9][0-9]*::[1-9][0-9]*$' "$log" || true)" -eq 1 ]] || return 1
    else
      [[ "$(grep -Ec '^M5_PROVIDER_CALLS::[1-9][0-9]*::0$' "$log" || true)" -eq 1 ]] || return 1
    fi
  else
    [[ "$(grep -Ec '^M5_ACCEPTANCE::(NO_PAY|PARTIAL)$' "$log" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Ec '^M5_PROVIDER_CALLS::[0-9]+::[0-9]+$' "$log" || true)" -eq 1 ]] || return 1
    if [[ "$(grep -Ec '^M5_PROVIDER_CALLS::[1-9][0-9]*::[0-9]+$' "$log" || true)" -gt 0 ]]; then
      [[ "$(grep -Ec '^M5_VENDOR_EVENT::[^:]+::[^:]+::sdk_callback$' "$log" || true)" -gt 0 ]] || return 1
    fi
  fi
  if [[ "$(grep -Ec '^M5_VENDOR_EVENT::tencent-im::[^:]+::sdk_callback$' "$log" || true)" -gt 0 ]]; then
    :
  else
    return 1
  fi
  if [[ "$PAYMENT_OPT_IN" == 'true' ]]; then
    if [[ "$PAYMENT_CANCEL_ONLY" == 'true' ]]; then
      if [[ "${dir##*/}" == 'AVD-A' ]]; then
        # The native cancellation callback is the only Alipay provider event
        # required here. An async notify callback is intentionally not required
        # and would be suspicious for an unpaid cancellation.
        [[ "$(grep -Ec '^M5_VENDOR_EVENT::alipay::launch_cancel::sdk_callback$' "$log" || true)" -eq 1 ]] || return 1
      else
        # AVD-B is receiver-only for every payment scenario and must not emit
        # even a cancellation callback.
        [[ "$(grep -Ec '^M5_VENDOR_EVENT::alipay::[^:]+::sdk_callback$' "$log" || true)" -eq 0 ]] || return 1
      fi
    else
      if [[ "${dir##*/}" == 'AVD-A' ]]; then
        [[ "$(grep -Ec '^M5_VENDOR_EVENT::alipay::launch_success::sdk_callback$' "$log" || true)" -eq 1 ]] || return 1
      else
        [[ "$(grep -Ec '^M5_VENDOR_EVENT::alipay::[^:]+::sdk_callback$' "$log" || true)" -eq 0 ]] || return 1
      fi
    fi
  fi
  [[ "$(grep -Ec '^M5_SECRETS_IN_CLIENT::0$' "$log" || true)" -eq 1 ]] || return 1
  [[ "$(grep -Ec '^M5_ROUTE_STATUS::[^:]+::[^:]+::[^:]+::[2-4][0-9][0-9]::' "$log" || true)" -gt 0 ]] || return 1
  ! grep -Eq '^M[234]_.*::' "$log"
}

validate_lanes() {
  local dir="$1"
  local -a core_lanes=(
    'tencent.credential' 'tencent.login' 'tencent.c2c.http-authority'
    'tencent.avchatroom.hint' 'tencent.avchatroom.leave' 'alipay.catalog'
  )
  local lane state
  for lane in "${core_lanes[@]}"; do
    state="$(awk -F '::' -v wanted="$lane" '$1 == "M5_LANE" && $2 == wanted {value=$3} END {print value}' "$dir/logs/flutter-drive.log" 2>/dev/null)"
    if [[ "$PAYMENT_OPT_IN" == 'true' ]]; then
      [[ "$state" == 'PASS' ]] || add_reason "${dir##*/}:lane_${lane}_not_pass"
    elif [[ "$lane" == tencent.* ]]; then
      # NO_PAY is still a Tencent core-provider verdict. Missing credentials,
      # an SDK block, or a client-only intent must remain PARTIAL/FAIL.
      [[ "$state" == 'PASS' ]] || add_reason "${dir##*/}:lane_${lane}_not_pass"
    else
      [[ "$state" == 'PASS' || "$state" == 'BLOCKED' || "$state" == 'FAIL' || "$state" == 'NOT_RUN' ]] || add_reason "${dir##*/}:lane_${lane}_missing_verdict"
    fi
  done
  state="$(awk -F '::' '$1 == "M5_LANE" && $2 == "tencent.outage.fallback" {value=$3} END {print value}' "$dir/logs/flutter-drive.log" 2>/dev/null)"
  [[ "$state" == 'PASS' || "$state" == 'NOT_RUN' || "$state" == 'BLOCKED' ]] || add_reason "${dir##*/}:resilience_verdict_invalid"
  if [[ "$PAYMENT_OPT_IN" == 'true' ]]; then
    if [[ "${dir##*/}" == 'AVD-A' ]]; then
      if [[ "$PAYMENT_CANCEL_ONLY" == 'true' ]]; then
        for lane in 'alipay.order' 'alipay.native.launch-cancel' 'alipay.query-reconcile'; do
          state="$(awk -F '::' -v wanted="$lane" '$1 == "M5_LANE" && $2 == wanted {value=$3} END {print value}' "$dir/logs/flutter-drive.log" 2>/dev/null)"
          [[ "$state" == 'PASS' ]] || add_reason "${dir##*/}:lane_${lane}_not_pass"
        done
      else
        for lane in 'alipay.order' 'alipay.native.launch-success' 'alipay.query-reconcile' 'alipay.settlement' 'alipay.reconcile-idempotency'; do
          state="$(awk -F '::' -v wanted="$lane" '$1 == "M5_LANE" && $2 == wanted {value=$3} END {print value}' "$dir/logs/flutter-drive.log" 2>/dev/null)"
          [[ "$state" == 'PASS' ]] || add_reason "${dir##*/}:lane_${lane}_not_pass"
        done
      fi
    else
      # AVD-B is receiver-only and must not create an order or call the
      # native payment SDK, even when the success lane is enabled globally.
      for lane in 'alipay.order' 'alipay.native.launch-cancel' 'alipay.native.launch-success' 'alipay.query-reconcile' 'alipay.settlement' 'alipay.reconcile-idempotency'; do
        state="$(awk -F '::' -v wanted="$lane" '$1 == "M5_LANE" && $2 == wanted {value=$3} END {print value}' "$dir/logs/flutter-drive.log" 2>/dev/null)"
        [[ "$state" == 'NOT_RUN' ]] || add_reason "${dir##*/}:payment_lane_must_be_not_run_${lane}"
      done
    fi
  else
    for lane in 'alipay.order' 'alipay.native.launch-cancel' 'alipay.native.launch-success' 'alipay.query-reconcile' 'alipay.settlement' 'alipay.reconcile-idempotency'; do
      state="$(awk -F '::' -v wanted="$lane" '$1 == "M5_LANE" && $2 == wanted {value=$3} END {print value}' "$dir/logs/flutter-drive.log" 2>/dev/null)"
      [[ "$state" == 'NOT_OPTED_IN' || "$state" == 'NOT_RUN' || "$state" == 'BLOCKED' ]] || add_reason "${dir##*/}:payment_lane_not_explicitly_withheld_${lane}"
    done
  fi
}

validate_db_evidence() {
  local file="$1" avd="$2" expected_nonce="$3" apk_sha="$4" result_value="$5"
  [[ -s "$file" ]] || return 1
  python3 - "$file" "$avd" "$expected_nonce" "$EXPECTED_RUN_ID" "$EXPECTED_FIXTURE_ID" "$EXPECTED_BACKEND_SHA" "$EXPECTED_FLUTTER_SHA" "$apk_sha" "$EXPECTED_BACKEND_DIGEST" "$PAYMENT_OPT_IN" "$PAYMENT_CANCEL_ONLY" "$PAYMENT_SUCCESS" "$result_value" <<'PY'
import json
import sys

path, expected_avd, expected_nonce, expected_run_id, expected_fixture, expected_backend_sha, expected_flutter_sha, expected_apk_sha, expected_digest, payment_opt_in, payment_cancel_only, payment_success, result_value = sys.argv[1:]
with open(path, encoding="utf-8") as stream:
    payload = json.load(stream)
required = {"status", "evidenceBinding", "writeCounters", "vendorOutbox", "callbackEvents", "outboxAttempts", "paymentSettlement", "secrets", "backendSourceDigest"}
if not isinstance(payload, dict) or set(payload) != required:
    raise SystemExit(1)
if payload.get("status") != "OK" or payload.get("secrets") is not False:
    raise SystemExit(1)
binding = payload.get("evidenceBinding")
if (not isinstance(binding, dict) or set(binding) != {"runId", "avd", "fixtureId", "startNonce", "backendSha", "flutterSha", "apkSha", "backendSourceDigest"} or
    binding.get("runId") != expected_run_id or binding.get("avd") != expected_avd or
    binding.get("fixtureId") != expected_fixture or binding.get("startNonce") != expected_nonce or
    binding.get("backendSha") != expected_backend_sha or binding.get("flutterSha") != expected_flutter_sha or
    binding.get("apkSha") != expected_apk_sha or binding.get("backendSourceDigest") != expected_digest):
    raise SystemExit(1)
counters = payload.get("writeCounters")
counter_keys = {"auth_sessions", "im_credentials", "c2c_messages", "avchatroom_sessions", "alipay_orders", "payment_provider_events", "wallet_transactions", "ledger_journals", "ledger_entries"}
if (not isinstance(counters, dict) or set(counters) != counter_keys or
    any(type(value) is not int or value < 0 for value in counters.values())):
    raise SystemExit(1)
settlement = payload.get("paymentSettlement")
settlement_keys = {"providerEventVerified", "providerEventProcessedCount", "succeededOrderCount", "walletTransactionCount", "walletCreditCount", "ledgerJournalCount", "ledgerEntryCount", "balancedJournalCount", "ledgerImbalanceCount"}
if (not isinstance(settlement, dict) or set(settlement) != settlement_keys or
    type(settlement["providerEventVerified"]) is not bool or
    any(type(settlement[key]) is not int or settlement[key] < 0 for key in settlement_keys - {"providerEventVerified"})):
    raise SystemExit(1)
for key in ("tencentIm", "alipay"):
    outbox = payload.get("vendorOutbox", {}).get(key)
    callback = payload.get("callbackEvents", {}).get(key)
    if (not isinstance(outbox, dict) or set(outbox) != {"state", "attempts"} or
        not isinstance(outbox["state"], str) or type(outbox["attempts"]) is not int or outbox["attempts"] < 0 or
        not isinstance(callback, dict) or set(callback) != {"verified", "eventCount"} or
        type(callback["verified"]) is not bool or type(callback["eventCount"]) is not int or callback["eventCount"] < 0):
        raise SystemExit(1)
attempts = payload.get("outboxAttempts")
if (not isinstance(attempts, dict) or set(attempts) != {"tencentIm", "alipay"} or
    any(type(value) is not int or value < 0 for value in attempts.values()) or
    (payment_cancel_only == "true" and expected_avd == "AVD-A" and counters["alipay_orders"] != 1) or
    (payment_cancel_only == "true" and expected_avd == "AVD-A" and counters["payment_provider_events"] != 0) or
    (payment_cancel_only == "true" and expected_avd == "AVD-A" and counters["wallet_transactions"] != 0) or
    (payment_cancel_only == "true" and expected_avd == "AVD-A" and counters["ledger_journals"] != 0) or
    (payment_cancel_only == "true" and expected_avd == "AVD-A" and counters["ledger_entries"] != 0) or
    (payment_cancel_only == "true" and expected_avd == "AVD-A" and payload["vendorOutbox"]["alipay"]["attempts"] < 1) or
    (payment_cancel_only == "true" and
     (payload["callbackEvents"]["alipay"]["verified"] is not False or
      payload["callbackEvents"]["alipay"]["eventCount"] != 0))):
    raise SystemExit(1)
if payment_success == "true":
    if expected_avd == "AVD-A":
        expected_settlement = {
            "providerEventVerified": True,
            "providerEventProcessedCount": 1,
            "succeededOrderCount": 1,
            "walletTransactionCount": 1,
            "walletCreditCount": 1,
            "ledgerJournalCount": 1,
            "ledgerEntryCount": 2,
            "balancedJournalCount": 1,
            "ledgerImbalanceCount": 0,
        }
        if settlement != expected_settlement or counters["alipay_orders"] != 1 or counters["payment_provider_events"] != 1 or counters["wallet_transactions"] != 1 or counters["ledger_journals"] != 1 or counters["ledger_entries"] != 2:
            raise SystemExit(1)
        if payload["callbackEvents"]["alipay"] != {"verified": True, "eventCount": 1}:
            raise SystemExit(1)
        if payload["vendorOutbox"]["alipay"]["attempts"] < 1 or attempts["alipay"] < 1:
            raise SystemExit(1)
    else:
        if any(counters[key] != 0 for key in ("alipay_orders", "payment_provider_events", "wallet_transactions", "ledger_journals", "ledger_entries")):
            raise SystemExit(1)
        if any(settlement[key] != 0 for key in settlement_keys - {"providerEventVerified"}) or settlement["providerEventVerified"]:
            raise SystemExit(1)
        if payload["callbackEvents"]["alipay"] != {"verified": False, "eventCount": 0} or payload["vendorOutbox"]["alipay"]["attempts"] != 0:
            raise SystemExit(1)
elif payment_opt_in != "true" or expected_avd == "AVD-B":
    if any(counters[key] != 0 for key in ("alipay_orders", "payment_provider_events", "wallet_transactions", "ledger_journals", "ledger_entries")):
        raise SystemExit(1)
    if any(settlement[key] != 0 for key in settlement_keys - {"providerEventVerified"}) or settlement["providerEventVerified"]:
        raise SystemExit(1)
for key in ("tencentIm", "alipay"):
    callback = payload["callbackEvents"][key]
    if ((key == "tencentIm") or
        (key == "alipay" and payment_success == "true" and expected_avd == "AVD-A")):
        if callback["verified"] is not True or callback["eventCount"] < 1:
            raise SystemExit(1)
if payload.get("backendSourceDigest") != expected_digest:
    raise SystemExit(1)
PY
}

validate_avd() {
  local avd="$1" dir="$ARTIFACT_ROOT/$1" result="$ARTIFACT_ROOT/$1/result.txt"
  local apk_sha host_sha provider_line tencent_calls alipay_calls nonce result_value acceptance_value
  [[ -f "$result" ]] || { add_reason "$avd:result_missing"; return; }
  result_value="$(field "$result" result)"
  acceptance_value="$(field "$result" acceptance_status)"
  if [[ "$PAYMENT_OPT_IN" == 'true' ]]; then
    if [[ "$PAYMENT_CANCEL_ONLY" == 'true' ]]; then
      [[ "$result_value" == PARTIAL ]] || add_reason "$avd:cancel_only_result_not_partial"
      [[ "$acceptance_value" == PARTIAL ]] || add_reason "$avd:cancel_only_acceptance_not_partial"
    else
      [[ "$result_value" == PASS ]] || add_reason "$avd:result_not_pass"
      [[ "$acceptance_value" == PASS ]] || add_reason "$avd:acceptance_not_pass"
    fi
  else
    [[ "$result_value" == NO_PAY || "$result_value" == PARTIAL ]] || add_reason "$avd:result_not_explicit_no_pay_or_partial"
    [[ "$acceptance_value" == NO_PAY || "$acceptance_value" == PARTIAL ]] || add_reason "$avd:acceptance_not_explicit_no_pay_or_partial"
  fi
  [[ "$(field "$result" run_id)" == "$EXPECTED_RUN_ID" ]] || add_reason "$avd:run_id_mismatch"
  [[ "$(field "$result" fixture_id)" == "$EXPECTED_FIXTURE_ID" ]] || add_reason "$avd:fixture_id_mismatch"
  [[ "$(field "$result" tested_git_sha)" == "$EXPECTED_FLUTTER_SHA" ]] || add_reason "$avd:source_sha_mismatch"
  [[ "$(field "$result" backend_sha)" == "$EXPECTED_BACKEND_SHA" ]] || add_reason "$avd:backend_sha_mismatch"
  [[ "$(field "$result" backend_source_digest)" == "$EXPECTED_BACKEND_DIGEST" ]] || add_reason "$avd:backend_digest_mismatch"
  [[ "$(field "$result" flutter_version)" == "$EXPECTED_FLUTTER_VERSION" ]] || add_reason "$avd:flutter_version_mismatch"
  [[ "$(field "$result" dart_version)" == "$EXPECTED_DART_VERSION" ]] || add_reason "$avd:dart_version_mismatch"
  [[ "$(field "$result" flutter_revision)" == "$EXPECTED_FLUTTER_REVISION" ]] || add_reason "$avd:flutter_revision_mismatch"
  host_sha="$(field "$result" android_host_source_sha256)"
  if [[ "$host_sha" =~ ^[0-9a-f]{64}$ ]]; then
    if [[ -z "$ANDROID_HOST_SHA" ]]; then ANDROID_HOST_SHA="$host_sha"; elif [[ "$ANDROID_HOST_SHA" != "$host_sha" ]]; then add_reason "$avd:android_host_sha_mismatch"; fi
  else
    add_reason "$avd:android_host_sha_invalid"
  fi
  apk_sha="$(field "$result" apk_sha256)"
  if [[ "$apk_sha" =~ ^[0-9a-f]{64}$ ]]; then
    if [[ "$avd" == 'AVD-A' ]]; then AVD_A_APK_SHA="$apk_sha"; else AVD_B_APK_SHA="$apk_sha"; fi
  else
    add_reason "$avd:apk_sha_missing"
  fi
  [[ "$(field "$result" apk_attestation_sha256)" == "$apk_sha" ]] || add_reason "$avd:apk_attestation_mismatch"
  [[ "$(field "$result" resilience_verdict)" == 'PASS' || "$(field "$result" resilience_verdict)" == 'NOT_RUN' || "$(field "$result" resilience_verdict)" == 'BLOCKED' ]] || add_reason "$avd:resilience_verdict_invalid"
  [[ "$(field "$result" db_evidence)" == COLLECTED ]] || add_reason "$avd:db_evidence_not_collected"
  [[ "$(field "$result" outbox_evidence)" == COLLECTED ]] || add_reason "$avd:outbox_evidence_not_collected"
  [[ "$(field "$result" callback_evidence)" == COLLECTED ]] || add_reason "$avd:callback_evidence_not_collected"
  [[ -s "$dir/payment-settlement.txt" ]] || add_reason "$avd:payment_settlement_missing"
  [[ "$(field "$result" secret_scan)" == PASS ]] || add_reason "$avd:secret_scan_not_pass"
  [[ "$(field "$result" apk_secret_scan)" == PASS ]] || add_reason "$avd:apk_secret_scan_not_pass"
  [[ "$(field "$result" crash_anr_count)" == 0 ]] || add_reason "$avd:crash_or_anr_nonzero"
  [[ "$(field "$result" screenshot_count)" =~ ^[1-9][0-9]*$ ]] || add_reason "$avd:screenshot_missing"
  [[ "$(field "$result" http_route_marker_count)" =~ ^[1-9][0-9]*$ ]] || add_reason "$avd:route_evidence_missing"
  if [[ "$PAYMENT_SUCCESS" == 'true' ]]; then
    if [[ "$avd" == 'AVD-A' ]]; then
      [[ "$(field "$result" payment_success_proven)" == 'true' ]] || add_reason "$avd:payment_success_not_proven"
      [[ "$(field "$result" reconcile_repeat)" == 'PASS' ]] || add_reason "$avd:reconcile_repeat_missing"
    else
      [[ "$(field "$result" payment_success_proven)" == 'false' ]] || add_reason "$avd:receiver_payment_success_marker_invalid"
      [[ "$(field "$result" reconcile_repeat)" == 'NOT_RUN' ]] || add_reason "$avd:receiver_reconcile_must_not_run"
    fi
  fi
  [[ -s "$dir/http-route-coverage.csv" ]] || add_reason "$avd:route_csv_missing"
  [[ -s "$dir/vendor-events.txt" ]] || add_reason "$avd:vendor_event_evidence_missing"
  [[ -s "$dir/db-write-counters.txt" ]] || add_reason "$avd:db_write_counters_missing"
  [[ -s "$dir/outbox-evidence.txt" ]] || add_reason "$avd:outbox_evidence_missing"
  [[ -s "$dir/callback-evidence.txt" ]] || add_reason "$avd:callback_evidence_missing"
  validate_log "$dir" || add_reason "$avd:log_evidence_invalid"
  validate_lanes "$dir"
  provider_line="$(grep -E '^M5_PROVIDER_CALLS::[0-9]+::[0-9]+$' "$dir/logs/flutter-drive.log" | tail -n 1 || true)"
  if [[ "$provider_line" =~ M5_PROVIDER_CALLS::([0-9]+)::([0-9]+)$ ]]; then
    tencent_calls="${BASH_REMATCH[1]}"
    alipay_calls="${BASH_REMATCH[2]}"
    if [[ "$result_value" == 'NO_PAY' && "$tencent_calls" -lt 1 ]]; then
      add_reason "$avd:tencent_provider_calls_missing_for_no_pay"
    fi
  else
    add_reason "$avd:provider_call_marker_invalid"
  fi
  nonce="$(field "$result" db_start_nonce)"
  validate_db_evidence "$dir/db-evidence.json" "$avd" "$nonce" "$apk_sha" "$result_value" || add_reason "$avd:db_evidence_contract_invalid"
  if [[ "$avd" == 'AVD-A' ]]; then
    AVD_A_RESULT="$result_value"
    AVD_A_TENCENT_CALLS="${tencent_calls:-0}"
    AVD_A_ALIPAY_CALLS="${alipay_calls:-0}"
  else
    AVD_B_RESULT="$result_value"
    AVD_B_TENCENT_CALLS="${tencent_calls:-0}"
    AVD_B_ALIPAY_CALLS="${alipay_calls:-0}"
  fi
}

validate_avd AVD-A
validate_avd AVD-B
if [[ -n "$AVD_A_APK_SHA" && -n "$AVD_B_APK_SHA" &&
  "$AVD_A_APK_SHA" != "$AVD_B_APK_SHA" ]]; then
  add_reason 'apk_sha_differs_between_avds'
fi
if [[ "$PAYMENT_OPT_IN" == 'true' &&
  "$(env_value QA_M5_PAYMENT_CONFIRMATION)" != 'I_UNDERSTAND_SANDBOX_PAYMENT' ]]; then
  add_reason 'aggregate_payment_confirmation_missing'
fi
if [[ "$PAYMENT_OPT_IN" == 'true' &&
  "$PAYMENT_SCENARIO" != 'cancel' && "$PAYMENT_SCENARIO" != 'success' ]]; then
  add_reason 'aggregate_payment_scenario_invalid'
fi
if [[ "$PAYMENT_SUCCESS" == 'true' &&
  "$PAYMENT_SUCCESS_CONFIRMATION" != 'I_UNDERSTAND_SANDBOX_SUCCESS_PAYMENT' ]]; then
  add_reason 'aggregate_success_confirmation_missing'
fi
TOTAL_TENCENT_CALLS=$(( AVD_A_TENCENT_CALLS + AVD_B_TENCENT_CALLS ))
TOTAL_ALIPAY_CALLS=$(( AVD_A_ALIPAY_CALLS + AVD_B_ALIPAY_CALLS ))

conclusion='ANDROID_EMULATOR_PASS'
if [[ -z "$AVD_A_RESULT" || -z "$AVD_B_RESULT" ]]; then
  conclusion='ANDROID_EMULATOR_FAIL'
elif ((${#REASONS[@]} > 0)); then
  conclusion='ANDROID_EMULATOR_FAIL'
elif [[ "$PAYMENT_CANCEL_ONLY" == 'true' ]]; then
  # A canceled native sandbox attempt is useful evidence but never a payment
  # PASS. Keep the nonzero PARTIAL exit until a confirmed-success lane exists.
  conclusion='ANDROID_EMULATOR_PARTIAL'
elif [[ "$PAYMENT_OPT_IN" != 'true' ]]; then
  if [[ "$AVD_A_RESULT" == 'NO_PAY' && "$AVD_B_RESULT" == 'NO_PAY' ]]; then
    conclusion='ANDROID_EMULATOR_NO_PAY'
  else
    conclusion='ANDROID_EMULATOR_PARTIAL'
  fi
fi
reasons_text=''
if ((${#REASONS[@]} > 0)); then
  reasons_text="$(printf '%s\n' "${REASONS[@]}")"
fi

python3 - "$AGGREGATE_JSON" "$ARTIFACT_ROOT" "$conclusion" "$EXPECTED_FLUTTER_SHA" "$EXPECTED_BACKEND_SHA" "$EXPECTED_BACKEND_DIGEST" "$ANDROID_HOST_SHA" "$EXPECTED_RUN_ID" "$EXPECTED_FIXTURE_ID" "$AVD_A_APK_SHA" "$AVD_B_APK_SHA" "$TOTAL_TENCENT_CALLS" "$TOTAL_ALIPAY_CALLS" "$([[ "$PAYMENT_OPT_IN" == true ]] && printf true || printf false)" "$PAYMENT_SCENARIO" "$reasons_text" <<'PY'
import json
import sys
path, artifact_root, conclusion, flutter_sha, backend_sha, backend_digest, android_host_sha, run_id, fixture_id, apk_a, apk_b, tencent_calls, alipay_calls, payment_opt_in, payment_scenario, raw_reasons = sys.argv[1:]
reasons = [line for line in raw_reasons.splitlines() if line]
settlement = {}
for avd in ("AVD-A", "AVD-B"):
    try:
        with open(f"{artifact_root}/{avd}/db-evidence.json", encoding="utf-8") as stream:
            settlement[avd] = json.load(stream).get("paymentSettlement")
    except (OSError, ValueError, TypeError):
        settlement[avd] = None
payload = {
    "schemaVersion": 1,
    "conclusion": conclusion,
    "tested_git_sha": flutter_sha,
    "backend_sha": backend_sha,
    "backend_source_digest": backend_digest,
    "android_host_source_sha256": android_host_sha,
    "apk_sha256": apk_a if apk_a and apk_a == apk_b else "",
    "run_id": run_id,
    "fixture_id": fixture_id,
    "providerCalls": {"tencentIm": int(tencent_calls), "alipay": int(alipay_calls)},
    "paymentOptIn": payment_opt_in == "true",
    "paymentMode": "cancel_only" if payment_scenario == "cancel" and payment_opt_in == "true" else ("success" if payment_scenario == "success" and payment_opt_in == "true" else "none"),
    "paymentSettlement": settlement,
    "secrets": False,
    "reasons": reasons,
}
with open(path, "w", encoding="utf-8") as stream:
    json.dump(payload, stream, sort_keys=True, indent=2)
    stream.write("\n")
PY

payment_mode='none'
if [[ "$PAYMENT_OPT_IN" == 'true' && "$PAYMENT_CANCEL_ONLY" == 'true' ]]; then
  payment_mode='cancel_only'
elif [[ "$PAYMENT_OPT_IN" == 'true' && "$PAYMENT_SUCCESS" == 'true' ]]; then
  payment_mode='success'
fi
{
  printf 'M5 aggregate verdict\nconclusion=%s\nrun_id=%s\nfixture_id=%s\n' "$conclusion" "$EXPECTED_RUN_ID" "$EXPECTED_FIXTURE_ID"
  printf 'tested_git_sha=%s\nbackend_sha=%s\nbackend_source_digest=%s\nandroid_host_source_sha256=%s\n' "$EXPECTED_FLUTTER_SHA" "$EXPECTED_BACKEND_SHA" "$EXPECTED_BACKEND_DIGEST" "$ANDROID_HOST_SHA"
  printf 'apk_a_sha256=%s\napk_b_sha256=%s\npayment_opt_in=%s\npayment_mode=%s\n' "${AVD_A_APK_SHA:-unknown}" "${AVD_B_APK_SHA:-unknown}" "$PAYMENT_OPT_IN" "$payment_mode"
  if ((${#REASONS[@]} == 0)); then printf 'reasons=none\n'; else printf 'reasons=%s\n' "$(printf '%s,' "${REASONS[@]}" | sed 's/,$//')"; fi
} >"$AGGREGATE_TEXT"

if [[ "$conclusion" == 'ANDROID_EMULATOR_PASS' || "$conclusion" == 'ANDROID_EMULATOR_NO_PAY' ]]; then exit 0; fi
exit 1
