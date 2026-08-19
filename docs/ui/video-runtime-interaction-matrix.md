# Runtime interaction evidence matrix

| Scenario | Expected runtime behavior |
|---|---|
| Home normal | Light sky/lilac lobby, mixed card sizes, categories, active room posters, fixed root nav |
| Enter room | Direct route to RM-004; dark immersive room; fixed 4×2 eight seats |
| Room keyboard | Keyboard opens without replacing the room route; header and seats remain in context |
| Gift | Half-height in-room sheet; recipient, category, selected gift, balance, quantity and send remain in room context |
| Recharge from gift | Nested recharge context returns to the same gift selection |
| Gift result | Non-blocking animation overlay; room controls remain available |
| More tools | In-room bottom sheet; immediate tools do not navigate to a full page |
| Minimize room | Room controller remains active; cross-tab pill is shown |
| Restore room | Tapping the pill reopens the same room controller and state |
| Leave room | Explicit confirmation; session is ended and pill disappears |
| Weak network | Core room skeleton remains visible; no fake message history |
| Provider blocked | RTC/IM/payment actions fail closed and never show false success |
