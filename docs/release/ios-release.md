# iOS Release Candidate archive gate

`tool/release/ios_release_validator.sh` is a read-only acceptance gate for an
explicit `.xcarchive`. It does not build, sign, publish, or access App Store
services. It writes only short-lived scratch files under the operating
system's temporary directory and never prints tool reports, certificate
contents, profile identifiers, account data, input paths, or credential-like
values.

## Real-candidate invocation

All expected identity and version fields are required. The IPA is optional:

```bash
tool/release/ios_release_validator.sh \
  --archive /secure/release/VoiceSocial.xcarchive \
  --expected-bundle-id com.example.voiceSocial \
  --expected-version 1.2.3 \
  --expected-build 42 \
  --expected-team-id TEAMID1234 \
  --ipa /secure/release/VoiceSocial.ipa
```

The archive gate checks the root `Info.plist`, exactly one app under
`Products/Applications`, the app's `Info.plist` and main executable, device
(`iphoneos`) rather than Simulator evidence, an arm64/arm64e device
architecture, a strict and valid recursive code signature, and a distribution
identity (`Apple Distribution` or the legacy `iPhone Distribution` form).
Ad-hoc and development/debug signatures are rejected.

The embedded profile is decoded with `security cms -D` into a temporary file,
then linted and checked for application identifier, team identifier,
application identifier prefix, `get-task-allow=false`, and a future
`ExpirationDate`. The signed entitlement dictionary is linted and every
top-level entitlement is required to be present in the profile with the same
scalar value or as an array subset. A dictionary-valued signed entitlement is
not accepted without a provable subset comparison. The signed entitlement
dictionary must itself contain the expected application identifier and team
identifier, with `get-task-allow=false`.

The app must contain a valid, non-symlink `PrivacyInfo.xcprivacy`. The summary
contains SHA-256 values for the archive `Info.plist`, a deterministic app
bundle manifest, the main executable, and—when an IPA is supplied—the IPA
file, IPA app bundle, and IPA executable. Bundle ID, version, build, signing
identity class, team, app name, executable name, and normalized executable
content are compared between the archive app and the IPA app. The entire
bundle also has a required normalized content digest: every Framework
(including Flutter's `App.framework`), plugin, and resource must match, not
just the main executable. Only `_CodeSignature` files and embedded profiles
are omitted; each Mach-O file has its signature removed on a temporary copy.
Other export-time content changes fail closed and require investigation.
Normalization
removes only the code signature from a temporary copy; the archive and IPA are
never modified. Raw app/executable SHA-256 values are evidence outputs, not
an unnecessary byte-for-byte equality gate, so normal export-time re-signing
and provisioning-profile replacement remain possible.

Before extraction, the IPA entry list is restricted to one `Payload/<app>.app`
tree. Absolute names, dot-dot components, backslashes, unexpected entries,
duplicate names, multiple apps, symlinks, and all special files are rejected.
Extraction uses no-overwrite mode into a new temporary directory, and the IPA
digest is checked before and after validation. The extracted app is validated
with the same checks as the archive app.

The normal success summary contains fixed labels and hashes only:

```text
ios-release-validation=PASS
archive_info_sha256=<sha256>
archive_app_sha256=<sha256>
archive_executable_sha256=<sha256>
archive_executable_content_sha256=<sha256>
ipa_sha256=<sha256>
ipa_app_sha256=<sha256>
ipa_executable_sha256=<sha256>
ipa_executable_content_sha256=<sha256>
```

Failures use a fixed reason code and never echo the rejected value. Run the
gate on macOS with the Xcode command-line tools available (`plutil`,
`PlistBuddy`, `codesign`, `security`, `file`, and `otool`). The host clock is
used for profile expiry, so a materially incorrect clock can cause a
fail-closed result.

## Offline tooling self-test

The complete self-test requires macOS: its synthetic signing tools still use
Apple's real `plutil` and `PlistBuddy` for plist validation. The macOS CI job
runs this full positive and negative contract before any iOS build; failure
stops the job. Linux Flutter tests instead execute the script and require its
exact missing-Apple-tool failure, empty stdout, and redacted stderr. They are
not skipped, but their passing result is only a fail-closed portability check,
not a successful native self-test or signed-artifact validation.

```bash
tool/release/ios_release_validator.sh --self-test
```

The self-test builds a completely temporary fixture and temporary fake
`codesign`, `security`, `file`, and `otool` commands. It exercises a synthetic
success path plus Simulator, invalid signature, ad-hoc, development/debug,
enabled task allowance, expired profile, profile application mismatch,
export-time profile replacement, multiple-app IPA, symlink IPA, and
path-traversal IPA fail-closed paths. Its only success output is:

```text
ios-release-validator=self-test-PASS
```

That result proves only the validator's offline contract and redaction logic;
it is not a real archive and does not prove that any signing certificate,
provisioning profile, archive, IPA, or App Store submission is valid. The
synthetic internal `PASS` is captured and never exposed as a real-candidate
result. A real-candidate `PASS` is possible only when the validator is run
against operator-supplied archive/IPA evidence with Apple's command-line tools.

## Verification ladder

From the repository root, run:

```bash
bash -n tool/release/ios_release_validator.sh
shellcheck tool/release/ios_release_validator.sh  # when installed
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/dart format --set-exit-if-changed \
  test/ios_release_candidate_contract_test.dart
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter analyze \
  test/ios_release_candidate_contract_test.dart
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter test \
  test/ios_release_candidate_contract_test.dart
git diff --check
```

The contract test dynamically runs `--self-test` and statically checks the
required evidence surfaces plus the absence of signing, network/publishing,
App Store, and credential-output behavior. The self-test is intentionally not
a substitute for running the validator against a real release candidate.

Known boundaries: the gate verifies local archive/IPA evidence only; it does
not establish App Store Connect state, TestFlight processing state, notarized
distribution, or a product-level runtime acceptance result. A supplied IPA is
cross-checked only when the operator explicitly supplies it.
