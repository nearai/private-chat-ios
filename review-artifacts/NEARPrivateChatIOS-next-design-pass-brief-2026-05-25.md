# NEAR Private Chat iOS - Next Design Pass Brief

Date: 2026-05-25  
Status: Resynthesis of:

- `NEARPrivateChatIOS-elite-design-product-audit-2026-05-25.md`
- `NEARPrivateChatIOS-elite-design-audit-v2-upgrade-2026-05-25.md`
- `claude-design-screen-improvement-prompt-2026-05-25.md`
- `latest-screenshot-index-2026-05-25.md`
- current source review and the 8:38 setup-card screenshot
- `NEARPrivateChatIOS-capability-setup-next-level-pass-2026-05-25.md`
- `NEARPrivateChatIOS-live-app-review-next-pass-2026-05-25.md`

This brief is the recommended working spec for the next design pass. It is intentionally more execution-shaped than the v2 upgrade memo.

Live-app correction: the 2026-05-25 live Simulator review supersedes the older screenshot-only assumptions. Use `NEARPrivateChatIOS-live-app-review-next-pass-2026-05-25.md` and `review-artifacts/live-app-review-2026-05-25/` as the first source of truth before applying any older audit recommendation.

## The Decision

The v2 upgrade is directionally right, but the live app has already improved substantially. Home, Project Context, model search labels, proof truthfulness, and overflow grouping are better than the older screenshot pack suggested.

The next pass should not start with platform moats like Live Activities or another broad visual reset. It should start with **state truth and capability connection**:

1. Fix live route/setup/proof mismatches.
2. Add a user-facing Capabilities surface.
3. Make NEAR AI Cloud and IronClaw connectable from obvious places.
4. Preserve the improved Home and Project Context.
5. Keep proof language truthful.
6. Then continue typography/color/intensity cleanup.

Only after those land should the team move to CouncilArtifact, AgentRunCard, Share proof footer, and then Live Activities / BackgroundTasks.

North star:

> Ask first. Proof always. Advanced power exactly when needed.

2026-05-25 capability addendum:

> Connect capabilities, not routes.

The next pass should make Private Inference, NEAR AI Cloud, IronClaw Agent, and Council feel like one coherent capability system. Private chat must work immediately; Cloud and IronClaw should be optional capabilities the user can connect, test, and use inside the same conversation. Use `NEARPrivateChatIOS-capability-setup-next-level-pass-2026-05-25.md` as the detailed spec for the new `Capabilities` surface, Cloud/IronClaw connection flows, route/trust labels, and missing-dependency recovery cards.

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
    case none
    case fetched
    case verifying
    case verified
    case stale
    case mismatch
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

- Setup: `Start from this goal`
- Home: `Ask`
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

Fix the live mismatches from `NEARPrivateChatIOS-live-app-review-next-pass-2026-05-25.md`:

- Setup shows `Ready: LLM Council` while CTA says `Ask a private question`.
- `Skip setup` applies defaults and starts a draft instead of skipping.
- Selecting `Claude Opus 4.7` appears to put the user into `LLM Council 2`.
- Hosted IronClaw selection says `Mobile agent ready`.
- Header proof chip can truncate to `No model`.

Deliverable:

- Shared route/setup state source.
- Snapshot tests for setup CTA/readiness combinations.
- Tests for Cloud single-model vs Council selection behavior.
- Tests for IronClaw hosted/mobile empty-state copy.

### P0.2 - Post-Push Live Screenshot Pack

After the design implementation lands, capture:

- setup
- home default
- home with project selected
- composer private
- model picker
- Cloud search result
- Cloud selected / missing-key state
- IronClaw search result
- Hosted IronClaw missing-workstation state
- Connect Agent
- Project Context
- Security/Proof
- Account top
- Capabilities states

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

### P0.4 - Setup As A Launchpad

The current setup is better than before, but still too much like a preference form.

Target:

- One question: `What should NEAR help with first?`
- Goal textarea.
- Three example chips that prefill the textarea.
- One quiet `Use web` toggle.
- One optional `Advanced` disclosure.
- One state-derived CTA.
- After Start: open chat with prompt prefilled and ready to send.

Move out of the default path:

- Beginner/Power
- Council preference
- Agent preference
- default model
- developer controls
- route details

Those can live in Advanced or Settings.

Engineering requirement:

- CTA text and selected route must be computed from the same state object.
- Add snapshot tests for setup states so `Private Chat selected / Start Council` never regresses.

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
| `none` | `No proof` | neutral | no proof fetched |
| `fetched` | `Proof fetched` | neutral / blue-grey | report exists but not cryptographically verified |
| `verifying` | `Checking proof` | neutral animated | verification in progress |
| `verified` | `Verified` | trust green | signature/measurement check passed |
| `stale` | `Proof stale` | amber | proof too old |
| `mismatch` | `Proof mismatch` | red | model/route/proof mismatch |

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

### P0.7 - Capability Center Shell

Add a user-facing `Capabilities` surface. It can be a sheet or Settings sub-screen in the first pass, but it must be reachable from Account, route-readiness recovery, Cloud-locked model rows, and Agent setup.

Minimum cards:

- Private Inference
- NEAR AI Cloud
- IronClaw Agent
- Council

Each card must show:

- status
- one-sentence purpose
- primary action
- secondary action where useful
- trust-boundary copy
- last checked / needs setup / unavailable state

Critical copy rule:

> NEAR Cloud is a capability, not the same privacy/proof boundary as NEAR Private verified inference.

Do not imply Cloud or hosted IronClaw turns have private proof unless the selected route actually has proof.

### P0.8 - Capability Recovery Cards

Missing dependencies must produce persistent recovery cards, not only banners:

- Cloud model without key -> `Connect NEAR AI Cloud`
- Hosted IronClaw without endpoint -> `Connect IronClaw`
- Council with too few models -> `Customize Council`

The recovery action should deep-link into the relevant `Capabilities` card or setup sub-flow while preserving the user's draft and attachments.

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
- one source chip
- send/stop

Hide full focus row behind source chip or Power mode.

The project/source chip is the user's primary answer to:

> What does this answer know?

Tap project/source chip -> Project Sources tab.

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

If no proof exists, show `No proof attached`, not silence.

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

> You are doing the next elite design pass for NEAR Private Chat iOS. Use the actual live app captures in `review-artifacts/live-app-review-2026-05-25/` and `NEARPrivateChatIOS-live-app-review-next-pass-2026-05-25.md` first; older screenshot audits are background only. The app is already better than the old pack implied, so do not restart Home or Project Context. Prioritize live state truth: setup readiness/CTA mismatch, Skip behavior, Cloud single-model vs Council selection, Hosted IronClaw showing Mobile readiness, proof-chip truncation, Connect Agent lacking a real action, and Account hiding Cloud/IronClaw setup. Then design Capabilities for Private Inference, NEAR AI Cloud, IronClaw Agent, and Council. Keep SF Pro, one saturated primary blue per scene, truthful proof language, route/trust labels, and persistent recovery cards.

## Updated Codex Build Prompt

Use this prompt for implementation:

> Implement against the current live app state. First fix the live mismatches: Setup readiness label must match CTA/selected route; Skip must either truly skip or be renamed Use Defaults; selecting a Cloud model must not silently switch into Council unless the UI says Add to Council; Hosted IronClaw must not show Mobile agent ready; proof chip labels must not truncate into unclear text. Then add a Capabilities shell for Private Inference / NEAR AI Cloud / IronClaw Agent / Council and persistent recovery cards for missing Cloud key and hosted IronClaw endpoint. Keep the improved Home and Project Context structure. Verify by launching the app in Simulator and recapturing `review-artifacts/live-app-review-2026-05-25-post-design-push/`.

## Acceptance Criteria

The next design pass is complete when:

- There is a fresh full screenshot set from the current build.
- There is a user-facing Capabilities shell with Private Inference, NEAR AI Cloud, IronClaw Agent, and Council cards.
- NEAR Cloud and IronClaw are easy to find/connect without digging through Account internals.
- Missing Cloud key / missing IronClaw endpoint produce persistent recovery cards that preserve the draft.
- Setup is one screen, one question, one primary CTA.
- CTA text cannot mismatch selected route because it is derived from the same state.
- `Verified` only appears when proof state is actually verified.
- The UI distinguishes `none`, `fetched`, `verifying`, `verified`, `stale`, and `mismatch`.
- Cloud, Private, IronClaw Mobile, and IronClaw Hosted each have distinct route/trust labels.
- No Cloud UI implies private proof unless the selected route actually provides it.
- Feature views no longer reference `Color.brandBlue` directly.
- Each screen has at most one saturated blue primary action.
- Home shows Ask and Resume without dashboard clutter.
- Composer default state has input, attachment, source chip, send/stop.
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
2. Setup simplification and CTA single-source-of-truth tests.
3. Capabilities shell and Account `Power Tools` -> `Capabilities` rename.
4. Persistent route-readiness recovery cards for Cloud and IronClaw.
5. ProofState + ProofCapsule + copy cleanup.
6. Semantic tokens + remove direct `brandBlue` from Setup/Security/Home first.
7. Typography ladder pass on Setup, Model Picker, Security, Project rows.
8. Composer source-chip simplification.
9. CouncilArtifact skeleton.
10. AgentRunCard skeleton.

This sequence turns the design pass from "taste critique" into a controlled product-quality upgrade.
