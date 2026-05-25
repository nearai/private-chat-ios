# NEAR Private Chat iOS Onboarding, Design, And Functionality Review

Date: 2026-05-25
Scope: current `NEARPrivateChatIOS` source review, focused on first-run onboarding, design utility, feature readiness, and what to hand to Claude/Codex next.

Concrete implementation companion: [NEARPrivateChatIOS-product-punchlist-2026-05-25.md](/Users/abhishekvaidyanathan/Documents/Playground/NEARPrivateChatIOS/review-artifacts/NEARPrivateChatIOS-product-punchlist-2026-05-25.md:1), especially Packet P9 for Beginner mode, Welcome project, and setup-to-first-action routing.

## Executive Verdict

Your read is basically right: onboarding has engineering machinery, but low product utility. It is not a guided first-use experience yet. It is a settings mutator with a friendly face.

The strongest issue is worse than "it does not help": several onboarding controls can be overridden at finish time, so users can make choices that the app immediately ignores. The app then lands them on the same power-user home screen, with no setup-aware first action, no readiness check, and no obvious proof that their setup mattered.

That means onboarding currently does three useful things:

- Creates/selects a starter project for Research, Agents, or Projects.
- Sets model/source defaults.
- Saves an account-scoped profile for reruns.

But it fails at the job users need most:

- Explain what the app is.
- Get the user to one successful first chat.
- Avoid unavailable routes.
- Make setup choices visibly change the product.

## Highest-Severity Findings

### P1: Onboarding Toggles Are Not Trustworthy

The setup screen exposes toggles for live web, IronClaw, and LLM Council, but `normalizedForDefaults` forces some of them back on or off based on selected use cases.

Relevant source:

- `NEARPrivateChat/NEARPrivateChatApp.swift:227-245` shows the toggle UI.
- `NEARPrivateChat/NEARPrivateChatApp.swift:265-268` finishes with `profile.normalizedForDefaults`.
- `NEARPrivateChat/NEARPrivateChatApp.swift:144-146` normalizes again before applying.
- `NEARPrivateChat/Models.swift:792-810` overrides user choices.

Concrete examples:

- If Research is selected, `wantsCouncil` is forced true even if the user turned "Enable LLM Council option" off.
- If Research, Build Agents, or Projects is selected, `wantsWeb` is forced true even if the user turned live web off.
- If Build Agents is selected, IronClaw is forced on and Council is forced off.
- If a non-private use case is selected and the user chooses Simple context, setup can force Project context.

This is the single biggest onboarding bug. Either make these controls read-only recommendations, or make explicit user toggles authoritative.

### P1: Goal Text Is Captured But Not Used

The wizard asks "Tell the app what you want help with", displays it in the preview, and saves it. After setup, that goal is not used by the app.

Relevant source:

- `NEARPrivateChat/NEARPrivateChatApp.swift:198` collects goal text.
- `NEARPrivateChat/NEARPrivateChatApp.swift:492-493` displays it in the setup preview.
- `NEARPrivateChat/Models.swift:732` stores it on `UserSetupProfile`.
- `NEARPrivateChat/ChatStore.swift:1367-1398` applies setup without reading `goalText`.

The goal should drive at least one of:

- A prefilled first prompt.
- Starter project instructions.
- A post-setup landing card.
- Personalized empty-state prompt chips.

Right now it is dead data.

### P1: Setup Does Not End In A First Successful Action

`completeSetup` applies defaults and dismisses. The user lands on the generic home screen, which always shows the command header, search, workspace rows, projects, and chat list.

Relevant source:

- `NEARPrivateChat/NEARPrivateChatApp.swift:138-149` applies and dismisses setup.
- `NEARPrivateChat/AppShellView.swift:153-256` renders the same home structure regardless of setup outcome.
- `NEARPrivateChat/AppShellView.swift:5625-5713` renders route/project-based empty prompts, not saved profile/goal-based prompts.

The preview says "First action", but the app does not route the user into that first action. That makes setup feel ceremonial.

Expected behavior:

- Private Chat -> open a new chat with "Ask privately" ready.
- Research -> open a sourced research chat, with Research focus visible.
- Build Agents -> open Agent readiness or mission control, depending on bridge status.
- Projects -> open project workspace with "Add file", "Add link", and "Create first chat".
- Beginner/Power mode -> make the choice explicit in onboarding. Hide Agent, Council, NEAR Cloud, and Developer affordances only when the user chooses Beginner; do not silently hide paid/power features from users who opt into Power.
- Welcome project -> seed useful first-run material: sample file, sample link, concise/cite-sources instruction, and one example Council chat.

### P1: Setup Is Not Readiness-Aware

Setup can guide the user into routes that are not usable yet.

Relevant source:

- Bootstrap loads conversations, models, billing, IronClaw tools, and shared items concurrently in `NEARPrivateChat/ChatStore.swift:759-768`.
- Setup application selects IronClaw/Council in `NEARPrivateChat/ChatStore.swift:1372-1380`.
- Council availability depends on model catalog and plan state in `NEARPrivateChat/ChatStore.swift:5226-5248`.
- NEAR Cloud send fails without a key in `NEARPrivateChat/ChatStore.swift:3177-3179`.
- NEAR Cloud and IronClaw setup live later in Account at `NEARPrivateChat/AppShellView.swift:4940-5033`.

The setup wizard should not say or imply "agent ready" or "council ready" unless the route can actually run. It needs a readiness snapshot:

- Model catalog loaded.
- Billing/plan loaded.
- Council lineup available.
- IronClaw Mobile available.
- Hosted IronClaw endpoint/token status.
- NEAR Cloud key status.
- Pending shared-link intent.

### P1: Privacy-Preserving Telemetry Exists But Is Not Wired Into The Product

There is a good local aggregate telemetry skeleton, but production setup actions do not record events.

Relevant source:

- `NEARPrivateChat/PrivateTelemetry.swift:75-85` defines onboarding, focus, prompt, attestation, share, stream, and error events.
- `NEARPrivateChat/PrivateTelemetry.swift:259-272` records local daily counters.
- Tests cover encoding and local aggregation in `NEARPrivateChatTests/PrivateChatCoreTests.swift:538-582`.
- No production callsite records setup selected/completed/skipped during `NEARPrivateChat/NEARPrivateChatApp.swift:191-268` or `NEARPrivateChat/NEARPrivateChatApp.swift:138-149`.

This creates a strategic blind spot: onboarding quality cannot be measured without either privacy-safe instrumentation or deliberate no-telemetry policy. The code already points toward local counters; wire them deliberately and expose the policy in Account.

## Design And Functionality Review

### What Has Improved Since The Earlier Audit

Several of the earlier high-value design items have been implemented or partially implemented:

- Auth is cleaner. Shared link is above developer token, and token sign-in is hidden behind a debug disclosure (`NEARPrivateChat/AuthView.swift:28-52`).
- Auth copy now leads with "Verified private AI chat with cryptographic proof" (`NEARPrivateChat/AuthView.swift:112-128`).
- Home project metadata hides zero counts (`NEARPrivateChat/AppShellView.swift:378-418`).
- Home status grammar is closer to `Noun: state`, for example `Privacy: verified`, `Web: on`, `Sources: 1` (`NEARPrivateChat/AppShellView.swift:637-668`).
- Composer now has a Focus row and a filled send/stop button (`NEARPrivateChat/AppShellView.swift:7288-7557`).
- Model picker has `Models | Council` tabs (`NEARPrivateChat/AppShellView.swift:1661-1760`).
- Model row badges are capped tighter than before (`NEARPrivateChat/AppShellView.swift:2057-2089`).
- Chat header now has a persistent attestation button in compact mode (`NEARPrivateChat/AppShellView.swift:1174-1248`).
- Security includes education copy: "Proof, not a promise" (`NEARPrivateChat/AttestationStatus.swift:284-318`, `NEARPrivateChat/AppShellView.swift:5310-5455`).
- Public link flow now uses "Review Public Link" plus preview and confirmations (`NEARPrivateChat/AppShellView.swift:2240-2509`).
- Permanent delete now routes through a confirmation dialog with "Archive Instead" (`NEARPrivateChat/AppShellView.swift:37-58`, `NEARPrivateChat/ChatStore.swift:1920-1957`).
- Conversation-load race and cache masking appear meaningfully improved with generation guards and network refresh after cached display (`NEARPrivateChat/ChatStore.swift:2410-2490`).

This is real progress. The remaining problem is not "nothing was implemented"; it is that the first-run product story still does not cohere.

### Home Still Feels Like Three Products

The home hero still presents Ask, Agent, and Project/Context at the same level.

Relevant source:

- `NEARPrivateChat/AppShellView.swift:551-669`

That is good for a demo. It is rough for first use. Users have not earned the Agent/Context vocabulary yet. The home screen should initially privilege one action:

- "Ask privately" as the primary path.
- Agent and Project revealed after setup selection or after first chat.
- A small "Change setup" entry, not a permanent command-center posture.

### Empty States Are Better, But Still Not Setup-Aware

The empty chat screen has prompt chips now, which is a good improvement.

Relevant source:

- `NEARPrivateChat/AppShellView.swift:5625-5713`

But the logic is derived from selected provider/project/research route, not from the saved setup profile or the user's stated goal. That means onboarding and empty state are not connected. A user who typed a goal sees no direct payoff.

### Composer Is Near Parity, With One Conceptual Problem

The Focus row is a strong improvement:

- Auto
- Web
- Files
- Links
- Research

Relevant source:

- `NEARPrivateChat/AppShellView.swift:7288-7557`

Remaining issues:

- Research is still a behavior bundle. Selecting it forces `sourceMode = .web` and turns research on (`NEARPrivateChat/AppShellView.swift:7533-7539`).
- Tapping Research again does not toggle it off; users must pick another focus mode.
- NEAR Cloud disables the whole focus row (`NEARPrivateChat/AppShellView.swift:7514-7523`) but does not turn that disabled state into a clear next action such as "Add key" or "Switch route".

### Share Is Much Safer, But Expiry Copy Is Premature

The public-link flow is much better now: review first, invite visible, disable confirmation.

Relevant source:

- `NEARPrivateChat/AppShellView.swift:2228-2237`
- `NEARPrivateChat/AppShellView.swift:2425-2509`

But the expiry menu lists 7 days and 30 days while `isAvailable` only allows manual disable. That is probably fine as a roadmap hint for internal demos, but it reads broken to a normal user.

Recommendation: hide unavailable expiry choices until backed by API, or label them "Coming soon" in a disabled footer.

### Account Is Cleaner, But Still Too Technical For The Default User

Connection and advanced params are behind a disclosure now, which is good. But Models and Integrations still expose API keys, endpoints, bridge tokens, thread IDs, hosted agent toggles, and diagnostic actions in the normal Account sheet.

Relevant source:

- `NEARPrivateChat/AppShellView.swift:4798-5033`

Recommendation:

- Default Account: Profile, Plan, Privacy, Setup, Sign out.
- Developer/Integrations: NEAR Cloud key, IronClaw bridge, diagnostics, imports, advanced params.

### Attestation Is Becoming The Differentiator

This is the best current product direction:

- Persistent header indicator.
- Per-message attestation surfaces.
- Security report.
- Education copy.
- Signed export warning.

Relevant source:

- Header: `NEARPrivateChat/AppShellView.swift:1174-1248`
- Message chip surfaces: `NEARPrivateChat/AppShellView.swift:6369-6534`
- Security sheet: `NEARPrivateChat/AppShellView.swift:5310-5455`

Next step is not more raw detail. Next step is linking attestation to user workflows:

- "Verified private route" in setup.
- "Only use verified private models" mode.
- Signed transcript verifier page/tool.
- Clear state when route changes to Cloud/IronClaw/Council.

## Engineering And Reliability Review

### Resolved Or Improved

- Account-scoped setup storage exists and is tested (`NEARPrivateChat/Models.swift:961-1012`, `NEARPrivateChatTests/PrivateChatCoreTests.swift:270-300`).
- Conversation-load generation guards exist (`NEARPrivateChat/ChatStore.swift:2410-2490`).
- Cached messages are displayed optimistically, then remote fetch still runs (`NEARPrivateChat/ChatStore.swift:2441-2467`).
- Delete confirmation exists.
- Telemetry has privacy-safe data structures and tests, even if not wired.

### Still High Risk

#### Streaming Resilience

The Responses API stream uses `URLSession.shared.bytes` and iterates lines. There is parsing and timeout handling, but no explicit cell-handoff resume/reconnect model.

Relevant source:

- `NEARPrivateChat/PrivateChatAPI.swift:544-556`
- `NEARPrivateChat/ChatStore.swift:2574-2603`

Mobile chat quality will depend on retry/resume semantics.

#### Monolith Risk

The core files are too large:

- `AppShellView.swift`: 8,245 lines.
- `ChatStore.swift`: 6,896 lines.
- `Models.swift`: 2,753 lines.

This is not a moral issue. It is a change-risk and SwiftUI render-performance issue. Onboarding, share, agent, model picker, attestation, markdown, projects, and composer all share a single huge UI file.

#### Mac Later, But Current Target Is iPhone-Only

User direction is to finish iOS first and consider Mac later. Current project settings are iPhone-only and portrait-only:

- `NEARPrivateChat/Info.plist:44-47`
- `NEARPrivateChat.xcodeproj/project.pbxproj:403-408`

No need to spend iPad time now. For Mac later, plan a separate "Mac readiness" pass after iPhone first-run quality is fixed.

## What The Onboarding Should Become

Replace the current setup page with a utility-first first-run flow.

### Step 1: Pick First Job

One screen:

- Ask privately.
- Research with sources.
- Work with project files.
- Use agent/code tools.
- Open a shared link, if pending.

Avoid early labels like IronClaw, LLM Council, source mode, and endpoint unless the user chose the advanced path.

### Step 2: Show Recommended Setup

Show a compact summary:

- Route: Verified private model / Council / Agent.
- Focus: Auto / Web / Files / Links / Research.
- Workspace: None / Research Room / Agent Workspace / Project Workspace.
- Requirements: Ready / needs API key / needs hosted bridge / needs model access.

Every editable control here must be authoritative. If it is a recommendation, label it as a recommendation.

### Step 3: Land On The First Action

Do not dismiss to generic home. Route directly:

- Ask privately -> new chat composer with private prompt chips.
- Research -> new chat with Research focus and "Start sourced brief" prompt.
- Project files -> project workspace with Add file/Add link visible.
- Agent -> readiness screen if bridge missing, mission composer if ready.
- Shared link -> shared preview first, setup second.

## Claude/Codex Work Packets

### Packet A: Fix Onboarding Correctness

Goal: make setup choices truthful.

Tasks:

- Rewrite `UserSetupProfile.normalizedForDefaults` so explicit toggles are not silently overridden.
- If use-case selection sets recommended defaults, do that only when the user changes the use-case selection, not at Finish.
- Add tests for Research with web off, Research with Council off, Build Agents with Council off, Projects with Simple context, and multi-select priority.
- Rename or remove controls that are not meant to be user-authoritative.

Acceptance criteria:

- Every visible toggle/choice remains reflected after Finish.
- Tests fail if normalization re-overrides explicit choices.

### Packet B: Use Goal Text

Goal: make the user's stated goal visible immediately after setup.

Tasks:

- Carry `goalText` into starter project instructions and/or a post-setup card.
- Add "Start from your goal" prompt chip that fills the composer.
- If the goal is present, open a new chat after setup with the goal prefilled but not sent.
- Add tests for `goalText` trimming and downstream plan output.

Acceptance criteria:

- A user who types a goal sees that goal on the next screen.

### Packet C: Readiness-Aware Setup

Goal: stop setup from promising unavailable routes.

Tasks:

- Add a `SetupReadinessSnapshot`.
- Gate LLM Council on available eligible models.
- Gate hosted agent work on endpoint/token/tool verification.
- Gate NEAR Cloud on API key, or provide an inline key path.
- Treat shared-link launch as a first-class onboarding route.

Acceptance criteria:

- Build Agents does not say "ready" if hosted agent is not connected.
- Council setup shows a clear unavailable state if fewer than two eligible models exist.
- NEAR Cloud cannot become the active first-run route without a visible key requirement.

### Packet D: Post-Setup Landing

Goal: make setup visibly change the app.

Tasks:

- Add a dismissible post-setup card on home or route directly into chat.
- Add setup-aware empty prompt chips.
- Persist card dismissal per account/setup version.
- Add UI tests for each setup use case landing on the right first action.

Acceptance criteria:

- Completing each use case produces a distinct first screen and first CTA.

### Packet E: Home Information Diet

Goal: make the default first screen calm.

Tasks:

- Hide Agent/Context CTAs unless selected in setup or already used.
- Keep Ask as the only primary action.
- Separate system collections from user projects.
- Keep status line, but avoid showing advanced status before first chat.

Acceptance criteria:

- First-run home shows no more than one primary CTA and no more than eight visible concepts before the first chat.

### Packet F: Wire Private Telemetry

Goal: measure onboarding without betraying the privacy claim.

Tasks:

- Instantiate a `PrivateTelemetryStore`.
- Record setup goal selected, setup completed/skipped, focus mode changed, prompt chip used, attestation chip tapped, share preview opened, stream reconnects, and generic error categories.
- Keep upload disabled by default unless there is a clear opt-in.
- Add an Account row explaining local/private counters and exporting diagnostics.

Acceptance criteria:

- No prompt, response, URL, filename, account id, conversation id, transcript id, or raw error body is stored.
- Tests cover event recording from setup completion/skipping.

### Packet G: Reliability And Demo Readiness

Goal: make the app survive real phone demos.

Tasks:

- Add stream reconnect/resume policy for network interruption.
- Add a demo preflight surface that checks auth, model catalog, attestation, NEAR Cloud key, hosted IronClaw, web grounding, and file upload.
- Hide unsupported/disabled public-link expiry options.
- Add smoke tests for setup -> first chat -> attestation -> share preview.

Acceptance criteria:

- A demo account can be verified in-app before recording.
- Network interruption does not leave a silent half-answer without retry affordance.

## Recommended Immediate Decision

Do not polish the current onboarding screen. Rebuild its behavior first.

The highest-return next PR is:

1. Make setup controls authoritative.
2. Use `goalText` after setup.
3. Route completion into a first action.
4. Add readiness gating for Agent/Council/Cloud.

After that, the visual design pass will matter. Before that, the screen can look good and still perform almost no utility.
