# NEAR Private Chat iOS - Live Simulator Design Review

Date: 2026-05-25
Device: iPhone 17 Pro simulator, iOS 26.5
Build: current working tree, including the parallel product/legal changes present locally.
Scope: design, usability, route clarity, setup readiness, and product polish from live app inspection. No code or legal copy was edited in this pass.

Canonical design spec: `NEARPrivateChatIOS-agentic-default-design-spec-2026-05-25.md`. This live review is the evidence pack; the agentic-default spec is the implementation brief. Findings tagged `[recast]` are subsumed or reversed by the agentic-default spec.

Implementation note: the first agentic-default code pass resolves the recast Home/composer/Setup issues structurally. Treat this live review as the pre-implementation evidence pack; use the implementation tracker for current code status.

## Screens Captured

- `live-sim-design-review-2026-05-25/00-legal-attestation.png`
- `live-sim-design-review-2026-05-25/01b-home-relaunch.png`
- `live-sim-design-review-2026-05-25/02-new-chat-composer.png`
- `live-sim-design-review-2026-05-25/03-chat-thread-cloud-context-failure.png`
- `live-sim-design-review-2026-05-25/04-ironclaw-mobile-running.png`
- `live-sim-design-review-2026-05-25/05-model-picker.png`
- `live-sim-design-review-2026-05-25/06-account-integrations.png`
- `live-sim-design-review-2026-05-25/07-home-shared.png`
- `live-sim-design-review-2026-05-25/08-new-project-sheet-from-context.png`
- `live-sim-design-review-2026-05-25/09-project-context.png`
- `live-sim-design-review-2026-05-25/10-connect-agent.png`

## Executive Diagnosis

The app is now recognizably product-shaped: Home is cleaner, the composer has a real first-run prompt, the project context sheet is much stronger, and the legal gate makes the app's risk model explicit. The remaining design issue is not raw ugliness. It is semantic mismatch: the UI advertises "project", "context", "proof", "agent", "cloud route", and "IronClaw" in adjacent places, but the controls do not always make clear what will actually be available after the next tap.

The most damaging live moment: a suggested project prompt led into a Cloud route that answered that it could not access project files or web. That is a product-level trust break. If the app says "Using Agent Workspace" or offers a project-derived prompt, the selected route must either have project access or the app should block/suggest switching before sending.

## Priority Findings

### P0 - Route and context contract is broken

Observed in `03-chat-thread-cloud-context-failure.png`: the app can show Agent Workspace context while selected on a NEAR Cloud model, then the assistant says it cannot access project files or web. This makes the product feel confused even when the backend behavior is technically correct.

Fix:

- Before send, validate whether the selected route supports the active focus/context.
- If Project focus is active and the route cannot read project context, show a blocking inline choice: `Switch to NEAR Private` / `Send without project context`.
- Suggestions pulled from a project should force a project-capable route or include a visible route warning before send.

### P0 [recast] - Home still has three products fighting for first action

Observed in `01b-home-relaunch.png`: the hero contains Ask, Agent, Project, a route/status line, search directly below, recents, and projects. It is cleaner than before, but still presents the product as a command center rather than a private chat app with advanced capabilities.

Fix:

- Keep Ask as the only filled primary action.
- Move Agent and Project into smaller text actions below the hero or into the selected project row.
- Replace `IRONCLAW / WEB ON` and `CLOUD ROUTE` with the agentic-default sentence: `Ready to answer, research, or take action.` Do not show model names or tool lists on default Home.

### P0 [recast] - "Context" sometimes means "create a project"

Observed in `08-new-project-sheet-from-context.png`: tapping `Context` from Home while on Shared opened `New Project`. That is not what the label promises. The user expects current context/project settings, not a create flow.

Fix:

- Delete the Home hero `Context`/`Project` button entirely.
- Open project context from the selected project row.
- Use `+ New` in the Projects header for creation.

### P1 - Legal gate is clear but heavy

Observed in `00-legal-attestation.png`: the legal gate is strong and credible, but it reads like a second onboarding hero plus a dense compliance card. It uses the app's strongest hero treatment before the user reaches product value.

Fix:

- Keep the legal card, shrink the brand hero above it by 25-35%.
- Collapse bullets into three rows: `Required before sign in`, `Cloud models are proxied, not attested`, `Agent actions remain your responsibility`.
- Keep `Review terms` secondary and `Accept and continue` primary.

### P1 [recast] - Composer is much better, but the lower controls feel cramped

Observed in `02-new-chat-composer.png`: `What do you want to ask?` is the right headline. Suggestions are now compact and useful. The bottom control stack still compresses focus chips, input, paperclip, and send into a very tight block.

Fix:

- Remove the focus chip row. The orchestrator picks web/project/files/research.
- Keep one input with attach + send/stop.
- Make the send button a visibly filled state when text is present; disabled state is okay but currently disappears into the input.
- Keep suggestion chips but make them longer, more concrete when project context exists.

### P1 [recast] - Model picker improved, but the sheet starts too low and buries inventory

Observed in `05-model-picker.png`: the `Models | Council` split is right. Under agentic-default, this is override UX, not the first-run path. Default users should rarely see it. The top of the sheet wastes vertical space while only showing one model row plus reasoning controls.

Fix:

- Promote selected model card and reasoning into a compact sticky header.
- Show at least 3 model rows above the fold.
- Make `Connect token` a clear setup action for IronClaw, not a pale badge inside a model card.

### P1 [recast] - Agent setup surface is too inert

Observed in `10-connect-agent.png`: `Connect Agent` explains the concept but gives no direct route to the Account setup fields visible in `06-account-integrations.png`.

Fix:

- Delete the standalone `Connect Agent` destination from the default flow.
- Offer `Run as agent?` inline when the orchestrator detects an agentic task.
- If setup is missing, the inline card deep-links into Account → Power Tools → agent connection and returns to chat.
- Replace status chips like `Shell + git` with plain capabilities only after connection is ready.

### P1 - Account integration setup is useful but visually reads like a settings/debug panel

Observed in `06-account-integrations.png`: the Agent Readiness card is good, but the form has too much exposed implementation text for a normal user.

Fix:

- Rename `Save Bridge` to `Save Agent Connection`.
- Put the long Cloudflare/Tailscale/ngrok helper behind `How do I connect this?`.
- Add a single setup checklist: `1. Start hosted IronClaw` / `2. Paste endpoint` / `3. Test tools`.

### P2 - Project Context is the strongest screen, with one issue: duplication

Observed in `09-project-context.png`: this is the most coherent surface. The "What this project knows" card is excellent. The lower empty state duplicates Add Link/Add Files and then starts another Add section below.

Fix:

- Keep either the empty-state CTAs or the Add section, not both above the fold.
- Consider making "What this project knows" collapsible after the first visit.
- The hero can shrink slightly; the content underneath is stronger than the banner.

### P2 - Shared view is too sparse for a top-level mode

Observed in `07-home-shared.png`: the single shared item is legible, but the page feels unfinished because there is no empty-state framing, permission cue, or preview affordance.

Fix:

- Add a compact info row: `Shared with you · read-only chats cannot be edited`.
- Show sender/source if available.
- Treat read-only state as a visible badge, not only metadata.

## Design System Notes

- The app is still overusing blue as brand, action, selected state, status, and background. The project context sheet works because it confines the strongest gradient to one hero.
- SF Pro is the right choice. The issue is sizing and density, not font family.
- The app needs semantic status colors: blue for action, green/teal for verified proof, orange for route mismatch, red for destructive/failure.
- Capsule chips are now more consistent, but the visual grammar is still inconsistent: some chips are inert facts, some are buttons, some are route warnings.

## Next Design Pass

1. Route-contract guardrails: prevent project-derived prompts from sending through routes that cannot read project context without explicit confirmation.
2. Home simplification: one primary action and the sentence `Ready to answer, research, or take action.`
3. Context correction: delete the Home hero project/context button; project rows open Project Context; `+ New` creates.
4. Agent connection funnel: inline `Run as agent?` / `Connect agent` cards deep-link into Account setup and return to chat.
5. Model picker density: override-only surface; show more choices above the fold for power users.
6. Composer simplification: remove focus chips; keep attach + input + send/stop.
7. Project Context trim: remove duplicate Add affordances and keep the knowledge preview.
