# NEAR Private Chat iOS - Live App Review + Corrected Next Pass

Date: 2026-05-25
Basis: current app built and launched on iPhone 17 Pro simulator, iOS 26.5, bundle `ai.near.privatechat.ios`.

This review supersedes any conclusion that was based only on the old 2026-05-24 screenshot pack. The current app is materially different in several places.

Fresh live screenshots captured:

- `review-artifacts/live-app-review-2026-05-25/00-live-setup.png`
- `review-artifacts/live-app-review-2026-05-25/01-live-new-chat-after-skip.png`
- `review-artifacts/live-app-review-2026-05-25/02-live-model-picker.png`
- `review-artifacts/live-app-review-2026-05-25/03-live-model-picker-council.png`
- `review-artifacts/live-app-review-2026-05-25/04-live-more-menu.png`
- `review-artifacts/live-app-review-2026-05-25/05-live-security-no-proof.png`
- `review-artifacts/live-app-review-2026-05-25/06-live-home.png`
- `review-artifacts/live-app-review-2026-05-25/07-live-account-top.png`
- `review-artifacts/live-app-review-2026-05-25/08-live-model-search-cloud.png`
- `review-artifacts/live-app-review-2026-05-25/09-live-cloud-council-selected.png`
- `review-artifacts/live-app-review-2026-05-25/10-live-model-search-ironclaw.png`
- `review-artifacts/live-app-review-2026-05-25/11-live-hosted-ironclaw-selected.png`
- `review-artifacts/live-app-review-2026-05-25/12-live-more-menu-agent-visible.png`
- `review-artifacts/live-app-review-2026-05-25/13-live-connect-agent.png`
- `review-artifacts/live-app-review-2026-05-25/14-live-home-ironclaw-mode.png`
- `review-artifacts/live-app-review-2026-05-25/15-live-new-project-sheet.png`
- `review-artifacts/live-app-review-2026-05-25/16-live-project-context.png`

## Executive Diagnosis

The current app is no longer the same app as the older screenshot pack. Home, Project Context, model search, proof, and menu grouping have all improved. The old critique that the Home hero is a three-button demo command card is partly stale.

The actual current problem is sharper:

> The app has strong surfaces, but route state, setup state, capability connection state, and proof state still disagree with each other.

The biggest live issues:

1. Setup says `Ready: LLM Council` while the primary CTA says `Ask a private question`.
2. `Skip setup` does not simply skip; it applies defaults, creates/opens a new chat, and preloads a draft.
3. Selecting `Claude Opus 4.7` from model search switched the header to `LLM Council 2` instead of reading as a single-model selection.
4. Selecting `Hosted IronClaw` leaves the composer saying `Mobile agent ready.`
5. The `Connect Agent` sheet tells the user to configure Account settings, but provides no actionable button or deep link.
6. Account top still does not expose NEAR Cloud or IronClaw setup; the most important power capabilities are hidden below current visible content / power tooling.
7. Proof is now more truthful, but header labels truncate to `No model` and disabled proof actions look tappable.
8. Cloud route labeling is much better than before (`NEAR Cloud`, `Anonymized`, `Not attested`), but the app still needs a first-class `Capabilities` connection flow.

## What Is Better Than The Earlier Audit Assumed

### Home Is Much Improved

Current Home has:

- one strong `Ask` primary action,
- a compact `Context` / `Agent` secondary action depending on state,
- search,
- filters,
- resume cards,
- project rows with icon/color,
- account avatar top-right,
- no bottom account footer.

This is much closer to product shape. The next pass should not restart Home from scratch.

Keep:

- Ask as the main action.
- Resume row near the top.
- Search across chats/projects/sources.
- Selected project indication.
- Project row color/icon treatment.

Fix:

- The hero changes labels based on selected route/project in a way that can feel magical. After selecting Hosted IronClaw, Home shows `IRONCLAW`; after selecting a project, it shows `Using Agent Workspace`. That statefulness is useful, but it needs a consistent slot: `Current context: Agent Workspace` or `Route: IronClaw`.
- `Agent` only appears in the hero after IronClaw is selected. This makes discoverability route-dependent.
- If the user is meant to connect Cloud/IronClaw, Home still offers no connection/status summary.

### Project Context Is Much Better

Current Project Context has:

- a compact hero,
- clear project name and active state,
- `What this project knows`,
- `Sources / Instructions / Notes`,
- empty state with `Add Link` and `Add Files`,
- more useful copy than the old Library/Guide/Saved taxonomy.

Keep this direction.

Fix:

- Add capability binding: `Used by chat and agents`.
- Add source freshness/indexing state.
- If a project is selected, Agent should automatically show `Using Agent Workspace`.
- `What this project knows` should be the permanent mental model for project context across the app.

### Proof Is More Truthful

The live Security sheet no longer overclaims. It shows:

- `Model proof unavailable`
- `No model proof`
- a clear note that proof does not mean the answer is true/safe/complete.

This is a strong correction.

Fix:

- The chat header proof chip truncates to `No model`, which is cryptic.
- `Verify on-device` and `Share Proof JSON` visually read as blue actions even when disabled.
- The sheet title should become `Proof` or `Security & Proof`; `Security` alone is too broad.
- If there is no proof, the primary action should be `Fetch proof` or `Check proof` if available. If proof cannot be fetched for this route, the primary state should say that directly.

### Model Search Is Stronger

Searching `Claude` shows Cloud model rows with good truth labels:

- `NEAR Cloud`
- `Anonymized`
- `Not attested`

Searching `IronClaw` shows both:

- `Hosted IronClaw`
- `IronClaw Mobile`

This is exactly the kind of route truth the app needs.

Fix:

- `Mostly Cloudy` appears as an accessibility description for Cloud rows; that should not ship as user-facing or VoiceOver copy.
- Search result cards are still visually dense.
- Selecting Cloud unexpectedly produced Council state in the header during live review.
- If Cloud key is missing, the row should show `Connect Cloud`; if key is present, show `Cloud ready`. The current row does not make connection status obvious from the visible card.

## Live Screen Findings

## 1. Setup

Live state:

- Hero: `Start with one job`
- Goal field empty placeholder.
- `Use the web` toggle off.
- Readiness line: `Ready: LLM Council`
- CTA: `Ask a private question`
- Secondary: `Skip setup`

Severity: P0.

The state model is still wrong. `Ready: LLM Council` and `Ask a private question` cannot both be the primary outcome. This is not only copy. It means readiness, selected route, and CTA derive from different parts of state.

Also, tapping `Skip setup` resulted in:

- banner: `Setup applied. First prompt ready.`
- new chat screen opened,
- draft prefilled: `Help me think through the most important question I should ask first.`

That is not "skip." It is "apply defaults and start a prompt." Users who tap Skip expect no setup side effects.

Required changes:

- Rename `Skip setup` to `Use defaults` if it applies defaults.
- Or make Skip truly skip and return Home without creating a draft.
- Make readiness line and CTA derive from the same selected route/use-case enum.
- Add a snapshot test for Setup:
  - selected private -> no `Ready: Council`
  - selected Council -> CTA includes Council
  - selected Agent -> readiness and CTA both reference Agent

## 2. New Chat / Composer

Live state after setup/defaults:

- model chip: `GLM 5.1`
- proof chip: `No proof` or `No model`
- title: `What do you want to ask?`
- subtitle: `Private by default. Add web, files, or sources when useful.`
- suggestions: `5 bullets`, `Compare`, `Risk memo`
- focus row: `Auto / Web / Project / Research`
- draft is prefilled.

What works:

- Current empty composer is calmer than the old centered logo screen.
- Send button is a clear blue circle.
- The proof chip is visible in the header.
- Prompt suggestions fill, not send, per accessibility hint.

Problems:

- The draft appears because of "Skip setup," not because the user asked for it.
- `No model` proof chip is too cryptic.
- The focus row still consumes persistent space even in default mode.
- The composer allows route state confusion: when Hosted IronClaw is selected, the empty-state subtitle says `Mobile agent ready.`

Required changes:

- Fix `Skip` behavior.
- Rename `No model` chip to `No proof` / `No model proof` with enough width or adaptive label.
- Collapse focus row behind one source chip in Beginner/default mode.
- Derive empty-state subtitle from selected route accurately.

## 3. Model Picker

Live default:

- `Search 24 models`
- `Models / Council` segmented control
- GLM row with `NEAR Private`, `Starter plan`, and `Unlock 29 more models`
- Reasoning effort controls visible below.

Live Cloud search:

- Cloud rows have clear `NEAR Cloud`, `Anonymized`, `Not attested` labels.

Live IronClaw search:

- `Hosted IronClaw`
- `IronClaw Mobile`
- each has route labels.

What works:

- Search placeholder is specific.
- Cloud truth labeling is much improved.
- IronClaw is discoverable by search.
- Upgrade row has become cleaner than the old chip soup.

Problems:

- Choosing `Claude Opus 4.7` made the chat header show `LLM Council 2` and `Anonymized`. If selecting a Cloud model intentionally modifies Council lineup, the interaction must say that before closing the sheet. If not intentional, it is a P0 route-selection bug.
- Reasoning effort appears in the model picker by default; useful, but it makes the picker feel like settings. It should be under `Cloud defaults` or a compact disclosure.
- `Mostly Cloudy` appears in accessibility output for Cloud rows.
- No visible Cloud connection state from the row itself beyond route labels.

Required changes:

- Separate `Select model` from `Add to Council`.
- If Council mode is active, the picker title/CTA should say `Edit Council`, not `Model`.
- Add explicit per-row connection status:
  - `Cloud connected`
  - `Connect Cloud`
  - `Private`
  - `Hosted not connected`
- Move reasoning effort to a `Cloud defaults` disclosure unless Cloud route is selected.

## 4. Council State

Live state after selecting Claude:

- Header: `LLM Council 2`
- Trust chip: `Anonymized`
- Empty subtitle: `Council is ready to compare answers.`
- Notice: `LLM Council includes NEAR Cloud models. Cloud legs are external to NEAR Private TEE inference; all-private Council lineups can fetch NEAR Private attestation.`
- Focus row disabled.

What works:

- The Cloud/private proof boundary is stated clearly.
- Disabled focus row makes sense because Council route controls source use differently.

Problems:

- It is not clear how the user got into Council mode.
- Notice text is too long for a bottom strip; it truncates.
- `Anonymized` as the main trust chip is not enough. It should say `Mixed route` or `Cloud included`.

Required changes:

- Add a Council status card/tray:
  - `2 models selected`
  - `1 private · 1 Cloud`
  - `Cloud members are not TEE-attested`
- Replace long bottom notice with tappable compact pill:
  - `Mixed route: Private + Cloud`
- Provide `Use single model` escape hatch.

## 5. Hosted IronClaw Selection

Live state:

- Header: `Hosted IronClaw`
- proof chip: `No TEE`
- empty subtitle: `Mobile agent ready.`
- focus row still visible.

Severity: P0.

This is a direct route-state mismatch. Hosted IronClaw and Mobile agent are different capability states. If hosted is selected but workstation is unavailable, the app should say:

`Hosted workstation not connected`

and show:

`Connect IronClaw`

Do not say `Mobile agent ready` while header says `Hosted IronClaw`.

Required changes:

- Route state enum should have user-visible status:
  - hosted selected + endpoint usable -> `Hosted workstation ready`
  - hosted selected + endpoint missing -> `Connect hosted workstation`
  - mobile selected -> `Phone agent ready`
- Show persistent recovery card before send:
  - `Connect IronClaw workstation`
  - `Use phone agent instead`

## 6. Connect Agent Sheet

Live state:

- title: `Connect Agent`
- subtitle: `Connect a hosted IronClaw workstation, then launch repo, research, and code tasks from your phone.`
- chips: `Workstation off`, `Shell + git`, `Token needed`, `Phone controlled`
- card: `Connect IronClaw`
- text: `Add a hosted HTTPS endpoint and token in Account settings. Local LAN gateways are not shown as phone-ready routes.`

What works:

- The sheet is much calmer than the old Agent workspace screenshot.
- The distinction between workstation and phone control is present.

Problems:

- There is no button. `Connect IronClaw` looks like a card/title, not a tappable action.
- The user is told to go to Account settings manually.
- `Shell + git` appears next to `Workstation off`, which implies shell/git may be available when it is not.
- It does not explain what the phone agent can do without the workstation.

Required changes:

- Add primary CTA: `Connect workstation`.
- Add secondary CTA: `Use phone agent`.
- Deep-link to the IronClaw capability setup section, not generic Account.
- Replace `Shell + git` chip with `Shell + git unavailable` when workstation is off.
- Explain phone-only capability in one sentence.

## 7. Account

Live visible top:

- Profile card.
- `Composer Setup` with `Run Setup Again`.
- `Composer` with Web Search, Large Paste as File, System prompt.
- `Privacy` / Import Chats.
- Sharing begins below.

This is cleaner than before, but it fails the user's main goal: making NEAR AI Cloud and IronClaw easy to sign up/connect.

Problems:

- No visible `Capabilities`, `NEAR AI Cloud`, or `IronClaw` entry in the first screen.
- `Run Setup Again` is still more prominent than Cloud/IronClaw setup.
- Users who land here from `Connect Agent` are told to find endpoint/token fields, but they are not visible.

Required changes:

- Add `Capabilities` directly under profile:
  - `Private ready`
  - `Cloud connected / Connect Cloud`
  - `Agent phone ready / Connect workstation`
- Demote `Run Setup Again`.
- Add direct rows:
  - `Connect NEAR AI Cloud`
  - `Connect IronClaw`
  - `Run health check`
- Move Composer settings below capability setup.

## 8. Home

Live default Home:

- `NEAR Private Chat`
- `Private AI with proof on iPhone`
- Ask
- Context
- Search
- filters
- Resume cards
- Projects

Live after IronClaw:

- Hero gains `Agent`
- bottom label `IRONCLAW`

Live after project selection:

- subtitle: `Using Agent Workspace`
- Project button replaces Context.

What works:

- This is a real product Home now.
- Resume path is visible.
- Project selection is visible.

Problems:

- Hero state changes are not explained.
- Agent discoverability depends on model/route state.
- There is no capability connection summary.

Required changes:

- Use a consistent metadata line:
  - `Private ready · Project: Agent Workspace`
  - `Route: IronClaw · Workstation off`
- Keep `Agent` visible as a secondary action if the app wants IronClaw adoption.
- Add a small `Capabilities` status entry, probably via account/avatar or a compact row under hero.

## 9. Project Context

Live state is good. This may be the strongest current screen.

Keep:

- `What this project knows`
- `Sources / Instructions / Notes`
- empty source state with Add Link / Add Files
- compact hero

Fix:

- Add `Used by chat and agents`.
- Add source freshness.
- Add clearer active instruction state.
- Ensure the agent sheet auto-binds this project.

## 10. Overflow Menu

Live menu is grouped:

- Navigate
- Edit
- Export
- Organize
- Destructive below fold

This is better than the old 13-item ungrouped menu.

Problems:

- It is still too tall for iPhone.
- Disabled items create visual noise.
- `Security & Attestation` as menu item hides proof behind overflow.
- `Open Agent` appears only in IronClaw mode; discoverability is inconsistent.
- `Export Signed JSON` appears disabled/selected in accessibility output, which is odd.

Required changes:

- Promote proof chip tap as the main route into Proof.
- Promote Share to header only when conversation has content.
- Only show disabled items when they teach something useful; otherwise hide until valid.
- Keep `Open Agent` consistently discoverable from composer slash command or Home.

## Corrected Next-Pass Priority

### P0.1 - State Truth Fixes

Fix the three live mismatches:

- Setup readiness vs CTA.
- Cloud model selection becoming Council unexpectedly.
- Hosted IronClaw showing Mobile agent readiness.

These are not polish. They will make users think the app is broken.

### P0.2 - Capability Center

Add a first-class `Capabilities` surface:

- Private Inference
- NEAR AI Cloud
- IronClaw Agent
- Council

Reachable from:

- Account top
- Home/avatar
- route recovery cards
- model picker locked/missing states
- Agent connect sheet

### P0.3 - Cloud + IronClaw Connection Flows

Design and stub screens even before dependencies are perfect:

- `Connect NEAR AI Cloud`
- `Paste/Test key`
- `Cloud connected`
- `Connect IronClaw`
- `Endpoint/token`
- `Verify tools`
- `Use phone agent instead`

### P0.4 - Persistent Recovery Cards

When a capability is missing:

- Do not rely on banners.
- Do not make the user hunt Account settings.
- Show an inline card with a direct action.

Examples:

- `Cloud key required` -> `Connect Cloud`
- `Hosted workstation missing` -> `Connect IronClaw` + `Use phone agent`
- `Council mixed route` -> `Review lineup`

### P0.5 - Account Reorder

Account first screen should be:

1. Profile
2. Capabilities
3. Cloud / IronClaw / Proof health
4. Composer settings
5. Data / sharing / developer

### P1.1 - Proof Language + Header Width

Fix:

- `No model`
- disabled blue proof actions
- `Security` title

Ship:

- `Proof`
- `No proof`
- `No model proof`
- `Not TEE-attested`
- `Mixed route`

### P1.2 - Agent Sheet

Make `Connect Agent` actionable:

- primary CTA
- secondary phone-agent CTA
- tool availability truth
- project binding line
- deep link to capability setup

### P1.3 - Model Picker Role Clarity

Separate:

- selecting a single model
- editing Council
- adding model to Council
- selecting route family

### P1.4 - Home Capability Summary

Do not turn Home back into a dashboard. Add one compact line or status affordance:

`Private ready · Cloud connected · Agent phone ready`

Tap opens Capabilities.

## Revised Claude Prompt From Live App

> Review the actual running NEAR Private Chat iOS app, not stale screenshots. Use the live captures under `review-artifacts/live-app-review-2026-05-25/`. The app is now better than older audits assumed: Home is cleaner, Project Context is strong, model search has route labels, and Proof is more truthful. Your job is to fix live state coherence and capability setup. Prioritize: (1) Setup readiness/CTA mismatch, (2) Cloud model selection unexpectedly entering Council state, (3) Hosted IronClaw showing Mobile agent readiness, (4) Account hiding Cloud/IronClaw setup, (5) Connect Agent lacking a real action, and (6) proof chip truncation / disabled action styling. Design a Capabilities surface for Private Inference, NEAR AI Cloud, IronClaw Agent, and Council, with truthful route/proof boundaries and persistent recovery cards. Keep SF Pro, one saturated primary blue per scene, and do not regress the improved Home or Project Context.

## Revised Codex Build Prompt From Live App

> Build against the current running app state. First add tests/state fixes for the live mismatches: Setup readiness label must match CTA/selected route; selecting a Cloud model must not silently switch into Council unless the UI explicitly says `Add to Council`; Hosted IronClaw must not show `Mobile agent ready` unless the mobile route is selected. Then add a `Capabilities` screen under Account top with cards for Private Inference, NEAR AI Cloud, IronClaw Agent, and Council. Add direct actions from `Connect Agent` to IronClaw setup and from Cloud/Hosted readiness failures to the matching capability card. Keep the current improved Home and Project Context structure. Verify by launching the app in Simulator and capturing the same live screenshot set.

## Bottom Line

The current app is closer than the old screenshot audit implied. The design is not globally broken. The issue is state coherence and connection usability.

The next pass should not be another broad aesthetic redesign. It should make the app trustworthy by ensuring:

- every route label matches the route,
- every proof label matches the proof state,
- every missing dependency has a clear recovery action,
- NEAR Cloud and IronClaw can be connected from one obvious place,
- and Setup never says one thing while the CTA does another.
