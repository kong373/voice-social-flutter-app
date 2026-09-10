# R01 explicit registration profile and avatar upload

User decisions: registration requires nickname, explicit avatar choice and explicit
sex (0/1/2). Avatar may be uploaded or selected from the six presets. Registration
does not require birthday, real-name verification or an age check; the age rule
belongs to real-name verification.

The live registration page implements the preset/profile path and anonymous avatar
selection, bounded preview, upload, status recovery and final READY binding.
Registration retains the original SMS challenge,
phone/device binding and a stable request key. Resend, cancellation and expiry
invalidate that context; late responses cannot publish a session. The anonymous
registration request strips injected Authorization/Content-Encoding headers,
does not follow redirects and does not invoke authenticated refresh/replay.

Invalid invitation input is retained until the user explicitly removes it.
The product never defaults to the first avatar or an undisclosed sex choice.
The uploaded choice requires the current host's canonical READY asset UUID/version
and allocation request key/capability. An arbitrary client-supplied UUID is rejected.
Interrupted PUT recovery checks the original asset; it never silently creates a
replacement or sends the bytes twice. Cancel, expiry, account/context replacement
and disposal invalidate the host and clean its temporary selection. The preview
owns and evicts its exact ResizeImage key, including pending decodes; unrelated
global image-cache entries are not cleared.

An uncertain final registration response is not a retry instruction: the page
blocks another registration POST and returns to normal login with a fresh SMS
challenge to recover the server's authoritative result. Known validation errors
preserve the nickname/invitation input and original submission binding.

Verification on Flutter 3.44.7:
- 49 affected profile/auth/parser tests pass; full analyze has no issues.
- Independent review found one old navigation fixture missing SMS preparation.
  The existing route-preservation assertions failed before correction. Adding
  the current phone's SMS challenge preparation makes all 8 navigation tests pass.
- No device, provider, payment, deployment or final full-suite acceptance was run.

Full upload wiring verification (same SDK, separate from the foundation above):
- The first combined run after wiring passed 100 affected tests and full analyze.
- Independent review reproduced preview cache retention; 8 regression cases failed
  before the local eviction change and pass after it (decoded/pending x cancel,
  invalidation, unmount and replacement; late completion cannot repopulate cache).
- Widget IO/temporary-file cleanup runs within the correct widget clock; bounded
  waits observe actual completion and preserve the original business assertions.
- Final combined registration/auth/host/transport verification passed 108/108;
  full analyze, changed-file format and diff checks passed. Evidence is recorded in
  `artifacts/product/filled-decisions-20260909/r01-upload-flow-combined-r6.log`
  at the workspace root. No old device evidence is promoted to this candidate.
