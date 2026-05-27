# NEAR Private Chat iOS - Agentic-Default Implementation Tracker

Date: 2026-05-25
Status: implementation tracker updated after the explicit model/Council/Effort correction. This file tracks app reality, not just design intent.

Canonical spec: `NEARPrivateChatIOS-agentic-default-design-spec-2026-05-25.md`

## Tracking Rule

A change is **Done** only when code implements the behavior and a focused test, build, or fresh simulator check proves it. Docs alone do not count.

## Current State

The first agentic-default implementation pass is now in code:

- `AskOrchestrator` exists and decides route, tools, proof posture, and failure plan before send.
- First-run Setup is no longer presented; sign-in/legal terms lead to Home.
- Home has one `Ask NEAR` hero and the plain sentence `Ready to answer, research, or take action.`
- The composer no longer shows the permanent Auto/Web/Files/Research strip.
- The chat/composer now exposes explicit `Model`, `Council`, and `Effort` controls. Fresh installs still default to GLM (`zai-org/GLM-5.1-FP8`).
- The prompt classifier no longer silently switches a GLM/private prompt into Council or hosted IronClaw. Council and IronClaw are user-selected routes.
- NEAR Cloud can receive app-supplied web, project links, notes, attachment summaries, and extracted context. The old “Cloud cannot use web/project context” apology path is no longer the default contract.
- Agent entry moved toward inline behavior: `/agent` and menu actions select the agent route and prepare the draft rather than opening a default destination.
- GitHub sign-in uses the supported token callback flow by default instead of requesting PKCE code exchange that the app does not implement.
- Fresh Simulator launch captured after the correction at `live-app-review-2026-05-25-model-controls/01-launched-after-model-controls.png`.
- `Power Tools` is the disclosure home for Cloud key, hosted agent connection, diagnostics, advanced params, Web override, Large Paste override, and System Prompt.
- Proof UI now uses a canonical `ProofState` and assistant answer footer capsules instead of top/header proof chips.
- Consumer copy no longer uses `Legal attestation required`, `5 bullets`, `Find risks`, `Draft memo`, `Anonymized`, or top-level `No proof` language in active UI.

## Implementation Matrix

| ID | Requested Change | Status | Evidence / Acceptance |
| --- | --- | --- | --- |
| A1 | Ship `AskOrchestrator(prompt, project?, attachments?, history?) -> route/tools/proofPosture/failurePlan`. | Done | `NEARPrivateChat/AskOrchestrator.swift`; tests `testAskOrchestratorKeepsNearCloudWithProjectAndWebContextWhenKeyExists`, `testAskOrchestratorRequestsCloudKeyWithoutChangingSelectedRoute`, and `testAskOrchestratorOffersAgentAndCouncilWithoutChangingSelectedRoute`. |
| A2 | Kill apology-turn route failures at source without stealing user route choice. | Mostly Done | Cloud prompt/system copy now says the app supplies web/project context; missing keys/endpoints block pre-send with recovery. The orchestrator no longer silently switches GLM/private prompts into Council or IronClaw. Remaining risk: real API/runtime errors can still produce provider-side limitation text and should be monitored. |
| H1 | Home becomes one Ask NEAR card + sentence. | Done | `WorkspaceCommandHeader` renders one `Ask NEAR` CTA plus `Ready to answer, research, or take action.` No Agent/Project hero CTAs or setup launch card. |
| H2 | Keep search, Resume, projects, date groups, project colors/icons/context menus. | Done / Preserve | Existing Home structure preserved while the hero was simplified. |
| S1 | Delete Setup as a destination. Sign-in -> Terms -> Home. | Done | `RootView` no longer presents `UserSetupView`; setup state is recorded as defaults for new accounts. |
| S2 | Replace `Run Setup Again` with `Reset defaults`. | Done | Account action now resets interaction defaults instead of opening setup. |
| C1 | Composer default state is input + visible Model/Council/Effort + attachment + send/stop. | Done | `InputBar` removed the permanent focus row and added explicit model, Council, and reasoning-effort controls in the chat window. |
| C2 | Keep route recovery as inline card/chip only when needed. | Done | `RouteReadinessRecoveryCard` remains conditional on actual readiness issues. |
| C3 | Keep slash commands as power-user shortcuts. | Done | Slash tray preserved; `/agent` now selects agent route and fills the mission draft. |
| P1 | Canonical eight-state `ProofState` in code. | Done | `ProofState { unknown, verifying, verified, stale, mismatch, private_, proxied, unverified }` lives in `AttestationStatus.swift`. |
| P2 | Answer-footer proof capsule replaces fragmented header/message chips. | Done | `MessageBubble` renders `answerProofCapsule` under assistant responses; header proof chip was removed from compact toolbar. |
| P3 | Stop default UI from using engineering terms. | Mostly Done | Default Home/Composer/Chat now uses `Verified`, `Private`, `Privacy proxy`, `Cloud`, and `Agent`. Engineering terms remain intentionally in Security/Power Tools/legal detail areas. |
| PT1 | Keep `Power Tools`; put capabilities inside it. | Done | Top-level Capabilities section removed; `CapabilitiesEntryRow` lives inside Power Tools. |
| PT2 | Hide Web Search, Large Paste, System Prompt, diagnostics, Cloud key, hosted agent behind Power Tools. | Done | Account default is quieter; advanced controls are gated by `showsPowerTools`. |
| AG1 | Agent becomes inline behavior, not a top-level destination. | Mostly Done | Home no longer opens Agent as a hero destination; slash/menu agent actions prepare an agent route in-thread. Remaining risk: `AgentWorkspaceView` still exists as a detail/recovery surface. |
| AG2 | In-thread agent run card with progress, pause/stop, approvals. | Partial / Existing | Existing status strip and approval card are preserved. The richer last-three-steps card remains a follow-up. |
| CL1 | Cloud key recovery is just-in-time and preserves draft. | Done | Cloud sends are blocked only when key is missing; recovery card preserves the draft. |
| CL2 | NEAR Cloud has app-supplied web/project access. | Done | Source routing and Cloud prompt/system prompts now attach app grounding/context. Tests cover Cloud with web/project context and missing-key fallback. |
| M1 | Model selection remains explicit while GLM is the default. | Done | Compact chat toolbar and composer both expose model selection; `ChatStore.defaultModelID` remains `zai-org/GLM-5.1-FP8`. |
| M2 | Council is user-selectable from chat. | Done / Preserve | Composer has a visible Council control; existing recommended Council/customizer controls are preserved. Decision-shaped inline Council offer remains follow-up work. |
| M3 | Reasoning effort is adjustable from the chat window. | Done | Composer has an `Effort Auto/Low/Medium/High` menu backed by `ChatStore.setReasoningEffort`. |
| AU1 | GitHub sign-in works with current backend callback contract. | Done | `SessionStore.authenticate` uses token callback auth by default; test `testAuthURLUsesTokenCallbackByDefaultForProviderLogin` guards against accidental PKCE-only regression. |
| PC1 | Project Context trim: Sources / Instructions / Notes, no duplicate dead states. | Mostly Done | Add-link form moved to the top/add affordance path; Library explainer card removed; empty states now point to `+`. Link-row overflow consolidation remains follow-up. |
| CA1 | Council answer artifact component. | Not Done | Still rendered as model Markdown; keep as next product pass. |
| CA2 | Council thinking tray with per-model status and stop-waiting. | Existing / Preserve | Existing Council progress surfaces preserved. |
| D1 | Typography/design polish pass. | Partial | The worst setup-card path was removed from default flow. A full Dynamic Type and screenshot polish pass is still needed. |
| DS1 | Semantic color tokens replace direct brand-blue overload. | Partial | Current pass reduced default-surface clutter but did not complete token refactor. |
| QA1 | Fresh Simulator screenshots after implementation. | Done | Fresh launch screenshot captured at `review-artifacts/live-app-review-2026-05-25-model-controls/01-launched-after-model-controls.png`; GitHub button is visible on auth. |

## Remaining Next Pass

1. Capture the post-implementation simulator pack and update `latest-screenshot-index-2026-05-25.md`.
2. Convert Council synthesis from Markdown into a real component.
3. Upgrade the agent run surface into the full last-three-steps card with pause/resume.
4. Finish the visual-system pass: Dynamic Type, contrast, one primary blue per scene, and semantic tokens.
5. Consolidate remaining engineering-language in Security/Power Tools without weakening technical accuracy.

## Verifier Instructions

When Claude/Codex/another agent uses this tracker:

- Inspect the app code, not only docs.
- Treat Setup, capability-strip composer, top-level Capabilities, top proof chips, and Cloud context apologies as regressions.
- Do not treat visible Model, Council, or Effort controls as regressions. They are required.
- Do not let the orchestrator silently switch selected GLM/private chat into Council, hosted IronClaw, or Cloud.
- Keep `Power Tools` as the advanced disclosure name.
- Keep `Capabilities` as a row inside Power Tools only.
- Do not change `TERMS_AND_CONDITIONS.md` unless the product/legal thread explicitly asks for it.
