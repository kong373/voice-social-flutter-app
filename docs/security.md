# Security Rules

This repository is public. Never commit:

- production or test credentials;
- backend source archives;
- APK files or decompiled proprietary source;
- signing certificates or provisioning profiles;
- database, Redis, MongoDB, MQ, RTC, IM, payment, SMS, or cloud secrets;
- copied brand, gift, illustration, or animation assets.

## Runtime configuration

- Gateway host and OAuth configuration are injected with dart defines or the deployment secret store.
- Access tokens and the install identifier are persisted through platform secure storage in application builds.
- Tests use an in-memory store and fake tokens.
- Logs, tests, screenshots, and crash reports must never print authorization headers, SMS codes, device identifiers, or raw payment data.

## Contract exposure

Relative routes and redacted field schemas are included only where required to implement the authorized client contract. Server source, private infrastructure names, Nacos exports, production values, and internal network topology remain outside this repository.

## Transport fail-closed policy

Live mode does not fall back to a fake RTC or realtime connection. Until approved SDK adapters are configured, room entry fails visibly rather than presenting a non-functional voice session as connected.
