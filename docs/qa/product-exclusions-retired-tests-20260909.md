# REMOVED_BY_PRODUCT test scope

Only feature-specific positive tests below were retired. Mixed tests retain guild, relationship, privacy, support and HTTP error assertions. Replacement coverage: product_exclusions_test.dart and product_exclusions_repository_test.dart.

- backend_community_repository_contract_test.dart: guild sign checks status and recovers a committed write after lost response
- backend_community_repository_contract_test.dart: community cp contracts parse state and preserve numeric ids
- backend_community_repository_contract_test.dart: community CP writes reject mismatched identity and non-terminal state
- backend_community_repository_contract_test.dart: community ends CP relation through the first-party mutation route
- backend_community_repository_contract_test.dart: community rejects unconfirmed or mismatched CP termination
- backend_community_repository_contract_test.dart: CP relation requires server createdAt
- backend_community_repository_contract_test.dart: community guardian and fan snapshot fans out four GET contracts
- backend_community_repository_contract_test.dart: community guardian and task mutations preserve body and follow-up reads
- backend_community_repository_contract_test.dart: community CP eligibility rejects inconsistent b709 reason
- backend_community_repository_contract_test.dart: activity without status trusts the first-party active-row invariant
- backend_community_repository_contract_test.dart: activity status is server-authoritative and unknown status fails closed
- backend_community_repository_contract_test.dart: concurrent CP requests for one target coalesce without swallowing 409
- backend_community_repository_contract_test.dart: community maps exact b709 guardian and fans payloads
- backend_community_repository_contract_test.dart: community guardian catalog rejects missing b709 level identity
- backend_community_repository_contract_test.dart: community fans relation rejects divergent b709 join aliases
- backend_community_repository_contract_test.dart: community exact b709 task payload rejects alias divergence
- backend_community_repository_contract_test.dart: task description aliases may differ from the title when they agree
- backend_community_repository_contract_test.dart: task description aliases are both required
- backend_community_repository_contract_test.dart: task description aliases must agree
- backend_community_repository_contract_test.dart: community CP writes reject an explicit provider invocation
- backend_social_repository_contract_test.dart: concurrent identical friend requests are single-flight
- backend_social_repository_contract_test.dart: friend request workflow parses pages and preserves server conflicts
- backend_social_repository_contract_test.dart: friend request pagination stops at the 100-page safety cap
- backend_social_repository_contract_test.dart: friend request send uses the first-party endpoint and validates the response
- backend_social_repository_contract_test.dart: friend request records require server id, time, and known status
- backend_social_repository_contract_test.dart: friend request user identities must be positive integers in the current view
- backend_social_repository_contract_test.dart: friend request requester, target, and current-user aliases must agree
- backend_social_repository_contract_test.dart: friend request parsing fails when the current view has no user id
- backend_social_repository_contract_test.dart: friend request send fails closed for empty response and preserves HTTP errors
- community_write_reliability_test.dart: guild sign keeps one id across 40901 and 40902 on one business day
- community_write_reliability_test.dart: guild sign trusts the backend business date over the device date
- community_write_reliability_test.dart: guild sign rotates a retained id after the local business date changes
- community_write_reliability_test.dart: guild sign rejects a stale signDate response
- community_write_reliability_test.dart: daily check-in rejects a stale businessDate response
- community_write_reliability_test.dart: daily check-in trusts the backend business date over the device date
- community_write_reliability_test.dart: daily check-in keeps its id across unknown conflicts but not across dates
- community_repository_test.dart: CP, guardian, task, and activity state remains authoritative

- first_party_live_mutation_coverage_test.dart: task claim sends first-party idempotency and refreshes authoritative center
