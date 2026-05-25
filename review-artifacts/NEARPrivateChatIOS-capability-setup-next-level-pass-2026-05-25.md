# NEAR Private Chat iOS - Capability Setup + Next-Level Product Pass

Date: 2026-05-25
Status: New next-pass spec after reviewing the latest live app run, setup flow, Account power-tool code, model routing code, IronClaw route handling, and the existing design audit stack.

This supplements:

- `NEARPrivateChatIOS-live-app-review-next-pass-2026-05-25.md`
- `NEARPrivateChatIOS-next-design-pass-brief-2026-05-25.md`
- `NEARPrivateChatIOS-elite-design-audit-v2-upgrade-2026-05-25.md`
- `claude-design-screen-improvement-prompt-2026-05-25.md`

Live-app correction: the actual Simulator review in `review-artifacts/live-app-review-2026-05-25/` is the controlling evidence for current UI state. This capability spec should be applied after fixing the live state mismatches called out there: setup readiness/CTA mismatch, Cloud single-model selection becoming Council, Hosted IronClaw using Mobile-agent copy, and ambiguous proof-chip truncation.

## Executive Thesis

The app should stop presenting NEAR AI Cloud, IronClaw, Council, web, projects, and proof as separate concepts the user must mentally assemble.

The next pass should make them feel like one coherent system:

> Private chat works immediately. Cloud and IronClaw are optional capabilities you connect, test, and then use inside the same conversation.

The product needs a **Capability Center**: a simple, premium, status-driven surface that shows what is ready now, what needs connection, what is safe/private/verified, and what can run together.

The key design principle:

> Connect capabilities, not routes.

Users do not want to "configure hosted endpoints" or "add route keys." They want:

- `Private answers are ready`
- `NEAR Cloud models are connected`
- `IronClaw agent is connected`
- `Proof is fresh`
- `This turn used Cloud / Private / IronClaw`

Everything else should be progressive disclosure.

## Screenshot Evidence Reviewed

Freshest evidence:

- `review-artifacts/live-app-review-2026-05-25/` - actual app running in Simulator on 2026-05-25. Includes setup, new chat, model picker, Council picker, more menu, Security without proof, Home, Account, Cloud search, Cloud-selected state, IronClaw search, Hosted IronClaw selected state, Connect Agent, New Project, and Project Context.
- `NEARPrivateChatIOS-live-app-review-next-pass-2026-05-25.md` - controlling live-app product/design review.
- `/Users/abhishekvaidyanathan/Desktop/Screenshot 2026-05-25 at 10.10.06 am.png` - simulator home screen; confirms current icon install state, not in-app UI.
- `review-artifacts/latest-smoke/iphone17pro-2026-05-25-after-setup-card-font-fix.png` - current setup top after the font fix. Better, but still setup-heavy and route-oriented.
- `/Users/abhishekvaidyanathan/Desktop/Screenshot 2026-05-25 at 8.38.12 am.png` - bad `Ready on day one` card evidence. The specific typography issue was patched, but it exposed the larger problem: metadata values were competing with actual screen hierarchy.

Older historical app evidence:

- `screenshots-2026-05-24-fresh/00-setup.png`
- `screenshots-2026-05-24-fresh/01-home.png`
- `screenshots-2026-05-24-fresh/02-new-chat-composer.png`
- `screenshots-2026-05-24-fresh/03-model-picker.png`
- `screenshots-2026-05-24-fresh/04-model-picker-council.png`
- `screenshots-2026-05-24-fresh/05-agent-workspace.png`
- `screenshots-2026-05-24-fresh/07-project-context.png`
- `screenshots-2026-05-24-fresh/08-project-library.png`
- `screenshots-2026-05-24-fresh/09-account-settings.png`
- `screenshots/03-chat-thread.png`
- `screenshots/05-source-mode-menu.png`
- `screenshots/06-chat-more-menu.png`
- `screenshots/10-security-attestation.png`
- `screenshots/11-share-collaboration.png`
- `screenshots/13-action-menu-demo.png`

Important caveat: the live app pack is current enough for next-pass direction, but the design push still needs a post-implementation recapture before final judgment.

## Current Product Diagnosis

The app is powerful, but the mental model is not yet productized.

Today a user encounters:

- Private Chat
- NEAR Private route
- NEAR Cloud models
- IronClaw Mobile
- IronClaw Hosted
- Agent
- Council
- Projects
- Sources
- Library
- Guide
- Saved
- Security
- Attestation
- Web
- Research
- Account power tools

Those are real capabilities, but the app surfaces them as parallel concepts. A new user has to infer:

- which thing is required,
- which thing is optional,
- which thing is private,
- which thing is verified,
- which thing needs a key,
- which thing needs a hosted endpoint,
- which thing can be used together,
- and whether missing setup means the app is broken.

That is the core product issue.

The next pass should convert the app from a route dashboard into a capability system.

## The New Product Model

Use four user-facing capability cards:

1. **Private Inference**
   - Always first.
   - Default ready state.
   - Owns proof / TEE / attestation.
   - User-facing language: `Private answers`, `Proof`, `Verified when available`.

2. **NEAR AI Cloud**
   - Optional model expansion.
   - Requires a Cloud key or account connection.
   - Must never be implied to have the same TEE/private proof boundary unless that is actually true.
   - User-facing language: `More models`, `Cloud key`, `External route`, `Not private proof`.

3. **IronClaw Agent**
   - Optional action/workflow capability.
   - Split internally into phone runtime and hosted workstation, but do not make the user learn that before they need it.
   - User-facing language: `Agent`, `Phone ready`, `Workstation connected`, `Tools verified`.

4. **Council**
   - Not a separate setup dependency.
   - A mode that uses the available model capabilities.
   - User-facing language: `Compare models`, `Private lineup`, `Cloud lineup`, `Mixed lineup`.

This model lets NEAR Cloud and IronClaw both be "running in the app" without forcing them into separate products. They become capability states available to the composer, model picker, agent sheet, Council builder, and per-message route/proof labels.

## What "Running At Once" Should Mean

Not four root tabs. Not four dashboards.

"Private + Cloud + IronClaw running at once" should mean:

- Capability Center shows all relevant systems connected or ready.
- The composer can start a private answer, a Cloud-model answer, a Council answer, or an IronClaw run from the same chat.
- The model picker shows which models require Cloud and whether the key is connected.
- The Agent sheet knows whether the phone runtime and hosted workstation are available.
- Messages show per-turn route labels:
  - `Private`
  - `Private verified`
  - `Cloud`
  - `IronClaw Mobile`
  - `IronClaw Hosted`
  - `Council mixed`
- The chat header shows a compact capability line only when non-default capabilities are active:
  - `Private ready`
  - `Cloud connected`
  - `Agent connected`
  - `Proof stale`
- Council can use Private and Cloud members together, but the synthesis artifact must say which legs were private and which were Cloud.
- Agent runs can appear in-thread as cards without pretending they are normal assistant messages.

## Critical Truth Boundary

This is the copy rule that prevents future trust damage:

> NEAR Cloud is a capability, not the same privacy/proof boundary as NEAR Private verified inference.

Every place Cloud appears should answer:

- Is this key connected?
- Does this turn leave the private verified route?
- Is there proof attached to this turn?
- If proof is unavailable, is that because the selected route cannot provide it?

Current code already has good route notices in `ChatStore.selectedRouteNotice`, including:

- Cloud is not NEAR Private TEE-attested.
- all-private Council lineups can fetch attestation.
- mixed Council lineups include Cloud legs.

The next pass should promote this truth from hidden notices into visible route labels and proof states.

## Capability Center

Create a new screen or sheet reachable from:

- Account top section
- setup completion screen
- route-readiness recovery card
- model picker locked Cloud row
- Agent sheet when hosted workstation is missing
- chat header capability pill

Working title: **Connections** or **Capabilities**. I prefer **Capabilities** because it is more user-centered than "Connections" and less technical than "Power Tools."

### Layout

Navigation title:

`Capabilities`

Subtitle:

`Private chat is ready now. Connect Cloud and IronClaw when you need more models or agent runs.`

Top status strip:

`Private ready · Cloud not connected · Agent phone ready`

Cards:

1. `Private Inference`
2. `NEAR AI Cloud`
3. `IronClaw Agent`
4. `Council`

Each card gets:

- icon
- title
- one-sentence purpose
- status label
- primary action
- secondary action
- trust boundary line
- last checked / needs setup / verified timestamp

### Private Inference Card

Title:

`Private Inference`

Purpose:

`Ask sensitive questions through the private route and attach proof when available.`

Status examples:

- `Ready`
- `Proof fetched`
- `Verified`
- `Proof stale`
- `Proof unavailable`

Actions:

- `Check proof`
- `View proof`

Trust line:

`Best for sensitive chats. Proof applies only to private-route turns.`

### NEAR AI Cloud Card

Title:

`NEAR AI Cloud`

Purpose:

`Connect a Cloud key for more models, larger lineups, and Council coverage.`

Status examples:

- `Not connected`
- `Key saved`
- `Testing key`
- `Connected`
- `Key failed`
- `Quota or plan issue`

Actions:

- `Connect Cloud`
- `Test key`
- `Remove key`

Trust line:

`Cloud turns are separate from private verified inference. Show a Cloud label on every Cloud message.`

Required screens:

- signup / get-key explainer
- paste key
- test key
- choose default Cloud model
- show what changes in model picker

Important copy:

`Use NEAR AI Cloud for extra models. Use Private when you need proof.`

Avoid:

- `Private Cloud`
- `Verified Cloud`
- `Secure Cloud`
- any copy that makes Cloud sound TEE-attested unless the runtime actually verifies it.

### IronClaw Agent Card

Title:

`IronClaw Agent`

Purpose:

`Run planning, repo, git, shell, and test tasks from your phone with approval gates.`

Status examples:

- `Phone ready`
- `Workstation not connected`
- `Endpoint saved`
- `Tools verified`
- `Token needed`
- `Bridge failed`

Actions:

- `Connect workstation`
- `Verify tools`
- `Start agent run`
- `Disconnect`

Trust line:

`Agent runs are action-capable. You approve risky steps before they run.`

Required screens:

- simple IronClaw signup/connect explainer
- hosted endpoint field
- token field
- test bridge
- verify tools
- project binding
- approval tier explainer

Important copy:

`Phone agent is ready. Connect a workstation when you want repo, git, shell, and test work.`

Avoid:

- `Shell + Git + Web` as the primary description.
- `Hosted endpoint required` without a next step.
- raw tunnel examples in the first card.

### Council Card

Title:

`Council`

Purpose:

`Compare multiple models, show agreements, and surface disagreements.`

Status examples:

- `Private lineup ready`
- `Cloud key unlocks more models`
- `Mixed lineup`
- `Needs two models`

Actions:

- `Ask Council`
- `Customize lineup`

Trust line:

`Council can mix private and Cloud models. Each model leg gets its own route label.`

## First-Run Setup Redesign

The current setup has moved in the right direction, but it still asks the user to configure the app before they have felt the value.

New default setup:

1. User signs in.
2. Setup asks one thing:
   `What should NEAR help with first?`
3. Three example chips prefill the field.
4. One optional toggle:
   `Use web`
5. One optional disclosure:
   `Connect more capabilities`
6. Primary CTA:
   `Start private chat`
   or state-derived equivalent.

Do not default to asking:

- Beginner vs Power
- Council
- Agent
- default model
- advanced source routing
- NEAR Cloud key
- IronClaw endpoint

Those belong in `Connect more capabilities` or post-first-run prompts.

### Setup Path A - Normal User

Visible:

- goal field
- examples
- private ready line
- web toggle
- CTA

After first chat:

- show a small non-blocking card:
  `Want more models or an agent? Connect Cloud or IronClaw.`

### Setup Path B - Power User

If they open `Connect more capabilities`:

- show compact checklist:
  - `Private inference: ready`
  - `NEAR AI Cloud: connect key`
  - `IronClaw Agent: connect workstation`
  - `Council: available after two models`

Power setup should never block the first chat. A user can skip all Cloud/IronClaw setup and still have the app work.

### Setup Path C - Dependency Not Ready

Because some screens may be conceptual before dependencies exist, design the states anyway:

- `Unavailable in this build`
- `Coming soon`
- `Needs account setup`
- `Needs hosted workstation`
- `Key saved, model list unavailable`
- `Endpoint saved, tools not verified`

These are not failure screens. They are honest product states.

## Account Settings Redesign

Current Account is a mixed index:

- identity
- setup rerun
- diagnostics
- chat settings
- NEAR Cloud key
- IronClaw bridge
- advanced model params
- developer-ish plumbing

The next pass should split Account into:

1. `Profile`
2. `Capabilities`
3. `Chat defaults`
4. `Data and sharing`
5. `Developer`

### Account Top

Keep:

- avatar
- name
- email/account ID

Add:

- compact capability summary:
  `Private ready · Cloud connected · Agent phone ready`

Replace:

- `Run Setup Again` as a large section.

With:

- `Change first-run preferences` inside Settings, secondary.
- `Capabilities` as the main setup/connection entry.

### Power Tools Rename

Rename `Power Tools` to `Capabilities`.

`Power Tools` sounds like advanced machinery. `Capabilities` says what the app can do.

Current quick actions are good raw material:

- `Add NEAR Cloud key`
- `Connect IronClaw bridge`
- `Advanced model params`
- `Run diagnostics`

But they should become:

- `Connect NEAR AI Cloud`
- `Connect IronClaw`
- `Model defaults`
- `Run health check`

### Developer Disclosure

Move raw fields behind Developer:

- endpoint/callback/auth scheme
- advanced params
- diagnostic internals
- local/LAN debug explanation
- optional thread ID

The normal Capability Center can still launch the specific field when needed, but the default settings page should not read like a dev console.

## Composer Next Pass

The composer should not expose all capability concepts at once.

Default composer:

- input
- attachment
- one source/context chip
- send/stop

Secondary capability chip row, only when relevant:

- `Private`
- `Cloud`
- `Agent`
- `Council`

But avoid a permanent row of five modes for every user. The current `Auto · Web · Files · Links · Research` row is strong for demos but heavy for daily use.

Recommended:

- Default: one chip `Auto` or project/source chip.
- Tap chip opens `Sources` menu.
- Type `/` opens commands:
  - `/cloud`
  - `/private`
  - `/council`
  - `/agent`
  - `/verify`
  - `/project`

When Cloud or IronClaw is not connected:

- selecting the mode should not dead-end.
- show inline recovery:
  - `Connect Cloud to use this model`
  - `Connect IronClaw workstation for hosted runs`
  - buttons open Capability Center to the right card.

## Model Picker Next Pass

Model picker should answer three questions quickly:

1. Can I use this model now?
2. Is it private/proof-capable, Cloud, or Agent?
3. What do I need if it is locked?

Rows should use:

- model name
- provider/route chip
- cost/access chip
- proof-capable indicator only when true
- `Connect Cloud` affordance for Cloud-locked rows

Do not show a soup of:

- `LLM Council`
- `Council 4`
- `Curated`
- `Web on`
- `Starter plan`
- `Upgrade: 29 more`

Council builder should default to auto lineup:

- `Auto Council`
- `Customize`
- lineup members with route labels:
  - `GLM 5.1 · Private`
  - `Qwen · Cloud`
  - `IronClaw · Agent`

If the lineup is mixed, show:

`Mixed route: some answers will not have private proof.`

## Agent Next Pass

The Agent sheet is visually strong but still too much of a standalone product.

Rewrite the surface around user intent:

Title:

`Start an Agent`

Subtitle:

`Give it a task. It uses your project context and asks before risky actions.`

Capability state:

- `Phone agent ready`
- `Workstation connected`
- `Tools verified`
- `No project selected`

If launched inside a project:

`Using IronClaw Phone QA · 1 link · 3 notes`

If workstation missing:

show a setup card:

`Connect workstation for repo, git, shell, and tests`

Actions:

- `Connect IronClaw`
- `Verify tools`
- `Start phone-safe plan`

The current `Coding / Local Test / GitHub` pills should become starter templates:

- `Plan code change`
- `Run tests`
- `Review PR`

The user should never wonder whether those pills are labels or buttons.

## Chat Header + Per-Turn Route Labels

The current chat header puts a lot of trust in a single model chip. For the multi-capability future, the app needs per-turn truth.

Add per-message route/proof labels:

- `Private`
- `Verified`
- `Proof fetched`
- `Cloud`
- `Agent`
- `Council mixed`

Header state should summarize the current route only:

- model / mode chip
- proof capsule
- project breadcrumb

For mixed Council:

- header says `Council`
- artifact shows per-model route labels
- proof state cannot become globally green unless every relevant leg is proof-verified

For IronClaw:

- message card should show `IronClaw Hosted` or `IronClaw Mobile`
- agent run card shows action/progress state
- approvals are explicit and tiered

## Security + Attestation Next Pass

Security is one of the app's strongest differentiators, but it is still a report view rather than a proof product.

Reframe:

Title:

`Proof`

Top result:

- `Verified`
- `Proof fetched`
- `Proof stale`
- `Proof mismatch`
- `No proof for this route`

Primary action:

- `Check proof`

Secondary actions:

- `Share proof`
- `Copy proof ID`
- `Open verifier` when available

Copy:

`Private proof applies to private-route turns. Cloud and hosted agent turns show route labels instead.`

Replace:

`Model attestations: 1`

With:

`GLM 5.1-FP8 · proof fetched`

or:

`GLM 5.1-FP8 · verified`

depending on actual state.

## Project Context Next Pass

Project Context is close, but should support capability setup too.

Add a slim project capability line:

`Used by chat and agents · 1 link · 3 notes`

When IronClaw launches from a project:

- project binding should be automatic.
- no `No project selected` card.
- show `Using this project`.

Rename tabs:

- `Sources`
- `Files`
- `Instructions`
- `Notes`

If four tabs feel heavy on iPhone, merge `Sources` and `Files` into `Knowledge` later, but the current terms are clearer than `Library / Guide / Saved`.

Source rows should show freshness:

- `synced today`
- `not checked`
- `stale`

This matters for both RAG credibility and agent context.

## Share / Export Next Pass

Sharing must preserve trust boundaries.

Public link flow should preview:

- title
- message count
- source count
- proof state
- route labels included
- account info excluded
- whether public link can expire

Add:

- `Invite people`
- `Create public link`
- `Share proof only`

For Cloud or Agent turns:

- show route label in shared transcript.
- do not imply private proof.

For Private proof:

- include proof footer or proof ID.

## New Screen Inventory For Next Design Pass

Design these screens even before every dependency works:

1. `Setup - simple`
2. `Setup - connect capabilities disclosure`
3. `Capabilities - all disconnected except Private`
4. `Capabilities - Cloud connected, Agent phone ready`
5. `Capabilities - Cloud connected, IronClaw workstation verified`
6. `Connect NEAR AI Cloud - get key`
7. `Connect NEAR AI Cloud - paste/test key`
8. `Connect IronClaw - phone ready, workstation missing`
9. `Connect IronClaw - endpoint/token`
10. `Connect IronClaw - tools verified`
11. `Composer - default private`
12. `Composer - selecting Cloud when key missing`
13. `Composer - selecting Agent when workstation missing`
14. `Model picker - Cloud locked rows`
15. `Council builder - mixed route labels`
16. `Agent sheet - project-bound`
17. `Agent run card - waiting for approval`
18. `Proof sheet - no proof for Cloud`
19. `Proof sheet - verified private route`
20. `Share sheet - proof-aware preview`

## Data Model Proposal

Add an app-level capability model. It can start as view-model-only and later move deeper.

```swift
enum AppCapabilityID: String, CaseIterable, Codable, Hashable {
    case privateInference
    case nearCloud
    case ironclawPhone
    case ironclawHosted
    case council
}

enum AppCapabilityStatus: Equatable, Hashable {
    case ready
    case unavailable(reason: String)
    case needsAccount
    case needsKey
    case needsEndpoint
    case needsToken
    case testing
    case failed(message: String)
    case connected(lastChecked: Date?)
    case verified(lastChecked: Date?)
}

enum RouteTrustBoundary: String, Codable, Hashable {
    case privateProofCapable
    case cloudExternal
    case mobileAgent
    case hostedAgent
    case mixedCouncil
}

struct AppCapabilitySnapshot: Equatable, Hashable {
    var id: AppCapabilityID
    var title: String
    var status: AppCapabilityStatus
    var trustBoundary: RouteTrustBoundary
    var primaryAction: CapabilityAction?
    var secondaryAction: CapabilityAction?
    var lastCheckedAt: Date?
}
```

The key is not the exact enum naming. The key is centralizing readiness so Setup, Account, Model Picker, Agent, and RouteReadinessRecoveryCard stop inventing separate status language.

## Code Observations

Existing code already has the ingredients:

- `ChatRouteKind` has private / Cloud / IronClaw Mobile / IronClaw Hosted.
- `ChatStore.routeReadinessIssue` already knows when Cloud key or hosted IronClaw endpoint is missing.
- `nearCloudKeyConfigured`, `ironclawTokenConfigured`, `ironclawStatusText`, `ironclawLastVerifiedAt`, and `ironclawToolNames` are already published.
- Account has `PowerToolsUnlockCard`, NEAR Cloud key entry, IronClaw endpoint/token fields, and diagnostic actions.
- Agent has setup/readiness panels and workstation test tools.
- Selected-route notices already avoid overclaiming Cloud privacy.

The work is productization, not invention:

- centralize statuses,
- rename power tools,
- surface capability cards,
- make missing setup recoverable from the route that needs it,
- and apply per-turn trust labels.

## P0 Work For This Specific Pass

### P0.1 - Capability Center Shell

Create a non-blocking `Capabilities` sheet/screen.

It does not need every backend dependency perfect. It must show truthful states from the data already present.

Minimum cards:

- Private Inference
- NEAR AI Cloud
- IronClaw Agent
- Council

Minimum actions:

- `Check proof`
- `Connect Cloud`
- `Connect IronClaw`
- `Customize Council`

### P0.2 - Rename Power Tools To Capabilities

Account should stop using `Power Tools` as the normal route into Cloud/IronClaw.

Replace with:

- `Capabilities`
- `Connect NEAR AI Cloud`
- `Connect IronClaw`
- `Run health check`
- `Model defaults`

Move developer copy behind `Developer`.

### P0.3 - Setup Simplification With Capability Disclosure

Keep setup one-screen.

Add a collapsed line:

`Private is ready now. Connect Cloud or IronClaw later.`

Optional disclosure:

`Connect more capabilities`

Inside:

- Cloud key connect
- IronClaw connect
- Council note

Do not block the first chat.

### P0.4 - Route Labels Everywhere

Add route/trust labels to:

- model picker rows
- chat header
- assistant messages
- Council artifact members
- Agent run cards
- share preview
- export proof footer later

Labels must be derived from `ChatRouteKind`, not copy pasted per screen.

### P0.5 - Recovery Flows From Missing Dependency

When user selects:

- Cloud model without key: show inline recovery and deep-link to Cloud card.
- hosted IronClaw without endpoint: show inline recovery and deep-link to IronClaw card.
- Council with fewer than two models: deep-link to Council lineup.

Do not only show banners. Banners disappear; recovery cards should be persistent until resolved or dismissed.

## P1 Work

### P1.1 - Connect NEAR AI Cloud Flow

Screens:

- What Cloud adds.
- Get key / sign up.
- Paste key.
- Test key.
- Choose defaults.

State copy:

- `Not connected`
- `Key saved`
- `Testing`
- `Connected`
- `Key failed`

Hard truth:

`Cloud models are not private proof unless a verified private route is explicitly shown.`

### P1.2 - Connect IronClaw Flow

Screens:

- What phone agent can do.
- What hosted workstation adds.
- Endpoint/token.
- Test bridge.
- Verify tools.
- Bind default project.

State copy:

- `Phone ready`
- `Workstation missing`
- `Endpoint saved`
- `Token saved`
- `Tools verified`
- `Bridge failed`

Approval education:

`IronClaw asks before risky file, network, or destructive actions.`

### P1.3 - Mixed Council Artifact

Council must show:

- model names
- route labels
- per-model completion state
- raw answer access
- synthesis
- disagreements only when real

If mixed:

`Mixed route: Cloud members are labeled and do not carry private proof.`

### P1.4 - Agent Run Card

Replace generic status with:

- current step
- last 3 steps
- approval gates
- pause/stop/retry
- final result summary

The card should show whether it used:

- phone runtime
- hosted workstation
- project context
- web
- repo tools

### P1.5 - Proof-Aware Share

Public links and exports must include:

- route labels
- proof state
- proof ID if available
- no-proof explanation where relevant

## Design System Requirements

### Typography

Apply the type ladder from the next-design-pass brief. The 8:38 setup card showed that values were too large and too bold relative to section labels.

Priority surfaces:

- setup preview / capability cards
- Account capabilities
- model rows
- Agent setup card
- Proof facts
- route labels

### Color

Use one saturated brand-blue CTA per scene.

Suggested roles:

- `actionPrimary` - primary CTA only
- `trustVerified` - proof verified
- `trustFetched` - proof fetched, neutral/blue-grey
- `trustStale` - amber
- `trustMismatch` - red
- `routeCloud` - neutral grey
- `routeAgent` - tool/orange or violet, not brand blue
- `routePrivate` - trust-adjacent, not necessarily blue

### Cards

Use cards only where the card is the interaction:

- Capability card
- Agent run card
- Council artifact
- Proof result card

Do not add hero cards to every sheet. Project context, Account, and Security should feel like focused utility surfaces, not a stack of marketing panels.

### Motion

Motion should clarify status:

- Cloud key test transitions: testing -> connected/failed
- IronClaw tool verification: checking -> verified/failed
- Proof state change: fetched -> verified/stale/mismatch
- Send -> stop
- Council model row: queued -> thinking -> done
- Agent run step updates

Respect Reduce Motion.

## Product Quality Questions For Claude / Design Agent

Use these to force a stronger next pass:

1. What is the minimum setup path that makes the app useful within 20 seconds?
2. Where does a user learn that Cloud, Private, and IronClaw have different trust boundaries?
3. Can a user recover from missing Cloud key or IronClaw endpoint without leaving the task they were trying to do?
4. Does any screen imply `verified` when the system only fetched metadata?
5. Does the Account screen read like a consumer settings page or a developer console?
6. Can a nontechnical user explain what IronClaw does after seeing only the Agent card?
7. Can a user tell whether the agent is running on phone or hosted workstation?
8. Can a user tell which project context an agent will use before starting?
9. In Council mode, can a user tell which answers came from Private vs Cloud?
10. If the app has no Cloud key and no hosted IronClaw endpoint, does it still feel complete?
11. What is the one dominant action on each screen?
12. Which screens still have more than one saturated blue control?
13. Which labels are internal concepts rather than user goals?
14. Which empty states dead-end instead of offering a first action?
15. Which route/proof labels need to survive into shared links and exports?

## Claude Design Prompt

Use this prompt for a dedicated design pass:

> You are doing the next elite product/design pass for NEAR Private Chat iOS. Treat the app as a capability system, not a set of routes. Private chat should work immediately; NEAR AI Cloud and IronClaw should be optional capabilities the user can connect, test, and use inside the same conversation. Design a `Capabilities` screen with Private Inference, NEAR AI Cloud, IronClaw Agent, and Council cards. For each card, specify status states, user copy, primary/secondary actions, trust-boundary copy, empty/error states, and recovery paths. Then update Setup, Account, Composer, Model Picker, Agent, Council, Proof, and Share so they deep-link into the right capability card when a dependency is missing. Keep SF Pro, one saturated brand-blue CTA per scene, and truthful proof language. Never imply NEAR Cloud is private TEE-attested unless the current route actually has proof. Produce screen-level specs, component specs, and a Swift implementation plan with files likely to touch.

## Codex Implementation Prompt

Use this after design direction is accepted:

> Implement the capability setup shell for NEAR Private Chat iOS. Rename Power Tools to Capabilities, add a Capabilities sheet/screen with cards for Private Inference, NEAR AI Cloud, IronClaw Agent, and Council, and derive statuses from existing ChatStore state (`nearCloudKeyConfigured`, `ironclawSettings`, `ironclawTokenConfigured`, `ironclawStatusText`, `ironclawLastVerifiedAt`, `ironclawToolNames`, route readiness issues, and attestation status). Add recovery deep links from Cloud-key-required and hosted-IronClaw-required route cards into the matching capability card. Do not invent backend endpoints. Use truthful placeholder states where dependencies are not ready. Keep Setup one-screen and add a collapsed `Connect more capabilities` disclosure. Add per-route labels to model rows and assistant turns where feasible. Verify with simulator screenshots for Setup, Account/Capabilities, Model Picker, Agent, and a route-readiness recovery state.

## Acceptance Criteria

This pass is complete when:

- The app has a user-facing `Capabilities` surface.
- NEAR Cloud and IronClaw are easy to find and connect without digging through Account internals.
- Private chat still works without connecting either.
- Missing Cloud key / missing IronClaw endpoint produce persistent recovery cards, not just banners.
- Cloud, Private, IronClaw Mobile, and IronClaw Hosted each have distinct route/trust labels.
- No Cloud UI implies private proof.
- Agent setup explains phone-ready vs workstation-connected clearly.
- Council mixed route lineups show route labels per member.
- Account no longer reads as the primary setup surface for integrations.
- Setup says private is ready now and Cloud/IronClaw can be connected later.
- The next screenshot pack includes conceptual/not-yet-functional setup states for Cloud and IronClaw.

## The Product Bar

The app should feel like this:

1. "I can ask privately right now."
2. "I can connect Cloud if I want more models."
3. "I can connect IronClaw if I want work done."
4. "The app tells me exactly what route each answer used."
5. "Proof is visible when it exists and never faked when it does not."

That is the path from impressive prototype to excellent product.
