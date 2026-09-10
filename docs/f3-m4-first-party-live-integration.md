# F3/M4 first-party live integration status

## 2026-09-10 dual host reuse draft — NOT_RUN

This scoped update is based on Flutter `1bce2177d081fe934ce0b4baed5a2b7920da5fd8`.
It changes only the existing dual integration test and offline regressions.
No device, DB, provider, real payment, PK code, private configuration or old
host source was modified/executed. The older sections below are historical;
removed product capabilities are not restored by this draft.

### Current device-test contract

- A is the canonical room owner and the room guild's current chair. B remains
  a real MEMBER/listener and has ORDINARY income eligibility (no manager
  promotion and no synthetic grant). A goes to seat 1. B uses the actual
  approval sheet to request seat 2 (normal seats are 2..9); A opens the real
  management page and clicks the matching applicant's `同意` button.
- Both initial and post-reentry rounds require the exact REQUEST to become
  APPROVED by A, assigned to the requested seat, plus authoritative room reads
  and actual controller seat state. The second request and room session must
  be new. Both down-mic rounds verify empty pair seats; ordinary membership
  never becomes manager authority. No repository mutation is called by QA.
- The existing relay phase list stays unchanged. In particular, read empty
  seats before `manual_room_reentry`; sample both starting wallets before
  `gift-seated`. These barriers prevent a faster peer racing the read window.
- Each role sends exactly one quantity-one gift. Existing single-target,
  receipt identity, provider-zero and serialized sender debit checks remain.
  Incoming/outgoing income currency and exact amount must match current rules.
  Both end wallets must equal the full pair's expected movements, including
  A's commission on BOTH transfers. Platform coins use integer tenths/BigInt;
  missing precision or historical receipt currency fails, never implies cash.
- New report fields require `ordinaryMicApprovalRounds=2`,
  `ordinaryMemberPromoted=false`, current `giftSettlement`, and mandatory host
  per-transfer ledger evidence. HTTP <=5s and normal enabled IM <=2s remain
  separate gates; disabled IM/RTC are not passed. 60 active pages / 14 states
  are not expanded by these actions. Old 69-page archives are not active scope.

### Existing host sources; parameterization proposal only

Read-only source snapshots recovered under workspace root:

- `artifacts/release/cross0907-e01f58ed98/composition-source.mjs` (Android A / iOS B).
- `artifacts/release/dualios0907-85f11d9758/composition-source.mjs` (iOS pair,
  referring to the existing `run-dual-ios-20260907.mjs` composition).

Keep their relay, native-window observer, install hashes, paused VM attachment,
existing Dart driver, deadlines, redaction and cleanup. Do not execute archived
sources or introduce another Runner. They currently have no CLI parser; the
following are replacement inputs for the main operator's existing composition,
not already-supported command-line flags:

| Fixed source item | Required replacement/validation |
|---|---|
| Old Flutter/Backend SHA literals | Final reviewed 40-character SHAs; retain clean worktree and running source-digest attestation |
| SDK/device/viewport constants | Exact Flutter3.44.7/Dart3.12.2, selected two devices; retain installed binary hashes and clear foreground native-window checks |
| Docker socket/container names | Explicit isolated Backend/MySQL identities; verify 28080 loopback mapping refers to the checked backend; never original18080 |
| Private `ios-public-live28080.json` dependency | Retain protected public-client configuration input; no credentials in defines/argv; do not read or publish its contents in this change |
| Private `IosReadOnlyObserver.java` dependency | Retain read-only observation contract and source hash; compile in run-owned directory, not over the shared class |
| Registration payload | Fetch `/app-register-api/media/v1/avatar-presets`; explicitly choose an allowed PRESET reference and sex; send `avatar: {kind: PRESET, reference: selectedPreset}` and the SAME SMS response's `challengeId`, code, device and client binding. Explicit sex 0 is valid; absent is not. No upload capability is needed for PRESET |
| Close-owned-rooms loop + new room POST | Remove those setup writes when reusing the dedicated fixture. Supply an existing dedicated OPEN PUBLIC room with canonical A owner, active guild/chair binding and empty seats. Closing does NOT free quota; never close unrelated or all owned rooms |
| Old empty DIRECT fixture | Require B current MEMBER, no seat/REQUEST leftovers, A owner, normal seat2 available, both legitimate sessions. Never promote B to satisfy old DIRECT assumptions |

Fresh registration alone does not make a guild owner or an adult verified
anchor. The existing guarded development provisioning hook may create wallets,
recharge records, real-name/payout fixtures, guilds, rooms and synthetic peers.
The main operator must explicitly decide and attest permitted fixture setup;
this proposal does not enable it or write roles/age/DB rows. In particular its
legacy VERIFIED marker lacks identity-age proof. Registration birthday is not
real-name evidence. B must not retain a seeded chair role in another guild.
Use existing authorized fixture preparation, or stop before relay readiness.

### Exact gift evidence migration (do not relax counts)

Let `p` be the authoritative whole-coin catalog price, quantity one per sender,
`v = p * 10` fen, `r = floor(v / 2)`, and `c = floor(v * 15 / 100)`.
For this fixture A is the SAME room's chair and receives cash; B is ordinary:

- A: coin tenths delta `-p*10`, cash fen delta `r + 2*c`.
- B: coin tenths delta `-p*10 + r`, cash fen delta `0`.
- Both frozen projections unchanged; two distinct transfers, request IDs and
  senders, quantity exactly one each, correct room/gift/receiver, no provider.
- Replace old `creator_income_minor == catalog.creator_income_minor * quantity`
  and CASH-only linkage with each transfer's current rule, income currency,
  guild/beneficiary and value fields. Require current revenue rule
  `HOST_ROLE_ROOM_GUILD_V2`, not unknown metadata.
- Base accounting for these two positive-price transfers is exactly six
  business journals / twelve postings / six wallet transactions: two SEND,
  two INCOME, two GUILD_GIFT_INCOME. Include chair business rows in scope even
  when their actor/counterparty differs from the direct recipient.
- B ordinary income has exactly one `gift_coin_precision_credit`. Compute
  `carry = floor((B starting fraction remainder + r) / 10)`. If carry >0,
  require exactly one COIN_PRECISION_CARRY journal with FOUR postings balanced per
  currency, and TWO carry wallet transactions. If carry=0, require zero carry
  rows. Do not count a carry as another gift or assume every journal has two
  postings. For quantity >1 in a future case, aggregate value before flooring.
- Projection bootstrap journals are separate, explicitly classified evidence,
  not an allowance for unexplained extra rows. Scope by exact request/transfer
  identities and retain immutable business linkage, unique counts and sums.
- Keep exact 20 private messages, distinct IDs/read evidence, two follows and
  all twenty <=5s host-monotonic samples. No raw balance values or account
  identifiers need be published in this document.

Q15 payout binding/withdrawal/refund and Q19 history-clear are not called by
this dual test. Their ordinary-UI acceptance remains NOT_RUN; do not claim the
registration hook or a notification clear covers them. History-clear, if later
added to the existing workflow, belongs after the twenty-message evidence.
PK changes remain exclusively with the assigned worker.

### Protected execution/cleanup boundary

Host SMS setup really calls the SMS endpoint. Verify development outbox and
all six vendor adapters disabled before requesting codes; a returned dev code
alone is not prior proof of no external SMS. Preserve loopback-only relay,
0600 no-clobber role/token files, short session-bounded TTL, failure cancellation,
VM URLs in child environment only and fixed-category diagnostics. The selected
sources contain no hardcoded full phone, bearer or secret value; referenced
private files were not opened. Replace broad inherited environment with a
reviewed allowlist when the main operator adapts the existing host; do not
print environment or Docker credentials.

Finally only removes run-owned runtime files/ADB forwarding, stops own
processes/relay and revokes its sessions. It does NOT roll back accounts,
rooms, posts or gift ledger, or restore the previous ordinary App installation.
Hard process termination is not guaranteed cleanup. Historical source snapshots
and 9/7 frozen evidence remain untouched. This document is a migration draft,
not permission to run or proof of a live PASS.

This document is the canonical Flutter-side status sheet for the current
checkpoint. It deliberately separates what is implemented from what has been
accepted against a live backend and two Android emulators.

## Status tuple

| Dimension | Canonical status | Meaning |
| --- | --- | --- |
| C-end UI | `UI_SCOPE=COMPLETE_69_PAGE_C_END` | The approved 69 Page IDs have implemented UI and scoped interactions. |
| First-party reads | `FIRST_PARTY_READS=READY` | The F3 live graph can use approved first-party HTTP/read contracts. |
| First-party mutations | `FIRST_PARTY_LIVE_MUTATIONS=READY_FOR_RUN` | The M4 runner now exercises only safe, authoritative first-party writes and recovery reads. A real AVD run is still required. |
| Live AVD acceptance | `LIVE_DUAL_AVD_ACCEPTANCE=PENDING` | A real first-party run on both AVD-A and AVD-B is still required. |
| B7 ops frontend | `C_END_B7_SCOPE=INTENTIONALLY_OUT_OF_SCOPE` | B7 is a backend capability; no operator route is added to the 69-page C-end. |
| Canonical audit review | `VERIFIED` | This is the canonical review state for the B7/C-end scope boundary. |

`UI_SCOPE=COMPLETE_69_PAGE_C_END` must not be read as
`LIVE_DUAL_AVD_ACCEPTANCE=PASS`. A local mock run, a widget/golden run, or a
single AVD screenshot does not close the live gate.

## First-party commerce boundary

`CM-002` has a first-party recharge-catalog read. The catalog response is
server-authoritative and may be rendered in live mode.

Recharge order creation (`CM-003`), payment-channel invocation, and provider
success remain `VENDOR_BLOCKED` and fail closed. An order/status read may still
be used when the first-party endpoint provides it; reading an order is not the
same as creating or paying one.

## M4 first-party mutation acceptance

The live integration test performs a mutation only after it has discovered the
authoritative ID, role, balance, account, or other domain precondition. Each
write uses the repository's idempotent request handling and is followed by an
authoritative recovery read. The current safe probes are:

- daily check-in and a claimable first-party task, with an explicit
  `already_authoritative` result when another AVD has already completed the
  business-day operation;
- one ordinary gift and receipt recovery, using a catalog UUID, an online room
  member, quantity one, and no provider invocation;
- a manual-review withdrawal with a masked, selectable payout account, or an
  explicit precondition block when the account, balance, or real-name status is
  not eligible;
- an eligible refund submission and result recovery, with a rejected-result
  retry only when the backend says retry is allowed;
- room moderation mute/restore, seat up/down compensation, and a PK invitation
  with rejection recovery (or accept/end recovery when an invitation is
  already authoritative);
- private first-party message storage/history recovery and notification
  read/interaction-clear operations.

No route is marked successful from a missing fixture, a UI transition, or an
inferred response. Network, protocol, configuration, and server failures fail
the run; only explicit domain/precondition states are recorded as blocked.
The probes never invoke formal SMS, RTC, IM delivery, payment, push, object
storage, media upload, or native vendor-share providers.

## Formal provider matrix

All six formal vendor capabilities are blocked in this checkpoint:

| Capability | Status | Explicit rule |
| --- | --- | --- |
| SMS | `VENDOR_BLOCKED` | A development Outbox OTP is only a controlled test response; it is not formal SMS delivery. |
| RTC | `VENDOR_BLOCKED` | No provider media join, publication, or live audio success. |
| IM | `VENDOR_BLOCKED` | No provider realtime/private-message session or delivery. |
| PAYMENT | `VENDOR_BLOCKED` | No provider order creation, SDK launch, callback, or success. |
| PUSH | `VENDOR_BLOCKED` | Native notification permission does not imply push delivery. |
| OBJECT_STORAGE | `VENDOR_BLOCKED` | No provider-backed image/media upload or success. |

The `VENDOR_BLOCKED` state is fail-closed: the client shows an explicit
unavailable/recovery state and must not turn a mock or missing adapter into a
success claim.

## Flutter live entry gates

The client-side live path is also fail-closed and is checked before `MainShell`:

| Gate | Client contract |
| --- | --- |
| `AC-002` consent | The app-owned `app-owned-v2` document must be read to its end and checked. It discloses the optional Agora RTC, Tencent Cloud IM, and Alipay App Pay providers, their purposes, and the bounded order, network, device/system, and app-switch data processing. Stored acceptance includes the version; an old or unversioned acceptance is invalid and requires re-consent. |
| `AC-003` development OTP | `developmentCode` is retained or auto-filled only for `local`/`development` environments with `allowsDevelopmentTools`; staging and production discard it. |
| `AC-004` account binding/share | The app-owned `account-vendor-boundary-v1` exclusion contract exposes `SOCIAL_ACCOUNT_BINDING` and `NATIVE_SHARE` as `VENDOR_BLOCKED` with `providerInvocation=false` and `successClaimAllowed=false`. No OAuth/social provider call, native vendor share call, credential collection, or fake success is enabled. |
| `AC-006` real name | Live uses the first-party manual-review contract (`FIRST_PARTY_MANUAL_REVIEW`, `providerInvocation=false`). The app may submit the legal-name/identity-number request to the first-party backend; the backend owns redaction and persistence, and this is not a formal identity-vendor integration. |
| `AC-007` active logins | The ordinary device page requests `GET /app-mini-api/mini/v1/account/sessions?scope=active&pageNum=1&pageSize=20` and validates every page. Each item must have `active=true` and a boolean `current` bound by the backend to the authenticated token family. Multiple login families on one installation remain separate; `deviceId` alone is not current-login authority. Revoked/expired history and contradictory current flags fail closed. `DELETE .../sessions/{sessionId}` retains the token public ID contract but revokes that login family, including rotated successors; the UI re-reads after removal and does not present a failed reload as success. Historical token rows are retained, not deleted. |
| `AC-008` account access | Session restore performs a server-authoritative restrictions and `accountUsable` read. Restricted, unusable, missing, or failed reads stay behind a retry/appeal/sign-out gate. |
| `AC-011` version policy | Mandatory updates block entry. Optional updates offer `稍后`; an unapproved or invalid package opener fails closed and cannot claim installation success. |
| `DS-004` live discovery | Live discovery renders the backend feed/action surface. Local follow and publish injections remain mock-only. |

These checks do not activate a third-party SDK or identity/payment provider.

## Permanent route exclusions

The following legacy commercial routes are historical references only and are
permanently `RETIRED` / `OUT_OF_SCOPE`:

- `/app-api/user/userPackGift` — gift backpack/inventory;
- `/app-api/vip/queryVipInfo` — commercial VIP information;
- `/app-economy-api/pay/ncoin/pay/vip` — commercial VIP purchase.

They must not be reintroduced as C-end routes, page IDs, placeholders, or live
acceptance targets. Guild membership is a separate in-scope capability:
`SC-001`/`SC-002` retain guild membership, applications, and member governance.

## M4 acceptance gate

The authoritative runner is
[`qa/m4-authoritative-live-avd-acceptance.md`](qa/m4-authoritative-live-avd-acceptance.md).
The runner specification is not evidence of a successful run. Until protected
evidence exists for both AVDs on the same candidate SHA, the only valid status
is `LIVE_DUAL_AVD_ACCEPTANCE=PENDING`; do not write live AVD `PASS`.
