# NEAR Private Chat iOS — Agentic-Default Design Spec

Date: 2026-05-25
Status: Implementation brief. Supersedes the screen-level fix lists in the prior audits where they conflict. Treat those audits as the diagnostic record; treat this as the next-pass build order.
Basis: live iPhone 17 Pro simulator review (`live-sim-design-review-2026-05-25/`), the user's product direction, and the consolidated screen-level audits accumulated earlier today.
North star (from product):

> **Agentic by default, configurable only when needed.**
> Open app. Ask anything. NEAR answers privately when it can, researches when needed, uses project context when available, and offers to act when a task requires an agent. Advanced controls are there, but the product earns trust by choosing well before asking the user to configure anything.

Implementation note, 2026-05-25: the first code pass has now landed the orchestrator, first-run Setup removal, simplified Home, simplified composer, Power Tools demotion, NEAR Cloud app-grounding fix, and answer-footer proof capsule. Use `NEARPrivateChatIOS-agentic-default-implementation-tracker-2026-05-25.md` for current status.

Correction note, later 2026-05-25: "agentic-default" does **not** mean hiding model choice. The app must default to GLM (`zai-org/GLM-5.1-FP8`) while keeping `Model`, `Council`, and `Effort` controls visible in the chat/composer surface. The orchestrator may classify prompts and prepare recovery/offers, but it must not silently switch a user from GLM to Council, IronClaw, or Cloud. User-picked route wins until a readiness issue blocks send.

---

## The shape of the product after this pass

One default experience. One composer. One sentence of ambient state. Every "configuration" surface is reframed as a recovery surface — it appears only when the default cannot succeed.

```
Open app           →  Home: "Ask NEAR" + recents + projects
Tap Ask            →  Composer with one input + Model / Council / Effort controls
Send anything      →  Selected model runs; orchestrator attaches context and surfaces recovery/offers
Result lands       →  Answer + a quiet "Verified · Private" capsule
Tap the capsule    →  Detail sheet (route, model, proof, sources)
```

That's the entire spine. Focus/source strips, setup surveys, capability centers, NEAR Cloud key entry, IronClaw endpoint config, system prompt, and global web toggles are either *deleted from the default flow*, *moved behind progressive disclosure*, or *triggered by a real capability need at the moment of need*. Model choice, Council choice, and reasoning effort remain first-class chat controls.

## The orchestrator (the only "new" thing this pass really needs)

Before any UI change makes sense, ship a server-side / client-side **`AskOrchestrator`**:

```swift
AskOrchestrator(prompt, project?, attachments?, history?) -> (
    route,
    tools,
    proofPosture,
    failurePlan
)
```

It decides:

1. **Route** — the user's selected route: GLM private by default, or the explicit Model/Council/IronClaw/Cloud selection.
2. **Tools** — none / web search / project files / repo / code interpreter / Council.
3. **Proof posture** — Verified / Private / Proxied (with badge state derived from route).
4. **Failure plan** — if the picked route can't honor the request, what recovery card to show before send.

Policy is dumb but explicit. Examples:

| Signal | Decision |
| --- | --- |
| Prompt mentions "this file" / "my doc" / has an attachment | Files tool on. Route must support files. Default: Private with project access. |
| Prompt mentions "latest", "today", "news", "price", a year ≥ current | Web tool on. Route must support web. Default: Private with web. |
| Prompt looks like a task verb ("create", "open a PR", "deploy", "run", "set up") + IronClaw connected | Offer Agent inline ("Run as agent?"). Do not auto-switch. |
| Prompt is a decision question ("should I", "compare", "which is better") + Council available | Offer Council inline. Do not auto-enable Council unless the user taps Council or types `/council`. |
| Prompt is short / conversational | Use the selected model. Fresh installs select GLM by default. |
| Selected model can't fulfill the picked tools | Surface one pre-send recovery card. Do not silently replace the chosen model. |

The orchestrator is the contract that lets the UI drop focus/source clutter below the input. It is not a license to remove model choice.

## What dies on Home

Looking at `01-home.png` and `01b-home-relaunch.png`:

**Delete**
- The dark hero command card with three CTAs (Ask, Agent, Project).
- The status capsules `PROOF READY / WEB ON / CLOUD ROUTE` in small caps under the card.
- The `Project` button (it's a context picker masquerading as an action; the project is set elsewhere).
- The `Context` button that, per `08-new-project-sheet-from-context.png`, sometimes opens "New Project" — stateful labels with two meanings are banned across the app.

**Keep / reshape**
- Search bar.
- `All / Shared / Archived` filter strip.
- Resume card.
- Projects list with `+ New`.

**Replace the hero** with a single primary call:

```
┌──────────────────────────────────────────────┐
│ [N] NEAR Private Chat                        │
│     Ask anything. Verified when it can be.   │
│                                              │
│ ┌──────────────────────────────────────────┐ │
│ │ Ask NEAR                              → │ │
│ └──────────────────────────────────────────┘ │
│                                              │
│  · Ready to answer, research, or take action │
└──────────────────────────────────────────────┘
```

One CTA. One sentence in plain language replacing five status capsules. The current `Using Agent Workspace` micro-line moves into the composer header once a project is bound. Home's job is "start something" — not "remind you what the app is."

## What dies on the composer

Looking at `02-new-chat-composer.png`:

**Delete**
- The `No proof` chip beside the model. Proof state appears on the answer footer once an answer lands.
- The focus chip row `Auto · Web · Project · Research` above the input. Context/web/source behavior is inferred or recovered inline.
- The triple-chips `5 bullets / Find risks / Draft memo`. Replace per below.
- The `Agent Workspace is selected.` subhead — fold into a smaller breadcrumb above the title.

**Keep / reshape**
- The headline `What do you want to ask?` (this is correct).
- A visible `Model` control, defaulting to GLM and opening Models/Council selection.
- A visible `Council` control that enables or customizes the Council by direct user action.
- A visible `Effort` control (`Auto / Low / Medium / High`) in the chat window.
- Paperclip for attachments.
- The bottom input + send.

**Replace prompt chips with project-aware verb-first chips** (verb + object, 5–8 words, three max, project-aware):

When a project is loaded:
- Summarize my latest doc in this project
- Compare two files in this project
- Draft a reply using my saved notes

When no project is loaded:
- Explain this article
- Plan my next 24 hours
- Write a follow-up to a meeting

After three composer opens in a session, hide chips entirely. Gemini Neural Expressive (May 2026) did exactly this.

## What dies on the chat thread

Looking at `03-chat-thread-cloud-context-failure.png` — the worst surface in the current app:

The whole "I can't access your project files, here are three options" assistant turn is a UX failure made visible. **Killed at the source by the orchestrator.** Either (a) the orchestrator picks a route that can read the project; (b) the orchestrator detects the conflict pre-send and surfaces a single inline chip; (c) the orchestrator routes through privacy proxy with files and the user sees a quiet `Proxied · Files on` badge on the answer footer. The route's lack of capability never gets to write an apology paragraph.

**Other thread-level cleanups:**

- Proof chip moves to the **answer footer**, not the header. The header may carry a compact model selector because route choice is core workflow.
- `Anonymized` chip → `Privacy proxy` (anonymization is a property of data; proxy is a property of route).
- `NEAR Cloud · NEAR Cloud · Agent Workspace` duplication bug → `Cloud · Agent Workspace`.
- The long disclosure `Claude Opus 4.7 runs through NEAR Cloud with anonymized provider forwarding…` → footer chip set: `Cloud · Claude Opus 4.7 · Proxied · No project files`. Eight tokens. Same truth.
- The composer at the bottom of the chat reverts to the same minimal shape used on Home/New Chat. No floating focus row.

## What dies on the model picker

Looking at `05-model-picker.png`:

In the agentic-default world the model picker is *not required* on first run because GLM is already selected. It is still a visible control from the chat header/composer because users must be able to choose GLM, IronClaw, NEAR Cloud models, or Council without digging through Account.

**Reshape the picker as an override surface, not a primary surface:**

- Promote the selected route into a sticky compact header: `Currently: Verified · GLM 5.1 · Files on · Web on`.
- Below: three large categorical choices, not a model list — `Verified Private` (default) · `Open Cloud` (proxied) · `Council` (multi-model).
- "Show all models" sits at the bottom as a disclosure for power users.
- `Connect token` for IronClaw is *not* surfaced inside a model row — it lives in the agent connect flow.

The picker becomes clearer and means something specific: **"choose the model or Council for the next message."**

## What dies on the account screen

Looking at the live Account screen captures:

**Delete from default Account**
- `Web Search` toggle at the account level. Lives in the orchestrator + per-message override.
- `Large Paste as File` toggle. Silent default — auto-attach pastes >5,000 chars.
- The `System prompt` empty field on the account level. Instructions live on Project; an account-level system prompt is a power feature behind Power Tools.

**Keep / reshape**
- Identity card.
- `Power Tools` as the advanced disclosure home.
- `Capabilities & integrations` as a row inside Power Tools, not a top-level destination.
- Sharing.
- Models & Billing — but render `Renews 2026-06-22T20:20:21Z` as `Renews Jun 22, 2026`.
- `Power Tools` section, but it must actually hide things behind the `Show Power Tools` CTA (currently the rows are visible above and below — broken affordance).

**Move behind "Show Power Tools" (collapsed by default)**
- Add NEAR Cloud key
- Connect IronClaw bridge
- Advanced model params
- Run diagnostics
- Capabilities & integrations
- Account-level system prompt
- Account-level Web Search override
- Large Paste as File override

## Agent as behavior, not destination

`10-connect-agent.png` and `04-ironclaw-mobile-running.png` show the current shape: Agent is a destination sheet, a chip on the chat header, a `Workstation off` / `Shell + git` status row, and an awkward `Connect IronClaw` card that doesn't deep-link into Account.

**Reframe:**

Agent is *detected* by the orchestrator, *offered* inline in chat, and *expanded* into a richer card when running. The user does not navigate to Agent.

```
User types:  "Open a PR fixing the typo in the README"
↓
Inline card mid-compose (orchestrator detected agentic intent):
   ⚡ This looks like a task. Run as agent?
   [ Run agent → ]    [ Just answer  ]
↓
If IronClaw not connected:
   [ Run agent → ] expands to a one-step connect:
   Connect your IronClaw workstation to run this task.
   [ Connect now → ]   [ Just answer  ]
↓
If connected:
   In-thread Agent Run Card replaces the assistant message.
   Sticky current step + last 3 steps + inline approval +
   Pause / Resume / Stop.
↓
On completion:
   Five-section summary (Outcome · Files · Tests · External · Risks).
```

The `Connect Agent` sheet (`10-connect-agent.png`) is replaced by an in-thread connect prompt that deep-links into Account → IronClaw bridge, fills it in, and returns to the chat. No separate destination. No "Workstation off" chip. The user does not see the word "IronClaw" on Home unless they explicitly enable Power Tools.

`Agent route` subtitle in the chat header (visible on `04-ironclaw-mobile-running.png`) stays as the per-chat indicator — but the *entry point* into agent mode is always a contextual offer, never a top-level destination.

## Proof as ambient

Looking at the current chips: `No proof`, `Anonymized`, `No TEE`, `PROOF READY` — proof state is fragmented across at least four different chip styles. Replace with a single capsule on the answer footer:

| State | Capsule | Glyph | Meaning |
| --- | --- | --- | --- |
| `unknown` | Neutral grey | shield outline | Pre-fetch or no proof check has run yet |
| `verifying` | Neutral grey | spinner | Fetched, signature in flight |
| `verified` | Trust-green | filled shield-check | Signed runtime attestation, fresh |
| `stale` | Amber-orange | shield-clock | Previously verified, now older than freshness window |
| `mismatch` | Amber-orange | shield with slash | Attestation present but doesn't match — rare; needs user attention |
| `private_` | Neutral grey | shield outline | Private route, no signed attestation this turn |
| `proxied` | Neutral grey | cloud + shield-outline | Cloud route via privacy proxy |
| `unverified` | Neutral grey | shield-outline + dot | Route doesn't carry a proof claim |

Canonical engineering enum:

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

Capsule lives in the answer footer. Tap → Verification sheet. **Never display the word "attestation" to a user.** Use **`Verified`**, **`Verify`**, **`Verification`** as the consumer vocabulary. Reserve `attestation` for engineering docs and the verifier package.

The capsule is the only place proof state appears by default. The chat header carries no proof chip. The composer carries no proof chip. The model picker shows proof posture as a property of the category (`Verified Private` vs `Open Cloud`) not as a chip on each model.

## Plain-language status sentence

Replace every status-chip strip with a single sentence in title case where status matters. The sentence lives:

- On Home, under the Ask card: `Ready to answer, research, or take action.`
- On the composer (when a project is bound): breadcrumb `Agent Workspace` + a small caps `Will use project files`.
- On an Agent run: `Running on your IronClaw workstation.` (replaces `Running IronClaw Mobile`).
- On a Cloud-proxied answer: `Routed through Cloud privacy proxy.` (replaces the long disclosure).

One sentence, plain English, no acronyms.

## Banned from default UI

These terms can exist in Power Tools, engineering docs, diagnostics, and verifier internals. They should not appear on default Home, Composer, Chat, Project, or first-run surfaces:

- `TEE`
- `attestation`
- `IronClaw` as a default user-facing brand; say `agent`
- `Cloud route`
- `Proof ready`
- `No proof`
- `Web on`
- `Endpoint`
- `Bridge`
- `Token`

The default UI vocabulary is:

- `Ask`
- `Agent`
- `Project`
- `Verified`
- `Private`
- `Privacy proxy`
- `Connect agent`
- `Verify`
- `Details`

## Configuration as recovery, not setup

Three configurations cost the most cognition today: **NEAR Cloud key**, **IronClaw endpoint**, **repo token**. None of these belong on a setup flow. Each gets triggered by a real capability need.

```
NEAR Cloud key
  Trigger: user picks a Cloud-only model OR orchestrator wants to escalate.
  Surface: one-line sheet inside the composer/chat.
    "Claude Opus 4.7 needs a NEAR Cloud key. Paste yours
     (we don't store it on our servers)."
  CTA: [ Paste key → ]   [ Stay on Private ]

IronClaw endpoint
  Trigger: user accepts the inline "Run as agent?" offer.
  Surface: one-step connect sheet that returns to the chat.
    "Connect your IronClaw workstation."
  CTA: [ Connect now → ]   [ Just answer  ]

Repo token
  Trigger: agent task references a private repo.
  Surface: inline approval card asking for repo access at the moment
  of need, scoped to that repo only.
```

Every other "configurable" thing — system prompt, advanced model params beyond Effort, diagnostics, and developer controls — lives behind `Show Power Tools`.

## Project context — the strongest screen, with cuts

`09-project-context.png` is the cleanest sheet in the app. Two cuts only:

- **Remove the duplicate "Add Link / Add Files" empty state.** The Sources tab already has the affordance below; the empty-state CTAs above duplicate it.
- **Make "What this project knows" collapsible after first view.** First-visit users see the summary; returning users see Sources/Instructions/Notes at the top.

Keep everything else.

## Setup → eliminate it

The current setup screen still asks goal + visibility + saved-material behavior + defaults across multiple cards. In agentic-default, **setup does not exist as a destination.**

```
Sign in → Terms & Conditions sheet → Home

That's it.
```

Everything setup used to ask gets inferred or deferred:

- Goal: inferred from first prompt.
- Visibility: default Beginner. Power Tools button on Account graduates the user.
- Saved-material: deferred to first project creation.
- Default model: GLM (`zai-org/GLM-5.1-FP8`).
- Council: visible composer control plus `/council`; inline offers are additive, not the only path.
- Agent: offered inline when prompt is task-shaped.

The `Run Setup Again` button on Account becomes `Reset defaults` — clears the orchestrator's per-user learned preferences without dragging the user through a survey.

## Legal gate design constraint

The product/legal thread owns legal substance and exact copy. This spec only defines the design principle:

- Sign-in flows to Terms, then Home.
- The legal gate should not become a second onboarding hero.
- Keep one legal card, one secondary review action, one primary continue action.
- Do not use "attestation" as the consumer-facing legal screen headline.
- Do not let legal onboarding compete visually with the core `Ask NEAR` product moment.

## Visual system implications

- **One saturated brand-blue per scene.** Reserved for the primary CTA (`Ask NEAR`, `Agree & Continue`, `Connect now`, `Switch model`).
- **Trust palette outside blue.** Verified = trust-green capsule. Cloud-proxied = neutral grey-glass. Mismatch = amber. Never red unless destructive.
- **One hero per screen.** Home has one. Legal sheet has one. Project Context has one. Composer has none — the input is the hero.
- **Liquid Glass discipline.** `.regular` material, capsule pills 10pt/14pt padding, hero cards 20pt outer radius concentric. Respect the iOS 26.4 user opacity toggle.
- **Status as sentences, not chips.** Sentences sit in 13pt SF Pro Text Regular under the relevant hero. Chips reserved for state on individual artifacts (the verified capsule on an answer footer, the route capsule on a chat header).

## Implementation order

### Sprint 1 — orchestrator and proof states (no UI shipping yet)

1. `AskOrchestrator`: decides route/tools/proof for a given prompt+project+attachments.
2. `ProofState` enum (`unknown / verifying / verified / stale / mismatch / private_ / proxied / unverified`) and the single capsule component that renders all eight.
3. Snapshot tests on a 20-prompt fixture set: project files referenced, no project, "latest" prompt, agentic verb, decision question, attachment, none.
4. `Verify` / `Verified` / `Verification` copy migration in code (banned: `attestation` outside engineering paths).

### Sprint 2 — Home and Composer collapse

1. Home: kill the three-CTA hero. Ship the single `Ask NEAR` card with the plain-language sentence beneath.
2. Composer: kill the focus chip row. Ship the project-aware verb-first chips. Keep visible Model / Council / Effort controls. Move proof to answer footer.
3. Migrate all `Color.brandBlue` references to semantic tokens, cap at one saturated blue per scene.

### Sprint 3 — inline agent offers, configuration-as-recovery

1. Agentic-intent detection inline in composer + chat. Inline `Run as agent?` card.
2. Cloud-key recovery sheet on demand only.
3. IronClaw connect via in-thread offer; deep-link into Account → IronClaw bridge; return to chat.
4. Delete the `Agent` sheet as a destination. Delete the `Connect Agent` standalone sheet.

### Sprint 4 — model picker as override surface

1. Picker becomes three categorical choices + a `Show all models` disclosure.
2. Remove every chip from the picker that isn't `Verified` / `Private` / `Cloud` / `Plan`.
3. `Connect token` moves out of model rows into the agent connect flow.

### Sprint 5 — setup deletion + account simplification

1. Delete the Setup screen entirely. Sign-in goes Terms → Home.
2. `Run Setup Again` becomes `Reset defaults`.
3. Move Web Search, Large Paste as File, System Prompt behind Power Tools.
4. Render all dates human-readable.

### Sprint 6 — Project Context, Sharing, Live Activity

1. Project Context: dedupe Add affordance, collapse "What this project knows" after first visit.
2. Shared: add the read-only badge + sender row.
3. Agent runs >30s surface to Lock Screen via `BGContinuedProcessingTask` + Live Activity. Current step + Stop on the lock screen.

## What's measurable when this lands

If the orchestrator is working, the following metrics should move (telemetry should be added inside the orchestrator boundary only, not on individual UI elements):

- **Apology-turn rate** (assistant turns containing "I can't access" / "switch to" / "this route doesn't") → target zero.
- **Pre-send capability conflict rate** (user sent on a route that couldn't fulfill) → target zero by Sprint 2.
- **Setup-completion friction** → eliminated; metric becomes "time from install to first sent message," target ≤30 seconds.
- **Configuration interruptions** (Cloud-key sheet, IronClaw sheet, etc.) per session → median 0, p95 ≤1.
- **Model / Council control success** → users can switch GLM, IronClaw, Cloud, Council, and Effort from chat without visiting Account.
- **Power Tools enable rate** → 5-15% steady-state. Higher means defaults are wrong; lower means the power user is being underserved.

## What this spec deliberately does not do

- **Doesn't redesign the Project Context sheet.** It's already the best surface in the app.
- **Doesn't introduce Live Activities outside Agent runs.** Tempting to lock-screen the verification freshness; defer.
- **Doesn't ship a "Council" top-level destination.** Council remains an inline offer when a prompt is decision-shaped.
- **Doesn't kill IronClaw branding entirely.** It stays in Power Tools and engineering docs. The default UI just doesn't lead with it.
- **Doesn't redesign the verifier web page.** Adjacent project; out of scope for this pass.

## North-star reminder

> Open app. Ask anything. NEAR answers privately when it can, researches when needed, uses project context when available, and offers to act when a task requires an agent. Advanced controls are there, but the product earns trust by choosing well before asking the user to configure anything.

When you next see a design proposal that asks the user to choose between Web / Files / Links / Research before they've typed anything, push back to this north star. When you see a proposal that hides GLM, IronClaw, Cloud, Council, or Effort from the chat window, push back just as hard. The product should feel agentic out of the box and still let the user steer the engine.
