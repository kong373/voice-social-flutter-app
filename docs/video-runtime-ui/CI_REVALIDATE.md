# M3.3 Video Runtime UI CI Revalidation

This marker triggers a fresh reviewable CI run after applying Flutter 3.44.7 formatting and the deployment-environment import correction.

- Target branch: `feat/m3-3-video-runtime-ui`
- Base branch: `feat/m3-2a-live-auth-readonly`
- Candidate: `c661470b4c18aca7d169facd8d22f04d76a05f8e`
- Scope: video-recording-matched runtime UI pilot
- Required gate: format, analyze, all tests, Android debug build, AVD-A, AVD-B, strict verdict
- Merge authorization: none
- Provider integrations: remain fail-closed
