# Plan

## Goal

Turn current repo from "feature folders around a god object" into feature-owned SwiftUI app with narrow stores, protocol-backed services, and tests that prove each extracted seam.

Primary objective: delete `ChatStore` responsibilities phase by phase. Do not polish it. Remove jobs from it until no feature depends on it as global state.

## Ground Rules

- Preserve user-visible behavior.
- No DB migrations.
- No localhost app runs.
- Use `pnpm` only for JS verifier work.
- Do not create branches with `codex/` prefix.
- New Swift files must be added to Xcode project target membership.
- No docs-only build.
- For Swift file moves/service extraction, build/test according to risk.
- Do not add new behavior to `ChatStore` except temporary forwarding deleted in same phase.

## Current Baseline

Hard blockers:

- `ChatStore.swift` is 11878 lines and owns too many domains.
- `PrivateChatCoreTests.swift` is 8352 lines and blocks targeted test ownership.
- Chat/Home/Setup UI files exceed 1000 lines in multiple places.
- `PrivateChatAPI` is still one concrete client for many domains.
- persistence keys/caches live inside app-wide state.
- existing feature stores are mostly read-model helpers, not true behavior owners.

Good foundation already present:

- feature folders exist
- route/sheet enums exist
- stream parser/service files exist
- model catalog/project/file/share first-pass stores exist
- app has a composition point
- Xcode project/schemes are discoverable with Build iOS Apps tooling

## Implementation Status

Last updated: 2026-06-02.

- Phase 0 is complete: `docs/architecture/ChatStoreDebtMap.md` maps the major `ChatStore` responsibilities to canonical owners.
- Phase 1 is complete: `PrivateChatCoreTests.swift` is now a shared helper harness, and the 410 existing tests are split into focused files under `NEARPrivateChatTests/`.
- No production Swift behavior was moved during Phases 0-1.
- Phase 2 is complete: `PrivateChatAPI` is now a compatibility facade over protocol-backed domain clients for auth, conversations, messages, models, files, sharing, settings, billing, and attestation.
- `AppEnvironment` exposes the API protocols, and `SessionStore` now depends on `AuthAPI`; broader feature call-site migration is intentionally deferred to later owner extraction phases.
- Phase 3 is complete.
- Phase 3-A is complete: draft/account-scoped persistence now lives in `Core/Persistence` via `AccountStorageScope`, `FileCache`, and `DraftPersistence`; `ChatStore` only forwards draft load/save/remove for the active draft scope.
- Phase 3-B is complete: `SettingsPersistence`, `ConversationCache`, `MessageCache`, `ProjectPersistence`, and `AgentThreadPersistence` now own the remaining settings/cache/thread storage that used to be inline in `ChatStore`; `ChatStore` keeps only temporary forwarding methods and user-facing failure banners.
- Phase 3-C is complete: `SessionPersistence` now owns auth/session/profile keychain accounts, pending auth state defaults, and simulator debug-session fallback storage; `SessionStore` keeps OAuth/web-auth orchestration and `api.authToken` assignment.
- Phase 4 is complete: `ShareStore` is now an observable sharing owner backed by `SharingService` and `ShareAPI`; public/direct/org/group share mutations, shared-with-me, share groups, readable shared previews, and share parsing helpers moved out of `ChatStore`.
- The remaining Phase 4 bridge is intentional: `ChatStore` still applies a `SharedConversationSnapshot` into the active chat for "Open chat" and "Copy & Continue" until conversation/message extraction owns that mutation.
- Phase 5 is complete: `FileService`, `FileStore`, `AttachmentStagingStore`, `DocumentTextExtractor`, and `VisionTextExtractor` now own remote file API calls, prompt attachment staging, large paste/shared-file staging, local document text extraction, and send-time staged attachment resolution.
- The remaining Phase 5 bridge is intentional: `ChatStore` still mutates selected project attachment lists and coordinates send rollback because Projects and Send Coordinator extraction are later phases.
- Phase 7 is complete: `ConversationStore` now owns conversation list, selected conversation, refresh/cache fallback, create/open/select/new, delete/archive/unarchive/pin/rename/clone, and local read models; `ConversationRepository` owns `ConversationAPI` + `ConversationCache` access.
- `MessageRepository` now owns message cache load/save/remove, remote item mapping, local external-model preservation, stale/local-failure normalization, and cached preview text; `MessageTimelineStore` owns current transcript state and selected response variants per conversation.
- Remaining Phase 7 bridges are explicit: `ChatStore` still coordinates send/app routing, draft resets, shared-preview application, demo capture seeding, and Agent tool dispatch until Phase 8/Agent extraction, but those paths now call the conversation/message owners for lifecycle and cache mutations.
- Phase 8 is complete: `ChatSendCoordinator` owns the ordinary chat send transaction, and `MessageTimelineStore` owns stream event application/text-delta buffering for visible messages.
- Remaining Phase 8 bridges are explicit: quick intents/trackers, Hosted/phone Agent runtime, Council fan-out, project prompt context, and app/demo glue still call through `ChatStore` until their owner phases.
- Phase 9 is complete for model/source ownership and pure Council/routing logic: `ModelCatalogStore` owns selected model, Council IDs, pinned IDs, source mode, research/web state, model refresh/fallback, plan locks, ranking, Council presets/defaults/eligibility, selected route read models, and picker actions.
- `RoutePlanner` owns prompt source privacy overrides, live-web detection, hosted-auto-route fallback, remote-workstation detection, Council prompt heuristics, route readiness, and source-routing semantics; tests now target these owners directly.
- `CouncilStreamService` owns Council result/read-model helpers, targeted follow-up prompt construction, synthesis prompt construction, usable-result collection helpers, synthesis-model detection, latest-response lookup, and the concurrency limit.
- Remaining Phase 9 bridges are explicit: `ChatStore` still mutates the transcript/timeline for Council fan-out, stop/synthesize actions, targeted follow-up streaming, and synthesis streaming because final chat/timeline facade and Agent runtime splits are Phases 12-13/15. It also remains the account/key bridge for NEAR Cloud catalog refresh and the app-level banner/proof-clear side effects of model route changes.
- Phase 10 is complete: Home now has `HomeStore` for Home-local search/filter/sheet/launch state, `ConversationListView` is a compatibility wrapper around `HomeScreen`, and Home surface files are split into owner-named Swift files under 500 lines.
- `HomeOrchestrationSurface.swift` is split into models, planner, planner-formatting helpers, and view surface. `HomeSupportingViews.swift` is now a tiny compatibility placeholder while setup, trust, chrome, inbox, project, row, and launch views live in dedicated files.
- Remaining Phase 10 bridge is explicit: Home still calls `ChatStore` for legacy navigation/send/setup/trust actions that are owned by later Chat UI, Setup, Agent, Account, and final facade phases.
- Phase 11 is complete: `SetupModels.swift` is now a compatibility marker and setup use cases, starter presets, profile planning, route defaults, setup plan, restore planner, capability recommendations, storage, and `SetupStore` live in owner-named files under 500 lines.
- `UserSetupView.swift` is split into the main setup screen, setup controls, and setup plan preview card while preserving the existing setup surface.
- Remaining Phase 11 bridge is explicit: setup application still flows through `ChatStore.applySetupProfile` because it mutates chat draft, route defaults, and project starter notes until Chat UI, Projects, and final facade phases finish.
- Phase 12 is complete for the chat UI split: chat message, widget, source, proof, edit, artifact, Council, threaded briefing, briefing builder/editor, demo-capture, composer, toolbar, attachment, and voice/dictation views now live in owner-named files under 500 lines.
- Remaining Phase 12 bridges are explicit: chat UI still reaches `ChatStore` for legacy app-level send/navigation/demo/Agent/account actions until Agent, Account, Security/Export, and final facade phases. Large non-view chat/service files (`LiveDataService.swift`, `ChatModels.swift`, `ChatSendCoordinator.swift`) are intentionally left for later owner phases.
- Phase 13 is complete for a bounded Agent/Account ownership pass: `AgentStore` now owns account-scoped Agent thread mapping, IronClaw conversation settings lookup, mission prompt/brief extraction, repository prompt helpers, normalized hosted prompt text, tool-result markdown, and mobile capability copy; `AccountStore` remains the Account settings owner added in the same wave.
- Remaining Phase 13 bridges are explicit: live Hosted/mobile Agent streaming, approvals, credentials, NEAR Cloud/account lifecycle side effects, and several Account UI call sites still cross through `ChatStore` until the final facade cleanup.
- Phase 14 is complete for a bounded Security/Export ownership pass: `SecurityStore` now owns attestation snapshot/loading/error state, proof refresh, current proof status derivation, assistant trust/proof metadata, and signed transcript export context.
- Phase 15-A is complete for the first final-facade reduction slice: `SecurityView` no longer depends on `ChatStore` for selected route/model/Council/Cloud/Agent context or banners; it reads `SecurityStore`, `ModelCatalogStore`, and `AgentStore` directly.
- Phase 15-A also split pure Security support rows and the proof-report card into owner-named files. `SecurityView.swift` is now 976 lines, under the 1000-line failure threshold.
- The Account capability surface now reads Account/Agent/ModelCatalog/Security stores directly for Cloud keys, Agent readiness, billing, diagnostics, proof availability, web defaults, and capability status; remaining Account `ChatStore` bridges are legacy import/share/security presentation, banner routing, and the default-model empty-chat side effect.
- Phase 15-B is complete for an Account file split: Account detail pushes, Capability Center, capability support cards, and connection cards now live in owner-named files under 500 lines. The parent Account settings surface is 630 lines and keeps only the legacy presentation/action bridges.
- Phase 16-A is complete for the Agent Workspace split: `AgentWorkspaceView.swift` is now a 52-line shell, with setup and mission-control surfaces in owner-named files. Project reads moved to `ProjectStore`; setup snapshot and launch/send remain explicit `ChatStore` bridges.
- Phase 16-B is complete for the Chat toolbar read-model decoupling: toolbar route, project, proof, Agent availability, and selected conversation reads moved to owner stores. Remaining toolbar `ChatStore` references are action/export/sheet compatibility bridges.
- Phase 16-C is complete for Account bridge cleanup: Account-only banners now route through `AccountStore`; Account settings only uses `ChatStore` for import and default-model empty-chat compatibility.
- Phase 16-D is complete for the Sharing file split: `ShareViews.swift` and `ShareSupportViews.swift` are both in the app target and under the 1000-line failure threshold. Remaining Sharing `ChatStore` references are selected-conversation rename and shared-preview open/copy bridges.
- Phase 16-E is complete for Share/Export read-model cleanup: the main `ShareConversationView` no longer depends on `ChatStore`; it reads transcript state via an explicit `ChatTranscriptStore`, proof/export context from `SecurityStore`, route context from `ModelCatalogStore`, project source counts from `ProjectStore`, and selected-conversation identity from `ConversationStore`.
- Phase 16-F is complete for selected-conversation rename ownership: `RenameConversationView` now uses `ConversationStore` directly, and `ShareSupportViews.swift` has zero `ChatStore` references.
- Phase 16-G is complete for Sharing-local shared-preview decoupling: `SharedConversationSheet.swift` no longer depends on `ChatStore` or `MessageBubble`; shared previews render with a read-only message bubble and receive open/copy actions from host surfaces.
- Phase 16-H is complete for the toolbar export bridge cleanup: signed transcript route context now has a single `SecurityStore` helper used by Share, Toolbar, and the `ChatStore` compatibility facade; transcript copy moved into `Core/Export/ConversationTranscriptClipboard`, deleting the old `ChatStore.copyCurrentTranscript` action.
- Phase 16-I is complete for Account import/default-model cleanup: `AccountSettingsView` no longer depends on `ChatStore`; chat import now runs through `AccountStore` and `Core/Export/ChatImportService`; default-model selection calls `ModelCatalogStore` with an explicit host-provided empty-chat predicate.
- Phase 16-J is complete for Project sheet host-action cleanup: `ProjectFilesView` no longer reads `ChatStore` directly for project selection, prompt staging, or conversation opening. Hosts inject project file upload/removal, route preview, conversation open, and prompt staging actions while file upload remains a deliberate `ChatStore` bridge until `FileService` upload/staging ownership is split further.
- Phase 16-K is complete for Hosted IronClaw preflight ownership: `AgentStore` owns the pending preflight sheet state and preflight disclosure/fingerprint construction; `ProjectStore` owns the selected-project disclosure helper. `ChatStore` now forwards only the streaming continuation/cancel bridge through `ChatSendCoordinator`.
- Phase 16-L is complete for Project surface decomposition: project action shelf, route preview rows, file pills, note/memory/chat rows, instructions cards, freshness badges, and project editor sheets moved from `ProjectContextViews.swift` into `ProjectContextSupportViews.swift`. No project behavior changed.
- Phase 16-M is complete for active message-load lifecycle ownership: `ChatMessageLoadCoordinator` now owns message-load generation, cancellation/reset, cache-first timeline application, remote refresh, selected-conversation staleness checks, and secure cache persistence failure banners. `ChatStore` keeps compatibility entry points plus callbacks for model restoration, Hosted/IronClaw latest-response repair, and banner presentation.
- Phase 16-N is complete for archive surface ownership: `ArchivedChatsView` moved from the project surface into `Features/Conversations/ArchivedChatsView.swift`. No archive behavior changed.
- Phase 16-O is complete for conversation navigation-pulse ownership: `openSelectedConversationToken` moved from `ChatStore` to `ConversationStore`, and App/Archive observers now watch the conversation owner directly. No send or stream behavior changed.
- Phase 16-P is complete for conversation delete-confirmation ownership: pending-delete dialog state moved from `ChatStore` to `ConversationStore`, and App/Home/Archive call sites now use the conversation owner directly. The destructive delete operation intentionally remains a `ChatStore` bridge because it still clears message cache and project membership.
- Phase 16-Q is complete for selected-action wrapper cleanup: `ChatToolbar` now passes the selected conversation directly into clone/pin/archive/delete request actions, and the selected-only `ChatStore` wrappers were removed. No conversation action semantics changed.
- Phase 16-R is complete for toolbar menu decomposition: `ChatToolbarMenuContent.swift` now owns the More-menu sections, putting `ChatToolbar.swift` back under 500 lines without behavior changes.
- Phase 16-S is complete for stale rename bridge removal: the unused `renameSelectedConversation` wrapper was deleted from `ChatStore`; `RenameConversationView` already uses `ConversationStore` directly.
- Phase 16-T is complete for rename view colocation: `RenameConversationView` moved from the Sharing support file into `Features/Conversations/RenameConversationView.swift` without behavior changes.
- Phase 16-U is complete for project editor colocation: `NewProjectView`, `EditProjectView`, and their preview helper moved from Sharing support into `Features/Projects/ProjectEditorViews.swift` without behavior changes.
- Phase 16-V is complete for shared-preview clone wrapper cleanup: host callbacks now call `cloneConversation(snapshot.conversation)` directly and the stale `cloneSharedPreviewToChat` wrapper was deleted from `ChatStore`.
- Phase 16-W is complete for archive surface cleanup: `ArchivedChatsView` no longer injects `ChatStore`; restore/copy/export status now routes through `ConversationStore` while preserving restore refresh and banners.
- Phase 16-X is complete for archive restore ownership: `ConversationStore` now owns async archived-conversation restore actions, Home archived rows use it directly, and the `ChatStore` unarchive wrappers were deleted.
- Phase 16-Y is complete for stale project-editor injection cleanup: the Home project editor sheet stopped injecting `ChatStore`; `EditProjectView` now receives only `ProjectStore`.
- Phase 16-Z is complete for writable shared-preview session ownership: `ChatSessionCoordinator` now owns selecting the shared conversation, replacing preview messages, clearing composer state, and pulsing navigation.
- Phase 16-AA is complete for ordinary session transitions: conversation switching and start-new transitions now go through `ChatSessionCoordinator`.
- Phase 16-AB is complete for conversation action side-effect choreography: delete/clone/archive/pin actions now go through `ConversationActionCoordinator`.
- Phase 16-AC is complete for pending-delete confirmation ownership: `ConversationActionCoordinator` now owns pending-delete unwrap/cancel plus destructive delete choreography; `ChatStore.confirmPendingDelete` is only a Task-launching compatibility adapter.
- Phase 16-AD is complete for project-session transition ownership: `ChatSessionCoordinator` now owns all-chats selection, project selection follow-up, latest project-chat selection, empty-project transcript clearing, and selected-project archive scope transitions. `ChatStore` only supplies draft persistence and message-load callbacks.
- Phase 16-AE is complete for draft-scope ownership: `ChatDraftScopeStore` now owns active draft scope IDs, account-scoped draft persistence access, loaded-draft persistence suppression, and persisted draft removal. `ChatStore` supplies only current conversation/project IDs, current draft state, and banners.
- Phase 16-AF is complete for send-host draft boundary cleanup: `ChatSendCoordinatorHost` no longer exposes active draft scope IDs or asks `ChatStore` to remove a caller-supplied draft scope. The send path now requests `discardActiveDraftForSend()`, and `ChatDraftScopeStore` owns current-scope removal.
- Phase 16-AG is complete for send-time conversation activation ownership: `ChatSendCoordinatorHost` no longer exposes a selected-conversation setter or a draft-scope transition hook. Send now asks the session owner to activate the created conversation atomically with the draft-scope transition.
- Phase 16-AH is complete for local intent dispatch ownership: `ChatLocalIntentDispatcher` now owns the parser and pending NEAR-account tracker dispatch decision for send fast paths. `ChatStore` still executes the resulting side effects and transcript mutations as an explicit compatibility bridge.
- Phase 16-AI is complete for local intent widget-fetch ownership: `ChatLocalIntentWidgetService` now owns which quick intents become live widgets, including the injected daily-brief digest hook. `ChatStore` still appends local transcript turns and owns local intent execution side effects.
- Phase 16-AJ is complete for local intent transcript construction ownership: `ChatLocalIntentTranscriptWriter` now owns local user/assistant message construction and the streaming assistant pending-message status. `ChatStore` still decides when to append those messages and executes local intent side effects.
- Phase 16-AK is complete for local intent response formatting ownership: `ChatLocalIntentResponseFormatter` now owns local intent confirmation, memory, activity-log, history-search, reminder, and fetch-failure response copy. `ChatStore` still decides when to execute side effects and append/update transcript turns.
- Phase 16-AL is complete for local intent briefing construction ownership: `ChatLocalIntentBriefingFactory` now owns tracker briefing creation, "track that" draft construction, NEAR-account tracker briefing creation, and the related activity-log summary strings. `ChatStore` still invokes tracker creation callbacks and owns local intent side-effect timing.
- Current Phase 16-AL size checkpoint: `ChatStore.swift` is 6464 lines, `ChatLocalIntentDispatcher.swift` is 46 lines, `ChatLocalIntentWidgetService.swift` is 39 lines, `ChatLocalIntentTranscriptWriter.swift` is 70 lines, `ChatLocalIntentResponseFormatter.swift` is 118 lines, `ChatLocalIntentBriefingFactory.swift` is 58 lines, `LiveDataService.swift` is 3599 lines, `ChatSessionStores.swift` is 330 lines, `ChatSendCoordinator.swift` is 599 lines, `ConversationStore.swift` is 388 lines, `ChatMessageLoadCoordinator.swift` is 143 lines, `MessageRepository.swift` is 433 lines, `ProjectContextViews.swift` is 723 lines, `ProjectContextSupportViews.swift` is 740 lines, `ProjectStore.swift` is 859 lines, `AgentStore.swift` is 783 lines, and `SecurityView.swift` is 976 lines. The next safe slice is extracting a narrow local-intent execution owner for memory/privacy/reminder/tracker side effects; do not start by ripping out `ChatSendCoordinatorHost`.

## Phase 0: Freeze And Map

Purpose: stop more architecture drift before moving code.

Actions:

- Add an ownership checklist to PR/review habit: "Which feature owns this?"
- Record top 20 largest Swift files before each phase.
- Mark `ChatStore` as legacy compatibility facade in comments.
- Create a `ChatStoreDebtMap.md` or section in this plan listing responsibility buckets and target owner.
- Do not move code yet.

Exit:

- every `ChatStore` responsibility has target owner
- no new feature starts from `ChatStore`
- next phase can remove one responsibility bucket without behavior guessing

Validation:

- docs only, no build

## Phase 1: Test Split First

Purpose: make later refactors reviewable.

Actions:

- Split `PrivateChatCoreTests.swift` into focused XCTest files by current ownership:
  - Auth
  - Routing
  - Streaming
  - ModelCatalog
  - Projects
  - Files
  - Sharing
  - Setup
  - Security
  - Export
  - Agent
  - Chat
- Move helper factories into test support files.
- Add new test files to Xcode project.
- Keep test bodies unchanged except imports/helper access.

Exit:

- no test file over 1000 lines unless temporarily justified
- changed test groups can run independently
- no production behavior changed

Validation:

- targeted test run
- simulator build if project file changes are manual

## Phase 2: API Client Split

Purpose: stop feature code depending on one concrete mega-client.

Actions:

- Extract `APIClient` request core from `PrivateChatAPI`.
- Create protocols and concrete clients:
  - `AuthAPI`
  - `ConversationAPI`
  - `MessageAPI`
  - `ModelAPI`
  - `FileAPI`
  - `ShareAPI`
  - `SettingsAPI`
  - `BillingAPI`
  - `AttestationAPI`
- Keep endpoint behavior byte-for-byte equivalent.
- Inject clients through `AppEnvironment`.
- Keep `PrivateChatAPI` as temporary facade only if needed by untouched code.

Exit:

- new feature services depend on protocols
- auth tests hit `AuthAPI`
- sharing tests can fake `ShareAPI`
- files tests can fake `FileAPI`

Validation:

- API/request tests
- simulator build

## Phase 3: Persistence Split

Purpose: remove storage keys, filenames, account scoping, and migration from app-wide state.

Actions:

- Extract adapters:
  - `SessionPersistence`
  - `SettingsPersistence`
  - `ConversationCache`
  - `MessageCache`
  - `ProjectPersistence`
  - `DraftPersistence`
  - `FileCache`
  - `AgentThreadPersistence`
- Move account-scope helpers out of `ChatStore`.
- Make adapters small and fakeable.
- Do not change stored key formats unless migration test exists.

Exit:

- `ChatStore` has no direct defaults/keychain/file cache helpers except temporary forwarding
- persistence tests own migration and fallback scope behavior

Validation:

- persistence tests
- simulator build

## Phase 4: Sharing Full Extraction

Purpose: prove real feature ownership on a bounded domain.

Actions:

- Create `SharingService` backed by `ShareAPI`.
- Turn `ShareStore` into `@MainActor ObservableObject`.
- Move share state out of `ChatStore`:
  - share info
  - shared-with-me
  - share groups
  - shared preview
  - loading flags
  - public/direct/org/group mutations
- Update sharing views to use `ShareStore`, not `ChatStore`.
- Leave only a temporary forwarding bridge where chat toolbar still opens sharing UI.

Exit:

- sharing tests do not instantiate `ChatStore`
- sharing UI no longer needs `EnvironmentObject ChatStore`
- all share mutations have one owner

Validation:

- sharing tests
- simulator build
- manual smoke by user if needed

## Phase 5: Files And Attachments Extraction

Purpose: separate document/file behavior from chat send flow.

Actions:

- Create `FileService` backed by `FileAPI` and `FileCache`.
- Turn `FileStore` into owning observable store.
- Move remote file list, preview, delete, upload, attach-to-project, attach-to-prompt.
- Extract local document text staging and large paste attachment into `AttachmentStagingStore`.
- Keep chat composer consuming a typed `PromptAttachmentDraft`.

Exit:

- file tests do not instantiate `ChatStore`
- composer does not know remote file API details
- document privacy mode has explicit owner

Validation:

- focused file tests
- affected chat/security tests
- full `NEARPrivateChatTests`
- `scripts/build-simulator.sh`
- attachment staging tests
- simulator build

## Phase 6: Projects Extraction

Purpose: move project mutation and persistence to project owner.

Status:

- Complete for project state, selection, persistence, read models, notes, links, instructions, memory, archive/unarchive, conversation assignment membership, file membership, setup starter seeding, assistant-output note saving, and agent project tool mutations.
- `ProjectStore` is now the observable owner and `ProjectService` owns the pure project mutation rules.
- Remaining bridges are explicit: `ChatStore` still coordinates draft-scope transitions when selecting all chats/projects, conversation opening/assignment side effects before Phase 7, send prompt assembly before Phase 8, and file upload/delete mechanics through the Files owners.

Actions:

- Turn `ProjectStore` into observable owning store.
- Add `ProjectService` using `ProjectPersistence`.
- Move project CRUD, archive, note/link/instruction/memory mutation, assignment, selected project.
- Expose read models for Home and Chat:
  - selected project summary
  - prompt context
  - membership state
  - project-scoped conversations
- Agent tools must call project service actions, not mutate chat arrays.

Exit:

- project tests do not instantiate `ChatStore`
- `ChatStore` no longer persists projects
- Home and Chat read project state through narrow models

Validation:

- project tests
- agent-project mutation tests
- simulator build

## Phase 7: Conversation And Message Cache Extraction

Purpose: isolate conversation lifecycle from chat UI.

Status:

- Complete for conversation list, selected conversation, refresh/cache fallback, create/open/select/new, delete/archive/unarchive/pin/rename/clone, visible/archived/all read models, local external-model message preservation, selected response variants, remote item mapping, and message cache load/save/remove.
- Home reads conversation lists and archived chats through `ConversationStore`.
- `ChatStore` is only a compatibility coordinator for send/app/demo/Agent bridges that still need draft, project, route, and stream context before Phase 8.

Actions:

- Create `ConversationStore`.
- Move conversation list, selected conversation, archive/pin/rename/delete/clone, cached previews.
- Create `MessageRepository` for load/save local/remote messages.
- Move selected response variant tracking into chat/message owner.
- Define one source of truth for current conversation.

Exit:

- Home reads `ConversationStore`
- Chat reads selected conversation/message repository
- delete/archive/pin/rename no longer live in `ChatStore`

Validation:

- conversation tests
- message repository tests
- simulator build

## Phase 8: Chat Send Pipeline Extraction

Purpose: remove highest-risk logic from god object into explicit transaction.

Status:

- Complete for the ordinary chat send transaction: `ChatSendCoordinator` now owns draft snapshot/clear/restore, Hosted handoff continuation, route-readiness blocking, staged attachment resolution, conversation ensure/create, user/assistant append, single-model stream start/fallback, cancel, retry/regenerate, and edit-and-resend branch truncation.
- `MessageTimelineStore` now owns stream event application, text-delta buffering, selected response variants, assistant completion, and stream cancellation mutation.
- Remaining bridges are explicit: `ChatStore` still hosts quick-intent/tracker fast paths, Council fan-out/synthesis, Hosted/phone Agent runtime, model-routing heuristics, project prompt context, and app/demo glue until Phases 9/13/15. The send coordinator calls these through a send-only host bridge rather than owning those domains.

Actions:

- Create `ChatSendCoordinator`.
- Move send flow:
  - draft snapshot
  - attachment resolution
  - route readiness
  - conversation creation
  - user message append
  - stream start/cancel
  - retry/regenerate/edit-and-resend
- `ChatFeatureStore` owns transcript/composer state and delegates to coordinator.
- Use `MessageTimelineStore` for event application.

Exit:

- `sendDraft`, `send`, retry/regenerate/edit flow no longer live in `ChatStore`
- send tests can fake route planner, message API, stream service, repository
- stream cancellation is testable without SwiftUI

Validation:

- chat send tests
- streaming tests
- simulator build
- simulator smoke recommended

## Phase 9: Council And Model Routing Extraction

Purpose: separate model choice from chat screen and global state.

Actions:

- Move council selection, default lineup, presets, eligibility, plan locks into `ModelCatalogStore`.
- Move council fan-out/synthesis into `CouncilConversationService`.
- Keep `RoutePlanner` pure and tested.
- Chat asks model/catalog services for send-ready route.

Exit:

- council logic does not depend on `ChatStore`
- route readiness tests hit route/model services directly
- model picker views use `ModelCatalogStore`

Validation:

- model catalog tests
- council tests
- route planner tests
- simulator build

## Phase 10: Home Refactor

Purpose: remove home as second mega-screen.

Actions:

- Create `HomeStore` for home-only state and actions.
- Split `ConversationListView.swift` into:
  - `HomeScreen`
  - `HomeSidebar`
  - `HomeInboxSection`
  - `HomeProjectSection`
  - `HomeLaunchComposer`
  - `HomeSetupSurface`
  - `HomeTrustSurface`
- Split `HomeSupportingViews.swift` by setup cards, rows, toolbar, backgrounds.
- Split `HomeOrchestrationSurface.swift` into planner models, planner, views.

Exit:

- no Home Swift file over 500 lines
- `HomeScreen` does not import chat internals
- home actions emit intents or call stores, not global state

Validation:

- home planner/search tests
- simulator build

## Phase 11: Setup Split

Purpose: stop setup model/planner growth from leaking everywhere.

Actions:

- Split `SetupModels.swift` into:
  - route defaults
  - use cases
  - setup plan
  - restore planner
  - starter presets
  - capability recommendations
- Create `SetupStore` only for persisted/interactive setup state.
- Keep pure planner logic testable without stores.

Exit:

- no setup model/planner file over 500 lines
- setup tests target planner/store files
- Home consumes setup read models, not raw setup internals

Validation:

- setup tests
- simulator build

## Phase 12: Chat UI Split

Purpose: make SwiftUI screens readable after state is narrower.

Status:

- Complete for chat UI/view files: message bubbles, streaming/status rows, inline actions, source/proof/artifact/widget surfaces, widget action preview, Council room views, threaded briefing views, briefing models/schedule/store/editor/builder/detail/sample/support files, demo-capture views, composer routing/attachments/slash/state/voice pieces, toolbar chrome, and save-output sheet now live in owner-named files under 500 lines.
- Remaining non-view files over 500 lines are intentionally out of this phase: `LiveDataService.swift`, `ChatModels.swift`, and `ChatSendCoordinator.swift`.
- Remaining bridge is explicit: views still invoke `ChatStore` for compatibility actions until Agent/Account/Security/Export/final facade phases remove those call sites.

Actions:

- Split `ChatInputBar.swift` into:
  - composer bar
  - source mode menu
  - attachment shelf
  - media picker bridge
  - dictation service
  - route readiness banner
- Split `ChatScreenView.swift` into:
  - transcript screen
  - toolbar
  - export menu
  - council room launcher
  - project save sheet
- Split `ChatMessageViews.swift` into:
  - message bubble
  - message actions
  - source carousel
  - proof footer
  - artifact preview
  - edit/resend sheet

Exit:

- no chat view file over 500 lines
- views depend on `ChatFeatureStore` or explicit values/actions
- view body reads like UI, not controller logic

Validation:

- simulator build
- UI smoke when user wants

## Phase 13: Agent And Account Split

Purpose: isolate power-user surfaces from chat.

Status:

- Complete for a bounded Agent/Account pass: `AgentStore` owns hosted-thread mapping persistence, conversation-scoped IronClaw settings lookup, Agent mission prompt/brief parsing, repository launch prompt helpers, normalized hosted prompt text, tool-result markdown, and mobile capability copy.
- Focused Agent/Account tests and the full test suite passed, followed by simulator build validation.
- Remaining bridges are explicit: live Hosted/mobile Agent streaming, approvals, credentials, NEAR Cloud/account lifecycle side effects, diagnostics, and several Account UI actions still pass through `ChatStore` until Phase 15 replaces those call sites with feature stores or app-level composition.

Actions:

- Create `AgentService` and `AgentStore`.
- Move phone-safe runtime dispatch, hosted handoff, approvals, credentials, tool result rendering.
- Create `AccountStore`.
- Move billing, integration checks, diagnostics entry, settings mutations.
- Agent calls project/file/conversation services through protocols.

Exit:

- agent tool execution no longer mutates `ChatStore`
- account settings no longer depend on chat state
- diagnostic checks own one service

Validation:

- agent tests
- account/settings tests
- simulator build

## Phase 14: Security And Export Cleanup

Purpose: keep trust/proof language correct and isolated.

Status:

- Complete for a bounded Security/Export pass: `SecurityStore` owns attestation snapshot/loading/error state, proof refresh, status derivation, assistant trust/proof metadata, and signed transcript export context.
- Security and export focused tests passed, the full test suite passed, `git diff --check` passed, and `scripts/build-simulator.sh` passed.
- Follow-up Phase 15-A removed the remaining `SecurityView` dependency on `ChatStore` for selected model/route context and banners, and split proof-report/support rows out of the main file. Security UI now reads proof state from `SecurityStore`, route/model state from `ModelCatalogStore`, and Hosted IronClaw readiness from `AgentStore`.

Actions:

- Move attestation snapshot/loading/errors to `SecurityStore`.
- Make proof copy models pure.
- Keep signed transcript export using captured message metadata, not current route state.
- Ensure "verified" appears only when local proof coverage exists.

Exit:

- security UI does not depend on chat state except selected message context
- export tests remain focused

Validation:

- security tests
- export tests
- simulator build

## Phase 15: Delete Or Crush `ChatStore`

Purpose: finish reset.

Status:

- Phase 15-A complete: Security route-context decoupling and Security view split landed. `SecurityView.swift` is 976 lines and has zero `ChatStore` references.
- Phase 15-A partial Account cleanup landed: Account capability/detail surfaces now use `AccountStore`, `AgentStore`, `ModelCatalogStore`, and `SecurityStore` for most status/settings reads. Remaining `AccountCapabilitiesViews.swift` `ChatStore` references are explicit bridges for import/share/security presentation, global banners, and default-model empty-chat switching.
- Phase 15-B complete: `AccountCapabilitiesViews.swift` is split into parent Account settings, detail pushes, Capability Center, capability support cards, and connection cards. Every new Account file is under 500 lines; the parent is 630 lines.
- Phase 16-A complete: `AgentWorkspaceView.swift` was split into a 52-line shell, `AgentMissionControlPanel.swift`, and `AgentWorkspaceSetupViews.swift`. Agent Workspace project reads now use `ProjectStore`; setup snapshot and launch/send behavior remain explicit `ChatStore` bridges until Setup defaults and `ChatSendCoordinator` ownership are narrowed.
- Phase 16-B complete: `ChatToolbar.swift` now reads route/source/Council state from `ModelCatalogStore`, project context from `ProjectStore`, proof status from `SecurityStore`, Agent availability from `AgentStore`, and selected conversation title/state from `ConversationStore`. Remaining `ChatStore` references are action/export/sheet compatibility bridges.
- Phase 16-C complete: Account settings stopped using `ChatStore` for Account-only banners and removed unused `ChatStore` environment injection for Account/Agent/Security sheets. Remaining Account `ChatStore` references are import and default-model empty-chat compatibility only.
- Phase 16-D complete: `ShareViews.swift` was split into a share-conversation surface and a support surface with project/share group sheets. Both files remain under the 1000-line failure threshold.
- Phase 16-E complete: `ShareConversationView` no longer depends on `ChatStore` for transcript, proof, route, project-source, selected-conversation, or banner state. Remaining Sharing `ChatStore` references are selected-conversation rename and shared-preview open/copy bridges.
- Phase 16-F complete: `RenameConversationView` now uses `ConversationStore` directly. The only remaining Sharing-local `ChatStore` bridge is `SharedConversationSheet`.
- Phase 16-G complete: `SharedConversationSheet.swift` no longer depends on `ChatStore` or `MessageBubble`; shared-preview open/copy behavior is injected from host surfaces as callbacks.
- Phase 16-H complete: toolbar/export trust context duplication was collapsed into `SecurityStore`, and the transcript-copy action moved to `Core/Export`.
- Phase 16-I complete: Account settings import/default-model behavior moved to `AccountStore`, `Core/Export`, and `ModelCatalogStore`; `AccountSettingsView` has zero `ChatStore` dependency.
- Phase 16-J complete: `ProjectFilesView` receives explicit host callbacks for chat-opening, prompt staging, route preview, and project file mutation. It no longer uses a `ChatStore` environment object; upload/removal remain host actions because file upload, document-text staging, notices, and file registration are still split across File/Chat compatibility code.
- Phase 16-K complete: hosted handoff preflight state and disclosure moved to `AgentStore`, with project disclosure supplied by `ProjectStore`. Approval resolution stays in `ChatStore` because it still mutates active streaming/transcript state and talks to Hosted IronClaw gates.
- Phase 16-L complete: `ProjectContextViews.swift` was split into `ProjectContextSupportViews.swift`, putting both files under the 1000-line quality bar without behavior changes.
- Phase 16-M complete: message-load task/generation/cancel/reset ownership moved into `ChatMessageLoadCoordinator`, with tests proving cache-first UI application and reset cancellation.
- Phase 16-N complete: archive UI moved from the project surface to `Features/Conversations/ArchivedChatsView.swift`; project and archive files remain under the 1000-line quality bar.
- Phase 16-O complete: selected-conversation navigation pulse moved to `ConversationStore`; App shell and archive sheet no longer observe `ChatStore` for that conversation-only signal.
- Phase 16-P complete: pending delete confirmation state moved to `ConversationStore`; App shell, Home menus, and archive sheet request/cancel through the conversation owner while final deletion stays in `ChatStore` until cache/project side effects are extracted.
- Phase 16-Q complete: selected-only clone/archive/pin/delete wrappers were removed from `ChatStore`; toolbar passes the selected conversation into the real action methods or requests delete confirmation from `ConversationStore`.
- Phase 16-R complete: toolbar More-menu sections moved to `ChatToolbarMenuContent.swift`; both toolbar files are under 500 lines.
- Phase 16-S complete: unused `renameSelectedConversation` bridge deleted; rename UI already goes through `ConversationStore`.
- Phase 16-T complete: `RenameConversationView` moved from Sharing support into `Features/Conversations/RenameConversationView.swift`; rename UI is now colocated with the conversation owner.
- Phase 16-U complete: Project creation/editing sheets moved from Sharing support into `Features/Projects/ProjectEditorViews.swift`; Sharing support now contains only sharing-related views.
- Phase 16-V complete: `cloneSharedPreviewToChat` wrapper deleted; shared-preview hosts call the real conversation clone action directly.
- Phase 16-W complete: `ArchivedChatsView` dropped its `ChatStore` environment dependency and uses `ConversationStore` for restore actions and archive export/copy banners.
- Phase 16-X complete: archived-conversation restore actions moved into `ConversationStore`; Home archived rows and the archive sheet no longer call `ChatStore` for restore, and the old unarchive wrappers were removed.
- Phase 16-Y complete: stale `ChatStore` injection was removed from the project editor sheet; `EditProjectView` now receives only `ProjectStore`.
- Phase 16-Z complete: writable shared-preview open now goes through `ChatSessionCoordinator`, which owns selecting the conversation, replacing preview messages, clearing composer state, and pulsing navigation; `ChatStore.openSharedPreviewForWriting` is now a compatibility adapter.
- Phase 16-AA complete: ordinary conversation switching and start-new transitions now go through `ChatSessionCoordinator`; `ChatStore.selectConversation` and `startNewConversation` are compatibility adapters.
- Phase 16-AB complete: delete/clone/archive/pin side-effect choreography moved to `ConversationActionCoordinator`; `ChatStore` keeps only Task-launching compatibility adapters and cross-domain callbacks.
- Phase 16-AC complete: pending-delete confirmation moved to `ConversationActionCoordinator`; `ChatStore.confirmPendingDelete` keeps only Task-launching compatibility glue.
- Phase 16-AD complete: all-chats/project selection and selected-project archive session transitions moved to `ChatSessionCoordinator`; `ChatStore` keeps only callback adapters for draft persistence and message loading.
- Phase 16-AE complete: active draft scope, account-scoped draft persistence, loaded-draft suppression, and persisted draft removal moved to `ChatDraftScopeStore`; `ChatStore` no longer stores draft scope IDs or suppression flags directly.
- Phase 16-AF complete: send-host draft cleanup removed the active draft scope ID from `ChatSendCoordinatorHost`; send now discards the active draft through a draft-owner operation instead of passing scope strings through `ChatStore`.
- Phase 16-AG complete: send-time conversation activation now goes through `ChatSessionCoordinator`, so selection and draft-scope transition are one session-owner operation instead of two send-host mutations.
- Phase 16-AH complete: local send fast-path dispatch now goes through `ChatLocalIntentDispatcher`, so quick-intent parsing and pending NEAR-account tracker dispatch decisions are testable outside `ChatStore`. `ChatStore` still executes local intent side effects and transcript mutations.
- Phase 16-AI complete: live-widget lookup for quick intents moved to `ChatLocalIntentWidgetService`, leaving `ChatStore` with transcript append/update and side-effect execution only.
- Phase 16-AJ complete: local transcript message construction moved to `ChatLocalIntentTranscriptWriter`, including pending streaming assistant messages for compound lookups.
- Phase 16-AK complete: local intent confirmation, memory, activity-log, history-search, reminder, and fetch-failure response copy moved to `ChatLocalIntentResponseFormatter`.
- Phase 16-AL complete: tracker briefing creation, "track that" briefing drafts, NEAR-account tracker briefing creation, and related activity-log summary strings moved to `ChatLocalIntentBriefingFactory`.
- `ChatStore.swift` is 6464 lines. The next safe slice is extracting a narrow local-intent execution owner for memory/privacy/reminder/tracker side effects; do not start by ripping out `ChatSendCoordinatorHost`.

Actions:

- Remove all unused forwarding methods.
- Move remaining global reset into app composition/state.
- Replace `EnvironmentObject ChatStore` callsites.
- Delete `ChatStore` if no longer needed.
- If temporary facade remains, keep under 300 lines with explicit deletion TODO.

Exit:

- no feature behavior owned by `ChatStore`
- new work starts in feature folders by default
- no god files over 1000 lines in app target

Validation:

- full test suite
- simulator build
- simulator smoke

Recent validation:

- Phase 15-B: focused Account tests, full `NEARPrivateChatTests`, `git diff --check`, and `scripts/build-simulator.sh` passed.
- Phase 16-A: focused Agent + Projects tests, full `NEARPrivateChatTests`, `git diff --check`, and `scripts/build-simulator.sh` passed.
- Phase 16-B: focused Chat + ModelCatalog + Security tests, full `NEARPrivateChatTests`, `git diff --check`, and `scripts/build-simulator.sh` passed.
- Phase 16-C: focused Account tests, full `NEARPrivateChatTests`, `git diff --check`, and `scripts/build-simulator.sh` passed.
- Phase 16-D: focused Sharing + Projects tests, full `NEARPrivateChatTests`, `git diff --check`, and `scripts/build-simulator.sh` passed.
- Phase 16-E: focused Sharing + Security + Projects tests, full `NEARPrivateChatTests`, `git diff --check`, and `scripts/build-simulator.sh` passed.
- Phase 16-F: focused Sharing + Chat tests, full `NEARPrivateChatTests`, `git diff --check`, and `scripts/build-simulator.sh` passed.
- Phase 16-G: focused Sharing + Home + Chat tests, full `NEARPrivateChatTests`, `git diff --check`, and `scripts/build-simulator.sh` passed.
- Phase 16-H: focused Security + Export tests, `git diff --check`, and `scripts/build-simulator.sh` passed.
- Phase 16-I: focused Export import tests, `git diff --check`, and `scripts/build-simulator.sh` passed.
- Phase 16-J: focused Projects tests passed.
- Phase 16-K: focused Agent hosted-preflight, Project fingerprint, and approval-redaction tests passed; `git diff --check` and `scripts/build-simulator.sh` passed.
- Phase 16-L: focused Projects tests passed; `git diff --check` and `scripts/build-simulator.sh` passed.
- Phase 16-M: focused message repository/timeline/load coordinator tests passed; `git diff --check` and `scripts/build-simulator.sh` passed.
- Phase 16-N: archive view relocation passed `git diff --check` and `scripts/build-simulator.sh`.
- Phase 16-O: focused `testConversationStoreOwnsOpenSelectedConversationPulse` passed; `git diff --check` and `scripts/build-simulator.sh` passed.
- Phase 16-P: focused `testConversationStoreOwnsOpenSelectedConversationPulse` and `testConversationStoreOwnsPendingDeleteConfirmation` passed; `git diff --check` and `scripts/build-simulator.sh` passed.
- Phase 16-Q: selected-wrapper cleanup passed `git diff --check` and `scripts/build-simulator.sh`.
- Phase 16-R: toolbar menu split passed `git diff --check` and `scripts/build-simulator.sh`.
- Phase 16-S: stale rename wrapper removal passed `git diff --check` and `scripts/build-simulator.sh`.
- Phase 16-T: rename view relocation passed `git diff --check` and `scripts/build-simulator.sh`.
- Phase 16-U: project editor relocation passed `git diff --check` and `scripts/build-simulator.sh`.
- Phase 16-V: shared-preview clone wrapper cleanup passed `git diff --check` and `scripts/build-simulator.sh`.
- Phase 16-W: archive surface cleanup passed `git diff --check` and `scripts/build-simulator.sh`.
- Phase 16-X: focused `testConversationStoreMutationsOwnLocalListAndSelection` passed; `git diff --check` and `scripts/build-simulator.sh` passed.
- Phase 16-Y: stale project-editor `ChatStore` injection cleanup passed `git diff --check` and `scripts/build-simulator.sh`.
- Phase 16-Z: focused `testChatSessionCoordinatorOwnsWritableSharedPreviewOpen` passed; `git diff --check` and `scripts/build-simulator.sh` passed.
- Phase 16-AA: focused `testChatSessionCoordinatorOwnsWritableSharedPreviewOpen` and `testChatSessionCoordinatorOwnsConversationSwitchAndStartNew` passed; `git diff --check` and `scripts/build-simulator.sh` passed.
- Phase 16-AB: focused `testConversationActionCoordinatorOwnsConversationSideEffects` passed; `git diff --check` and `scripts/build-simulator.sh` passed.
- Phase 16-AC: focused `testConversationActionCoordinatorOwnsConversationSideEffects` passed with pending-delete confirmation coverage; `git diff --check` and `scripts/build-simulator.sh` passed.
- Phase 16-AD: focused `testChatSessionCoordinatorOwnsWritableSharedPreviewOpen`, `testChatSessionCoordinatorOwnsConversationSwitchAndStartNew`, and `testChatSessionCoordinatorOwnsProjectSelectionTransitions` passed; `git diff --check` and `scripts/build-simulator.sh` passed.
- Phase 16-AE: focused `testChatDraftScopeStoreOwnsScopeAndPersistenceSuppression` plus the three `ChatSessionCoordinator` ownership tests passed; `git diff --check` and `scripts/build-simulator.sh` passed.
- Phase 16-AF: focused `testChatDraftScopeStoreOwnsScopeAndPersistenceSuppression` plus session, conversation-action, tracker-send, and pending NEAR-account send tests passed; `git diff --check` and `scripts/build-simulator.sh` passed.
- Phase 16-AG: focused `testChatSessionCoordinatorOwnsConversationSwitchAndStartNew` plus session/project, tracker-send, pending NEAR-account send, and normal-routing send tests passed; `git diff --check` and `scripts/build-simulator.sh` passed.
- Phase 16-AH: focused local-intent dispatcher and pending NEAR-account send tests passed; `git diff --check` and `scripts/build-simulator.sh` passed.
- Phase 16-AI: focused local-intent dispatcher/widget-service and pending NEAR-account send tests passed; `git diff --check` and `scripts/build-simulator.sh` passed.
- Phase 16-AJ: focused local-intent dispatcher/widget-service/transcript-writer and pending NEAR-account send tests passed; `git diff --check` and `scripts/build-simulator.sh` passed.
- Phase 16-AK: focused local-intent formatter/dispatcher/widget-service/transcript-writer tests passed; `git diff --check` and `scripts/build-simulator.sh` passed.
- Phase 16-AL: focused local-intent briefing-factory/formatter/dispatcher/widget-service/transcript-writer tests passed after making the NEAR-account schedule assertion locale-safe.

## Phase Order Rationale

Order matters.

1. Tests split first because current test file blocks safe movement.
2. API and persistence split next because every feature extraction needs fakeable seams.
3. Sharing/files/projects before chat send because boundaries are clearer and reduce `ChatStore` surface.
4. Conversation/message cache before send pipeline because send needs one owner for selected conversation and messages.
5. Chat send/council after dependencies are narrow.
6. UI file splits after state ownership improves, otherwise views keep depending on global state.
7. Final phase deletes compatibility facade.

## Architecture Review Bar

Block changes that:

- add new unrelated methods to `ChatStore`
- push any Swift file over 1000 lines
- add feature-specific branches to shared/core code
- add storage keys outside persistence adapters
- add API methods only to the mega-client without domain protocol
- pass full feature stores into small subviews when explicit values/actions suffice
- introduce optional/cast-heavy state where invariant can be explicit
- move code without deleting concepts or improving ownership

Preferred move: delete a responsibility from the wrong owner and give it one canonical home.
