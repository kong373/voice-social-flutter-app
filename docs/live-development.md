# Live development launcher

`tool/live_development.sh` is the single local entry point for first-party
development integration. It keeps the normal debug build in mock mode while
making a live development run explicit and fail-closed.

## Required inputs

Set only the development gateway and the public OAuth client identifier in the
local shell. Neither value is written to the repository by the launcher.

```bash
export API_BASE_URL=http://10.0.2.2:18080/
export OAUTH_CLIENT_ID=voice-social-mobile-public
```

`OAUTH_CLIENT_ID` is a public-client identifier. The Flutter application must
never receive an OAuth client secret, JWT secret, vendor key, payment key,
storage credential, or private key. The launcher rejects secret-like
environment variables, rejects secret-like arguments, and does not accept
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
Local HTTP is allowed only because the wrapper fixes `APP_ENV=development` and
passes `ALLOW_INSECURE_HTTP=true`; this entry point cannot be used for staging
or production.

## Commands

Use Flutter 3.44.7 (for example, run these through the repository's FVM
checkout or set `FLUTTER_BIN` to that executable):

```bash
# Check configuration without starting Flutter or contacting the backend.
./tool/live_development.sh build-apk \
  --target android-emulator \
  --dry-run

# Run on an Android Emulator / BlueStacks device.
./tool/live_development.sh run \
  --target android-emulator \
  --device emulator-5554

# Build a debug APK with the Android Emulator address baked in.
./tool/live_development.sh build-apk \
  --target android-emulator
```

For a host Flutter target, change both the environment and selector. This is a
`run` target; do not use it to build an Android APK:

```bash
export API_BASE_URL=http://127.0.0.1:18080/
./tool/live_development.sh run --target host --device macos
```

The launcher always injects:

```text
BACKEND_MODE=live
APP_ENV=development
API_BASE_URL=<validated target URL>
OAUTH_CLIENT_ID=<public client id>
ALLOW_INSECURE_HTTP=true
```

It also sets the non-sensitive client metadata defaults used by
`AppEnvironment`. Flutter receives no OAuth or vendor secret. `--dry-run`
prints only the target, API origin, and whether the public client is configured;
it never prints the client identifier itself.

The launcher uses an explicit two-level environment policy. Exported names
that clearly denote application or vendor credentials (`SECRET`, `PASSWORD`,
`PRIVATE_KEY`, or `ACCESS_KEY`) fail before Flutter. Ordinary `*_TOKEN` names
are removed from the Flutter child environment instead of being forwarded;
this keeps unrelated host tokens out without blocking a local tool that happens
to export one. The child still receives no OAuth or vendor credential. Run the
launcher from a shell without hard credential variables when local tooling sets
them.

## What this does not do

The launcher does not call `/health`, request an SMS, authenticate a user,
create a room, send a message, create an order, charge a wallet, or invoke an
RTC, IM, push, payment, or storage provider. Those are separate integration
and acceptance steps. The backend must be started independently on port
`18080` before a live run can make a read or authentication request.
