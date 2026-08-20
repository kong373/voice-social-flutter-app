# M3.3 Video Runtime UI CI Revalidation

This marker triggers a fresh reviewable CI run after applying the exact Flutter 3.44.7 formatter to the corrected video-runtime candidate.

- Target branch: `feat/m3-3-video-runtime-ui`
- Base branch: `feat/m3-2a-live-auth-readonly`
- Candidate: `aba28471e2df37f9837839bf2c828b11dde34341`
- Scope: video-recording-matched runtime UI pilot
- Required gate: format, analyze, all tests, Android debug build, AVD-A, AVD-B, strict verdict
- Merge authorization: none
- Provider integrations: remain fail-closed
