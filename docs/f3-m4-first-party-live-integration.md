# F3/M4 first-party live integration status

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
| `AC-002` consent | The app-owned `app-owned-v2` document must be read to its end and checked. Stored acceptance includes the version; an old `accepted` value is invalid. The payment section discloses the optional Alipay App Pay SDK and its order, network, device, and app-switch processing boundary. |
| `AC-003` development OTP | `developmentCode` is retained or auto-filled only for `local`/`development` environments with `allowsDevelopmentTools`; staging and production discard it. |
| `AC-004` account binding/share | The app-owned `account-vendor-boundary-v1` exclusion contract exposes `SOCIAL_ACCOUNT_BINDING` and `NATIVE_SHARE` as `VENDOR_BLOCKED` with `providerInvocation=false` and `successClaimAllowed=false`. No OAuth/social provider call, native vendor share call, credential collection, or fake success is enabled. |
| `AC-006` real name | Live uses the first-party manual-review contract (`FIRST_PARTY_MANUAL_REVIEW`, `providerInvocation=false`). The app may submit the legal-name/identity-number request to the first-party backend; the backend owns redaction and persistence, and this is not a formal identity-vendor integration. |
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
