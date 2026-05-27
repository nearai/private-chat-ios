# Handoff: ChatStore Service Split

## Focus

Pick up after the structural cleanup. The repo now has feature folders, shared design primitives, a small app shell, and domain model files. The next meaningful speed/reliability work is reducing `App/State/ChatStore.swift`.

Reference docs:

- `CONTEXT.md` for product terms.
- `docs/architecture/ARCHITECTURE.md` for target shape.
- `docs/architecture/PLAN.md` for phased migration status.

## Completed On 2026-05-26

Created or populated:

- `NEARPrivateChat/App/`
- `NEARPrivateChat/App/State/`
- `NEARPrivateChat/Core/API/`
- `NEARPrivateChat/Core/Auth/`
- `NEARPrivateChat/Core/DesignSystem/`
- `NEARPrivateChat/Core/Export/`
- `NEARPrivateChat/Core/Routing/`
- `NEARPrivateChat/Core/Security/`
- `NEARPrivateChat/Core/Services/`
- `NEARPrivateChat/Core/Streaming/`
- `NEARPrivateChat/Core/Telemetry/`
- `NEARPrivateChat/Features/*`
- `NEARPrivateChat/Shared/*`

Major reductions:

- `AppShellView.swift`: 1,248 lines -> 96 lines.
- `Models.swift`: removed from target and split into domain files.
- Root `NEARPrivateChat/` now mostly contains app resources and privacy metadata.

Validated:

- `xcodebuild build -project NEARPrivateChat.xcodeproj -scheme NEARPrivateChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`

## Current Hotspot

`NEARPrivateChat/App/State/ChatStore.swift` is still the main bottleneck. It remains a compatibility facade, but it currently owns too many responsibilities:

- conversation loading/cache
- message loading/cache
- streaming and cancellation
- Council fan-out/synthesis
- route readiness
- drafts and large paste persistence
- project CRUD/context
- file upload/preview
- sharing/public links/shared-with-me
- model selection/pinning
- billing/settings
- attestation fetch state
- IronClaw runtime/handoff state
- diagnostics and banners

## Next Phase

Start with services that are easy to test without rendering SwiftUI:

1. `Core/Streaming/MessageStreamService`
2. `Core/Streaming/CouncilStreamService`
3. `Core/Routing/RoutePlanner`
4. `Features/Chat/ComposerState`
5. `Features/Chat/MessageTimelineStore`
6. `Features/Sharing/ShareStore`
7. `Features/Projects/ProjectStore`

Keep `ChatStore` as a facade while extracting. Do not rewrite UI callers all at once.

## Guardrails

- Preserve behavior while moving code.
- Keep the app phone-first.
- Keep hosted API contracts unchanged.
- No DB migrations.
- No localhost app.
- Add every new Swift source to `NEARPrivateChat.xcodeproj/project.pbxproj`; this project does not use filesystem-synced groups.
- Build after Swift file/project changes.
- Treat `review-artifacts/live-sim-design-review-2026-05-25 2/` as unrelated/untracked unless explicitly asked.

## Suggested First Extraction

Extract route planning first if the goal is Council crash/latency work:

- Move route decision helpers and readiness issue generation from `ChatStore` to `Core/Routing/RoutePlanner`.
- Keep a thin forwarding method on `ChatStore`.
- Add unit tests for GLM default, Council selection, NEAR Cloud key absent, project context, web-needed prompts, and IronClaw unavailable.

Extract sharing first if the goal is correctness:

- Move share/public-link/shared-with-me mutation into `Features/Sharing/ShareStore`.
- Keep `ChatStore` publishing the same public properties until views are updated.

Do not start by splitting every `@Published` property. Start by moving behavior with clear inputs/outputs.
