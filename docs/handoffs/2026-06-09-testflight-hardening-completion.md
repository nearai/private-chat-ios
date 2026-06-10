# TestFlight Hardening — Completion Report

Date: 2026-06-09 (evening)
Base handoff: `2026-06-09-claude-testflight-hardening-handoff.md`
Branch: `main` (work committed on top of `55a40b0`)

## Verdict

All five handoff lanes landed, plus eight gaps the handoff missed. Full unit
suite green: **506 passed, 0 failed** (three pre-existing `main` failures were
verified against clean HEAD in a throwaway worktree, then fixed as stale
expectations). Simulator-verified with screenshots. Build 5 archived and
uploaded per the procedure at the bottom.

## What the inherited patch already had (verified, kept)

- `model_id`/`modelId` decoding aliases (Lane 1)
- `canShowAnswerProofFooter` gating the proof capsule (Lane 2)
- Attachment turns clear `previousResponseID` (Lane 3) — also covers council
  sends, which receive the coordinator's cleared value through
  `sendCouncilTurnBridge`
- Failed-delivery mapping + `BriefingFollowUpResult` with error carrying (Lane 4)
- "temporarily restricted" recognized as recoverable + actionable copy in both
  copy maps (Lane 5). Because `streamResponseWithFallback` already wraps main
  chat sends, this one-line recognizer change activates automatic private-model
  fallback for normal chat too, not just briefings.

## New fixes beyond the handoff

1. **Failed turns no longer render the inline action row** (copy/export/
   regenerate/proof/save) — new `ChatMessage.canShowAssistantActions` gate.
   The failed row now shows red `Failed` plus a `Retry` button wired to
   `regenerateResponse`.
2. **"now ago" timestamp bug** — footer renders "just now" via
   `VerifiedFooterButton.relativeSuffix`.
3. **"No model proof" badge normalized to "No proof"** in the answer footer
   (the toolbar compact label already had this) — "No model proof · GLM 5.1"
   read as a contradiction. The header badge bug was exactly this string with
   " proof" stripped, yielding "No model".
4. **On-device intent replies stop claiming a model answered.**
   `ChatLocalIntentTranscriptWriter` no longer stamps `model` +
   `trustMetadata` on app-generated turns (tracker confirmations, local
   lookups). They render as "Assistant" with no proof footer.
5. **`BriefingRunOutcome` (delivered / quiet / failed)** replaces the
   `MessageWidget?` runner contract. Two real bugs this kills:
   - A conditional alert's quiet "condition not met" check was recorded as a
     *failure* every run; once failures became visible, every healthy alert
     would have shown "Run failed".
   - The actual failure reason (e.g. restricted route, sign-in needed) was
     discarded; trackers showed the generic "Run failed before producing a
     result." Now `runBriefing` → `BriefingStore.run` carries the specific
     reason end to end, council briefings capture the first model failure, and
     a quiet run clears a stale failure record.
6. **Tracker failed-delivery row is fully actionable**: red "Run failed"
   headline, the specific reason, red "failed" dot, and a **Run again** button
   on the delivery itself (`BriefingDelivery.isFailure` + `BotDeliveryRow`
   `onRetry`). Screenshot-testing this caught that the row renders `summary`,
   not `body`, under a headline — the reason now rides in both.
7. **Failure copy single-sourced**: `ChatStore.displayFailureMessage` now
   delegates to `MessageRepository.displayFailureMessage` (the two had
   byte-identical 40-line bodies that could drift).
8. **Attachment chips truncate in the middle** so long document names keep
   their start and extension visible.

## Demo-capture additions (QA surfaces)

Two new `DemoCaptureScreen` cases for deterministic failure-state screenshots
(no auth needed):

```sh
xcrun simctl launch "iPhone 17 Pro" ai.near.privatechat.ios -NEARDemoCapture -NEARDemoScreen=chatFailure
xcrun simctl launch "iPhone 17 Pro" ai.near.privatechat.ios -NEARDemoCapture -NEARDemoScreen=trackerFailure
```

`chatFailure` renders a successful turn (proof footer + actions) directly above
a failed turn (Failed + Retry only) — the canonical trust contrast.
`trackerFailure` renders the failed tracker delivery with reason + Run again.

## Pre-existing test failures fixed (verified stale against clean HEAD)

- `testCurrentCloudCatalogModelsRemainIndividuallySelectable` and
  `testDeprecatedPickerHidesLegacyRoutesButKeepsCurrentCloudChoices`:
  `openai/gpt-oss-120b` was deliberately deny-listed in
  `isDeprecatedPickerModel`; fixtures updated (Kimi K2 Instruct stands in as a
  current Cloud model).
- `testHomeOrchestrationPlannerAsksToCompleteIncompleteCouncilLineup`:
  subtitle format changed deliberately in `surfaceSubtitle` (commit 83ac698);
  expectation updated, the real invariant (no "Council" claim on incomplete
  lineups) unchanged.

## Verification evidence

- Focused handoff tests: 5/5 pass.
- Full unit suite: 506 pass / 0 fail (`-only-testing:NEARPrivateChatTests`).
- `./scripts/build-simulator.sh`: succeeds.
- Simulator screenshots (iPhone 17 Pro, fresh erase):
  - Cold launch → login screen renders correctly (terms gate + 3 providers).
  - `chat`, `threaded`, `glmResult`, `fileAttach` demo screens: chips aligned,
    footer "Proof · NEAR Private · 2 sources · just now", no "No model" badge,
    no "now ago".
  - `chatFailure` / `trackerFailure`: see above.

## Not verifiable headlessly (needs a signed-in device)

- Production OAuth callback round-trip (criterion 1) — the callback schemes
  (`nearai`, `nearprivatechat`) are registered; recent commits a65e5d0/aefae80
  addressed routing. Needs a phone test.
- Live GLM 5.1 answer / restricted-route fallback against the real backend
  (criteria 2–4 runtime side) — logic unit-tested; fallback now active for
  main sends. Needs a signed-in session.
- HEIC camera-photo upload end-to-end (criterion 7) — transcode path
  (`normalizedVisionUpload`) is unit-covered (`FileTests` 638–670).

Suggested phone pass once build 5 processes: the handoff's Hostile Product
Test Matrix, unchanged.
