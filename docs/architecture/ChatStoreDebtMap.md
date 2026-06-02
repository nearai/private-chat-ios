# ChatStore Debt Map

Phase 0 handoff for shrinking `NEARPrivateChat/App/State/ChatStore.swift`.

Read with:

- `RULES.md`
- `docs/architecture/ARCHITECTURE.md`
- `docs/architecture/PLAN.md`

## Status

`ChatStore` is legacy compatibility debt. It was 11,878 lines at Phase 0 and is 6,464 lines after the bounded Phase 16-AL pass. It still owns app-wide compatibility behavior, routing/send/stream coordination bridges, demo capture, and UI compatibility state.

Recent validated cleanup:

- Phase 15-A: Security route-context and proof-report UI now use `SecurityStore`, `ModelCatalogStore`, and `AgentStore`; `SecurityView.swift` has zero `ChatStore` references.
- Phase 15-B: Account settings/capability views were split into focused files under 500 lines except the 630-line parent, with remaining `ChatStore` references limited to explicit legacy bridges.
- Phase 16-A: Agent Workspace was split into a 52-line shell, setup views, and mission-control panel. Selected project reads moved to `ProjectStore`; setup snapshot and launch/send behavior remain `ChatStore` bridges by design.
- Phase 16-B: Chat toolbar read-only state moved to `ModelCatalogStore`, `ProjectStore`, `SecurityStore`, `AgentStore`, and `ConversationStore`; remaining `ChatStore` references are action/export/sheet bridges.
- Phase 16-C: Account-only banners now route through `AccountStore`; Account Settings only uses `ChatStore` for import and default-model empty-chat compatibility.
- Phase 16-D: Sharing support sheets moved out of `ShareViews.swift`; both Sharing surface files are under the 1000-line failure threshold.
- Phase 16-E: `ShareConversationView` no longer depends on `ChatStore`; Share export/proof/read-model state uses owner stores.
- Phase 16-F: `RenameConversationView` now uses `ConversationStore`; the only remaining Sharing-local `ChatStore` bridge is `SharedConversationSheet`.
- Phase 16-G: `SharedConversationSheet` no longer depends on `ChatStore` or `MessageBubble`; shared-preview open/copy behavior is injected from host surfaces as callbacks.
- Phase 16-H: signed transcript route context moved to a single `SecurityStore` helper, and transcript copy moved to `Core/Export/ConversationTranscriptClipboard`; `ChatStore.copyCurrentTranscript` was deleted.
- Phase 16-I: Account import/default-model bridges were removed from `ChatStore`; `AccountSettingsView` calls `AccountStore.importChats` and `ModelCatalogStore.setPreferredDefaultModel` directly.
- Phase 16-J: `ProjectFilesView` no longer uses `ChatStore` directly for project selection, conversation opening, or prompt staging; hosts inject those actions explicitly.
- Phase 16-K: Hosted IronClaw preflight pending state and disclosure/fingerprint construction moved to `AgentStore`; `ProjectStore` supplies the selected-project disclosure.
- Phase 16-L: Project support rows, action shelf, route preview, file pills, and editor sheets moved out of `ProjectContextViews.swift` into `ProjectContextSupportViews.swift`; both files are below the 1000-line quality bar.
- Phase 16-M: Message-load generation, cancellation/reset, cache-first timeline application, remote refresh, selected-conversation staleness checks, and secure cache persistence failure banners moved to `ChatMessageLoadCoordinator`.
- Phase 16-N: `ArchivedChatsView` moved out of the project surface into `Features/Conversations/ArchivedChatsView.swift`; archive UI is now colocated with conversation ownership.
- Phase 16-O: selected-conversation navigation pulse moved to `ConversationStore`; App shell and archive UI now observe the conversation owner directly.
- Phase 16-P: pending-delete confirmation state moved to `ConversationStore`; destructive deletion remains a `ChatStore` bridge until message-cache and project-membership side effects are split.
- Phase 16-Q: selected-only clone/archive/pin/delete wrappers were removed from `ChatStore`; toolbar passes selected conversations into real action methods or requests delete confirmation from `ConversationStore`.
- Phase 16-R: toolbar More-menu sections moved to `ChatToolbarMenuContent.swift`; both toolbar files are under 500 lines.
- Phase 16-S: unused `renameSelectedConversation` bridge was deleted; rename UI already uses `ConversationStore`.
- Phase 16-T: `RenameConversationView` moved from Sharing support into `Features/Conversations/RenameConversationView.swift`; rename UI is now colocated with conversation ownership.
- Phase 16-U: `NewProjectView`, `EditProjectView`, and their preview helper moved from Sharing support into `Features/Projects/ProjectEditorViews.swift`; project editor UI is now colocated with project ownership.
- Phase 16-V: `cloneSharedPreviewToChat` was deleted; shared-preview hosts call `cloneConversation(snapshot.conversation)` directly.
- Phase 16-W: `ArchivedChatsView` no longer depends on `ChatStore`; archive restore/copy/export status goes through `ConversationStore`.
- Phase 16-X: archived-conversation restore actions moved into `ConversationStore`, Home archived rows use those actions directly, and `ChatStore` unarchive wrappers were deleted.
- Phase 16-Y: the Home project editor sheet stopped injecting `ChatStore`; `EditProjectView` is now explicitly project-owned and receives only `ProjectStore`.
- Phase 16-Z: writable shared-preview open moved to `ChatSessionCoordinator`; the compatibility `ChatStore` method only passes the shared snapshot into the active-session owner.
- Phase 16-AA: ordinary conversation switching and start-new transitions moved to `ChatSessionCoordinator`; the compatibility `ChatStore` methods only provide draft persistence/load callbacks.
- Phase 16-AB: delete/clone/archive/pin side-effect choreography moved to `ConversationActionCoordinator`; `ChatStore` only launches Tasks and supplies cross-domain callbacks for project membership, message cache, load, refresh, and banners.
- Phase 16-AC: pending-delete confirmation moved to `ConversationActionCoordinator`; `ChatStore.confirmPendingDelete` now only launches the owner action and supplies cross-domain callbacks.
- Phase 16-AD: all-chats/project selection and selected-project archive session transitions moved to `ChatSessionCoordinator`; `ChatStore` now supplies only draft persistence and message-load callbacks for those paths.
- Phase 16-AE: active draft scope IDs, draft persistence access, loaded-draft suppression, and persisted draft removal moved to `ChatDraftScopeStore`.
- Phase 16-AF: active draft discard became a draft-owner operation; `ChatSendCoordinatorHost` no longer exposes draft scope IDs or accepts caller-supplied draft scopes.
- Phase 16-AG: send-time selected-conversation activation moved to `ChatSessionCoordinator`; `ChatSendCoordinatorHost` no longer exposes a selected-conversation setter or draft-scope transition hook.
- Phase 16-AH: quick-intent parsing and pending NEAR-account tracker dispatch decisions moved to `ChatLocalIntentDispatcher`; local intent execution, tracker/memory/reminder creation, and transcript mutation remain explicit `ChatStore` compatibility bridges.
- Phase 16-AI: quick-intent live-widget lookup moved to `ChatLocalIntentWidgetService`; local transcript append/update and side-effect execution remain explicit `ChatStore` compatibility bridges.
- Phase 16-AJ: local transcript message construction moved to `ChatLocalIntentTranscriptWriter`; `ChatStore` still decides append/update timing and owns local intent side-effect execution.
- Phase 16-AK: local intent response copy moved to `ChatLocalIntentResponseFormatter`; `ChatStore` still decides append/update timing and owns local intent side-effect execution.
- Phase 16-AL: tracker briefing creation, "track that" briefing drafts, NEAR-account tracker briefing creation, and related activity-log summary strings moved to `ChatLocalIntentBriefingFactory`; `ChatStore` still invokes tracker creation callbacks and owns local intent side-effect timing.

Do not add new behavior here. During extraction, `ChatStore` may temporarily forward to a real owner only when the same phase removes the real logic from `ChatStore`.

## Target Ownership Map

| Current `ChatStore` bucket | Current line neighborhoods | Canonical owner | Notes for extraction |
| --- | ---: | --- | --- |
| Conversations list and selected conversation | 16, 424-432, 1468-1490, 1638-1670, 4047-4204, 7429-7460, 10314-10363 | `ConversationStore` + conversation repository + `ConversationActionCoordinator` | Own list refresh, select/open/new, delete/archive/pin/rename/clone, cached preview, selected conversation read model, conversation navigation pulse, pending-delete confirmation state, pending-delete confirmation action, archived-restore actions, and conversation action side effects. `ArchivedChatsView` now lives under `Features/Conversations` and has no `ChatStore` dependency; remaining `ChatStore` action methods are Task-launching adapters until message-cache and project-membership callbacks move to services. Home and Chat should consume narrow read models, not full `ChatStore`. |
| Messages, transcript, branches, selected response variant | 129-136, 203, 4550-4671, 6021-6110, 7569-7794, 10497-11211 | `MessageRepository` + `MessageTimelineStore` + `ChatMessageLoadCoordinator` + `ChatSessionCoordinator` | Load lifecycle, cancellation, cache-first apply, remote refresh, and stale-selection checks now live in `ChatMessageLoadCoordinator`. Writable shared-preview open, ordinary conversation switching, start-new transitions, project-session selection follow-up, and send-time selected-conversation activation now live in `ChatSessionCoordinator`. Remaining work: reduce `ChatStore` callbacks for model restore and Hosted/IronClaw repair. |
| Draft/composer state | 139-160, 147-173, 3294-3382, 8072-8166 | `ChatComposerStore` + `ChatDraftScopeStore` + `DraftPersistence` + `AttachmentStagingStore` | Composer owns draft and pending prompt attachments. `ChatDraftScopeStore` owns active draft scope IDs, account-scoped draft persistence access, loaded-draft suppression, persisted draft removal, and current-scope discard. `ChatSessionCoordinator` clears composer state for writable shared-preview open and coordinates draft-scope transitions through callbacks. Persistence keys/files belong in `Core/Persistence`. |
| Send pipeline | 5430-5684, 6329-6565, 7429-7568 | `ChatSendCoordinator` | Own one send transaction: snapshot draft, resolve attachments, create conversation, append user message, choose route, start stream, rollback failed draft, retry/regenerate/edit-and-resend. The host contract no longer exposes draft scope IDs, a selected-conversation setter, or a draft-scope transition hook; remaining send-host noise is stream/runtime bridges and model/Hosted repair callbacks. |
| Streaming and stream event application | 5685-5728, 6983-7132, 7569-7794 | `Core/Streaming` + `MessageTimelineStore` | `MessageStreamService` should own response streaming, fallback, timeout policy, and parsed events. Timeline store applies events to visible messages. |
| Council fan-out and synthesis | 62-70, 641-700, 1194-1257, 5729-5959, 6566-6929, 9418-9594 | `Features/ModelCatalog` + `Core/Routing` + `CouncilStreamService` | Model catalog owns eligible models, presets, default lineup, pinned models, plan locks. Routing owns readiness/source policy. Council service owns fan-out, stop, collection, and synthesis input. |
| Model catalog and route selection | 17-18, 57-67, 588-796, 1087-1276, 1846-1888, 9360-9686 | `Features/ModelCatalog` + `Core/Routing` | Catalog owns model lists, grouping, provider display, allowed models, pinned models, selected model. Route planner owns route kind, readiness, recovery, source semantics. |
| Web/source/research routing | 67-83, 518-568, 1873-1888, 7248-7313, 9385-9438, 10632-10880 | `Core/Routing` + Chat composer/source-mode store | Source mode is a routing concern surfaced by composer. Prompt-specific web/app grounding policy belongs in route planning, not global state. |
| Files and local attachments | 37-38, 139-160, 194-219, 2864-3382, 3437-4039, 6129-6288, 10232-10246 | `Features/Files` + `AttachmentStagingStore` + `FileService` | Own local attach, remote files, preview, upload, delete, large-paste staging, PDF/table/image text extraction, prompt file drafts, and privacy mode. |
| Project files and project attachment mutation | 458-527, 2944-3116, 9975-10227 | `Features/Projects` + `Features/Files` | Project owns membership and project attachment list. `ProjectFilesView` now receives host actions instead of a `ChatStore` environment object. Files still owns upload/remote/local file mechanics; the upload bridge should move only after file upload, document-text staging, upload notices, and registration have one owner. |
| Projects, notes, links, memory, instructions | 19, 45-56, 416-527, 2206-2495, 2495-2864, 8378-8454, 8969-9033, 10000-10175 | `Features/Projects` + `ProjectPersistence` + `ChatSessionCoordinator` | Project store owns CRUD, selected project, archive, notes, links, memory, instructions, assignment, project-scoped conversations, and prompt-context read model. Project creation/editing sheets now live in `Features/Projects/ProjectEditorViews.swift` and no longer receive `ChatStore` from Home. `ChatSessionCoordinator` owns the cross-owner session follow-up for project selection and selected-project archive transitions. |
| Sharing and shared previews | 20, 36, 39, 41, 4211-4460, 4495-4550, 4617-4651, 10381-10400 | `Features/Sharing` + `ShareAPI` | First bounded feature extraction. Own public/direct/org/group shares, shared-with-me, share groups, readable shared preview, permission copy, and share URL parsing. Shared-preview copy now uses the real conversation clone action directly; writable open delegates into `ChatSessionCoordinator` instead of mutating transcript/composer state inline in `ChatStore`. |
| Security, proof, attestation, trust metadata | 21-22, 830-940, 4464-4492, 6008, 7725, 10367, 11806-11824 | `Features/Security` + `AttestationAPI` + `Core/Security` | Security owns proof state, loading/error state, freshness/coverage copy, proof capsule view models, nonce/hash helpers, and message trust metadata creation. |
| Account settings, billing, integrations, diagnostics | 23-35, 72-105, 1582-1637, 1896-2105, 2106-2205, 7978-8058 | `Features/Account` + `SettingsAPI` + `BillingAPI` | Account owns billing snapshot, remote settings, appearance/notifications, NEAR Cloud key/account connection, Hosted IronClaw connection settings, diagnostics entry, and integration test state. |
| Agent hosted and phone-safe runtime | 23-26, 44, 168, 202, 1896-2105, 4683-4728, 5509-5609, 7133-7247, 7797-7969, 8890-10227 | `Features/Agent` + `AgentRuntimeService` + `AgentThreadPersistence` | Agent now owns hosted handoff preflight state/disclosure, connection state, tool names, and hosted thread mapping. Approval/credential resolution still belongs to the streaming/transcript path until a dedicated runtime coordinator can own Hosted IronClaw polling, gate resolution, and stream event application. Project/file mutations must go through services. |
| Quick intents, trackers, widgets, briefings | 175-179, 2624-2894, 6320-6350 | Existing briefing/tracker owner, likely `Features/Chat` only for chat-local dispatch | `ChatLocalIntentDispatcher` owns the parse/pending NEAR-account tracker dispatch decision. `ChatLocalIntentWidgetService` owns which quick intents fetch live widgets, including the injected daily-brief digest hook. `ChatLocalIntentTranscriptWriter` owns local user/assistant message construction. `ChatLocalIntentResponseFormatter` owns local intent confirmation, memory, activity-log, history-search, reminder, and fetch-failure response copy. `ChatLocalIntentBriefingFactory` owns tracker briefing creation, "track that" draft construction, NEAR-account tracker briefing creation, and related activity-log summaries. Remaining work is moving execution side effects out of `ChatStore`: tracker creation callbacks, memory/reminder creation, local transcript append/update timing, activity logging, haptics, and streaming state. The target owner should expose a narrow action service used by chat send and widget actions. |
| Setup application and starter project seeding | 2206-2495, 2221-2369 | `Features/Setup` + `Features/Projects` | Setup owns profile/plan application. Project seeding should route through project service. Chat should receive starter draft intent only. |
| Persistence, cache, defaults, keychain scoping | 47-105, 203-228, 268-304, 7978-8465, 8508-8597, 10889-11052 | `Core/Persistence` adapters + narrow feature stores | Move account scoping, migrations, defaults keys, keychain accounts, file-backed caches, draft caches, conversation/message/project caches, and protected text storage into adapters. Draft persistence now sits behind `ChatDraftScopeStore`; remaining persistence bridges are account reset/load fan-out and broader send-host compatibility callbacks. |
| Import/export, chat import, and transcript copy | 1491-1548, 5960-6034 | `Core/Export` + conversation/message services | Transcript copy and chat import now live in `Core/Export`; remaining signed-snippet paths should use captured message metadata, not current global route state. |
| App lifecycle/bootstrap/account reset glue | 1300-1467, 7978-8058, 11252-11320 | `App/Composition`, `App/Lifecycle`, feature stores | App should orchestrate dependency construction, account reset, and bootstrap fan-out. Feature stores own their own reset/load hooks. |
| Deep links and external handoff | 1677-1825 | `AppRouter` + `Core/Routing` | Deep links should decode to route/actions in routing layer. `ChatStore` should not own URL handling or open-chat navigation tokens. |
| Demo capture and seeded data | 1317-1318, 4214-4215, 11249-11878 | Dedicated debug/demo owner | Keep demo data isolated from production chat state and model catalog. Demo capture should not expand `ChatStore` or ship speculative defaults into normal state. |
| Global UI compatibility state | 40, 42-45, 110-124, 7972-7995 | Transitional facade only | Banners, loading flags, pending sheets, delete confirmations, and open tokens should either move to feature stores/router or remain as short-lived forwarding until the owning view is split. |

## Phase 1 Test Split Hints

Use this map to split `PrivateChatCoreTests.swift` before moving production code:

- `Sharing`: share permission, URL parsing, shared preview, shared author names.
- `Files`: attachment classification, PDF/table/image extraction, remote files, upload dispatch.
- `Projects`: CRUD, links, notes, memory, assignment, project prompt context.
- `Routing`: source mode, route readiness, recovery, model route classification.
- `Streaming`: stream parser, stream visibility, delta buffering, cancellation.
- `ModelCatalog`: model lists, plan locks, pinned/default models, council eligibility/presets.
- `Security`: attestation state, proof coverage, trust copy, signed transcript context.
- `Agent`: hosted handoff, phone-safe tool planning/results, approvals/credentials.
- `Account`: settings, billing, NEAR Cloud, Hosted IronClaw connection checks.
- `Chat`: send coordinator behavior, retry/regenerate/edit flows, composer state.
- `Persistence`: account-scoped storage, draft/message/project caches, keychain scopes.
- `Export`: selected answer markdown/PDF/DOCX/signed JSON.

## Extraction Discipline

- Move one bucket at a time.
- Do not add behavior to `ChatStore` while preparing extraction.
- New Swift files need Xcode project membership.
- A successful phase removes ownership confusion, not just line count.
- If a method touches two domains, split by owner before moving it.
- If a view needs data from several owners, add a read model or app-level coordinator rather than passing full stores around.

## Phase 0 Exit Check

- Every major `ChatStore` responsibility above has a target owner.
- No production Swift code moved for this phase.
- Next agent can start Phase 1 test split by owner without guessing where behavior should land.
