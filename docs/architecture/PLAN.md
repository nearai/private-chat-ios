# Plan

## Goal

Turn current monolithic SwiftUI app into feature-first iOS app that is easy to debug, scale, test, and hand to parallel agents.

## Migration Status

As of 2026-05-26:

- Phase 0 baseline docs exist in `docs/architecture` and `CONTEXT.md`.
- Phase 1 app shell/routing foundation is complete: root lifecycle, setup, legal gate, status banner, and route/sheet models have moved into `App/`, `Features/Setup/`, and `Core/Routing/`.
- Phase 2 design-system/shared extraction is complete: haptics, design tokens, brand marks, clipboard, chip layout, view extensions, and markdown rendering now live under `Core/DesignSystem` or `Shared`.
- Phase 3 feature ownership is materially complete for file placement: Auth, Home, Chat, ModelCatalog, Sharing, Projects, Files, Account, Security, Agent, and Setup now have feature folders.
- The app shell split is complete enough for continued work: `AppShellView.swift` is down to root navigation/dialog coordination, while `ConversationListView`, shared conversation UI, and `EmptyChatView` live in their owning features.
- Phase 12 model-file split is complete as a mechanical first pass: the former monolithic `Models.swift` has been replaced by domain model files.
- Phases 4-8 now have first-pass service/store owners: `ComposerState`, `MessageTimelineStore`, `RoutePlanner`, `MessageStreamService`, `CouncilStreamService`, `ModelCatalogStore`, `ProjectStore`, `FileStore`, and `ShareStore`.
- Next phase: continue reducing `ChatStore` beyond the compatibility facade, starting with route mutation, Council fan-out, project persistence, file cache, and sharing API calls.

## Guardrails

- Preserve behavior while moving code.
- Keep app phone-first.
- Keep hosted API contracts unchanged.
- Use `pnpm` only for JS verifier work.
- Do not run or create DB migrations.
- Do not run localhost app.
- Do not build for tiny docs/style-only edits unless needed.

## Phase 0: Baseline Map

- Record current file ownership and line counts.
- Create feature map from existing `AppShellView.swift`, `ChatStore.swift`, `Models.swift`, and API files.
- Identify public behaviors that must not change for each feature.
- Create first smoke checklist for manual verification.

Exit:

- `ARCHITECTURE.md` defines target folders, routing, state ownership, service seams.
- `CONTEXT.md` defines product terms.
- Each future extraction has owner feature.

## Phases 4-8 Shipment

Detailed execution plan: `docs/architecture/PHASE_4_8_SHIPPING_PLAN.md`.

Shipping rule: phases 4-8 move behavior out of `ChatStore` in service/store chunks, not by changing the app's user-facing flow. Each phase must build, test, simulator-smoke, and update docs before being pushed.

## Phase 1: App Shell And Routing

- Create `App/RootView.swift`.
- Create `App/StatusBanner.swift`.
- Create `Features/Setup/UserSetupView.swift`.
- Create `Features/Setup/LegalTermsRequiredView.swift`.
- Create `Core/Routing/AppRoute.swift`.
- Create `Core/Routing/AppSheet.swift`.
- Create `Core/Routing/AppRouter.swift`.
- Add all new Swift files to `NEARPrivateChat.xcodeproj/project.pbxproj`.
- Move root auth/setup/legal/banner routing out of `NEARPrivateChatApp.swift`.
- Convert `AppRouter` as `ObservableObject` for Phase 1 and inject with current `EnvironmentObject` style.
- Remove `private` from moved Swift declarations only when another file must reference them.
- Keep `ChatStore` as compatibility facade for this phase.
- Keep existing `SessionStore` name; do not rename auth state in this phase.

Exit:

- Navigation and sheets have one route model.
- `NEARPrivateChatApp.swift` no longer contains root setup/legal/banner view declarations.
- Feature-specific nested `NavigationStack` and sheets may remain local until their feature extraction.
- Sign-in, sign-out, deep links, setup rerun still route correctly.
- Simulator build succeeds after Swift file/project changes.

## Phase 2: Design System Extraction

- Move colors, typography helpers, haptics, toolbar icons, chips, cards, rows, empty states, and loading rows into `Core/DesignSystem` and `Shared/Components`.
- Move markdown renderer into `Shared/Components/Markdown`.
- Keep visuals unchanged.

Exit:

- `AppShellView.swift` no longer owns reusable visual primitives.
- Feature screens compose shared primitives.

Status: complete on 2026-05-26.

## Phase 3: Home Feature

- Create `Features/Home`.
- Move conversation list, search/filter, project rows, recent cards, and home actions.
- Introduce `HomeStore` only if local state and derived values exceed view-local state.
- Keep data backed by existing facade until conversation/project stores exist.

Exit:

- Home feature can be debugged without opening chat/composer/sharing code.

Status: partial/structural complete on 2026-05-26. UI ownership moved; `HomeStore` intentionally deferred until `ChatStore` facade is reduced.

## Phase 4: Chat Feature

- Create `Features/Chat`.
- Move `ChatView`, toolbar, transcript list, message bubbles, composer, attachments strip, source strip, response variants, inline actions.
- Create `MessageTimelineStore` for visible messages and stream application.
- Create `ComposerState` for draft, source mode display, prompt attachments, and route readiness display.

Exit:

- Chat UI no longer depends on home/project/account UI code.
- Message timeline changes test without rendering SwiftUI.

Status: first-pass complete on 2026-05-26. Chat UI files moved; `MessageTimelineStore` owns visible transcript grouping and `ComposerState` owns sendability state.

## Phase 5: Streaming And Route Services

- Create `Core/Streaming/MessageStreamService`.
- Create `Core/Streaming/CouncilStreamService`.
- Create `Core/Routing/RoutePlanner`.
- Move fallback, visible-output timeout, cancellation, Council fan-out, and synthesis out of `ChatStore`.

Exit:

- Response streaming bugs have one owner.
- Route decisions test without UI.

Status: first-pass complete on 2026-05-26. `RoutePlanner` owns route classification/readiness/source-routing forwarding, `MessageStreamService` owns visible-output timeout policy, and `CouncilStreamService` owns the Council concurrency limit. Deeper streaming mutation/fan-out extraction remains follow-up.

## Phase 6: Model Catalog And Source Routing

- Create `Features/ModelCatalog`.
- Move model picker, capability filters, pinned models, council picker, reasoning effort UI.
- Move source-mode semantics into `Core/Routing/SourceRouting`.
- Split API model DTOs from UI display models.

Exit:

- Model catalog and route readiness are independent from chat screen layout.

Status: first-pass complete on 2026-05-26. `ModelCatalogStore` owns cloud route models, external models, picker models, pinned picker derivation, and ranking. Source-routing semantics remain in `ChatRoutingModels.swift` with `RoutePlanner` forwarding.

## Phase 7: Projects And Files

- Create `Features/Projects`.
- Create `Features/Files`.
- Move project CRUD, project context, notes, links, reusable files, remote file list/preview, attachment upload.
- Create storage adapters for project cache, file cache, and drafts.

Exit:

- Project context and file library can evolve without touching composer internals except explicit interfaces.

Status: first-pass complete on 2026-05-26. `ProjectStore` owns selected-project conversation scoping and visible/archived filtering. `FileStore` owns prompt/project attachment limit decisions. Project persistence/file cache/upload are still bridged through `ChatStore`.

## Phase 8: Sharing

- Create `Features/Sharing`.
- Move share sheet, public link preview, direct/org/group shares, shared-with-me, shared preview/open/copy flows.
- Create `ShareStore` backed by `ShareAPI`.

Exit:

- Sharing permission bugs have small surface and fakeable API tests.

Status: first-pass complete on 2026-05-26. `ShareStore` owns shared-author visibility state. Share API mutation and sheet state are still bridged through `ChatStore`.

## Phase 9: Security And Attestation

- Create `Features/Security`.
- Move attestation state display, proof capsule, security rows, diagnostics rows, local verification state.
- Keep language strict: attestation unless proof chain actually verified.

Exit:

- Privacy/security copy and state model reviewable in one feature.

## Phase 10: Agent And Account

- Create `Features/Agent`.
- Move IronClaw Mobile UI, hosted handoff, approval/credential gates, tool-call status.
- Create `Features/Account`.
- Move settings, billing, imports, integration checks, diagnostics entry.

Exit:

- Power-user surfaces no longer expand chat/home files.

## Phase 11: API Split

- Split `PrivateChatAPI` into protocol-backed API clients by domain.
- Keep shared request/response plumbing in `Core/API`.
- Add fakes for tests.

Exit:

- Tests can target each API domain.
- Feature services depend on protocols, not concrete mega-client.

## Phase 12: Model Split

- Split `Models.swift` into domain files:
  - `Core/Auth/AuthModels.swift`
  - `Core/API/APIError.swift`
  - `Features/Chat/ChatModels.swift`
  - `Features/ModelCatalog/ModelCatalogModels.swift`
  - `Features/Projects/ProjectModels.swift`
  - `Features/Sharing/SharingModels.swift`
  - `Features/Security/AttestationModels.swift`
  - `Features/Agent/AgentModels.swift`
- Move UI-only extensions/components out of model files.

Exit:

- No model file mixes API DTOs, storage helpers, view components, and design constants.

Status: complete as a mechanical first pass on 2026-05-26. Follow-up cleanup should refine ownership if a type is found in the wrong first-pass file.

## Phase 13: Cleanup Gates

- Remove compatibility facade methods that have no callers.
- Add `MARK` only where useful during transition.
- Keep public feature imports clean.
- Update docs when architecture changes.

Exit:

- `AppShellView.swift`, `ChatStore.swift`, and `Models.swift` stop being default edit targets.
- New feature work starts inside feature folder.

## First Extraction Candidate

Start with Home or Sharing.

Recommended: Sharing first if risk focus is correctness. It has clear API boundary and fewer layout dependencies than Chat.

Recommended: Home first if goal is fast visible file-size reduction. It gives quick win but less architectural proof.

My pick: Sharing first.
