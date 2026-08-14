# M1 Acceptance Gate

The current checkpoint is accepted only when GitHub CI proves all of the following:

- dependency resolution succeeds;
- Dart analysis reports no issues;
- the 69-page manifest remains complete and unique;
- agreement, SMS login, session persistence, logout, and registration-required branches pass tests;
- fixed eight-seat mapping passes, including special backend seat zero and impossible nine-seat conflict;
- room role/capability rules pass;
- room join, mic request, mute, public screen, ordinary gift, reconnect warning, and exit pass controller tests;
- a 390×844 widget test clicks through consent → login → home → room → gift → leave;
- Android debug APK builds in an isolated generated runner.

Passing this gate confirms the **mock-backed M1 contract checkpoint**, not production RTC, realtime, payment, backend deployment, or full 69-page completion.

## Fail-closed integration gates

- Live RTC and realtime transports remain blocked until approved SDK/handshake configuration is supplied.
- Live room gift sending remains disabled until the authoritative ordinary-gift catalog and economy balance contract are wired; mock gift IDs are never sent to production.
- Online count is nullable until a verified room-presence source is connected.
