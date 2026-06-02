# Architecture

## Position

This repo needs a hard architecture reset, not cosmetic cleanup.

Current source already has feature folders, but ownership did not move far enough. Most important behavior still routes through one app-wide object. That object is doing too many jobs: app state, conversation state, project state, sharing, files, streaming, prompt assembly, model routing, account settings, persistence, agent tools, demo data, cache, banners, and UI compatibility.

Feature folders are useful only when behavior follows them. Right now several folders are place names, not boundaries.

## Audit Snapshot

Measured on 2026-06-01:

| File | Lines | Problem |
| --- | ---: | --- |
| `NEARPrivateChat/App/State/ChatStore.swift` | 11878 | God object. Central risk. Must shrink phase by phase until deleted or reduced to a tiny facade. |
| `NEARPrivateChatTests/PrivateChatCoreTests.swift` | 8352 | Test god file. Slows review, hides ownership, makes targeted changes harder. |
| `NEARPrivateChat/Features/Chat/LiveDataService.swift` | 3599 | Mixed intent parsing, live data, reminders, memory, trackers, widgets. Needs domain split. |
| `NEARPrivateChat/Features/Chat/BriefingFeature.swift` | 3016 | Feature surface plus orchestration packed together. |
| `NEARPrivateChat/Features/Chat/ChatMessageViews.swift` | 2452 | Many view components in one file. Hard to review and preview. |
| `NEARPrivateChat/Features/Home/HomeSupportingViews.swift` | 2224 | Many unrelated home/setup/supporting views in one file. |
| `NEARPrivateChat/Features/Setup/SetupModels.swift` | 2032 | Setup planning/model logic concentrated in one file. |
| `NEARPrivateChat/Core/API/PrivateChatAPI.swift` | 1590 | Domain APIs still share one concrete mega-client. |
| `NEARPrivateChat/Features/Chat/ChatInputBar.swift` | 1411 | Composer UI owns too many sheets, media actions, dictation, source routing actions. |
| `NEARPrivateChat/Features/Chat/ChatScreenView.swift` | 1385 | Chat screen still coordinates toolbar, export, security, project save, room UI. |

Repo has one Xcode project and no workspace:

- `NEARPrivateChat.xcodeproj`
- schemes: `NEARPrivateChat`, share extension, widget extension
- project uses manual file membership. Every new Swift source file must be added to `project.pbxproj`.

## Core Diagnosis

The architecture problem is not file count. It is missing ownership.

Bad current flow:

```txt
View -> ChatStore -> everything
```

Target flow:

```txt
AppEnvironment
  -> AppRouter
  -> Feature stores
  -> Domain services
  -> API clients / persistence adapters
```

No feature should need full app state. Views should receive narrow stores or explicit values/actions.

## Target Tree

```txt
NEARPrivateChat/
  App/
    Composition/
    Lifecycle/
    Navigation/
    State/
  Core/
    API/
    Auth/
    Diagnostics/
    Export/
    Persistence/
    Routing/
    Security/
    Streaming/
    Telemetry/
  Features/
    Account/
      Models/
      Services/
      Store/
      Views/
    Agent/
      Models/
      Services/
      Store/
      Views/
    Chat/
      Composer/
      Messages/
      Streaming/
      Store/
      Views/
    Files/
      Models/
      Services/
      Store/
      Views/
    Home/
      Planner/
      Store/
      Views/
    ModelCatalog/
      Models/
      Services/
      Store/
      Views/
    Projects/
      Models/
      Services/
      Store/
      Views/
    Security/
      Models/
      Services/
      Store/
      Views/
    Setup/
      Planner/
      Store/
      Views/
    Sharing/
      Models/
      Services/
      Store/
      Views/
  Shared/
    Components/
    Extensions/
    Formatting/
    Utilities/
```

Folders are allowed to stay flatter inside small features. Use this tree when code grows enough to need it.

## Ownership Rules

### App

App owns construction only:

- create API clients
- create persistence adapters
- create feature services
- create feature stores
- install environment dependencies
- handle app lifecycle callbacks
- reset app state on sign-out/account switch

App must not own feature business rules.

### Core

Core owns cross-feature infrastructure:

- authenticated request plumbing
- route planning primitives
- stream event parsing
- secure URL validation
- persistence primitives
- export primitives
- telemetry primitives
- diagnostics primitives

Core must not import feature UI.

### Features

Feature owns:

- screen views
- feature store
- feature-specific service
- feature models
- feature tests
- feature-specific formatting/helpers

Feature must not reach into unrelated feature internals. Cross-feature work flows through app-level orchestration or narrow protocols.

### Shared

Shared owns boring reusable UI/utilities only. If code knows about chat, project, setup, model route, sharing, agent, billing, or attestation, it is not shared.

## Store Rules

Use narrow stores. One store per feature or sub-feature when behavior is real.

Allowed store jobs:

- hold observable feature state
- expose user actions as methods
- call services
- translate service results into feature state

Forbidden store jobs:

- raw HTTP construction
- file/keychain/defaults key construction
- global routing decisions unrelated to feature
- prompt assembly for unrelated routes
- demo data generation
- unrelated feature mutation

State ownership:

- local view state -> `@State`
- child mutation -> `@Binding`
- root-owned observable feature store -> `@StateObject` for current deployment style
- shared app service -> environment
- domain behavior -> service/reducer/pure type

Do not create view models to mirror state. Split views first. Add a store only when it owns behavior.

## API Boundary

`PrivateChatAPI` should become request plumbing plus domain clients.

Target clients:

- `AuthAPI`
- `ConversationAPI`
- `MessageAPI`
- `ModelAPI`
- `FileAPI`
- `ShareAPI`
- `SettingsAPI`
- `BillingAPI`
- `AttestationAPI`

Each client gets a protocol. Feature services depend on protocols, not the concrete mega-client.

DTO rule: API DTOs live in API/domain files. Views consume feature/domain models, not raw response shapes.

## Persistence Boundary

No feature builds storage keys inline.

Target adapters:

- `SessionPersistence`
- `SettingsPersistence`
- `ConversationCache`
- `MessageCache`
- `ProjectPersistence`
- `DraftPersistence`
- `FileCache`
- `AgentThreadPersistence`

Each adapter owns account scoping, migration from fallback scope, filenames, defaults keys, keychain account names, and serialization.

## Routing Boundary

Routing must be enum-driven.

`AppRouter` owns:

- navigation path
- active sheet
- account reset
- external/deep-link handoff

Feature views call router actions or return intents. They should not mutate unrelated app state to cause navigation.

Feature-local sheet state can stay local only when it does not cross feature boundaries.

## Streaming Boundary

Streaming must leave `ChatStore`.

Target flow:

```txt
ChatStore/ChatFeatureStore
  -> ChatSendCoordinator
  -> RoutePlanner
  -> MessageStreamService / CouncilStreamService / AgentRuntimeService
  -> MessageTimelineStore
```

Ownership:

- `RoutePlanner`: route classification, readiness, source policy
- `MessageStreamService`: response stream request, event parsing, timeout policy
- `CouncilStreamService`: fan-out, per-model result collection, synthesis input
- `AgentRuntimeService`: phone-safe and hosted agent dispatch
- `MessageTimelineStore`: apply events to visible messages
- `ChatSendCoordinator`: one send transaction from draft to final state

No UI file should assemble streaming prompts or mutate message arrays directly.

## Feature Targets

### Chat

Owns transcript, composer, message actions, response variants, selected answer export, source chips, and route readiness UI.

Must not own home setup cards, project storage, model catalog fetching, sharing permission mutation, account billing, or agent project mutations.

### Home

Owns conversation/project listing, home search, inbox grouping, setup/home launch cards, orchestration surface, and open-chat intents.

Home must call conversation/project stores through narrow read models. It should not read full `ChatStore`.

### Projects

Owns project CRUD, project instructions, memory, links, notes, selected-project read model, and project membership.

Project persistence belongs here or in `Core/Persistence`, not in chat.

### Files

Owns local attachments, remote files, previews, upload limits, project file attach, and prompt file attach.

File upload and preview calls go through `FileAPI`.

### Sharing

Owns public links, direct shares, org shares, groups, shared-with-me, shared preview, and share permission copy.

Sharing should be first full extraction because boundary is obvious and risk is contained.

### Model Catalog

Owns route model lists, picker sections, pinned models, council selection, plan locks, and provider display metadata.

Route readiness rules may live in `Core/Routing`; picker-specific grouping stays in feature.

### Security

Owns attestation display, proof capsule, proof education copy, freshness, coverage, and diagnostics entry.

Never say verified when only attestation exists.

### Setup

Owns setup plan, starter presets, restore planner, use-case selection, and first-run recommendations.

Setup model/planner code needs split before new setup behavior lands.

### Agent

Owns phone-safe runtime UI, hosted handoff, approval/credential gates, tool previews, and agent workspace.

Agent project/file mutation must happen through Project/File services, not direct array mutation.

### Account

Owns billing, settings, imports, integrations, diagnostics entry, and auth-linked account actions.

## View Rules

SwiftUI files over 300 lines need scrutiny. Files over 1000 lines are architecture debt unless there is a strong reason.

Rules:

- one component per file when component has its own behavior or preview value
- keep large bodies as stable view trees
- prefer dedicated subview types over many computed `some View` fragments
- move side effects out of `body`
- pass explicit inputs/actions into subviews
- avoid `EnvironmentObject ChatStore` in new views
- no view talks directly to API or persistence

## Test Architecture

Current test file is also a god object. Split by ownership as seams are extracted.

Target:

```txt
NEARPrivateChatTests/
  Auth/
  API/
  Routing/
  Streaming/
  Chat/
  Home/
  Projects/
  Files/
  Sharing/
  Setup/
  Security/
  Agent/
  Export/
```

Each feature extraction must move or add tests beside the new owner.

## Refactor Gates

Every phase must satisfy:

- behavior preserved
- new Swift files added to Xcode project target membership
- no new mega-store
- no new catch-all helper
- no new feature logic in `ChatStore` unless it is temporary glue being deleted in same phase
- docs updated when ownership changes
- focused tests for moved pure/service behavior

Build/test level depends on risk:

- docs only: no build needed
- file moves/new Swift files: simulator build
- service/store extraction: focused tests plus simulator build
- streaming/auth/security: focused tests, simulator build, simulator smoke when feasible

## End State

`ChatStore` should either disappear or become a small compatibility object under 300 lines while old views are replaced. Acceptable final jobs:

- expose selected conversation bridge during transition
- forward narrow chat actions to `ChatFeatureStore`
- coordinate app-wide reset until app state is split

Everything else needs a real owner.
