# NEAR Private Chat iOS - Code Audit and Remediation Pass

Date: 2026-05-25  
Scope: non-legal app runtime, chat state, model routing, IronClaw readiness, persistence, safety checks, and test coverage.  
Explicitly excluded to avoid conflict with the parallel "create ios private chat app" thread: `TERMS_AND_CONDITIONS.md`, `AuthView.swift`, legal gating in `NEARPrivateChatApp.swift`, and `LegalTerms` definitions in `Models.swift`.

## Verification Run

- `xcodebuild analyze` on `NEARPrivateChat` succeeded.
- `xcodebuild test` on iPhone 17 Pro simulator succeeded after remediation.
- Static sweep covered Swift source size, force casts/unwraps, local storage, file IO, URL/auth/token handling, task detachment, and dangerous placeholders.

## Remediated Findings

### P0 - Single-model selection could preserve a stale Council lineup

Selecting a normal model after using LLM Council could keep extra Council model IDs in memory. That made the header and routing semantics disagree with the user's visible selection.

Fix:

- `ChatStore.selectModel(_:)` now resets the Council lineup to exactly the selected model when it is Council-eligible, or clears it for non-Council models.
- Added `testSelectingSingleModelClearsExistingCouncilLineup`.

### P0 - Hosted IronClaw could look ready while disabled

The hosted IronClaw route treated a valid endpoint as usable even when the Hosted Agent toggle was off. This could let the UI imply readiness while send-time behavior failed later.

Fix:

- Route readiness now uses `ironclawRemoteWorkstationAvailable`, which requires both enabled settings and a usable hosted endpoint.
- Send-time hosted IronClaw streaming now rejects disabled settings with a direct recovery message.
- Added `testHostedIronclawDisabledEndpointBlocksSend`.

### P1 - Empty chat copy conflated Hosted IronClaw and Mobile IronClaw

The empty chat hero checked only the provider name, so hosted and mobile agent states could show the wrong readiness copy.

Fix:

- Empty-state copy now branches on `isIronclawHostedModel` vs. `isIronclawMobileRuntime`.

### P1 - IronClaw Mobile pin/archive tools were local-only

The mobile agent's pin/archive tool calls mutated local UI state without calling backend pin/archive endpoints. A refresh could erase the user's apparent agent action.

Fix:

- `conversationPinSet` now calls `pinConversation` / `unpinConversation`, then refreshes conversations.
- `conversationArchiveSet` now calls `archiveConversation` / `unarchiveConversation`, then refreshes conversations.
- Failures are returned as failed tool results rather than optimistic success.

### P2 - Model metadata rendering had brittle force unwraps/cast

Model display and picker description paths used force unwraps after optional checks. They were probably safe under ideal payloads, but the model list is an external payload and should not get crash-shaped affordances.

Fix:

- `ModelOption.displayName` now uses sanitized optional display names.
- `ModelPickerRow` now uses a safe `modelDescription` fallback.
- Empty-response API handling removed the forced generic cast path.

## Residual Risks

### R1 - `ChatStore.swift` and `AppShellView.swift` are still too large

Current sizes are roughly 7.9k and 11.3k lines. This makes SwiftUI invalidation, state ownership, and regression review harder than necessary.

Recommended next pass:

- Split route readiness, IronClaw tool execution, and Council orchestration out of `ChatStore`.
- Split model picker, project context, chat thread, setup, and account settings out of `AppShellView`.

### R2 - File-backed cache/storage still uses synchronous local IO in some paths

Most large import/file upload paths are already detached, but cache migrations and small persistence helpers still perform synchronous reads/writes from actor-bound code.

Recommended next pass:

- Move file-backed cache load/save/migration to a small storage actor.
- Add tests for corrupt cache recovery and account-scoped migration.

### R3 - No UI automation coverage yet for the design-critical screens

Unit tests cover routing, parsing, attestation copy, telemetry privacy, setup state, imports, and URL safety. They do not yet screenshot-check home, composer, model picker, agent, project context, or attestation.

Recommended next pass:

- Add a deterministic screenshot seed mode for `Home`, `Composer`, `ModelPicker`, `Agent`, `ProjectContext`, `Security`, and `Share`.
- Assert minimum tap-target sizes and Dynamic Type behavior on the most fragile cards.

### R4 - App Intents metadata is currently absent

The build logs show metadata extraction skipped because there is no AppIntents dependency. This matches the product roadmap gap: `Start verified chat`, `Ask NEAR Private about selected text`, and `Open shared link in NEAR` are still missing.

### R5 - Legal/product policy surface was intentionally not touched

Legal terms tests still pass, but this pass did not edit legal files because the parallel thread is actively updating that surface.

## Recommended Next Work Packets

1. Extract `RouteReadinessService` and `IronclawToolExecutor` from `ChatStore`.
2. Add seeded UI screenshot tests for the main design surfaces.
3. Add App Intents for verified chat, selected-text ask, and shared-link open.
4. Move cache persistence to a storage actor with corrupt-file recovery tests.
5. After the legal thread lands, re-run the full suite and reconcile any legal/setup copy changes.
