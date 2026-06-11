# NEAR Private Chat iOS — Build-Out Plan (Codex-executable)

Phased plan to take the app from "logs in, mostly works" to polished, correct, and maintainable. Grounded in a file:line audit of the live codebase (build 9). Each phase is self-contained: feed a phase's section to Codex with the **Project Context** block prepended.

Ordering is by user-visible impact, then dependency: **functionality the user reports as broken first**, then usability, design, and code quality. Phases 1–5 are functional fixes; 6–7 usability; 8 design; 9 code quality; 10 is the ship gate. Phases are independent enough to run in parallel git worktrees except where noted.

---

## PROJECT CONTEXT (prepend to every Codex phase prompt)

```
Repo: /Users/abhishekvaidyanathan/Documents/Playground/NEARPrivateChatIOS — SwiftUI iOS 17 app "NEAR Private Chat", backed by https://private.near.ai (OpenAI Responses API + SSE) and a hosted IronClaw "reborn" agent.

BUILD / TEST / ARCHIVE (run from repo root):
- Build:   xcodebuild -project NEARPrivateChat.xcodeproj -scheme NEARPrivateChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DD -allowProvisioningUpdates CODE_SIGNING_ALLOWED=NO build
- Unit:    same with `-only-testing:NEARPrivateChatTests test` (NOT the UI test target — its runner is flaky headless)
- Lint pbxproj after adding files: plutil -lint NEARPrivateChat.xcodeproj/project.pbxproj

HARD CONSTRAINTS (violating any of these breaks the build or CI):
1. NO synchronized groups. Every NEW .swift file must be registered in the Xcode project with:
     python3 scripts/pbxproj-add.py <relative/path/to/New.swift> <SiblingInSameDir.swift>
   then `plutil -lint` the pbxproj. App-target files vs test-target files are auto-routed by directory.
2. RULES.md is enforced: `App/` wires lifecycle; `Core/` owns infra; `Features/` own product behavior; `Shared/` is generic UI only. No feature imports another feature's internals — use narrow protocols. ChatStore is legacy debt: do NOT add behavior to it; only add temporary forwarding when the same change moves real logic out. Views/files over ~300–500 lines should be split by owner.
3. No `try!`, `as!`, `fatalError`, or `URL(string:)!` in non-test code. No `print()` in non-test code (use `#if DEBUG` or os.Logger).
4. Agent route requires HTTPS (URLSecurity.isPublicHost). No secrets in code.
5. Match surrounding code style and the doc-comment voice (state the constraint/why, not narration).

ALREADY DONE (builds 8–9) — do NOT redo, but you may refine:
- Login works: WebSignInView (WKWebView harvest of localStorage sessionToken/sessionId), native NEP-413 (NEP413Signer/NearKeyStore/NearAccountSignInView, /v1/auth/near with a TIMESTAMP nonce — bytes 0-7 = Date.now() ms big-endian, 8-31 random), Release token paste. SessionStore.adoptSession.
- ConnectionDiagnostics + ConnectionDiagnosticsView; RouteHealthMonitor distinguishes auth failures (401 / auth-worded 403 → "sign in") from rate limits ("temporarily busy"); auth-401 trips only the private breaker.
- Council GLM force-injection removed; tracker/briefing cloud-proxy routing (cloudBriefingText) with web grounding; DocumentChunker.contextBlock opening-chunks fallback for generic questions; WebGroundingService.searchPrompt low-signal follow-up reuse; SourceFaviconView real favicons (cookie-free, gated to web-search provenance).
- Agent route rewired from /api/chat/* to reborn /api/webchat/v2/* (IronclawAPI, poll-based). Reborn is reachable at https://dangwalvaidy.family/reborn (Caddy strips /reborn → :3000); auth = `Authorization: Bearer <IRONCLAW_REBORN_WEBUI_TOKEN>`.

LIVE API CONTRACTS:
- private.near.ai: Bearer token in `Authorization` header; base `/v1`. Web stores token in localStorage `sessionToken`/`sessionId`.
- reborn webui_v2: POST/GET /api/webchat/v2/threads; POST /threads/{id}/messages {client_action_id, content} → {outcome, run_id, status}; GET /threads/{id}/runs/{run_id}; GET /threads/{id}/timeline?limit=N; POST /threads/{id}/runs/{run}/gates/{ref}/resolve {client_action_id, resolution}; SSE GET /threads/{id}/events (also accepts ?token=). Status enum is PascalCase (Queued/Running/BlockedApproval/BlockedAuth/Completed/Failed/Cancelled/RecoveryRequired). Every mutation needs a client_action_id idempotency key.

WORKING STYLE: After each phase, run the build + `-only-testing:NEARPrivateChatTests`. Add the tests listed in the phase. Do not regress existing tests. Commit per phase with a descriptive message.
```

### How to run a phase with Codex

```sh
cd /Users/abhishekvaidyanathan/Documents/Playground/NEARPrivateChatIOS
git worktree add ../npc-phaseN -b phaseN/<slug> main
cat > /tmp/phaseN.txt <<'EOF'
<paste PROJECT CONTEXT block>

<paste the Phase N section>
EOF
codex exec -C ../npc-phaseN --skip-git-repo-check -s workspace-write \
  -c service_tier=fast -c model_reasoning_effort="high" -c approval_policy="never" - < /tmp/phaseN.txt
# then in that worktree: build + unit tests; review the diff; merge to main.
```
Phases 1–5 touch overlapping files in `ChatStore.swift` and `Features/Chat/`; run them **sequentially** (or accept merge conflicts). Phases 8 (design) and 9 (code quality) can run in parallel worktrees against the others.

---

## PHASE 1 — Document context reaches every route (Functionality · HIGH)

**Objective.** A PDF/XLS/CSV's extracted text must reach the model on *every* route, not just single private. This is the real cause of "pdf/xls/document extraction simply does not work" — the build-8 chunker fix only covered the private streamer.

**Why.** Audit found extracted text is injected only on the private route; cloud, briefing/tracker cloud-proxy, IronClaw Mobile, and Hosted IronClaw each drop it in different ways.

**Files.** `App/State/ChatStore.swift`, `Features/Chat/ChatSendCoordinator.swift`, `Features/Files/AttachmentStagingStore.swift`, `Features/Files/DocumentTextExtractor.swift`, `NEARPrivateChatShareExtension/ShareViewController.swift`, `Core/Persistence/DraftPersistence.swift`.

**Steps.**
1. **Cloud models get extracted text.** In `ChatStore.streamNearCloudModel()` (~ChatStore.swift:3900–3926), the prompt comes from `nearCloudPrompt()` (~5702–5749) which embeds attachment **names only**. Wrap it: build the cloud prompt, then pass it through `documentAugmentedPromptForSend(_:question:attachments:)` (the same call the private path uses at ChatSendCoordinator.swift:575–576) before sending. Respect the existing privacy gate `DocumentTextExtractor.localDocsAllowedForRoute` — local-only docs must NOT be sent to cloud; only server-uploaded `pdf_text`/`table_text` excerpts.
2. **Briefing/tracker cloud-proxy gets extracted text.** In `cloudBriefingText()` (~3853–3898) inject `documentAugmentedPromptForSend()` for any project/briefing attachments before the completion call, mirroring step 1.
3. **IronClaw Mobile gets extracted text.** In `ironclawPrompt()` (~4141–4186) after building `agentContext`, inject document text via `documentAugmentedPromptForSend()` so the Mobile runtime sees content, not just project context.
4. **Hosted IronClaw stops dropping local-only docs.** `hostedIronclawContextSection()` (~4229–4235) filters `!$0.isLocalOnly`, so "Keep on device" docs vanish. Either (a) include local-only doc *text* (capped 2k, "locally-staged, untrusted" marker) instead of filtering, or (b) move the privacy gate upstream so the user can't pick Hosted IronClaw while a local-only doc is attached. Prefer (b) for privacy honesty; show the banner *before* draft, not after send.
5. **Share-extension files extract on receive.** Shared files currently extract only at send (`resolvePromptAttachmentsForSend`). In `ShareViewController` (or `consumePendingSharedItem`) pre-extract via `DocumentTextExtractor` and stage into `AttachmentStagingStore` so text survives if the app is killed before send.
6. **Persist staged text across app kill.** `AttachmentStagingStore.pendingDocumentTexts` (line 18) is in-memory only. Persist it in `DraftPersistence` alongside `pendingLargePasteTexts`; restore on relaunch before send.

**Acceptance.** Attach a PDF with a sentinel string; ask "summarize this" on (a) a private model, (b) a NEAR Cloud model, (c) a tracker/briefing run, (d) IronClaw Mobile — the answer references sentinel content, not just the filename, in all four. Local-only docs never reach cloud/agent.

**Tests.** `NEARPrivateChatTests/Files/`: assert `nearCloudPrompt`-equivalent output contains injected excerpts when uploaded docs are staged; assert local-only docs are excluded from cloud/hosted prompts; assert staged text round-trips through DraftPersistence save/load.

---

## PHASE 2 — Kill truncation: full content everywhere (Functionality · HIGH)

**Objective.** No user-visible body text is silently clipped with "…". This is the "still getting elipsses or not entire content included" complaint.

**Why.** Audit found hard caps that cut content the user expects to see in full.

**Files.** `Features/Chat/MessageStreamingViews.swift`, `Features/Chat/CouncilResponseGroup.swift`, `Features/Chat/ChatModels.swift`, `Shared/Components/Markdown/MarkdownRenderingViews.swift`, `Features/Chat/SourceCarousel.swift`, `Features/Chat/MessageWidgetBodies.swift`, `Shared/Components/Markdown/StreamingMarkdownText.swift`.

**Steps.**
1. **Streaming preview cap.** `MessageStreamingViews.swift:100–111` and the duplicate in `CouncilResponseGroup.swift:240–251` do `String(trimmed.suffix(4_000))` + `lines.suffix(12)`. Remove both caps; render the full streaming text (it's already in a scrollable bubble). Extract the shared logic into one helper (e.g. `StreamingPreviewHelper`) and call it from both — the duplication currently hides that the cap is applied twice.
2. **Source snippet cap.** `ChatModels.swift:240` `snippetPreview` truncates to 420 chars while the stored snippet is already capped at 600 (line 272). Raise the preview to the full stored length (≥600) or remove the second cap.
3. **Briefing query cap.** `MarkdownRenderingViews.swift:1149–1150` (`displayQuery` in `SearchContextStrip`) cuts at 96 chars. Raise to ≥180 or render `lineLimit(2)`.
4. **Wide-table cells.** `MarkdownRenderingViews.swift:835/856` forces `cellLineLimit: 4` + `truncationMode(.tail)` + `maxWidth: 200`. Change `cellLineLimit` to `nil` (keep `maxWidth: 200` + horizontal scroll). Keep the tap-to-expand detail sheet as the full view.
5. **Widget title cap.** `MessageWidgetBodies.swift:18–24` `lineLimit(1)` + `minimumScaleFactor(0.8)` → `lineLimit(2)`.
6. **Sweep for remaining clips.** Grep `Features/Chat` for `lineLimit(1`, `truncationMode(.tail)`, `.prefix(`, `minimumScaleFactor` on **body** text (not row labels/titles in dense lists) and lift caps on assistant message content, council member text, and source snippets. Leave intentional single-line labels (conversation list rows, chips) alone.

**Acceptance.** Stream a >5000-char answer (single + council): the full text renders with no mid-sentence "…". A long source snippet shows in full in the detail sheet. A 5-column markdown table shows full cell text on tap.

**Tests.** Add a render-logic test asserting the streaming-preview helper returns the full string (no suffix cap) for a 6000-char input; assert `snippetPreview` length tracks the stored snippet.

---

## PHASE 3 — Web search & sources: diversity, mode intent, provenance (Functionality)

**Objective.** Fix "search seems like its all from google news" and unify backend vs model-native search.

**Files.** `Core/Services/WebGroundingService.swift`, `App/State/ChatStore.swift`, `Core/API/MessageAPI.swift`, `Features/Chat/ChatModels.swift`, `Features/Chat/MessageRepository.swift`, `Features/Chat/CouncilAnswerTabs.swift`, `Shared/Components/SourceFaviconView.swift`.

**Steps.**
1. **Backend exclusivity.** `ChatStore.swift:4112–4139` can enable BOTH the model-native `web_search` tool (MessageAPI.swift:62–63) and app-side `WebGroundingService` at once, producing mixed/duplicate sources. Make them mutually exclusive: if `modelNativeWebToolPolicy == .always` (model has native search), set `shouldUseAppWebGrounding` false; app-side grounding is the fallback only for models without native search.
2. **News diversity.** `WebGroundingService.fetchGoogleNews` (329–364) is the only news backend. Add a second (e.g. a general web query split, or a configurable secondary). At minimum, when `preferNews` is true, still merge DuckDuckGo general results so it isn't 100% news.google.com. Rank with the existing `sourceQualityScore`.
3. **Source-mode intent.** `searchPrompt()` (159–167) returns text but drops "from google news / news only / web only" intent. Extract a `SearchMode` from the prompt and thread it into `preferNews` (ChatStore.swift:4073) instead of keying only on `researchModeEnabled`.
4. **Council source provenance.** Council sources are deduped into one flat list (`CouncilAnswerTabs.swift:106–116`) with no "which model cited this". Add per-source model attribution (`[WebSearchSource: [modelID]]`) and render "Reuters · cited by GPT-5, Claude" in `CouncilSourcesTabContent`.
5. **Inferred-source favicons + honesty.** Allow `type=='inferred'` sources (model-cited URLs, MessageRepository.swift:232) to fetch favicons (they're public hosts). Add a subtle "Web" badge to web-search sources so users can distinguish them from conversation-derived ones.
6. **Instrumentation.** Add `#if DEBUG` logging of search outcomes (backend, query, result_count) so DuckDuckGo HTML-structure drift is detectable.

**Acceptance.** A news query returns a mix of hosts, not only news.google.com. A council with 3 models shows per-source attribution. A model with native web search does not also run app-side grounding.

**Tests.** `WebGroundingService` SearchMode extraction tests; council source-aggregation dedup + provenance tests (`CouncilSourceAggregationTests`).

---

## PHASE 4 — Council reliability & per-leg sources (Functionality)

**Objective.** Make council trustworthy: per-leg sources, stale-leg timeout, lineup validation, synthesis retry.

**Files.** `Features/ModelCatalog/ModelCatalogStore.swift`, `Core/Streaming/CouncilStreamService.swift`, `App/State/ChatStore.swift`, `Features/Chat/CouncilRoomFeature.swift`, `Features/Chat/CouncilRoomRows.swift`, `Features/Chat/CouncilAnswerTabs.swift`.

**Steps.**
1. **Per-leg sources in the room.** `CouncilMessageRow` (CouncilRoomRows.swift:3–62) has no sources. Add `sources` to `CouncilMessageVM` (CouncilRoomFeature.swift:40), populate in `from()` (87–112), render a compact source strip per member.
2. **Stale-leg timeout.** Council `withTaskGroup` (ChatStore.swift:3297–3402) blocks synthesis on a silently-stuck member. Add a soft per-member timeout (~90–120s of no tokens) that cancels the leg and synthesizes from what's available.
3. **Lineup validation on load.** `ModelCatalogStore.configure` (130–145) restores stored council IDs without checking the live catalog. In `normalizeCouncilSelection()`, drop IDs no longer in `chatModels` (unless `canPreserveCouncilModelID`), and surface "Council lineup updated: N models no longer available."
4. **Inline synthesis retry.** A failed synthesis (model == `llmCouncilSynthesisModelID`, status `failed`) has no inline retry. Add a "Retry synthesis" button in `CouncilSynthesisCard` wired to `synthesizeCouncilBatch(batchID:)`; dedupe so re-running replaces the prior synthesis message rather than appending.
5. **Failure-kind clarity.** `CouncilStreamResult` only has `failureSummary`. Add an `errorKind` (`.rateLimit/.authFailure/.transportError/.timeout`) parsed from the error and show specific status text per member ("Rate limited" vs "Auth failed").

**Acceptance.** Council with one deliberately-slow model still synthesizes within ~2min. Reopening with a deprecated model in the lineup auto-prunes it with a notice. Failed synthesis shows a one-tap retry.

**Tests.** Extend `CouncilTests`: synthesis budget clipping, source dedup, lineup pruning against a shrunk catalog, errorKind mapping.

---

## PHASE 5 — Agent/reborn robustness (Functionality)

**Objective.** Harden the freshly-rewired reborn agent route. ("dont think most recent ironclaw reborn is actually wired in properly" — it is wired and live-validated, but polling-only with thin error handling.)

**Files.** `Core/API/IronclawAPI.swift`, `Features/Agent/AgentStore.swift`, `Features/Agent/AgentModels.swift`, `Features/Account/AccountSettingsDetailViews.swift`, `App/State/ChatStore.swift`, `Features/Agent/HostedHandoffPreflightSheet.swift`.

**Steps.**
1. **Default + validated endpoint.** `IronclawSettings.baseURL` defaults to "". Add a placeholder "e.g. https://your-host/reborn" in the Agent URL field (AccountSettingsDetailViews.swift:~239) and a DEBUG default via env. Document that the reborn base is `https://dangwalvaidy.family/reborn`.
2. **Transient-failure retries.** `fetchRunState`/`fetchTimeline` (IronclawAPI.swift:298/310) currently `try?`-swallow. Add bounded retry on 429/503/timeout with backoff (2s→max 30s, honor `Retry-After`); never retry 4xx auth. Return a `success/permanentFailure/retryable` result, not a bare optional.
3. **Cancellation correctness.** The poll loop checks `Task.isCancelled` but events can apply to the wrong conversation after a switch. In `ChatStore` capture `conversationID` and discard `apply()` events if `selectedConversation?.id != conversationID`.
4. **Gate detail.** `BlockedApproval`/`BlockedAuth` build a generic gate (IronclawAPI.swift:370–373). Surface `gate.reason`/headline/body from the run/timeline so the approval card names the tool and reason (timeout vs denied vs credential-invalid). Tighten `HostedHandoffPreflightSheet.isFamiliarGateHost` with an explicit "third-party auth URL" advisory.
5. **Timeline completeness.** `?limit=20` (IronclawAPI.swift:317) may miss the final assistant message in long chains. Confirm the latest assistant message for the run is present; raise the limit or paginate if the run's final message isn't in the first page.
6. **(Optional, behind a flag) SSE.** Add `streamRunViaSSE()` using a line-buffered `URLSession.bytes` reader against `/threads/{id}/events?token=…`, mapping the `type`-tagged event frames (accepted/running/final_reply/gate/auth_required/failed/cancelled) to `ResponseStreamEvent`. Gate behind a feature flag; keep polling as fallback. This removes the 2s poll latency.
7. **fetchToolNames.** Reborn has no tool-list endpoint; either remove the call and keep the "Shell + git" display literal, or populate from a run-completed capability event when available.

**Acceptance.** Agent send against `https://dangwalvaidy.family/reborn` returns an answer; a tool-approval gate shows the tool name; switching conversations mid-run doesn't leak the answer into the wrong chat; a transient 503 retries instead of failing.

**Tests.** `AgentTests`: `deferred_busy` → `active_run_id` mapping; retry classifier (429/503 retryable, 401 not); conversation-mismatch event discard.

---

## PHASE 6 — Auth & onboarding clarity (Usability)

**Objective.** The sign-in surface now has 3 provider buttons + token paste + NEAR-key + web-harvest — coherent mental model, not clutter.

**Files.** `Features/Auth/AuthView.swift`, `Features/Auth/WebSignInView.swift`, `Features/Auth/NearAccountSignInView.swift`, `Features/Setup/UserSetupView.swift`, `Core/Auth/SessionStore.swift`.

**Steps.**
1. **Hierarchy.** Make the 3 provider buttons (NEAR/Google/GitHub via the web view) the primary path. Move token-paste and NEAR-key into a "More ways to sign in" disclosure. One-line sub-label per method ("Sign in in-app", "Paste a token from private.near.ai", "Sign in locally with your NEAR wallet — no web").
2. **Terms gate legibility.** Move `TermsRowCard` above the providers; dim sign-in until accepted with "Accept the terms above to continue"; make "Read" a compact link in the checkbox row.
3. **Error recovery.** `WebSignInView` harvest that returns empty should show "Sign-in page didn't return a session — try again or use token paste", with a Retry. Token paste invalid → inline red field + guidance. NEP-413 failure → show the server message ("device key not authorized") + a help affordance.
4. **Accessibility.** Add `accessibilityLabel`/`Identifier`/`Hint` across `WebSignInView` and `NearAccountSignInView` (account field, device-key display, copy-key, Step 1/Step 2 buttons, loading indicator).
5. **Onboarding copy.** In `UserSetupView`, replace vague "source behavior / model route / capabilities" with trade-off-explaining copy (web = slower/fresher vs files = faster/private; private = no setup vs Cloud = needs key; what Council/Agent do) + inline help icons.

**Acceptance.** A new user understands, without docs, what each sign-in method does and that terms must be accepted first; a failed sign-in offers a clear next step; VoiceOver reads every auth control.

**Tests.** Snapshot/logic tests are optional here; primary acceptance is a manual pass + accessibility audit. Add a `SessionStore` test that a failed `signInWithNearAccount` surfaces a non-empty user-facing message.

---

## PHASE 7 — Composer & model-picker route clarity (Usability)

**Objective.** Make route/model/source/council state legible before send.

**Files.** `Features/Chat/ChatInputBar.swift`, `Features/Chat/ChatInputBar+Routing.swift`, `Features/ModelCatalog/ModelPickerView.swift`, `Features/Chat/EmptyChatView.swift`, `Features/Agent/AgentWorkspaceView.swift`.

**Steps.**
1. **Session-config summary.** Above the horizontal routing chips (ChatInputBar+Routing.swift:32), add a read-only summary card shown when any non-default is active: "Sending to GPT-5 · Web+Files · Council off · Reasoning auto"; tap to open a full config sheet.
2. **Model-picker route requirements.** In `ModelPickerView` section headers, spell out the barrier: "Private — always available", "Cloud — requires API key", "Agent — requires Hosted IronClaw / Mobile". If a Cloud model is selected with no key, show a top-of-section banner with a direct "Add in Account" button (not just a disabled state). Change "Proof available" badges to "Proof when fetched" unless a snapshot is cached.
3. **Readiness-aware starters.** `EmptyChatStarterCoordinator` suggests "Handoff to Agent"/"Compare with Council" even when unavailable. Gate suggestions on `modelCatalogLoaded && defaultCouncilModels.count >= 2` and agent availability; otherwise show "Set up Agent"/"Add Council models" linking to the right surface.
4. **Agent readiness breadcrumb.** `AgentWorkspaceView` shows MissionControl or Setup with no "what's missing". Add a readiness header ("Agent — Not ready (0/2): 1. Add Cloud key 2. Set hosted URL") linking each step.

**Acceptance.** Before sending, the user can see the full active config in one place; picking a Cloud model with no key shows an actionable banner; empty-state starters never dead-end.

---

## PHASE 8 — Design system consistency & accessibility (Design)

**Objective.** Premium dark-mode consistency (navy/black bg, restrained accents), Dynamic Type, and accessibility. Runs in parallel with functional phases.

**Files.** `Core/DesignSystem/DesignTokens.swift`, `Shared/Components/PrimaryButton.swift`, `Features/Security/SecurityView.swift`, `Features/ModelCatalog/ModelPickerView.swift`, plus the 131 `Color.brandBlue` sites.

**Steps.**
1. **Semantic color discipline.** `Color.brandBlue` is used 131× for non-CTA meaning (Cloud status, metadata, agent state). Add semantic aliases in DesignTokens (`routeCloud = textSecondary`, `routeExternal = textTertiary`, etc.) and reserve `actionPrimary` for the single primary CTA per scene. Audit and replace.
2. **Disabled-state polish.** `PrimaryButton.swift:43` uses only `opacity(0.5)`. Add explicit disabled foreground (`white.opacity(0.6)`), `allowsHitTesting(isEnabled)`, optional failure haptic on disabled tap.
3. **Dynamic Type.** Only ~42 scaledMetric/minimumScaleFactor refs app-wide. Move fixed fonts to system-relative styles; verify `caption2` proof/detail rows are legible at Accessibility-XL; add `@ScaledMetric` where pixel sizes are load-bearing.
4. **Proof-surface copy honesty.** `SecurityView.swift:621–624` implies full model coverage when the model hash is absent — say "Model name listed in proof" unless `modelHashPreview` exists; never show "No proof report" before a fetch succeeds; hide the raw nonce from the primary summary; add a "Proof" navigation title (line 50).
5. **Radius + touch-target consistency.** Standardize: dense rows `AppRadius.pill` (8), feature cards `control` (12), presentation cards `card` (16). Min 44pt touch targets on primary controls (HomeSidebar.swift:40 is 40pt).
6. **VoiceOver.** Add labels/hints to compound controls (model-picker segmented tabs, project file pills as buttons), and expand `DesignTokenContrastTests` to cover white-on-actionPrimary and disabled text contrast.

**Acceptance.** No `brandBlue` for non-CTA semantics; the app is legible and operable at Accessibility-XL; proof copy never overstates; contrast tests pass for button text.

---

## PHASE 9 — Code quality: split ChatStore, kill unsafe code, centralize errors, add tests (Code quality)

**Objective.** Pay down the debt that most impedes future work. Runs in parallel; coordinate ChatStore edits with phases 1–5 (do this phase **after** them, or rebase carefully).

**Files.** `App/State/ChatStore.swift` (6809 lines), `Features/Chat/LiveDataService.swift` (3693), `Shared/Components/Markdown/MarkdownRenderingViews.swift` (1286), `Features/Security/SecurityView.swift` (971), `Features/Sharing/ShareViews.swift` (914), `Features/ModelCatalog/ModelPickerView.swift` (885), `Features/Conversations/ConversationStore.swift`, `Core/Auth/AuthModels.swift`, `Core/API/APIClient.swift`, `Core/API/MessageAPI.swift`.

**Steps.**
1. **Fix unsafe code first (small, high-value).** `ConversationStore.swift:275` `var refreshed = selectedConversation!` → `guard var refreshed = selectedConversation else { return }`. Replace `URL(string:)!` force-unwraps in `AuthModels.swift:183–187` and `WebSignInView.swift:54` with validated static helpers (assertionFailure in DEBUG, safe fallback). Wrap `print()` in `APIClient.swift:91` and `MessageAPI.swift:215` in `#if DEBUG` or os.Logger.
2. **Centralize error copy.** Create `Core/API/ErrorMessageMapper.swift` mapping `APIError`/`StreamingError`/file errors → user strings; replace scattered ad-hoc `showBanner` translations.
3. **Split the giants (one PR each, pure moves + tests).** Per RULES:
   - `MarkdownRenderingViews.swift` → `MarkdownBlockParser.swift` (parser+cache) + `TableBlockView`/`ListBlockView`/`QuoteBlockView`/`CodeBlockView`; leave composition ~300 lines.
   - `SecurityView.swift` → hero / action-stack / verification-detail / education-accordion / proof-report sub-views.
   - `ShareViews.swift` → mode-picker / permission-picker / target-input / group-management / public-link sub-views; move nested enums to own files.
   - `LiveDataService.swift` → `LiveCoinsData.swift` (data) + `QuickIntentModels.swift` (types) + `QuickIntentParser.swift` (logic); facade stays thin.
   - `ModelPickerView.swift` → search-field / tab-bar / pinned-list / all-models-list sub-views.
4. **Shrink ChatStore by domain.** Extract cohesive domains into owners (send pipeline already partly in ChatSendCoordinator; do conversation-session, draft-scope, memory next). Delete the forwarding wrappers (ChatStore.swift:6702–6809) once callers call the real owners. Target trajectory toward <1500 lines (RULES end-target 300). Each extraction is a 2-pass refactor: extract+test, then update callers. **Register every new file via scripts/pbxproj-add.py.**
5. **Lifecycle cleanup.** Add a `ChatStore.deinit`/reset that stops `AgentActivityController`, `IronclawMobileRuntime`, `WebGroundingService` background work (add `cancel()`/`stop()` to each).
6. **Close test gaps.** Add `ConversationStoreTests`, `ShareStoreTests`, `FileStoreTests` (mock repositories, deterministic fixtures), covering lifecycle/mutation/cache paths.

**Acceptance.** No `try!/as!/fatalError/URL(string:)!/print()` in non-test code (grep clean); no file over ~900 lines except ChatStore (and ChatStore trending down); new store tests green; full unit suite green.

---

## PHASE 10 — Verification & ship gate

1. Full unit suite green: `-only-testing:NEARPrivateChatTests` (after a Mac restart if the runner PTY is wedged).
2. Manual device pass on the **Hostile Product Test Matrix**: sign in (each method) → private send → cloud send → council 3× → PDF summarize on every route → tracker run → agent send via reborn → switch chats mid-stream → relaunch (persistence).
3. Visual pass at 393pt + Accessibility-XL + dark mode.
4. Bump `CURRENT_PROJECT_VERSION`, archive (`xcodebuild archive … CODE_SIGNING_ALLOWED=NO`), upload via Xcode GUI session or ASC API key.

---

## Priority cheat-sheet

| Phase | Axis | User complaint it fixes | Risk |
|---|---|---|---|
| 1 Documents reach every route | Functionality | "extraction doesn't work" | low |
| 2 Kill truncation | Functionality | "ellipses / not entire content" | low |
| 3 Search & sources | Functionality | "all from google news" | med |
| 4 Council reliability | Functionality | "sources don't render for council" | med |
| 5 Agent reborn robustness | Functionality | "reborn not wired properly" | med |
| 6 Auth & onboarding clarity | Usability | new sign-in clutter | low |
| 7 Composer/picker clarity | Usability | route confusion | low |
| 8 Design system & a11y | Design | polish, accessibility | low |
| 9 Code quality | Code quality | maintainability, crash risk | med (refactor surface) |

Start with Phases 1 and 2 — they are the smallest changes that resolve the loudest, longest-standing complaints.
