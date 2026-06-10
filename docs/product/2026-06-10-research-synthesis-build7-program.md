# Research Synthesis → Build 7 Program

Date: 2026-06-10
Corpus digested: the June-1 design program (`research/near-private-chat-ios-{program,gaps-and-design-tests,grounded-redo,hostile-review-grounded,soul-md-and-formatting,state-and-autonomous-pass}-2026-06-01.md`, `copy-design-ux-audit`, `core-feature-profile`, `hostile-review-grounded-both-apps`, `soul-md-design-hostile-review`), the claude-design kit (`near-private-chat/claude-design/` — product spine, anti-patterns, competitor precedents, design tokens, onboarding, handoff contracts, 89 competitor captures), and the copy audits. Every directive was mapped against the post-build-6 codebase; the claims below were re-verified against today's code, not taken on faith from June 1.

## The one-paragraph verdict

The research converges on a diagnosis the build-6 overhaul did not touch: the app's problem is ~75% positioning and trust-copy, ~25% capability. The engine is a competent general assistant; the surfaces dress it as a crypto product, the trust UI overclaims ("ready" states, reused proof), and the few real capability gaps versus ChatGPT/Gemini/Perplexity are specific: export fidelity (exports exist but degrade tables/lists/code to flat text), native vision, math rendering, and a personalization layer. The kit's product spine is unambiguous: **Ask → Answer → Sources → Proof → Model → Council → Projects → Power Tools**, golden path under 20 seconds, "Ask privately." as the composer promise, and one canonical verification sentence: *"Checked on this device against signed proof from TEE-supported infrastructure."*

## Status of the research corpus (verified 2026-06-10)

### Already satisfied (by build 5/6 or interim work — do not redo)
- Ship-gates: legal entity + contact filled (`AuthModels.swift:244`), `PrivacyInfo.xcprivacy` present, acknowledgments real.
- Dead verified-proof ternary (`coverage == .covered ? .verified : .verified`) — fixed; the `.valid` case now switches on real coverage.
- Auth screen positioning — copy is already the research's prescription ("write, code, research, summarize files…", not ETH).
- Table cell hard-clipping, raw-markdown streaming, source-carousel bleed, council persistence, tracker failure visibility/backoff, chat-switch blocking, council picker latency, PDF text loss (all build 6).
- UI-automation target — ReleaseGate live harness + markdownGallery layout gates (the research demanded this as gap #3; snapshot-image comparison remains a possible extension).
- Per-answer export EXISTS (context menu + inline actions) — the June-1 "no per-answer export" finding is stale; what remains is fidelity (below).

### Stale or superseded directives (do not adopt as written)
- "Purge speculative model names (Claude Opus 4.7, Qwen 3.7 Max)" — these are now real models served by the backend (June 10 screenshots). The live directive is narrower: don't ship hardcoded fallback CATALOGS that drift (`ModelCatalogStore.preferredModelIDs`); prefer API-returned IDs with generic fallbacks.
- "No UI-test target exists" — exists now; redirect energy to snapshot baselines.
- Wave-0 "repo stabilization / revert resolution" — moot; main is green and shipped.

### Open and adopted — the Build 7 program

**Lane 1 — Trust honesty (P0, mostly small diffs)**
1. Per-message proof provenance: stop rendering today's global `attestationSnapshot` under old answers; capture route/proof state at generation time on the message (`ChatMessageViews.swift:384` area, `ChatMessage.trustMetadata` already exists — extend to non-metadata messages).
2. Canonical verification copy sweep: adopt the kit's exact sentence; replace "Attestation refreshed." banner and the widget "Attestation" row label ("verification"/"proof"); honor the banned-word list (TEE/attestation/enclave/route/endpoint never in primary copy). Reconcile build-6's "No proof"/"Get proof" badges with the kit's "Verifying… / Verification failed" vocabulary.
3. Kill remaining static "ready" overclaims in Account/Capabilities ("Phone Agent ready" etc. when unverified) — claims must be backed by checked state.

**Lane 2 — Prompt/PII hardening (P0, security-grade)**
4. System-prompt injection: the user system prompt is concatenated raw ("User system preference:") on all three routes (`MessageAPI.swift:294`, `ChatStore.swift:5632`, `IronclawMobileRuntime.swift:172`) — no cap, no fencing, no precedence. Add length cap, delimiter-escaping, and a fixed precedence contract (base contract → user prefs → format contract), per the soul-md spec.
5. PII route-gating: identity-bearing context (memory identity, soul Identity section) injects on the private route only; cloud/hosted get intent+voice+format only, with per-route opt-in.

**Lane 3 — Render == Export invariant (P0, the biggest remaining parity fail)**
6. Replace the line-by-line PDF/DOCX converters (`ConversationExport.swift` `pdfLineText` path) with export driven by the same markdown AST that renders on screen: tables stay tables, lists keep nesting, code keeps monospace. Add `.md` export. ReleaseGate scenario: export an answer with table+nested list+code, assert structure survives.

**Lane 4 — soul.md personalization (the research's flagship net-new feature)**
7. Local `soul.md` (Identity / Intent / Voice & Format / Rules) parsed into `activeSystemPrompt` with the Lane-2 precedence and privacy gating; authoring surface in Settings (relocate the buried system-prompt field); optional onboarding capture; format contract pinning the renderable/exportable markdown subset. Verification tests per the spec (profile reaches model on every route; identity absent on cloud unless opted in; voice measurably changes output).

**Lane 5 — Product spine & IA alignment (P1)**
8. Composer: placeholder "Ask privately."; model chip always shows version; Council remains a separate chip (never in the model list — already true; lock with a test).
9. Council answer view: adopt the Perplexity-precedent tabs (Synthesis | per-model | Sources) with Agreement/Disagreement/Next-step chips, replacing the progress-rows + preview stack after streaming settles. No "why synthesis is better" copy.
10. Pre-login surface: keep live-data, but lead with general capability; crypto becomes one example chip among several (the auth copy already conforms; the pre-login starter chips do not).
11. Home: one dominant primary action; Shared/Archived as persistent affordance; mode banner (pre-login live-data vs private vs cloud/agent) — design-test DT-1/DT-3/DT-4 from the gaps file become ReleaseGate assertions.

**Lane 6 — Design-system mechanical pass (P1, high-volume/low-risk)**
12. WCAG-AA: blue-on-light text → `#005EA5`; darken proofVerified/proofStale for text use (current 2.0–3.3:1 failures).
13. Tokens: add radius (8/12/16/22 continuous) + 4pt spacing scale to `DesignTokens.swift`; collapse the 14 ad-hoc radii.
14. `brandBlue` → semantic `actionPrimary` sweep (~150 raw uses); single `PrimaryButton` component.
15. Dynamic Type: migrate fixed `.font(.system(size:))` on scalable text; 44pt tap-target audit (empty-chat chips, message actions, home icons).

**Lane 7 — Remaining parity (P2 / backend-dependent)**
16. Math rendering (KaTeX-equivalent) — render + export.
17. Native vision input (send images as vision, not OCR-text proxy) — partially landed via FileAPI vision uploads; verify end-to-end and close the OCR-only fallbacks.
18. Native NEP-413 signing (drop the `demo-ed25519-signature` placeholder), offline message-history cache expansion, ChatStore decomposition (`RouteReadinessService`, `IronclawToolExecutor`), iPad drag/drop, audio/connectors (backend-blocked).

## Sequencing recommendation

Build 7 = Lanes 1–4 (trust honesty, prompt/PII hardening, render==export, soul.md) + Lane 6's contrast fix — these are the research's P0s, none need backend changes, and ReleaseGate can gate all of them. Lane 5 (spine/IA, council tabs) is build 8 with the design-kit workflow (Claude Design per-surface passes per `07-workflow-guide.md`). Lane 6 mechanical sweeps interleave anywhere; Lane 7 rides behind.

## Standing rules now binding on all future UI work (from the kit)

- Anti-pattern list (`03-anti-patterns.md`) and banned-word list apply to every PR touching UI/copy.
- One accent per screen; per-message proof footer, never a global banner; no chip soup; primary actions bottom-third; `.continuous` radii; SF Pro only.
- The DT-1…DT-7 design-test battery re-runs whenever a top surface or routing/source model changes (DT-1/3/4/6 are release-blocking).
- New surfaces follow the SwiftUI handoff contract: improve named existing views in place; iOS 26 APIs always behind `#available` with iOS 17 fallbacks; colors only via tokens.
