# Live development launcher

`tool/live_development.sh` is the single local entry point for first-party
development integration. It keeps the normal debug build in mock mode while
making a live development run explicit and fail-closed. The optional
`--enable-agora-rtc` switch is the only way this launcher enables the live
first-party Agora audio transport; when omitted, it passes an explicit
`ENABLE_AGORA_RTC=false` define.

## Required inputs

Set only the development gateway and the public OAuth client identifier in the
local shell. Neither value is written to the repository by the launcher.

```bash
export API_BASE_URL=http://10.0.2.2:18080/
export OAUTH_CLIENT_ID=voice-social-mobile-public
```

`OAUTH_CLIENT_ID` is an opaque public-client identifier, not a proof that an
arbitrary value is non-sensitive. The launcher rejects values that are
obviously secret-like (including `secret`, `token`, or key names), whitespace,
newlines, and `=`; callers remain responsible for supplying a public client ID.
The Flutter application must never receive an OAuth client secret, JWT secret,
vendor key, payment key, storage credential, or private key. The launcher
rejects secret-like environment variables and arguments and does not accept
`--dart-define-from-file`.

## Address mapping

The target selector prevents accidentally using the wrong loopback address:

| Target | Gateway URL | Use |
| --- | --- | --- |
| `android-emulator` | `http://10.0.2.2:18080/` | Android Emulator or BlueStacks reaching a backend on the Mac host |
| `host` | `http://127.0.0.1:18080/` | A Flutter process running directly on the Mac (`run` only) |

`127.0.0.1` inside an Android Emulator points to the emulator itself, not the
Mac. The launcher requires the matching URL host before it invokes Flutter.
`build-apk` accepts only `android-emulator`; a host-target APK would bake
`127.0.0.1` into an Android process and therefore point back to the device,
not the Mac.
For `run`, `--device` is checked against the target: `android-emulator` accepts
selectors such as `emulator-5554` or `127.0.0.1:5555`, while `host` rejects
Android emulator selectors and should use a host selector such as `macos`.
Both `run` targets require an explicit `--device`; Flutter's automatic device
selection is not allowed. `build-apk` rejects `--device` because it produces an
APK rather than selecting a running device. The API value is an origin with an
optional single root `/` only; paths such as `/token` are rejected. Its port,
when present, must be in the range 1 through 65535.
Local HTTP is allowed only because the wrapper fixes `APP_ENV=development` and
passes `ALLOW_INSECURE_HTTP=true`; this entry point cannot be used for staging
or production.

## Commands

The launcher verifies Flutter 3.44.7 and Dart 3.12.2 before every real run or
build. Point `FLUTTER_BIN` at the repository's FVM 3.44.7 executable; another
SDK fails before Flutter can build or install anything:

The launcher also forces `ENABLE_QA_CONSOLE=false` and
`ENABLE_VIDEO_RUNTIME_DEMO=false`; a live build cannot route into either
Mock-backed shell even when the host environment requests one.

Only the wrapper's options are accepted. A small allowlist of non-defining
diagnostic flags (`--verbose`, `--quiet`, `--wrap`, `--no-wrap`, `--color`,
`--no-color`, `--suppress-analytics`, and `--disable-analytics`) may follow
`--`. Unknown Flutter options are rejected before Flutter starts.

```bash
# Check configuration without starting Flutter or contacting the backend.
./tool/live_development.sh build-apk \
  --target android-emulator \
  --dry-run

# Run on an Android Emulator / BlueStacks device with snapshot-only room audio.
./tool/live_development.sh run \
  --target android-emulator \
  --device emulator-5554

# Opt into the server-issued Agora audio transport for this run.
./tool/live_development.sh run \
  --target android-emulator \
  --device emulator-5554 \
  --enable-agora-rtc

# Build a debug APK with the Android Emulator address baked in.
./tool/live_development.sh build-apk \
  --target android-emulator

# Build a debug APK with the live Agora audio transport enabled.
./tool/live_development.sh build-apk \
  --target android-emulator \
  --enable-agora-rtc
```

## Isolated Android host

The Android target works from a clean checkout even though this repository does
not track an `android/` directory. Before a live run or APK build, the launcher
requires `git status --porcelain --untracked-files=normal` to be empty, then
creates a temporary Flutter Android host under `TMPDIR`, overlays the tracked
checkout sources, runs `tool/prepare_android_audio_manifest.py`, and performs a
locked `flutter pub get`. Flutter then runs from that temporary host. The
generated directory is removed on exit, so the ignored `android/` host never
pollutes this checkout or becomes a commit candidate. A dirty checkout fails
before Flutter starts; commit or remove local changes first so the app source
being built is unambiguous and no untracked secret can enter the host.

`tool/bootstrap_local.sh` remains available for general local Flutter runners,
but it copies a generated platform host into the checkout and therefore is not
used by the live Android launcher. The audio manifest helper keeps
`RECORD_AUDIO` and removes `CAMERA`, `READ_PHONE_STATE`,
`FOREGROUND_SERVICE_MEDIA_PROJECTION`, and Agora screen-capture components.

For a host Flutter target, change both the environment and selector. This is a
`run` target; do not use it to build an Android APK:

```bash
export API_BASE_URL=http://127.0.0.1:18080/
./tool/live_development.sh run --target host --device macos
```

The M3.3 golden/widget tests no longer depend on `../artifacts` font drops.
They load the checked-in subset fonts under `test/fonts/`, and the subset can
be regenerated deterministically with `python3 tool/qa/build_m33_golden_fonts.py`
from the pinned upstream Noto Sans SC commit when needed.

The launcher always injects:

```text
BACKEND_MODE=live
APP_ENV=development
ENABLE_QA_CONSOLE=false
ENABLE_VIDEO_RUNTIME_DEMO=false
ENABLE_AGORA_RTC=<true only when --enable-agora-rtc is present; otherwise false>
API_BASE_URL=<validated target URL>
OAUTH_CLIENT_ID=<public client id>
ALLOW_INSECURE_HTTP=true
```

It also sets the non-sensitive client metadata defaults used by
`AppEnvironment`; these values are fixed by the wrapper and cannot be supplied
through ordinary host environment variables. Flutter receives no OAuth or
vendor secret. `--dry-run`
prints only the target, API origin, and whether the public client is configured;
it never prints the client identifier itself.

The `ENABLE_AGORA_RTC` environment variable and related environment aliases
(`AGORA_RTC`, `AGORA_ENABLE_RTC`, `DART_DEFINES`, `FLUTTER_TOOL_ARGS`, and
Gradle project-define variables) are rejected. Arbitrary `--dart-define`,
`--dart-define-from-file`, Gradle define, and Android project-argument aliases
remain rejected as well; the wrapper owns every runtime define and never
accepts an OAuth or vendor secret.

The launcher uses an explicit two-level environment policy. Environment
variable and CLI argument checks are case-insensitive: names that clearly
denote application or vendor credentials (`CLIENT_SECRET`, `SECRET`,
`PASSWORD`, `PRIVATE_KEY`, `ACCESS_KEY`, `*_API_KEY`, `*_CREDENTIALS`, `*_PAT`,
`*_AUTH`, or `*_BEARER`) fail before Flutter. Normal system variables such as
`PATH`, `HOME`, `SHELL`, and `SSH_AUTH_SOCK` are not treated as credentials.
Ordinary `*_TOKEN` names, including lowercase or mixed-case spellings, are
removed from the Flutter child environment instead of being forwarded; their
values are never printed. `-D`, `--dart-define`, `--DartDefines`,
`--dart-define-from-file`, Gradle `-P` define forms, and
`--android-project-arg` are rejected regardless of argument casing. This keeps
unrelated host tokens out while ensuring a secret or user-supplied Dart define
cannot bypass the wrapper through casing or an alternate Flutter/Gradle
spelling. The child still receives no OAuth or vendor credential. Run the
launcher from a shell without hard credential variables when local tooling sets
them.

Flutter itself is started under `env -i` with only the SDK/runtime allowlist:
`PATH`, `HOME`, `USER`/`LOGNAME`, `TMPDIR`, `SHELL`, `LANG`/`LC_*`, Java and
Android SDK paths, `PUB_CACHE`, `GRADLE_USER_HOME`, and the macOS SDK selector
variables needed by a host run. Profile/config/auth variables such as
`AWS_PROFILE`, `KUBECONFIG`, `DOCKER_CONFIG`, and `SSH_AUTH_SOCK` are not passed
to either the version probe or the run/build child. This allowlist is the
fail-closed boundary for unknown vendor environment names; it is not an
attempt to enumerate every possible credential suffix.

## What this does not do

The launcher does not call `/health`, request an SMS, authenticate a user,
create a room, send a message, create an order, charge a wallet, or invoke an
RTC, IM, push, payment, or storage provider. Those are separate integration
and acceptance steps. The backend must be started independently on port
`18080` before a live run can make a read or authentication request.
