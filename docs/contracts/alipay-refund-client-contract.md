# Alipay order refund client contract

This is the minimum authenticated first-party contract consumed by the Flutter
client. It is a status projection and manual-review workflow; it is not a
provider callback and it never authorizes a client-side wallet or gift-coin
write. `providerStatus` is a separate provider observation/readiness value; it
must not be confused with the user-facing refund `status`.

## Eligibility

`GET /app-api/refund/check?orderNo=<exact-order-number>` returns:

```json
{
  "orderNo": "<same exact order number>",
  "eligible": true,
  "reason": "ELIGIBLE",
  "currency": "CASH_CNY",
  "amountMinor": 600,
  "giftCoinAmount": 60,
  "providerStatus": "READY",
  "existingApplicationId": null
}
```

`amountMinor` and `giftCoinAmount` are positive JSON integers. The readiness
value is `READY` when the server can execute the configured Alipay provider and
`VENDOR_BLOCKED` when that adapter is not configured. For an ineligible order,
`eligible` is false and `reason` is a server-owned value such as
`ACTIVE_REFUND_EXISTS`, `REFUND_ALREADY_EXISTS`, or
`GIFT_COIN_ALREADY_CONSUMED`; an existing application reason must include a
canonical UUID `existingApplicationId`. `existingApplicationId` is omitted or
null for all other reasons. The client does not infer eligibility from a local
order list.

## Submit and retry

`POST /app-api/refund/application` accepts only `{ "orderNo", "reason" }` and
requires an authenticated `X-Request-Id`. Its `data` must include the same
`orderNo`, a positive `amountMinor`, `currency: "CASH_CNY"`,
`providerStatus` (`READY` or `VENDOR_BLOCKED` before finance review), `refundId`,
`reason`, `submittedAt`,
`resultMessage`, `completed`, and a status from the table below.

`POST /app-api/refund/repeat` accepts only `{ "refundId", "reason" }` with a
new/replayed authenticated `X-Request-Id`. It is allowed only after a current
authoritative `REJECTED` result. Both writes are idempotent; an ambiguous
response must be recoverable by reading the result before another write.

## Authoritative result

`GET /app-api/refund/result?refundId=<exact-id>` and
`GET /app-api/refund/history?pageNum=&pageSize=` return the same result shape:

```json
{
  "refundId": "<refund-id>",
  "orderNo": "<order-number>",
  "amountMinor": 600,
  "currency": "CASH_CNY",
  "reason": "重复充值",
  "status": "APPROVED",
  "resultMessage": "",
  "submittedAt": "2026-08-27T08:00:00Z",
  "providerStatus": "PENDING",
  "completed": false
}
```

Supported status values and UI meaning:

| Backend status | `completed` | Client state | Recovery |
| --- | ---: | --- | --- |
| `SUBMITTED`, `REVIEWING`, `RESUBMITTED` + `READY`/`SUBMITTED`/`VENDOR_BLOCKED` | `false` | 服务端处理中 | Refresh the result; do not credit locally |
| `APPROVED` + `APPROVED` | `false` | 服务端已审批，尚未确认完成 | Refresh until terminal; do not credit locally |
| `APPROVED` + `PROCESSING`/`PENDING`/`UNKNOWN` | `false` | 厂商结果待核验 | Refresh/reconcile on the server; do not credit locally |
| `COMPLETED` + `REFUNDED` | `true` | 服务端确认退款完成 | Display only; wallet remains backend-owned |
| `REJECTED` + `REJECTED` | `false` | 失败，`resultMessage` required | Show reason and allow `repeat` after user correction |
| `CANCELED` / `CANCELLED` + `CANCELED`/`CANCELLED` | `false` | 不可继续处理 | Refresh/history only; no client mutation |

The client rejects missing or contradictory IDs, amounts, currency, provider
status, timestamps, status/`completed`, and rejection reason. `VENDOR_BLOCKED`
is only a readiness fallback for an unavailable adapter on eligibility or a
pre-review row; approved, rejected, cancelled, and completed rows must carry
a matching concrete provider observation. It never authorizes a client write.
`APPROVED` is not `COMPLETED`; only the latter is terminal. No refund status
causes Flutter to change a balance—the next wallet/ledger read remains
authoritative.
