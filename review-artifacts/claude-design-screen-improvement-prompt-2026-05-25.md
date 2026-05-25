# Claude Design Prompt - NEAR Private Chat iOS Screen Improvement Pass

Update: use `review-artifacts/NEARPrivateChatIOS-live-app-review-next-pass-2026-05-25.md`, `review-artifacts/NEARPrivateChatIOS-next-design-pass-brief-2026-05-25.md`, and `review-artifacts/NEARPrivateChatIOS-capability-setup-next-level-pass-2026-05-25.md` as the source-of-truth execution briefs. This prompt remains useful background, but those briefs supersede it where priorities differ.

Use this as a design/research prompt. Do not start by adding features. Start by making the existing app feel calmer, more premium, and more internally consistent.

## Context

We are building NEAR Private Chat iOS: a private/verifiable AI chat app with Project Context, LLM Council, IronClaw Agent, sharing, and TEE attestation/proof surfaces.

The app is already powerful. The current problem is design quality:

- typography hierarchy is inconsistent
- too many controls are shown too early
- too many surfaces use the same blue/card language
- setup still feels like a preferences form
- proof/security still feels too diagnostic
- Council and Agent are powerful but not yet presented as elite artifacts
- many cards have equal visual weight, so nothing feels primary

Target design principle:

> Ask first. Proof always. Advanced power exactly when needed.

Capability principle:

> Connect capabilities, not routes.

Private chat must work immediately. NEAR AI Cloud and IronClaw should be optional capabilities the user can connect, test, and use inside the same conversation without digging through Account plumbing.

## What To Review

Review the app screen by screen, using current simulator screenshots and source:

- Setup / onboarding
- Capabilities / Cloud + IronClaw connection states
- Home
- New chat / empty composer
- Chat thread
- Model picker
- Council picker and Council answer
- Project Context
- Security / Attestation
- Share
- Agent / IronClaw
- Account / settings

Latest screenshot sources to check first:

- `review-artifacts/live-app-review-2026-05-25/`
- `review-artifacts/NEARPrivateChatIOS-live-app-review-next-pass-2026-05-25.md`
- `/Users/abhishekvaidyanathan/Desktop/Screenshot 2026-05-25 at 8.38.12 am.png`
- `review-artifacts/latest-smoke/iphone17pro-2026-05-25-after-setup-card-font-fix.png`
- `review-artifacts/latest-smoke/iphone17pro-2026-05-25-setup-polish-booted.png`
- `review-artifacts/latest-smoke/iphone17pro-2026-05-25-setup-polish.png`
- `review-artifacts/latest-smoke/iphone17pro-2026-05-25-post-four-docs.png`
- `review-artifacts/screenshots-2026-05-24-fresh/`

Use `review-artifacts/latest-screenshot-index-2026-05-25.md` as the screenshot inventory. The 2026-05-24 pack is historical reference only. Regenerate missing post-push screens before making final calls.

Live app bugs to treat as P0 design/product-truth issues, not mere copy polish:

- Setup can show `Ready: LLM Council` while the CTA says `Ask a private question`.
- `Skip setup` currently applies defaults, opens chat, and preloads a draft; decide whether this is a true skip or a named quick-start action.
- Selecting a Cloud single model can leave the header in `LLM Council 2` state.
- Hosted IronClaw can show `Mobile agent ready` empty-state copy.
- The proof chip can truncate into ambiguous labels like `No model`.
- Cloud icons can inherit irrelevant accessibility labels such as `Mostly Cloudy`.

Use the screenshot issue below as a representative bug:

> In Setup's "Ready on day one" card, metadata values are visually too large compared with surrounding UI. Labels and values compete, wrapping is awkward, and the card reads like a broken table rather than a calm preview.

Look for similar issues across all screens.

## Design Tasks

### 1. Typography Audit

Create a typography ladder for the whole app:

- screen title
- hero title
- section header
- row title
- row body
- metadata label
- metadata value
- chip text
- button label
- code/raw proof text

Then identify every place the current UI violates that ladder.

Pay special attention to:

- setup cards
- model picker rows
- Project Context rows
- proof/security facts
- Council answer sections
- Agent status strips
- chat metadata/breadcrumbs

### 2. Visual Hierarchy Audit

For each main screen, answer:

- What is the one primary action?
- What is secondary?
- What is diagnostic/developer detail?
- What can be hidden until needed?
- What can move into a menu or disclosure?

The output should include a "keep / reduce / hide / redesign" table.

### 3. Screen Improvement Concepts

Propose a concrete redesign for:

#### Setup

- Make setup feel like a launchpad, not settings.
- Keep goal text, Beginner/Power, and source style.
- Hide advanced route/capability setup unless the user opens `Connect more capabilities`.
- Make "Ready on day one" compact, readable, and consequence-based.
- CTA must always match the selected route and be sendable.

#### Capabilities

- Add a user-facing surface for Private Inference, NEAR AI Cloud, IronClaw Agent, and Council.
- Make Cloud and IronClaw easy to connect, test, and recover from when missing.
- Show capability status without raw developer plumbing.
- Clearly separate Private proof from Cloud/hosted-agent route labels.
- Deep-link here from model rows, Agent setup, and route-readiness recovery cards.

#### Home

- Ask is primary.
- Resume should be visible immediately for returning users.
- Search should not visually compete with Ask.
- Filters should be low-chrome.
- Project rows should have color/icon and a clean one-line metadata format.

#### Composer

- Default state should show input, attachment, source chip, and send.
- Full focus row can be hidden behind source chip or Power mode.
- Empty state should use concrete prompt examples, not generic feature chips.
- Council and Agent should appear as contextual upgrades.

#### Model Picker

- Reduce database-browser feel.
- Make Verified/Private, cost, speed, and favorites legible.
- Council tab should default to Auto-Council, with Customize secondary.

#### Project Context

- Rename/position as Project if appropriate.
- Show "what this project knows."
- Make Sources/Instructions/Notes calm and obvious.
- Make source state clear: ready, indexing, stale, failed, not used.

#### Security / Attestation

- Make proof result the first thing.
- Separate "proof fetched" from "proof verified."
- Move endpoint/signing/raw JSON behind Advanced.
- Use trust color, not action blue.
- Write a two-sentence explanation for non-technical users.

#### Council Answer

- Make it a designed artifact, not grouped chat bubbles.
- Sections: Direct answer, Agreement, Disagreement, Next step.
- Hide empty sections.
- Add model status/TTFT and "Synthesize now."

#### Agent

- Convert status strip into a run timeline card.
- Show current step, last 3 steps, approvals, pause/resume/stop.
- Final summary should include files, commands, tests, and risks.

### 4. Interaction Polish

Specify motion/haptic rules:

- send button activation
- focus chip selection
- attestation status change
- Council model state transition
- Agent approval/run state
- sheet presentation/dismissal

Respect Reduce Motion.

### 5. Accessibility

Audit for:

- Dynamic Type issues
- grey text contrast
- color-only state
- icon-only controls
- horizontal chip overflow
- VoiceOver labels/hints

Produce a test matrix for at least:

- default text size
- xxxLarge
- accessibility medium
- Reduce Motion on
- VoiceOver on
- light and dark mode

## Output Format

Return:

1. `Executive diagnosis`: 5-8 bullets.
2. `Typography ladder`: exact font roles and sizes/styles.
3. `Screen-by-screen findings`: include severity and reason.
4. `Top 10 design changes`: ordered by leverage.
5. `Component specs`: Setup plan card, Home hero, Composer, Model row, Proof capsule, Council artifact, Agent run card.
6. `Capability setup specs`: Private Inference, NEAR AI Cloud, IronClaw Agent, Council cards; status states; recovery paths.
7. `Copy improvements`: exact replacement copy.
8. `Implementation map`: Swift files/components likely touched.
9. `Test plan`: screenshot and accessibility checks.

## Constraints

- Keep SF Pro.
- Ignore external brand guidelines except for useful iconography ideas.
- Do not add decorative blobs/orbs.
- Do not make a marketing landing page.
- Keep iPhone excellent first. Mac can come later.
- Preserve advanced features, but progressively disclose them.
- Make proof/trust the unique design signature.

## North-Star Screens

The redesigned app should make these screenshots feel inevitable:

1. A calm Setup screen where the first answer is clearly ready.
2. A Home screen with one obvious Ask action and a fast Resume path.
3. A Chat screen with a quiet persistent proof shield.
4. A Council answer that looks like a high-confidence decision artifact.
5. A Security screen where a non-technical user understands "proof, not promise."
6. An Agent run card that feels controlled, inspectable, and safe.
