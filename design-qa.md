# M3.3 Video Runtime UI Design QA

## Source and scope

- Reference video capture: `/Users/kongzheng/Downloads/cc7361ff-cd00-4871-8367-5caa1929310f.mp4` (the original MP4 is no longer local; the audited extracted frames remain under `artifacts/m3-3/video-reference-cc7361ff/`)
- Reference SHA-256: `2d2a350dc1c63c59d764be2e4bb801086d79281c444725a4788c324a07112221`
- Implementation viewport: `390x844` logical pixels at `1.0x`
- Secondary viewport gate: `360x800` at `1.3x` text scale
- Source frames are `448x960`; Flutter goldens are `390x844` at device-pixel ratio `1.0`. The nearly identical portrait aspect ratios were compared as content-only phone surfaces; source status-bar chrome was excluded from fidelity findings.
- Product boundary: preserve the approved 69-page scope, the four root tabs, and the exact eight-seat room model. Brand-specific source assets, memberships, paid status tiers, and gift-inventory capabilities are deliberately excluded.

## Same-input comparisons

Each comparison places a scaled source-video frame on the left and the real Flutter-rendered implementation on the right.

| State | Source frame | Flutter golden | Combined comparison |
| --- | --- | --- | --- |
| Lobby | `frame-7s.png` | `test/goldens/m3_3_home_390x844.png` | `/Users/kongzheng/Documents/ny/artifacts/m3-3/design-qa/home-comparison.png` |
| Eight-seat room | `frame-10s.png` | `test/goldens/m3_3_room_390x844.png` | `/Users/kongzheng/Documents/ny/artifacts/m3-3/design-qa/room-comparison.png` |
| Expression sheet | `frame-22s.png` | `test/goldens/m3_3_expression_390x844.png` | `/Users/kongzheng/Documents/ny/artifacts/m3-3/design-qa/expression-comparison.png` |
| In-room gift sheet | `frame-28s.png` | `test/goldens/m3_3_gift_390x844.png` | Compared together in the current QA run after removing the unsupported inventory tab |
| Discovery | `frame-52s.png` | `test/goldens/m3_3_discovery_390x844.png` | Compared together in the current QA run; hierarchy and feed density checked against the source state |
| Messages | `frame-55s.png` | `test/goldens/m3_3_messages_390x844.png` | Compared together in the current QA run; shortcuts, recent-message hierarchy, and fixed navigation checked |
| Account | `frame-58s.png` | `test/goldens/m3_3_account_390x844.png` | Compared together in the current QA run |
| Decoration center | `frame-61s.png` as a collection-page visual-language reference | `test/goldens/m3_3_decoration_390x844.png` | Consistency check only; the source is not the same product state and is not claimed as a 1:1 match |
| Dynamic detail | `frame-52s.png` as the discovery-feed visual-language reference | `test/goldens/m3_3_dynamic_detail_390x844.png` | Same-input comparison of the light social surface, post hierarchy, actions, comments, and fixed composer |
| Private chat | `frame-55s.png` as the message-area visual-language reference | `test/goldens/m3_3_private_chat_390x844.png` | Same-input comparison of the light social background, compact header, conversation hierarchy, and fixed composer |
| Notifications | `frame-55s.png` | `test/goldens/m3_3_notifications_390x844.png` | Same-input comparison of notification categories, unread indicators, card density, and empty-space rhythm |
| Public profile | `frame-64s.png` as the account/profile visual-language reference | `test/goldens/m3_3_public_profile_390x844.png` | Same-input comparison of avatar, social counters, primary relationship actions, room entry, and reporting |
| Room members | `frame-43s.png` as the in-room tools visual-language reference | `test/goldens/m3_3_room_members_390x844.png` | Same-input comparison of the deep-purple layer, segmented filters, avatar treatment, and member density |
| Room management | `frame-43s.png` | `test/goldens/m3_3_room_management_390x844.png` | Same-input comparison of the dark tool surface, role badges, member actions, and management tabs |

The complete page inventory also has area-level comparison boards. These boards
place a normalized `390x844` source-video state beside three real Flutter page
captures. Deep pages do not exist as exact states in the source recording, so
these boards are used for visual-language consistency rather than false
pixel-for-pixel claims.

| Area | Combined comparison |
| --- | --- |
| Account and profile | `/Users/kongzheng/Documents/ny/artifacts/m3-3/design-qa/full-page-areas/account-area-comparison.png` |
| Discovery and dynamic | `/Users/kongzheng/Documents/ny/artifacts/m3-3/design-qa/full-page-areas/discovery-area-comparison.png` |
| Room and PK | `/Users/kongzheng/Documents/ny/artifacts/m3-3/design-qa/full-page-areas/room-area-comparison.png` |
| Messages | `/Users/kongzheng/Documents/ny/artifacts/m3-3/design-qa/full-page-areas/messaging-area-comparison.png` |
| Wallet, recharge, and decoration | `/Users/kongzheng/Documents/ny/artifacts/m3-3/design-qa/full-page-areas/commerce-area-comparison.png` |

All 69 rendered pages are additionally collected by area under
`/Users/kongzheng/Documents/ny/artifacts/m3-3/full-page-visual/`.

## Visual verdict

- P0: none.
- P1: none.
- P2: none.
- P3: the source recording includes its own status-bar chrome, brand identity, copyrighted artwork, and unsupported feature entries. The implementation intentionally uses original assets and only approved product capabilities.
- Complete inventory: all `69` manifest pages now use the light social or
  immersive room surface appropriate to their product area. No legacy bare
  scaffold remains as the visible page background.
- Lobby: matched the airy blue-lilac atmosphere, dense featured mosaic, activity strip, social finder panel, two-column visual room cards, and compact fixed navigation.
- Room: matched the immersive dark-purple hierarchy, compact host header, two announcement strips, fixed `4x2` mic-seat grid, conversation area, composer, and compact action dock.
- Expression: matched the room-preserving bottom-sheet behavior and tabbed reaction/sticker selection, using original portrait reactions and gift artwork instead of copied source stickers.
- Gift: matched the room-preserving dark sheet, recipient selector, campaign banner, category row, `4`-column asset grid, balance, quantity selector, and primary send action. The source inventory tab is intentionally absent under the approved product boundary.
- Discovery: preserves the source's airy social-feed hierarchy with top tabs, a compact campaign surface, avatar-led posts, large media, social actions, and fixed root navigation. All imagery is original project-owned artwork.
- Messages: preserves the source's light social surface, compact top tabs, prominent notification shortcuts, recent-conversation hierarchy, unread state, and fixed root navigation; unsupported source shortcuts are not fabricated.
- Account: preserves the reference hierarchy of profile, four social counters, a compact feature banner, three primary entries, recent rooms, service tools, and fixed root navigation. The banner now promotes only in-scope appearance customization.
- Decoration center: uses the account surface, established blue-lilac palette, pill filters, and clear owned/equipped states. It contains no membership status, subscription CTA, privilege copy, or gift inventory.
- Dynamic detail and private chat: use the same airy social background as the root surfaces, keep content readable above a fixed composer, and preserve repository-backed comment/message actions.
- Notifications and public profile: use compact white cards, explicit unread/relationship state, project-owned avatars, and working target routes without inventing a vendor result.
- Room members and management: retain the room's deep-purple visual hierarchy, readable role/state badges, dense but touch-safe rows, and real member/seat actions.
- Cropping, spacing, radii, borders, text hierarchy, and asset fit were checked in the combined comparisons. No visible overflow or broken glyph remains in the approved states.

## Required fidelity surfaces

- Fonts and typography: Chinese app-bar titles, filter labels, status copy, and action buttons render without missing glyphs; hierarchy stays legible at `390x844` and `1.3x` text scale.
- Spacing and layout rhythm: account cards, decoration filters, three decoration rows, and the gift grid preserve safe margins and do not cover persistent navigation or actions.
- Colors and tokens: account and decoration use the existing light blue-lilac social tokens; the room and gift sheet retain the established immersive purple room tokens.
- Image quality: original project-owned avatars, room covers, backgrounds, and gift art remain sharp and correctly cropped. No source brand artwork was copied.
- Copy and content: visible membership and gift-inventory language is removed; decoration copy refers only to appearance assets and exact owned/equipped state.

## Comparison history

- First post-change capture found a P2 app-bar surface problem and unreadable CJK labels in the decoration title/action buttons.
- Fix: moved the whole decoration scaffold onto `SocialSkySurface` and applied the app text styles explicitly to the app-bar title and primary actions.
- Post-fix evidence: `test/goldens/m3_3_decoration_390x844.png`; title and `卸下 / 购买 / 穿戴` actions are legible, with no remaining P0/P1/P2 finding.
- Conversation rows use stable `HH:mm / 昨天 / M/D` calendar labels rather than a minute-by-minute relative clock, so visual fixtures do not cross an hourly boundary during a full test run. The comparator still permits only `0.02%` renderer-level pixel noise.
- The secondary-page pass exposed a hidden Material/Ink layering issue in two relationship lists. `SocialCard` now places `Material` inside the shadow container, so ListTile ink feedback remains visible and all four 69-page viewport suites pass.
- Golden fixtures now pin the mock clock and load separate regular/bold CJK faces; app-bar titles and primary button labels render deterministically without missing glyphs.
- The 69-page contact-sheet pass exposed a P2 personal-center isolation issue:
  `US-001` inherited a dark host background when opened outside the root shell.
  `PersonalCenterPage` now owns `SocialSkySurface`; the revised US contact
  sheet and account area board show the corrected light social surface.
- The normalized room comparison exposed a P1 contrast issue in `RM-004` and
  `RM-005`: the ordinary room inherited the light parent theme before its
  title, topic, public-screen labels, composer, and actions were constructed.
  `RoomPage` now wraps its stateful content in `AppTheme.room`. The
  post-fix `RM-004`/`RM-005` captures use white/secondary room text and the
  complete 69-page golden suite passes after the fix.

## Interaction verdict

- Root navigation remains exactly `首页 / 发现 / 消息 / 我的`.
- Home category tabs filter the visible rooms, `换一批` rotates the result, ranking opens the existing ranking route, and topic/activity cards enter real room or topic flows.
- Discovery tabs filter the feed, follow and like states toggle locally, text publishing enters the existing repository-backed form, and share performs copy or message-center navigation without claiming a vendor share success.
- Dynamic detail supports refresh, like, reply selection, reply cancellation, validation, and repository-backed comment submission; the list and count update immediately after a successful submit.
- Message shortcuts open the correct notification, relation, or help route; real repository conversations open their exact private-chat route.
- Private chat restores repository history, opens the public profile/report routes, sends through the configured repository, and keeps the composer clear of the keyboard at 1.3x text scale. Read-only live mode remains explicit when vendor IM send is unavailable.
- Profile, appearance banner, decoration card, service tools, and recent-room cards are actionable; recent rooms restore a real room route.
- Public profile follow, private-chat, blacklist, active-room, and report actions are connected; private chat no longer stops at an unconditional SDK placeholder.
- The account appearance entries open the pure `DecorationPage`; its category filters, purchase confirmation, equip, and unequip states are interactive and repository-backed.
- The room always exposes exactly eight mic seats; no extra host seat is introduced.
- Host follow state toggles visibly. The composer keeps the room visible, exposes contextual prompts while focused, and accepts a selected original reaction or sticker token.
- Members, gift, and more-tools actions open working routes or bottom sheets.
- Member filters, profile/chat/report actions, room role/state badges, management tabs, member menus, and seat controls remain real interactive surfaces.
- Gift campaign details, target, category, gift, quantity, recharge-return, send, and celebration states are interactive. No inventory route or tab remains.
- A room can be minimized, remains present across root tabs, and can be restored or closed.
- Live mode remains fail-closed: it does not fabricate message history or enable unavailable vendor integrations.
- Deep interaction verification additionally completes system-permission
  changes, real-name submission, account appeal, youth-mode activation,
  recharge selection and confirmed order submission, guardian purchase,
  daily check-in, and ordinary-room PK invitation.
- Runtime product code contains no membership or gift-backpack copy or route.
  Those words occur only in negative tests that assert they are absent.

## Verification

- Flutter SDK: `3.44.7`
- Dart SDK: `3.12.2`
- Candidate Dart format: pass (`88` changed/new Dart files checked, `0` rewritten)
- `flutter analyze`: pass, zero issues
- `flutter test --concurrency=1 --timeout=60s`: `179/179` pass
- Exact-view visual coverage: all 69 pages pass at `390x844`, `360x800`, and both viewports at `1.3x` text scale
- Visual golden coverage: `69/69` page inventory states plus `14` source-aligned/key interaction states pass at `390x844`
- Android debug APK: pass, `162447548` bytes; package `com.kong373.voice_social_app`, version `0.6.0+6`, min SDK `24`, target SDK `36`, APK Signature Scheme v2 verified
- APK: `/Users/kongzheng/Documents/ny/artifacts/m3-3/apk/voice-social-m3-3-all-pages-ui-debug.apk`
- APK SHA-256: `cb24ff5ca5586f633a0c5bed24c428a43962d962a7c8430d2a4257cca03bbb5c`
- Runtime note: no device execution is claimed in this closure. This pass includes Android compilation, APK integrity, widget interaction, exact-viewport, and visual-golden verification. Physical-device acceptance remains the next gate.

final result: passed
