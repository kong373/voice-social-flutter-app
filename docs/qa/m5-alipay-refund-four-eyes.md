# M5 Alipay sandbox Finance four-eyes refund acceptance

`tool/qa/m5_alipay_refund_four_eyes.py` is a QA-only, opt-in harness for the
refund lane. It is run only after the existing M5 runner has created and
authenticated a successful Alipay sandbox order. The refund harness does not
discover an order, user, provider identifier, amount, or refund identifier;
the protected runner/secret store must inject the exact order reference.

## Safety contract

The harness performs this bounded sequence:

1. Verify the injected order is `SUCCEEDED`, `TRADE_SUCCESS`/`TRADE_FINISHED`,
   `alipay-sandbox`, and has not required a provider call for the read.
2. Capture the aggregate ledger baseline before the user submits a refund.
3. Submit the user's refund application.
4. Approve it with a different Finance bearer.
5. Execute it with a third bearer, using the same refund public id as the
   provider `out_request_no`.
6. Replay execute with the same request id. If the result is pending/unknown,
   reconcile with the same refund id and replay that request id as well.
7. Verify the terminal first-party result and collect aggregate DB evidence.

Provider execution is blocked unless all three values below are present. The
two confirmation strings are intentionally different and must be supplied by
the protected operator workflow; they are never inferred from a payment lane.

```text
QA_M5_REFUND_ALLOW_PROVIDER=true
QA_M5_REFUND_CONFIRMATION=I_UNDERSTAND_ALIPAY_SANDBOX_REFUND
QA_M5_REFUND_CONFIRMATION_2=I_UNDERSTAND_ALIPAY_SANDBOX_REFUND_SECOND_OPERATOR
```

Without that exact gate, `--run` emits only a fixed `BLOCKED` category and
exits 3. `--self-test` and all offline behavior tests never open a socket,
start Docker, or call Alipay.

## Protected inputs

The caller must provide these values through a protected environment or
one-shot secret-manager relay. Do not put them in Flutter arguments, shell
history, logs, screenshots, test fixtures, or committed files.

```text
QA_M5_REFUND_BASE_URL=https://<first-party-backend-host>/
QA_M5_REFUND_ORDER_NO=<the exact completed success-lane order>
QA_M5_REFUND_USER_BEARER=<customer bearer>
QA_M5_REFUND_REVIEWER_BEARER=<Finance reviewer bearer>
QA_M5_REFUND_EXECUTOR_BEARER=<different Finance executor bearer>
QA_M5_REFUND_REASON=<1-256 printable characters>
QA_M5_REFUND_RUN_ID=m5-refund-<fresh-run>
QA_M5_REFUND_MYSQL_CONTAINER=<serving MySQL container>
QA_M5_REFUND_LEDGER_STATE_DIR=/secure/private/m5-refund-state
```

The three bearer values must be distinct. The state directory must already
exist with mode `0700` or narrower. `QA_M5_REFUND_ARTIFACT_DIR` is optional,
but if supplied it must also be a new private directory. The optional
`QA_M5_REFUND_ALLOW_INSECURE_HTTP=true` is accepted only for the controlled
host-loopback names `127.0.0.1`, `localhost`, or `::1`; HTTPS is the default.
The Android-only `10.0.2.2` gateway is deliberately rejected because this
orchestrator runs on the Mac host and carries bearer credentials.

The Docker helper reads MySQL credentials only from the serving container's
`MYSQL_DATABASE` and one of `MYSQL_PASSWORD`, `MYSQL_APP_PASSWORD`, or
`MYSQL_ROOT_PASSWORD`. It receives order/refund references over stdin, never
on the Docker command line. Its SQL returns only fixed schema markers and
aggregate counts. The execute and reconcile counts each require the selected
refund row's exact public id in `response_json`, the matching Finance actor,
and the backend's exact SHA-256 request fingerprint (`queryOnly=false/true`);
the helper never prints those values.

## Explicit M5 runner invocation

Load the normal protected M5 inputs first, then run the tracked runner's
success payment lane. This step is the source of the order reference; it must
finish with the runner's successful provider result before the refund lane is
started.

```bash
# All ordinary QA_M5_* inputs are loaded by the protected runner workflow.
env \
  QA_M5_ALLOW_EXTERNAL_PAYMENT=true \
  QA_M5_PAYMENT_CONFIRMATION=I_UNDERSTAND_SANDBOX_PAYMENT \
  QA_M5_ALIPAY_SCENARIO=success \
  QA_M5_SUCCESS_CONFIRMATION=I_UNDERSTAND_SANDBOX_SUCCESS_PAYMENT \
  tool/qa/run_m5_vendor_live_avd.sh
```

After that command returns a successful M5 result, inject the exact order
reference and the three role bearers from the protected handoff, create the
private ledger state directory, and invoke the refund orchestrator. The
orchestrator performs no order lookup beyond the exact supplied reference and
does not read an artifact to discover one.

```bash
umask 077
mkdir -m 700 /secure/private/m5-refund-state
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=tool/qa \
  python3 tool/qa/m5_alipay_refund_four_eyes.py --run
```

The process output and optional artifact contain only status enums, booleans,
aggregate counts, and SHA-256 hashes of the two protected references. They do
not contain order/refund/user/provider identifiers, secrets, amounts, phone
numbers, or provider payloads. A terminal execute result intentionally skips
reconcile; a pending/unknown result requires reconcile and the same refund id.
After the explicit provider gate has opened, any failed run reports
`providerInvocation=UNKNOWN`; a local validation or transport failure cannot
prove that Alipay was not reached. Only the default pre-confirmation block may
report `providerInvocation=false`.

## Local validation (provider-free)

Run these checks from the Flutter checkout. They do not need backend, MySQL,
Android, credentials, or network access.

```bash
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=tool/qa \
  python3 tool/qa/m5_alipay_refund_four_eyes.py --self-test
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=tool/qa \
  python3 tool/qa/m5_alipay_refund_ledger_evidence.py --self-test
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=tool/qa \
  python3 -m unittest \
    tool/qa/m5_alipay_refund_four_eyes_test.py \
    tool/qa/m5_alipay_refund_ledger_evidence_test.py
python3 -m py_compile \
  tool/qa/m5_alipay_refund_four_eyes.py \
  tool/qa/m5_alipay_refund_ledger_evidence.py \
  tool/qa/m5_alipay_refund_four_eyes_test.py \
  tool/qa/m5_alipay_refund_ledger_evidence_test.py
bash -n tool/qa/run_m5_vendor_live_avd.sh
```

The behavior tests cover the default double-confirmation block, response
redaction, completed-order gating, user application, distinct review and
execute actors, same-id execute/reconcile replays, terminal-vs-pending
handling, strict separate ledger idempotency markers, schema failure, and
the exact fingerprint association. No vendor call is part of these checks.
