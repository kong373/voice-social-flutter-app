#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

# M4 runs the Flutter client against the real first-party development backend.
# It does not start a deterministic contract server or any formal vendor. The
# only local process is an ephemeral relay for operator values; those values
# never enter a dart-define.

readonly PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
readonly DB_EVIDENCE_HELPER="$PROJECT_ROOT/tool/qa/m4_db_evidence_server.py"
required() {
  local name="$1"
  local value
  value="$(printenv "$name" || true)"
  [[ -n "$value" ]] || { printf '%s is required\n' "$name" >&2; exit 64; }
  printf '%s' "$value"
}

readonly ARTIFACT_ROOT="$(required QA_ARTIFACT_ROOT)"
readonly FLUTTER_SHA_EXPECTED="$(required QA_FLUTTER_SHA)"
readonly BACKEND_SHA_EXPECTED="$(required QA_BACKEND_SHA)"
readonly BACKEND_REPO="$(required QA_BACKEND_REPO)"
readonly LIVE_PHONE="$(required QA_LIVE_PHONE)"
readonly OAUTH_CLIENT_ID="$(required QA_OAUTH_CLIENT_ID)"
readonly FIXTURE_ID="$(required QA_M4_FIXTURE_ID)"
readonly FIXTURE_STATUS="$(required QA_M4_FIXTURE_STATUS)"
readonly DB_URL="$(required QA_DB_EVIDENCE_URL)"
readonly DB_TOKEN="$(required QA_DB_EVIDENCE_TOKEN)"
readonly BACKEND_BASE_URL='http://10.0.2.2:18080/'
readonly RUN_ID="$(required QA_RUN_ID)"
readonly AVD_A_SERIAL="$(printenv QA_AVD_A_SERIAL || true)"
readonly AVD_B_SERIAL="$(printenv QA_AVD_B_SERIAL || true)"
readonly AVD_A_NAME="$(printenv QA_AVD_A_NAME || printf pixel_7_pro)"
readonly AVD_B_NAME="$(printenv QA_AVD_B_NAME || printf pixel_2)"

readonly A_API='36'
readonly A_PROFILE='pixel_7_pro'
readonly A_PHYSICAL='1170x2532'
readonly A_DENSITY='480'
readonly A_WIDTH='390'
readonly A_HEIGHT='844'
readonly A_DPR='3.00'
readonly B_API='35'
readonly B_PROFILE='pixel_2'
readonly B_PHYSICAL='864x1920'
readonly B_DENSITY='384'
readonly B_WIDTH='360'
readonly B_HEIGHT='800'
readonly B_DPR='2.40'
readonly SMS_COOLDOWN_SECONDS='60'
readonly SMS_COOLDOWN_BUFFER_SECONDS='5'
readonly APP_PACKAGE='com.kong373.voice_social_app'
readonly RUNTIME_TOKEN_FILE='cache/m4-runtime-relay-token'
readonly RUNTIME_TOKEN_TMP_FILE="$RUNTIME_TOKEN_FILE.tmp"
readonly EXPECTED_FLUTTER_VERSION='3.44.7'
readonly EXPECTED_DART_VERSION='3.12.2'
readonly EXPECTED_FLUTTER_REVISION='84fc5cbb223bc12f83d65b647ff8a56caf779ffd'

readonly SUMMARY_FILE="$ARTIFACT_ROOT/summary.txt"
readonly MANIFEST_FILE="$ARTIFACT_ROOT/evidence-manifest.sha256"
readonly STARTED_SERIALS_FILE="$ARTIFACT_ROOT/.started-emulator-serials"
[[ -n "$ARTIFACT_ROOT" && -n "$FLUTTER_SHA_EXPECTED" && -n "$BACKEND_SHA_EXPECTED" &&
  -n "$BACKEND_REPO" && -n "$LIVE_PHONE" && -n "$OAUTH_CLIENT_ID" &&
  -n "$FIXTURE_ID" && -n "$FIXTURE_STATUS" && -n "$DB_URL" &&
  -n "$DB_TOKEN" && -n "$RUN_ID" ]] || exit 64
RELAY_PID=''
RELAY_PORT=''
DB_START_NONCE=''
SMS_COOLDOWN_STARTED_AT=''
RELAY_TOKEN_A=''
RELAY_TOKEN_B=''
RUNTIME_TOKEN_FEEDER_PID=''
FLUTTER_BIN=''
FLUTTER_FRAMEWORK_VERSION=''
FLUTTER_DART_VERSION=''
FLUTTER_FRAMEWORK_REVISION=''
ANDROID_HOST_SOURCE_SHA256=''
OVERALL_RESULT='PASS'

fail() {
  OVERALL_RESULT='FAIL'
  printf 'M4 preflight failed: %s\n' "$1" >&2
  exit 64
}

assert_flutter_checkout_clean() {
  local status
  # This is intentionally the pre-build binding point. Git's default status
  # semantics exclude ignored Flutter outputs (build/, .dart_tool/, etc.),
  # while --untracked-files=all still rejects every non-ignored untracked
  # input. Generated outputs therefore cannot turn a clean checkout dirty
  # after this check, but source or tooling outside the ignore rules cannot be
  # silently included in the evidence run.
  if ! status="$(git -C "$PROJECT_ROOT" status \
    --porcelain=v1 --untracked-files=all --ignore-submodules=none)"; then
    fail 'Flutter checkout status could not be read'
  fi
  [[ -z "$status" ]] || fail 'Flutter checkout is dirty or has non-ignored untracked files'
}

create_safe_artifact_root() {
  python3 - "$ARTIFACT_ROOT" <<'PY'
import os
from pathlib import Path
import stat
import sys

raw = sys.argv[1]
if not os.path.isabs(raw) or os.path.normpath(raw) != raw or os.path.lexists(raw):
    raise SystemExit(1)
path = Path(raw)
ancestor = path.parent
missing = []
while not os.path.lexists(ancestor):
    missing.append(ancestor)
    if ancestor == ancestor.parent:
        raise SystemExit(1)
    ancestor = ancestor.parent
current = Path(ancestor.anchor)
for part in ancestor.parts[1:]:
    current /= part
    mode = os.lstat(current).st_mode
    if stat.S_ISLNK(mode) or not stat.S_ISDIR(mode):
        raise SystemExit(1)
for directory in reversed(missing):
    os.mkdir(directory, 0o700)
os.mkdir(path, 0o700)
current = Path(path.anchor)
for part in path.parts[1:]:
    current /= part
    mode = os.lstat(current).st_mode
    if stat.S_ISLNK(mode) or not stat.S_ISDIR(mode):
        raise SystemExit(1)
PY
}

attest_flutter_sdk() {
  local fact
  local -a sdk_facts=()
  FLUTTER_BIN="$(command -v flutter)"
  [[ -n "$FLUTTER_BIN" ]] || fail 'Flutter executable could not be resolved'
  while IFS= read -r fact; do
    sdk_facts+=("$fact")
  done < <("$FLUTTER_BIN" --version --machine 2>/dev/null | python3 -c '
import json
import sys
try:
    payload = json.load(sys.stdin)
    print(payload["frameworkVersion"])
    print(payload["dartSdkVersion"])
    print(payload["frameworkRevision"])
except (KeyError, TypeError, ValueError):
    raise SystemExit(1)
')
  [[ "${#sdk_facts[@]}" -eq 3 ]] || fail 'Flutter SDK metadata is invalid'
  FLUTTER_FRAMEWORK_VERSION="${sdk_facts[0]}"
  FLUTTER_DART_VERSION="${sdk_facts[1]}"
  FLUTTER_FRAMEWORK_REVISION="${sdk_facts[2]}"
  [[ "$FLUTTER_FRAMEWORK_VERSION" == "$EXPECTED_FLUTTER_VERSION" ]] || fail 'Flutter version mismatch'
  [[ "$FLUTTER_DART_VERSION" == "$EXPECTED_DART_VERSION" ]] || fail 'Dart version mismatch'
  [[ "$FLUTTER_FRAMEWORK_REVISION" == "$EXPECTED_FLUTTER_REVISION" ]] || fail 'Flutter framework revision mismatch'
}

attest_android_host_source() {
  local digest
  # android/ is intentionally generated and ignored by Git in this repository,
  # but its Gradle, manifest, wrapper, Kotlin, and resource files still affect
  # the APK. Re-create the exact Flutter template with the selected SDK, compare
  # every build input, then replace machine-local properties and remove the
  # generated plugin registrant so the ensuing Flutter build regenerates it.
  # Caches and IDE metadata are excluded; extra source/config files fail closed.
  if ! digest="$(python3 - "$PROJECT_ROOT" "$FLUTTER_BIN" <<'PY'
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile

project_root = Path(sys.argv[1]).resolve()
flutter = str(Path(sys.argv[2]).resolve())
current = project_root / "android"
if not current.is_dir() or current.is_symlink():
    raise SystemExit(1)

excluded_directories = {".gradle", ".kotlin", "build", ".cxx"}
excluded_files = {
    Path("local.properties"),
    Path("app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java"),
}
generated_registrant = Path(
    "app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java"
)


def source_files(root: Path):
    result = {}
    for directory, directory_names, file_names in os.walk(root, followlinks=False):
        base = Path(directory)
        for name in list(directory_names):
            candidate = base / name
            if candidate.is_symlink():
                raise RuntimeError("symlinked Android host directory")
            if name in excluded_directories:
                directory_names.remove(name)
        for name in file_names:
            candidate = base / name
            relative = candidate.relative_to(root)
            if candidate.is_symlink():
                raise RuntimeError("symlinked Android host file")
            if relative in excluded_files or name.endswith(".iml"):
                continue
            if not candidate.is_file():
                raise RuntimeError("non-regular Android host input")
            result[relative.as_posix()] = hashlib.sha256(candidate.read_bytes()).digest()
    return result


try:
    with tempfile.TemporaryDirectory(prefix="m4-android-template-") as temporary:
        generated_root = Path(temporary) / "generated"
        subprocess.run(
            [
                flutter,
                "create",
                "--platforms=android",
                "--android-language=kotlin",
                "--org=com.kong373",
                "--project-name=voice_social_app",
                "--no-pub",
                str(generated_root),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        expected = generated_root / "android"
        expected_sources = source_files(expected)
        if source_files(current) != expected_sources:
            raise RuntimeError("Android host does not match the selected Flutter template")

        expected_local_properties = expected / "local.properties"
        if not expected_local_properties.is_file():
            raise RuntimeError("generated Android local properties missing")
        local_properties = current / "local.properties"
        if local_properties.is_symlink():
            raise RuntimeError("symlinked Android local properties")
        with tempfile.NamedTemporaryFile(dir=current, prefix=".m4-local-", delete=False) as output:
            temporary_properties = Path(output.name)
            output.write(expected_local_properties.read_bytes())
        os.chmod(temporary_properties, 0o600)
        os.replace(temporary_properties, local_properties)

        registrant = current / generated_registrant
        if registrant.exists():
            if registrant.is_symlink() or not registrant.is_file():
                raise RuntimeError("invalid generated plugin registrant")
            registrant.unlink()

        digest_builder = hashlib.sha256()
        for relative in sorted(expected_sources):
            digest_builder.update(relative.encode("utf-8"))
            digest_builder.update(b"\0")
            digest_builder.update(expected_sources[relative])
        digest_builder.update(b"local.properties\0")
        digest_builder.update(hashlib.sha256(expected_local_properties.read_bytes()).digest())
        print(digest_builder.hexdigest())
except (OSError, RuntimeError, subprocess.SubprocessError):
    raise SystemExit(1)
PY
  )"; then
    fail 'ignored Android host source attestation failed'
  fi
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || fail 'Android host source digest is invalid'
  ANDROID_HOST_SOURCE_SHA256="$digest"
}

cleanup() {
  local incoming_status=$?
  local cleanup_failed=0
  set +e
  [[ "$incoming_status" -eq 0 ]] || OVERALL_RESULT='FAIL'
  [[ -z "$RELAY_PID" ]] || { kill "$RELAY_PID" 2>/dev/null || true; wait "$RELAY_PID" 2>/dev/null || true; }
  [[ -z "$RUNTIME_TOKEN_FEEDER_PID" ]] || {
    kill "$RUNTIME_TOKEN_FEEDER_PID" 2>/dev/null || true
    wait "$RUNTIME_TOKEN_FEEDER_PID" 2>/dev/null || true
  }
  local started_serial
  if [[ -f "$STARTED_SERIALS_FILE" ]]; then
    while IFS= read -r started_serial; do
      [[ -n "$started_serial" ]] || continue
      adb -s "$started_serial" shell run-as "$APP_PACKAGE" rm -f \
        "$RUNTIME_TOKEN_FILE" "$RUNTIME_TOKEN_TMP_FILE" >/dev/null 2>&1 || true
      adb -s "$started_serial" emu kill >/dev/null 2>&1 || true
    done <"$STARTED_SERIALS_FILE"
    rm -f "$STARTED_SERIALS_FILE"
  fi
  {
    printf 'M4 authoritative live AVD acceptance\n'
    printf 'conclusion=%s\n' "$OVERALL_RESULT"
    printf 'flutter_sha=%s\n' "$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || printf unknown)"
    printf 'backend_sha=%s\n' "$(git -C "$BACKEND_REPO" rev-parse HEAD 2>/dev/null || printf unknown)"
    printf 'android_host_source_sha256=%s\n' "${ANDROID_HOST_SOURCE_SHA256:-unknown}"
    printf 'flutter_version=%s\ndart_version=%s\nflutter_revision=%s\n' \
      "${FLUTTER_FRAMEWORK_VERSION:-unknown}" "${FLUTTER_DART_VERSION:-unknown}" \
      "${FLUTTER_FRAMEWORK_REVISION:-unknown}"
    printf 'backend_mode=live\nbackend_base_url=%s\n' "$BACKEND_BASE_URL"
    printf 'provider_calls_made=false\n'
    printf 'formal_sms_vendor_started=false\nformal_rtc_vendor_started=false\n'
    printf 'formal_im_vendor_started=false\nformal_payment_vendor_started=false\n'
    printf 'formal_push_vendor_started=false\nformal_storage_vendor_started=false\n'
    printf 'development_outbox_key_to_flutter=false\nrun_id=%s\n' "$RUN_ID"
    printf 'fixture_id=%s\nfixture_status=%s\n' "$FIXTURE_ID" "$FIXTURE_STATUS"
    for avd in AVD-A AVD-B; do
      if [[ -f "$ARTIFACT_ROOT/$avd/result.txt" ]]; then
        sed "s/^/$avd./" "$ARTIFACT_ROOT/$avd/result.txt"
      else
        printf '%s.result=NOT_RUN\n' "$avd"
      fi
      if [[ -f "$ARTIFACT_ROOT/$avd/db-evidence-status.txt" ]]; then
        sed "s/^/$avd./" "$ARTIFACT_ROOT/$avd/db-evidence-status.txt"
      fi
    done
  } >"$SUMMARY_FILE" || cleanup_failed=1
  # Re-scan after writing the summary so the final metadata file is covered as
  # well. The manifest is generated from hashes only after this check.
  if ! declare -F secret_scan >/dev/null 2>&1 || ! secret_scan "$ARTIFACT_ROOT"; then
    OVERALL_RESULT='FAIL'
    cleanup_failed=1
  fi
  if [[ "$OVERALL_RESULT" != PASS ]]; then
    local summary_tmp
    summary_tmp="$(mktemp "$ARTIFACT_ROOT/.m4-summary.XXXXXX")" || cleanup_failed=1
    if [[ -n "${summary_tmp:-}" && -f "$SUMMARY_FILE" ]]; then
      awk -v result="$OVERALL_RESULT" '
      /^conclusion=/ { print "conclusion=" result; next }
      { print }
    ' "$SUMMARY_FILE" >"$summary_tmp" && \
        python3 - "$summary_tmp" "$SUMMARY_FILE" <<'PY' || cleanup_failed=1
import os
import sys
os.replace(sys.argv[1], sys.argv[2])
PY
    fi
  fi
  python3 - "$ARTIFACT_ROOT" "$MANIFEST_FILE" <<'PY' || cleanup_failed=1
import hashlib
import os
from pathlib import Path
import stat
import sys
import tempfile

root = Path(sys.argv[1]).resolve()
final = Path(sys.argv[2])
try:
    rows = []
    for directory, directory_names, file_names in os.walk(root, followlinks=False):
        base = Path(directory)
        for name in directory_names:
            if (base / name).is_symlink():
                raise OSError("symlinked evidence directory")
        for name in file_names:
            path = base / name
            if path == final or path.name.startswith(".m4-manifest."):
                continue
            item = os.lstat(path)
            if not stat.S_ISREG(item.st_mode):
                raise OSError("non-regular evidence file")
            relative = path.relative_to(root).as_posix()
            rows.append((relative, hashlib.sha256(path.read_bytes()).hexdigest()))
    with tempfile.NamedTemporaryFile(
        dir=root, prefix=".m4-manifest.", delete=False, mode="w", encoding="utf-8"
    ) as output:
        temporary = Path(output.name)
        for relative, digest in sorted(rows):
            output.write(f"{digest}  {relative}\n")
    os.replace(temporary, final)
    result = os.lstat(final)
    if not stat.S_ISREG(result.st_mode) or result.st_nlink != 1:
        raise OSError("manifest publication was not exclusive")
except OSError:
    raise SystemExit(1)
PY
  if [[ "$cleanup_failed" -ne 0 ]]; then
    OVERALL_RESULT='FAIL'
    incoming_status=1
    if [[ -f "$SUMMARY_FILE" ]]; then
      local failed_summary
      failed_summary="$(mktemp "$ARTIFACT_ROOT/.m4-summary-failed.XXXXXX")" || true
      if [[ -n "${failed_summary:-}" ]]; then
        awk '
          /^conclusion=/ { print "conclusion=FAIL"; next }
          { print }
        ' "$SUMMARY_FILE" >"$failed_summary" && \
          python3 - "$failed_summary" "$SUMMARY_FILE" <<'PY' || true
import os
import sys
os.replace(sys.argv[1], sys.argv[2])
PY
      fi
    fi
  fi
  trap - EXIT
  exit "$incoming_status"
}
for command_name in adb flutter git python3 curl find sort awk grep unzip date sleep rm mktemp; do
  command -v "$command_name" >/dev/null 2>&1 || fail "missing command: $command_name"
done
attest_flutter_sdk
readonly FLUTTER_BIN
readonly FLUTTER_FRAMEWORK_VERSION FLUTTER_DART_VERSION FLUTTER_FRAMEWORK_REVISION
[[ -f "$PROJECT_ROOT/pubspec.yaml" ]] || fail 'not a Flutter checkout'
[[ -f "$DB_EVIDENCE_HELPER" ]] || fail 'bundled DB evidence helper is missing'
[[ -d "$BACKEND_REPO/.git" || -f "$BACKEND_REPO/.git" ]] || fail 'QA_BACKEND_REPO is not Git'
[[ "$LIVE_PHONE" =~ ^1[3-9][0-9]{9}$ ]] || fail 'QA_LIVE_PHONE is invalid'
[[ -n "$OAUTH_CLIENT_ID" ]] || fail 'QA_OAUTH_CLIENT_ID is empty'
[[ "$FIXTURE_ID" =~ ^m4-fresh-[A-Za-z0-9_.:-]{1,64}$ ]] || fail 'QA_M4_FIXTURE_ID must identify a fresh M4 fixture'
[[ "$FIXTURE_ID" != *legacy* && "$FIXTURE_ID" != *LEGACY* ]] || fail 'QA_M4_FIXTURE_ID may not identify a legacy fixture'
[[ "$FIXTURE_STATUS" == 'fresh_dedicated' ]] || fail 'QA_M4_FIXTURE_STATUS must be fresh_dedicated'
[[ "$DB_URL" =~ ^https?:// ]] || fail 'QA_DB_EVIDENCE_URL must be an HTTP(S) endpoint'
[[ "$DB_URL" != *'?'* && "$DB_URL" != *'@'* ]] || fail 'QA_DB_EVIDENCE_URL may not contain query credentials'
[[ "$RUN_ID" =~ ^[A-Za-z0-9_.:-]{1,80}$ ]] || fail 'QA_RUN_ID contains unsafe characters'
[[ -z "$AVD_A_SERIAL" || "$AVD_A_SERIAL" =~ ^[A-Za-z0-9_.:-]{1,80}$ ]] || fail 'QA_AVD_A_SERIAL contains unsafe characters'
[[ -z "$AVD_B_SERIAL" || "$AVD_B_SERIAL" =~ ^[A-Za-z0-9_.:-]{1,80}$ ]] || fail 'QA_AVD_B_SERIAL contains unsafe characters'
[[ "$AVD_A_NAME" =~ ^[A-Za-z0-9_.-]{1,80}$ && "$AVD_B_NAME" =~ ^[A-Za-z0-9_.-]{1,80}$ ]] || fail 'AVD name contains unsafe characters'

readonly FLUTTER_SHA_ACTUAL="$(git -C "$PROJECT_ROOT" rev-parse --verify HEAD)"
readonly BACKEND_SHA_ACTUAL="$(git -C "$BACKEND_REPO" rev-parse --verify HEAD)"
[[ "$FLUTTER_SHA_EXPECTED" == "$FLUTTER_SHA_ACTUAL" ]] || fail 'QA_FLUTTER_SHA mismatch'
[[ "$BACKEND_SHA_EXPECTED" == "$BACKEND_SHA_ACTUAL" ]] || fail 'QA_BACKEND_SHA mismatch'
assert_flutter_checkout_clean
[[ "$ARTIFACT_ROOT" != *':8765'* && "$ARTIFACT_ROOT" != *'contract-server'* && "$ARTIFACT_ROOT" != *'.env.local'* ]] || fail 'artifact path names a forbidden source'
[[ "$ARTIFACT_ROOT" != *"$LIVE_PHONE"* && "$ARTIFACT_ROOT" != *"$OAUTH_CLIENT_ID"* ]] || fail 'artifact path contains a runtime secret'
[[ -z "$DB_TOKEN" || "$ARTIFACT_ROOT" != *"$DB_TOKEN"* ]] || fail 'artifact path contains the DB token'

# The clean-checkout binding above must happen before this directory is
# created, because QA_ARTIFACT_ROOT may itself be inside the Flutter checkout.
# The normal Flutter build outputs are ignored by Git and are intentionally
# allowed after the binding point.
create_safe_artifact_root || fail 'artifact root must be a new absolute directory with no symlinked parent'
trap cleanup EXIT

[[ -z "$(printenv DEVELOPMENT_OUTBOX_KEY || true)" ]] || fail 'DEVELOPMENT_OUTBOX_KEY is forbidden'
[[ -z "$(printenv QA_DEVELOPMENT_OUTBOX_KEY || true)" ]] || fail 'QA_DEVELOPMENT_OUTBOX_KEY is forbidden'
[[ -z "$(printenv QA_API_BASE_URL || true)" ]] || fail 'QA_API_BASE_URL override is forbidden'
[[ -z "$(printenv CONTRACT_SERVER_PORT || true)" &&
  -z "$(printenv QA_CONTRACT_SERVER_PORT || true)" ]] || fail 'contract-server variables are forbidden'
[[ "$BACKEND_BASE_URL" != *':8765'* && "$BACKEND_BASE_URL" != *'contract-server'* ]] || fail 'backend target is not authoritative'
python3 "$DB_EVIDENCE_HELPER" --self-test >/dev/null 2>&1 || fail 'bundled DB evidence helper self-test failed'
"$FLUTTER_BIN" clean >/dev/null 2>&1 || fail 'Flutter clean failed'
attest_android_host_source
"$FLUTTER_BIN" pub get --enforce-lockfile >/dev/null 2>&1 || fail 'locked Flutter dependency regeneration failed'

run_with_timeout() {
  local timeout_seconds="$1"
  local kill_after_seconds="$2"
  shift 2
  python3 - "$timeout_seconds" "$kill_after_seconds" "$@" <<'PY'
import os
import signal
import subprocess
import sys

timeout_seconds = int(sys.argv[1])
kill_after_seconds = int(sys.argv[2])
command = sys.argv[3:]
process = subprocess.Popen(command, start_new_session=True)
try:
    raise SystemExit(process.wait(timeout=timeout_seconds))
except subprocess.TimeoutExpired:
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=kill_after_seconds)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
    raise SystemExit(124)
PY
}

wait_for_sms_cooldown() {
  [[ -n "$SMS_COOLDOWN_STARTED_AT" ]] || return 0
  local now required_until remaining nap
  now="$(date +%s)"
  required_until=$((SMS_COOLDOWN_STARTED_AT + SMS_COOLDOWN_SECONDS + SMS_COOLDOWN_BUFFER_SECONDS))
  remaining=$((required_until - now))
  [[ "$remaining" -gt 0 ]] || return 0
  # The development backend enforces a 60-second per-phone challenge window.
  # Wait only the residual window, in short bounded sleeps, so a rerun never
  # launches AVD-B into a known cooldown rejection or blocks in one long sleep.
  while [[ "$remaining" -gt 0 ]]; do
    if [[ "$remaining" -gt 10 ]]; then
      nap=10
    else
      nap="$remaining"
    fi
    sleep "$nap"
    now="$(date +%s)"
    remaining=$((required_until - now))
  done
  printf 'sms_cooldown_waited_until=%s\n' "$required_until" >>"$ARTIFACT_ROOT/sms-cooldown.txt"
}

record_sms_cooldown_start() {
  local avd="$1"
  SMS_COOLDOWN_STARTED_AT="$(date +%s)"
  if [[ "$avd" == 'AVD-A' ]]; then
    {
      printf 'run_id=%s\nfixture_id=%s\n' "$RUN_ID" "$FIXTURE_ID"
      printf 'sms_cooldown_seconds=%s\nbuffer_seconds=%s\n' \
        "$SMS_COOLDOWN_SECONDS" "$SMS_COOLDOWN_BUFFER_SECONDS"
      printf 'last_challenge_window_avd=%s\nlast_challenge_window_started_at=%s\n' \
        "$avd" "$SMS_COOLDOWN_STARTED_AT"
    } >"$ARTIFACT_ROOT/sms-cooldown.txt"
    return 0
  fi
  {
    printf 'last_challenge_window_avd=%s\nlast_challenge_window_started_at=%s\n' \
      "$avd" "$SMS_COOLDOWN_STARTED_AT"
  } >>"$ARTIFACT_ROOT/sms-cooldown.txt"
}

db_evidence_start() {
  local dir="$1"
  local avd="$2"
  local nonce status
  nonce=''
  set +e
  nonce="$(QA_M4_DB_TOKEN="$DB_TOKEN" QA_M4_DB_URL="$DB_URL" \
    QA_M4_RUN_ID="$RUN_ID" QA_M4_AVD="$avd" QA_M4_FIXTURE_ID="$FIXTURE_ID" python3 -u - <<'PY'
import json
import os
import urllib.error
import urllib.request

request = urllib.request.Request(
    os.environ["QA_M4_DB_URL"],
    headers={
        "Authorization": "Bearer " + os.environ["QA_M4_DB_TOKEN"],
        "Accept": "application/json",
        "X-M4-Evidence-Phase": "start",
        "X-M4-Run-ID": os.environ["QA_M4_RUN_ID"],
        "X-M4-AVD": os.environ["QA_M4_AVD"],
        "X-M4-Fixture-ID": os.environ["QA_M4_FIXTURE_ID"],
    },
)
try:
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(request, timeout=20) as response:
        if response.status < 200 or response.status >= 300:
            raise RuntimeError("db evidence start returned non-success status")
        payload = json.loads(response.read())
    if (
        not isinstance(payload, dict)
        or payload.get("status") != "STARTED"
        or payload.get("runId") != os.environ["QA_M4_RUN_ID"]
        or payload.get("avd") != os.environ["QA_M4_AVD"]
        or payload.get("fixtureId") != os.environ["QA_M4_FIXTURE_ID"]
        or payload.get("fixtureAccountState")
        != ("absent_at_start" if os.environ["QA_M4_AVD"] == "AVD-A" else "present_at_start")
        or not isinstance(payload.get("startNonce"), str)
    ):
        raise RuntimeError("db evidence start contract invalid")
    print(payload["startNonce"])
except (OSError, ValueError, urllib.error.URLError, RuntimeError):
    raise SystemExit(1)
PY
  )"
  status=$?
  set -e
  if [[ "$status" -ne 0 || ! "$nonce" =~ ^[A-Za-z0-9_.~=-]{16,255}$ ]]; then
    printf 'db_evidence_status=FAIL\n' >"$dir/db-evidence-error.txt"
    return 1
  fi
  DB_START_NONCE="$nonce"
  return 0
}

sanitize() {
  QA_M4_SECRET_PHONE="$LIVE_PHONE" \
    QA_M4_SECRET_CLIENT="$OAUTH_CLIENT_ID" \
    QA_M4_SECRET_DB_TOKEN="$DB_TOKEN" \
    QA_M4_SECRET_RELAY_A="$RELAY_TOKEN_A" \
    QA_M4_SECRET_RELAY_B="$RELAY_TOKEN_B" \
    python3 -u -c '
import os
import re
import sys
values = [os.environ.get("QA_M4_SECRET_PHONE", ""), os.environ.get("QA_M4_SECRET_CLIENT", ""), os.environ.get("QA_M4_SECRET_DB_TOKEN", ""), os.environ.get("QA_M4_SECRET_RELAY_A", ""), os.environ.get("QA_M4_SECRET_RELAY_B", "")]
for line in sys.stdin:
    for value in values:
        if value:
            line = line.replace(value, "[REDACTED]")
    line = re.sub(r"(?<!\d)1[3-9]\d{9}(?!\d)", "[REDACTED_PHONE]", line)
    line = re.sub(r"(?<!\d)\d{6}(?!\d)", "[REDACTED_OTP]", line)
    line = re.sub(r"(?i)(bearer\s+)[A-Za-z0-9._~+/=-]{12,}", r"\1[REDACTED_TOKEN]", line)
    line = re.sub(r"(?i)((?:access[_-]?token|refresh[_-]?token|client[_-]?secret|password|token)\s*[:=]\s*)[A-Za-z0-9._~+/=-]{8,}", r"\1[REDACTED_TOKEN]", line)
    line = re.sub(r"(?i)(\"(?:access_token|refresh_token|accessToken|refreshToken)\"\s*[:=]\s*\")[^\"]+", r"\1[REDACTED_TOKEN]", line)
    sys.stdout.write(line)
    sys.stdout.flush()
'
}

start_relay() {
  local relay_dir="$ARTIFACT_ROOT/config-relay"
  mkdir -p "$relay_dir"
  RELAY_TOKEN_A="$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(48))
PY
)"
  RELAY_TOKEN_B="$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(48))
PY
)"
  [[ "${#RELAY_TOKEN_A}" -ge 64 && "${#RELAY_TOKEN_B}" -ge 64 ]] || fail 'runtime relay token generation failed'
  RELAY_PORT="$(python3 - <<'PY'
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)"
  QA_RELAY_TOKEN_A="$RELAY_TOKEN_A" QA_RELAY_TOKEN_B="$RELAY_TOKEN_B" \
    python3 -u - "$RELAY_PORT" >"$relay_dir/relay.log" 2>&1 <<'PY' &
import http.server
import hmac
import json
import os
import sys
import threading
port = int(sys.argv[1])
phone = os.environ["QA_LIVE_PHONE"]
client_id = os.environ["QA_OAUTH_CLIENT_ID"]
tokens = {
    os.environ["QA_RELAY_TOKEN_A"]: False,
    os.environ["QA_RELAY_TOKEN_B"]: False,
}
token_lock = threading.Lock()
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/m4/config":
            self.send_response(404)
            self.end_headers()
            return
        values = self.headers.get_all("Authorization") or []
        prefix = "Bearer "
        token = values[0][len(prefix):] if len(values) == 1 and values[0].startswith(prefix) else ""
        matched = None
        with token_lock:
            for expected, consumed in tokens.items():
                if hmac.compare_digest(token, expected) and not consumed:
                    matched = expected
                    break
            if matched is None:
                self.send_response(401)
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                return
            tokens[matched] = True
        body = json.dumps({"phone": phone, "oauthClientId": client_id}, separators=(",", ":")).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, _format, *_args):
        return
http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
PY
  RELAY_PID=$!
  for _ in {1..60}; do
    kill -0 "$RELAY_PID" 2>/dev/null || fail 'runtime config relay exited'
    if python3 - "$RELAY_PORT" <<'PY'
import socket
import sys
try:
    with socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=1):
        pass
except OSError:
    raise SystemExit(1)
PY
    then
      return 0
    fi
    sleep 0.1
  done
  fail 'runtime config relay did not become ready'
}

feed_runtime_relay_token() {
  local serial="$1"
  local token="$2"
  [[ "$serial" =~ ^[A-Za-z0-9_.:-]{1,80}$ ]] || fail 'runtime token feeder serial is invalid'
  [[ "${#token}" -ge 64 ]] || fail 'runtime token feeder token is invalid'
  (
    # Flutter drive installs a debug APK after this feeder starts. Repeating
    # the 0600 cache-file write bridges that install window without passing the
    # bearer through dart-define, process arguments, logs, or artifacts.
    for _ in {1..240}; do
      printf '%s' "$token" |
        adb -s "$serial" shell run-as "$APP_PACKAGE" tee "$RUNTIME_TOKEN_TMP_FILE" \
          >/dev/null 2>&1 &&
        adb -s "$serial" shell run-as "$APP_PACKAGE" chmod 600 "$RUNTIME_TOKEN_TMP_FILE" \
          >/dev/null 2>&1 &&
        adb -s "$serial" shell run-as "$APP_PACKAGE" mv "$RUNTIME_TOKEN_TMP_FILE" "$RUNTIME_TOKEN_FILE" \
          >/dev/null 2>&1 || true
      sleep 0.25
    done
  ) &
  RUNTIME_TOKEN_FEEDER_PID=$!
}

stop_runtime_relay_token_feeder() {
  [[ -z "$RUNTIME_TOKEN_FEEDER_PID" ]] || {
    kill "$RUNTIME_TOKEN_FEEDER_PID" 2>/dev/null || true
    wait "$RUNTIME_TOKEN_FEEDER_PID" 2>/dev/null || true
  }
  RUNTIME_TOKEN_FEEDER_PID=''
}

clear_runtime_relay_token() {
  local serial="$1"
  adb -s "$serial" shell run-as "$APP_PACKAGE" rm -f \
    "$RUNTIME_TOKEN_FILE" "$RUNTIME_TOKEN_TMP_FILE" \
    >/dev/null 2>&1 || true
}

device_for_api() {
  local serial sdk
  # The script-wide IFS intentionally excludes spaces, but `adb devices`
  # separates its serial and state with horizontal whitespace. Restore that
  # delimiter only for this parser so a cold-started emulator is discoverable.
  while IFS=$' \t' read -r serial _state; do
    [[ "$serial" == emulator-* ]] || continue
    sdk="$(adb -s "$serial" shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r')"
    [[ "$sdk" == "$1" ]] && { printf '%s\n' "$serial"; return 0; }
  done < <(adb devices | awk 'NR > 1 && $2 == "device" {print $1, $2}')
  return 1
}

wait_boot() {
  local serial="$1"
  adb -s "$serial" wait-for-device >/dev/null
  local attempt
  for attempt in {1..180}; do
    [[ "$(adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == '1' ]] && return 0
    sleep 2
  done
  return 1
}

start_emulator() {
  local api="$1"
  local name="$2"
  local run_dir="$3"
  local emulator_bin
  emulator_bin="$(command -v emulator 2>/dev/null || true)"
  if [[ -z "$emulator_bin" ]]; then
    local sdk_root
    sdk_root="$(printenv ANDROID_SDK_ROOT || printenv ANDROID_HOME || true)"
    [[ -n "$sdk_root" && -x "$sdk_root/emulator/emulator" ]] || fail "no API $api emulator or emulator binary"
    emulator_bin="$sdk_root/emulator/emulator"
  fi
  "$emulator_bin" -avd "$name" -no-snapshot -no-boot-anim -gpu swiftshader_indirect \
    -no-window >"$run_dir/emulator.log" 2>&1 &
  local pid=$!
  local serial
  for _ in {1..180}; do
    serial="$(device_for_api "$api" || true)"
    if [[ -n "$serial" ]] && wait_boot "$serial"; then
      # This function is called through command substitution, so shell state
      # assigned here cannot reach cleanup. Persist only the non-sensitive
      # emulator serial in a short-lived file that cleanup removes.
      printf '%s\n' "$serial" >>"$STARTED_SERIALS_FILE"
      printf '%s\n' "$serial"
      return 0
    fi
    kill -0 "$pid" 2>/dev/null || fail "emulator $name exited before API $api booted"
    sleep 2
  done
  fail "timed out waiting for API $api emulator"
}

select_device() {
  local avd="$1"
  local api="$2"
  local override="$3"
  local name="$4"
  local run_dir="$5"
  local serial=''
  if [[ -n "$override" ]]; then
    serial="$override"
    [[ "$(adb -s "$serial" shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r')" == "$api" ]] || fail "$avd serial is not API $api"
    wait_boot "$serial" || fail "$avd failed to boot"
  else
    serial="$(device_for_api "$api" || true)"
    [[ -n "$serial" ]] || serial="$(start_emulator "$api" "$name" "$run_dir")"
  fi
  printf '%s\n' "$serial"
}

configure_viewport() {
  local serial="$1"
  local physical="$2"
  local density="$3"
  adb -s "$serial" shell settings put system accelerometer_rotation 0 >/dev/null
  adb -s "$serial" shell settings put system user_rotation 0 >/dev/null
  adb -s "$serial" shell settings put system font_scale 1.0 >/dev/null
  adb -s "$serial" shell settings put global window_animation_scale 0 >/dev/null
  adb -s "$serial" shell settings put global transition_animation_scale 0 >/dev/null
  adb -s "$serial" shell settings put global animator_duration_scale 0 >/dev/null
  adb -s "$serial" shell wm size "$physical" >/dev/null
  adb -s "$serial" shell wm density "$density" >/dev/null
  local size density_value rotation font
  size="$(adb -s "$serial" shell wm size | tr -d '\r')"
  density_value="$(adb -s "$serial" shell wm density | tr -d '\r')"
  rotation="$(adb -s "$serial" shell settings get system user_rotation | tr -d '\r')"
  font="$(adb -s "$serial" shell settings get system font_scale | tr -d '\r')"
  [[ "$size" == *"$physical"* && "$density_value" == *"$density"* &&
    "$rotation" == '0' && "$font" == '1.0' ]] || return 1
  printf 'wm_size=%s\nwm_density=%s\nrotation=%s\nfont_scale=%s\n' "$size" "$density_value" "$rotation" "$font"
}

write_environment() {
  local dir="$1"; shift
  local avd="$1"; shift
  local api="$1"; shift
  local profile="$1"; shift
  local width="$1"; shift
  local height="$1"; shift
  local dpr="$1"; shift
  local serial="$1"; shift
  local viewport="$1"
  {
    printf 'avd=%s\napi_level=%s\nprofile=%s\nserial=%s\n' "$avd" "$api" "$profile" "$serial"
    printf 'run_id=%s\nfixture_id=%s\nfixture_status=%s\n' "$RUN_ID" "$FIXTURE_ID" "$FIXTURE_STATUS"
    printf 'expected_viewport=%sx%s\nexpected_dpr=%s\n' "$width" "$height" "$dpr"
    printf 'backend_mode=live\nbackend_base_url=%s\n' "$BACKEND_BASE_URL"
    printf 'flutter_sha=%s\nbackend_sha=%s\n' "$FLUTTER_SHA_ACTUAL" "$BACKEND_SHA_ACTUAL"
    printf 'android_host_source_sha256=%s\n' "$ANDROID_HOST_SOURCE_SHA256"
    printf 'flutter_version=%s\ndart_version=%s\nflutter_revision=%s\n' \
      "$FLUTTER_FRAMEWORK_VERSION" "$FLUTTER_DART_VERSION" "$FLUTTER_FRAMEWORK_REVISION"
    printf 'oauth_client_id_loaded_by_flutter=false\n'
    printf 'development_outbox_key_loaded_by_flutter=false\nprovider_calls_made=false\n'
    printf '%s\n' "$viewport"
  } >"$dir/environment.txt"
}

write_route_evidence() {
  local dir="$1"
  local log="$dir/logs/flutter-drive.log"
  {
    printf 'capability,method,route,status,state\n'
    awk -F '::' '/M4_ROUTE_STATUS::/ {
      gsub(/,/, "%2C", $2); gsub(/,/, "%2C", $3); gsub(/,/, "%2C", $4)
      printf "%s,%s,%s,%s,%s\n", $2, $3, $4, $5, $6
    }' "$log" | sort -u
  } >"$dir/http-route-coverage.csv"
  awk -F '::' '/M4_AUTHORITY_INVARIANT::/ {print $2}' "$log" | sort -u >"$dir/authority-invariants.txt"
  local writes
  writes="$(grep -Ec 'M4_ROUTE_STATUS::[^:]+::(POST|PUT|PATCH|DELETE)::' "$log" || true)"
  {
    printf 'source=client_observed_route_markers\nwrite_route_marker_count=%s\n' "$writes"
    printf 'database_write_counter_source=operator_redacted_db_evidence\n'
    printf 'database_write_counter_file=db-evidence.json\n'
  } >"$dir/db-write-counters.txt"
}

db_evidence() {
  local dir="$1"
  local avd="$2"
  local nonce="$3"
  [[ "$DB_URL" != *':8765'* && "$DB_URL" != *'contract-server'* ]] || {
    printf 'db_evidence_status=FAIL\n' >"$dir/db-evidence-error.txt"
    return 1
  }
  [[ "$nonce" =~ ^[A-Za-z0-9_.~=-]{16,255}$ ]] || {
    printf 'db_evidence_status=FAIL\n' >"$dir/db-evidence-error.txt"
    return 1
  }
  set +e
  QA_M4_DB_TOKEN="$DB_TOKEN" QA_M4_DB_URL="$DB_URL" \
    QA_M4_RUN_ID="$RUN_ID" QA_M4_AVD="$avd" QA_M4_FIXTURE_ID="$FIXTURE_ID" \
    QA_M4_START_NONCE="$nonce" \
    python3 -u - 2>"$dir/db-evidence-curl.stderr" <<'PY' | sanitize >"$dir/db-evidence.json"
import os
import sys
import urllib.error
import urllib.request

request = urllib.request.Request(
    os.environ["QA_M4_DB_URL"],
    headers={
        "Authorization": "Bearer " + os.environ["QA_M4_DB_TOKEN"],
        "Accept": "application/json",
        "X-M4-Evidence-Phase": "collect",
        "X-M4-Run-ID": os.environ["QA_M4_RUN_ID"],
        "X-M4-AVD": os.environ["QA_M4_AVD"],
        "X-M4-Fixture-ID": os.environ["QA_M4_FIXTURE_ID"],
        "X-M4-Start-Nonce": os.environ["QA_M4_START_NONCE"],
    },
)
try:
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(request, timeout=20) as response:
        if response.status < 200 or response.status >= 300:
            raise RuntimeError("db evidence returned non-success status")
        sys.stdout.buffer.write(response.read())
except (OSError, urllib.error.URLError, RuntimeError):
    print("db evidence request failed", file=sys.stderr)
    raise SystemExit(1)
PY
  local status=${PIPESTATUS[0]}
  set -e
  [[ "$status" -eq 0 && -s "$dir/db-evidence.json" ]] || {
    printf 'db_evidence_status=FAIL\n' >"$dir/db-evidence-error.txt"
    return 1
  }
  if ! python3 - "$dir/db-evidence.json" "$avd" "$nonce" "$RUN_ID" "$FIXTURE_ID" \
    2>"$dir/db-evidence-validation.stderr" <<'PY'
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
if set(payload["writeCounters"]) != required_counter_keys:
    raise SystemExit(1)
if any(
    type(value) is not int or value < 0
    for value in payload["writeCounters"].values()
):
    raise SystemExit(1)
if sum(payload["writeCounters"].values()) <= 0:
    raise SystemExit(1)
if payload["writeCounters"]["social_user_reports"] <= 0:
    raise SystemExit(1)
if set(payload["scopedCounters"]) != required_scoped_counter_keys:
    raise SystemExit(1)
if any(type(value) is not int or value <= 0 for value in payload["scopedCounters"].values()):
    raise SystemExit(1)
actual_invariant_keys = set(payload["authorityInvariants"])
if actual_invariant_keys != required_invariant_keys:
    raise SystemExit(1)
if any(value is not True for value in payload["authorityInvariants"].values()):
    raise SystemExit(1)
if payload["providerCalls"] not in (0, False, "0"):
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
  then
    printf 'db_evidence_status=FAIL\n' >"$dir/db-evidence-error.txt"
    return 1
  fi
  printf 'db_evidence_status=COLLECTED\n' >"$dir/db-evidence-status.txt"
}

contains_literal_file() {
  local value="$1"
  local path="$2"
  local status
  # 0 means found, 1 means absent, and 2 means the scanner could not read or
  # process the file. Callers must keep the third state fail-closed.
  [[ -n "$value" && -f "$path" && -r "$path" ]] || return 2
  # Keep protected values in shell memory/stdin; never put them in grep argv.
  grep -aFq -f <(printf '%s' "$value") "$path" 2>/dev/null
  status=$?
  case "$status" in
    0|1) return "$status" ;;
    *) return 2 ;;
  esac
}

contains_literal_stream() {
  local value="$1"
  local status
  [[ -n "$value" ]] || return 2
  # The APK bytes stay on stdin while the private pattern travels through a
  # process-substitution fd, so neither protected value becomes subprocess argv.
  # Do not use grep -q here: it can close the pipe early and make unzip report
  # SIGPIPE instead of its real archive status.
  grep -aF -f <(printf '%s' "$value") >/dev/null 2>/dev/null
  status=$?
  case "$status" in
    0|1) return "$status" ;;
    *) return 2 ;;
  esac
}

path_contains_protected_value() {
  local path="$1"
  local protected_value
  for protected_value in "$LIVE_PHONE" "$OAUTH_CLIENT_ID" "$DB_TOKEN" \
    "$RELAY_TOKEN_A" "$RELAY_TOKEN_B"; do
    [[ -z "$protected_value" || "$path" != *"$protected_value"* ]] || return 0
  done
  [[ "$path" =~ 1[3-9][0-9]{9} ]] && return 0
  return 1
}

publish_scan_output() {
  local temporary="$1"
  local final="$2"
  python3 - "$temporary" "$final" <<'PY'
import os
import stat
import sys

temporary, final = sys.argv[1:]
try:
    mode = os.lstat(temporary).st_mode
    if not stat.S_ISREG(mode):
        raise OSError("scan output is not regular")
    if os.path.lexists(final) and stat.S_ISDIR(os.lstat(final).st_mode):
        raise OSError("scan output destination is a directory")
    os.replace(temporary, final)
    result = os.lstat(final)
    if not stat.S_ISREG(result.st_mode) or result.st_nlink != 1:
        raise OSError("scan output publication was not exclusive")
except OSError:
    raise SystemExit(1)
PY
}

scan_apk_literal() {
  local value="$1"
  local apk="$2"
  local statuses unzip_status='' grep_status=''

  # Return 0 for absent, 1 for found, and 2 for an unzip/grep failure. The
  # pipeline runs with errexit disabled only inside this subshell so its two
  # component statuses can be captured without weakening the runner itself.
  statuses="$(
    set +e
    unzip -p "$apk" 2>/dev/null | contains_literal_stream "$value"
    local -a pipeline_status=("${PIPESTATUS[@]}")
    printf '%s %s\n' "${pipeline_status[0]}" "${pipeline_status[1]}"
  )" || return 2
  IFS=' ' read -r unzip_status grep_status <<<"$statuses" || return 2
  [[ "$unzip_status" =~ ^[0-9]+$ && "$grep_status" =~ ^[0-9]+$ ]] || return 2
  (( unzip_status == 0 )) || return 2
  case "$grep_status" in
    0) return 1 ;;
    1) return 0 ;;
    *) return 2 ;;
  esac
}

secret_scan() {
  local dir="$1"
  local final_output="$dir/secret-scan.txt"
  local output list nodes
  local bad=0 path base protected_value scan_status
  output="$(mktemp "$dir/.m4-secret-scan-output.XXXXXX")" || return 1
  list="$(mktemp "$dir/.m4-secret-scan-files.XXXXXX")" || {
    printf 'scanner_error=secret_scan_list_unwritable\n' >>"$output" || return 1
    return 1
  }
  nodes="$(mktemp "$dir/.m4-secret-scan-nodes.XXXXXX")" || {
    rm -f "$list" || true
    printf 'scanner_error=secret_scan_node_list_unwritable\n' >>"$output" || return 1
    return 1
  }
  if ! find "$dir" ! -type f ! -type d -print0 >"$nodes" 2>/dev/null; then
    printf 'scanner_error=secret_scan_node_find_failed\n' >>"$output" || return 1
    bad=1
  elif [[ -s "$nodes" ]]; then
    printf 'scanner_error=non_regular_artifact_node\n' >>"$output" || return 1
    bad=1
  fi
  if ! find "$dir" -type f ! -path "$output" ! -path "$final_output" \
    ! -path "$list" ! -path "$nodes" -print0 >"$list" 2>/dev/null; then
    printf 'scanner_error=secret_scan_find_failed\n' >>"$output" || return 1
    bad=1
  fi
  while IFS= read -r -d '' path; do
    if path_contains_protected_value "$path"; then
      printf 'forbidden_artifact_path_value=true\n' >>"$output" || return 1
      bad=1
      continue
    fi
    if [[ ! -f "$path" || ! -r "$path" ]]; then
      printf 'scanner_error=unreadable_artifact\n' >>"$output" || return 1
      bad=1
      continue
    fi
    base="${path##*/}"
    if [[ "$base" == '.env.local' || "$path" == *'.env.local'* ||
      "$path" == *'contract-server'* || "$path" == *':8765'* ]]; then
      printf 'forbidden_artifact_name=true\n' >>"$output" || return 1
      bad=1
    fi
    for protected_value in "$LIVE_PHONE" "$OAUTH_CLIENT_ID" "$DB_TOKEN" \
      "$RELAY_TOKEN_A" "$RELAY_TOKEN_B"; do
      if contains_literal_file "$protected_value" "$path"; then
        printf 'runtime_secret_value_found=true\n' >>"$output" || return 1
        bad=1
      else
        scan_status=$?
        if [[ "$scan_status" -ne 1 ]]; then
          printf 'scanner_error=secret_literal_grep_failed\n' >>"$output" || return 1
          bad=1
        fi
      fi
    done
    if grep -aEiq '1[3-9][0-9]{9}|Bearer[[:space:]]+[A-Za-z0-9._~+/=-]{12,}' "$path" 2>/dev/null; then
      printf 'credential_like_value_found=true\n' >>"$output" || return 1
      bad=1
    else
      scan_status=$?
      if [[ "$scan_status" -gt 1 ]]; then
        printf 'scanner_error=credential_grep_failed\n' >>"$output" || return 1
        bad=1
      fi
    fi
    if python3 - "$path" <<'PY'
import re
import sys

try:
    with open(sys.argv[1], "rb") as handle:
        text = handle.read().decode("utf-8", errors="ignore")
except OSError:
    raise SystemExit(2)
keys = (
    "access_token", "refresh_token", "accessToken", "refreshToken",
    "token", "password", "client_secret", "clientSecret", "oauthClientId",
    "mobile", "phone",
)
for key in keys:
    pattern = r'"' + re.escape(key) + r'"\s*:\s*"([^"]+)"'
    for match in re.finditer(pattern, text):
        value = match.group(1)
        if value and not value.startswith("[REDACTED"):
            raise SystemExit(1)
raise SystemExit(0)
PY
    then
      :
    else
      scan_status=$?
      if [[ "$scan_status" -eq 1 ]]; then
        printf 'credential_field_value_found=true\n' >>"$output" || return 1
      else
        printf 'scanner_error=python_secret_scan_failed\n' >>"$output" || return 1
      fi
      bad=1
    fi
  done <"$list"
  if ! rm -f "$list" "$nodes"; then
    printf 'scanner_error=secret_scan_list_cleanup_failed\n' >>"$output" || return 1
    bad=1
  fi
  if [[ "$bad" -eq 0 ]]; then
    printf 'secret_scan=0\n' >>"$output" || return 1
    publish_scan_output "$output" "$final_output" || return 1
    return 0
  fi
  printf 'secret_scan=FAIL\n' >>"$output" || return 1
  publish_scan_output "$output" "$final_output" || return 1
  return 1
}

apk_scan() {
  local dir="$1"
  local final_output="$dir/apk-secret-scan.txt"
  local output list
  local bad=0 apk apk_count=0 scan_status protected_value
  output="$(mktemp "$dir/.m4-apk-scan-output.XXXXXX")" || return 1
  list="$(mktemp "$dir/.m4-apk-scan-files.XXXXXX")" || {
    printf 'scanner_error=apk_scan_list_unwritable\n' >>"$output" || return 1
    return 1
  }
  if ! find "$PROJECT_ROOT/build/app/outputs" -type f -name '*.apk' -print0 >"$list" 2>/dev/null; then
    printf 'scanner_error=apk_find_failed\n' >>"$output" || return 1
    bad=1
  fi
  while IFS= read -r -d '' apk; do
    apk_count=$((apk_count + 1))
    if path_contains_protected_value "$apk"; then
      printf 'forbidden_apk_path_value=true\n' >>"$output" || return 1
      bad=1
      continue
    fi
    if [[ ! -f "$apk" || ! -r "$apk" ]]; then
      printf 'scanner_error=unreadable_apk\n' >>"$output" || return 1
      bad=1
      continue
    fi
    if ! unzip -t "$apk" >/dev/null 2>&1; then
      printf 'scanner_error=corrupt_or_unreadable_apk\n' >>"$output" || return 1
      bad=1
      continue
    fi
    for protected_value in "$LIVE_PHONE" "$OAUTH_CLIENT_ID" "$RELAY_TOKEN_A" "$RELAY_TOKEN_B"; do
      if scan_apk_literal "$protected_value" "$apk"; then
        scan_status=0
      else
        scan_status=$?
      fi
      case "$scan_status" in
        0) ;;
        1)
          printf 'apk_secret_value_found=true\n' >>"$output" || return 1
          bad=1
          ;;
        *)
          printf 'scanner_error=apk_unzip_or_grep_failed\n' >>"$output" || return 1
          bad=1
          ;;
      esac
    done
  done <"$list"
  if ! rm -f "$list"; then
    printf 'scanner_error=apk_scan_list_cleanup_failed\n' >>"$output" || return 1
    bad=1
  fi
  if [[ "$apk_count" -eq 0 ]]; then
    printf 'apk_missing=true\n' >>"$output" || return 1
    bad=1
  fi
  if [[ "$bad" -eq 0 ]]; then
    printf 'apk_secret_scan=0\n' >>"$output" || return 1
    publish_scan_output "$output" "$final_output" || return 1
    return 0
  fi
  printf 'apk_secret_scan=FAIL\n' >>"$output" || return 1
  publish_scan_output "$output" "$final_output" || return 1
  return 1
}

run_one() {
  local avd="$1"; shift
  local api="$1"; shift
  local profile="$1"; shift
  local physical="$1"; shift
  local density="$1"; shift
  local width="$1"; shift
  local height="$1"; shift
  local dpr="$1"; shift
  local serial_override="$1"; shift
  local avd_name="$1"
  local dir="$ARTIFACT_ROOT/$avd"
  mkdir -p "$dir/logs" "$dir/screenshots"
  local serial viewport
  serial="$(select_device "$avd" "$api" "$serial_override" "$avd_name" "$dir")"
  viewport="$(configure_viewport "$serial" "$physical" "$density" || true)"
  [[ -n "$viewport" ]] || { printf 'result=FAIL\nreason=viewport_override_rejected\n' >"$dir/result.txt"; OVERALL_RESULT='FAIL'; return 1; }
  write_environment "$dir" "$avd" "$api" "$profile" "$width" "$height" "$dpr" "$serial" "$viewport"

  if [[ "$avd" == 'AVD-B' ]]; then
    wait_for_sms_cooldown
  fi
  db_evidence_start "$dir" "$avd" || {
    printf 'result=FAIL\nreason=db_evidence_start_failed\n' >"$dir/result.txt"
    OVERALL_RESULT='FAIL'
    return 1
  }
  record_sms_cooldown_start "$avd"

  # A bounded post-run dump avoids leaving a background `adb logcat` process
  # that can ignore TERM and block the evidence lane after Flutter exits.
  adb -s "$serial" logcat -G 16M >/dev/null 2>&1 || true
  adb -s "$serial" logcat -c >/dev/null 2>&1 || true
  local relay_token="$RELAY_TOKEN_A"
  [[ "$avd" == 'AVD-B' ]] && relay_token="$RELAY_TOKEN_B"
  feed_runtime_relay_token "$serial" "$relay_token"
  set +e
  run_with_timeout 1500 30 \
    env -u QA_LIVE_PHONE -u QA_OAUTH_CLIENT_ID \
      -u QA_DB_EVIDENCE_URL -u QA_DB_EVIDENCE_TOKEN \
      -u DEVELOPMENT_OUTBOX_KEY -u QA_DEVELOPMENT_OUTBOX_KEY \
      -u OAUTH_CLIENT_ID -u M3_OAUTH_CLIENT_ID -u M3_API_BASE_URL -u QA_API_BASE_URL \
      QA_SCREENSHOT_DIR="$dir/screenshots" \
      "$FLUTTER_BIN" drive --driver=test_driver/integration_test.dart \
      --target=integration_test/m4_first_party_live_integration_test.dart \
      --device-id="$serial" --debug --no-pub \
      --dart-define=BACKEND_MODE=live --dart-define=APP_ENV=development \
      --dart-define=ALLOW_INSECURE_HTTP=true --dart-define=API_BASE_URL="$BACKEND_BASE_URL" \
      --dart-define=API_TIMEOUT_SECONDS=15 \
      --dart-define=M4_RUNTIME_CONFIG_PORT="$RELAY_PORT" \
      --dart-define=QA_M4_FIXTURE_ID="$FIXTURE_ID" \
      --dart-define=M4_EXPECTED_FLUTTER_SHA="$FLUTTER_SHA_EXPECTED" \
      --dart-define=M4_EXPECTED_BACKEND_SHA="$BACKEND_SHA_EXPECTED" \
      --dart-define=QA_AVD_ID="$avd" \
      --dart-define=QA_EXPECTED_VIEWPORT_WIDTH="$width" \
      --dart-define=QA_EXPECTED_VIEWPORT_HEIGHT="$height" \
      --dart-define=QA_EXPECTED_DPR="$dpr" 2>&1 | sanitize >"$dir/logs/flutter-drive.log"
  local drive_status=${PIPESTATUS[0]}
  stop_runtime_relay_token_feeder
  clear_runtime_relay_token "$serial"
  adb -s "$serial" logcat -d -v threadtime \
    2>"$dir/logs/logcat-adb.stderr" | \
    sanitize >"$dir/logs/logcat-full.txt" \
      2>"$dir/logs/logcat-sanitizer.stderr"
  local logcat_status=${PIPESTATUS[0]}
  set -e

  write_route_evidence "$dir"
  local db_status='FAIL'
  if db_evidence "$dir" "$avd" "$DB_START_NONCE"; then
    db_status="$(sed -n 's/^db_evidence_status=//p' "$dir/db-evidence-status.txt" 2>/dev/null || printf FAIL)"
  fi
  local screenshot_count marker_count provider_count invariant_count hard_count crash_count
  screenshot_count="$(find "$dir/screenshots" -type f -name '*.png' -size +0c | wc -l | tr -d ' ')"
  marker_count="$(awk -F '::' '/M4_ROUTE_STATUS::/ {print $2 "::" $3 "::" $4 "::" $5 "::" $6}' "$dir/logs/flutter-drive.log" | sort -u | wc -l | tr -d ' ')"
  provider_marker_count="$(grep -Ec 'M4_PROVIDER_CALLS::' "$dir/logs/flutter-drive.log" || true)"
  provider_count="$(grep -Ec '(^|[[:space:]])M4_PROVIDER_CALLS::0($|[[:space:]])' "$dir/logs/flutter-drive.log" || true)"
  provider_nonzero_count="$(awk '/M4_PROVIDER_CALLS::/ && $0 !~ /M4_PROVIDER_CALLS::0([[:space:]]|$)/ {count += 1} END {print count + 0}' "$dir/logs/flutter-drive.log")"
  invariant_count="$(grep -Ec 'M4_AUTHORITY_INVARIANT::' "$dir/logs/flutter-drive.log" || true)"
  hard_count="$(cat "$dir/logs/logcat-full.txt" "$dir/logs/flutter-drive.log" | grep -Eci 'FATAL EXCEPTION|AndroidRuntime|Fatal signal [0-9]+|ANR in com\.kong373\.voice_social_app|MissingPluginException|RenderFlex overflow|Unhandled Exception|EXCEPTION CAUGHT BY|Failed assertion' || true)"
  crash_count="$(cat "$dir/logs/logcat-full.txt" "$dir/logs/flutter-drive.log" | grep -Eci 'FATAL EXCEPTION|Fatal signal [0-9]+|ANR in com\.kong373\.voice_social_app' || true)"
  grep -Ei 'EXCEPTION CAUGHT BY|Unhandled Exception|Failed assertion|RenderFlex overflow' "$dir/logs/flutter-drive.log" >"$dir/logs/flutter-errors.txt" || true
  grep -Ei 'FATAL EXCEPTION|AndroidRuntime|Fatal signal [0-9]+|ANR in com\.kong373\.voice_social_app' "$dir/logs/logcat-full.txt" "$dir/logs/flutter-drive.log" >"$dir/logs/crash-anr.txt" || true

  local expected_marker="M4_VIEWPORT::$avd::"$width"x"$height"::$dpr"
  local acceptance_marker
  acceptance_marker="$(grep -Ec '(^|[[:space:]])M4_ACCEPTANCE::PASS($|[[:space:]])' "$dir/logs/flutter-drive.log" || true)"
  acceptance_failure_marker="$(grep -Ec '(^|[[:space:]])M4_ACCEPTANCE::FAIL($|[[:space:]])' "$dir/logs/flutter-drive.log" || true)"
  bad_route_status_count="$(awk -F '::' '/M4_ROUTE_STATUS::/ {if ($5 !~ /^[2-4][0-9][0-9]$/) count += 1} END {print count + 0}' "$dir/logs/flutter-drive.log")"
  local secret_status='PASS'
  local apk_status='PASS'
  secret_scan "$dir" || secret_status='FAIL'
  apk_scan "$dir" || apk_status='FAIL'
  local result='PASS'
  local reason='complete'
  if [[ "$drive_status" -ne 0 ]]; then result='FAIL'; reason="flutter_drive_exit_$drive_status"
  elif [[ "$logcat_status" -ne 0 || ! -s "$dir/logs/logcat-full.txt" ]]; then result='FAIL'; reason='logcat_capture_failed'
  elif [[ "$marker_count" -lt 10 ]]; then result='FAIL'; reason='insufficient_http_route_markers'
  elif [[ "$provider_marker_count" -ne 1 || "$provider_count" -ne 1 || "$provider_nonzero_count" -ne 0 ]]; then result='FAIL'; reason='provider_calls_marker_missing_or_nonzero'
  elif [[ "$invariant_count" -lt 5 ]]; then result='FAIL'; reason='insufficient_authority_invariants'
  elif [[ "$screenshot_count" -lt 4 ]]; then result='FAIL'; reason='insufficient_screenshots'
  elif [[ "$acceptance_marker" -ne 1 || "$acceptance_failure_marker" -ne 0 ]]; then result='FAIL'; reason='acceptance_marker_missing_or_failed'
  elif [[ "$bad_route_status_count" -ne 0 ]]; then result='FAIL'; reason='route_status_missing_or_failed'
  elif ! grep -Fq "$expected_marker" "$dir/logs/flutter-drive.log"; then result='FAIL'; reason='viewport_marker_missing'
  elif [[ "$hard_count" -ne 0 || "$crash_count" -ne 0 ]]; then result='FAIL'; reason='hard_flutter_or_android_finding'
  elif [[ "$db_status" != 'COLLECTED' ]]; then result='FAIL'; reason='db_write_evidence_missing_or_failed'
  elif [[ "$secret_status" != PASS || "$apk_status" != PASS ]]; then result='FAIL'; reason='secret_scan_failed'
  fi
  {
    printf 'result=%s\nreason=%s\navd=%s\napi_level=%s\nprofile=%s\nserial=%s\n' "$result" "$reason" "$avd" "$api" "$profile" "$serial"
    printf 'run_id=%s\nfixture_id=%s\nfixture_status=%s\ndb_start_nonce=%s\ntested_git_sha=%s\nflutter_sha=%s\nbackend_sha=%s\nhttp_route_marker_count=%s\nauthority_invariant_count=%s\n' \
      "$RUN_ID" "$FIXTURE_ID" "$FIXTURE_STATUS" "$DB_START_NONCE" "$FLUTTER_SHA_ACTUAL" "$FLUTTER_SHA_ACTUAL" "$BACKEND_SHA_ACTUAL" "$marker_count" "$invariant_count"
    printf 'android_host_source_sha256=%s\n' "$ANDROID_HOST_SOURCE_SHA256"
    printf 'flutter_version=%s\ndart_version=%s\nflutter_revision=%s\n' \
      "$FLUTTER_FRAMEWORK_VERSION" "$FLUTTER_DART_VERSION" "$FLUTTER_FRAMEWORK_REVISION"
    printf 'screenshot_count=%s\nhard_finding_count=%s\ncrash_anr_count=%s\n' "$screenshot_count" "$hard_count" "$crash_count"
    printf 'acceptance_status=%s\nprovider_calls_made=false\ndb_evidence=%s\nsecret_scan=%s\napk_secret_scan=%s\n' "$([[ "$result" == PASS ]] && printf PASS || printf FAIL)" "$db_status" "$secret_status" "$apk_status"
  } >"$dir/result.txt"
  [[ "$result" == PASS ]] || { OVERALL_RESULT='FAIL'; return 1; }
  return 0
}

start_relay
# AVD-A then AVD-B is intentional and produces independent API36 and API35
# evidence even when only one emulator slot is available.
run_one AVD-A "$A_API" "$A_PROFILE" "$A_PHYSICAL" "$A_DENSITY" "$A_WIDTH" "$A_HEIGHT" "$A_DPR" "$AVD_A_SERIAL" "$AVD_A_NAME" || true
run_one AVD-B "$B_API" "$B_PROFILE" "$B_PHYSICAL" "$B_DENSITY" "$B_WIDTH" "$B_HEIGHT" "$B_DPR" "$AVD_B_SERIAL" "$AVD_B_NAME" || true
if ! secret_scan "$ARTIFACT_ROOT"; then
  OVERALL_RESULT='FAIL'
fi
[[ "$OVERALL_RESULT" == PASS ]] || exit 1
exit 0
