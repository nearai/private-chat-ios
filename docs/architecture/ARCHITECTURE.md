# Architecture

## Current State

The app works, and Phase 1 has started the feature-first migration. Root app shell code now lives in `App/`, setup/legal views live in `Features/Setup/`, and root route/sheet types live in `Core/Routing/`.

The remaining concentration is still significant:

- `AppShellView.swift` owns home composition and still coordinates chat, model picker, sharing, project context, account, security, agent workspace, and many design primitives through extracted sibling files.
- `ChatStore.swift` owns conversation state, project state, sharing, files, streaming, source routing, settings, billing, attestation, agent tools, persistence, cache, and banners.
- `Models.swift` mixes product models, API DTOs, routing semantics, local storage helpers, visual constants, and UI components.

This shape blocks fast debug because feature behavior, UI, network, persistence, and route decisions live in same files.

## Target Shape

Use feature-first SwiftUI with small shared core modules.

```txt
NEARPrivateChat/
  App/
    NEARPrivateChatApp.swift
    RootView.swift
    AppEnvironment.swift
    AppLifecycle.swift
  Core/
    API/
    Auth/
    Cache/
    DesignSystem/
    Diagnostics/
    Export/
    Persistence/
    Routing/
    Security/
    Telemetry/
  Features/
    Account/
    Agent/
    Auth/
    Chat/
    Files/
    Home/
    ModelCatalog/
    Projects/
    Security/
    Setup/
    Sharing/
  Shared/
    Components/
    Extensions/
    Utilities/
  Resources/
```

Rule: feature owns its screen, reducer/store slice, feature-specific components, and feature-specific helpers. Core owns cross-feature services only.

Swift access rule: when moving current `private` view types or extensions into separate files, remove `private` only from declarations that must be referenced cross-file. Keep helper subviews `private` when they stay in the same file as their only caller.

## App Shell

Target state: root app creates one dependency graph:

- `PrivateChatAPI`
- `SessionStore`
- `ConversationStore`
- `MessageStreamService`
- `ProjectStore`
- `FileStore`
- `ShareStore`
- `SettingsStore`
- `AttestationStore`
- `AgentRuntimeStore`
- `BannerCenter`
- `AppRouter`

SwiftUI views read narrow dependencies. Avoid passing full app store into every feature once extraction starts.

Transition rule: Phase 1 keeps current `SessionStore` and `ChatStore` environment objects. New stores are introduced only when their feature is extracted.

Phase 1 completed on 2026-05-26:

- `NEARPrivateChatApp.swift` is now app construction and dependency install.
- `App/RootView.swift` owns root auth/setup/legal/banner presentation.
- `App/AppLifecycle.swift` owns root URL, auth, profile, account-switch, and bootstrap callbacks.
- `Core/Routing/AppRoute.swift`, `AppSheet.swift`, and `AppRouter.swift` establish the route model for later feature extraction.
- `Features/Setup/UserSetupView.swift` and `LegalTermsRequiredView.swift` own setup/legal UI.

## Routing

Use enum routes, not scattered booleans.

```swift
enum AppRoute: Hashable {
    case chat(conversationID: String)
    case sharedConversation(id: String)
    case project(id: String)
    case security
    case account
}

enum AppSheet: Identifiable {
    case modelPicker
    case share(conversationID: String)
    case projectFiles(projectID: String)
    case setup
    case accountSettings
}
```

Target state: `AppRouter` owns:

- navigation path
- active sheet
- external deep-link handoff
- reset on sign-out/account switch

Route mapping lives in one `Routing` module. Feature views call router actions, not `NavigationStack` state directly.

Transition rule: do not replace every nested `NavigationStack` in one pass. Phase 1 introduces route/sheet types and moves root-level auth/setup/legal/banner routing first. Feature-specific sheets stay local until their feature extraction.

Phase 1 router should match the current app style: `ObservableObject` with `@StateObject` ownership and `@EnvironmentObject` injection. A later Observation migration may switch to `@Observable` after state ownership is smaller.

## State Ownership

Keep state at narrowest owner:

- Local UI state -> `@State`
- Child mutation -> `@Binding`
- Feature data and async behavior -> feature store or service
- Cross-feature app services -> environment injection
- Route and sheets -> `AppRouter`

No new global mega-store. `ChatStore` becomes temporary facade during migration, then disappears or shrinks to composition root adapter.

## Feature Boundaries

### Auth

Owns sign-in, callback parsing, session persistence, profile refresh, sign-out.

### Home

Owns conversation list UI, search/filter state, project summary rows, quick actions. Calls conversation/project stores.

### Chat

Owns transcript UI, composer, message actions, response variants, markdown rendering, source strips. Calls message streaming and routing services.

### Model Catalog

Owns model catalog, ranked picker, pinned models, council selection, route readiness.

### Projects

Owns project CRUD, project instructions, memory, links, notes, project-scoped files.

### Files

Owns local file import, remote file list, preview, upload limits, prompt/project attachment behavior.

### Sharing

Owns public links, direct shares, org shares, share groups, shared-with-me, shared previews.

### Security

Owns attestation display, proof language, local verification state, diagnostics tied to privacy/security.

`Core/Security` is for shared security utilities such as URL validation, keychain wrappers, and cryptographic helpers. `Features/Security` is for user-facing attestation/security UI.

### Agent

Owns IronClaw Mobile runtime, hosted handoff preflight, tool calls, approval/credential gates.

### Account

Owns billing, settings, imports, integrations, diagnostics entrypoints.

## Service Boundaries

`PrivateChatAPI` should become protocol-backed clients:

- `AuthAPI`
- `ConversationAPI`
- `MessageAPI`
- `ModelAPI`
- `FileAPI`
- `ShareAPI`
- `SettingsAPI`
- `BillingAPI`
- `AttestationAPI`

Each client returns typed DTOs. Feature services translate DTOs into domain models when needed.

Xcode project rule: this project uses manual `PBXGroup`, `PBXFileReference`, and `PBXSourcesBuildPhase` entries, not filesystem-synchronized groups. Every new Swift source file must be added to `NEARPrivateChat.xcodeproj/project.pbxproj` with target membership.

## Persistence

Create explicit storage adapters:

- `KeychainSessionStore`
- `UserDefaultsSettingsStore`
- `FileCacheStore`
- `DraftStore`
- `ProjectLocalStore`
- `MessageCacheStore`

No feature should build UserDefaults keys inline. Account-scoped keys live in one persistence helper.

## Streaming

Move stream orchestration out of view-facing store:

- `MessageStreamService` owns `/v1/responses` stream parsing and cancellation.
- `CouncilStreamService` owns parallel model fan-out and synthesis.
- `RoutePlanner` chooses NEAR Private, NEAR Cloud, IronClaw Mobile, Hosted IronClaw, or Council.
- `MessageTimelineStore` applies stream events to visible message state.

This isolates hard bugs: stale stream, retry/fallback, branch variants, visible-output timeout, cancellation.

## UI Standards

- One component per file when moved out.
- Target components under 150 lines when natural.
- Split by feature first, shared components second.
- No feature screen imports unrelated feature internals.
- Design primitives live in `Core/DesignSystem`.
- Markdown renderer is shared UI, not chat screen inline code.
- Sheets use enum-driven presentation.
- Destructive actions use confirmation or undo model.

## Testing Shape

Tests should target extracted seams:

- API request builders and stream event parser
- route planner
- source-mode semantics
- message timeline reducer
- council selection and failure isolation
- project/file attachment limits
- sharing permission flows
- auth callback state validation
- attestation wording/state model

No live network in unit tests. Use protocols and fakes at service seams.

## Migration Rule

Do not big-bang rewrite. Extract one vertical feature at a time:

1. Copy smallest complete UI cluster into feature folder.
2. Move feature-only helpers with it.
3. Replace direct `ChatStore` reads with narrow facade methods.
4. Extract service/store behind facade.
5. Add focused tests where behavior changed or seam is risk-heavy.
6. Remove old code from monolith only after callsites compile.

## Non-Goals

- No backend contract redesign.
- No DB migrations.
- No localhost dependency for normal app.
- No visual redesign as part of architecture cleanup unless feature extraction requires tiny layout glue.
- No Swift package split until folders and seams stabilize inside app target.
