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

After dependencies are available, run:

```bash
tool/release/android_release_build.sh \
  --flutter-bin /path/to/flutter
```

The command builds both `app-release.apk` and `app-release.aab`, copies them
under the ignored `build/android-release/` directory, and invokes the
validator. The validator checks the package ID, release non-debuggable state,
APK/AAB signatures, SHA-256 of both output artifacts, required AAB entries, and
absence of the debug-only Alipay isolation surface. It emits only pass/fail and
artifact hashes; certificate subjects and signing details are kept in temporary
files. A `bundletool` executable is required for the AAB manifest check; the
validator fails closed when it is unavailable instead of treating package-only
parsing as proof of a non-debuggable release.

The expected fail-closed check without signing material is:

```bash
tool/release/android_release_build.sh \
  --flutter-bin /path/to/flutter
```

with no signing environment and no `android/key.properties`. A release build
must fail before producing a release artifact. Do not replace this check with
the debug keystore or a debug APK.

For deterministic tooling self-tests:

```bash
tool/release/android_release_validator.sh --self-test
tool/release/android_release_build.sh --self-test
```

The debug-only `NativeAlipayIsolationActivity` is supplied by the Alipay
plugin's `src/debug` source set and is not declared by the main Android host;
the release validator rejects it if it is ever present in an APK or AAB.
