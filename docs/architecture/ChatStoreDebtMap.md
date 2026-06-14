# ChatStore Debt Map (Phase 0)

**Date:** 2026-06-11
**Scope:** `NEARPrivateChat/App/State/ChatStore.swift` and extension domains

## Guiding rule
`ChatStore` should stop owning product behavior. It should remain a narrow orchestrator with
clear delegation to feature/state owners and lightweight forwarding only where needed.

## Current ownership mapping

- **ChatStore core coordination (remaining)**
  - `NEARPrivateChat/App/State/ChatStore.swift`
  - lifecycle orchestration, compose and inject dependencies, wiring state updates, and public convenience API

- **Sharing**
  - **Target owner:** `NEARPrivateChat/Features/Sharing`
  - **Current in ChatStore:** `consumePendingSharedItem` + `consumePendingSharedItem` helpers in `ChatStore.swift`
  - **Current delegated owners:** attachment staging and share snapshots remain in `ShareStore`/`Features/Sharing` types.

- **Files / attachments**
  - **Target owner:** `NEARPrivateChat/Features/Files`
  - **Current in ChatStore:** `AttachmentStagingStore` access and send-side attachment resolution.
  - **Current delegated owners:** `NEARPrivateChat/Features/Files/FileStore.swift`, `FileService`, `NEARPrivateChat/App/State/ChatStore+SendHost.swift`, `NEARPrivateChat/App/State/ChatStore+StreamingRuntime.swift`.

- **Projects / project context**
  - **Target owner:** `NEARPrivateChat/Features/Projects`
  - **Current in ChatStore:** light orchestration and selected-project state plumbing.
  - **Current delegated owners:** `NEARPrivateChat/App/State/ChatStore+Projects.swift`, `NEARPrivateChat/Features/Projects/ProjectStore.swift`.

- **Conversations + messages**
  - **Target owner:** conversation/message repository + dedicated stores
  - **Current in ChatStore:** orchestration only (`refreshConversations`, `openConversation`, `startNewConversation`, message loading hooks).
  - **Current delegated owners:** `NEARPrivateChat/Features/Chat/ConversationStore.swift`, `NEARPrivateChat/Features/Chat/MessageTimelineStore.swift`, `NEARPrivateChat/Features/Chat/ChatTranscriptStore.swift`, `NEARPrivateChat/Features/Chat/ConversationActionCoordinator.swift`.

- **Send pipeline**
  - **Target owner:** `NEARPrivateChat/Features/Chat/ChatSendCoordinator.swift`
  - **Current in ChatStore:** pipeline entrypoints and route-readiness guards.
  - **Current delegated owners:** `NEARPrivateChat/Features/Chat/ChatSendCoordinator.swift`, send staging mirrors in `ChatStore+SendHost.swift`/`ChatStore+SendActions.swift`.

- **Streaming runtime**
  - **Target owner:** `NEARPrivateChat/Core/Streaming`
  - **Current in ChatStore:** response streaming orchestration and event application.
  - **Current delegated owners:** `NEARPrivateChat/Core/Streaming/IronclawMobileRuntime.swift`, `NEARPrivateChat/Core/Services/WebGroundingService.swift`, `NEARPrivateChat/App/State/ChatStore+StreamingRuntime.swift`, `NEARPrivateChat/App/State/ChatStore+StreamEvents.swift`.

- **Council / routing**
  - **Target owner:** `NEARPrivateChat/Features/ModelCatalog` + `NEARPrivateChat/Core/Routing`
  - **Current in ChatStore:** model selection helpers, route validation, route readiness mapping, council dispatch/synthesis orchestration.
  - **Current delegated owners:** `NEARPrivateChat/App/State/ChatStore+CouncilRuntime.swift`, `NEARPrivateChat/App/State/ChatStore+Routing.swift`, `NEARPrivateChat/Features/ModelCatalog/ModelCatalogStore.swift`.

- **Agent tools / mission tools**
  - **Target owner:** `NEARPrivateChat/Features/Agent`
  - **Current in ChatStore:** agent tool execution routing and permissioned mutations.
  - **Current delegated owners:** `NEARPrivateChat/Features/Agent/AgentStore.swift`, `NEARPrivateChat/App/State/ChatStore+AgentTools.swift`.

- **Account / settings / billing**
  - **Target owner:** `NEARPrivateChat/Features/Account`
  - **Current in ChatStore:** settings and account state facades and route checks.
  - **Current delegated owners:** `NEARPrivateChat/Features/Account/AccountStore.swift`, `NEARPrivateChat/App/State/ChatStore+Setup.swift`.

- **Security / attestation**
  - **Target owner:** `NEARPrivateChat/Features/Security`
  - **Current in ChatStore:** trusted-proof status propagation into routing and message trust metadata.
  - **Current delegated owners:** `NEARPrivateChat/Features/Security/SecurityStore.swift`, `NEARPrivateChat/App/State/ChatStore+ModelCatalog.swift`.

- **Persistence / cache / defaults**
  - **Target owner:** `NEARPrivateChat/Core/Persistence`
  - **Current in ChatStore:** persistence coordination.
  - **Current delegated owners:** `NEARPrivateChat/App/State/ChatStore+Persistence.swift`, `NEARPrivateChat/Core/Persistence/*.swift`.

- **Demo capture**
  - **Target owner:** dedicated debug/demo owner
  - **Current implementation:** `NEARPrivateChat/App/State/ChatStore+DemoCapture.swift`.

## Acceptance for Phase 0

- [x] All top-level ChatStore responsibilities enumerated.
- [x] Large behavior is now split into extension domains.
- [x] `ChatStore` remains under 1,500 lines (`1315` lines in current working tree).
- [x] No new direct behavior has been added to the old monolith root file while refactoring.

## Next hardening pass (Phase 1)

- Move share-extension intake (`consumePendingSharedItem`) into a dedicated Sharing owner.
- Move send pre-send attachment resolution from `ChatStore+StreamingRuntime` into `ChatSendCoordinator`.
- Move trust summary formatting and banner-safe attestation messaging out of ChatStore root.
- Keep `ChatStore` as orchestration/wiring until each domain has own test-backed public façade.
