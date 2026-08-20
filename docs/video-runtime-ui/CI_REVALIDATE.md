# M3.3 Video Runtime UI CI Revalidation

This marker triggers a fresh reviewable CI run after the video-runtime interaction tests, public-client readiness semantics, authenticated shell fixture, room lifecycle smoke flow, and 1.3× responsive home mosaic were corrected under Flutter 3.44.7.

- Target branch: `feat/m3-3-video-runtime-ui`
- Base branch: `feat/m3-2a-live-auth-readonly`
- Candidate: `fabd5a86b754983a0b5faa2fb1e7578446a8113a`
- Scope: video-recording-matched runtime UI pilot
- Required gate: format, analyze, all tests, Android debug build, AVD-A, AVD-B, strict verdict
- Merge authorization: none
- Provider integrations: remain fail-closed
