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

- files tests
- attachment staging tests
- simulator build

## Phase 6: Projects Extraction

Purpose: move project mutation and persistence to project owner.

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
