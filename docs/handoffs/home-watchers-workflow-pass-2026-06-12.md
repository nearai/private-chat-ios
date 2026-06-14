# Home Watchers Workflow Pass

Date: 2026-06-12

## What Changed

- Added explicit empty-state actions on the Home feed:
  - Briefings -> stages a daily AI news digest draft.
  - Watchers -> stages a Rolex market watcher draft.
  - Chats/All -> starts a private chat.
- Tightened recurring briefing parsing so prompts like “Create a daily AI news digest every morning at 8am with sources…” produce a clean `AI news digest` briefing title while preserving the full prompt.
- Tightened open-ended tracker parsing so extra instruction sentences do not leak into tracker titles/confirmations.
  - Bad before: `Rolex GMT-Master II . Use web search, lead with`
  - Fixed future output: `Rolex GMT-Master II`
- Simplified the Home Watchers staged draft so it does not duplicate model-routing instructions already added by the tracker factory.

## Hostile Workflow Coverage

Focused simulator tests passed:

- `testHardRecurringWorkflowPromptsBecomeActionableTrackers`
- `testSendDraftCreatesHardRecurringWorkflowWithoutPrivateRoute`
- `testQuickIntentParsesOpenEndedTracker`
- `testQuickIntentParsesGenericRecurringAgentTracker`
- `testSendDraftCreateTrackerInvokesCallbackWithoutStreaming`

Result bundle:

- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T19-14-54-116Z_pid37699_6fd613a1.xcresult`

Build/install/launch passed:

- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T19-18-00-987Z_pid37699_7fccdd55.log`

## Screenshot Evidence

- `review-artifacts/screenshots/2026-06-12-goal-continuation/home-current-streams.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation/answer-failure-card-current.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation/watchers-empty-draft-cta.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation/watcher-draft-staged-chat.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation/watchers-populated-rolex-card.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation/watcher-thread-detail-rolex.jpg`

## Remaining Gaps

- The overall Home visual direction is closer to the supplied Streams reference, but the All feed still has older chat rows from pre-fix testing that can look messy in screenshots.
- The Briefings empty-state action is staged but was not yet clicked/captured in this pass.
- The watcher result proved the recurring workflow surface and threaded follow-up path, but the result came from a simulator run with existing model/backend state; live backend reliability still depends on the private-route/OVH/AASA work documented separately.
- The widget detail thread is usable, but the bottom composer and card spacing still need a final visual pass for TestFlight polish.
