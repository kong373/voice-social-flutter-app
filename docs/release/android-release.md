# Android release host and signing

The Android host under `android/` is part of the repository release surface.
Generated caches and machine-local files remain ignored (`android/.gradle`,
`android/build`, `android/app/build`, `android/local.properties`,
`android/*.iml`, `android/key.properties`, and
`GeneratedPluginRegistrant.java`). The Gradle wrapper and host sources are
tracked so a release build does not depend on a developer's generated host.

## Signing contract

Debug builds continue to use the normal debug variant. Release builds use a
dedicated `release` signing config and fail closed if its material is absent,
ambiguous, unreadable, or invalid. The release config never aliases the debug
config.

Provide exactly one signing source in the release environment:

1. `ANDROID_RELEASE_SIGNING_PROPERTIES_FILE`, pointing to an untracked file
   containing `storeFile`, `storePassword`, `keyAlias`, and `keyPassword`; or
2. all four direct environment variables:
   `ANDROID_RELEASE_STORE_FILE`, `ANDROID_RELEASE_STORE_PASSWORD`,
   `ANDROID_RELEASE_KEY_ALIAS`, and `ANDROID_RELEASE_KEY_PASSWORD`; or
3. the ignored local file `android/key.properties` with those four keys.

The Gradle configuration does not print signing values. Do not commit the
properties file or any keystore. CI should inject the values through its secret
store and provide the keystore as a protected file.

The build wrapper first runs `:app:validateReleaseSigning`. This validates the
keystore format, store password, key alias, and key password before Flutter
starts either release build. An invalid or missing contract stops the build
without creating an APK or AAB.

## Build and validate

### Public runtime configuration

Release builds require one absolute-path JSON file containing only the public
defines consumed by `AppEnvironment.fromDefines()`. This file is build input,
not a credential, and must not contain OAuth, vendor, payment, signing, or
other secret fields.

The required values are:

- `APP_ENV`: exactly `staging` or `production`.
- `BACKEND_MODE`: exactly `live`.
- `API_BASE_URL`: an HTTPS origin with an optional root `/`; it cannot contain
  userinfo, a non-root path, query, or fragment.
- `OAUTH_CLIENT_ID`: a non-empty public identifier; secret-like values are
  rejected.
- `CLIENT_TYPE`: exactly `Android`.

The optional values mirror `AppEnvironment.fromDefines()`: positive
`CLIENT_INNER_VERSION` (default `1`), `API_TIMEOUT_SECONDS` from 5 through 60
(default `15`), `ROOM_REALTIME_ENDPOINT`, `LIVE_PROBE_PATH` beginning with `/`
(default `/`). `LIVE_PROBE_PATH` must use a single leading slash; a `//`
prefix is rejected because URI resolution would treat it as a new authority.
The boolean enables are `ENABLE_AGORA_RTC`,
`ENABLE_ALIPAY_APP_PAY`, and `ENABLE_TENCENT_IM`. `ALLOW_INSECURE_HTTP`,
`ALIPAY_FORMAL_ACCEPTANCE`, and `ENABLE_APPLE_IAP` must be false or omitted.
Boolean values may be JSON booleans or the exact strings `true`/`false`.

The validator rejects missing, relative, non-regular, or symlink config files,
duplicate JSON keys, unknown fields, malformed JSON, and oversized files. It
emits no config values and runs before any Gradle, Flutter, generated-source
cleanup, or build step. After validation it serializes that same in-memory
object once into a fresh canonical snapshot with a 0600 file mode inside a
0700 temporary directory. The original public path is never reread by the
builds; the snapshot is the only runtime-config input for both builds and is
removed on exit.

After dependencies are available, run:

```bash
tool/release/android_release_build.sh \
  --config-file /absolute/path/to/public-android-release.json \
  --flutter-bin /path/to/flutter
```

The command passes the same validated private snapshot to both the APK and AAB
release builds with `--dart-define-from-file`, copies both artifacts under the
ignored `build/android-release/` directory, and invokes the validator. The
validator checks the package ID, release non-debuggable state, APK/AAB
signatures, SHA-256 of both output artifacts, required AAB entries, and absence
of the debug-only Alipay isolation surface. It emits only pass/fail and
artifact hashes; certificate subjects and signing details are kept in temporary
files. A `bundletool` executable is required for the AAB manifest check; the
validator fails closed when it is unavailable instead of treating package-only
parsing as proof of a non-debuggable release.

The expected fail-closed check without signing material is to provide a valid
public config while leaving the signing contract unset:

```bash
tool/release/android_release_build.sh \
  --config-file /absolute/path/to/public-android-release.json \
  --flutter-bin /path/to/flutter
```

with no signing environment and no `android/key.properties`. A release build
must fail before producing a release artifact. Do not replace this check with
the debug keystore or a debug APK.

For deterministic tooling self-tests:

```bash
python3 tool/release/android_release_config_validator.py --self-test
tool/release/android_release_validator.sh --self-test
tool/release/android_release_build.sh --self-test
```

The build-wrapper self-test retains the missing-signing-material probe and
does not start Flutter packaging; it does not require a runtime config file.

The debug-only `NativeAlipayIsolationActivity` is supplied by the Alipay
plugin's `src/debug` source set and is not declared by the main Android host;
the release validator rejects it if it is ever present in an APK or AAB.
