# R01 explicit registration profile foundation

User decisions: registration requires nickname, explicit avatar choice and explicit
sex (0/1/2). Avatar may be uploaded or selected from the six presets. Registration
does not require birthday, real-name verification or an age check; the age rule
belongs to real-name verification.

This commit implements the explicit preset/profile path and the submission binding,
not the complete upload UI. Registration retains the original SMS challenge,
phone/device binding and a stable request key. Resend, cancellation and expiry
invalidate that context; late responses cannot publish a session. The anonymous
registration request strips injected Authorization/Content-Encoding headers,
does not follow redirects and does not invoke authenticated refresh/replay.

Invalid invitation input is retained until the user explicitly removes it.
The product never defaults to the first avatar or an undisclosed sex choice.
The uploaded choice shape requires a canonical asset UUID/version and upload
capability, but its host/UI integration is a following batch.

Verification on Flutter 3.44.7:
- 49 affected profile/auth/parser tests pass; full analyze has no issues.
- Independent review found one old navigation fixture missing SMS preparation.
  The existing route-preservation assertions failed before correction. Adding
  the current phone's SMS challenge preparation makes all 8 navigation tests pass.
- No device, provider, payment, deployment or final full-suite acceptance was run.
