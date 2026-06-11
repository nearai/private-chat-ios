# NEAR Private Chat iOS — Build-Out Plan v2 (current-state)

Supersedes `BUILDOUT-PLAN.md`. Reflects the **current working tree** (build 9 + a large uncommitted change set in which a code agent executed ~75% of v1). Audited file-by-file on 2026-06-11; the tree **builds clean** (`** BUILD SUCCEEDED **`, all 22 new files registered in pbxproj, no `try!`/`fatalError`/`URL(string:)!`/`print()` in non-test code).

**Read this first — current status of the v1 phases:**

| v1 Phase | Status now | What's left |
|---|---|---|
| 1 Documents reach every route | ✅ done | 1 integration test (sentinel across 4 routes) |
| 2 Kill truncation | ✅ done | — |
| 3 Search & sources | ✅ done | 2 integration tests; check full-length snippet layout |
| 4 Council reliability | ✅ done | simulator verification; tests present |
| 5 Agent reborn robustness | ✅ done (SSE skipped) | 2 tests; optional SSE |
| 6 Auth & onboarding clarity | ✅ done | — |
| 7 Composer & picker clarity | ✅ done | manual smoke |
| 8 Design system & a11y | 🟡 partial | Dynamic Type, radius tokens, 44pt targets |
| 9 Code quality | 🟡 partial | ChatStore still 6997 lines; deinit; 3 test suites |

**The single most important fact:** all of the above is **uncommitted and not yet run through the test suite** — the test runner is blocked by a machine-level CoreSimulator PTY fault (`Pseudo Terminal Setup Error`) that a Mac restart clears. So the v2 work is: **verify → commit → finish design/a11y + code-quality tail → ship.**

The remaining work is reorganized into phases A–F below, in execution order. Phases C and D are independent and can run in parallel worktrees after A.

---

## PROJECT CONTEXT (prepend to every Codex phase prompt)

```
Repo: /Users/abhishekvaidyanathan/Documents/Playground/NEARPrivateChatIOS — SwiftUI iOS 17 app "NEAR Private Chat".

BUILD / TEST (from repo root):
- Build: xcodebuild -project NEARPrivateChat.xcodeproj -scheme NEARPrivateChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DD CODE_SIGNING_ALLOWED=NO build
- Unit:  same with `-only-testing:NEARPrivateChatTests test` (NOT the UI test target — its runner is flaky headless). If you hit "Pseudo Terminal Setup Error", the machine's CoreSimulator is wedged: `killall -9 com.apple.CoreSimulator.CoreSimulatorService Simulator; xcrun simctl shutdown all` and retry, or restart the Mac.
- Lint pbxproj after adding files: plutil -lint NEARPrivateChat.xcodeproj/project.pbxproj

HARD CONSTRAINTS:
1. NO synchronized groups. Register every NEW .swift with: python3 scripts/pbxproj-add.py <relative/path> <SiblingInSameDir.swift>; then plutil -lint.
2. RULES.md: App/ wires lifecycle; Core/ owns infra; Features/ own product behavior; Shared/ generic UI only. ChatStore is legacy debt — extract OUT of it, never add to it; target trajectory <1500 lines. Split files >~500 lines by owner.
3. No try!/as!/fatalError/URL(string:)!/print() in non-test code. (Currently clean — keep it clean.)
4. Agent route HTTPS-only. No secrets in code. Match surrounding style + doc-comment voice (state the constraint, not narration).

ALREADY DONE (v1 phases 1–7, mostly 8–9) — verify, do NOT redo:
- Login (WebSignInView WKWebView harvest; native NEP-413 with timestamp nonce; Release token paste; SessionStore.adoptSession). ConnectionDiagnostics; RouteHealthMonitor auth-vs-ratelimit.
- Documents now reach every route (cloud, briefing/tracker proxy, IronClaw Mobile, Hosted) via documentAugmentedPrompt injection + !isLocalOnly gating; staged text persists in DraftPersistence.
- No truncation: StreamingPreviewHelper (no 4000/12-line cap), full snippets, wide-table wrapping, widget lineLimit(2).
- Search: model-native vs app-side grounding mutually exclusive; SearchMode intent; council source provenance.
- Council: per-leg sources, errorKind classification (CouncilStreamService.errorKind(forFailureSummary:)), lineup pruning vs catalog, inline synthesis retry + dedup.
- Agent reborn: bounded retry + retryClassification + IronclawHTTPStatusError; timeline limit 100/250; gate detail; endpoint placeholder.
- Auth UX (provider hierarchy, terms gate, error recovery, accessibility) + composer/model-picker route clarity (session-config summary card, route-requirement headers, readiness-aware starters, agent breadcrumb).
- Code-quality splits landed: LiveDataService→QuickIntent*/LiveCoinsData/LiveNewsRSSParser; MarkdownRenderingViews→MarkdownBlockParser (now 739); SecurityView→SecurityProofParsing (842); ShareViews→ShareGrantModels (869); ModelPickerView→ModelPickerRows (747); ChatMemoryStores; MessageWidget*Models; ErrorMessageMapper. Unsafe code removed.

LIVE CONTRACTS: private.near.ai Bearer header, base /v1, web token in localStorage sessionToken/sessionId. Reborn agent at https://dangwalvaidy.family/reborn (Caddy strips /reborn → :3000), Bearer IRONCLAW_REBORN_WEBUI_TOKEN, /api/webchat/v2/* with client_action_id idempotency keys.

WORKING STYLE: after each phase, build + `-only-testing:NEARPrivateChatTests`; add the listed tests; do not regress; commit per phase.
```

### Codex run recipe (per phase)
```sh
cd /Users/abhishekvaidyanathan/Documents/Playground/NEARPrivateChatIOS
git worktree add ../npc-pX -b pX/<slug> HEAD     # HEAD = current state incl. the uncommitted work once committed (see Phase A)
cat > /tmp/pX.txt <<'EOF'
<PROJECT CONTEXT block> + <Phase section>
EOF
codex exec -C ../npc-pX --skip-git-repo-check -s workspace-write -c service_tier=fast -c model_reasoning_effort="high" -c approval_policy="never" - < /tmp/pX.txt
```

---

## PHASE A — Stabilize, verify, and commit the change set (do first; blocks everything)

**Objective.** Get the 107-file uncommitted change set test-green and committed in coherent commits so later phases build on a stable base. Right now it is unverified by tests and a single `git checkout` would destroy it.

**Steps.**
1. **Clear the test runner.** `killall -9 com.apple.CoreSimulator.CoreSimulatorService Simulator; xcrun simctl shutdown all; xcrun simctl erase "iPhone 17 Pro"` — or restart the Mac. Then boot the sim.
2. **Run the full unit suite:** `-only-testing:NEARPrivateChatTests test`. Expect new suites the refactor added (AgentTests, AuthTests, CouncilTests, StreamingTests, FileTests). Fix every failure — the refactor moved many symbols, so the likeliest failures are tests referencing moved types (update imports/call sites), not logic.
3. **Static re-verify** (cheap, sim-independent): `grep -rn "try!\|fatalError(\|URL(string:[^)]*)!\| print(" NEARPrivateChat/ --include=*.swift | grep -v Tests` returns nothing; `plutil -lint` the pbxproj; confirm all 22 new files have 4 pbxproj refs each.
4. **Commit in logical chunks** (not one mega-commit): one commit per v1 phase area where the diff is separable — (a) documents-every-route, (b) truncation, (c) search/sources, (d) council, (e) agent reborn robustness, (f) auth/composer UX, (g) code-quality splits + ErrorMessageMapper. Each commit message names the v1 phase it lands. Co-author trailer: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`. Push to `main`.
5. **Bump to build 10**, archive (`xcodebuild archive … CODE_SIGNING_ALLOWED=NO -archivePath build/Archives/NEARPrivateChat-<date>-b10-unsigned.xcarchive`). This is the testable artifact for the device matrix.

**Acceptance.** Full unit suite green; `main` contains the work in reviewable commits; build 10 archived.

---

## PHASE B — Close the test-coverage gaps the refactor left (Functionality assurance)

**Objective.** The implementations landed but several plan-mandated tests did not. Add them so the functional fixes are regression-protected.

**Files.** `NEARPrivateChatTests/Files/FileTests.swift`, `NEARPrivateChatTests/Agent/AgentTests.swift`, `NEARPrivateChatTests/Streaming/StreamingTests.swift`, `NEARPrivateChatTests/Chat/`, new `NEARPrivateChatTests/Conversations/ConversationStoreTests.swift`, `NEARPrivateChatTests/Sharing/ShareStoreTests.swift`, `NEARPrivateChatTests/Files/FileStoreTests.swift`.

**Steps.**
1. **Cross-route document sentinel** (Phase 1 acceptance, currently untested). Stage a doc with a sentinel string; assert the prompt-building path injects the excerpt for: private (`documentAugmentedPrompt`), NEAR Cloud (`streamNearCloudModel`/`nearCloudPrompt`), briefing/tracker (`cloudBriefingText`), and IronClaw Mobile (`streamIronclawMobileRuntime`/`normalizedIronclawPrompt`). Assert local-only docs are **excluded** from cloud + hosted prompts. Test at the prompt-builder level (no network).
2. **Hosted local-only filtering.** Assert `hostedIronclawContextSection` includes only uploaded `pdf_text`/`table_text` excerpts (capped 2k, "untrusted" framing) and emits the "omitted local-only" note.
3. **Agent conversation-mismatch discard** (Phase 5, IronclawAPI/ChatStore). Apply a stream event whose `conversationID != selectedConversation.id`; assert it is discarded (not appended to the timeline).
4. **Agent `deferred_busy` mapping.** Assert `IronclawSubmitResponse.resolvedRunID` returns `active_run_id` for a `deferred_busy` outcome.
5. **Search exclusivity.** Send with a native-web-tool model + a web-benefiting prompt; assert app-side `webContext == nil` (no double search).
6. **Council source dedup + provenance.** Assert `uniqueSources` dedupes by URL and the per-source model attribution is correct.
7. **New store suites** (also Phase 9 step 6): `ConversationStoreTests` (refresh/select/delete/mutation, **fix the force-unwrap path** — see Phase D), `ShareStoreTests` (grant create/validate/revoke/persist), `FileStoreTests` (cache hit/miss/invalidation). Use mock repositories.

**Acceptance.** All new tests green; the four-route document path, agent edge cases, and the three refactored stores are covered.

---

## PHASE C — Finish design system & accessibility (Design; parallelizable)

**Objective.** Complete v1 Phase 8 — it's the least-finished area. Premium dark-mode consistency + Dynamic Type + touch targets.

**Files.** `Core/DesignSystem/DesignTokens.swift`, `Shared/Components/PrimaryButton.swift`, `Features/Auth/AuthView.swift`, `Features/Security/SecurityView.swift`, and the broad set of views using hardcoded `cornerRadius(...)` / fixed fonts.

**Steps.**
1. **Dynamic Type adoption.** Only ~2 dynamic-type references exist app-wide; no `@ScaledMetric`. Migrate fixed `.font(.system(size:))` / hardcoded point sizes in shared components to system-relative text styles; add `@ScaledMetric` for pixel-load-bearing sizes (badge/avatar heights). Verify `caption2` proof/detail rows are legible at Accessibility-XL.
2. **Touch targets.** Fix `AuthView.swift:136` `.frame(height: 42)` → ≥44pt; grep for other <44pt interactive frames (e.g. `HomeSidebar` 40pt) and lift primary controls to 44pt. Add a `.minimumTouchTarget()` modifier.
3. **Radius tokenization.** Replace scattered literal `cornerRadius(7/8/12/13/14/16/24)` with `AppRadius.pill/control/card` by context (dense rows 8, feature cards 12, presentation 16). Add a `featureCard` style modifier to enforce it.
4. **Proof-copy polish.** `SecurityView.swift:694` still surfaces the raw nonce in the on-device check message — keep it out of the primary summary and soften the detail copy. Confirm model-coverage copy only claims a hash when `modelHashPreview` exists.
5. **PrimaryButton disabled state.** Add explicit disabled foreground + `allowsHitTesting(isEnabled)`; optional failure haptic on disabled tap.
6. **Contrast tests.** Expand `DesignTokenContrastTests` to cover white-on-`actionPrimary` and disabled-text contrast.

**Acceptance.** App legible/operable at Accessibility-XL; no literal corner radii in shared components; no interactive control under 44pt; contrast tests pass. Manual pass at 393pt + Accessibility-XL + dark mode.

---

## PHASE D — Code-quality tail (Code quality; parallelizable, but coordinate ChatStore edits)

**Objective.** Finish v1 Phase 9. The big-file splits landed; the remaining debt is **ChatStore (6997 lines — it grew)** plus lifecycle cleanup.

**Files.** `App/State/ChatStore.swift`, `Features/Chat/LiveDataService.swift`, `App/State/AgentActivityController.swift`, `Core/Streaming/IronclawMobileRuntime.swift`, `Core/Services/WebGroundingService.swift`.

**Steps.**
1. **ChatStore deinit/cleanup.** No `deinit` exists. Add one (or wire into account-reset) that calls `cancel()`/`stop()` on `AgentActivityController`, `IronclawMobileRuntime`, `WebGroundingService` (there is a `cancelBackgroundOwners` already — call it from `deinit`). Add the missing `cancel()`/`stop()` methods to each service (invalidate timers, cancel tasks).
2. **ChatStore reduction.** Drive 6997 → <1500 by extracting cohesive domains into owners with temporary forwarding, then deleting the forwarding once callers use the owner directly: do **conversation-session**, **draft-scope**, and **memory** domains (send-pipeline already lives in ChatSendCoordinator). Each extraction is a 2-pass refactor (extract+test, then update callers). Register every new file via `scripts/pbxproj-add.py`. This is the largest single item — it can be its own multi-commit sub-project; each extraction must keep the build + suite green.
3. **Confirm no file >900 lines except ChatStore.** Current offenders to watch after edits: `ModelCatalogStore` (1251 — candidate for a follow-up split), `IronclawAPI` (1031), `AgentModels` (864), `ProjectStore` (859).

**Acceptance.** ChatStore trending down with each commit (target <1500); `deinit` cancels background owners; no new file over ~900 lines; suite green.

---

## PHASE E — Optional robustness & polish

1. **Agent SSE (optional, flagged).** Add `streamRunViaSSE()` using a line-buffered `URLSession.bytes` reader against `/threads/{id}/events?token=…`, mapping `type`-tagged frames (accepted/running/final_reply/gate/auth_required/failed/cancelled) to `ResponseStreamEvent`; keep polling as the fallback behind a feature flag. Removes the 2s poll latency.
2. **Snippet layout check.** `snippetPreview` now returns the full stored snippet (≤600). Verify `SourceCarousel` cards and the detail sheet lay out cleanly with long snippets (they should wrap, not push width); adjust card height if needed.
3. **Composer summary smoke.** Manually verify the session-config summary card appears/clears correctly as Council toggles, sources change, a Cloud key is added, and the Agent URL changes.
4. **News diversity follow-up.** If QA still sees mostly `news.google.com`, add a second news backend or merge more DuckDuckGo general results when `preferNews` is true (the dual-backend + ranking exist; this is a weighting tweak).

---

## PHASE F — Ship gate

1. Full unit suite green (after the Phase A reboot).
2. Device matrix (build 10): sign in via each method → private send → cloud send → council 3× → **PDF "summarize" on every route → references content, not filename** → tracker run → agent send via `https://dangwalvaidy.family/reborn` → switch chats mid-stream → relaunch (persistence holds, including staged doc text).
3. Visual pass at 393pt + Accessibility-XL + dark mode.
4. Bump build, archive, upload (Xcode GUI session or ASC API key).

---

## Execution order & ownership

1. **Phase A** now — nothing else is safe until the change set is tested and committed.
2. Then **B**, **C**, **D** in parallel worktrees (B = tests, C = design, D = code-quality). D's ChatStore edits and B's new store tests touch adjacent code — land D's extractions first or rebase B's store tests onto them.
3. **E** opportunistic. **F** before each TestFlight upload.

The functional product is effectively built and building clean; the work that remains is **proving it (A, B), polishing it (C), and paying down the last of the debt (D).**
