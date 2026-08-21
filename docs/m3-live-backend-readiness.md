# M3.1 — Development gateway readiness

## Goal

Move the merged 69-page mock baseline toward an authorized non-production backend without introducing provider SDKs or committing runtime credentials.

This checkpoint is deliberately side-effect-free. It validates runtime configuration and gateway transport reachability before SMS, login, room, wallet, RTC, IM, or payment integration is attempted.

## Included

- Explicit deployment profiles: local, development, staging, and production.
- HTTPS enforcement for staging and production.
- Explicit opt-in for local/development HTTP through `ALLOW_INSECURE_HTTP=true`.
- Self-hosted preflight rejects public HTTP origins; insecure HTTP is limited to loopback or private development hosts.
- Bounded API/probe timeout between 5 and 60 seconds.
- Redacted runtime summary that never emits OAuth values or secret values.
- DNS, TCP, TLS, and HTTP reachability probe with distinct failure states.
- Live-mode login entry for an in-app redacted diagnostics page.
- Manual GitHub Actions workflow for the protected `development` environment.
- CLI preflight that produces a redacted JSON artifact and performs no business mutation.
- Self-hosted preflight uploads only allowlisted redacted evidence files; the raw `/health` response body is not retained as an artifact.

## Required development public-client configuration

Provide these two values to the preflight in the GitHub `development` environment or a local configuration store:

- `M3_API_BASE_URL`
- `M3_OAUTH_CLIENT_ID`

The Flutter app and both preflight workflows are OAuth public clients: they need only the API base URL and public client ID. The OAuth client secret is backend-only and must never be supplied as a mobile or preflight input. Do not add either configuration value to issues, pull requests, workflow YAML, screenshots, logs, or the repository.

For the self-hosted preflight, `M3_API_BASE_URL` may use `http://` only when it targets loopback or a private development host such as RFC1918, link-local, ULA, `.local`, `.lan`, or `.internal`. Any public HTTP origin fails closed and must be upgraded to HTTPS.

The self-hosted workflow publishes only allowlisted redacted evidence files: tested commit, runner metadata, Flutter runtime metadata, backend HTTP status, a redacted backend health summary, and the redacted preflight JSON. It must not upload the raw backend health body or any secret-bearing file.

## Runtime example

```bash
flutter run \
  --dart-define=BACKEND_MODE=live \
  --dart-define=APP_ENV=development \
  --dart-define=API_BASE_URL=https://authorized-dev-gateway.example/ \
  --dart-define=CLIENT_TYPE=Android \
  --dart-define=CLIENT_INNER_VERSION=6 \
  --dart-define=OAUTH_CLIENT_ID=... \
  --dart-define=API_TIMEOUT_SECONDS=15 \
  --dart-define=LIVE_PROBE_PATH=/
```

## Interpretation

`gatewayReachable` means only that the configured endpoint produced an HTTP response after system TLS verification. A 401, 403, or 404 can still prove transport reachability. It does not prove that SMS, authentication, response envelopes, user data, rooms, wallets, RTC, IM, or payment work.

## Next checkpoint

M3.2 will use a dedicated non-production account and the authorized development gateway to validate, in order:

1. SMS request contract without exposing phone data in logs.
2. SMS login and secure session persistence.
3. DS-001 recommendation and DS-002/003 search reads.
4. RM-003 validation, RM-004 HTTP room snapshot, and leave behavior without RTC publication.
5. CM-001 wallet and CM-005 order read-only data.

RTC, Tencent IM, payment invocation, push, native permissions, and object storage remain blocked until their provider configuration is approved.
