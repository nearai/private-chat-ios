# Answer Thread Failure Card Notes

Date: 2026-06-12

## Goal

Move failed answer threads closer to the supplied Answer reference: the thread should feel like a real product surface with clear route state and recovery choices, not a raw backend sentence plus a tiny retry row.

## What Changed

`NEARPrivateChat/Features/Chat/ChatMessageViews.swift`

- Failed assistant messages now render through `AssistantFailureRecoveryCard`.
- Private route rate-limit failures are summarized as:
  - `Private route needs a moment`
  - Recovery copy that explains the current-session route rejection without exposing the raw backend sentence as the whole answer.
- The card shows:
  - route/model chip
  - primary `Retry private`
  - secondary `Add Cloud key` or `Use Cloud once` when the failure is a private-route rate-limit class.
- Successful answers and streaming answers are unchanged.

## Tests

Focused simulator tests passed:

- `testAssistantFailurePresentationSummarizesPrivateRouteRateLimit`
- `testPrivateRouteBusyRetriesSameRouteOnceBeforeBreaker`
- `testPrivateRouteRateLimitDoesNotAutoRetrySameRoute`

XcodeBuildMCP result:

- Status: `SUCCEEDED`
- Passed: 3
- Failed: 0
- Result bundle: `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T17-53-15-163Z_pid37699_90ec0036.xcresult`

Build/install/launch also succeeded after the patch.

## Evidence

Before screenshot:

- `review-artifacts/screenshots/2026-06-12-answer-thread-failure-card/before-raw-private-route-failure.jpg`

After-capture note:

- The app built and launched after the patch, but the XcodeBuildMCP semantic snapshot bridge returned no tappable refs after relaunch, so this pass could not reopen the failed thread for a visual after screenshot in the same turn. The presentation path is covered by focused tests and the build.

## Remaining Work

- Reopen the failed answer thread once simulator tapping is available again and capture the after screenshot.
- Apply the same Answer-reference polish to successful answer threads: source chips, proof/footer spacing, and answer body rhythm.
- Continue into briefing detail parity and hostile widget workflow tests.
