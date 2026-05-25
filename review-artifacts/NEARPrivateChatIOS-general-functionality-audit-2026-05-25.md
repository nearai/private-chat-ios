# NEAR Private Chat iOS General Functionality Audit

Date: 2026-05-25

Scope: current local iOS source, focused on feature behavior, reliability, missing utility, and what Claude/Codex should fix next. This is a review artifact only; I did not run the app or the test suite in this pass.

Concrete product/design punchlist: see [NEARPrivateChatIOS-product-punchlist-2026-05-25.md](/Users/abhishekvaidyanathan/Documents/Playground/NEARPrivateChatIOS/review-artifacts/NEARPrivateChatIOS-product-punchlist-2026-05-25.md:1). That file should be used for UI implementation details; this file remains the reliability/functionality audit.

## Executive Verdict

NEAR Private Chat is not feature-poor. It is the opposite: it now has private chat, project context, prompt files, file library, saved links, notes, sharing, public links, direct invites, share groups, NEAR Cloud routes, IronClaw Mobile, hosted IronClaw, LLM Council, attestation, signed verified export, diagnostics, import/export, and setup profiles.

The main risk is that the app has more surface area than the functional spine can safely support. The places most likely to break in real use are route readiness, mobile streaming recovery, onboarding utility, retry/error recovery, undo/safety semantics, telemetry, and coverage of the actual end-to-end chat flows.

The highest-leverage framing for Claude/Codex: do not add another large feature yet. Make the existing feature graph reliable and legible.

## What Has Improved Since The Earlier Audit

- Destructive conversation delete is no longer an instant action. `ChatStore` now has a pending-delete flow and confirmation path before permanent delete (`ChatStore.swift:2030-2041`), while archive remains recoverable (`ChatStore.swift:2100-2124`).
- Public sharing is materially safer. The share UI now shows a preview sheet before creating a public link (`AppShellView.swift:2416-2427`, `AppShellView.swift:3029-3100`) and confirms sensitive share grants (`AppShellView.swift:2441-2459`).
- File upload no longer performs the main file read on the main actor. `PrivateChatAPI.uploadFile` reads data in a detached task and enforces the 10 MB limit (`PrivateChatAPI.swift:183-207`).
- PDF handling exists. `ChatStore.uploadAttachment` extracts readable PDF text off the main actor and uploads it as `pdf_text` (`ChatStore.swift:1838-1876`).
- Large paste handling is useful. Large draft paste content is staged as a pending text file and uploaded only when the user sends (`ChatStore.swift:1883-1937`).
- Council behavior is stronger than the original critique implied. Council streams multiple models in parallel (`ChatStore.swift:2924-3061`) and the synthesis prompt explicitly asks for "Disagreements or uncertainty" (`ChatStore.swift:3122-3153`).
- Attestation is now much better surfaced. The chat header has a compact attestation/security control (`AppShellView.swift:1224-1248`), route metadata can show attestation state (`AppShellView.swift:1256-1286`), the toolbar has a security button (`AppShellView.swift:1394-1404`), and assistant bubbles can show message-level attestation chips (`AppShellView.swift:6433-6444`).

## Current Feature Map

- Chat: streaming assistant responses, regenerate, edit/resend, local external-model message persistence, source modes, app web grounding, native web tool routing, prompt attachments.
- Models/routes: NEAR Private, NEAR Cloud, IronClaw Mobile, hosted IronClaw, LLM Council, Council synthesis.
- Context: local projects, project instructions, project files, saved links, saved notes, source-mode behavior.
- Files: prompt uploads, file library refresh/preview, project attachment, PDF-to-text extraction, large paste staging, remote delete.
- Sharing: public read-only link, direct invite, organization pattern, share groups, group share, share removal, public link disable.
- Security: TEE attestation fetch, freshness/status model, header indicator, message chips, copy, verified JSON export tests.
- Setup: account-scoped setup profile, use cases, context style, route preferences, generated plan preview, rerun from Account.
- Diagnostics: model catalog, web grounding, IronClaw bridge, IronClaw workstation, NEAR Cloud key check (`ChatStore.swift:1368-1380`).

## P1 Findings

### P1. First-run setup still does not deliver enough utility

The setup flow collects intent, but it mostly writes defaults instead of routing the user into a useful first action.

Evidence:

- Setup collects goal, use cases, context style, and toggles (`NEARPrivateChatApp.swift:197-249`), then saves a normalized profile (`NEARPrivateChatApp.swift:138-146`, `NEARPrivateChatApp.swift:267`).
- Normalization silently overrides explicit choices: build-agent forces IronClaw on and Council off; research forces Council on; research/build/team force web on and project context (`Models.swift:792-811`).
- `goalText` is used in setup preview copy (`Models.swift:915-933`) but is not used by `ChatStore.applySetupProfile` to seed a draft, create a first task, or open the relevant surface (`ChatStore.swift:1472-1503`).

Why this matters: the user is right that onboarding has close to zero functional payoff. It creates the feeling of configuration, but the app still drops the user onto a dense workspace and asks them to figure out what to do.

Fix:

- Convert setup completion into a first-action router.
- If the user entered a goal, seed the draft or create a "Start from your goal" action.
- If the user selected research, create/open the research project and show 2-3 starter prompts.
- If the user selected build agents, open the Agent sheet only if IronClaw is actually ready; otherwise open a focused setup repair sheet.
- Stop silently overriding toggles. If a use case requires a default, show the consequence inline before Finish.

### P1. Route readiness is advisory, not a hard pre-send gate

The UI can hint that a route is unavailable, but `sendDraft` clears the draft and enters the send pipeline before route-specific readiness has been validated.

Evidence:

- `sendDraft` clears `draft` and `pendingAttachments` before send resolution (`ChatStore.swift:2679-2688`).
- `send` refreshes models/billing, routes the prompt, ensures/creates a conversation, appends local user/assistant messages, then streams (`ChatStore.swift:2798-2921`).
- Hosted IronClaw validates endpoint only inside `streamResponse` after the conversation/message setup has begun (`ChatStore.swift:3233-3237`).
- NEAR Cloud key validation happens inside `streamNearCloudModel` (`ChatStore.swift:3274-3285`).
- Account-scoped load prevents selecting hosted IronClaw when the hosted endpoint is unusable, but it does not similarly force away a NEAR Cloud route when the cloud key is missing (`ChatStore.swift:4019-4028`).
- The placeholder can say "Add NEAR Cloud API key" (`ChatStore.swift:671-682`), but placeholder text is not a functional guard.

Impact:

- A user can create a new local conversation and assistant failure state when the app already knows the selected route cannot work.
- Demo risk: selecting a NEAR Cloud or hosted IronClaw path without the key/endpoint can make the first visible action look broken.

Fix:

- Add a `RouteReadinessGate` before draft clearing, conversation creation, and message append.
- Gate NEAR Cloud on saved API key, hosted IronClaw on usable HTTPS endpoint, IronClaw Mobile on local/hosted availability, and Council on all selected model legs being usable.
- Return a typed recovery action: `addNearCloudKey`, `configureIronClawEndpoint`, `switchToPrivate`, `editCouncilLineup`.
- Add tests for each blocked route to prove no conversation or empty assistant bubble is created.

### P1. Mobile streaming resilience is not strong enough

Streaming is implemented, but it is a single-shot SSE stream with no resume/reconnect semantics.

Evidence:

- `PrivateChatAPI.streamResponse` uses `URLSession.shared.bytes`, iterates `bytes.lines`, and throws if the stream ends before `response.completed` (`PrivateChatAPI.swift:503-570`).
- `cancelStream` marks local messages cancelled, but does not model retry/resume state (`ChatStore.swift:2706-2724`).

Impact:

- Cell handoff, app backgrounding, captive Wi-Fi, and transient server disconnects can turn a normal mobile condition into a failed answer.
- This is one of the fastest ways for an otherwise strong iOS chat app to feel unreliable.

Fix:

- Introduce a stream state machine: connecting, streaming, reconnecting, completed, failed, cancelled.
- Track last visible output time, last response id/event id if available, and whether replay is safe.
- Add one automatic reconnect for transport failures before visible output, and an explicit "Continue" recovery card after partial output.
- Preserve partial assistant text and sources through retry.

### P1. Failure UX still leans too heavily on transient banners

Many operations use `showBanner`, and banners disappear after three seconds.

Evidence:

- `showBanner` clears the message after three seconds (`ChatStore.swift:3991-3999`).
- Send failures update the assistant bubble if one exists, but failures before the assistant placeholder exists can be only a transient banner (`ChatStore.swift:2903-2921`).
- Files, shares, diagnostics, project operations, archive/delete, and route setup all use banner-only feedback in many cases.

Impact:

- The user can miss the reason something failed.
- Recovery is not attached to the failed object.
- Demo flows can fail without a visible persistent explanation.

Fix:

- Replace route, stream, upload, and share failures with inline recovery cards.
- Keep banners for success confirmations only.
- Add retry buttons where safe: "Try again", "Add key", "Switch to NEAR Private", "Reconnect stream", "Re-upload".

### P1. Test coverage does not cover the riskiest functional paths

The test file is a good start, but it mostly covers pure parsing, model/source semantics, storage, attestation helpers, telemetry encoding, and export shape.

Evidence:

- `PrivateChatCoreTests.swift` has tests for auth callback state, deep links, import normalization, stream parser events, setup storage, source routing, NEAR Cloud ids, attestation, telemetry encoding/local aggregation, and verified transcript export.
- Missing from the current visible tests: `ChatStore.sendDraft/send` integration, route readiness gates, NEAR Cloud missing-key behavior, hosted IronClaw missing-endpoint behavior, share public-link create/disable, file upload/PDF failure recovery, project mutation persistence, undo behavior, stream reconnect behavior, and UI smoke tests.
- Current core file sizes are high: `ChatStore.swift` 7,050 lines, `AppShellView.swift` 8,309 lines, `Models.swift` 2,774 lines, while `PrivateChatCoreTests.swift` is 716 lines.

Fix:

- Create a mockable `ChatService` boundary around the API and route clients.
- Add `ChatStoreSendFlowTests`.
- Add route-readiness tests that verify the draft is preserved and no conversation is created.
- Add share/file/project mutation tests with fake APIs.
- Add one lightweight UI smoke test: setup finish -> home -> new chat -> send blocked route -> recovery action visible.

## P2 Findings

### P2. Attestation is surfaced well, but freshness should become automatic

The UI now has the right primitives: header indicator, metadata pill, security button, and per-message chips. The remaining functional problem is that proof freshness still depends too much on explicit fetch behavior.

Evidence:

- `currentAttestationStatus` returns unavailable for non-private routes and uses the private route snapshot otherwise (`ChatStore.swift:557-574`).
- `refreshAttestationReport` is manual and route-gated (`ChatStore.swift:2435-2456`).

Fix:

- Auto-refresh attestation on private-route chat open, selected model change, and app foreground if stale.
- Store attestation freshness per model, not just as a single current snapshot.
- Degrade the header state visibly when the selected model changes away from the attested model.

### P2. Sharing is strong, but expiry is UI-only right now

Public link safety improved, but expiry options are visible while only manual disable is available.

Evidence:

- `SharePublicLinkExpiry` includes manual, 7 days, and 30 days, but only manual is available (`AppShellView.swift:2293-2302`).
- `enablePublicShare` does not pass expiry into the API call (`ChatStore.swift:2216-2222`).
- Public URLs are hard-coded to `https://private.near.ai/c/<id>` (`ChatStore.swift:2426-2428`).

Fix:

- Either hide unavailable expiry choices or implement expiry end to end.
- Move public base URL to configuration.
- Add undo/recovery for removed access where backend allows it.

### P2. File handling is much better, but still whole-memory and no undo

Evidence:

- File data is read in full into memory, then the multipart body is built in memory (`PrivateChatAPI.swift:191-207`, `PrivateChatAPI.swift:252-265`).
- Remote file delete removes the file from remote list, pending prompt attachments, projects, and preview state with only a banner confirmation after the API call (`ChatStore.swift:1796-1812`).

Fix:

- Whole-memory upload is acceptable at 10 MB, but document that this is the budget and enforce it everywhere.
- Add a delete confirmation and/or a soft undo where possible. The UI already has confirmation for remote file delete, so the missing piece is recoverability after the fact.
- Preserve structured PDF metadata in addition to extracted text when possible.

### P2. Council is a product win, but disagreement is not yet a durable artifact

Evidence:

- Council streams multiple model answers and can synthesize a final answer (`ChatStore.swift:2924-3061`).
- The synthesis prompt asks for agreements and disagreements (`ChatStore.swift:3147-3151`).

Gap:

- There is no first-class "disagreement report" export or durable comparison object.

Fix:

- Add a Council report view: model answers, agreements, disagreements, failed legs, synthesis model, sources, and attestation state.
- Add export: JSON and Markdown.
- For high-stakes prompts, make "Show disagreement" a visible affordance, not something buried in the synthesized prose.

### P2. Telemetry exists but is not wired into product decisions

Evidence:

- `PrivateTelemetry.swift` defines local aggregation and settings.
- Tests verify telemetry encoding excludes forbidden fields and aggregates counters locally.
- No current production call sites were found in `ChatStore`, `AppShellView`, or setup beyond telemetry definitions/tests.

Fix:

- Make the product decision explicit: no telemetry, local-only diagnostics export, or opt-in private aggregated telemetry.
- If enabled, wire only privacy-safe events: setup completed/skipped, route readiness blocked, stream failed/retried, share preview opened/created, attestation fetched/stale, first prompt sent.
- Expose the setting in Account with clear copy.

### P2. Diagnostics are useful but not part of the working path

Evidence:

- `runDiagnostics` checks model catalog, web grounding, IronClaw bridge, IronClaw workstation, and NEAR Cloud key (`ChatStore.swift:1368-1380`).

Gap:

- Diagnostics are a manual account action, not a prerequisite repair path for demo-critical features.

Fix:

- Add a "Demo readiness" or "Route readiness" preflight that produces a pass/warning/fail summary.
- Let setup and route-blocked errors deep-link into the exact repair action.

### P2. Cross-device and conflict semantics are still unclear

The code has local external-model persistence and server refreshes, but no visible product semantics for "same chat open on web and iOS while both stream".

Fix:

- Add conversation sync state: up to date, local external turns, remote changed, conflict.
- For active stream conflicts, show a read-only warning or branch automatically.

## P3 Findings

### P3. Performance risk is structural

`ChatStore.swift` and `AppShellView.swift` are very large. That does not automatically mean the app is slow, but it makes SwiftUI invalidation and regression analysis harder.

Current sizes:

- `ChatStore.swift`: 7,050 lines
- `AppShellView.swift`: 8,309 lines
- `Models.swift`: 2,774 lines
- `PrivateChatCoreTests.swift`: 716 lines

Fix:

- Add performance budgets before more visual polish: cold start, first frame, chat switch, send-to-first-token, tokens/sec, file sheet open, project sheet open.
- Split route handling, sharing, file library, attestation, and setup application into smaller services only where tests can pin behavior.

### P3. Some destructive flows are confirmed but not undoable

The "delete needs confirmation" issue is mostly addressed for conversations and project/file UI flows. The remaining gap is undo/recovery across archive, move, share revoke, share group delete, and file delete.

Fix:

- Add a global undo toast for local reversible actions.
- For non-reversible backend actions, use a stronger confirmation sheet and, where possible, signed receipts.

## Recommended Work Packets For Claude/Codex

### Packet F0 - Make onboarding useful

Implement first-action routing from setup completion. Preserve explicit user toggles or show clear inline consequences before overriding them. Use `goalText` to seed draft or create a first action. Add tests for setup profile application.

### Packet F1 - Route readiness gate

Add a pre-send readiness gate before draft clearing and conversation creation. Block missing NEAR Cloud key, unusable hosted IronClaw endpoint, unavailable IronClaw Mobile route, and invalid Council lineups. Return typed recovery actions and test that blocked sends preserve draft/attachments.

### Packet F2 - Streaming recovery

Introduce stream state, reconnect/retry semantics, and persistent partial-output recovery. Add tests around stream ending before completion and around cancellation.

### Packet F3 - Inline error and retry system

Move high-value errors out of transient banners and into contextual cards. Prioritize send failures, route readiness failures, file upload failures, share failures, and attestation fetch failures.

### Packet F4 - Telemetry decision and wiring

Choose privacy stance, document it, expose it in Account, and wire opt-in local/private counters if desired. Do not collect prompt, response, filename, URL, account, or recipient content.

### Packet F5 - Functional test harness

Build fake API clients and cover send flows, route gates, share flows, file flows, project mutation, and attestation freshness. Add one UI smoke test for setup to first prompt.

### Packet F6 - Files and sharing recovery

Add undo/recovery for archive, move, share revoke, share group delete, and file delete where possible. Implement or hide public-link expiry.

### Packet F7 - Council disagreement artifact

Create a durable Council report view and export. Make model disagreement a first-class product artifact, not just prose in the synthesis.

### Packet F8 - Performance budget

Add measured budgets and only then split the largest store/view areas around tested seams: route runtime, sharing, files, attestation, setup.

### Packet F9 - Product-quality iPhone pass

Implement the build-now items from `NEARPrivateChatIOS-product-punchlist-2026-05-25.md`: Home productization, Composer/New Chat, Model Picker/Auto-Council, Project Context taxonomy and source freshness, Chat Header/Titles/Sources, Security proof actions, Visual/accessibility/haptics tokens, search, recents/resume, and draft persistence. This should stay iPhone-focused; do not start iPad work.

### Packet F10 - Welcome project and Beginner mode

Add the first-run utility layer from the punchlist: an explicit Beginner/Power onboarding choice, advanced features hidden only when the user chooses Beginner, and a curated Welcome project with a sample file, sample link, instruction, and example Council chat.

### Packet F11 - Category workflows

After the core product is stable, build the high-differentiation workflows: Quick Council on any answer, Signed Snippet copy with proof, Attestation Diff, signed transcript publish, Lock Screen Live Activity, App Intents, widgets, and future Mac proof panel.

## Suggested Claude/Codex Prompt

Use this directly:

> Work in `/Users/abhishekvaidyanathan/Documents/Playground/NEARPrivateChatIOS`. Implement Packet F1 from `review-artifacts/NEARPrivateChatIOS-general-functionality-audit-2026-05-25.md`: add a pre-send route readiness gate before draft clearing, conversation creation, and assistant placeholder creation. Gate NEAR Cloud missing key, hosted IronClaw missing endpoint, unavailable IronClaw Mobile, and invalid Council lineups. Preserve the user's draft and attachments when blocked. Show a persistent recovery affordance, not only a transient banner. Add tests proving blocked sends do not create conversations/messages and valid sends still work. Do not refactor unrelated UI.

Second prompt after F1:

> Implement Packet F0 from `review-artifacts/NEARPrivateChatIOS-general-functionality-audit-2026-05-25.md`: make setup completion route to an actual first action. Use `goalText` to seed a draft or action. Do not silently override toggles without visible consequence copy. Add tests for `UserSetupProfile.normalizedForDefaults` and `ChatStore.applySetupProfile`.

Third prompt for the product pass:

> Work in `/Users/abhishekvaidyanathan/Documents/Playground/NEARPrivateChatIOS`. Implement the first iPhone product-quality sprint from `review-artifacts/NEARPrivateChatIOS-product-punchlist-2026-05-25.md`: route readiness gate from this audit, Packet P8 visual/accessibility/haptics baseline, Packet P0 home productization, and Packet P1 composer/new-chat improvements. Reconsideration note: do not remove compose globally; keep a top-right compose/pencil icon off-home. Do not create 64 x 64 tiles for All/Shared/Archived; use segmented control or compact filter strip. Add home search across chats/projects/sources, last-three recents/resume row, project icon/color persistence, focus-aware placeholders, visible attachment shelf, draft persistence, long-paste attachment affordance, and filled circular send/stop state. Keep SF Pro, ignore full NEAR brand guidelines, and do not start iPad work. Add focused tests for new persistence/state helpers and run the iOS test target if available.
