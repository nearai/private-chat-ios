# NEAR Private Chat iOS - Next Design Pass Brief

Date: 2026-05-25  
Canonical update: this brief is superseded for the next design push by `NEARPrivateChatIOS-agentic-default-design-spec-2026-05-25.md`.

Use the new spec's principle first:

> Agentic by default. Configurable on demand.

The earlier "connect capabilities, not routes" framing is still valid, but it is now subordinate to a stronger product rule: the app should work beautifully out of the box, choose the right capability automatically, and expose configuration only when the user needs to recover or unlock a missing capability.

Where this brief and the agentic-default spec conflict, the spec wins. `P0.4 - Setup As A Launchpad` is reversed: Setup is deleted as a destination. `P0.7 - Capability Center Shell` is demoted from a destination to a row inside `Power Tools`; capability recovery cards are the actual user-facing surface.

Implementation note: the first code pass has now shipped the orchestrator, Setup deletion, Home/composer collapse, Power Tools demotion, NEAR Cloud app-grounding fix, canonical proof footer state, and the explicit chat-window Model/Council/Effort controls. Use `NEARPrivateChatIOS-agentic-default-implementation-tracker-2026-05-25.md` for current status and remaining work.

Correction note: prior language saying "default model/route: orchestrator decides per prompt" is superseded. The default model is GLM (`zai-org/GLM-5.1-FP8`). Users must be able to choose GLM, IronClaw, Cloud models, Council, and reasoning effort directly from chat. The orchestrator classifies, attaches context, and surfaces recovery/offers; it does not silently switch the chosen route.

Status: Resynthesis of:

- `NEARPrivateChatIOS-elite-design-product-audit-2026-05-25.md`
- `NEARPrivateChatIOS-elite-design-audit-v2-upgrade-2026-05-25.md`
- `claude-design-screen-improvement-prompt-2026-05-25.md`
- `latest-screenshot-index-2026-05-25.md`
- current source review and the 8:38 setup-card screenshot
- `NEARPrivateChatIOS-capability-setup-next-level-pass-2026-05-25.md`
- `NEARPrivateChatIOS-live-app-review-next-pass-2026-05-25.md`

This brief is now a supporting execution note. The recommended working spec is `NEARPrivateChatIOS-agentic-default-design-spec-2026-05-25.md`.

Live-app correction: the 2026-05-25 live Simulator review supersedes the older screenshot-only assumptions. Use `NEARPrivateChatIOS-live-app-review-next-pass-2026-05-25.md` and `review-artifacts/live-app-review-2026-05-25/` as the first source of truth before applying any older audit recommendation.

## The Decision

The v2 upgrade is directionally right, but the live app has already improved substantially. Home, Project Context, model search labels, proof truthfulness, and overflow grouping are better than the older screenshot pack suggested.

The next pass should not start with platform moats like Live Activities or another broad visual reset. It should start with **agentic state truth and capability recovery**:

1. Add the AskOrchestrator contract so route/tool/proof mismatches are resolved before send.
2. Make NEAR AI Cloud and agent connections appear as just-in-time recovery cards.
3. Keep capabilities visible inside Power Tools, not as a top-level destination.
4. Preserve the improved Home and Project Context.
5. Keep proof language truthful.
6. Then continue typography/color/intensity cleanup.

Only after those land should the team move to CouncilArtifact, AgentRunCard, Share proof footer, and then Live Activities / BackgroundTasks.

North star:

> Ask first. Proof always. Advanced power exactly when needed.

2026-05-25 capability addendum:

> Connect capabilities, not routes.

The next pass should make Private Inference, NEAR AI Cloud, agent runs, and Council feel like one coherent capability system without exposing that system as a default destination. Private chat must work immediately; Cloud and agent setup should appear only when needed inside the same conversation. Use `NEARPrivateChatIOS-agentic-default-design-spec-2026-05-25.md` as the source of truth; use `NEARPrivateChatIOS-capability-setup-next-level-pass-2026-05-25.md` only for implementation details that do not conflict.

## Hard Rules For The Next Pass

### 1. Screenshot Truth First

Do not make final design calls from stale screenshots. A fresh live app pack now exists:

`review-artifacts/live-app-review-2026-05-25/`

Use it first. The older 2026-05-24 screenshots are historical reference only.

Before shipping the design push, regenerate the live set against the post-push build:

- setup top
- home
- new chat composer
- chat thread with proof shield
- model picker
- council picker
- Cloud search result
- IronClaw search result
- project context
- security/proof
- connect agent / agent workspace
- share
- account/settings
- capabilities / Cloud + IronClaw connection states

Save them under:

`review-artifacts/live-app-review-2026-05-25-post-design-push/`

Update `latest-screenshot-index-2026-05-25.md` after capture.

### 2. One Saturated Brand Blue Per Scene

The v2 memo is right to tighten the previous "three blues" rule. For the next pass:

- One saturated action blue per screen/scene.
- Brand blue is for the single primary CTA only.
- Proof uses trust colors.
- Project context uses project color.
- Cloud route uses neutral grey, not blue.
- Destructive uses system red.
- Warning/stale uses amber/orange.

Current source still has many direct `Color.brandBlue` references. This is design debt, not just code debt.

### 3. Fetched Is Not Verified

Use a proof state machine:

```swift
enum ProofState {
    case unknown
    case verifying
    case verified
    case stale
    case mismatch
    case private_
    case proxied
    case unverified
}
```

Never show the word `Verified` unless the proof state is actually `.verified`.

If the app only has metadata, use:

- `Proof fetched`
- `Metadata checked`
- `Proof stale`
- `Proof unavailable`

Do not call metadata inspection `Verify on-device`.

### 4. One Screen, One Primary Action

Every screen needs one obvious primary action.

Examples:

- Terms: `Continue`
- Home: `Ask NEAR`
- Composer: send/stop
- Security: `Verify proof` or `Fetch proof`
- Share: `Create private invite` or `Enable public link`, not both as equally loud
- Agent: `Start run`
- Council: `Ask Council` / `Synthesize now` only when contextually valid

### 5. Advanced Features Are Contextual Upgrades

On iPhone:

- Council is not a top-level destination.
- Proof is not a top-level destination.
- Shared is a filter/state under chats.
- Agent is a contextual upgrade unless product requires it as a fourth destination.
- Search is a mode.

Recommended destination model:

- Chats
- Projects
- Settings

If Agent must be top-level later, add a fourth. Do not exceed four.

## Immediate P0 Work

### P0.1 - State Truth Fixes

Resolved structurally by Sprint 1 of the agentic-default spec: build `AskOrchestrator` so route/tool/proof mismatches are resolved before send. The old standalone mismatch list remains useful as regression fixtures:

- Setup shows `Ready: LLM Council` while CTA says `Ask a private question`.
- `Skip setup` applies defaults and starts a draft instead of skipping.
- Selecting `Claude Opus 4.7` appears to put the user into `LLM Council 2`.
- Hosted IronClaw selection says `Mobile agent ready`.
- Header proof chip can truncate to `No model`.

Deliverable:

- Shared orchestrator decision object.
- Snapshot tests for orchestrator route/tool/proof decisions.
- Tests for Cloud single-model vs Council selection behavior.
- Tests for IronClaw hosted/mobile empty-state copy.

### P0.2 - Post-Push Live Screenshot Pack

After the design implementation lands, capture:

- sign-in / terms
- home default
- home with project selected
- composer private
- model picker
- Cloud search result
- Cloud selected / missing-key state
- IronClaw search result
- Hosted IronClaw missing-workstation state
- inline agent recovery / agent run
- Project Context
- Security/Proof
- Account top
- Power Tools capability row and recovery states

Update `latest-screenshot-index-2026-05-25.md`.

### P0.3 - Typography Ladder And Setup Cleanup

The `Ready on day one` screenshot is the proof that the app lacks a strict type ladder. The card had large metadata values fighting the section title and the route title.

The immediate code patch reduced that specific issue, but the real task is system-wide:

| Role | Suggested style |
| --- | --- |
| Screen title | `title3.semibold` / platform nav title |
| Hero title | `title2.bold` only in true hero |
| Section header | `subheadline.semibold`, secondary |
| Row title | `callout.semibold` |
| Row body | `subheadline.medium` or `caption.medium` depending density |
| Metadata label | `caption2.bold`, uppercase, secondary |
| Metadata value | `caption.semibold`, primary |
| Chip text | `caption2.semibold` |
| Primary button | `headline.semibold` |
| Raw proof/code | `caption.monospaced` |

Apply this first to:

- Setup plan card
- Model picker rows
- Security proof facts
- Project source/file rows
- Council status/header
- Agent run status/card

### P0.4 - Delete Setup As A Destination

Agentic-default reverses the earlier launchpad proposal.

Target:

```text
Sign in -> Terms -> Home
```

Everything setup used to ask is inferred or deferred:

- Goal: inferred from the first prompt.
- Beginner/Power: default simple; Power Tools opt-in in Account.
- Council: offered inline when prompt is decision-shaped.
- Agent: offered inline when prompt is task-shaped.
- Default model/route: GLM by default; user-chosen model/Council/IronClaw/Cloud route wins.
- Saved-material behavior: deferred to first project creation or attachment.

`Run Setup Again` becomes `Reset defaults`.

The old goal-textarea idea is not lost; it becomes the composer empty state and verb-first suggestion chips.

### P0.5 - Proof Truth Layer

Build one `ProofCapsule` and use it everywhere:

- chat header
- assistant messages
- Security sheet
- share preview
- export footer later

States:

| State | Label | Color role | Meaning |
| --- | --- | --- | --- |
| `unknown` | `Proof unknown` | neutral | pre-fetch / no check has run yet |
| `verifying` | `Checking proof` | neutral animated | verification in progress |
| `verified` | `Verified` | trust green | signature/measurement check passed |
| `stale` | `Proof stale` | amber | proof too old |
| `mismatch` | `Proof mismatch` | amber | model/route/proof mismatch |
| `private_` | `Private` | neutral | private route, no signed proof this turn |
| `proxied` | `Privacy proxy` | neutral | Cloud route through privacy proxy |
| `unverified` | `Unverified` | neutral | route carries no proof claim |

Canonical two-sentence explainer:

> Your messages are processed inside a secure chip running sealed code, so the server operator cannot read what you send. NEAR Private Chat checks the chip's signed proof for this session, so you can verify the private route instead of trusting a promise.

If the implementation cannot yet cryptographically verify the proof, update the copy to say metadata/proof fetched rather than verified.

### P0.6 - Semantic Color And Intensity Tokens

Create real semantic tokens before polishing individual screens.

Color roles:

- `actionPrimary`
- `actionSecondary`
- `proofVerified`
- `proofFetched`
- `proofStale`
- `proofMismatch`
- `routePrivate`
- `routeCloud`
- `projectAccent`
- `danger`
- `surfaceBase`
- `surfacePanel`
- `surfaceRaised`
- `textPrimary`
- `textSecondary`
- `borderSubtle`

Intensity roles:

- `surfaceBase`
- `rowPlain`
- `panelSoft`
- `rowSelected`
- `commandPrimary`
- `proofArtifact`
- `dangerZone`

Definition of done:

- No direct `Color.brandBlue` in feature views.
- `brandBlue` only exists in the token definition file.
- Each main screen has at most one `commandPrimary`.

### P0.7 - Power Tools Capability Row

Demote the earlier Capabilities destination. Keep `Power Tools` as the disclosure because it sets the expectation that these are opt-in advanced controls.

Inside collapsed Power Tools, add a row:

`Capabilities & integrations ->`

That detail screen may list:

- Private inference
- NEAR AI Cloud
- Agent connection
- Council

Each row/card shows status, one-sentence purpose, primary action, trust-boundary copy, and last checked / needs setup / unavailable state.

Critical copy rule:

> NEAR Cloud is a capability, not the same privacy/proof boundary as NEAR Private verified inference.

Do not imply Cloud or hosted IronClaw turns have private proof unless the selected route actually has proof.

### P0.8 - Capability Recovery Cards

Missing dependencies must produce persistent recovery cards. These cards are the primary user-facing capability surface in agentic-default:

- Cloud model without key -> `Connect NEAR Cloud`
- Agent task without hosted workstation -> `Connect agent`
- Council with too few models -> `Customize Council`

The recovery action should deep-link into Account -> Power Tools -> relevant setup row while preserving the user's draft and attachments.

## P1 Work After P0 Lands

### P1.1 - Home Density Reduction

Target:

- Ask remains primary.
- Resume appears immediately for returning users.
- Search becomes a mode or compact nav action.
- Filters are low-chrome.
- Project rows show icon/color/name and one clean metadata line.
- Project context menu includes Open, Rename, Color/Icon, Archive.

Do not let Home become the control center for Agent/Council/Proof. Those are contextual upgrades.

### P1.2 - Composer Simplification

Default composer:

- input
- attachment
- send/stop

No source chip in the default state. Model, Council, and Effort are visible chat controls; source/web/file routing stays inferred or behind recovery/Details.

The orchestrator is the user's primary answer to:

> What does this answer know?

If the orchestrator detects an unresolved conflict, it shows one inline recovery chip below the input. Tapping it opens the relevant recovery sheet or Project Sources tab.

### P1.3 - CouncilArtifact

Replace grouped message wrapper with a designed artifact.

Sections:

- synthesis/direct answer
- model agreement strip
- disagreement, conditional only
- next step
- raw answers collapsed

Actions:

- `Synthesize now` when at least two models have usable output.
- `Ask dissenters` only when a contested claim exists.
- `Export disagreement` later.

Do not render empty disagreement sections.

### P1.4 - AgentRunCard

Current source already has approval cards and a compact status strip. The next step is quality and legibility:

- sticky current step
- last 3 completed steps
- inline approval card
- pause/resume/stop
- final summary: Outcome / Files / Tests / External actions / Open risks

Risk approvals should be tiered:

- readonly
- local-write
- network
- destructive

Avoid per-tool approval fatigue.

### P1.5 - Share And Export Proof Footer

If proof is the differentiator, it must survive sharing.

Every shared/exported artifact should show:

- proof state
- model
- route/platform
- freshness
- proof short code
- verify link

If no proof exists, show `No verification attached`, not silence.

### P1.6 - Accessibility And Haptics

Horizontal chips must have an accessibility fallback.

Use `ViewThatFits` where possible:

- normal: horizontal chip row
- accessibility: menu or vertical stack

Centralize haptics:

```swift
enum HapticEvent {
    case send
    case approvalRequested
    case approvalConfirmed
    case proofVerified
    case proofMismatch
    case routeChangedToCloud
    case councilSynthesisReady
}
```

Ban ad hoc `UIImpactFeedbackGenerator` calls inside feature code.

## P2 / Category Moats

These are important but should not outrank the core visual pass:

- Agent Live Activity on Lock Screen.
- `BGContinuedProcessingTask` for long agent runs.
- Signed Snippet.
- Public verifier page.
- App Intents.
- Widget.
- Mac proof panel after iPhone is excellent.

Do not let these distract from the P0 visual/product truth work.

## Updated Claude Design Prompt

Use this prompt for Claude or another design agent:

> You are doing the next elite design pass for NEAR Private Chat iOS. Use `NEARPrivateChatIOS-agentic-default-design-spec-2026-05-25.md` as the implementation brief and the live simulator captures as evidence. The product principle is: agentic by default, configurable on demand. Do not add a permanent Web/Files/Research capability strip, do not keep Setup as a destination, and do not make Capabilities a top-level surface. Design the default flow as Home -> Ask NEAR -> composer with explicit Model/Council/Effort controls -> selected route runs with orchestrator-supplied context/recovery -> answer footer capsule. Agent, Cloud key, project context conflicts, and hosted workstation setup appear as inline recovery/offers; Council is also a visible user choice. Keep Project Context mostly intact, keep SF Pro, one saturated blue per scene, truthful Verification language, and Power Tools as the disclosure home for advanced controls.

## Updated Codex Build Prompt

Use this prompt for implementation:

> Implement against the current live app state using `NEARPrivateChatIOS-agentic-default-design-spec-2026-05-25.md` as source of truth. First build `AskOrchestrator(prompt, project?, attachments?, history?) -> route/tools/proofPosture/failurePlan` and tests for project files, latest/web, agentic verbs, decision questions, attachments, Cloud-only models, and missing setup, with explicit user route choice preserved. Then collapse Home and Composer: one Ask NEAR action, visible Model/Council/Effort controls, one input, attach, send/stop, no default focus/source strip. Delete Setup as a destination; sign-in goes Terms -> Home. Demote Capabilities to Account -> Power Tools -> Capabilities & integrations. Add inline recovery cards for missing Cloud key, missing agent connection, and project-context conflicts. Keep Project Context mostly intact and verify by launching Simulator and recapturing `review-artifacts/live-app-review-2026-05-25-post-design-push/`.

## Acceptance Criteria

The next design pass is complete when:

- There is a fresh full screenshot set from the current build.
- There is no default Setup destination; sign-in goes Terms -> Home.
- Capabilities live inside Account -> Power Tools -> Capabilities & integrations, not as a top-level surface.
- NEAR Cloud and agent connection are easy to connect from inline recovery cards without digging through Account internals.
- Missing Cloud key / missing agent connection produce persistent recovery cards that preserve the draft.
- Route/tool/proof decisions cannot mismatch because they come from the orchestrator.
- `Verified` only appears when proof state is actually verified.
- The UI distinguishes `unknown`, `verifying`, `verified`, `stale`, `mismatch`, `private_`, `proxied`, and `unverified`.
- Cloud, Private, phone agent, and hosted agent each have distinct route/trust labels in Details/Power Tools.
- No Cloud UI implies private proof unless the selected route actually provides it.
- Feature views no longer reference `Color.brandBlue` directly.
- Each screen has at most one saturated blue primary action.
- Home shows Ask and Resume without dashboard clutter.
- Composer default state has Model/Council/Effort, input, attachment, send/stop.
- Council output is specified as an artifact, not grouped chat bubbles.
- Agent run is specified as a timeline card, not only a status strip.
- Horizontal chip rows have accessibility fallbacks.
- Share/export proof footer spec is ready.

## What To Avoid

- Do not add another hero gradient to every screen.
- Do not introduce more chips to solve density problems.
- Do not use `Verified` as a vibe word.
- Do not make Council or Proof top-level iPhone destinations.
- Do not start with Live Activity demos.
- Do not treat typography bugs as one-off fixes; enforce the ladder.
- Do not rely on 2026-05-24 screenshots for final calls.

## Practical First PR Sequence

1. Screenshot capture/index script and fresh screenshots.
2. AskOrchestrator and route/tool/proof decision tests.
3. Setup deletion: Sign-in -> Terms -> Home; `Run Setup Again` -> `Reset defaults`.
4. Persistent recovery cards for Cloud and agent connection.
5. Power Tools capability row; no Power Tools -> Capabilities rename.
6. ProofState + ProofCapsule + copy cleanup.
7. Semantic tokens + remove direct `brandBlue` from Home/Composer/Security first.
8. Typography ladder pass on Model Picker, Security, Project rows, AgentRunCard.
9. Composer default collapse and Details override.
10. CouncilArtifact skeleton as inline offer.
11. AgentRunCard skeleton.

This sequence turns the design pass from "taste critique" into a controlled product-quality upgrade.
