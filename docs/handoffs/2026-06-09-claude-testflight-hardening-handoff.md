# NEAR Private Chat iOS: TestFlight Hardening Handoff

Date: 2026-06-09

Repo: `/Users/abhishekvaidyanathan/Documents/Playground/NEARPrivateChatIOS`

Branch at handoff: `main`

Status at handoff: local fixes are in progress and uncommitted. Do not discard or rewrite them without first reading the diffs.

Primary owner intent: make the TestFlight app actually usable for real mobile testing. That means auth works, chat works, model selection is coherent, attachments work, recurring trackers can be created and run, failures are honest and actionable, and the UI looks intentional instead of stitched together.

## Security And Secrets

Do not paste live API keys, bearer tokens, session tokens, or TestFlight credentials into this document, commits, logs, screenshots, PRs, or chat transcripts.

Use local environment variables or Keychain-only setup:

```sh
export NEAR_AI_CLOUD_API_KEY="<provided securely outside git>"
export PRIVATE_CHAT_SESSION_TOKEN="<provided securely outside git>"
```

If a key or token was pasted into chat, assume it should be rotated. Do not preserve it in any artifact.

## Current User-Visible Failures

The latest TestFlight build is installable, but the app is still not acceptable for real testing. The most recent screenshots show:

- A chat header badge says `No model` even though the footer says `GLM 5.1`.
- A GLM 5.1 request fails with `Access temporarily restricted. Please try again later.`
- Attachment summarization fails after a previous successful chat turn.
- The app can create a tracker, for example `NEAR price`, but opening the tracker shows no delivery.
- Tracker thread replies show weak generic copy such as `I couldn't reach the model just now - try again in a moment.`
- Failure and proof states are visually confused. Failed messages can still look like proof-bearing assistant answers.
- The app still feels too brittle and too wired around specific examples rather than general "turn any input into useful action" behavior.

Recent screenshot paths supplied by the user:

- `/Users/abhishekvaidyanathan/Downloads/IMG_0006.PNG`
- `/Users/abhishekvaidyanathan/Downloads/IMG_0007.PNG`
- `/Users/abhishekvaidyanathan/Downloads/IMG_0008.PNG`

## Non-Negotiable Acceptance Criteria

Do not ship another build just because it compiles.

A new TestFlight build is acceptable only when all of these are true:

1. Auth completes from the production mobile callback path.
2. A fresh private chat can send and receive at least one answer.
3. Model selection is coherent. The selected model shown in the composer, header, request route, message footer, and proof surface cannot contradict itself.
4. If GLM 5.1 is restricted or unavailable, the app either falls back to another available private model or gives the user a clear, actionable model-route error.
5. Failed assistant replies never show proof affordances, proof footers, green checks, or `No model proof` as if they were real answers.
6. A PDF attachment can be summarized in a new chat and after a previous chat turn.
7. A camera/screenshot image attachment path is tested, including iOS-native formats where possible.
8. A tracker can be created, run now, opened, and followed up in thread.
9. If tracker execution fails, the tracker detail screen shows a failed run with error text and a retry/run-now path, not `No delivery yet`.
10. The core UI reads as deliberate on an iPhone screen: chips aligned, no awkward truncation, no duplicate/contradictory labels, no proof/model copy confusion.

## Current Local Worktree

At the moment this handoff was written, these files had local modifications:

```text
NEARPrivateChat/App/State/ChatStore.swift
NEARPrivateChat/Features/Chat/ChatMessageViews.swift
NEARPrivateChat/Features/Chat/ChatModels.swift
NEARPrivateChat/Features/Chat/ChatSendCoordinator.swift
NEARPrivateChat/Features/Chat/ChatToolbar.swift
NEARPrivateChat/Features/Chat/MessagePresentationHelpers.swift
NEARPrivateChat/Features/Chat/MessageRepository.swift
NEARPrivateChat/Features/Chat/ThreadedBriefingMapping.swift
NEARPrivateChat/Features/Chat/ThreadedFeature.swift
NEARPrivateChatTests/Chat/BriefingTrackerTests.swift
NEARPrivateChatTests/Chat/ComposerAndSendTests.swift
```

Start with:

```sh
cd /Users/abhishekvaidyanathan/Documents/Playground/NEARPrivateChatIOS
git status --short --branch
git diff --stat
git diff -- NEARPrivateChat/App/State/ChatStore.swift
git diff -- NEARPrivateChat/Features/Chat
git diff -- NEARPrivateChatTests/Chat
```

Do not run `git reset --hard`, `git checkout --`, or destructive cleanup. Preserve user and agent changes unless there is an explicit reason to replace them.

## Fixes Already Started

The local patch set attempts to address the TestFlight failures in five lanes.

### Lane 1: Model Identity And Message Decoding

File: `NEARPrivateChat/Features/Chat/ChatModels.swift`

Problem:

The server may return model identity as `model_id` or `modelId`, while the client only reliably surfaced `model`. This can produce UI states where the message footer knows a model indirectly, but the header/proof surfaces render `No model`.

Started fix:

- Add decoding aliases for `model_id` and `modelId`.
- Ensure `ConversationItem.model` is populated from those aliases when `model` is absent.

Required verification:

- Decode fixture with `model_id: "GLM 5.1"` and assert the UI-facing model is not empty.
- Decode fixture with `modelId: "GLM 5.1"`.
- Decode fixture with no model and assert proof surfaces do not pretend the answer has proof.

### Lane 2: Proof And Failure Honesty

Files:

- `NEARPrivateChat/Features/Chat/MessagePresentationHelpers.swift`
- `NEARPrivateChat/Features/Chat/ChatMessageViews.swift`
- `NEARPrivateChat/Features/Chat/ChatToolbar.swift`

Problem:

Failed assistant turns and model-less turns can still render proof-related UI. This is a trust bug. It makes a failed or unverified response look more authoritative than it is.

Started fix:

- Add `ChatMessage.canShowAnswerProofFooter`.
- Only show answer proof footers for non-streaming assistant messages with non-failed status, non-empty text, and non-empty model identity.
- Prevent compact proof UI from turning `No model proof` into `No model`; it should read `No proof` or be hidden depending on context.

Required verification:

- Failed assistant message: no proof footer, no shield/check affordance, failure state visible.
- Successful assistant message with model: footer and proof state render normally.
- Successful assistant message without model: no fake proof.
- Toolbar compact proof label never says `No model` as the primary state when model selection elsewhere says `GLM 5.1`.

### Lane 3: Attachment Send Pipeline

File: `NEARPrivateChat/Features/Chat/ChatSendCoordinator.swift`

Problem:

Attachment turns can reuse a previous response ID from a prior chat turn. This can route file summarization as a continuation of old context rather than a clean file-grounded request, and can contribute to failures after a previous successful chat.

Started fix:

- Calculate `apiAttachments` before deciding the previous response chain.
- If attachments are present, clear `previousResponseID` for the streaming request.
- Preserve previous response chaining only for no-attachment chat turns.

Required verification:

- Chat once with text only.
- Then attach a PDF and ask `summarize this`.
- Assert the outgoing stream request has attachment IDs and no previous response ID.
- Repeat with a new chat and with a project/file context if applicable.

### Lane 4: Tracker And Briefing Failure Visibility

Files:

- `NEARPrivateChat/Features/Chat/ThreadedFeature.swift`
- `NEARPrivateChat/Features/Chat/ThreadedBriefingMapping.swift`
- `NEARPrivateChat/App/State/ChatStore.swift`

Problem:

Trackers can be created but their immediate or scheduled run can fail invisibly. The tracker detail screen may still show `No delivery yet`, and thread follow-ups collapse to generic text.

Started fix:

- Replace tuple-like briefing follow-up result with a structured `BriefingFollowUpResult`.
- Carry failure message through tracker thread replies.
- Map failed briefing status into a visible failed delivery in `ThreadedBriefingMapping`.
- Start a model-fallback path for briefing text streaming.

Required verification:

- Create tracker from prompt: `Create NEAR price tracker run it now`.
- Open tracker immediately.
- If run succeeds, a delivery exists.
- If run fails, delivery area shows `Run failed`, specific error text, and a retry/run-now affordance.
- Reply in tracker thread. The answer should either succeed or preserve actionable failure copy.

### Lane 5: Restricted Model Errors

Files:

- `NEARPrivateChat/App/State/ChatStore.swift`
- `NEARPrivateChat/Features/Chat/MessageRepository.swift`

Problem:

`Access temporarily restricted. Please try again later.` is too opaque and leaves users stuck. It also appears to come from a model/provider route rather than local auth alone.

Started fix:

- Treat `temporarily restricted` as a recoverable model access error.
- Map it to clearer copy:
  `Access temporarily restricted on the selected model route. Choose another private model or try again in a moment.`
- In briefing streams, try a preferred available private-model fallback on recoverable model errors.

Required verification:

- Unit test maps raw restricted error to actionable copy.
- If model fallback is available, tracker/briefing run should try it.
- UI should show which model actually answered after fallback.
- Do not silently change the user's selected model without visible disclosure.

## Tests Already Started

Files:

- `NEARPrivateChatTests/Chat/ComposerAndSendTests.swift`
- `NEARPrivateChatTests/Chat/BriefingTrackerTests.swift`

Tests added or extended:

- `testAttachmentTurnClearsPreviousResponseIDBeforeStreaming`
- `testConversationItemsDecodeModelIDVariants`
- `testFailedAssistantTurnsDoNotShowProofFooter`
- `testChatStoreRateLimitFailureCopyIsActionable`
- `testBriefingRunRecordsFailureStatusAndTimezone`

Before doing more feature work, run the focused set:

```sh
xcodebuild test \
  -project NEARPrivateChat.xcodeproj \
  -scheme NEARPrivateChat \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:NEARPrivateChatTests/PrivateChatCoreTests/testAttachmentTurnClearsPreviousResponseIDBeforeStreaming \
  -only-testing:NEARPrivateChatTests/PrivateChatCoreTests/testConversationItemsDecodeModelIDVariants \
  -only-testing:NEARPrivateChatTests/PrivateChatCoreTests/testFailedAssistantTurnsDoNotShowProofFooter \
  -only-testing:NEARPrivateChatTests/PrivateChatCoreTests/testChatStoreRateLimitFailureCopyIsActionable \
  -only-testing:NEARPrivateChatTests/PrivateChatCoreTests/testBriefingRunRecordsFailureStatusAndTimezone
```

Known recent compile issues that may already be fixed locally:

- `MessagePresentationHelpers.swift`: computed helper initially missed an explicit `return`.
- `ComposerAndSendTests.swift`: test fake `streamResponseWithFallbackForSend` initially missed `return initialModel`.

If either comes back, fix directly and rerun.

## Required Build Verification

After focused tests pass:

```sh
./scripts/build-simulator.sh
```

Then launch the app in Simulator using the configured iOS workflow. If using XcodeBuildMCP, call `session_show_defaults` before the first build/run command in that tool session.

Manual smoke requirements in Simulator:

1. Launch app cold.
2. Confirm auth/session state.
3. Confirm default model shows GLM 5.1 or the intended default consistently.
4. Open model selector and verify private/cloud models are selectable as intended.
5. Send `who am i`.
6. Attach a PDF and ask `summarize this`.
7. Create a tracker and run it now.
8. Open tracker thread and send a follow-up.
9. Confirm no contradictory `No model` or fake proof state appears.

## Hostile Product Test Matrix

Run these as actual app flows, not just unit tests. Capture screenshots for pass/fail evidence.

### Basic Chat

Prompt:

```text
who am i
```

Expected:

- If no identity context is available, the answer says so plainly.
- The request succeeds through a real model route.
- Footer model matches selected model or disclosed fallback model.
- No `No model` badge appears in the header.

### Model Fallback

Prompt:

```text
Give me a two paragraph summary of what this app can do.
```

Steps:

- Send with GLM 5.1.
- If restricted, switch to another private model.
- Try again.

Expected:

- Restricted route gives actionable error.
- Other available model can be selected.
- The app does not trap the user on a dead model.

### PDF Work Product

Attach a PDF, preferably a term sheet or services agreement template.

Prompt:

```text
Summarize this document, extract the obligations, and turn them into a draft action checklist with owners and dates where possible.
```

Expected:

- File uploads as an attachment.
- Request does not reuse a stale previous response ID.
- Output references document content.
- If the PDF cannot be parsed, the app explains why and suggests next action.

### Image Understanding

Attach an iPhone screenshot or photo.

Prompt:

```text
Describe this screenshot and tell me what looks broken or confusing.
```

Expected:

- PNG/JPEG works with native vision where supported.
- HEIC/HEIF/TIFF path should either be sent as native vision or transcoded before upload. It must not silently degrade to OCR-only if visual understanding is needed.

### Tracker Creation

Prompt:

```text
Track NEAR price every weekday at 8am and run it now.
```

Expected:

- Tracker is created.
- Schedule is correct.
- Immediate run happens or a visible failed delivery appears.
- No hardcoded price logic. The model or a real data/tool route should decide how to handle the request.

### General Tracker

Prompt:

```text
Every Monday morning, find new papers about TEE attestation and summarize the three most important ones with citations.
```

Expected:

- Tracker should not assume price/weather-specific shape.
- It should store a general recurring research task.
- It should disclose sources/tool route when it runs.

### Action Conversion

Prompt:

```text
Turn this messy note into next actions, reminders, and a project brief.
```

Expected:

- The app proposes structured actions.
- It does not force the user through a rigid tracker-only or briefing-only path.
- It should feel like a general mobile AI work surface.

## Design Hardening Brief

The current UI problems are not cosmetic only. They create trust failures.

Design principles for this pass:

- One source of truth for model state.
- One source of truth for source/tool mode.
- Proof UI only appears when proof exists and applies to the displayed answer.
- Failure states should be visually obvious but not scary unless action is required.
- Chips should align cleanly and fit on iPhone widths.
- The app should feel like a mobile AI workbench, not a pile of debug affordances.
- Avoid hardcoded demo content in production UX. `NEAR price` can be user-created, but it must not be wired as a special-case behavior.

Specific UI fixes to inspect:

- Header model badge.
- Composer model chip.
- Source chip.
- Council chip.
- Proof/shield controls below assistant messages.
- Failed assistant message rendering.
- Tracker detail empty/failed/success states.
- Tracker thread composer.
- Attachment chip truncation.
- Empty chat action chips.

Acceptance bar:

- On a narrow iPhone, chips are aligned, legible, and tappable.
- No button text clips.
- No duplicated `Web` or contradictory source labels.
- No `No model` display when the selected model is known.
- No model/proof badge should look disabled if the user can fix it by selecting a model.
- No proof-related affordance on failed replies.

## Architecture Guardrails

This repo has been going through an architecture reset. Respect the direction rather than adding more behavior to the biggest files.

Read before larger changes:

- `RULES.md`
- `docs/architecture/ARCHITECTURE.md`
- `docs/architecture/PLAN.md`
- `docs/architecture/ChatStoreDebtMap.md` if present

Rules for this handoff:

- Do not add more unrelated behavior to `ChatStore` if a narrower owner exists.
- If a new Swift file is added, add it to the Xcode project.
- Prefer small testable helpers over giant view/model conditionals.
- Avoid hardcoded workflow paths for price/weather/research.
- The product model is: any user-provided context can become chat, files, research, trackers, actions, or project state.

## Suggested Multi-Agent Workstreams

If using multiple agents, split the work like this.

### Agent A: Chat And Model Route

Scope:

- Model decoding.
- Model selector parity.
- Restricted model fallback.
- Message footer/header consistency.
- API request route verification.

Deliverables:

- Unit tests for model aliases and selected/displayed model consistency.
- Simulator proof that at least one private model answers.
- Clear failure copy for restricted models.

### Agent B: Attachments And Work Products

Scope:

- PDF summarization.
- Image attachment dispatch.
- HEIC/HEIF/TIFF handling.
- Previous response ID behavior with files.

Deliverables:

- Tests asserting attachment requests carry attachment IDs and clear stale response IDs.
- Simulator proof with a PDF and a screenshot/photo.
- No OCR-only silent degradation for visual tasks.

### Agent C: Trackers And Recurring Work

Scope:

- Tracker creation.
- Run-now behavior.
- Scheduled briefing result mapping.
- Tracker thread follow-up.
- General non-price tracker prompts.

Deliverables:

- Tests for failed and successful delivery mapping.
- UI proof for failed run and retry.
- Hostile tests for price, research, and arbitrary recurring tasks.

### Agent D: Design And Trust Surface

Scope:

- Header/composer chip alignment.
- Proof/failure UI.
- Empty and tracker states.
- Dynamic Type and tap target sanity.

Deliverables:

- Before/after screenshots.
- No clipped chips on iPhone.
- No contradictory model/proof/source copy.

### Agent E: Release QA

Scope:

- Focused tests.
- Broader unit tests.
- Simulator build.
- TestFlight build bump/archive/upload.

Deliverables:

- Exact commands run.
- Test logs.
- Build number.
- App Store Connect/TestFlight processing status.

## TestFlight Build Procedure

Only do this after the acceptance criteria pass.

Check current build settings first:

```sh
agvtool what-version
xcodebuild -showBuildSettings -project NEARPrivateChat.xcodeproj -scheme NEARPrivateChat | rg 'MARKETING_VERSION|CURRENT_PROJECT_VERSION|PRODUCT_BUNDLE_IDENTIFIER|DEVELOPMENT_TEAM'
```

If the next build number is needed, bump it intentionally:

```sh
xcrun agvtool new-version -all <next_build_number>
```

Archive/export/upload pattern that previously worked:

```sh
ARCHIVE_PATH="$PWD/build/Archives/NEARPrivateChat-$(date +%Y%m%d)-b<next_build_number>-unsigned.xcarchive"

xcodebuild archive \
  -project NEARPrivateChat.xcodeproj \
  -scheme NEARPrivateChat \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  DEVELOPMENT_TEAM=RYJ2LB9649
```

Then export/upload with automatic signing:

```sh
EXPORT_PLIST="$PWD/build/ExportOptions-b<next_build_number>.plist"
EXPORT_DIR="$PWD/build/ExportBuild<next_build_number>"

mkdir -p "$EXPORT_DIR"
/usr/libexec/PlistBuddy -c 'Clear dict' "$EXPORT_PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Add :method string app-store-connect' "$EXPORT_PLIST"
/usr/libexec/PlistBuddy -c 'Add :destination string upload' "$EXPORT_PLIST"
/usr/libexec/PlistBuddy -c 'Add :teamID string RYJ2LB9649' "$EXPORT_PLIST"
/usr/libexec/PlistBuddy -c 'Add :signingStyle string automatic' "$EXPORT_PLIST"
/usr/libexec/PlistBuddy -c 'Add :uploadSymbols bool true' "$EXPORT_PLIST"
/usr/libexec/PlistBuddy -c 'Add :manageAppVersionAndBuildNumber bool false' "$EXPORT_PLIST"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -allowProvisioningUpdates
```

Record:

- Build number.
- Archive log path.
- Export/upload log path.
- Whether App Store Connect accepted the upload.
- Whether TestFlight processing completed.

## Commit Guidance

Commit only after tests and simulator verification.

Suggested commit shape:

```text
Harden TestFlight chat, tracker, and proof states

- Decode server model_id/modelId aliases into chat messages
- Hide proof affordances on failed/model-less assistant replies
- Avoid stale previous response chaining for attachment turns
- Surface tracker run failures as visible deliveries
- Improve restricted-model failure copy and briefing fallback behavior
- Add focused tests for model decoding, attachments, failure proof state, and tracker failures
```

Before commit:

```sh
git diff --check
git status --short
```

After commit and push, include:

- Commit SHA.
- Tests run.
- Simulator proof summary.
- TestFlight build number if uploaded.

## Do Not Do

- Do not hardcode price checks, weather checks, or one-off tracker behavior.
- Do not create a separate private chat inside private chat.
- Do not show fake proof or green trust UI for unverified, failed, or model-less output.
- Do not ship a build where chat only works in a simulator but not TestFlight.
- Do not rely on canned demo screenshots as proof.
- Do not bury real failures behind generic `try again later` copy.
- Do not leak secrets into git or logs.

## Final Definition Of Done

The work is done when a TestFlight user can:

1. Install the app.
2. Sign in.
3. Select a model.
4. Send a normal chat.
5. Attach and summarize a PDF.
6. Create and run a tracker.
7. Open the tracker and follow up in thread.
8. Understand failures without reading logs.
9. Trust that model, source, and proof labels are accurate.
10. Look at the UI and feel that the product is coherent enough to keep testing.

