# Private Route Rate-Limit Fix Notes

Date: 2026-06-12

## What Changed

- Explicit private-route rate-limit signals now trip the route breaker without an automatic same-route retry.
- Genuinely busy route signals can still receive the single same-route retry.
- Breaker notice copy now keeps explicit rate limits separate from genuinely busy route failures.
- This prevents one user send from becoming two immediate private `/v1/responses` attempts when the backend says the current session is rate-limited.

## Code

- `NEARPrivateChat/Core/Routing/RouteHealthMonitor.swift`
  - Added explicit rate-limit classification.
  - Kept busy-route retry classification separate from quota/rate-limit classification.
  - Stores whether the latest breaker trip was explicit rate-limit vs busy so the user-facing notice is honest.
- `NEARPrivateChatTests/Routing/RouteHealthTests.swift`
  - Added classifier and notice coverage for quota/rate-limit vs transient busy.
- `NEARPrivateChatTests/Streaming/StreamingTests.swift`
  - Updated the busy retry test.
  - Added a rate-limit test proving a queued second response is not consumed.

## Validation

Focused simulator tests passed:

- `testExplicitRateLimitFailureDetectsQuotaSignals`
- `testTransientBusyFailureExcludesAuthAccessAndExplicitRateLimits`
- `testBusyNoticeDoesNotCallBusyRouteRateLimited`
- `testPrivateRouteBusyRetriesSameRouteOnceBeforeBreaker`
- `testPrivateRouteRateLimitDoesNotAutoRetrySameRoute`
- `testAssistantFailurePresentationSummarizesPrivateRouteRateLimit`

XcodeBuildMCP result:

- Status: `SUCCEEDED`
- Passed: 6
- Failed: 0
- Result bundle: `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T17-58-44-246Z_pid37699_9698796e.xcresult`

Build/install/launch also succeeded:

- App: `/Users/abhishekvaidyanathan/Documents/Playground/NEARPrivateChatIOS/build/DD/Build/Products/Debug-iphonesimulator/NEARPrivateChat.app`
- Simulator: `FF55DF8F-6AE7-4F18-8197-1B59D1AB3E55`
- Build log: `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T17-59-48-950Z_pid37699_7a934947.log`

Screenshot evidence:

- `review-artifacts/screenshots/2026-06-12-private-route-rate-limit-fix/home-after-no-auto-rate-limit-retry.jpg`

## Remaining External Blocker

This does not fix OVH/backend route capacity or quota. It removes a client-side retry amplification. The server-side AASA endpoint also remains wrong as of the live check: `https://private.near.ai/.well-known/apple-app-site-association` returns HTML, not AASA JSON.
