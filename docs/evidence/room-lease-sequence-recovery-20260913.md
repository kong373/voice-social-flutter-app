# Room lease sequence recovery evidence

- Base: `c9de3cc44476`.
- RED: `reconnect adopts a committed heartbeat lease before the next renewal`
  failed before the fix because the reconnect snapshot still exposed lease
  sequence `0` instead of the server-confirmed sequence `1`.
- GREEN: reconnect now accepts only a valid same-session monotonic lease. A
  newer sequence is adopted with the existing deadline anchor, the heartbeat
  request ID is rotated, and an older in-flight renewal cannot overwrite it.
  Same-sequence confirmations do not extend expiry; regressed leases end the
  local session.
- RED/GREEN log anchors: `test/room_lease_controller_test.dart`, covering
  `reconnect adopts a committed heartbeat lease before the next renewal`,
  `same-sequence reconnect confirmation cannot extend the old deadline`,
  `regressed reconnect lease ends the local session`, and
  `late heartbeat error 40101/40936/40937 still revokes the current lease`.
  The pre-fix REDs were the stale sequence `0` assertion and the stale-error
  result remaining `joined`; the final controller raw line was
  `00:00 +38: All tests passed!`.
- Focused verification: `flutter test --no-pub
  test/room_lease_controller_test.dart` — raw result
  `00:00 +38: All tests passed!`; repository contract raw result was
  `00:00 +53: All tests passed!`.
- Scope boundary: this is a client-side recovery fix only. It does not prove
  the live incident root cause; HTTP auth-refresh and heartbeat evidence are
  still required for that conclusion.
