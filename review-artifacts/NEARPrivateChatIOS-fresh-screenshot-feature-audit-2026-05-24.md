# NEAR Private Chat iOS Fresh Screenshot And Feature Audit

Date: 2026-05-24
Scope: latest local `NEARPrivateChatIOS` source review plus fresh simulator screenshot extraction.

## Verification

- Build and launch: `DERIVED_DATA_PATH="$PWD/build/DerivedDataFreshAudit" ./scripts/run-simulator.sh "iPhone 17 Pro"` completed with `BUILD SUCCEEDED`.
- Screenshot packet: `review-artifacts/screenshots-2026-05-24-fresh/`, zipped as `review-artifacts/screenshots-2026-05-24-fresh.zip`.
- Transcript verifier: `bash verifier/scripts/test-fixtures.sh` passed.
- Test inventory: `NEARPrivateChatTests/PrivateChatCoreTests.swift` now has 26 unit tests, up from the original thin suite.
- Full `xcodebuild test` was not rerun in this pass because an active background simulator smoke loop was repeatedly taking over the default simulator. The source and verifier checks below are still current.

## Screenshot Packet

| File | Screen |
| --- | --- |
| `screenshots-2026-05-24-fresh/00-setup.png` | First-run setup |
| `screenshots-2026-05-24-fresh/01-home.png` | Main home, all chats selected |
| `screenshots-2026-05-24-fresh/01b-home-project-selected.png` | Home with project selected |
| `screenshots-2026-05-24-fresh/02-new-chat-composer.png` | Empty new chat composer and focus row |
| `screenshots-2026-05-24-fresh/03-model-picker.png` | Model picker, Models tab |
| `screenshots-2026-05-24-fresh/04-model-picker-council.png` | Model picker, Council tab |
| `screenshots-2026-05-24-fresh/05-agent-workspace.png` | IronClaw Agent workspace |
| `screenshots-2026-05-24-fresh/06-new-project-sheet.png` | New Project sheet |
| `screenshots-2026-05-24-fresh/07-project-context.png` | Project Context, Sources tab |
| `screenshots-2026-05-24-fresh/08-project-library.png` | Project Context, Library tab |
| `screenshots-2026-05-24-fresh/09-account-settings.png` | Account settings |

Clean auth, populated chat, share, and security screenshots should be recaptured in a quiet simulator session. Those surfaces were reviewed from source in this pass.

## Highest-Risk Open Findings

### P1: Phone chat header still hides attestation too much

The underlying attestation system is now much stronger: `AttestationStatus`, education copy, per-message chips, signed export, and verifier work all exist. But on the phone toolbar, `ChatToolbar.body` renders `compactToolbar`, which shows model, optional agent, and overflow only. The dedicated `securityButton` and attestation metadata row are in other toolbar paths, not the compact phone path.

Evidence:
- `NEARPrivateChat/AppShellView.swift:1152` defines `ChatToolbar`.
- `NEARPrivateChat/AppShellView.swift:1166` renders `compactToolbar`.
- `NEARPrivateChat/AppShellView.swift:1229` to `1241` shows compact model/agent/more only.
- `NEARPrivateChat/AppShellView.swift:1278` to `1296` has attestation metadata, but this row is not what the captured phone toolbar shows.
- `NEARPrivateChat/AppShellView.swift:6003` to `6033` adds per-message attestation chips only after a relevant assistant message and snapshot exist.

Recommendation: add a persistent compact header shield beside the model chip. It should show `Verified <2m`, `Verified <1h`, `Stale`, `Mismatch`, or `Unknown`, and tap into the existing Security sheet.

### P1: Public-link sharing is still one tap with no preview or expiry

The Share sheet now has public links, direct grants, organization grants, and share groups. The dangerous part is still the public-link affordance: if public share is off, the user sees a primary `Enable Public Link` button that calls `enablePublicShare()` directly.

Evidence:
- `NEARPrivateChat/AppShellView.swift:2169` defines `ShareConversationView`.
- `NEARPrivateChat/AppShellView.swift:2292` to `2341` shows the public-link section and one-tap enable button.

Recommendation: insert a pre-enable preview sheet: title, message count, source count, whether account metadata is excluded, link expiry, read-only/write state, and attestation seal. Make `Invite People` a visible secondary action next to public link.

### P1: Undo is still missing for reversible actions

Permanent delete now has a confirmation dialog with `Archive Instead`, which fixes the original data-loss floor. But archive, move, link revocation, file removal, saved-output removal, and share-group delete still rely mostly on immediate actions and banners rather than a consistent undo system.

Evidence:
- `NEARPrivateChat/AppShellView.swift:37` to `58` confirms permanent conversation delete.
- `NEARPrivateChat/AppShellView.swift:263` to `276` still gives swipe archive/delete; archive is immediate.
- `NEARPrivateChat/AppShellView.swift:3187` to `3190`, `3247` to `3253`, and `3330` to `3332` show immediate project link/file actions.
- `NEARPrivateChat/AppShellView.swift:2323` to `2329` disables public links without a visible undo.

Recommendation: add a global undo banner model for archive, move, share disable, link delete, saved-output delete, and file detach. Keep permanent delete behind confirmation.

### P1: Home is improved but still has too many first-screen jobs

The home screen fixed several earlier issues: chip grammar is now closer to `Noun: state`, zero project counts are hidden, and system rows are clearer. But it still exposes search, the command hero, Ask, Agent, Context/Project, workspace rows, projects, recent chats, account footer, and a toolbar plus before the user has done one thing.

Evidence:
- `NEARPrivateChat/AppShellView.swift:128` to `156` shows search plus the command hero with Ask, Agent, and Project/Context actions.
- `NEARPrivateChat/AppShellView.swift:321` to `335` keeps the toolbar plus as another new-chat affordance.
- Screenshot: `01-home.png` and `01b-home-project-selected.png`.

Recommendation: make Ask the only primary new-chat action on home. Hide the toolbar plus or turn it into a secondary icon only after first conversation. Show Agent/Context based on setup intent or after the user selects a project/agent model.

### P1: Telemetry foundation exists but is not wired into product events

The missing strategy is no longer missing. There is now a local-only telemetry policy, enum schema, forbidden field list, disabled-by-default setting, and aggregation store. But source search shows the schema is currently tested and documented rather than called from setup, composer, picker, share, streaming, or attestation surfaces.

Evidence:
- `NEARPrivateChat/PrivateTelemetry.swift:75` to `85` defines the allowed event list.
- `NEARPrivateChat/PrivateTelemetry.swift:238` to `244` defaults usage sharing off.
- `NEARPrivateChat/PrivateTelemetry.swift:259` to `307` records local aggregate counters.
- `NEARPrivateChat/PrivateTelemetryPolicy.md` documents local-only behavior and forbidden content.
- `rg` found telemetry call sites only in tests/policy/definitions, not UI flows.

Recommendation: wire local event recording into setup, focus chips, model tabs, attestation taps, share preview, and reconnect events. Keep upload disabled until privacy copy and the app privacy manifest are updated.

### P1: Chat and app shell remain monolithic

The app has grown more capable, but the two largest files are now past the point where SwiftUI re-render and review risk are easy to reason about.

Evidence:
- `NEARPrivateChat/AppShellView.swift`: 7,649 lines.
- `NEARPrivateChat/ChatStore.swift`: 6,204 lines.
- `NEARPrivateChat/Models.swift`: 2,391 lines.

Recommendation: split by feature without changing behavior: `HomeView`, `ChatToolbar`, `InputBar`, `ProjectContextView`, `ShareConversationView`, `SecurityView`, `AgentWorkspaceView`, and separate store services for streaming, sharing, project context, attestation, telemetry, and IronClaw.

### P1: Mobile stream resilience is still underbuilt

The app handles stale running messages and fallback between models, but the core SSE path is still a direct `URLSession.shared.bytes(for:)` stream with no mobile resume protocol, exponential reconnect, event id tracking, or cell-handoff state machine.

Evidence:
- `NEARPrivateChat/PrivateChatAPI.swift:455` to `522` streams response lines.
- `NEARPrivateChat/ChatStore.swift:2829` to `2869` falls back between models, not resumes the same stream.
- `NEARPrivateChat/ChatStore.swift:5518` to `5536` marks old in-progress runs stale after interruption.

Recommendation: define explicit retry/resume semantics: request id, last event id or last completed output index, reconnect budget, offline banner, and final reconciliation from conversation items.

## What Is Now Meaningfully Better

- Auth now leads with OAuth and shared-link entry, while simulator/debug token sign-in sits behind `More sign-in options`.
  - `NEARPrivateChat/AuthView.swift:28` to `52`.
- Auth copy now leads with verified private AI and cryptographic proof.
  - `NEARPrivateChat/AuthView.swift:112` to `128`.
- Setup is account-scoped, loadable, migratable from fallback session/token identities, and prefilled on rerun.
  - `NEARPrivateChat/NEARPrivateChatApp.swift:108` to `147`.
  - `NEARPrivateChat/Models.swift:794` to `845`.
- Empty new chat now has setup/provider/project-aware prompt chips.
  - `NEARPrivateChat/AppShellView.swift:5111` to `5199`.
- Composer focus is now a single visible row: Auto, Web, Files, Links, Research.
  - `NEARPrivateChat/AppShellView.swift:6709` to `6975`.
- Send button now has real active and streaming states, with brand fill when sendable and red stop while streaming.
  - `NEARPrivateChat/AppShellView.swift:6813` to `6874`.
- Model picker has `Models | Council` tabs.
  - `NEARPrivateChat/AppShellView.swift:1668` to `1752`.
- LLM Council responses render as a grouped multi-answer surface with per-model selection.
  - `NEARPrivateChat/AppShellView.swift:1010` to `1150`.
- Overflow menu has been grouped into Navigate, Edit, Export, Organize, and Destructive sections.
  - `NEARPrivateChat/AppShellView.swift:1446` to `1577`.
- Verified JSON export exists.
  - `NEARPrivateChat/ConversationExport.swift:9` to `30`.
  - `NEARPrivateChat/ConversationExport.swift:127` to `185`.
- Open verifier package exists and passes fixtures.
  - `verifier/README.md`.
  - `verifier/public/index.html`.
  - `verifier/scripts/test-fixtures.sh`.
- Account screen moved connection/auth plumbing behind a Developer disclosure.
  - `NEARPrivateChat/AppShellView.swift:4392` to `4447`.
- Security sheet now includes education copy, report data, raw JSON disclosure, and refresh behavior.
  - `NEARPrivateChat/AppShellView.swift:4819` to `4925`.

## Screen-By-Screen Review

### 00 Setup

Strengths:
- Much better than the original: it is account-scoped, remembers profile choices, has a real plan preview, and lets the user choose Private Chat, Research, Agent Work, or Projects.
- The screen is visually coherent and gives a useful first-run sense of what the app can do.

Weaknesses:
- It still teaches five concepts at once: models, context, web, projects, and IronClaw. For first-run users, IronClaw and Council may be better as setup opt-ins behind "Advanced".
- `Skip` silently applies defaults. Add a one-line default preview before skip or after skip.

### 01 Home

Strengths:
- Status grammar is cleaner: `Privacy: verified`, `Web: on`, `Links: 1`.
- Project row metadata hides zero counts.
- System collections are more legible than before.

Weaknesses:
- The first screen still reads as Private Chat plus Agent plus Project workspace. That is true to the product, but too much for a new user.
- The toolbar plus competes with the hero Ask action.
- Brand blue remains heavily used for selected state, links, active chips, and action emphasis.

### 02 New Chat Composer

Strengths:
- The dead empty state is fixed with prompt chips.
- The focus row is a major improvement over the old source-mode popover.
- Project context strip and attachment strip are now correctly separated above the input.
- Send/stop state is now visually distinct.

Weaknesses:
- Research is now visually one focus chip, but under the hood it still toggles research and forces web mode. Keep tests around that interaction.
- The compact header does not surface a persistent attestation shield.

### 03/04 Model Picker And Council

Strengths:
- `Models | Council` tabs make the flagship Council feature discoverable.
- Model descriptions and sections are easier to scan than the old over-tagged flat list.
- "Upgrade: 29 more" is better than "29 locked hidden."

Weaknesses:
- The summary card can still carry too many concepts at once: provider, model count, plan, web, private route, Council, IronClaw readiness.
- Council disagreement is not first-class. The app shows multiple answers, but it does not yet extract "where models disagreed" as a report.

### 05 Agent Workspace

Strengths:
- This remains one of the strongest branded surfaces.
- Context affirmation at the bottom is a good pattern and should be reused elsewhere.
- Prompt examples make the agent surface more usable.

Weaknesses:
- Capability chips such as Coding, Local Test, and GitHub can still read as filters. If they are static capabilities, style them less like controls.
- Auto skills is visible, but still secondary compared with the mission input.

### 06 New Project

Strengths:
- The new-project sheet is clear and practical.
- Project creation pairs well with setup and Context.

Weaknesses:
- Project icon/color still appears absent from the user-facing project list. This is a cheap scanning win.
- Project default tools/source mode are not yet obvious.

### 07/08 Project Context And Library

Strengths:
- The hero card is still one of the best design elements.
- Library now feels more real: file preview, attach to prompt, add to project, delete, and refresh are visible in source and screenshots.

Weaknesses:
- Taxonomy is still too broad: Sources, Library, Guide, Saved. Users likely perceive "attached stuff", "files", "instructions", and "saved notes".
- Add-link form still appears below the list. It should be above the list or behind a single `Add link` affordance.
- File/link delete actions need confirmation or undo.

### 09 Account

Strengths:
- `Run Setup Again` now explains that it keeps chats/projects/account.
- Diagnostics are clearer.
- Developer connection details are behind a disclosure.

Weaknesses:
- Account still carries too many advanced routes: NEAR Cloud key, IronClaw Bridge, diagnostics, billing, imports, share groups, and chat settings. That is fine for test builds, but production should likely split Account from Developer/Integrations.

## Feature Inventory

| Area | Current status | Notes |
| --- | --- | --- |
| Auth | Strong | NEAR, Google, GitHub, shared-link entry, debug token behind disclosure |
| Setup | Stronger | Account-scoped, prefilled, migratable, real defaults preview |
| Home | Feature-rich, still crowded | Needs final information diet |
| Chat | Strong | Streaming, stop, regenerate, edit and branch, markdown, sources, attachments |
| Composer | Much improved | Focus row and active send state implemented |
| Models | Strong | Sections, search, plan awareness, private routes, NEAR Cloud route |
| Council | Strong but underexploited | Multi-answer view exists; disagreement artifact missing |
| Projects | Strong | Instructions, memory, links, files, notes, scoped chats |
| Files | Good | Upload, remote library, preview, attach, add to project, delete |
| Agent | Differentiated | IronClaw Mobile and hosted bridge are deep, but need simpler affordances |
| Sharing | Feature-rich, safety gap | Public link, grants, orgs, groups, write permission; preview/expiry/undo missing |
| Security | Category-leading | Attestation, education, raw report, message chips; compact header still weak |
| Export | Strong | TXT, JSON, PDF, signed verified JSON |
| Verifier | Strong | NPM-style verifier and web page exist; fixtures pass |
| Telemetry | Foundation only | Local-only schema exists; not wired into UI events |
| iOS surfaces | Missing | No App Intents, WidgetKit, ActivityKit, Live Activities |
| Mac path | Later | Project is iPhone-only and Mac support disabled for now |

## Claude/Codex Work Packets

### Packet A: Attestation Visibility

Add compact chat-header shield. Reuse `AttestationStatus` and `SecurityView`. Show freshness and route coverage. Add UI tests/snapshot tests for unknown, valid, stale, and mismatch.

### Packet B: Share Safety

Add public-link preview, expiry, invite-first secondary action, and revocation undo. Include attestation seal in preview and public share metadata if available.

### Packet C: Home Information Diet

Remove or demote toolbar plus. Gate Agent/Context on setup intent, selected project, or agent model. Reduce first-screen concepts to Ask, Search, Workspace, Projects/Chats, Account.

### Packet D: Undo Infrastructure

Create a reversible action banner model in `ChatStore` or a small `UndoStore`. Start with archive, move, share-disable, project link delete, saved output delete, and file detach.

### Packet E: Taxonomy Cleanup

Rename project tabs and copy to fewer concepts. Proposed user-facing taxonomy:
- Sources: links and files attached to answers or projects.
- Files: persistent private file library.
- Instructions: project guidance and memory.
- Notes: saved outputs.

### Packet F: Telemetry Wiring

Keep local-only and disabled-by-default, but record enum events for setup, focus-mode, prompt chips, model tabs, share preview, attestation taps, and stream reconnects. Add a diagnostics export button only in Developer/Diagnostics.

### Packet G: Stream Resilience

Implement mobile reconnect semantics. Add tests for partial stream, network drop, cancel, stale run reconciliation, and final remote conversation refresh.

### Packet H: Monolith Split

Move views out of `AppShellView.swift` by screen. Move sharing, attestation, project, telemetry, and streaming operations out of `ChatStore.swift` into smaller collaborators.

### Packet I: iOS Native Surfaces

After core iPhone polish, add App Intents first:
- Start verified chat.
- Ask NEAR Private about selected text.
- Open shared link in NEAR Private Chat.

Then consider widgets or Live Activity for active-session attestation freshness. Mac can follow once iPhone UX is stable.

## Bottom Line

The implementation has caught up with a surprising amount of the previous audit. The product is no longer missing the strategy layer for telemetry, attestation education, model-picker structure, focus modes, signed export, or verifier infrastructure.

The next bottleneck is polish and trust visibility: make attestation impossible to miss, make public sharing safer, give reversible actions undo, and reduce home/composer/settings density. Once those land, NEAR Private Chat will feel much less like a powerful prototype and much more like a category-defining iOS app.

