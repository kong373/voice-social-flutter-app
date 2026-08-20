# M3.3 Video Runtime UI CI Revalidation

This marker triggers a fresh reviewable CI run after applying Flutter 3.44.7 formatting to every Dart file changed from `main`.

- Target branch: `feat/m3-3-video-runtime-ui`
- Base branch: `feat/m3-2a-live-auth-readonly`
- Formatted candidate: `8016373ea400f09b3e064d0438ed779adfc65edb`
- Scope: video-recording-matched runtime UI pilot
- Required gate: format, analyze, all tests, Android debug build, AVD-A, AVD-B, strict verdict
- Merge authorization: none
- Provider integrations: remain fail-closed
