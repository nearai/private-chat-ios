# NEAR Private Chat iOS Feature And Design Audit

Date: 2026-05-24
Scope: `NEARPrivateChatIOS` native SwiftUI app, source review plus simulator design capture.

Status note: this audit is preserved as the original source/design pass. For current implementation status and work packets, use `review-artifacts/NEARPrivateChatIOS-competitive-onboarding-roadmap.md` plus `review-artifacts/NEARPrivateChatIOS-design-review-addendum.md`. Several findings below are now marked fixed in the roadmap, including permanent-delete confirmation, Run Setup Again, Saved links restoration, protected file-backed persistence, stale-token shared reads, and the privacy manifest.

## Verification

- `./scripts/build-simulator.sh` passes.
- `xcodebuild test -project NEARPrivateChat.xcodeproj -scheme NEARPrivateChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO` passes.
- Current test coverage is thin: 5 core tests covering auth callback state and role/import normalization.

## Screenshot Set

Screenshots are in `review-artifacts/screenshots/`.

| File | Screen |
| --- | --- |
| `00-auth-sign-in.png` | Signed-out auth screen |
| `01-chats-home.png` | Main chats/projects home |
| `02-new-chat-composer.png` | Empty chat composer |
| `03-chat-thread.png` | Populated chat transcript |
| `04-model-picker.png` | Model picker and LLM Council |
| `05-source-mode-menu.png` | Composer source/research menu |
| `06-chat-more-menu.png` | Chat overflow/action menu |
| `07-project-context.png` | Project Context sheet |
| `08-account-settings.png` | Account/settings sheet |
| `09-agent-workspace.png` | IronClaw Agent workspace |
| `10-security-attestation.png` | Security/attestation sheet |
| `11-share-collaboration.png` | Share/public-link sheet |
| `12-file-library.png` | Project file library |
| `13-action-menu-demo.png` | Demo action menu frame |

## Feature Inventory

### Auth And Onboarding

- OAuth sign-in for NEAR, Google, and GitHub via hosted auth callbacks.
- Manual session-token entry for internal testing.
- Custom callback scheme: `nearprivatechat://auth`.
- OAuth state is now generated, persisted, and validated before accepting a token.
- First-run setup captures use case, context style, web preference, IronClaw interest, and LLM Council preference.

### Chat Core

- Conversation list, search, grouping by recency, selection, new chat, rename, pin, archive, delete, clone/copy-and-continue.
- Streaming responses through `/v1/responses` with `web_search`, `signing_algo: ecdsa`, model params, previous response ids, edit/regenerate initiators, and source events.
- Stop/cancel streaming.
- Regenerate and edit-message branching.
- Markdown rendering for headings, bullets, quotes, code blocks, tables, inline formatting, source chips, and long-output sheets.

### Models And Routing

- Model catalog from `/v1/model/list`.
- Private-first model ranking with hidden/locked models and plan awareness.
- Optional NEAR Cloud Qwen route once API key is configured.
- LLM Council mode with 2-4 selected models, parallel answers, isolated per-model failures, and synthesis.
- Open-weight preference for IronClaw Mobile.

### Sources, Files, And Projects

- Prompt attachments through `/v1/files`.
- 10 MB upload cap.
- Readable PDFs are converted to text before upload.
- Large pasted text can auto-promote to `.txt`.
- Local projects with instructions, memory, saved notes, source links, project files, and per-project conversation scoping.
- Source modes: Auto, Web, Saved links, Files, Web + Files, plus Research mode.
- Remote file library with fetch, preview, attach-to-prompt, add-to-project, and delete.

### IronClaw

- Phone-first IronClaw Mobile route with native tool planning and local project/chat/source-mode actions.
- Hosted IronClaw bridge settings, token storage, connection test, workstation capability test, and diagnostics.
- Approval/authentication cards for gated IronClaw actions.
- Local scripts for simulator, smoke checks, hosted bridge setup, and overnight loops.

### Sharing And Collaboration

- Public read-only links.
- Open shared link before/after sign-in.
- Shared With Me inbox.
- Copy shared conversation into owned chat.
- Writable shared-open path when API says `can_write`.
- Direct invites by email/NEAR account, organization patterns, read/write permissions, remove-access.
- Share groups with create/edit/delete/member preview.

### Account, Diagnostics, Billing, Export

- Account sheet with profile, endpoint/callback/auth display, setup rerun, diagnostics, chat settings, billing, NEAR Cloud key, IronClaw bridge, import, share groups, sign out.
- Billing visibility via subscription plans/subscriptions.
- Chat import from native and legacy JSON.
- Export current transcript as TXT, JSON, PDF; copy transcript.
- Archived chat sheet with restore/delete/export.
- Security sheet with attestation report.

## Design Extraction

### Visual Language

- Brand is NEAR AI plus the Private Chat icon.
- Primary blue is `Color.brandBlue` / `#0091FD`, with cyan-blue active surfaces and pale blue selected rows.
- App background is a very light off-white/blue-tinted system surface. Sheets use grouped iOS card sections.
- Corners are generally 8 px continuous rectangles for controls/cards; larger sheet/content cards inherit SwiftUI grouped forms.
- SF Symbols are used heavily for scanability: lock, globe, folder, paperclip, terminal, shield, link, doc, archive, trash.
- The main home motif is a dark blue/black command card with three primary actions: Ask, Agent, Context.

### Layout Patterns

- Phone-first single-column navigation stack.
- Home screen is both navigation and command center: search, hero action card, project list, conversation list, account footer.
- Chat screen uses a compact top toolbar, metadata line, transcript, and a bottom two-row composer.
- Secondary workflows are mostly modal sheets: model picker, project context, account, share, security, shared link, agent workspace.
- Menus are used for dense option sets: source mode, chat overflow, move-to-project.

### UX Strengths

- Strong first-viewport identity: signed-out screen and home both communicate NEAR Private Chat clearly.
- The command-card home works well for demo posture: Ask/Agent/Context are obvious.
- Project context is visually coherent and makes links/files/saved notes feel like one workspace.
- Composer exposes source mode and files without burying them in account settings.
- Security and attestation have a dedicated surface, which matches the product claim.
- Chat output controls are compact and useful: copy, save, open output, regenerate.

### UX Weaknesses

- The product has too many advanced concepts visible at once: NEAR Private, NEAR Cloud, IronClaw Mobile, hosted bridge, workstation, source modes, Research, LLM Council, projects, share groups, billing, attestation.
- Many important commands are hidden in a long overflow menu, including share, export, rename, project creation, move, pin, archive, delete.
- The same action appears in multiple places with slightly different names: Context, Project Context, Project Files, Sources, Library, Saved.
- "Agent ready", "Private", "Web on", "Research", and "Project Selected" are concise but not always self-explanatory for non-builders.
- Account settings are doing too much: profile, diagnostics, imports, billing, NEAR Cloud, IronClaw bridge, share groups, setup, and sign out.
- Share UI and public-link enablement need extra care because the action changes external access, but the current visual hierarchy makes it feel like a normal utility action.

## Current High-Value Findings

### P1: Conversation Loading Race Can Show The Wrong Transcript

`selectConversation` starts an untracked `Task { await loadMessages(for:) }`. `loadMessages` later assigns the global `messages` array without checking that the selected conversation is still the same. Rapidly tapping two chats, or selecting a response variant then switching, can let the slower older request overwrite the newer chat's transcript.

Relevant source:
- `NEARPrivateChat/ChatStore.swift` lines 823-830
- `NEARPrivateChat/ChatStore.swift` lines 2106-2125
- `NEARPrivateChat/ChatStore.swift` lines 2132-2138

Suggested fix:
- Add a `messageLoadGeneration` or `loadingConversationID` guard.
- Cancel any in-flight load when selecting a new conversation.
- Apply loaded messages only when `selectedConversation?.id == conversation.id`.
- Add tests with a mock API that returns responses out of order.

### P1: Cached Local Messages Can Mask Server Truth

`loadMessages` returns early if any local cached messages exist. That is useful for external/local model routes, but it can prevent fresh server messages, shared updates, branch updates, or remote device changes from ever being fetched for that conversation.

Relevant source:
- `NEARPrivateChat/ChatStore.swift` lines 2106-2119
- `NEARPrivateChat/ChatStore.swift` lines 3530-3534

Suggested fix:
- Treat cache as immediate optimistic display, then always refresh network in the background.
- Restrict local-only cache to external/IronClaw conversations or include a cache type marker.
- Merge remote items with locally persisted external assistant messages.

### P1: Destructive Conversation Deletes Lack A Confirmation Layer

The list swipe action and overflow menu call delete directly. This is a real data-loss path for conversations and is easier to hit than the importance of the action suggests.

Relevant source:
- `NEARPrivateChat/AppShellView.swift` lines 221-225
- `NEARPrivateChat/AppShellView.swift` lines 1462-1467
- `NEARPrivateChat/ChatStore.swift` lines 1655-1672

Suggested fix:
- Prefer Archive as the primary destructive-looking action.
- Add confirmation dialog for permanent delete.
- Consider undo banner for deletes or route all deletes through archive first.

### P1: Test Coverage Is Still Far Behind The Feature Surface

The suite now passes, but it only covers auth state and role/import normalization. The riskiest surfaces have no unit or UI coverage: stream event parsing/completion, conversation-load races, local cache behavior, source modes, file upload/PDF behavior, share permissions, billing/model gating, IronClaw polling/gates, export, setup rerun, and destructive actions.

Relevant source:
- `NEARPrivateChatTests/PrivateChatCoreTests.swift`
- `NEARPrivateChat.xcodeproj/project.pbxproj` test target entries

Suggested fix:
- First add protocol seams for API clients and persistence.
- Build deterministic unit tests for ChatStore and PrivateChatAPI.
- Add 2-3 XCUITests for auth screen, home-to-chat, model picker/source mode, and share/security sheet visibility.

### P2: Plain File Upload Can Block The Main Actor And Reads Whole Files Into Memory

Readable PDF extraction is detached now, but non-PDF uploads still call `Data(contentsOf:)` in `PrivateChatAPI.uploadFile`. Because the call originates from `@MainActor` ChatStore and the read happens before the first suspension, this can still block UI. It also reads the whole file into memory.

Relevant source:
- `NEARPrivateChat/PrivateChatAPI.swift` lines 169-183
- `NEARPrivateChat/ChatStore.swift` lines 1498-1537

Suggested fix:
- Move file data reads into detached/background work.
- Consider streaming multipart upload or at least limit memory pressure.
- Add cancellation/progress feedback for larger files.

### P2: UserDefaults Stores Large/Sensitive Chat And Project Content

Projects, local messages, selected settings, system prompt, and cached conversations are stored in UserDefaults. This will bloat over time and stores sensitive chat/project context in a storage layer designed for small preferences.

Relevant source:
- `NEARPrivateChat/ChatStore.swift` lines 35-80
- `NEARPrivateChat/ChatStore.swift` lines 3525-3534
- `NEARPrivateChat/ChatStore.swift` line 117

Suggested fix:
- Move chat/project/cache payloads to file-backed JSON or SQLite.
- Set iOS data protection attributes.
- Add schema versioning, max size, eviction, and clear-cache controls.

### P2: IronClaw SSE Consumer Appears Unused

`streamPrompt` sends a prompt and then polls history until finished. `consumeEvents` exists but has no call site in the current path. This creates two maintenance paths and likely explains why hosted IronClaw streaming feels less live than Responses API streaming.

Relevant source:
- `NEARPrivateChat/IronclawAPI.swift` lines 153-181
- `NEARPrivateChat/IronclawAPI.swift` lines 487-525

Suggested fix:
- Either wire SSE into `streamPrompt` and fall back to polling, or delete/quarantine `consumeEvents` as future work.
- Add tests for failed/completed/running/empty IronClaw states.

### P2: Source Mode Semantics Are Powerful But Easy To Misread

The UI says "Saved links" or "Project Selected", while internally `.links` still makes `effectiveWebSearchEnabled` true. The prompt asks the model to avoid broad web unless needed, but the visible chip can read as web enabled. NEAR Cloud also says it has no web tools while app-side web grounding can still inject source packs.

Relevant source:
- `NEARPrivateChat/ChatStore.swift` lines 300-313
- `NEARPrivateChat/ChatStore.swift` lines 5530-5565
- `NEARPrivateChat/ChatStore.swift` lines 5701-5710
- `NEARPrivateChat/AppShellView.swift` lines 6381-6417

Suggested fix:
- Rename modes around user intent: Auto, Live Web, Saved Links, Files, Research.
- Separate "model has web tool" from "app will attach source pack".
- Add tests asserting which attachments/links/web tools are sent for each route/mode.

### P2: Public/Shared Link Reads Can Fail With A Stale Signed-In Token

Readable public endpoints authenticate whenever `authToken` is non-empty. If a signed-in token is expired or revoked, a public link that would work unauthenticated may fail instead of falling back.

Relevant source:
- `NEARPrivateChat/PrivateChatAPI.swift` lines 233-247

Suggested fix:
- On 401/403 for readable endpoints, retry unauthenticated before surfacing failure.
- Keep authenticated fetch for permission discovery, but make preview resilient.

### P2: Raw Shared IDs Are Parsed Too Narrowly

`/c/<id>` URLs accept any id, but raw pasted IDs only pass when they start with `conv_` or `chatcmpl-`. If the backend changes id formats, Shared With Me rows that pass `item.conversationID` directly can stop opening.

Relevant source:
- `NEARPrivateChat/ChatStore.swift` lines 2053-2058
- `NEARPrivateChat/ChatStore.swift` lines 5276-5295

Suggested fix:
- Accept any sane raw id, or pass Shared With Me IDs through a separate trusted path.

### P2: "Run Setup Again" Likely Does Not Reopen Setup Immediately

The Account button clears the completion flag and dismisses the sheet, but `RootView` only calls `presentSetupIfNeeded()` on appear and session-token changes. There is no `onChange` for the setup-completed flag, and the setup completion is global rather than per account.

Relevant source:
- `NEARPrivateChat/NEARPrivateChatApp.swift` lines 43-86
- `NEARPrivateChat/AppShellView.swift` lines 4142-4148
- `NEARPrivateChat/Models.swift` lines 492-505

Suggested fix:
- Add an app-level setup presentation signal or observe `setupCompleted`.
- Key setup completion by user id/session account where possible.

### P3: Monolithic AppShell And ChatStore Will Slow Parallel Agents

The core UI and state object are very large: `AppShellView.swift` is 7,176 lines and `ChatStore.swift` is 6,003 lines. This makes code review, merge conflict handling, UI iteration, and unit testing much harder than the product complexity requires.

Suggested fix:
- Extract features into folders: Auth, Chat, Home, Projects, Sharing, Account, IronClaw, Security, DesignSystem.
- Split ChatStore into focused stores/services: ConversationStore, MessageStreamStore, ProjectStore, ShareStore, SettingsStore, FileStore, IronClawStore.
- Introduce protocols for API/persistence dependencies before broad test work.

### P3: Release Readiness Gaps

- `DEVELOPMENT_TEAM` is empty.
- `TARGETED_DEVICE_FAMILY = 1`, so it is iPhone-only.
- No `PrivacyInfo.xcprivacy` found.
- No entitlements file found.
- Portrait-only orientation in `Info.plist`.

Suggested fix:
- Decide whether this is TestFlight/internal or App Store bound.
- Add privacy manifest/copy, signing team, data protection posture, and iPad decision.

### P3: Documentation Drift

`WEB_PARITY.md` still marks subscription/plans as missing, while README and source show billing implemented.

Relevant source:
- `WEB_PARITY.md` line 70
- `NEARPrivateChat/PrivateChatAPI.swift` lines 111-119
- `NEARPrivateChat/AppShellView.swift` lines 4236-4258

Suggested fix:
- Update parity docs before assigning more web-parity work to another agent.

## Claude Code Work Packets

### Packet 1: Stabilize Conversation Loading And Cache

Prompt:

```text
In NEARPrivateChatIOS, fix conversation-load races and stale cache masking. Add a generation/cancellation guard around ChatStore.selectConversation/loadMessages/selectResponseVariant so older network/cache completions cannot overwrite messages for the newly selected conversation. Change local message cache behavior to display cached messages optimistically but still refresh server truth, with special handling for local external/IronClaw-only messages. Add focused unit tests with a mock API that returns out of order.
```

Acceptance:
- Rapid chat switching cannot show the wrong transcript.
- Cached messages do not permanently prevent server refresh.
- Tests cover out-of-order loads and cache-then-network refresh.

### Packet 2: Safety For Destructive And Sharing Actions

Prompt:

```text
Add confirmation and safer UX for destructive conversation/file/share actions. Permanent conversation delete from list swipe and chat overflow should require confirmation or become archive-first with undo. Review public-link enable/disable and share-group delete for confirmation consistency. Keep existing API behavior but make accidental data/access changes harder.
```

Acceptance:
- Permanent delete requires explicit confirmation.
- Archive remains quick.
- Share/public access changes have clear state copy.

### Packet 3: Add Test Harness Around Core Risks

Prompt:

```text
Expand NEARPrivateChatTests beyond auth/import. Add tests for PrivateChatAPI stream parsing/completion/failure behavior, ChatStore source-mode routing decisions, conversation loading races, setup rerun state, public-readable fallback, and local message cache normalization. Introduce small protocols/fakes only where needed; keep production behavior unchanged.
```

Acceptance:
- Tests run with `xcodebuild test ... iPhone 17 Pro`.
- Core stream and ChatStore behavior is testable without live network.

### Packet 4: Persistence And File IO Hardening

Prompt:

```text
Move large/sensitive local persistence out of UserDefaults and move plain file upload reads off the MainActor. Add a small persistence service for projects/local message cache with data protection, schema versioning, size caps, and migration from current UserDefaults. Ensure non-PDF file uploads do not block UI and preserve current 10 MB validation.
```

Acceptance:
- UserDefaults no longer stores full chat/project payloads after migration.
- File import/upload remains responsive on 10 MB files.

### Packet 5: Design-System Extraction

Prompt:

```text
Extract repeated NEAR Private Chat visual primitives from AppShellView into a DesignSystem layer: command card, status chips, toolbar icons, sheet headers, section cards, rows, empty states, and source/context pills. Do not redesign behavior; reduce AppShellView size and make screen-level code easier to review.
```

Acceptance:
- AppShellView meaningfully shrinks.
- Visual output remains equivalent in screenshots.
- Extracted components have narrow APIs and previews where practical.

### Packet 6: Source Mode And Route Semantics

Prompt:

```text
Clarify source-mode and route semantics across UI labels, prompt construction, and tests. Separate "model-native web tool enabled" from "app-side source pack attached". Rename or adjust chips/menus so Saved Links, Files, Web, Research, NEAR Cloud, and IronClaw communicate what will actually be sent.
```

Acceptance:
- Each route/mode has a test showing tools, attachments, links, and app-grounding behavior.
- UI chips no longer imply unavailable capabilities.

## Already Improved In Current Source

Do not re-open these as fresh bugs unless regression tests fail:

- OAuth callback state is generated and validated.
- SSE stream EOF without `response.completed` now throws.
- Chat role decoding tolerates `developer` and `tool`.
- IronClaw local gateway script now generates a random token by default, refuses the old shared token, and binds localhost unless explicitly overridden.
- IronClaw test connection now hits the authenticated chat route instead of public health/status.
- Failed IronClaw turns with text are surfaced as failures.
