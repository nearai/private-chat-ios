# Rules

Small rules for building this repo back into solid architecture.

## Main Rule

Every change must answer:

> Which owner does this belong to?

If answer is `ChatStore`, stop. Pick real owner or create one.

## Ownership

- `App/` wires dependencies, lifecycle, root navigation, account reset.
- `Core/` owns cross-feature infrastructure: API plumbing, persistence primitives, routing, streaming, security, telemetry, export.
- `Features/` own product behavior, feature stores, feature services, feature views.
- `Shared/` owns generic UI/utilities only.

No feature imports another feature's internals. Cross-feature work uses narrow protocols, read models, or app-level coordination.

## `ChatStore`

`ChatStore` is legacy compatibility debt.

- Do not add new feature behavior to it.
- Only add temporary forwarding when same phase deletes/moves real logic.
- Move state out by domain: sharing, files, projects, conversations, send pipeline, agent, account, security.
- End target: deleted or under 300 lines.

## Stores

Stores may:

- hold observable feature state
- expose user actions
- call services
- translate service results into state

Stores must not:

- build raw HTTP requests
- create storage keys or filenames
- mutate unrelated feature state
- contain SwiftUI layout
- become global catch-all state

## Services

Services own business behavior and async orchestration.

- API service calls go through protocol-backed clients.
- Persistence goes through adapters.
- Streaming goes through streaming services.
- Prompt/send orchestration goes through a coordinator, not a view.

## Views

Views render state and emit actions.

- No direct API calls.
- No direct persistence.
- No prompt assembly.
- No stream mutation.
- No full `ChatStore` dependency in new views.
- Prefer explicit values/actions over passing giant stores.

SwiftUI files:

- over 300 lines: inspect for split
- over 500 lines: split unless strong reason
- over 1000 lines: architecture failure

One component per file when component has its own behavior, state, or preview value.

## API

Do not grow one mega-client.

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

Feature services depend on protocols, not concrete mega-client.

## Persistence

No inline storage keys in features.

Use adapters for:

- session
- settings
- conversations
- messages
- projects
- drafts
- files
- agent threads

Adapters own account scoping, migrations, filenames, defaults keys, keychain account names, and serialization.

## Routing

Use enum-driven routing and sheets.

`AppRouter` owns app navigation. Feature-local sheets may stay local only when they do not cross feature boundaries.

Deep links convert to route/actions in routing layer, not inside random views.

## Streaming

Streaming flow:

```txt
ChatFeatureStore
  -> ChatSendCoordinator
  -> RoutePlanner
  -> MessageStreamService / CouncilStreamService / AgentRuntimeService
  -> MessageTimelineStore
```

No UI file directly applies stream events.

## Tests

Tests follow owners.

- API tests in API group
- routing tests in Routing group
- streaming tests in Streaming group
- feature tests in feature group
- helpers in test support files

No new test god file. Split before adding broad coverage.

## Xcode

This repo uses manual Xcode project membership.

Every new Swift file must be added to:

- `PBXFileReference`
- `PBXGroup`
- `PBXSourcesBuildPhase`

Confirm target membership before build/test.

## Phase Discipline

Refactor by responsibility, not by random cleanup.

Good phase:

- one owner clarified
- one responsibility leaves wrong owner
- tests move or appear near new owner
- behavior preserved
- docs updated when ownership changes

Bad phase:

- code moves but same concepts remain tangled
- new wrapper hides same god object
- new optional/cast-heavy contract papers over unclear state
- feature branch added to shared/core code

## Build Discipline

- Docs-only: no build.
- Tiny copy/style change: no build if risk is truly tiny.
- New Swift files or project membership change: simulator build.
- Store/service/API extraction: focused tests plus simulator build.
- Auth/security/streaming changes: focused tests, simulator build, smoke when feasible.

## Review Bar

Block changes that:

- grow `ChatStore`
- push app Swift file over 1000 lines
- add feature logic to shared/core path
- add persistence keys outside adapters
- add API methods without domain protocol
- pass giant stores into small subviews
- move complexity without deleting ownership confusion

Preferred move: delete wrong ownership and give behavior one canonical home.
