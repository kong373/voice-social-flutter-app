#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

# M5 is provider-live.  It has an independent marker namespace and never
# treats a zero-call/provider-blocked run as a PASS.
readonly PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
readonly BACKEND_BASE_URL='http://10.0.2.2:18080/'
readonly APP_PACKAGE='com.kong373.voice_social_app'
readonly EXPECTED_FLUTTER_VERSION='3.44.7'
readonly EXPECTED_DART_VERSION='3.12.2'
readonly EXPECTED_FLUTTER_REVISION='84fc5cbb223bc12f83d65b647ff8a56caf779ffd'
readonly RUNTIME_TOKEN_FILE='cache/m5-runtime-relay-token'
readonly RUNTIME_TOKEN_TMP_FILE="$RUNTIME_TOKEN_FILE.tmp"
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

env_value() { printenv "$1" || true; }
is_true() { [[ "${1:-}" == 'true' || "${1:-}" == '1' || "${1:-}" == 'yes' ]]; }
required() {
  local value
  value="$(env_value "$1")"
  [[ -n "$value" ]] || { printf '%s is required\n' "$1" >&2; exit 64; }
  printf '%s' "$value"
}

readonly DRY_RUN="$(env_value QA_M5_DRY_RUN)"
readonly ARTIFACT_ROOT="$(required QA_ARTIFACT_ROOT)"
readonly FLUTTER_SHA_EXPECTED="$(env_value QA_FLUTTER_SHA)"
readonly BACKEND_SHA_EXPECTED="$(env_value QA_BACKEND_SHA)"
readonly BACKEND_REPO="$(env_value QA_BACKEND_REPO)"
readonly BACKEND_CONTAINER="$(env_value QA_BACKEND_CONTAINER)"
readonly RUN_ID="$(env_value QA_M5_RUN_ID)"
readonly FIXTURE_ID="$(env_value QA_M5_FIXTURE_ID)"
readonly EXTERNAL_DB_URL="$(env_value QA_DB_EVIDENCE_URL)"
readonly EXTERNAL_DB_TOKEN="$(env_value QA_DB_EVIDENCE_TOKEN)"
DB_URL="$EXTERNAL_DB_URL"
DB_TOKEN="$EXTERNAL_DB_TOKEN"
readonly MYSQL_CONTAINER_CONFIG="$(env_value QA_M5_MYSQL_CONTAINER)"
readonly LIVE_PHONE="$(env_value QA_LIVE_PHONE)"
readonly RECEIVER_PHONE="$(env_value QA_M5_RECEIVER_PHONE)"
readonly OAUTH_CLIENT_ID="$(env_value QA_OAUTH_CLIENT_ID)"
readonly BACKEND_DIGEST_EXPECTED="$(env_value QA_BACKEND_DIGEST)"
readonly AVD_A_SERIAL="$(env_value QA_AVD_A_SERIAL)"
readonly AVD_B_SERIAL="$(env_value QA_AVD_B_SERIAL)"
readonly AVD_A_NAME="$(env_value QA_AVD_A_NAME)"
readonly AVD_B_NAME="$(env_value QA_AVD_B_NAME)"
readonly ENABLE_ALIPAY="$(env_value QA_M5_ENABLE_ALIPAY_APP_PAY)"
readonly PAYMENT_ALLOW_REQUEST="$(env_value QA_M5_ALLOW_EXTERNAL_PAYMENT)"
readonly PAYMENT_CONFIRMATION="$(env_value QA_M5_PAYMENT_CONFIRMATION)"
readonly PAYMENT_SCENARIO="$(env_value QA_M5_ALIPAY_SCENARIO)"
readonly PAYMENT_SUCCESS_CONFIRMATION="$(env_value QA_M5_SUCCESS_CONFIRMATION)"

readonly SUMMARY_FILE="$ARTIFACT_ROOT/summary.txt"
readonly MANIFEST_FILE="$ARTIFACT_ROOT/evidence-manifest.sha256"
readonly STARTED_SERIALS_FILE="$ARTIFACT_ROOT/.started-emulator-serials"
RELAY_PID=''
RELAY_PORT=''
RELAY_TOKEN_A=''
RELAY_TOKEN_B=''
RUNTIME_TOKEN_FEEDER_PID=''
DB_HELPER_PID=''
DB_HELPER_STATE_DIR=''
DB_HELPER_LOG=''
FLUTTER_BIN=''
FLUTTER_FRAMEWORK_VERSION=''
FLUTTER_DART_VERSION=''
FLUTTER_FRAMEWORK_REVISION=''
FLUTTER_SHA_ACTUAL=''
BACKEND_SHA_ACTUAL=''
BACKEND_SOURCE_DIGEST_ACTUAL=''
ANDROID_HOST_SOURCE_SHA256=''
APK_SHA_EXPECTED=''
ATTESTED_APK_PATH=''
OVERALL_RESULT='PASS'
LAST_RESULT_REASON='not_started'
PAYMENT_OPT_IN='false'
PAYMENT_INVOKED='false'
DB_START_NONCE_A=''
DB_START_NONCE_B=''
declare -a DB_EVIDENCE_RAW_FILES=()

fail() {
  OVERALL_RESULT='FAIL'
  LAST_RESULT_REASON="$1"
  printf 'M5 preflight failed: %s\n' "$1" >&2
  exit 64
}

validate_external_db_url() {
  local url="$1"
  # Only an HTTPS endpoint may be supplied by the operator.  The sole HTTP
  # exception is the exact 127.0.0.1 endpoint generated below for the local
  # helper; it never enters this function.
  [[ "$url" == https://* ]] || return 1
  M5_EXTERNAL_DB_URL="$url" PYTHONPATH="$PROJECT_ROOT/tool/qa" python3 - <<'PY'
import os
from m5_vendor_db_evidence import validate_evidence_url

try:
    validate_evidence_url(os.environ["M5_EXTERNAL_DB_URL"])
except Exception:
    raise SystemExit(1)
PY
}

validate_local_db_url() {
  local url="$1"
  M5_LOCAL_DB_URL="$url" PYTHONPATH="$PROJECT_ROOT/tool/qa" python3 - <<'PY'
import os
from m5_vendor_db_evidence import validate_evidence_url

try:
    validate_evidence_url(os.environ["M5_LOCAL_DB_URL"], allow_loopback_http=True)
except Exception:
    raise SystemExit(1)
PY
}

create_safe_artifact_root() {
  python3 - "$ARTIFACT_ROOT" <<'PY'
import os
import stat
import sys
from pathlib import Path
raw = sys.argv[1]
path = Path(raw)
if not path.is_absolute() or os.path.normpath(raw) != raw or os.path.lexists(raw):
    raise SystemExit(1)
missing = []
ancestor = path.parent
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
PY
}

assert_flutter_checkout_clean() {
  local status
  status="$(git -C "$PROJECT_ROOT" status --porcelain=v1 --untracked-files=all --ignore-submodules=none)" || fail 'Flutter checkout status unavailable'
  [[ -z "$status" ]] || fail 'Flutter checkout is dirty or has non-ignored untracked files'
}

attest_flutter_sdk() {
  local -a facts=()
  local fact
  FLUTTER_BIN="$(command -v flutter || true)"
  [[ -n "$FLUTTER_BIN" ]] || fail 'Flutter executable could not be resolved'
  while IFS= read -r fact; do facts+=("$fact"); done < <("$FLUTTER_BIN" --version --machine 2>/dev/null | python3 -c '
import json
import sys
try:
    data = json.load(sys.stdin)
    print(data["frameworkVersion"])
    print(data["dartSdkVersion"])
    print(data["frameworkRevision"])
except (KeyError, TypeError, ValueError):
    raise SystemExit(1)
')
  [[ "${#facts[@]}" -eq 3 ]] || fail 'Flutter SDK metadata is invalid'
  FLUTTER_FRAMEWORK_VERSION="${facts[0]}"
  FLUTTER_DART_VERSION="${facts[1]}"
  FLUTTER_FRAMEWORK_REVISION="${facts[2]}"
  [[ "$FLUTTER_FRAMEWORK_VERSION" == "$EXPECTED_FLUTTER_VERSION" ]] || fail 'Flutter version mismatch'
  [[ "$FLUTTER_DART_VERSION" == "$EXPECTED_DART_VERSION" ]] || fail 'Dart version mismatch'
  [[ "$FLUTTER_FRAMEWORK_REVISION" == "$EXPECTED_FLUTTER_REVISION" ]] || fail 'Flutter framework revision mismatch'
}

attest_backend() {
  [[ -d "$BACKEND_REPO/.git" || -f "$BACKEND_REPO/.git" ]] || fail 'backend repository is not Git'
  local status
  status="$(git -C "$BACKEND_REPO" status --porcelain=v1 --untracked-files=all)" || fail 'backend status unavailable'
  [[ -z "$status" ]] || fail 'backend checkout is dirty or has non-ignored untracked files'
  BACKEND_SHA_ACTUAL="$(git -C "$BACKEND_REPO" rev-parse --verify HEAD)" || fail 'backend SHA unavailable'
  [[ "$BACKEND_SHA_ACTUAL" == "$BACKEND_SHA_EXPECTED" ]] || fail 'QA_BACKEND_SHA mismatch'
  [[ "$BACKEND_DIGEST_EXPECTED" =~ ^[0-9a-f]{64}$ ]] || fail 'QA_BACKEND_DIGEST must be a lowercase SHA-256'
  local digest_script="$BACKEND_REPO/scripts/compute-backend-source-digest.sh"
  [[ -x "$digest_script" ]] || fail 'backend source digest script missing'
  BACKEND_SOURCE_DIGEST_ACTUAL="$(cd "$BACKEND_REPO" && ./scripts/compute-backend-source-digest.sh)" ||
    fail 'backend source digest unavailable'
  [[ "$BACKEND_SOURCE_DIGEST_ACTUAL" == "$BACKEND_DIGEST_EXPECTED" ]] || fail 'backend source digest mismatch'
}

attest_serving_backend() {
  local docker_bin container_state health_status digest port_json
  docker_bin="$(command -v docker || true)"
  [[ -n "$docker_bin" ]] || fail 'docker executable is unavailable'
  [[ "$BACKEND_CONTAINER" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$ ]] ||
    fail 'QA_BACKEND_CONTAINER is invalid'
  container_state="$("$docker_bin" inspect --format '{{.State.Status}}' "$BACKEND_CONTAINER" 2>/dev/null || true)"
  [[ "$container_state" == 'running' ]] || fail 'serving backend container is not running'
  health_status="$("$docker_bin" inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "$BACKEND_CONTAINER" 2>/dev/null || true)"
  [[ "$health_status" == 'healthy' ]] || fail 'serving backend container is not healthy'
  digest="$("$docker_bin" exec "$BACKEND_CONTAINER" /bin/sh -c \
    'test -f /app/backend-source.sha256 && cat /app/backend-source.sha256' 2>/dev/null || true)"
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || fail 'serving backend source digest is invalid'
  [[ "$digest" == "$BACKEND_SOURCE_DIGEST_ACTUAL" && "$digest" == "$BACKEND_DIGEST_EXPECTED" ]] ||
    fail 'serving backend source digest mismatch'
  port_json="$("$docker_bin" inspect --format '{{json .NetworkSettings.Ports}}' "$BACKEND_CONTAINER" 2>/dev/null || true)"
  python3 - "$port_json" <<'PY' || fail 'serving backend port 18080 is not published'
import json
import sys

try:
    ports = json.loads(sys.argv[1])
    bindings = ports.get("18080/tcp")
except (TypeError, ValueError, AttributeError):
    raise SystemExit(1)
if not isinstance(bindings, list) or not any(
    isinstance(binding, dict) and binding.get("HostPort") == "18080"
    for binding in bindings
):
    raise SystemExit(1)
PY
}

prepare_android_host() {
  local staging_root generated_project
  if [[ ! -d "$PROJECT_ROOT/android" ]]; then
    staging_root="$(mktemp -d "${TMPDIR:-/tmp}/voice-social-m5-android-host.XXXXXX")" ||
      fail 'Android host staging directory creation failed'
    generated_project="$staging_root/voice_social_app"
    "$FLUTTER_BIN" create --platforms=android --android-language=kotlin --org=com.kong373 \
      --project-name=voice_social_app --no-pub "$generated_project" >/dev/null 2>&1 || {
      rm -rf -- "$staging_root"
      fail 'Flutter Android host generation failed'
    }
    [[ -d "$generated_project/android" ]] || {
      rm -rf -- "$staging_root"
      fail 'generated Flutter Android host is missing'
    }
    mv "$generated_project/android" "$PROJECT_ROOT/android" || {
      rm -rf -- "$staging_root"
      fail 'generated Flutter Android host installation failed'
    }
    rm -rf -- "$staging_root"
  fi
  [[ -f "$PROJECT_ROOT/android/settings.gradle" || -f "$PROJECT_ROOT/android/settings.gradle.kts" ]] || fail 'Android host is missing'
}

prepare_android_audio_manifest() {
  local script relative
  script="$PROJECT_ROOT/tool/prepare_android_audio_manifest.py"
  relative='tool/prepare_android_audio_manifest.py'
  [[ -f "$script" ]] || fail 'tracked Android audio manifest helper is missing'
  git -C "$PROJECT_ROOT" ls-files --error-unmatch -- "$relative" >/dev/null 2>&1 ||
    fail 'Android audio manifest helper is not tracked'
  python3 "$script" "$PROJECT_ROOT" >/dev/null 2>&1 ||
    fail 'Android audio manifest preparation failed'
}

attest_android_host() {
  ANDROID_HOST_SOURCE_SHA256="$(python3 - "$PROJECT_ROOT/android" <<'PY'
import hashlib
import os
import sys
from pathlib import Path
root = Path(sys.argv[1]).resolve()
excluded_directories = {".gradle", ".kotlin", "build", ".cxx"}
excluded_files = {Path("local.properties"), Path("app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java")}
rows = []
def digest_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while True:
            chunk = stream.read(1024 * 1024)
            if not chunk: return digest.digest()
            digest.update(chunk)
for directory, names, files in os.walk(root, followlinks=False):
    base = Path(directory)
    for name in list(names):
        candidate = base / name
        if candidate.is_symlink(): raise SystemExit(1)
        if name in excluded_directories: names.remove(name)
    for name in files:
        candidate = base / name
        relative = candidate.relative_to(root)
        if relative in excluded_files or name.endswith(".iml"): continue
        if candidate.is_symlink() or not candidate.is_file(): raise SystemExit(1)
        rows.append((relative.as_posix(), digest_file(candidate)))
digest = hashlib.sha256()
for relative, content_digest in sorted(rows):
    digest.update(relative.encode())
    digest.update(b"\0")
    digest.update(content_digest)
print(digest.hexdigest())
PY
  )" || fail 'Android host source attestation failed'
  [[ "$ANDROID_HOST_SOURCE_SHA256" =~ ^[0-9a-f]{64}$ ]] || fail 'Android host source digest invalid'
}

attest_debug_apk() {
  local alipay_define='false' payment_define='false' confirmation_define='' success_confirmation_define='' apk_source=''
  is_true "$ENABLE_ALIPAY" && alipay_define='true'
  if [[ "$PAYMENT_OPT_IN" == 'true' ]]; then
    payment_define='true'
    confirmation_define='--dart-define=M5_PAYMENT_CONFIRMATION=I_UNDERSTAND_SANDBOX_PAYMENT'
    if [[ "${PAYMENT_SCENARIO:-none}" == 'success' ]]; then
      success_confirmation_define='--dart-define=M5_SUCCESS_CONFIRMATION=I_UNDERSTAND_SANDBOX_SUCCESS_PAYMENT'
    fi
  fi
  # Build the exact integration-test APK once. The same immutable binary is copied to
  # both AVDs; role and viewport are runtime relay values so the database
  # attestation can bind one immutable APK SHA across A and B.
  "$FLUTTER_BIN" build apk --debug \
    --target=integration_test/m5_vendor_live_integration_test.dart \
    --dart-define=BACKEND_MODE=live \
    --dart-define=APP_ENV=development --dart-define=ALLOW_INSECURE_HTTP=true \
    --dart-define=API_BASE_URL="$BACKEND_BASE_URL" --dart-define=API_TIMEOUT_SECONDS=15 \
    --dart-define=ENABLE_TENCENT_IM=true \
    --dart-define=ENABLE_ALIPAY_APP_PAY="$alipay_define" \
    --dart-define=M5_RUNTIME_CONFIG_PORT="$RELAY_PORT" \
    --dart-define=QA_M5_FIXTURE_ID="$FIXTURE_ID" \
    --dart-define=M5_EXPECTED_FLUTTER_SHA="$FLUTTER_SHA_ACTUAL" \
    --dart-define=M5_EXPECTED_BACKEND_SHA="$BACKEND_SHA_ACTUAL" \
    --dart-define=M5_EXPECTED_BACKEND_DIGEST="$BACKEND_SOURCE_DIGEST_ACTUAL" \
    --dart-define=QA_M5_RUN_ID="$RUN_ID" \
    --dart-define=M5_ALLOW_EXTERNAL_PAYMENT="$payment_define" \
    --dart-define=M5_ALIPAY_SCENARIO="${PAYMENT_SCENARIO:-none}" \
    $confirmation_define $success_confirmation_define >/dev/null 2>&1 ||
    fail 'attested APK build failed'
  apk_source="$PROJECT_ROOT/build/app/outputs/flutter-apk/app-debug.apk"
  [[ -f "$apk_source" ]] || fail 'attested APK is missing at the expected output path'
  ATTESTED_APK_PATH="$apk_source"
  APK_SHA_EXPECTED="$(shasum -a 256 "$apk_source" | awk '{print $1}')"
  [[ "$APK_SHA_EXPECTED" =~ ^[0-9a-f]{64}$ ]] || fail 'attested APK SHA is invalid'
}

install_attested_apk() {
  [[ -n "$ATTESTED_APK_PATH" && -f "$ATTESTED_APK_PATH" ]] ||
    fail 'attested APK path is missing'
  for avd in AVD-A AVD-B; do
    mkdir -p "$ARTIFACT_ROOT/$avd/apk"
    cp -- "$ATTESTED_APK_PATH" "$ARTIFACT_ROOT/$avd/apk/app-debug.apk"
    local copied_sha
    copied_sha="$(shasum -a 256 "$ARTIFACT_ROOT/$avd/apk/app-debug.apk" | awk '{print $1}')"
    [[ "$copied_sha" == "$APK_SHA_EXPECTED" ]] || fail "$avd APK copy attestation mismatch"
    printf '%s\n' "$copied_sha" >"$ARTIFACT_ROOT/$avd/apk/apk_sha256.txt"
  done
}

sanitize_stream() {
  M5_SECRET_PHONE="$LIVE_PHONE" M5_SECRET_RECEIVER_PHONE="$RECEIVER_PHONE" M5_SECRET_CLIENT="$OAUTH_CLIENT_ID" \
    M5_SECRET_DB_TOKEN="$DB_TOKEN" M5_SECRET_RELAY_A="$RELAY_TOKEN_A" \
    M5_SECRET_RELAY_B="$RELAY_TOKEN_B" python3 -u -c '
import os
import re
import sys
values = [os.environ.get(name, "") for name in ("M5_SECRET_PHONE", "M5_SECRET_RECEIVER_PHONE", "M5_SECRET_CLIENT", "M5_SECRET_DB_TOKEN", "M5_SECRET_RELAY_A", "M5_SECRET_RELAY_B")]
for line in sys.stdin:
    for value in values:
        if value: line = line.replace(value, "[REDACTED]")
    line = re.sub(r"(?<!\d)1[3-9]\d{9}(?!\d)", "[REDACTED_PHONE]", line)
    line = re.sub(r"(?<!\d)\d{6}(?!\d)", "[REDACTED_OTP]", line)
    line = re.sub(r"(?i)(bearer\s+)[A-Za-z0-9._~+/=-]{12,}", r"\1[REDACTED_TOKEN]", line)
    line = re.sub(r"(?i)((?:access[_-]?token|refresh[_-]?token|client[_-]?secret|password|token)\s*[:=]\s*)[A-Za-z0-9._~+/=-]{8,}", r"\1[REDACTED_TOKEN]", line)
    sys.stdout.write(line)
    sys.stdout.flush()
'
}

secret_scan() {
  local target="$1"
  M5_SCAN_PHONE="$LIVE_PHONE" M5_SCAN_CLIENT="$OAUTH_CLIENT_ID" \
    M5_SCAN_RECEIVER_PHONE="$RECEIVER_PHONE" M5_SCAN_DB_TOKEN="$DB_TOKEN" \
    M5_SCAN_RELAY_A="$RELAY_TOKEN_A" \
    M5_SCAN_RELAY_B="$RELAY_TOKEN_B" python3 - "$target" <<'PY'
import os
import sys
from pathlib import Path
root = Path(sys.argv[1])
needles = [value.encode() for value in (
    os.environ.get("M5_SCAN_PHONE", ""),
    os.environ.get("M5_SCAN_RECEIVER_PHONE", ""),
    os.environ.get("M5_SCAN_CLIENT", ""),
    os.environ.get("M5_SCAN_DB_TOKEN", ""),
    os.environ.get("M5_SCAN_RELAY_A", ""),
    os.environ.get("M5_SCAN_RELAY_B", ""),
) if value]

def scan_stream(stream, values):
    values = list(dict.fromkeys(values))
    if not values:
        return True
    overlap_size = max(len(value) for value in values) - 1
    overlap = b""
    while True:
        chunk = stream.read(1024 * 1024)
        if not chunk:
            return True
        window = overlap + chunk
        if any(value in window for value in values):
            return False
        overlap = window[-overlap_size:] if overlap_size else b""

def iter_files(path):
    if not path.exists() or path.is_symlink():
        raise RuntimeError("invalid scan target")
    if path.is_file():
        yield path
        return
    if not path.is_dir():
        raise RuntimeError("invalid scan target")
    for directory, names, files in os.walk(path, followlinks=False):
        base = Path(directory)
        for name in names:
            if (base / name).is_symlink():
                raise RuntimeError("symlink in scan target")
        for name in files:
            candidate = base / name
            if candidate.is_symlink() or not candidate.is_file():
                raise RuntimeError("invalid file in scan target")
            yield candidate

for candidate in iter_files(root):
    with candidate.open("rb") as stream:
        if not scan_stream(stream, needles):
            raise SystemExit(1)
raise SystemExit(0)
PY
}

apk_secret_scan() {
  local target="$1"
  M5_SCAN_PHONE="$LIVE_PHONE" M5_SCAN_RECEIVER_PHONE="$RECEIVER_PHONE" \
    M5_SCAN_CLIENT="$OAUTH_CLIENT_ID" M5_SCAN_DB_TOKEN="$DB_TOKEN" \
    M5_SCAN_RELAY_A="$RELAY_TOKEN_A" M5_SCAN_RELAY_B="$RELAY_TOKEN_B" \
    python3 - "$target" <<'PY'
import os
import sys
import zipfile
from pathlib import Path

apk = Path(sys.argv[1])
secret_values = [value.encode() for value in (
    os.environ.get("M5_SCAN_PHONE", ""),
    os.environ.get("M5_SCAN_RECEIVER_PHONE", ""),
    os.environ.get("M5_SCAN_CLIENT", ""),
    os.environ.get("M5_SCAN_DB_TOKEN", ""),
    os.environ.get("M5_SCAN_RELAY_A", ""),
    os.environ.get("M5_SCAN_RELAY_B", ""),
) if value]
# These optional extension JNI libraries are forbidden in the M5 APK because
# this acceptance build does not use face capture or lip sync. The base Agora
# SDK libraries are allowed; PEM/private-key material is never allowed client
# side. Scan both ZIP entry names and streamed entry contents.
forbidden = [
    b"libagora_face_capture_extension.so",
    b"libagora_lip_sync_extension.so",
    b"-----begin private key-----",
    b"-----begin rsa private key-----",
    b"-----begin ec private key-----",
    b"-----begin openssh private key-----",
]
values = list(dict.fromkeys(secret_values + forbidden))

def scan_stream(stream):
    overlap_size = max(len(value) for value in values) - 1
    overlap = b""
    while True:
        chunk = stream.read(1024 * 1024)
        if not chunk:
            return True
        window = overlap + chunk
        lowered = window.lower()
        if any(value.lower() in lowered for value in values):
            return False
        overlap = window[-overlap_size:] if overlap_size else b""

if not apk.exists() or apk.is_symlink() or not apk.is_file():
    raise SystemExit(1)
try:
    with apk.open("rb") as stream:
        if not scan_stream(stream):
            raise SystemExit(1)
    with zipfile.ZipFile(apk) as archive:
        for info in archive.infolist():
            entry_name = info.filename.encode("utf-8", "surrogateescape").lower()
            if any(value.lower() in entry_name for value in forbidden):
                raise SystemExit(1)
            with archive.open(info, "r") as stream:
                if not scan_stream(stream):
                    raise SystemExit(1)
except (OSError, zipfile.BadZipFile, RuntimeError, ValueError):
    raise SystemExit(1)
raise SystemExit(0)
PY
}

start_relay() {
  mkdir -p "$ARTIFACT_ROOT/config-relay"
  RELAY_TOKEN_A="$(python3 -c 'import secrets; print(secrets.token_urlsafe(48))')"
  RELAY_TOKEN_B="$(python3 -c 'import secrets; print(secrets.token_urlsafe(48))')"
  [[ "${#RELAY_TOKEN_A}" -ge 64 && "${#RELAY_TOKEN_B}" -ge 64 ]] || fail 'runtime relay token generation failed'
  RELAY_PORT="$(python3 - <<'PY'
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)"
  QA_M5_RELAY_TOKEN_A="$RELAY_TOKEN_A" QA_M5_RELAY_TOKEN_B="$RELAY_TOKEN_B" \
    QA_M5_RECEIVER_PHONE="$RECEIVER_PHONE" \
    python3 -u - "$RELAY_PORT" >/dev/null 2>&1 <<'PY' &
import hmac
import http.server
import json
import os
import re
import sys
import threading
port = int(sys.argv[1])
phone = os.environ["QA_LIVE_PHONE"]
receiver_phone = os.environ.get("QA_M5_RECEIVER_PHONE") or phone
client_id = os.environ["QA_OAUTH_CLIENT_ID"]
tokens = {
    os.environ["QA_M5_RELAY_TOKEN_A"]: {"role": "sender", "phone": phone, "configConsumed": False},
    os.environ["QA_M5_RELAY_TOKEN_B"]: {"role": "receiver", "phone": receiver_phone, "configConsumed": False},
}
coordination = {
    "receiverReady": False,
    "senderSent": False,
    "receiverPass": False,
    "roomId": None,
    "roomMessageId": None,
    "roomPass": False,
}
opaque_id = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")
lock = threading.Lock()
class Handler(http.server.BaseHTTPRequestHandler):
    def _token(self):
        values = self.headers.get_all("Authorization") or []
        prefix = "Bearer "
        supplied = values[0][len(prefix):] if len(values) == 1 and values[0].startswith(prefix) else ""
        with lock:
            for expected, details in tokens.items():
                if hmac.compare_digest(supplied, expected):
                    return details
        return None
    def _json(self, status, payload):
        body = json.dumps(payload, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def _body_json(self):
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length < 0 or length > 4096:
                return {}
            raw = self.rfile.read(length)
            decoded = json.loads(raw.decode("utf-8")) if raw else {}
            return decoded if isinstance(decoded, dict) else {}
        except (ValueError, TypeError, UnicodeDecodeError, json.JSONDecodeError):
            return {}
    def do_GET(self):
        details = self._token()
        if details is None:
            self._json(401, {"error": "unauthorized"})
            return
        if self.path == "/m5/config":
            with lock:
                if details["configConsumed"]:
                    self._json(409, {"error": "config_already_consumed"})
                    return
                details["configConsumed"] = True
            self._json(200, {"phone": details["phone"], "oauthClientId": client_id, "role": details["role"]})
            return
        if self.path == "/m5/c2c/receiver-pass":
            with lock: ready = coordination["receiverPass"]
            self._json(200, {"ready": ready})
            return
        if self.path == "/m5/c2c/receiver-ready":
            with lock: ready = coordination["receiverReady"]
            self._json(200, {"ready": ready})
            return
        if self.path == "/m5/c2c/sender-sent":
            with lock: ready = coordination["senderSent"]
            self._json(200, {"ready": ready})
            return
        if self.path == "/m5/avchatroom/ready":
            with lock:
                room_id = coordination["roomId"]
            self._json(200, {"ready": isinstance(room_id, str), "roomId": room_id})
            return
        if self.path == "/m5/avchatroom/message-sent":
            with lock:
                message_id = coordination["roomMessageId"]
            self._json(200, {"ready": isinstance(message_id, str), "messageId": message_id})
            return
        if self.path == "/m5/avchatroom/pass":
            with lock: ready = coordination["roomPass"]
            self._json(200, {"ready": ready})
            return
        self._json(404, {"error": "not_found"})
    def do_POST(self):
        details = self._token()
        if details is None:
            self._json(401, {"error": "unauthorized"})
            return
        if self.path == "/m5/c2c/sender-sent" and details["role"] == "sender":
            with lock: coordination["senderSent"] = True
            self._json(200, {"accepted": True})
            return
        if self.path == "/m5/c2c/receiver-pass" and details["role"] == "receiver":
            with lock: coordination["receiverPass"] = True
            self._json(200, {"accepted": True})
            return
        if self.path == "/m5/c2c/receiver-ready" and details["role"] == "receiver":
            with lock: coordination["receiverReady"] = True
            self._json(200, {"accepted": True})
            return
        if self.path == "/m5/avchatroom/ready" and details["role"] == "sender":
            room_id = self._body_json().get("roomId")
            if not isinstance(room_id, str) or not opaque_id.fullmatch(room_id):
                self._json(400, {"error": "invalid_room_id"})
                return
            with lock:
                if coordination["roomId"] not in (None, room_id):
                    self._json(409, {"error": "room_id_conflict"})
                    return
                coordination["roomId"] = room_id
            self._json(200, {"accepted": True})
            return
        if self.path == "/m5/avchatroom/message-sent" and details["role"] == "sender":
            message_id = self._body_json().get("messageId")
            if not isinstance(message_id, str) or not opaque_id.fullmatch(message_id):
                self._json(400, {"error": "invalid_message_id"})
                return
            with lock:
                if coordination["roomMessageId"] not in (None, message_id):
                    self._json(409, {"error": "message_id_conflict"})
                    return
                coordination["roomMessageId"] = message_id
            self._json(200, {"accepted": True})
            return
        if self.path == "/m5/avchatroom/pass" and details["role"] == "receiver":
            with lock: coordination["roomPass"] = True
            self._json(200, {"accepted": True})
            return
        self._json(409, {"error": "role_or_state_mismatch"})
    def log_message(self, *_args): return
http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
PY
  RELAY_PID=$!
  for _ in {1..60}; do
    kill -0 "$RELAY_PID" 2>/dev/null || fail 'runtime relay exited'
    if python3 - "$RELAY_PORT" <<'PY'
import socket
import sys
try:
    with socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=1): pass
except OSError: raise SystemExit(1)
PY
    then return 0; fi
    sleep 0.1
  done
  fail 'runtime relay did not become ready'
}

feed_runtime_relay_token() {
  local serial="$1" token="$2"
  [[ "$serial" =~ ^[A-Za-z0-9_.:-]{1,80}$ ]] || fail 'invalid emulator serial'
  [[ "${#token}" -ge 64 ]] || fail 'invalid relay token'
  (
    for _ in {1..300}; do
      printf '%s' "$token" |
        adb -s "$serial" shell run-as "$APP_PACKAGE" tee "$RUNTIME_TOKEN_TMP_FILE" >/dev/null 2>&1 &&
        adb -s "$serial" shell run-as "$APP_PACKAGE" chmod 600 "$RUNTIME_TOKEN_TMP_FILE" >/dev/null 2>&1 &&
        adb -s "$serial" shell run-as "$APP_PACKAGE" mv "$RUNTIME_TOKEN_TMP_FILE" "$RUNTIME_TOKEN_FILE" >/dev/null 2>&1 || true
      sleep 0.2
    done
  ) &
  RUNTIME_TOKEN_FEEDER_PID=$!
}

stop_runtime_relay_token_feeder() {
  if [[ -n "$RUNTIME_TOKEN_FEEDER_PID" ]]; then
    kill "$RUNTIME_TOKEN_FEEDER_PID" 2>/dev/null || true
    wait "$RUNTIME_TOKEN_FEEDER_PID" 2>/dev/null || true
  fi
  RUNTIME_TOKEN_FEEDER_PID=''
}

clear_runtime_relay_token() {
  local serial="$1"
  adb -s "$serial" shell run-as "$APP_PACKAGE" rm -f \
    "$RUNTIME_TOKEN_FILE" "$RUNTIME_TOKEN_TMP_FILE" >/dev/null 2>&1 || true
}

device_for_api() {
  local serial sdk
  while IFS=$' \t' read -r serial _state; do
    [[ "$serial" == emulator-* ]] || continue
    sdk="$(adb -s "$serial" shell getprop ro.build.version.sdk </dev/null 2>/dev/null | tr -d '\r')"
    [[ "$sdk" == "$1" ]] && { printf '%s\n' "$serial"; return 0; }
  done < <(adb devices | awk 'NR > 1 && $2 == "device" {print $1, $2}')
  return 1
}

wait_boot() {
  local serial="$1"
  adb -s "$serial" wait-for-device >/dev/null
  for _ in {1..180}; do
    [[ "$(adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == '1' ]] && return 0
    sleep 2
  done
  return 1
}

start_emulator() {
  local api="$1" name="$2" dir="$3" emulator_bin
  emulator_bin="$(command -v emulator || true)"
  if [[ -z "$emulator_bin" ]]; then
    local sdk_root
    sdk_root="$(env_value ANDROID_SDK_ROOT)"
    [[ -n "$sdk_root" && -x "$sdk_root/emulator/emulator" ]] || fail 'emulator binary is unavailable'
    emulator_bin="$sdk_root/emulator/emulator"
  fi
  "$emulator_bin" -avd "$name" -no-snapshot -no-boot-anim -gpu swiftshader_indirect \
    -no-window >"$dir/emulator.log" 2>&1 &
  local pid=$!
  for _ in {1..180}; do
    local serial
    serial="$(device_for_api "$api" || true)"
    if [[ -n "$serial" ]] && wait_boot "$serial"; then
      printf '%s\n' "$serial" >>"$STARTED_SERIALS_FILE"
      printf '%s\n' "$serial"
      return 0
    fi
    kill -0 "$pid" 2>/dev/null || fail 'emulator exited before boot'
    sleep 2
  done
  fail 'timed out waiting for emulator'
}

select_device() {
  local avd="$1" api="$2" override="$3" name="$4" dir="$5" serial=''
  if [[ -n "$override" ]]; then
    serial="$override"
    [[ "$(adb -s "$serial" shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r')" == "$api" ]] || fail "$avd serial SDK mismatch"
    wait_boot "$serial" || fail "$avd failed to boot"
  else
    serial="$(device_for_api "$api" || true)"
    [[ -n "$serial" ]] || serial="$(start_emulator "$api" "$name" "$dir")"
  fi
  printf '%s\n' "$serial"
}

configure_viewport() {
  local serial="$1" physical="$2" density="$3"
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
  [[ "$size" == *"$physical"* && "$density_value" == *"$density"* && "$rotation" == '0' && "$font" == '1.0' ]] || return 1
  printf 'wm_size=%s\nwm_density=%s\nrotation=%s\nfont_scale=%s\n' "$size" "$density_value" "$rotation" "$font"
}

start_db_evidence_helper() {
  # An externally supplied endpoint is an explicit operator choice. Require
  # its bearer token as a pair; never mix one external half with the local
  # helper's endpoint or token.
  if [[ -n "$EXTERNAL_DB_URL" || -n "$EXTERNAL_DB_TOKEN" ]]; then
    [[ -n "$EXTERNAL_DB_URL" && -n "$EXTERNAL_DB_TOKEN" ]] ||
      fail 'QA_DB_EVIDENCE_URL and QA_DB_EVIDENCE_TOKEN must be supplied together'
    validate_external_db_url "$EXTERNAL_DB_URL" ||
      fail 'QA_DB_EVIDENCE_URL must be an HTTPS evidence endpoint without credentials or query data'
    DB_URL="$EXTERNAL_DB_URL"
    DB_TOKEN="$EXTERNAL_DB_TOKEN"
    return 0
  fi

  local mysql_container docker_socket helper_token listening_port
  mysql_container="$MYSQL_CONTAINER_CONFIG"
  [[ "$mysql_container" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$ ]] ||
    fail 'QA_M5_MYSQL_CONTAINER is required for the local evidence helper'
  DB_HELPER_STATE_DIR="$ARTIFACT_ROOT/.m5-db-evidence-state"
  mkdir -m 700 -- "$DB_HELPER_STATE_DIR" || fail 'local evidence state directory could not be created'
  helper_token="$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(48), end="")
PY
)"
  [[ "${#helper_token}" -eq 64 && "$helper_token" =~ ^[A-Za-z0-9_-]+$ ]] ||
    fail 'local evidence helper token generation failed'
  DB_TOKEN="$helper_token"
  DB_HELPER_LOG="$ARTIFACT_ROOT/.m5-db-evidence.log"
  docker_socket="${DOCKER_HOST:-}"
  if [[ "$docker_socket" != unix://* && "$docker_socket" != /* ]]; then
    docker_socket=''
  fi
  if [[ -n "$docker_socket" ]]; then
    M5_DOCKER_SOCKET="$docker_socket" \
      M5_RUN_ID="$RUN_ID" M5_BACKEND_REPO="$BACKEND_REPO" \
      M5_BACKEND_SHA="$BACKEND_SHA_ACTUAL" M5_FLUTTER_REPO="$PROJECT_ROOT" \
      M5_FLUTTER_SHA="$FLUTTER_SHA_ACTUAL" M5_APK_PATH="$ATTESTED_APK_PATH" \
      M5_APK_SHA="$APK_SHA_EXPECTED" M5_MYSQL_CONTAINER="$mysql_container" \
      M5_BACKEND_DIGEST="$BACKEND_SOURCE_DIGEST_ACTUAL" M5_ALIPAY_SCENARIO="${PAYMENT_SCENARIO:-none}" \
      M5_DB_EVIDENCE_TOKEN="$DB_TOKEN" M5_DB_EVIDENCE_STATE_DIR="$DB_HELPER_STATE_DIR" \
      python3 -u "$PROJECT_ROOT/tool/qa/m5_vendor_db_evidence.py" --serve \
      >"$DB_HELPER_LOG" 2>/dev/null &
  else
    env -u M5_DOCKER_SOCKET -u QA_DOCKER_SOCKET \
      M5_RUN_ID="$RUN_ID" M5_BACKEND_REPO="$BACKEND_REPO" \
      M5_BACKEND_SHA="$BACKEND_SHA_ACTUAL" M5_FLUTTER_REPO="$PROJECT_ROOT" \
      M5_FLUTTER_SHA="$FLUTTER_SHA_ACTUAL" M5_APK_PATH="$ATTESTED_APK_PATH" \
      M5_APK_SHA="$APK_SHA_EXPECTED" M5_MYSQL_CONTAINER="$mysql_container" \
      M5_BACKEND_DIGEST="$BACKEND_SOURCE_DIGEST_ACTUAL" M5_ALIPAY_SCENARIO="${PAYMENT_SCENARIO:-none}" \
      M5_DB_EVIDENCE_TOKEN="$DB_TOKEN" M5_DB_EVIDENCE_STATE_DIR="$DB_HELPER_STATE_DIR" \
      python3 -u "$PROJECT_ROOT/tool/qa/m5_vendor_db_evidence.py" --serve \
      >"$DB_HELPER_LOG" 2>/dev/null &
  fi
  DB_HELPER_PID=$!
  listening_port=''
  for _ in {1..100}; do
    listening_port="$(sed -n 's/^M5_DB_EVIDENCE_LISTENING=127\.0\.0\.1:\([0-9][0-9]*\)\/m5\/db-evidence$/\1/p' "$DB_HELPER_LOG" 2>/dev/null | head -n 1)"
    [[ -n "$listening_port" ]] && break
    kill -0 "$DB_HELPER_PID" 2>/dev/null || break
    sleep 0.1
  done
  [[ "$listening_port" =~ ^[1-9][0-9]*$ ]] || fail 'local evidence helper did not start'
  DB_URL="http://127.0.0.1:${listening_port}/m5/db-evidence"
  validate_local_db_url "$DB_URL" || fail 'local evidence helper URL is not a controlled loopback endpoint'
}

db_evidence_start() {
  local dir="$1" avd="$2" nonce=''
  set +e
  nonce="$(M5_DB_TOKEN="$DB_TOKEN" M5_DB_URL="$DB_URL" M5_RUN_ID="$RUN_ID" M5_AVD="$avd" M5_FIXTURE_ID="$FIXTURE_ID" \
    M5_BACKEND_SHA="$BACKEND_SHA_ACTUAL" M5_FLUTTER_SHA="$FLUTTER_SHA_ACTUAL" \
    M5_APK_SHA="$APK_SHA_EXPECTED" M5_BACKEND_DIGEST="$BACKEND_SOURCE_DIGEST_ACTUAL" \
    M5_PAYMENT_SCENARIO="${PAYMENT_SCENARIO:-none}" \
    python3 -u - <<'PY'
import json
import os
import urllib.request
request = urllib.request.Request(os.environ["M5_DB_URL"], headers={
    "Authorization": "Bearer " + os.environ["M5_DB_TOKEN"],
    "Accept": "application/json", "X-M5-Evidence-Phase": "start",
    "X-M5-Run-ID": os.environ["M5_RUN_ID"], "X-M5-AVD": os.environ["M5_AVD"],
    "X-M5-Fixture-ID": os.environ["M5_FIXTURE_ID"],
    "X-M5-Backend-SHA": os.environ["M5_BACKEND_SHA"],
    "X-M5-Flutter-SHA": os.environ["M5_FLUTTER_SHA"],
    "X-M5-APK-SHA": os.environ["M5_APK_SHA"],
    "X-M5-Backend-Digest": os.environ["M5_BACKEND_DIGEST"],
    "X-M5-Payment-Scenario": os.environ["M5_PAYMENT_SCENARIO"],
})
try:
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            raise RuntimeError("redirect")

    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    with opener.open(request, timeout=180) as response:
        if response.geturl() != os.environ["M5_DB_URL"]: raise RuntimeError("redirect")
        if response.status < 200 or response.status >= 300: raise RuntimeError("non_success")
        payload = json.loads(response.read())
    if (not isinstance(payload, dict) or payload.get("status") != "STARTED" or
        payload.get("runId") != os.environ["M5_RUN_ID"] or payload.get("avd") != os.environ["M5_AVD"] or
        payload.get("fixtureId") != os.environ["M5_FIXTURE_ID"] or
        payload.get("backendSha") != os.environ["M5_BACKEND_SHA"] or
        payload.get("flutterSha") != os.environ["M5_FLUTTER_SHA"] or
        payload.get("apkSha") != os.environ["M5_APK_SHA"] or
        payload.get("backendSourceDigest") != os.environ["M5_BACKEND_DIGEST"] or
        payload.get("paymentScenario") != os.environ["M5_PAYMENT_SCENARIO"] or
        payload.get("paymentSettlementPoll") != "internal-bounded-90s" or
        not isinstance(payload.get("startNonce"), str)):
        raise RuntimeError("invalid_binding")
    print(payload["startNonce"])
except Exception:
    raise SystemExit(1)
PY
  )"
  local status=$?
  set -e
  if [[ "$status" -ne 0 || ! "$nonce" =~ ^[A-Za-z0-9_.~=-]{16,255}$ ]]; then
    printf 'status=UNAVAILABLE\nphase=start\n' >"$dir/db-evidence-error.txt"
    return 1
  fi
  if [[ "$avd" == 'AVD-A' ]]; then DB_START_NONCE_A="$nonce"; else DB_START_NONCE_B="$nonce"; fi
  printf '%s\n' "$nonce"
}

db_evidence_collect() {
  local dir="$1" avd="$2" nonce="$3" apk_sha="$4"
  [[ -n "$nonce" ]] || { printf 'status=UNAVAILABLE\nphase=collect\n' >"$dir/db-evidence-error.txt"; return 1; }
  [[ "$apk_sha" =~ ^[0-9a-f]{64}$ ]] || { printf 'status=UNAVAILABLE\nphase=collect\n' >"$dir/db-evidence-error.txt"; return 1; }
  local raw
  raw="$(mktemp "$dir/.m5-db-evidence.XXXXXX")"
  DB_EVIDENCE_RAW_FILES+=("$raw")
  if ! M5_DB_TOKEN="$DB_TOKEN" M5_DB_URL="$DB_URL" M5_RUN_ID="$RUN_ID" M5_AVD="$avd" \
    M5_FIXTURE_ID="$FIXTURE_ID" M5_START_NONCE="$nonce" M5_BACKEND_SHA="$BACKEND_SHA_ACTUAL" \
    M5_FLUTTER_SHA="$FLUTTER_SHA_ACTUAL" M5_APK_SHA="$apk_sha" \
    M5_BACKEND_DIGEST="$BACKEND_SOURCE_DIGEST_ACTUAL" \
    M5_PAYMENT_SCENARIO="${PAYMENT_SCENARIO:-none}" \
    python3 -u - "$raw" <<'PY'
import json
import os
import sys
import urllib.request
out = sys.argv[1]
request = urllib.request.Request(os.environ["M5_DB_URL"], headers={
    "Authorization": "Bearer " + os.environ["M5_DB_TOKEN"], "Accept": "application/json",
    "X-M5-Evidence-Phase": "collect", "X-M5-Run-ID": os.environ["M5_RUN_ID"],
    "X-M5-AVD": os.environ["M5_AVD"], "X-M5-Fixture-ID": os.environ["M5_FIXTURE_ID"],
    "X-M5-Start-Nonce": os.environ["M5_START_NONCE"],
    "X-M5-Backend-SHA": os.environ["M5_BACKEND_SHA"],
    "X-M5-Flutter-SHA": os.environ["M5_FLUTTER_SHA"],
    "X-M5-APK-SHA": os.environ["M5_APK_SHA"],
    "X-M5-Backend-Digest": os.environ["M5_BACKEND_DIGEST"],
    "X-M5-Payment-Scenario": os.environ["M5_PAYMENT_SCENARIO"],
})
try:
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            raise RuntimeError("redirect")

    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    # The helper polls settlement internally for up to 90 seconds, may spend
    # up to 300 seconds in one bounded Docker scan, and serializes A/B state
    # transitions.  Keep a 15-minute client budget so a slow scan cannot
    # orphan a valid one-shot nonce.
    with opener.open(request, timeout=900) as response:
        if response.geturl() != os.environ["M5_DB_URL"]: raise RuntimeError("redirect")
        if response.status < 200 or response.status >= 300: raise RuntimeError("non_success")
        payload = json.loads(response.read())
    required = {"status", "evidenceBinding", "writeCounters", "vendorOutbox", "callbackEvents", "outboxAttempts", "paymentSettlement", "secrets", "backendSourceDigest"}
    if not isinstance(payload, dict) or set(payload) != required or payload.get("status") != "OK" or payload.get("secrets") is not False:
        raise RuntimeError("schema_or_status")
    binding = payload.get("evidenceBinding")
    if (not isinstance(binding, dict) or set(binding) != {"runId", "avd", "fixtureId", "startNonce", "backendSha", "flutterSha", "apkSha", "backendSourceDigest"} or
        binding.get("runId") != os.environ["M5_RUN_ID"] or binding.get("avd") != os.environ["M5_AVD"] or
        binding.get("fixtureId") != os.environ["M5_FIXTURE_ID"] or binding.get("startNonce") != os.environ["M5_START_NONCE"] or
        binding.get("backendSha") != os.environ["M5_BACKEND_SHA"] or binding.get("flutterSha") != os.environ["M5_FLUTTER_SHA"] or
        binding.get("apkSha") != os.environ["M5_APK_SHA"] or binding.get("backendSourceDigest") != os.environ["M5_BACKEND_DIGEST"]):
        raise RuntimeError("binding")
    counters = payload.get("writeCounters")
    if (not isinstance(counters, dict) or set(counters) != {"auth_sessions", "im_credentials", "c2c_messages", "avchatroom_sessions", "alipay_orders", "payment_provider_events", "wallet_transactions", "ledger_journals", "ledger_entries"} or
        any(type(value) is not int or value < 0 for value in counters.values())):
        raise RuntimeError("counters")
    for key in ("tencentIm", "alipay"):
        outbox = payload.get("vendorOutbox", {}).get(key)
        callback = payload.get("callbackEvents", {}).get(key)
        if (not isinstance(outbox, dict) or set(outbox) != {"state", "attempts"} or type(outbox["attempts"]) is not int or outbox["attempts"] < 0 or
        outbox["state"] not in {"MISSING", "SENT", "VENDOR_BLOCKED", "PENDING", "PROCESSING", "RETRY", "UNKNOWN", "FAILED"} or
        not isinstance(callback, dict) or set(callback) != {"verified", "eventCount"} or
            type(callback["verified"]) is not bool or type(callback["eventCount"]) is not int or callback["eventCount"] < 0):
            raise RuntimeError("vendor_evidence")
    attempts = payload.get("outboxAttempts")
    if (not isinstance(attempts, dict) or set(attempts) != {"tencentIm", "alipay"} or any(type(value) is not int or value < 0 for value in attempts.values())):
        raise RuntimeError("outbox_attempts")
    if payload.get("backendSourceDigest") != os.environ["M5_BACKEND_DIGEST"]: raise RuntimeError("backend_digest")
    settlement = payload.get("paymentSettlement")
    settlement_keys = {"providerEventVerified", "providerEventProcessedCount", "succeededOrderCount", "walletTransactionCount", "walletCreditCount", "ledgerJournalCount", "ledgerEntryCount", "balancedJournalCount", "ledgerImbalanceCount"}
    if (not isinstance(settlement, dict) or set(settlement) != settlement_keys or
        type(settlement["providerEventVerified"]) is not bool or
        any(type(settlement[key]) is not int or settlement[key] < 0 for key in settlement_keys - {"providerEventVerified"})):
        raise RuntimeError("payment_settlement")
    with open(out, "w", encoding="utf-8") as stream: json.dump(payload, stream, sort_keys=True, separators=(",", ":"))
except Exception:
    raise SystemExit(1)
PY
  then
    printf 'status=UNAVAILABLE\nphase=collect\n' >"$dir/db-evidence-error.txt"
    rm -f -- "$raw"
    return 1
  fi
  mv -- "$raw" "$dir/db-evidence.json"
  printf 'status=COLLECTED\nphase=collect\n' >"$dir/db-evidence-status.txt"
}

write_db_fallback() {
  local dir="$1"
  printf 'schema=m5-vendor-live-evidence-v1\nstatus=UNAVAILABLE\nsdk_callbacks_observed=unknown\nsecrets=false\n' >"$dir/db-write-counters.txt"
}

write_db_projections() {
  local dir="$1"
  python3 - "$dir/db-evidence.json" "$dir/db-write-counters.txt" "$dir/outbox-evidence.txt" "$dir/callback-evidence.txt" "$dir/payment-settlement.txt" <<'PY'
import json
import sys

source, counters_path, outbox_path, callback_path, settlement_path = sys.argv[1:]
with open(source, encoding="utf-8") as stream:
    payload = json.load(stream)
binding = payload["evidenceBinding"]
counter_lines = [
    "schema=m5-vendor-live-evidence-v1",
    "status=" + payload["status"],
    "run_id=" + binding["runId"],
    "fixture_id=" + binding["fixtureId"],
    "avd=" + binding["avd"],
    "start_nonce=" + binding["startNonce"],
    "backend_sha=" + binding["backendSha"],
    "flutter_sha=" + binding["flutterSha"],
    "apk_sha=" + binding["apkSha"],
    "backend_source_digest=" + binding["backendSourceDigest"],
    "secrets=false",
]
counter_lines.extend(
    f"{key}={value}" for key, value in sorted(payload["writeCounters"].items())
)
with open(counters_path, "w", encoding="utf-8") as stream:
    stream.write("\n".join(counter_lines) + "\n")
with open(outbox_path, "w", encoding="utf-8") as stream:
    for key in ("tencentIm", "alipay"):
        item = payload["vendorOutbox"][key]
        stream.write(f"{key}.state={item['state']}\n{key}.attempts={item['attempts']}\n")
with open(callback_path, "w", encoding="utf-8") as stream:
    for key in ("tencentIm", "alipay"):
        item = payload["callbackEvents"][key]
        stream.write(f"{key}.verified={str(item['verified']).lower()}\n{key}.eventCount={item['eventCount']}\n")
settlement = payload["paymentSettlement"]
with open(settlement_path, "w", encoding="utf-8") as stream:
    for key in sorted(settlement):
        value = settlement[key]
        stream.write(f"{key}={str(value).lower() if isinstance(value, bool) else value}\n")
PY
}

run_flutter_test() {
  local serial="$1" avd="$2" width="$3" height="$4" dpr="$5" dir="$6"
  local raw="$dir/logs/flutter-drive.raw.log" safe="$dir/logs/flutter-drive.log"
  local alipay_define='false' payment_define='false' confirmation_define='' success_confirmation_define=''
  is_true "$ENABLE_ALIPAY" && alipay_define='true'
  [[ "$PAYMENT_OPT_IN" == 'true' ]] && payment_define='true'
  [[ "$PAYMENT_OPT_IN" == 'true' ]] && confirmation_define='--dart-define=M5_PAYMENT_CONFIRMATION=I_UNDERSTAND_SANDBOX_PAYMENT'
  if [[ "$PAYMENT_OPT_IN" == 'true' && "${PAYMENT_SCENARIO:-none}" == 'success' ]]; then
    success_confirmation_define='--dart-define=M5_SUCCESS_CONFIRMATION=I_UNDERSTAND_SANDBOX_SUCCESS_PAYMENT'
  fi
  set +e
  env -u QA_LIVE_PHONE -u QA_M5_RECEIVER_PHONE -u QA_OAUTH_CLIENT_ID -u QA_DB_EVIDENCE_TOKEN \
    -u DEVELOPMENT_OUTBOX_KEY -u QA_DEVELOPMENT_OUTBOX_KEY "$FLUTTER_BIN" drive \
    --use-application-binary="$dir/apk/app-debug.apk" \
    --driver=test_driver/integration_test.dart --target=integration_test/m5_vendor_live_integration_test.dart \
    --device-id="$serial" --dart-define=BACKEND_MODE=live --dart-define=APP_ENV=development \
    --dart-define=ALLOW_INSECURE_HTTP=true --dart-define=API_BASE_URL="$BACKEND_BASE_URL" \
    --dart-define=API_TIMEOUT_SECONDS=15 --dart-define=ENABLE_TENCENT_IM=true \
    --dart-define=ENABLE_ALIPAY_APP_PAY="$alipay_define" --dart-define=M5_RUNTIME_CONFIG_PORT="$RELAY_PORT" \
    --dart-define=QA_M5_FIXTURE_ID="$FIXTURE_ID" --dart-define=M5_EXPECTED_FLUTTER_SHA="$FLUTTER_SHA_ACTUAL" \
    --dart-define=M5_EXPECTED_BACKEND_SHA="$BACKEND_SHA_ACTUAL" --dart-define=M5_EXPECTED_BACKEND_DIGEST="$BACKEND_SOURCE_DIGEST_ACTUAL" \
    --dart-define=QA_M5_RUN_ID="$RUN_ID" \
    --dart-define=M5_ALLOW_EXTERNAL_PAYMENT="$payment_define" \
    --dart-define=M5_ALIPAY_SCENARIO="${PAYMENT_SCENARIO:-none}" \
    $confirmation_define $success_confirmation_define >"$raw" 2>&1
  local status=$?
  set -e
  sanitize_stream <"$raw" >"$safe" || true
  rm -f -- "$raw"
  return "$status"
}

capture_screenshot() {
  local serial="$1" dir="$2"
  adb -s "$serial" exec-out screencap -p >"$dir/screenshots/m5-${dir##*/}.png" 2>/dev/null || true
}

write_route_evidence() {
  local dir="$1" log="$dir/logs/flutter-drive.log"
  {
    printf 'marker,capability,method,route,status,state\n'
    awk -F '::' '/M5_ROUTE_STATUS::/ && NF >= 7 {printf "%s,%s,%s,%s,%s,%s\n", $0, $2, $3, $4, $5, $6}' "$log" 2>/dev/null || true
  } >"$dir/http-route-coverage.csv"
  awk '/M5_AUTHORITY_INVARIANT::/ {print}' "$log" 2>/dev/null >"$dir/authority-invariants.txt" || true
  awk '/M5_VENDOR_EVENT::/ {print}' "$log" 2>/dev/null >"$dir/vendor-events.txt" || true
  awk '/M5_LANE::/ {print}' "$log" 2>/dev/null >"$dir/lane-verdicts.txt" || true
  awk '/M5_ACCEPTANCE::/ {print}' "$log" 2>/dev/null >"$dir/evidence-verdict.txt" || true
  awk '/M5_PROVIDER_CALLS::/ {print}' "$log" 2>/dev/null >"$dir/provider-calls.txt" || true
}

write_result() {
  local dir="$1" avd="$2" result="$3" reason="$4" db_status="$5" apk_sha="$6"
  local screenshot_count="$7" route_count="$8" event_count="$9" tencent_calls="${10}" alipay_calls="${11}" nonce="${12:-}" resilience="${13:-NOT_RUN}"
  local payment_success_proven='false' reconcile_repeat='NOT_RUN'
  if grep -Eq '^M5_PAYMENT_SUCCESS_FLOW_VERIFIED::1$' "$dir/logs/flutter-drive.log" 2>/dev/null; then
    payment_success_proven='true'
    reconcile_repeat='PASS'
  fi
  {
    printf 'result=%s\nacceptance_status=%s\nreason=%s\n' "$result" "$result" "$reason"
    printf 'run_id=%s\nfixture_id=%s\navd=%s\n' "$RUN_ID" "$FIXTURE_ID" "$avd"
    printf 'db_start_nonce=%s\n' "$nonce"
    printf 'tested_git_sha=%s\nflutter_sha=%s\nbackend_sha=%s\nbackend_source_digest=%s\n' \
      "$FLUTTER_SHA_ACTUAL" "$FLUTTER_SHA_ACTUAL" "$BACKEND_SHA_ACTUAL" "$BACKEND_SOURCE_DIGEST_ACTUAL"
    printf 'android_host_source_sha256=%s\napk_sha256=%s\napk_attestation_sha256=%s\n' "$ANDROID_HOST_SOURCE_SHA256" "$apk_sha" "$APK_SHA_EXPECTED"
    printf 'flutter_version=%s\ndart_version=%s\nflutter_revision=%s\n' \
      "$FLUTTER_FRAMEWORK_VERSION" "$FLUTTER_DART_VERSION" "$FLUTTER_FRAMEWORK_REVISION"
    printf 'tencent_provider_calls=%s\nalipay_provider_calls=%s\n' "$tencent_calls" "$alipay_calls"
    if [[ "$tencent_calls" -gt 0 || "$alipay_calls" -gt 0 ]]; then
      printf 'provider_call_evidence=real_sdk_callbacks\n'
    else
      printf 'provider_call_evidence=none\n'
    fi
    printf 'db_evidence=%s\noutbox_evidence=%s\ncallback_evidence=%s\n' "$db_status" \
      "$( [[ -s "$dir/outbox-evidence.txt" ]] && printf COLLECTED || printf UNAVAILABLE )" \
      "$( [[ -s "$dir/callback-evidence.txt" ]] && printf COLLECTED || printf UNAVAILABLE )"
    printf 'screenshot_count=%s\nhttp_route_marker_count=%s\nvendor_event_count=%s\n' \
      "$screenshot_count" "$route_count" "$event_count"
    printf 'resilience_verdict=%s\npayment_scenario=%s\npayment_success_proven=%s\nreconcile_repeat=%s\n' \
      "$resilience" "${PAYMENT_SCENARIO:-none}" "$payment_success_proven" "$reconcile_repeat"
    printf 'hard_finding_count=0\ncrash_anr_count=%s\n' \
      "$( [[ -s "$dir/logs/crash-anr.txt" ]] && printf 1 || printf 0 )"
    printf 'secret_scan=%s\napk_secret_scan=%s\npayment_opt_in=%s\npayment_invoked=%s\n' \
      "$(sed -n 's/^status=//p' "$dir/secret-scan.txt" 2>/dev/null | head -n 1 || printf FAIL)" \
      "$(sed -n 's/^status=//p' "$dir/apk-secret-scan.txt" 2>/dev/null | head -n 1 || printf FAIL)" \
      "$PAYMENT_OPT_IN" "$PAYMENT_INVOKED"
  } >"$dir/result.txt"
}

run_one() {
  local avd="$1" api="$2" profile="$3" physical="$4" density="$5" width="$6" height="$7" dpr="$8" override="$9"
  local dir="$ARTIFACT_ROOT/$avd"
  mkdir -p "$dir/logs" "$dir/screenshots" "$dir/apk"
  local serial='' result='FAIL' reason='not_started' db_status='UNAVAILABLE' apk_sha=''
  local tencent_calls=0 alipay_calls=0
  serial="$(select_device "$avd" "$api" "$override" "$profile" "$dir")" || {
    write_db_fallback "$dir"
    write_result "$dir" "$avd" FAIL device_unavailable UNAVAILABLE unknown 0 0 0 0 0 ''
    return 1
  }
  {
    printf 'avd=%s\napi_level=%s\nprofile=%s\nserial=%s\n' "$avd" "$api" "$profile" "$serial"
    printf 'run_id=%s\nfixture_id=%s\nbackend_mode=live\nbackend_base_url=%s\n' "$RUN_ID" "$FIXTURE_ID" "$BACKEND_BASE_URL"
    printf 'flutter_sha=%s\nbackend_sha=%s\nbackend_source_digest=%s\nandroid_host_source_sha256=%s\n' \
      "$FLUTTER_SHA_ACTUAL" "$BACKEND_SHA_ACTUAL" "$BACKEND_SOURCE_DIGEST_ACTUAL" "$ANDROID_HOST_SOURCE_SHA256"
    printf 'expected_viewport=%sx%s\nexpected_dpr=%s\npayment_opt_in=%s\npayment_scenario=%s\n' \
      "$width" "$height" "$dpr" "$PAYMENT_OPT_IN" "${PAYMENT_SCENARIO:-none}"
  } >"$dir/environment.txt"
  [[ -f "$dir/apk/app-debug.apk" ]] || {
    write_db_fallback "$dir"
    write_result "$dir" "$avd" FAIL apk_missing UNAVAILABLE unknown 0 0 0 0 0 ''
    return 1
  }
  apk_sha="$(shasum -a 256 "$dir/apk/app-debug.apk" | awk '{print $1}')"
  [[ "$apk_sha" == "$APK_SHA_EXPECTED" ]] || {
    write_db_fallback "$dir"
    write_result "$dir" "$avd" FAIL apk_attestation_mismatch UNAVAILABLE "$apk_sha" 0 0 0 0 0 ''
    return 1
  }
  configure_viewport "$serial" "$physical" "$density" >"$dir/viewport.txt" || {
    write_db_fallback "$dir"
    write_result "$dir" "$avd" FAIL viewport_mismatch UNAVAILABLE unknown 0 0 0 0 0 ''
    return 1
  }
  db_evidence_start "$dir" "$avd" >/dev/null || true
  local nonce="$DB_START_NONCE_A"
  [[ "$avd" == 'AVD-B' ]] && nonce="$DB_START_NONCE_B"
  local relay_token="$RELAY_TOKEN_A"
  [[ "$avd" == 'AVD-B' ]] && relay_token="$RELAY_TOKEN_B"
  adb -s "$serial" logcat -c >/dev/null 2>&1 || true
  feed_runtime_relay_token "$serial" "$relay_token"
  if run_flutter_test "$serial" "$avd" "$width" "$height" "$dpr" "$dir"; then
    result='PASS'
    reason='integration_completed'
  else
    reason='integration_failed'
  fi
  stop_runtime_relay_token_feeder
  clear_runtime_relay_token "$serial"
  adb -s "$serial" logcat -d -v threadtime 2>"$dir/logs/logcat.stderr" | sanitize_stream >"$dir/logs/logcat.log" || true
  adb -s "$serial" shell dumpsys activity processes 2>/dev/null | sanitize_stream >"$dir/logs/activity-processes.log" || true
  capture_screenshot "$serial" "$dir"
  grep -E '(^|[[:space:]])(FATAL EXCEPTION|ANR in|E/flutter|Unhandled Exception)' "$dir/logs/logcat.log" >"$dir/logs/crash-anr.txt" 2>/dev/null || true
  : >"$dir/logs/flutter-errors.txt"
  write_route_evidence "$dir"
  local marker resilience
  marker="$(grep -E 'M5_PROVIDER_CALLS::[0-9]+::[0-9]+$' "$dir/logs/flutter-drive.log" | tail -n 1 || true)"
  if [[ "$marker" =~ M5_PROVIDER_CALLS::([0-9]+)::([0-9]+)$ ]]; then
    tencent_calls="${BASH_REMATCH[1]}"
    alipay_calls="${BASH_REMATCH[2]}"
  fi
  resilience="$(grep -E '^M5_RESILIENCE::(PASS|NOT_RUN|BLOCKED)$' "$dir/logs/flutter-drive.log" | tail -n 1 | sed 's/^M5_RESILIENCE:://' || printf 'NOT_RUN')"
  if [[ "$alipay_calls" -gt 0 ]]; then PAYMENT_INVOKED='true'; fi
  printf '%s\n' "$apk_sha" >"$dir/apk/apk_sha256.txt"
  if secret_scan "$dir"; then printf 'status=PASS\n' >"$dir/secret-scan.txt"; else printf 'status=FAIL\n' >"$dir/secret-scan.txt"; result='FAIL'; reason='secret_scan_failed'; fi
  if [[ -f "$dir/apk/app-debug.apk" ]] && apk_secret_scan "$dir/apk/app-debug.apk"; then printf 'status=PASS\n' >"$dir/apk-secret-scan.txt"; else printf 'status=FAIL\n' >"$dir/apk-secret-scan.txt"; result='FAIL'; reason='apk_missing_or_secret_scan_failed'; fi
  if db_evidence_collect "$dir" "$avd" "$nonce" "$apk_sha"; then
    db_status='COLLECTED'
    if ! write_db_projections "$dir"; then
      db_status='UNAVAILABLE'
      if [[ "$result" != 'FAIL' ]]; then
        [[ "$PAYMENT_OPT_IN" == 'true' ]] && result='FAIL' || result='PARTIAL'
        reason='db_projection_write_failed'
      fi
      write_db_fallback "$dir"
    fi
  else
    if [[ "$result" != 'FAIL' ]]; then
      [[ "$PAYMENT_OPT_IN" == 'true' ]] && result='FAIL' || result='PARTIAL'
      reason='db_evidence_unavailable_or_invalid'
    fi
    write_db_fallback "$dir"
  fi
  local screenshot_count route_count event_count
  screenshot_count="$(find "$dir/screenshots" -type f -name '*.png' | wc -l | tr -d '[:space:]')"
  route_count="$(grep -Ec '^M5_ROUTE_STATUS::' "$dir/http-route-coverage.csv" 2>/dev/null || printf 0)"
  event_count="$(grep -Ec '^M5_VENDOR_EVENT::' "$dir/vendor-events.txt" 2>/dev/null || printf 0)"
  local acceptance_marker
  acceptance_marker="$(grep -E '^M5_ACCEPTANCE::(PASS|NO_PAY|PARTIAL|FAIL)$' "$dir/evidence-verdict.txt" 2>/dev/null | tail -n 1 | sed 's/^M5_ACCEPTANCE:://' || true)"
  local result_before_acceptance="$result"
  local reason_before_acceptance="$reason"
  case "$acceptance_marker" in
    PASS)
      [[ "$result" == 'FAIL' || "$result" == 'PARTIAL' ]] || result='PASS'
      ;;
    NO_PAY|PARTIAL)
      if [[ "$result_before_acceptance" == 'FAIL' ]]; then
        result='FAIL'
      elif [[ "$result_before_acceptance" == 'PARTIAL' ]]; then
        result='PARTIAL'
      elif [[ "$PAYMENT_OPT_IN" == 'true' ]]; then
        result='FAIL'
      else
        result="$acceptance_marker"
      fi
      if [[ "$result_before_acceptance" != 'FAIL' &&
        "$result_before_acceptance" != 'PARTIAL' ]]; then
        reason="acceptance_$(printf '%s' "$acceptance_marker" | tr '[:upper:]' '[:lower:]')"
      else
        reason="$reason_before_acceptance"
      fi
      ;;
    *)
      [[ "$PAYMENT_OPT_IN" == 'true' ]] && result='FAIL' || result='PARTIAL'
      reason='acceptance_marker_missing'
      ;;
  esac
  if [[ "$acceptance_marker" == 'FAIL' ]]; then
    result='FAIL'
    reason='acceptance_failed'
  fi
  write_result "$dir" "$avd" "$result" "$reason" "$db_status" "${apk_sha:-unknown}" "$screenshot_count" "$route_count" "$event_count" "$tencent_calls" "$alipay_calls" "$nonce" "$resilience"
  [[ "$result" == PASS || "$result" == NO_PAY ]]
}

write_summary() {
  local payment_invoked_summary="$PAYMENT_INVOKED"
  if grep -Eq '^AVD-[AB]\.payment_invoked=true$' <(for avd in AVD-A AVD-B; do [[ -f "$ARTIFACT_ROOT/$avd/result.txt" ]] && sed "s/^/$avd./" "$ARTIFACT_ROOT/$avd/result.txt"; done) 2>/dev/null; then
    payment_invoked_summary='true'
  fi
  {
    printf 'M5 Tencent IM + Alipay vendor-live AVD acceptance\n'
    printf 'conclusion=%s\nrun_id=%s\nfixture_id=%s\n' "$OVERALL_RESULT" "$RUN_ID" "$FIXTURE_ID"
    printf 'tested_git_sha=%s\nbackend_sha=%s\nbackend_source_digest=%s\napk_attestation_sha256=%s\n' \
      "${FLUTTER_SHA_ACTUAL:-unknown}" "${BACKEND_SHA_ACTUAL:-unknown}" "${BACKEND_SOURCE_DIGEST_ACTUAL:-unknown}" "${APK_SHA_EXPECTED:-unknown}"
    printf 'android_host_source_sha256=%s\nflutter_version=%s\ndart_version=%s\nflutter_revision=%s\n' \
      "${ANDROID_HOST_SOURCE_SHA256:-unknown}" "${FLUTTER_FRAMEWORK_VERSION:-unknown}" "${FLUTTER_DART_VERSION:-unknown}" "${FLUTTER_FRAMEWORK_REVISION:-unknown}"
    printf 'backend_mode=live\nbackend_base_url=%s\npayment_opt_in=%s\npayment_invoked=%s\nlast_result_reason=%s\n' \
      "$BACKEND_BASE_URL" "$PAYMENT_OPT_IN" "$payment_invoked_summary" "$LAST_RESULT_REASON"
    for avd in AVD-A AVD-B; do
      if [[ -f "$ARTIFACT_ROOT/$avd/result.txt" ]]; then sed "s/^/$avd./" "$ARTIFACT_ROOT/$avd/result.txt"; else printf '%s.result=NOT_RUN\n' "$avd"; fi
    done
  } >"$SUMMARY_FILE"
}

write_manifest() {
  python3 - "$ARTIFACT_ROOT" "$MANIFEST_FILE" <<'PY'
import hashlib
import os
import sys
from pathlib import Path
root = Path(sys.argv[1]).resolve()
final = Path(sys.argv[2]).resolve()
rows = []
def digest_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while True:
            chunk = stream.read(1024 * 1024)
            if not chunk: return digest.hexdigest()
            digest.update(chunk)
for directory, names, files in os.walk(root, followlinks=False):
    base = Path(directory)
    if any((base / name).is_symlink() for name in names): raise SystemExit(1)
    for name in files:
        path = base / name
        if path.resolve() == final or path.is_symlink() or not path.is_file(): continue
        rows.append((path.relative_to(root).as_posix(), digest_file(path)))
temporary = root / '.m5-manifest.tmp'
with temporary.open('w', encoding='utf-8') as stream:
    for relative, digest in sorted(rows): stream.write(f'{digest}  {relative}\n')
os.replace(temporary, final)
PY
}

cleanup() {
  local incoming_status=$?
  set +e
  [[ "$incoming_status" -eq 0 ]] || OVERALL_RESULT='FAIL'
  stop_runtime_relay_token_feeder
  if [[ -n "$RELAY_PID" ]]; then kill "$RELAY_PID" 2>/dev/null || true; wait "$RELAY_PID" 2>/dev/null || true; fi
  local started_serial
  if [[ -f "$STARTED_SERIALS_FILE" ]]; then
    while IFS= read -r started_serial; do
      [[ "$started_serial" =~ ^emulator-[0-9]+$ ]] || continue
      adb -s "$started_serial" shell run-as "$APP_PACKAGE" rm -f "$RUNTIME_TOKEN_FILE" "$RUNTIME_TOKEN_TMP_FILE" >/dev/null 2>&1 || true
      adb -s "$started_serial" emu kill >/dev/null 2>&1 || true
    done <"$STARTED_SERIALS_FILE"
    rm -f -- "$STARTED_SERIALS_FILE"
  fi
  if [[ -n "$DB_HELPER_PID" ]]; then
    kill "$DB_HELPER_PID" 2>/dev/null || true
    wait "$DB_HELPER_PID" 2>/dev/null || true
  fi
  if [[ -n "$DB_HELPER_STATE_DIR" &&
    "$DB_HELPER_STATE_DIR" == "$ARTIFACT_ROOT/.m5-db-evidence-state" &&
    ! -L "$DB_HELPER_STATE_DIR" ]]; then
    rm -rf -- "$DB_HELPER_STATE_DIR"
    DB_HELPER_STATE_DIR=''
  fi
  if [[ -n "$DB_HELPER_LOG" &&
    "$DB_HELPER_LOG" == "$ARTIFACT_ROOT/.m5-db-evidence.log" &&
    ! -L "$DB_HELPER_LOG" ]]; then
    rm -f -- "$DB_HELPER_LOG"
    DB_HELPER_LOG=''
  fi
  if [[ ${DB_EVIDENCE_RAW_FILES[@]+_} ]]; then
    for raw in "${DB_EVIDENCE_RAW_FILES[@]}"; do
      [[ "$raw" == "$ARTIFACT_ROOT"/AVD-[AB]/.m5-db-evidence.* ]] && rm -f -- "$raw"
    done
  fi
  if [[ -d "$ARTIFACT_ROOT" ]]; then
    write_summary || true
    if secret_scan "$ARTIFACT_ROOT"; then printf 'status=PASS\n' >"$ARTIFACT_ROOT/aggregate-secret-scan.txt"; else OVERALL_RESULT='FAIL'; printf 'status=FAIL\n' >"$ARTIFACT_ROOT/aggregate-secret-scan.txt"; write_summary || true; fi
    write_manifest || true
  fi
  trap - EXIT
  exit "$incoming_status"
}

if is_true "$DRY_RUN"; then
  create_safe_artifact_root || fail 'dry-run artifact root must be a new absolute directory'
  printf 'M5 vendor-live acceptance dry run\nconclusion=DRY_RUN\nprovider_calls_observed=0\npayment_invoked=false\n' >"$SUMMARY_FILE"
  printf 'status=DRY_RUN\n' >"$ARTIFACT_ROOT/evidence-verdict.txt"
  write_manifest || true
  exit 0
fi

for required_value in FLUTTER_SHA_EXPECTED BACKEND_SHA_EXPECTED BACKEND_REPO BACKEND_CONTAINER RUN_ID FIXTURE_ID LIVE_PHONE RECEIVER_PHONE OAUTH_CLIENT_ID; do
  [[ -n "${!required_value}" ]] || fail "required M5 input is missing: $required_value"
done
[[ "$FLUTTER_SHA_EXPECTED" =~ ^[0-9a-f]{40}$ ]] || fail 'QA_FLUTTER_SHA must be a lowercase 40-character SHA'
[[ "$BACKEND_SHA_EXPECTED" =~ ^[0-9a-f]{40}$ ]] || fail 'QA_BACKEND_SHA must be a lowercase 40-character SHA'
[[ "$RUN_ID" =~ ^[A-Za-z0-9_.:-]{1,80}$ ]] || fail 'QA_M5_RUN_ID contains unsafe characters'
[[ "$FIXTURE_ID" =~ ^m5-fresh-[A-Za-z0-9_.:-]{1,64}$ ]] || fail 'QA_M5_FIXTURE_ID must identify a fresh fixture'
if [[ -n "$EXTERNAL_DB_URL" || -n "$EXTERNAL_DB_TOKEN" ]]; then
  [[ -n "$EXTERNAL_DB_URL" && -n "$EXTERNAL_DB_TOKEN" ]] ||
    fail 'QA_DB_EVIDENCE_URL and QA_DB_EVIDENCE_TOKEN must be supplied together'
  [[ "$EXTERNAL_DB_URL" == https://* ]] ||
    fail 'QA_DB_EVIDENCE_URL must use HTTPS; only the controlled loopback helper may use HTTP'
fi
[[ "$LIVE_PHONE" =~ ^1[3-9][0-9]{9}$ ]] || fail 'QA_LIVE_PHONE is invalid'
[[ "$RECEIVER_PHONE" =~ ^1[3-9][0-9]{9}$ ]] || fail 'QA_M5_RECEIVER_PHONE is invalid'
[[ "$RECEIVER_PHONE" != "$LIVE_PHONE" ]] || fail 'QA_M5_RECEIVER_PHONE must be a distinct second account'
[[ -n "$OAUTH_CLIENT_ID" ]] || fail 'QA_OAUTH_CLIENT_ID is empty'
[[ -z "$(env_value DEVELOPMENT_OUTBOX_KEY)" && -z "$(env_value QA_DEVELOPMENT_OUTBOX_KEY)" ]] || fail 'development outbox secrets are forbidden'
[[ -z "$(env_value CONTRACT_SERVER_PORT)" && -z "$(env_value QA_CONTRACT_SERVER_PORT)" ]] || fail 'contract server variables are forbidden'
if is_true "$PAYMENT_ALLOW_REQUEST"; then
  case "${PAYMENT_SCENARIO:-none}" in
    cancel|success) ;;
    none) fail 'payment scenario is required when external payment is enabled' ;;
    *) fail 'payment scenario must be none, cancel, or success' ;;
  esac
  [[ "$PAYMENT_CONFIRMATION" == 'I_UNDERSTAND_SANDBOX_PAYMENT' ]] || fail 'external payment opt-in confirmation is required'
  if [[ "${PAYMENT_SCENARIO:-none}" == 'success' ]]; then
    [[ "$PAYMENT_SUCCESS_CONFIRMATION" == 'I_UNDERSTAND_SANDBOX_SUCCESS_PAYMENT' ]] ||
      fail 'success payment confirmation is required'
  fi
  is_true "$ENABLE_ALIPAY" || fail 'Alipay provider build flag is required for payment opt-in'
  PAYMENT_OPT_IN='true'
elif [[ -n "$PAYMENT_SCENARIO" && "$PAYMENT_SCENARIO" != 'none' &&
  "$PAYMENT_SCENARIO" != 'cancel' && "$PAYMENT_SCENARIO" != 'success' ]]; then
  fail 'payment scenario must be none, cancel, or success'
fi
for command_name in adb flutter docker git python3 awk grep find mktemp shasum sort tr; do command -v "$command_name" >/dev/null 2>&1 || fail "missing command: $command_name"; done
if [[ -n "$EXTERNAL_DB_URL" ]]; then
  validate_external_db_url "$EXTERNAL_DB_URL" ||
    fail 'QA_DB_EVIDENCE_URL must be an HTTPS evidence endpoint without credentials or query data'
fi
[[ -f "$PROJECT_ROOT/pubspec.yaml" ]] || fail 'not a Flutter checkout'
create_safe_artifact_root || fail 'artifact root must be a new absolute directory'
trap cleanup EXIT
assert_flutter_checkout_clean
attest_flutter_sdk
attest_backend
attest_serving_backend
FLUTTER_SHA_ACTUAL="$(git -C "$PROJECT_ROOT" rev-parse --verify HEAD)" || fail 'Flutter SHA unavailable'
[[ "$FLUTTER_SHA_ACTUAL" == "$FLUTTER_SHA_EXPECTED" ]] || fail 'QA_FLUTTER_SHA mismatch'
prepare_android_host
prepare_android_audio_manifest
attest_android_host
"$FLUTTER_BIN" clean >/dev/null 2>&1 || fail 'Flutter clean failed'
"$FLUTTER_BIN" pub get --enforce-lockfile >/dev/null 2>&1 || fail 'locked Flutter dependency regeneration failed'
start_relay
attest_debug_apk
install_attested_apk
start_db_evidence_helper
set +e
run_one AVD-A "$A_API" "$A_PROFILE" "$A_PHYSICAL" "$A_DENSITY" "$A_WIDTH" "$A_HEIGHT" "$A_DPR" "$AVD_A_SERIAL" &
pid_a=$!
run_one AVD-B "$B_API" "$B_PROFILE" "$B_PHYSICAL" "$B_DENSITY" "$B_WIDTH" "$B_HEIGHT" "$B_DPR" "$AVD_B_SERIAL" &
pid_b=$!
wait "$pid_a"
status_a=$?
wait "$pid_b"
status_b=$?
set -e
if [[ "$status_a" -ne 0 || "$status_b" -ne 0 ]]; then
  OVERALL_RESULT='FAIL'
  LAST_RESULT_REASON='one_or_more_avds_failed'
elif [[ "$PAYMENT_OPT_IN" != 'true' ]]; then
  if [[ "$(sed -n 's/^result=//p' "$ARTIFACT_ROOT/AVD-A/result.txt" 2>/dev/null | head -n 1)" == 'NO_PAY' &&
    "$(sed -n 's/^result=//p' "$ARTIFACT_ROOT/AVD-B/result.txt" 2>/dev/null | head -n 1)" == 'NO_PAY' ]]; then
    OVERALL_RESULT='NO_PAY'
  else
    OVERALL_RESULT='PARTIAL'
  fi
fi
exit "$([[ "$OVERALL_RESULT" == PASS || "$OVERALL_RESULT" == NO_PAY ]] && printf 0 || printf 1)"
