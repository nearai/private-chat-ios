# NEAR Private Chat iOS - Feature & Functionality Review

Date: 2026-05-25  
Scope: static source review of the current `NEARPrivateChatIOS` workspace, plus handoff questions for Claude/deep research.  
Note: this pass did not re-run the simulator or refresh screenshots. It is grounded in the current Swift source and the earlier screenshot/design audits.

## Executive Verdict

The app has moved meaningfully since the earlier audit. Several originally scary problems are now either fixed or partially fixed:

- Setup now collects a real first goal, Beginner/Power visibility mode, saved-material style, and explicit defaults.
- Setup applies a first-run draft and can seed a starter project, so onboarding is no longer purely decorative.
- Route readiness now blocks bad sends before clearing the composer in the main send path.
- Hosted IronClaw has a privacy-aware handoff preflight before sending prompt/project context to the workstation path.
- Home has search, a Resume row, All/Shared/Archived filters, project color/icon identity, and date-grouped conversations.
- Composer has focus-specific placeholders, attachment shelf, route-readiness recovery card, slash commands, haptics, draft persistence, and Reduce Motion handling.
- Council has a visible grouped response surface and parallel model streaming.
- Project Context is much closer to a real project workspace: three tabs, add-link flow, source/file freshness labels, notes, and project identity.
- Security has persistent attestation surfaces, proof actions, and a proof explanation section.

The remaining product risk is no longer "this is only a prototype." The risk is sharper: **the app now looks like it proves privacy/verifiability more than the implementation actually proves it in some places.** That is fixable, but it should be treated as high priority because NEAR Private Chat's category claim is proof, not generic chat polish.

## Highest-Risk Findings

### P1 - "Verify on-device" currently overpromises

`SecurityView` exposes a `Verify on-device` action, but the implementation checks the current attestation status and nonce presence, then displays a metadata message. It does not cryptographically verify the report, certificate chain, signature, nonce binding, model hash, transcript hash, or hardware identity.

Code reference:

- `NEARPrivateChat/AppShellView.swift:6354` exposes `Verify on-device`.
- `NEARPrivateChat/AppShellView.swift:6439` implements `verifyProofOnDevice`.
- The implementation says: "This checks proof metadata, not answer truth."

Recommendation:

- Either rename to `Check proof metadata` for now, or implement a real verifier and keep `Verify on-device`.
- A real verifier should return structured states: `verified`, `stale`, `model mismatch`, `signature failed`, `missing nonce`, `unsupported proof`.
- The UI should distinguish "proof fetched" from "proof verified."

### P1 - Per-message attestation is not generation-time provenance yet

Assistant messages now show an attestation chip when the current attestation snapshot covers the message's model. That is a good UI direction, but it derives the chip from the **current global snapshot**, not from a proof captured at the time the message was generated.

Code reference:

- `NEARPrivateChat/AppShellView.swift:7652` computes `messageAttestationStatus`.
- `NEARPrivateChat/AppShellView.swift:7658` builds `AttestationStatus(snapshot: chatStore.attestationSnapshot, selectedModelID: modelID)`.

Why this matters:

- If the user refreshes attestation after the answer, older messages may appear covered by newer proof.
- If the model changes, stale/fresh status can be misleading per turn.
- A public/signed export needs proof-per-turn or a transcript-level proof chain.

Recommendation:

- Add generation-time attestation metadata to `ChatMessage`: proof ID/hash, fetched timestamp, model hash, nonce, route, verification state.
- On send completion, bind the assistant message to the proof snapshot used for that route.
- Header shield can stay global; message shields should be per-turn.

### P1 - Streaming still has no mobile-grade resume/retry contract

The private chat SSE path opens a single `URLSession.shared.bytes(for:)` stream and throws if the stream ends before `response.completed`.

Code reference:

- `NEARPrivateChat/PrivateChatAPI.swift:507` starts `streamResponse`.
- `NEARPrivateChat/PrivateChatAPI.swift:548` uses `URLSession.shared.bytes`.
- `NEARPrivateChat/PrivateChatAPI.swift:574` throws when the server never sends completion.

Recommendation:

- Define the server/client contract for reconnect: event IDs, response ID, idempotency key, last emitted output index, retry window.
- On cell handoff, app background, or short network drop, resume the stream instead of failing the answer.
- At minimum, persist partial text and show `Connection interrupted - resume` rather than a hard failure.

### P1 - Setup can still select a blocked advanced route

Setup is much better, but `applySetupProfile` still sets `selectedModel = ModelOption.ironclawMobileModelID` when `wantsIronclaw` is true. Route readiness blocks later sends, but the onboarding promise can still land the user on a path that immediately needs repair.

Code reference:

- `NEARPrivateChat/ChatStore.swift:1660` applies setup profile.
- `NEARPrivateChat/ChatStore.swift:1667` selects IronClaw Mobile for IronClaw preference.
- `NEARPrivateChat/AppShellView.swift:8606` shows a route-readiness recovery card later in the composer.

Recommendation:

- Use `AppSetupReadinessSnapshot` to gate the setup CTA itself.
- If IronClaw is not ready, setup should say `Configure IronClaw` or select private chat and place Agent behind an explicit setup task.
- Do not make the user's first post-setup state be a recovery state.

### P2 - Council is visible, but not yet controllable

Council now streams multiple models and renders a grouped surface. That is a real improvement. The missing functionality is user control during the slow/waiting phase.

Code reference:

- `NEARPrivateChat/ChatStore.swift:3394` starts council turns.
- `NEARPrivateChat/ChatStore.swift:3439` runs model streams in a task group.
- `NEARPrivateChat/AppShellView.swift:1420` renders `CouncilResponseGroup`.

Gaps:

- No per-model time-to-first-token.
- No per-model cancel.
- No `good enough - synthesize now` action.
- No visible synthesizer picker.
- No disagreement export or `Ask the dissenters`.
- No confidence/uncertainty artifact per model.

Recommendation:

- Add a Council run model: `queued`, `connecting`, `firstTokenAt`, `streaming`, `done`, `failed`, `cancelled`.
- Allow early synthesis once at least two useful answers have completed.
- Keep raw model answers one tap away from synthesis.

### P2 - Agent still needs a first-class run surface

IronClaw is better protected now because hosted handoff preflight tells the user what data is being sent.

Code reference:

- `NEARPrivateChat/ChatStore.swift:3029` builds hosted handoff preflight.
- `NEARPrivateChat/ChatStore.swift:3042` lists disclosed prompt/project items.

The missing piece is the agent run UX:

- No persistent in-thread progress card.
- No pause/resume.
- No inline approval gates for expensive/destructive work.
- No concise "last 3 steps + current step" presentation.

Recommendation:

- Treat Agent like a run object, not just a model route.
- Add `AgentRun`, `AgentStep`, `ApprovalRequest`, and a compact in-thread card.
- Store enough run state to resume after app backgrounding.

### P2 - Privacy-preserving telemetry exists, but product instrumentation is minimal

The app now has a private telemetry store that writes local aggregate counters and defaults upload to disabled.

Code reference:

- `NEARPrivateChat/PrivateTelemetry.swift:238` defines disabled-by-default telemetry settings.
- `NEARPrivateChat/PrivateTelemetry.swift:259` records aggregate counters.
- `NEARPrivateChat/NEARPrivateChatApp.swift:167` records setup goal/completion telemetry.

Gaps:

- It is mostly wired to setup, not actual feature adoption or failure modes.
- No visible user setting was confirmed in this pass.
- `uploadEnabled` is always false in diagnostics export, which is privacy-safe but means success metrics are local only unless manually exported.

Recommendation:

- Make the telemetry strategy explicit in product copy and docs:
  - Option A: no telemetry, only local diagnostics export.
  - Option B: opt-in on-device daily aggregates.
  - Option C: differential privacy/k-anonymous rollups later.
- Track local counters for route readiness blocks, stream failures, attestation taps, share-proof actions, Council early stops, Agent approvals, and setup recovery.

## Feature / Functionality Matrix

| Area | Current state | Verdict | Next fix |
| --- | --- | --- | --- |
| Auth and sign-in | OAuth/session/shared-link flow exists from earlier work. | Mostly solid | Keep session token and developer affordances behind disclosure. |
| Onboarding | Goal text, use cases, Beginner/Power, context style, defaults, setup plan, first-run draft. | Much improved | Gate advanced routes by actual readiness; reduce passive hero chips. |
| First-run utility | `firstRunDraft` turns goal/use case into an immediate prompt. | Good | Add concrete examples from project guide/welcome project. |
| Home | Search, filter strip, Resume row, Projects header with New, project icons/colors, date groups. | Stronger | Add project context-menu actions: Rename, Color/Icon, Archive. |
| Search | Searches chats, projects, and sources. | Good | Add ranking rules and empty search state. |
| Recents | Top 3 Resume cards plus grouped lists. | Good | Consider pinned/favorites and explicit "last active" metadata. |
| Composer | Attachment shelf, focus modes, dynamic placeholder, slash commands, route readiness card, haptics. | Strong | Add Council thinking tray; refine selected/off chip contrast. |
| Drafts | Draft persistence appears implemented across selection changes and app lifecycle. | Good | Test background/kill/restore and multi-project draft scopes. |
| Long paste | Large paste staging exists. | Good direction | Confirm threshold/copy and attachment UX in simulator. |
| Model picker | Search and attestation state are present; Auto-Council work exists. | Improved | Add favorites, last verified timestamp, cost/latency chips, Customize Council flow. |
| Council | Parallel streaming, grouped response, synthesis prompt. | Promising | Add early synthesis, TTFT, cancel per model, disagreement actions. |
| Project Context | Three tabs, sources/files, instructions/notes, add link, freshness labels. | Much improved | Add "what this project knows" summary and real stale/sync semantics. |
| Source/file library | File library is now less dominant but still present. | Partial | Remove explanatory card; use pull-to-refresh/header refresh only. |
| Chat header | Attestation surfaces and model/source/project context have been promoted. | Good | Bind proof state to each turn, not just current snapshot. |
| Chat titles | Needs simulator verification. | Unknown/likely partial | Ensure auto-title after first assistant response and fallback rename flow. |
| Branch/regenerate | Response variant UI exists. | Good start | Confirm regenerate preserves sibling branches and never destroys previous answer. |
| Attestation | Header/message/sheet proof surfaces exist. | Product-defining but risky | Replace metadata check with real verifier; add QR/public verifier path. |
| Signed export | Signed transcript support exists from prior work. | Good | Add Signed Snippet and signed publish page. |
| Sharing | Public link preview/expiry UI exists; proof is passed into preview. | Improved | Verify expiry is enforced server-side; add visible shared-context banner. |
| Hosted IronClaw | Handoff preflight discloses prompt/project data before hosted use. | Good | Add run state, approvals, pause/resume, and in-thread progress. |
| Settings | Setup rerun and developer-ish settings remain available. | Partial | Keep endpoint/callback/auth under Developer disclosure. |
| Telemetry | Local aggregate counter store exists; setup records events. | Partial | Decide product telemetry policy and expose it to users. |
| Accessibility | Some labels, hints, haptics, Reduce Motion handling. | Partial | Full VoiceOver/Dynamic Type/contrast pass needed. |
| Color system | Semantic tokens exist, but `brandBlue` remains heavily used. | Partial | Finish semantic-token migration and cap blue per screen. |
| Platform surfaces | No App Intents, WidgetKit, ActivityKit/Live Activity found in app code. | Missing | Ship after iPhone core: intents first, Live Activity second. |
| Tests | Core test suite is larger and covers route/setup/telemetry/export. | Better | Add fake API streaming tests and UI tests for onboarding/composer/security. |

## What Is Now Working Better

### Setup has real utility

The original critique was fair: onboarding looked like setup but did not do enough. Current code now has:

- Beginner/Power choice in `UserSetupExperienceMode`.
- Setup goal text in `UserSetupProfile.goalText`.
- Goal-derived first-run draft in `UserSetupProfile.firstRunDraft`.
- Starter project name/instructions for research, agents, team projects, or project mode.
- `ChatStore.applySetupProfile` starts a new conversation and places the first prompt in the composer.

This is the right direction. The remaining design issue is that onboarding should feel like a **launchpad**, not a preferences survey. Every setup choice should visibly affect the "Ready on day one" preview.

### Route readiness is substantially safer

The send path now checks hosted handoff and route readiness before clearing the draft. This addresses one of the worst prior failure modes.

Key behavior:

- `sendDraft` snapshots text/attachments.
- Hosted handoff preflight appears before a hosted IronClaw route.
- Route readiness blocks before draft clearing.
- A route readiness recovery card appears in the composer.

Remaining question:

- Does every non-send path obey the same safety contract? Regenerate and edit paths now appear covered, but simulator tests should verify draft preservation and recovery for every route.

### Home has become a real workspace

Home now has the structure the design audits were pushing toward:

- Command header with one primary Ask action.
- Secondary Agent/Project actions under the hero.
- Search across chats/projects/sources.
- Filter strip instead of 64pt filter tiles.
- Resume row.
- Projects with identity.
- Grouped conversation list.

This is close to the right information diet. The largest remaining issue is project management: long-press project rows still need Rename, Color/Icon, and Archive.

### Composer is now competitive

The composer has most of the expected product behaviors:

- Focus modes.
- Placeholder changes by mode.
- Attachment shelf.
- Slash commands.
- Route recovery.
- Haptics.
- Reduce Motion handling.

The missing piece is Council-specific wait state. A normal model stream can get away with a spinner; Council cannot. Council has multiple concurrent agents in the user's head, so the UI needs to show what each one is doing.

### Attestation is finally visible

The product claim is now visible in the UI, not buried:

- Header status.
- Model/security proof surfaces.
- Assistant message chips.
- Security sheet facts.
- Share proof JSON.

But the proof system now needs to grow up from "display attestation report" to "verifiable evidence chain." That means real local verification, generation-time binding, public verifier compatibility, and proof formats that can travel outside the app.

## Recommended Build Packets

### Packet 1 - Truthful Attestation

Goal: remove any gap between proof copy and proof implementation.

Tasks:

- Rename current `Verify on-device` to `Check proof metadata` unless a real verifier is implemented.
- Define `AttestationVerificationResult`.
- Store proof metadata per assistant turn.
- Bind signed transcript export to per-turn proofs.
- Add tests for model mismatch, stale proof, missing nonce, failed signature placeholder, and unsupported proof.

Claude prompt:

> Audit the NEAR Private Chat attestation implementation. Identify every UI string that implies cryptographic verification. Then design and implement a real `AttestationVerificationResult` model with truthful states. If full cryptographic verification is blocked by missing proof-chain details, rename the UI to metadata-check copy and leave TODOs with the exact verifier inputs required.

### Packet 2 - Mobile Streaming Resilience

Goal: make private chat survive normal cellular/network interruptions.

Tasks:

- Add stream run IDs and idempotency keys.
- Persist partial response state.
- Decide retry policy for no-visible-output, mid-output, and after-completed failures.
- Add a `Resume response` UI state.
- Add fake API tests for stream interruption.

Claude prompt:

> Review `PrivateChatAPI.streamResponse` and `ChatStore.streamResponseWithFallback`. Propose and implement the smallest client-side resilience layer possible without server changes. Then write a server-contract note for true SSE resume: event ID, previous response ID, idempotency key, and last visible output offset.

### Packet 3 - Council Control Surface

Goal: make Council feel fast and controllable, not like waiting for several black boxes.

Tasks:

- Track per-model queued/connecting/first-token/done/failed/cancelled states.
- Show TTFT and elapsed time.
- Add "Synthesize now" once two models have useful output.
- Add per-model cancel.
- Add raw/synthesis toggle.
- Add disagreement artifact later.

Claude prompt:

> Build a Council run state model that supports per-model status, time-to-first-token, cancellation, and early synthesis. Keep the UI compact: last state visible in the chat, full details in an expandable tray. Avoid making users manually assemble a council before first use.

### Packet 4 - Agent Runs As First-Class Objects

Goal: make IronClaw agent work inspectable and interruptible.

Tasks:

- Define `AgentRun`, `AgentStep`, and `AgentApprovalRequest`.
- Render an in-thread card: sticky current step, last 3 steps, expandable history.
- Add pause/resume/cancel.
- Add inline approval gates before hosted/destructive actions.
- Persist run state across app background.

Claude prompt:

> Convert the current IronClaw agent flow from a sheet/model route into a first-class run surface. Add a compact in-thread progress card, pause/resume/cancel states, and inline approval gates. Keep hosted handoff privacy preflight intact.

### Packet 5 - Setup Readiness Gate

Goal: prevent onboarding from routing users into an immediate error.

Tasks:

- Feed real readiness into `AppSetupPlan`.
- If IronClaw/NEAR Cloud/Council are not ready, change the setup CTA to configure or choose a safe default.
- Make Beginner mode visibly hide advanced surfaces until enabled.
- Add a setup smoke test: complete setup -> first prompt can be sent without repair.

Claude prompt:

> Review setup end-to-end. Ensure every setup completion path lands the user in a sendable state. If a selected route is not ready, either repair during setup or choose a private default and show the advanced setup task separately.

### Packet 6 - Feature Discoverability Without Density

Goal: expose NEAR's unique features without turning Home into a control panel.

Tasks:

- Add `Quick Council` on assistant-message long press.
- Add `Copy with proof` / Signed Snippet.
- Add visible shared-context banner for chats opened via share.
- Add project row context actions: Rename, Color/Icon, Archive.
- Add project "what this project knows" summary.

Claude prompt:

> Implement the two highest-leverage contextual actions: Quick Council and Copy with proof. They should appear in message context menus, not as permanent chrome. Then add project row management actions to the existing context menu.

## Deep Research Questions For Claude

Use these as research prompts. Claude should answer with evidence, dated source links, screenshots where possible, and a recommendation that maps back to the iOS codebase. These are not requests to mutate the repo unless explicitly assigned as build tasks.

### 1. Attestation verifier contract

- What exact fields does NEAR AI Cloud's current attestation report expose as of May 2026?
- Which parts can be verified fully offline on iOS?
- Which parts require a web verifier or remote certificate chain fetch?
- Does the report bind model hash, runtime hash, nonce, signing algorithm, gateway identity, hardware identity, and transcript hash?
- What should the app call each verification level without overpromising?
- What should `Verify on-device` mean in a consumer app?

### 2. Public verifier and Signed Snippet format

- What is the minimal signed snippet format that survives Slack, email, Notes, and Twitter/X?
- Should a snippet be plain text plus URL, JSON-LD, or both?
- What privacy risks come from stable verifier URLs?
- Should verifier links be revocable, expiring, or content-addressed?
- How do Signal safety numbers, 1Password signed manifests, Tinfoil/Phala/Chutes verifiers, and GitHub signed commits frame proof for non-experts?

### 3. Per-turn proof provenance

- What is the right data model for binding an assistant message to proof-at-generation?
- Should the app store full attestation JSON per turn, a hash pointer, or a transcript-level chain?
- How should proof state display when a chat mixes verified and unverified turns?
- What should export do when one turn is stale or mismatched?

### 4. Council UX and latency

- How do Copilot Model Counsel, Poe multi-bot, Perplexity research, and any current multi-model apps expose waiting/partial answers?
- Should synthesis wait for all models, first N models, or a timeout?
- What is the best mobile pattern for "stop waiting and synthesize now"?
- Should per-model raw answers be stacked, tabbed, or side-by-side on iPhone?
- How should disagreements be detected: model self-report, synthesizer extraction, semantic diff, or user-marked?

### 5. Council output reliability

- How should the app prevent "Disagreements" sections from becoming theater?
- What evaluation prompts reliably extract substantive disagreement rather than stylistic variation?
- Can confidence be usefully displayed per claim without misleading users?
- What should a "model disagreement report" include for legal/finance/medical/high-stakes use?

### 6. Streaming resilience

- What is the best SSE resume contract for mobile LLM streaming?
- How do ChatGPT, Claude, Perplexity, and Gemini behave on cell handoff or app background?
- What should the client do when the stream ends without `response.completed` after visible output?
- What should be retried automatically versus shown as user-controlled `Resume`?
- What retry behavior avoids duplicate user messages or duplicate assistant output?

### 7. Hosted agent privacy and approvals

- What data should a hosted IronClaw handoff disclose before sending?
- Which agent actions require inline approval: file writes, git commits, network calls, paid API calls, public link creation, deletion?
- How do Claude Code mobile, Codex mobile, Linear agents, and GitHub Copilot agents present progress and approvals?
- What is the best compact run card for iPhone?

### 8. Setup and progressive disclosure

- Do users prefer Beginner/Power setup choices or contextual reveal after first few chats?
- What should be hidden in Beginner mode: Agent, Council, NEAR Cloud, Developer settings, model picker complexity?
- What is the minimum setup path that still proves the app's unique value?
- What should the "Welcome project" contain without feeling fake or demo-only?

### 9. Home/search information architecture

- How do leading AI iOS apps rank search across chats, files, projects, and shared links?
- Should NEAR search be global from Home only, or available in every chat/project?
- What scopes should search expose: transcript, title, project name, file name, source host, note content, attestation metadata?
- What should empty search states recommend?

### 10. Project/source freshness

- What freshness signal matters for RAG trust: upload time, sync time, source modified time, crawl time, or last-used time?
- How should stale source warnings be phrased without scaring users?
- Should project hero show "What this project knows" as generated summary?
- How should the app handle files that were uploaded but never indexed?

### 11. Privacy-preserving telemetry

- Should NEAR Private Chat ship no telemetry, local-only diagnostics, opt-in aggregate telemetry, or differential privacy?
- What product questions must be answered to improve the app without inspecting prompts?
- Which counters are safe: setup completed, route blocked, attestation viewed, proof shared, stream failed, Council used, Agent launched?
- How should the app explain telemetry without undermining "private chat"?

### 12. iOS system surfaces

- Which App Intents should ship first: Start verified chat, Ask selected text, Open shared link, Verify current chat?
- What privacy risks appear when exposing selected text to App Intents?
- Is a Lock Screen Live Activity for attestation freshness useful or confusing?
- What should widgets show without leaking private prompt text?
- What is the smallest Mac follow-up after iPhone is solid?

### 13. Accessibility and motion

- What Dynamic Type sizes break the current Home, composer, model picker, Security sheet, and Project Context?
- Which color pairs fail WCAG AA in the current Off-White/Sky/Blue palette?
- What haptic events are expected versus annoying?
- How should Reduce Motion change chip selection, send activation, attestation state changes, and sheet transitions?

### 14. Positioning and category ownership

- Which four features should be the public demo spine: persistent shield, Signed Snippet, Council, Agent, Live Activity, verifier page, Quick Council?
- What language explains TEE attestation in two sentences without sounding like crypto marketing?
- What does the app do that ChatGPT/Claude/Gemini cannot credibly copy quickly?
- Which features are parity work and which are category-making?

## Suggested Claude Research Output Format

Ask Claude to return:

1. `Current competitor evidence`: dated links and screenshots where possible.
2. `Implication for NEAR`: one paragraph.
3. `Recommended product behavior`: exact UX/copy.
4. `Implementation notes`: Swift models/views/APIs likely touched.
5. `Risks`: privacy, security, accessibility, or reliability.
6. `Test plan`: unit/UI/manual checks.

## Immediate Priority Line

Do these before more visual polish:

1. Make attestation proof copy truthful, then implement real verification.
2. Bind proof state to each assistant turn.
3. Add mobile stream resilience or at least resumable failure UX.
4. Gate setup by route readiness so first-run never lands in repair mode.
5. Add Council wait controls: TTFT, cancel one model, synthesize now.
6. Add in-thread Agent run card with pause/resume/approval.
7. Add fake API and UI tests for the above.

After that, resume polish:

1. Signed Snippet.
2. Quick Council.
3. Project context actions and project summary.
4. Semantic color token migration.
5. App Intents.
6. Lock Screen Live Activity.
7. Mac proof panel after iPhone is genuinely solid.
