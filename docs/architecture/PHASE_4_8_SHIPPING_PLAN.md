# Phases 4-8 Shipping Plan

Date: 2026-05-26

## Goal

Ship the remaining feature-first cleanup in reviewable chunks without breaking the app's current product behavior. `ChatStore` remains the compatibility facade until each feature has a smaller owner.

## Shipment Status

First-pass shipment completed on 2026-05-26:

- Phase 4: `ComposerState` and `MessageTimelineStore` added and wired.
- Phase 5: `RoutePlanner`, `MessageStreamService`, and `CouncilStreamService` added and wired.
- Phase 6: `ModelCatalogStore` added and wired for picker/cloud/pinned/ranking derivation.
- Phase 7: `ProjectStore` and `FileStore` added and wired for project scoping and attachment limits.
- Phase 8: `ShareStore` added and wired for shared-author visibility.

Remaining follow-up: move mutating route, streaming, Council fan-out, project persistence, file cache/upload, and share API calls behind these owners once the facade callers have settled.

## Non-Negotiable Validation

Every shipped phase must pass:

- `git diff --check`
- `xcodebuild build -project NEARPrivateChat.xcodeproj -scheme NEARPrivateChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
- `xcodebuild test -project NEARPrivateChat.xcodeproj -scheme NEARPrivateChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
- Simulator install/launch smoke with a screenshot under `/tmp/nearprivatechat-validation/`

## Phase 4: Chat Feature State

Scope:

- Add `Features/Chat/ComposerState.swift`.
- Add `Features/Chat/MessageTimelineStore.swift`.
- Move pure draft/composer and visible-message transformation logic first.
- Keep `ChatStore` forwarding public properties until UI callers can be switched safely.

Acceptance:

- Composer defaults and route-display state are testable without SwiftUI.
- Timeline merge/variant selection is testable without rendering chat bubbles.
- `ChatStore` line count decreases or gains clear forwarding seams.

Status: shipped as first-pass seams.

## Phase 5: Streaming And Route Services

Scope:

- Add `Core/Routing/RoutePlanner.swift`.
- Add `Core/Streaming/MessageStreamService.swift`.
- Add `Core/Streaming/CouncilStreamService.swift`.
- Move route readiness, route fallback, visible-output timeout, stream cancellation, and Council fan-out into services.

Acceptance:

- Council crash surface has a single owner.
- Route decisions can be tested without `ChatStore`.
- GLM default, Council, NEAR Cloud key missing, hosted IronClaw missing, project context, and web-needed prompts have tests.

Status: shipped as first-pass seams. Deep Council fan-out extraction remains follow-up.

## Phase 6: Model Catalog And Source Routing

Scope:

- Add `Features/ModelCatalog/ModelCatalogStore.swift`.
- Add `Core/Routing/SourceRouting.swift`.
- Move model filtering, pinning limits, Council lineup validation, reasoning effort presentation, and source-mode semantics out of `ChatStore`.

Acceptance:

- Model picker can evolve without touching chat streaming.
- Council lineup and single-model selection tests live outside `ChatStore`.
- Source routing semantics are a pure tested module.

Status: shipped as first-pass seams. Source-routing semantics are still in `ChatRoutingModels.swift`; `RoutePlanner` is the forwarding point.

## Phase 7: Projects And Files

Scope:

- Add `Features/Projects/ProjectStore.swift`.
- Add `Features/Files/FileStore.swift`.
- Move project CRUD, project context, links, notes, file preview/list/upload, project cache, and file cache into feature stores.

Acceptance:

- Project context and file library can change without editing composer internals.
- File-size limits and URL/file safety checks remain enforced.
- Project/file persistence has a single owner.

Status: shipped as first-pass seams. Persistence/cache/upload migration remains follow-up.

## Phase 8: Sharing

Scope:

- Add `Features/Sharing/ShareStore.swift`.
- Move share sheet state, public link preview, direct/org/group shares, shared-with-me, shared preview/open/copy flows into sharing.
- Keep `ChatStore` bridging properties until views are switched.

Acceptance:

- Sharing permission bugs have a small surface.
- Public/private shared preview behavior is testable with fake API data.
- Share UI no longer reaches through unrelated chat state except selected conversation identity.

Status: shipped as first-pass seams. Share API mutation migration remains follow-up.

## Ship Order

1. Phase 4 foundations: `ComposerState` and `MessageTimelineStore`.
2. Phase 5 route planner: pure route/readiness extraction before streaming mutation.
3. Phase 5 streaming services: single response first, then Council.
4. Phase 6 model/source stores.
5. Phase 7 project/file stores.
6. Phase 8 sharing store.
7. Final docs, full validation, commit, push, PR update.

## Stop Conditions

Stop and leave a clear handoff only if:

- A phase requires changing hosted API contracts.
- A phase requires UI behavior changes outside the phase scope.
- A phase exposes an existing bug that cannot be fixed without product/design choice.
- Tests reveal nondeterministic behavior that would make the next phase unsafe.
