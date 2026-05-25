# NEAR Private Chat iOS Design Review Addendum

Date: 2026-05-25
Scope: current source plus the fresh screenshot set in `review-artifacts/screenshots-2026-05-24-fresh/`.

User direction: finish the iPhone app first. Defer iPad. Mac can be a later power-user surface after the iOS experience is great.

Concrete build punchlist: see [NEARPrivateChatIOS-product-punchlist-2026-05-25.md](/Users/abhishekvaidyanathan/Documents/Playground/NEARPrivateChatIOS/review-artifacts/NEARPrivateChatIOS-product-punchlist-2026-05-25.md:1). That file is the implementation-ready version of this review. It has been revised after the Deep Research Pass and supersedes this document wherever there is a conflict.

## Design Verdict

The app has real visual craft in pockets, especially the dark command cards, Agent workspace, Project Context hero, and attestation surfaces. The problem is not lack of taste. The problem is hierarchy.

The current design reads like three products competing for attention:

- Private Chat.
- IronClaw Agent.
- Project workspace/context system.

The first-run experience does not visually answer "what should I do now?" It presents a dense control surface and asks the user to understand models, context, web, projects, agents, Council, and setup before they have had one successful chat.

The design goal should be:

- One obvious first action.
- Fewer concepts above the fold.
- Setup that shows consequences, not settings.
- Verifiability as a persistent trust layer.
- Power features revealed after intent, not before.

## Current Screenshot Set

- [00 Setup](/Users/abhishekvaidyanathan/Documents/Playground/NEARPrivateChatIOS/review-artifacts/screenshots-2026-05-24-fresh/00-setup.png)
- [01 Home](/Users/abhishekvaidyanathan/Documents/Playground/NEARPrivateChatIOS/review-artifacts/screenshots-2026-05-24-fresh/01-home.png)
- [02 New Chat Composer](/Users/abhishekvaidyanathan/Documents/Playground/NEARPrivateChatIOS/review-artifacts/screenshots-2026-05-24-fresh/02-new-chat-composer.png)
- [03 Model Picker](/Users/abhishekvaidyanathan/Documents/Playground/NEARPrivateChatIOS/review-artifacts/screenshots-2026-05-24-fresh/03-model-picker.png)
- [04 Model Picker Council](/Users/abhishekvaidyanathan/Documents/Playground/NEARPrivateChatIOS/review-artifacts/screenshots-2026-05-24-fresh/04-model-picker-council.png)
- [05 Agent Workspace](/Users/abhishekvaidyanathan/Documents/Playground/NEARPrivateChatIOS/review-artifacts/screenshots-2026-05-24-fresh/05-agent-workspace.png)
- [07 Project Context](/Users/abhishekvaidyanathan/Documents/Playground/NEARPrivateChatIOS/review-artifacts/screenshots-2026-05-24-fresh/07-project-context.png)
- [09 Account Settings](/Users/abhishekvaidyanathan/Documents/Playground/NEARPrivateChatIOS/review-artifacts/screenshots-2026-05-24-fresh/09-account-settings.png)

Note: the source has moved after this screenshot set in a few places. Where source and screenshot differ, treat the screenshot critique as visual direction and the code review as implementation truth.

## Latest Punchlist Synthesis

The latest concrete suggestions sharpen the design direction. The right first build is not "redesign everything"; it is a product-quality iPhone pass across the most visible surfaces:

- Home: keep `Ask` as the home primary action, but keep an explicit compose/pencil affordance off-home; demote Agent/Project below the hero; remove the account footer; use a filter strip for `All / Shared / Archived`; add search, last-three recents/resume, project icon/color, and date grouping.
- Composer: replace the logo-heavy empty state with one clear question, use concrete setup/project-aware suggestions, add a chevron to the model chip, remove the standalone terminal button, make focus placeholders mode-specific, add visible attachment/draft handling, add slash commands, and turn send/stop into one morphing circular control.
- Model picker: reduce row metadata to provider plus plan/cost, move upgrade to one bottom strip, put `Models | Council` directly under the title, add favorites and filters, show `last verified`, and make Auto-Council the default with builder behind `Customize`.
- Project Context: use three tabs on iPhone if possible, merge files/links under `Sources`, reduce hero height, move add-link creation out of content rows, collapse row actions behind overflow, add source freshness, and make empty states action-first.
- Chat: persistent attestation shield beside the model chip, per-message attestation chips, auto-generated 3-6 word titles, breadcrumb subtitle, expandable source-count panels only when sources were consulted, branch view for regenerate, and long-press timestamps.
- Security: add `Verify on-device`, `Share proof`, `View on verifier.near.ai` with QR, readable coverage copy like `Verified / GLM 5.1-FP8 / Intel TDX`, hardware identity, reproducibility testing, and a collapsed "Why this matters" explanation.
- Visual system: keep SF Pro, ignore the full NEAR brand guideline system, use Sky/NEAR iconography only where it helps, add semantic color tokens, reduce visible Blue, standardize radii, add haptics, and support VoiceOver/Dynamic Type/Reduce Motion.

Items like Live Activities, widgets, App Intents, Quick Council, Signed Snippet, Attestation Diff, and signed transcript publish are category moves, but should come after the iPhone core has route readiness, home, composer, model picker, project context, and attestation actions cleaned up.

## Top Design Findings

### P1: Onboarding Looks Like A Settings Form, Not A First-Run Experience

The setup screen opens with a polished hero, then immediately becomes a long vertical list of configuration choices.

Visible issues:

- "Make it yours" is abstract. It does not say what the app will help the user accomplish.
- The hero chips `Private / Web / Agents` look like status badges but are passive.
- `Skip` and `Finish` are both large bright pill buttons, so the screen visually treats abandoning setup and completing setup as peers.
- The first visible choice group is internal taxonomy: use case, context style, web, agents, Council.
- The design asks for configuration before showing value.
- The selected rows are very blue, which makes setup feel like toggling settings rather than moving through a guided path.

Design fix:

- Replace the setup page with a first-job picker.
- Show one primary prompt: "What do you want to do first?"
- Use four large, outcome-based choices: Ask privately, Research with sources, Work with files, Use agent/code tools.
- After a choice, show a compact "Recommended setup" confirmation with route/focus/workspace/readiness.
- Make the final CTA action-specific: `Start private chat`, `Start research brief`, `Open project workspace`, `Connect agent`.

### P1: Setup Does Not Visually Show Consequences

The setup preview is trying to solve this in source, but the visual system still treats setup as a list of choices rather than a causal flow.

What users need to see:

- What route will be active.
- What source/focus mode will be active.
- Whether a project will be created.
- Whether the chosen route is actually ready.
- What the very next screen/action will be.

Design fix:

- Add a persistent summary card pinned near the bottom of setup:
  - `Route: Verified private model`
  - `Focus: Auto`
  - `Workspace: Research Room`
  - `Ready: Attestation available`
- If a route is not ready, make the primary CTA a setup step, not `Finish`.

### P1: Home Still Has Too Many Equivalent Actions

The home screen is visually attractive, but it is too dense for first use.

Visible issues:

- Three strong new-entry affordances compete: toolbar plus, hero Ask, search.
- Hero card has Ask, Agent, Project, Privacy, Web, conversation/project count, and Agent ready in one surface.
- `Agent: ready` looks actionable but is visually a status pill.
- `All Chats` is selected in a large blue row, competing with the hero primary CTA.
- Projects begin below the fold, so the app says "Projects matter" while hiding the actual project list.
- The account footer is visually heavy and consumes bottom real estate.

Design fix:

- Keep one primary CTA: `Ask`.
- Remove/demote the toolbar plus on first-run home, but keep an explicit compose/pencil affordance off-home so users can start a fresh chat from an active thread.
- Hide Agent/Project buttons until selected in setup or used before.
- Move search below recents or make it collapsed until there are enough chats.
- Separate system collections (`All Chats`, `Shared With Me`, `Archived`) from projects with smaller rows and lower emphasis.
- Replace account footer with a compact avatar/settings row, or move it into toolbar.

### P1: New Chat Empty State Has Better Chips But Too Much Dead Space

The new chat screen has a cleaner prompt-chip treatment, but the visual hierarchy still leaves the user suspended.

Visible issues:

- The model chip at top left is visually huge and reads as the main CTA.
- Agent/workspace icon and overflow icon are unlabeled square buttons; they look like utilities but are prominent.
- Empty-state content sits in the middle while the actual composer is at the bottom, leaving a large blank vertical gulf.
- Prompt chips are helpful but generic; they do not reflect onboarding goal text.
- Disabled send arrow and attachment button both read as pale/disabled utilities.

Design fix:

- Pull the empty prompt cluster closer to the composer.
- Use setup-aware chips: if the user chose Research, show research chips; if they typed a goal, show `Start from your goal`.
- Make the model chip smaller and clearly tappable with a chevron.
- Hide Agent button unless route/intent is Agent.
- Add a quiet first-run explainer line above chips: "Private route verified. Ask anything, attach files, or use web when needed."

### P1: Model Picker Still Feels Over-Tagged

The Models/Council tabs are a strong improvement, but the first card is still metadata-heavy.

Visible issues:

- The summary card uses many chips before the user sees actual model choices.
- `LLM Council 4` appears as both title and chip.
- `Curated`, `Web on`, `Starter plan`, and `Upgrade: 29 more` compete with model identity.
- The bottom sheet opens at a height that cuts off the first model row, so the picker feels cramped.

Design fix:

- Summary card should show only current route + one sentence.
- Move plan/upgrade metadata into a smaller footer row.
- Keep chips to two visible concepts: `Verified/private` and `Plan/cost`.
- Open the model picker at a taller detent when launched from first-run or from model chip.
- In Council tab, prioritize "Use Council" and active model list; hide general model metadata.

### P1: Brand Blue Is Overloaded

Blue currently means:

- Primary action.
- Selected row.
- Active chip.
- Link/action text.
- Web enabled.
- Model selected.
- Trust/verification.
- Decorative hero glow.

That makes the UI energetic, but it flattens meaning. A user cannot tell what is important because everything important is blue.

Design fix:

- Brand blue: primary actions only.
- Pale blue: selected navigation state only.
- Verified green: attestation/trust only.
- Neutral grey: passive metadata, disabled controls, non-primary actions.
- Cyan/sky: dark hero accent only, not every active state.

### P2: Typography Ladder Needs More Discipline

The app uses large bold text well in hero cards, but section and row hierarchy is inconsistent.

Visible issues:

- Section headers like `Workspace`, `Projects`, `Setup`, and `Diagnostics` are large grey text and can dominate content beneath them.
- Metadata text is often large but low-contrast grey.
- Card subtitles sometimes carry key meaning in muted text, for example "A few choices set models..." or project metadata lines.
- Model picker and Account use default iOS list typography, so they feel less custom than Agent/Project surfaces.

Design fix:

- H1: screen title only.
- H2: major section headers, smaller and darker than current grey giants.
- Row title: semibold, consistent.
- Metadata: smaller but higher contrast, with icons for scanability.
- Hero subtitle: brighter on dark backgrounds, because it carries the actual explanation.

### P2: Card System Is Inconsistent

The dark command card is the strongest identity element, but it appears as a hero, setup preview, project summary, and agent container with slightly different semantics.

Visible issues:

- On Home, the dark card is brand + commands + status.
- On Setup, the dark card is brand + passive metrics.
- On Agent, the dark card is the actual work surface.
- On Project Context, the dark card is a project summary.

Design fix:

- Define card roles:
  - `CommandCard`: contains one primary action and at most two secondary actions.
  - `StatusCard`: shows state only, no primary CTA.
  - `WorkspaceCard`: summarizes project/agent context.
- Do not mix status and primary commands unless the status directly supports the action.

### P2: Account Still Reads Like A Utility Console

Account is cleaner than before, but visually it is still a list of operational controls.

Visible issues:

- `Run Setup Again` is a full prominent action with body copy, which makes setup feel like a major/reset operation.
- Diagnostics is demo-focused and takes prime space.
- Chat settings and system prompt appear before many user-facing account concepts.
- Developer/integration controls below the fold are still part of the same mental page.

Design fix:

- Default Account sections:
  - Profile.
  - Plan.
  - Privacy & verification.
  - Setup preferences.
  - Sign out.
- Move diagnostics, system prompt, NEAR Cloud key, IronClaw bridge, imports, and advanced params into `Developer & Integrations`.
- Make `Run Setup Again` a smaller row: `Preferences`, subtitle `Goal, defaults, and first-run choices`.

### P2: Project Context Is Strong, But Taxonomy Still Hurts It

Project Context is one of the better-looking surfaces. The hero card communicates "workspace" well.

Visible issues:

- It still shows `0 files`, which is visual noise.
- Tabs say `Sources / Library / Guide / Saved`, which is four words for two user concepts.
- The add-link form is embedded inside the existing link card, so creation and existing content are visually tangled.
- The empty file state is large and starts below the fold.

Design fix:

- Hide zero-count metrics in hero.
- Use three tabs on iPhone where possible, preferably `Sources / Instructions / Notes`, with files and links grouped under Sources.
- Move add-link behind a clear `Add link` row or put the add form above the list.
- Make empty states action-first: `Add file`, `Add link`, `Paste note`.

### P2: Agent Workspace Is The Strongest Feature Surface

Agent workspace has the clearest mood and best relationship between visual hierarchy and task.

What works:

- Dark card makes the mode feel distinct.
- Large mission input is appropriate.
- Context row at bottom is excellent.
- Capability chips are compact and scannable.

Issues:

- `Auto skills` is too low contrast and looks disabled.
- `Coding / Local Test / GitHub` look tappable, but appear passive.
- The Start button inside an empty input area reads disabled even when it is the primary action.
- The whole surface is visually stronger than normal chat, which makes Private Chat feel like the less-designed product.

Design fix:

- Make capability chips explicitly passive or truly filterable.
- Move `Skills: Auto` beside Start as a real control.
- Reuse the bottom context row in normal chat.
- Borrow the Agent surface's task clarity for Private Chat onboarding.

## Proposed First-Run Redesign

### Screen 1: Pick First Job

No dark hero card. Use a calm white screen with one strong title and four choices.

Title:

`What do you want to do first?`

Choices:

- `Ask privately`
  - `Start with a verified private model.`
- `Research with sources`
  - `Use web, citations, and source-aware prompts.`
- `Work with files`
  - `Create a project workspace for links, files, and notes.`
- `Use agent/code tools`
  - `Connect IronClaw or start a phone-safe agent task.`

Primary CTA:

- `Continue`

Secondary:

- `Skip for now`

### Screen 2: Confirm Setup

Show one summary card:

- Route.
- Focus.
- Workspace.
- Verification/readiness.

Below it, show only editable essentials:

- Web on/off.
- Create workspace on/off.
- Compare multiple models on/off, only when ready.
- Agent readiness, only if chosen.

Primary CTA changes by readiness:

- `Start private chat`
- `Start research brief`
- `Create workspace`
- `Connect agent`

### Post-Setup Landing

Do not dump the user on generic home.

- Private: open new chat with private prompt chips.
- Research: open new chat with Research selected and source chips.
- Files/projects: open Project Context with `Add file` and `Add link`.
- Agent: open readiness/mission screen.

## Design Work Packets

### Packet D1: Onboarding Visual Rebuild

Priority: P1

Scope:

- Setup screen only.

Build:

- Replace the long settings page with a two-step first-job flow.
- Remove passive hero metrics.
- Make primary CTA action-specific.
- Show a readiness/consequence summary before completion.
- Make Skip visually secondary.

Acceptance criteria:

- The first setup screen has one question and four outcome-based choices.
- No advanced nouns appear before a user chooses an advanced job.
- The final CTA tells the user where they will land.

### Packet D2: Home Information Diet

Priority: P1

Scope:

- Home screen, first-run state, project rows.

Build:

- One primary action: Ask.
- Do not remove compose globally. Keep home focused on `Ask`, but keep a top-right compose/pencil icon off-home.
- Remove `Agent: ready` from the hero.
- Keep `Ask` full-width in the hero and move Agent/Project to text buttons directly underneath: `Open Agent ->`, `New Project ->`.
- Replace status chips with one small metadata line: `Verified · Web on · 1 link`.
- Remove the account footer card; move avatar/settings to the toolbar.
- Convert `All Chats`, `Shared With Me`, and `Archived` into a segmented control or compact filter strip, not horizontal tiles.
- Add home search across chats, projects, and sources.
- Add last-three recents/resume row.
- Add `+ New` to the Projects header.
- Add project icon/color and a one-line stat format.
- Add Today/Yesterday/Earlier recents grouping.
- Add long-press project peek menu: Open, Rename, Color, Archive.
- Separate system collections from user projects.
- Hide zero-count metadata.
- Reduce account footer weight.

Acceptance criteria:

- First-run home has no more than eight visible concepts.
- Ask is unambiguously the primary action.
- Projects are easier to scan than system collections.

### Packet D3: Empty State And Composer Alignment

Priority: P1

Scope:

- New chat screen and composer.

Build:

- Move empty prompts closer to composer.
- Replace logo-heavy empty state with a 40 pt mark plus `What do you want to ask?`.
- Make prompt chips setup-aware and concrete.
- Add goal-aware `Start from your goal`.
- Shrink model chip and make it clearly a selector.
- Add chevron to model/Council chip.
- Hide irrelevant agent button and move Agent entry into overflow.
- Add focus-specific placeholder copy.
- Add attachment shelf above input.
- Use one morphing circular send/stop control.
- Add slash commands and draft persistence.
- Add Council thinking tray during Council runs, with per-model TTFT and `Stop waiting`.

Acceptance criteria:

- Empty state directly helps the first message.
- Onboarding choices visibly affect prompt chips.
- No unlabeled utility button is visually stronger than the composer.

### Packet D4: Color And Trust System

Priority: P1

Scope:

- App-wide tokens and component states.

Build:

- Reserve blue for primary CTA and selected controls.
- Use verified green only for attestation/trust.
- Use neutral grey for secondary actions.
- Audit contrast for metadata and disabled states.

Acceptance criteria:

- Trust state never looks like generic blue selection.
- Metadata passes WCAG AA at displayed sizes.
- Primary action is identifiable on every screen.

### Packet D5: Model Picker Density

Priority: P2

Scope:

- Model picker and Council tab.

Build:

- Reduce summary chips.
- Move plan/upgrade copy to a single bottom upgrade strip.
- Current row shows only provider and plan/cost.
- Move segmented control directly under the title.
- Add `Search 33 models`.
- Add favorites/pinned models.
- Add quick filters: Private, Open weights, Reasoning.
- Add relative-cost chip per model row.
- Show Verified check for attested model coverage.
- Increase default detent height.
- Make Auto-Council the default and put the reorder/add/remove/synthesizer builder behind `Customize`.

Acceptance criteria:

- User can see at least two model rows without scrolling on open.
- No model summary card shows more than three chips.
- Council route is understandable without reading backend taxonomy.

### Packet D6: Account And Developer Split

Priority: P2

Scope:

- Account/settings sheet.

Build:

- Default Account becomes user-facing.
- Developer & Integrations contains diagnostics, NEAR Cloud key, IronClaw bridge, imports, advanced params.
- `Run Setup Again` becomes `Preferences`.

Acceptance criteria:

- A normal user can scan Account without seeing endpoint/token/thread controls.
- Demo preflight remains reachable but does not dominate Account.

### Packet D7: Project Context Taxonomy

Priority: P2

Scope:

- Project Context sheet and project rows.

Build:

- Hide zero-count metrics.
- Use three tabs on iPhone where possible, preferably `Sources / Instructions / Notes`; keep files and links inside Sources.
- Move add-link creation out of existing link rows.
- Add action-first empty states.
- Collapse link-row actions behind `...`.
- Reduce hero height and replace metadata chips with one small metadata line.
- Add source freshness and `What this project knows` preview.
- Add file-type tinting.

Acceptance criteria:

- Project Context has one clear taxonomy.
- Creation controls are visually separate from existing content.
- Empty states include a first action.

## Updated Design Priority Order

P1:

- Onboarding visual rebuild.
- Home information diet.
- Empty state/composer alignment.
- Color and trust system.
- Route readiness gate from the functionality audit.
- Home search, recents/resume, drafts, haptics, and accessibility pass.

P2:

- Model picker density.
- Account/developer split.
- Project Context taxonomy.
- Chat header/titles/sources branch view.
- Security proof actions.
- Typography and Dynamic Type pass.

Later:

- Mac design system after iPhone quality.
- Voice/live mode.
- Widgets/Live Activities/Watch.
- Global memory and file/canvas preview surfaces.
- Quick Council, Signed Snippet, Attestation Diff, signed transcript publish.

## Bottom Line

The app does not need a prettier version of the current onboarding. It needs a different design premise.

Current premise:

`Choose settings before you understand the product.`

Better premise:

`Choose the job you came to do, then we show the verified/private setup that makes it work.`

That one shift will clean up onboarding, home, empty states, and the demo narrative at the same time.
