# Core-eight native follow-up — 2026-09-23

This follows `e16582f` on the existing UI refinement branch/PR27. It is not a new production deployment or a claim that the entire release is ready.

## Findings and repairs

The ordinary Android package was installed on the preserved API36/API35 emulators, at 390×844/1.0 and 360×800/1.3. Backend remained the existing `ae9e37f` ordinary RC on loopback 28080; Agora, Tencent IM, Alipay, IAP, and QA-console flags were false. The main reviewer owned device control; the independent patch worker used gpt-6-sol/high.

| Before | After | Why |
| --- | --- | --- |
| Live Discovery's own publish FAB overlapped the MainShell bottom bar. | `846ca6a`: suppress that FAB only when embedded; retain the top publish route and standalone FAB. | Native screenshots exposed an overlap that the standalone page golden did not cover. Native revisit confirmed top publishing and bottom navigation remain reachable. |
| The private-chat send button's inherited white Material obscured its gradient. | `7067faa`: local transparent Material background, circular shape, explicit enabled/disabled icon colors. | Preserve the actual 48×48 control and all send conditions while restoring a clear enabled state. Four targeted pixel/behavior cases and three existing cases passed. |
| Gift quantity/send controls were 38dp high; refresh/recharge hit regions were also undersized. | `251e30d`: all four actual controls have a 48dp minimum hit area. | Three genuine size failures became passes; edge taps exercise the added area. Nine existing authority, balance, and unknown-result cases passed. The short 360×640/1.3 modal still shows a full first row. |

No repository/API/permission/accounting logic, dependency lock, package identity, or production deployment target was changed by these repairs.

## Native business evidence and limits

On installed `846ca6a`, preserved UID145 and UID243 each sent one private message through the real page. The peer received the reply while remaining in chat; unread/read UI and keyboard return were observed. Both devices also displayed `CORE8-0923-public-A` in room169/code313179. This proves ordinary first-party retention/automatic compensation visibility, not Tencent IM or a measured two-second SLA.

Microphone request83 was submitted at 05:27:25Z and the reviewer clicked approval at 05:28:33Z, after its one-minute deadline. Its expired projection and absence of a seat were not treated as a product defect or as a pass. A newly coordinated request84 was submitted at 05:36:07.698571Z and resolved at 05:36:36.952722Z, before 05:37:07.698571Z. Read-only authority showed APPROVED/assigned seat2/occupant243. Both native room pages displayed the occupant, and the member's normal “主动下麦” cleared seat2 on both pages. No TTL/guard/DB fixture was changed; this is seat authority, not a real audio test.

Gift controls were checked with the actual current on-mic recipient, including quantity1→10 and total10→100 without submitting a gift. Decoration showed expired history with 0 owned/0 equipped and a working image preview. Those observations do not prove a new purchase, a new expiry cycle, or partial-result recovery on this native build.

## Platform/visual verification

The post-fix local golden comparison produced exactly the anticipated three failures: `m3_3_private_chat`, `m3_3_all/ms-002`, and `m3_3_gift`; the other 62 test cases passed. The reviewer opened the before/after/diff images: changes were confined to the send button and gift footer. macOS and Linux baselines remain separate; comparison thresholds and the golden hosts were not relaxed. Generation is not counted as comparison approval.

Xcode license acceptance was completed by the user. Both ordinary Android and iOS Simulator packages built and installed successfully. A local Xcode27 simulator-only arm64/minimum15 configuration worked without changing the production iOS13 minimum. iOS SE3 runs the candidate, but Device Hub's AX lookup times out with `-10005`; `jev-use` therefore has no usable native controls. iOS core-eight navigation, keyboard, and gestures remain unverified. Simulator screenshots alone are not those tests.

Local evidence is under `artifacts/ui-audit-20260921/core8-refinement-20260923/device-acceptance-20260923` in the ny workspace. It contains exact build/install hashes, original screenshots/XML, chronological ADB actions, RED/GREEN logs, visual comparisons, and separate limitations. Final package and CI receipts must bind their actual source SHA, not inherit `e16582f` results.
