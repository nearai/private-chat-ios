# NEAR Private Chat iOS - Elite Design & Product Audit

Date: 2026-05-25  
Scope: design-led review of current source plus available screenshot artifacts.  
Main screenshot references: `review-artifacts/latest-smoke/*`, `review-artifacts/screenshots-2026-05-24-fresh/*`, and `review-artifacts/screenshots/*`.

This is intentionally not another feature inventory. The question here is: **what keeps this from feeling like an elite iOS product?**

## Short Answer

The app is feature-rich and much more coherent than the first audit state, but it still feels like a powerful internal tool that has been visually polished, not a finished premium product.

The core issue is not "missing UI." It is that too many concepts are introduced as visible controls before they become useful: Private, Web, Agent, Council, Context, Sources, Files, Notes, Proof, Gateway, Route, Endpoint, Signing, Model, Project, Cloud. Elite design would make the app feel simpler while keeping the power intact.

The design north star should be:

> **Ask first. Proof always. Advanced power exactly when needed.**

That means:

- One obvious next action per screen.
- Proof as a quiet persistent system signal, not mostly a sheet.
- Council and Agent as contextual upgrades, not competing product modes.
- Fewer cards, fewer blue accents, fewer status chips.
- Setup that produces a working first answer, not a preference profile.
- A real hierarchy between primary, secondary, diagnostic, and developer surfaces.

## What Is Already Better

Do not throw this work away. The app has several good design moves now:

- Home has the right shape: primary Ask, search, filters, Resume, Projects, grouped chats.
- Setup now asks for a job and generates a first-run draft.
- The composer has focus-specific placeholders, source modes, attachment shelf, slash commands, haptics, and route recovery.
- Project Context has moved toward the right taxonomy: Sources, Instructions, Notes.
- Model picker now has Models/Council tabs, filters, pinned models, and better rows.
- IronClaw has hosted handoff disclosure, approval cards, and a compact run-status strip.
- Security has proof actions and education, not just raw JSON.

The problem is that these pieces are still wearing a similar visual costume: rounded panel, blue icon, blue tint, secondary grey copy, grouped-list section. That makes the app legible but not memorable.

## Elite Design Diagnosis

### 1. The product still reads as three products

The app is still asking the user to understand:

- Private Chat
- LLM Council
- IronClaw Agent
- Project Context
- Attestation/Security
- NEAR Cloud

Those are real features, but they should not all be peers in the user's first mental model.

Elite simplification:

- Primary product: **private verified chat**.
- Contextual upgrades:
  - `Compare with Council`
  - `Run as Agent`
  - `Use Project Sources`
  - `Copy with Proof`
- Persistent trust layer: shield/proof status.
- Developer/debug layer: endpoint, callback, auth scheme, raw JSON.

Design implication:

- Home and new chat should not present Agent, Council, Context, and Proof as equal top-level nouns.
- They should appear as actions attached to a prompt, message, project, or proof state.

### 2. Blue is still overused

There are semantic color tokens, but `brandBlue` is still used heavily across the app. A current grep shows 154 direct `brandBlue` references.

Code references:

- `NEARPrivateChat/Models.swift:3133` defines `brandBlue`.
- `NEARPrivateChat/Models.swift:3137` maps `primaryAction = Color.brandBlue`.
- `NEARPrivateChat/Models.swift:3138` defines `trustVerified`.
- `NEARPrivateChat/AppShellView.swift` still uses direct `Color.brandBlue` throughout.

Elite design issue:

- Blue currently means primary action, selected state, active route, link, model, trust, decorative glow, card shadow, row icon, and status.
- If everything is blue, nothing is actually primary.

Required change:

- Use `actionPrimary` only for the main action on a screen.
- Use `trustVerified` / `trustFresh` for proof.
- Use neutral grey for inactive system states.
- Use project color for project context.
- Use orange/red only for degraded and destructive states.
- Cap visible strong blue to three instances per screen.

### 3. The app is card-heavy in a way that flattens hierarchy

Screens use many repeated rounded rectangles at similar radii, weight, padding, and border strength. This is competent, but it makes the app feel like a stack of settings panels.

Visible examples:

- Setup choice rows look like large settings rows.
- Home search, hero, filters, resume cards, and project rows all compete as panels.
- Model picker rows, summary, filters, and Council builder all use similar grouped-list language.
- Project Context has hero card, segmented tabs, source cards, empty cards, and file/library cards.
- Security has summary, current session, proof actions, proof facts, education, report, refresh.

Elite change:

- Use cards only for repeated items, proof artifacts, and genuinely framed tools.
- Use unframed text rows for low-importance metadata.
- Use one hero surface per screen maximum.
- Avoid giving search, filters, sections, and rows equal visual depth.

### 4. The command-card gradient is the only strong brand moment

The dark blue command card looks like the brand center of gravity, but it appears on Home, Setup, Project Context, and Agent. That creates consistency, but it also makes unrelated surfaces feel like the same object.

Current code:

- `CommandCardBackground` is used as the dark hero style at `NEARPrivateChat/AppShellView.swift:1105`.
- Setup uses it at `NEARPrivateChat/NEARPrivateChatApp.swift:409`.
- Home uses it at `NEARPrivateChat/AppShellView.swift:1063`.
- Project Context uses it at `NEARPrivateChat/AppShellView.swift:4815`.
- Agent uses it at `NEARPrivateChat/AppShellView.swift:7197`.

Elite change:

- Home gets the primary command card.
- Project Context gets a project-colored header, not the same generic command card.
- Agent gets a tool/workspace surface, not the same private-chat hero.
- Security gets a proof/seal surface using trust colors, not generic brand blue.
- Setup should use a lighter, calmer onboarding header after the first screen.

### 5. The visual system needs an intensity ladder

Right now many components are "medium loud." Elite apps have a tighter scale:

- Level 0: background
- Level 1: plain rows
- Level 2: grouped panels
- Level 3: selected/active item
- Level 4: primary command
- Level 5: critical proof/destructive state

Recommendation:

- Define component intensity tokens, not just color tokens.
- Example:
  - `plainRow`
  - `softPanel`
  - `selectedRow`
  - `primaryCommand`
  - `proofArtifact`
  - `dangerZone`

Then audit every screen so each has only one Level 4 element.

## Screen-Level Findings

### Setup / Onboarding

Current state:

- The source is much improved: setup asks for a job, use cases, Beginner/Power, context style, defaults, and shows a plan.
- The latest setup screenshots show a nicer "Start with one job" hero, but the screen still feels like a settings survey.

Code references:

- `NEARPrivateChat/NEARPrivateChatApp.swift:267` asks what the user wants to do first.
- `NEARPrivateChat/NEARPrivateChatApp.swift:284` asks Beginner/Power visibility.
- `NEARPrivateChat/NEARPrivateChatApp.swift:311` exposes defaults.
- `NEARPrivateChat/NEARPrivateChatApp.swift:332` shows the setup plan.
- `NEARPrivateChat/NEARPrivateChatApp.swift:384` derives the footer CTA from `AppSetupPlan`.

Elite issues:

- It still asks too many abstract configuration questions before the user gets value.
- The hero says "one job," but the following UI asks use case, visibility, saved-material behavior, and defaults.
- The Private/Web/Agents hero metrics are passive and introduce concepts too early.
- The bottom CTA must always match the visible selections and route readiness. One smoke screenshot showed a Council CTA while Private Chat appeared selected; source may have moved since then, but this needs a UI smoke test because it is exactly the kind of mismatch that kills trust.

Elite redesign:

- Screen 1: "What should NEAR help with first?" plus text area and 3 examples.
- Screen 2: "Use sources?" with simple choices: No sources / Web / Project.
- Screen 3: "Advanced mode?" Beginner default, Power optional.
- Hide model/Council/IronClaw defaults unless Power is selected.
- The final CTA should be consequence-based:
  - `Start private chat`
  - `Create research project`
  - `Configure Agent`
  - `Start from this goal`

Do not make onboarding a place to admire features. Make it a place where the user's first successful answer becomes inevitable.

### Home

Current state:

- Home now has a strong command header, secondary Agent/Project actions, search, filter strip, Resume row, project list, and date-grouped chats.
- This is a big improvement over the earlier "three CTAs inside hero" state.

Code references:

- Home structure begins around `NEARPrivateChat/AppShellView.swift:238`.
- Search field at `NEARPrivateChat/AppShellView.swift:260`.
- Filter strip at `NEARPrivateChat/AppShellView.swift:265`.
- Resume row at `NEARPrivateChat/AppShellView.swift:274`.
- Projects section at `NEARPrivateChat/AppShellView.swift:289`.
- Hero component at `NEARPrivateChat/AppShellView.swift:993`.

Elite issues:

- Home still feels like a dashboard, not a fast return surface.
- Search is visually large enough to compete with Ask.
- Filters add another row of chrome before the user sees useful content.
- Resume should be the returning-user path, not just a mid-page section.
- Project context menus are too thin: Open, Project Context, New Chat. No Rename, Color/Icon, Archive.
- The hero status line still has internal language: provider/route/web/sources. It should expose only what the user needs now.

Elite redesign:

- Top: compact app header with avatar/settings and search icon.
- First surface: Ask composer/card.
- Immediately under: Resume last 3.
- Then Projects.
- Then grouped chats.
- Search expands into a full search mode when tapped rather than permanently consuming height.
- Home hero status should become a single trust/context line:
  - `Verified`
  - `Verified / Web`
  - `Verified / Project: IronClaw QA`
  - `Cloud route` only when non-private.

### New Chat / Composer

Current state:

- The source now has focus modes, placeholder-per-mode, attachment shelf, route-readiness card, slash commands, haptics, and Reduce Motion handling.
- The older screenshot still showed a dead empty state with logo and generic chips; source likely improved parts of this, but the empty-state experience still needs simulator verification.

Code references:

- Input bar starts at `NEARPrivateChat/AppShellView.swift:8722`.
- Focus placeholder logic at `NEARPrivateChat/AppShellView.swift:8765`.
- Focus modes at `NEARPrivateChat/AppShellView.swift:8804`.
- Slash commands at `NEARPrivateChat/AppShellView.swift:8853`.
- Route readiness card at `NEARPrivateChat/AppShellView.swift:8606`.

Elite issues:

- A bottom composer plus horizontal focus row can feel like a toolbar before the user has typed.
- Auto/Web/Files/Links/Research are still five concepts at rest.
- `/agent`, `/council`, `/verify`, `/project`, `/sources` are powerful but could become hidden expert-only affordances if not paired with contextual long-press actions.
- When Council is active, the composer should shift from "chat input" to "multi-model run input" with visible expectations.

Elite redesign:

- Default rest state:
  - input
  - paperclip
  - source chip (`Auto`)
  - send/mic/stop morph
- Hide full focus row until the source chip is tapped or the user is in Power mode.
- Empty chat should say: `What do you want to ask?` and show 3 concrete examples from setup/project.
- Council mode should add a small tray:
  - `GLM queued`
  - `Qwen thinking`
  - `Synthesis ready after 2 answers`
- Slash commands stay, but message/context menus should expose the same power to normal users.

### Model Picker

Current state:

- Model picker has Models/Council tabs, search, filters, pinned models, row badges, verified route badge, and Council customization.

Code references:

- `ModelPickerView` starts at `NEARPrivateChat/AppShellView.swift:2157`.
- Models/Council segmented picker at `NEARPrivateChat/AppShellView.swift:2215`.
- Model rows at `NEARPrivateChat/AppShellView.swift:2784`.

Elite issues:

- It is better, but still too much like a database browser.
- Sections include Pinned, Recommended, Open/Reasoning, Private/Verifiable, Frontier, NEAR Cloud, General, Agents. That is comprehensive but cognitively heavy.
- "Verified route" is good, but it sits beside generic badges instead of being a first-class trust mark.
- No "best for" language is visible at the top level.

Elite redesign:

- Default view:
  - Recommended
  - Private verified
  - Favorites
- Advanced filters behind `All models`.
- Row shape:
  - model name
  - one-line best-for copy
  - trust/cost/speed chips
  - pin
- Verified indicator should be a shield/check aligned with model name, not another chip in a chip flow.
- Council tab default should be `Auto-Council`, with Customize behind a secondary control.

### Project Context

Current state:

- Project Context is much closer to the right shape now: Sources, Instructions, Notes.
- Confirm dialogs exist for source/note/file delete.
- Source empty state has Add Link/Add Files.

Code references:

- Project Context tabs at `NEARPrivateChat/AppShellView.swift:4248`.
- Sources empty action row at `NEARPrivateChat/AppShellView.swift:4436`.
- Project hero card at `NEARPrivateChat/AppShellView.swift:4405`.

Elite issues:

- The project hero still uses the generic command-card style, so it looks like Home/Agent rather than "this project."
- "Project Context" remains an internal phrase. Users think "what this project knows" and "instructions."
- The file/source surface still does not clearly answer: what will the model actually read?
- Source freshness labels exist, but there is not yet a strong trust model around indexing/staleness/last used.

Elite redesign:

- Rename surface to `Project`.
- Header:
  - project icon/color
  - project name
  - generated "What this project knows" summary
  - compact metadata line
- Tabs:
  - Sources
  - Instructions
  - Notes
- Add source state:
  - `Ready`
  - `Indexing`
  - `Stale`
  - `Failed`
  - `Not used yet`
- Replace hero command-card gradient with project color and neutral material.

### Security / Attestation

Current state:

- Security has summary, current session, proof actions, proof facts, education, raw report, and fetch/refresh.
- This is a serious differentiator, but the design still reads like a technical diagnostics sheet.

Code references:

- `SecurityView` starts at `NEARPrivateChat/AppShellView.swift:6384`.
- Current Session at `NEARPrivateChat/AppShellView.swift:6396`.
- Proof Actions at `NEARPrivateChat/AppShellView.swift:6403`.
- What This Means at `NEARPrivateChat/AppShellView.swift:6411`.
- Raw Report at `NEARPrivateChat/AppShellView.swift:6417`.

Elite issues:

- The first useful thing should be a large proof result, not a list of internals.
- "Endpoint", "Request signing", and "Selected model" are details, not the main story.
- Raw JSON belongs behind an advanced disclosure.
- `Verify on-device` currently overpromises unless backed by real cryptographic verification.
- The trust accent should not be the same brand blue used for buttons.

Elite redesign:

- Top proof capsule:
  - `Verified`
  - `GLM 5.1-FP8`
  - `Intel/NVIDIA TEE` when known
  - `fresh 2m ago`
- Primary actions:
  - `Verify proof`
  - `Share proof`
  - `Copy with proof`
- Education:
  - collapsed `Why this matters`
- Advanced:
  - endpoint
  - signing
  - raw JSON
  - gateway addresses

The sheet should make a non-technical user feel safer in five seconds, while giving a technical user full proof details after one tap.

### Council Answer

Current state:

- Council has a grouped response component with model pills and status.
- Synthesis prompt asks for direct answer, agreement, disagreement, and next step.

Code references:

- `CouncilResponseGroup` starts at `NEARPrivateChat/AppShellView.swift:1420`.
- Council streaming starts at `NEARPrivateChat/ChatStore.swift:3394`.
- Synthesis starts at `NEARPrivateChat/ChatStore.swift:3533`.

Elite issues:

- The grouped UI is a wrapper around messages, not yet a designed Council artifact.
- Status text like `2 of 4 answered` is useful but not emotionally enough when users are waiting.
- No visible "synthesize now."
- No "why models disagreed" action.
- No per-model confidence or claim-level contrast.

Elite redesign:

- Council artifact header:
  - model pills
  - elapsed/TTFT status
  - `Synthesize now` when useful
- Body:
  - Direct answer
  - Agreement
  - Disagreement
  - Next step
- Secondary:
  - raw answers
  - ask dissenters
  - export disagreement

Do not render empty sections. If there is no meaningful disagreement, do not pretend there is.

### Agent / IronClaw

Current state:

- Agent is not as bare as earlier: it has hosted handoff disclosure, approval cards, a compact status strip, and a mission control panel.

Code references:

- Agent workspace starts at `NEARPrivateChat/AppShellView.swift:7005`.
- Mission control panel starts at `NEARPrivateChat/AppShellView.swift:7137`.
- Agent run status strip starts at `NEARPrivateChat/AppShellView.swift:7977`.
- Approval card starts at `NEARPrivateChat/AppShellView.swift:8374`.

Elite issues:

- The run status strip is too generic: `Agent running`, `No output received`, `Waiting for approval`.
- It does not tell a story of the run: read files, checked git, ran tests, wrote patch, waiting approval.
- The Agent sheet uses the same command-card visual language as Home and Project.
- "Auto tools", "Likely tools", and tool counts are accurate but still a little tool-centric.

Elite redesign:

- Agent run card in thread:
  - sticky current step
  - last 3 steps
  - approvals inline
  - pause/resume/stop
  - final run summary
- Agent sheet:
  - "Give it a task. It uses your project context."
  - templates that prefill the composer
  - project binding visible
  - tools hidden behind details unless relevant

## Cross-Cutting Quality Issues

### Copy Drift

The app still uses multiple labels for adjacent concepts:

- Sources
- Files
- Library
- Context
- Instructions
- Guide
- Notes
- Saved
- Proof
- Attestation
- Security
- Verification

Elite copy taxonomy:

- `Chat`
- `Project`
- `Sources`
- `Instructions`
- `Notes`
- `Proof`
- `Agent`
- `Council`

Everything else should be internal or advanced.

### Trust Language

Avoid:

- "Secure"
- "Verified" when only metadata was checked
- "Private" when route is NEAR Cloud or hosted IronClaw
- "Proof" when the artifact is not independently verifiable

Use:

- `Private route`
- `Verified proof`
- `Proof fetched`
- `Proof stale`
- `Cloud route`
- `Hosted handoff`
- `Metadata check`

### Accessibility

The code includes accessibility labels/hints in places and uses Reduce Motion in the composer, but the visual system still needs a full pass:

- Grey secondary text is often small.
- Many controls rely on blue tint to signal active state.
- Horizontal chip rows can become poor with Dynamic Type.
- The app uses many icon-only controls that need explicit labels.
- Large setup rows may become too tall at large text sizes.

Required tests:

- Dynamic Type: large, extra extra large, accessibility medium.
- VoiceOver through setup, composer, security, share, project context.
- Color-blind proof/failure state check.
- Reduce Motion on composer send, chip selection, sheet transitions.

### Motion

Motion should make state legible, not decorative.

Use motion for:

- send button active/inactive/stop
- source chip selection
- attestation freshness change
- Council model status transitions
- Agent approval state

Avoid:

- hero/card motion
- bouncing loading dots
- long decorative spring chains

### Dark Mode

Light mode has a warm off-white direction. Dark mode must not be a simple inversion.

Needed:

- separate dark token set
- proof/trust accent that survives dark mode
- project colors tuned for dark
- raw JSON/code surfaces with readable contrast

### Performance / Maintainability Affects Design Quality

Elite design requires fast iteration. Current UI is still concentrated in very large files:

- `AppShellView.swift` is about 9,840 lines.
- `ChatStore.swift` is about 7,513 lines.

Design issue:

- Monolithic UI files make it harder to polish components consistently.
- They also make visual regression and snapshot testing more difficult.

Recommendation:

- Extract component groups by surface:
  - `Home`
  - `Composer`
  - `ModelPicker`
  - `ProjectContext`
  - `SecurityProof`
  - `Agent`
  - `Council`
- Add screenshot/snapshot tests for the main states.

## Priority Fixes

### P0 - Make onboarding a launchpad

- Cut onboarding to job, source style, beginner/power.
- Hide advanced toggles by default.
- CTA must match the visible route and be sendable.
- First-run should land on a prefilled prompt that can succeed.
- Smoke test all setup combinations.

### P0 - Make proof truthful and beautiful

- Replace diagnostics-first Security with proof-result-first Security.
- Separate `proof fetched` from `proof verified`.
- Use trust colors, not generic blue.
- Bind proof to assistant turns.
- Add Signed Snippet design now, even if implementation follows.

### P1 - Reduce Home density

- Search as expandable mode or toolbar search.
- Resume above filters.
- Filters less prominent.
- Project context menu: Rename, Color/Icon, Archive.
- Hero status line only when non-default or useful.

### P1 - Redesign Council as an artifact

- Status tray with per-model states.
- Synthesize now.
- Raw/synthesis toggle.
- Agreement/disagreement sections as components.
- Ask dissenters only when there is real disagreement.

### P1 - Make Agent runs legible

- Expand status strip into a real timeline card.
- Show current step and last 3 steps.
- Keep approval cards inline.
- Add final run summary with commands/tests/files.

### P1 - Finish semantic design tokens

- Stop direct `brandBlue` use in feature components.
- Define action/trust/project/status tokens.
- Apply an intensity ladder.
- Cap blue per screen.

### P2 - Project trust model

- Add "what this project knows" summary.
- Add source state: ready/indexing/stale/failed/not-used.
- Make "what will be used in this answer" visible from composer.

### P2 - Accessibility and visual QA

- Dynamic Type audit.
- VoiceOver script.
- Contrast pass.
- Dark mode pass.
- Screenshot regression pack.

## Claude Design Research Questions

Ask Claude to answer these with evidence and concrete recommendations:

### 1. Onboarding

- What is the best setup shape for a privacy AI chat app: no setup, one-question setup, or guided setup?
- Which choices should be made by onboarding, and which should be inferred later?
- What is the minimum onboarding that makes first-run useful without feeling like preferences?
- How do elite iOS apps prevent CTA/selection mismatch?

### 2. Proof UX

- What consumer proof patterns are easiest to understand: SSL lock, Signal safety number, 1Password verification, wallet transaction proof, Git signed commit?
- What should a verified AI answer look like at message, thread, share, and export levels?
- What exact copy explains TEE in two sentences?
- How should the app visually distinguish proof fetched, proof verified, proof stale, and proof mismatch?

### 3. Council UX

- How should multiple model answers be represented on iPhone: tabs, stacked cards, carousel, collapsible sections, or synthesis-first?
- When should "synthesize now" appear?
- How should disagreement be detected and displayed without theatre?
- What should "Ask dissenters" do in a way users understand?

### 4. Agent UX

- What is the best mobile pattern for long-running coding/research agents?
- How should approvals be grouped: per tool, per run, per risk category?
- What run steps are meaningful to users versus developer noise?
- How should final run summaries present changed files, tests, and risks?

### 5. Visual System

- What palette/tokens let blue stay premium rather than noisy?
- What should trust/proof colors be if action blue is reserved for primary CTA?
- How should project colors appear without making the app childish?
- What corner radii, shadows, and separators feel native/premium on current iOS?

### 6. Information Architecture

- What concepts should be top-level: Chat, Projects, Shared, Agent, Council, Proof?
- Which concepts should only appear contextually?
- Should search be persistent on Home or entered as a mode?
- How should a user understand sources, files, notes, and instructions in one minute?

### 7. Accessibility

- Which parts of this UI are most likely to fail Dynamic Type?
- How should chip rows collapse for accessibility sizes?
- How should proof and route state be conveyed without color?
- What haptic map feels premium rather than gimmicky?

## Build Prompts For Claude/Codex

### Prompt 1 - Onboarding Redesign

> Redesign setup as a launchpad, not a preferences page. Keep goal text, Beginner/Power, and source style. Hide advanced defaults unless Power is selected. Ensure the final CTA always matches the selected route and can succeed. Add UI tests for each setup route.

### Prompt 2 - Proof-First Security

> Redesign Security around a proof-result capsule. Separate proof fetched from proof verified. Move endpoint/signing/raw JSON behind Advanced. Use trust tokens instead of brand blue. Do not claim cryptographic verification unless implemented.

### Prompt 3 - Home Density Pass

> Make Home feel like an elite return surface. Ask remains primary, Resume is immediately visible, search becomes an expandable mode, filters are low-chrome, project rows get Rename/Color/Icon/Archive context actions, and hero status only appears when useful.

### Prompt 4 - Council Artifact

> Convert Council output from grouped messages into a designed artifact with model status, synthesis-first sections, raw answer toggle, early synthesis, and disagreement actions. Hide empty sections.

### Prompt 5 - Agent Run Timeline

> Expand the IronClaw run strip into an in-thread timeline card with current step, last 3 steps, inline approvals, pause/resume/stop, and final run summary. Keep the existing handoff and approval safety model.

### Prompt 6 - Semantic Visual Tokens

> Replace direct `brandBlue` usage in feature views with semantic tokens. Add action/trust/project/status tokens and an intensity ladder. Audit Home, Setup, Composer, Model Picker, Project Context, Security, Agent, and Council for no more than one primary action per screen.

## Bottom Line

The app has enough functionality to be impressive. The elite design work is now about restraint and truth:

- fewer visible concepts
- less blue
- fewer equal-weight cards
- proof as a system signal
- setup that creates immediate utility
- Council and Agent as contextual power, not competing app identities
- every claim backed by an actual state

If those land, NEAR Private Chat stops feeling like "a loaded prototype" and starts feeling like a premium private AI instrument.
