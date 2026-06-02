# NEAR Private Chat iOS Codebase Audit — Copy, Auth, Workflow

Date: 2026-06-01
Branch: `design/v2-claude-design-handoff`

## Verdict

This pass is shippable for review. I did not find a blocking regression in the changed implementation after auditing the risky areas: auth normalization, route trust copy, Home prompt staging, setup defaults, native vision handling, Soul prompt injection, and the regression tests covering the hostile product lanes.

The worktree now has a coherent theme: private chat stays the default, external routes are disclosed more plainly, raw auth failures are hidden behind actionable Account copy, Home stages actions before sending, and the app preserves broader “turn any context into useful work” behavior instead of hardcoding one workflow.

## Local Re-Audit Pass

Ran directly in this checkout at `2026-06-01 19:12 CEST` after the user asked whether the audit had actually been run, not just written up.

- Compared the full branch against `origin/main` and reviewed the active delta shape with `git diff --stat origin/main...HEAD` and `git log origin/main..HEAD`.
- Re-scanned auth, route, proof, speculative-model, Home-launch, setup, attachment, Soul prompt, legal-placeholder, and stale-copy surfaces with `rg`.
- Re-read the high-risk implementation areas: `PrivateChatAPI`, `ChatStore`, `SoulPromptComposer`, `SetupSoulPromptBuilder`, `EmptyChatStarterCoordinator`, `ConversationListView`, `FileModels`, and `LiveDataService`.
- Linted all app, share-extension, and widget plists with `plutil`.
- Ran Xcode static analysis for the app target with `xcodebuild analyze -scheme NEARPrivateChat -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`; it completed with `ANALYZE SUCCEEDED`.

The re-audit found one non-functional cleanup: an unprofessional regression-test comment. It has been rewritten so the test suite does not carry sloppy copy into review.

## What Changed

- Cleaned copy across onboarding, Account, Home, chat, model picker, sharing, proof, files, widgets, and Agent surfaces.
- Replaced “Hosted Agent” phrasing with “Hosted IronClaw” in user-facing surfaces.
- Normalized pasted NEAR AI Cloud credentials, including copied `Authorization: Bearer …` headers.
- Rejected blank Cloud keys and whitespace-only app auth tokens before network calls.
- Added friendlier auth failure copy for raw 401/403 “Missing authorization header” and expired-token backend responses.
- Added `soul.md` profile parsing and setup-generated Soul defaults, with identity/rules kept to the private route while intent/format preferences can inform non-private routes.
- Added Markdown format contracts to model prompts so generated work products fit the app renderer.
- Preserved Home action staging through Project/Council follow-up sheets instead of dead-ending after selection.
- Kept HEIC/HEIF/TIFF native-vision behavior safe by transcoding to JPEG before vision upload.

## Audit Notes

### Auth And Cloud Keys

No blocker found. `PrivateChatAPI.normalizedNearCloudAPIKey(_:)` trims whitespace and strips copied `Authorization:` / `Bearer` prefixes before model-list and chat-completion calls. Blank Cloud keys now fail locally with actionable copy instead of sending an empty Authorization header. App session tokens are trimmed before authenticated requests, and whitespace-only tokens now produce `.unauthenticated` before network.

### Trust And Proof Copy

No blocker found. Proof copy no longer overstates truth verification. The changed copy says proof shows where a request ran and avoids saying the answer itself is verified. The scan found no product-source hits for old “truthfulness,” “Proof, not a promise,” “Missing authorization header,” or “Invalid or expired authentication token” copy.

Internal route identifiers such as `"hosted-agent"` remain in serialized metadata paths, which is expected. User-facing labels now use Hosted IronClaw.

### Model Catalog And Speculative IDs

No product-source leak found. Speculative identifiers remain in tests only as fixtures and banned-string assertions. Product source does not expose the banned fallback names scanned in this audit.

### Home Workflow

No blocker found. Home prompt staging now uses `EmptyChatStarterCoordinator.prepare` to apply route/source side effects first, then resumes pending prompts after Project or Council sheets close. This avoids the earlier dead-end where the user tapped a workflow chip, got a setup/select sheet, and lost the prompt flow.

### Soul Markdown

No blocker found. `SoulPromptComposer` parses the expected `soul.md` sections and limits private identity/rules to `.nearPrivate`. Intent and voice/format can travel to external routes, so product preferences survive route changes without leaking identity text or conditional private rules. Tests cover private vs Cloud vs IronClaw prompt injection.

### Native Vision Attachments

No blocker found. HEIC/HEIF/TIFF are still not sent raw as `input_image`; they are normalized to JPEG first, then dispatched with vision upload purpose. This avoids silent OCR-only behavior for default iPhone camera formats.

### Copy Quality

No blocker found. The pass removes a lot of overlong/legalistic copy and reduces “agentic” jargon in primary surfaces. There is still some dense operational copy in Project action prompts and LiveData prompt contracts, but those are prompt scaffolds rather than visible UI.

## Verification

- `xcodebuild test -scheme NEARPrivateChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:NEARPrivateChatTests/PrivateChatCoreTests`
- `xcodebuild analyze -scheme NEARPrivateChat -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`
- `scripts/build-simulator.sh`
- `git diff --check`
- `plutil -lint NEARPrivateChat/Info.plist NEARPrivateChatShareExtension/Info.plist NEARPrivateChatWidget/Info.plist`
- Product-source copy scan for stale auth/proof/Hosted Agent/speculative-model strings.
- Simulator install + launch smoke on iPhone 17 Pro.

## Residual Risks

- `PrivateChatCoreTests` is broad and useful, but this repo still needs a true snapshot/UI test target for visual regressions.
- `ChatStore.swift` remains very large. The new Soul prompt extraction helps, but route readiness, prompt assembly, and action staging still deserve further extraction.
- `scripts/build-simulator.sh` succeeds, but Xcode logs an AppIntents SSU archive warning/error line during simulator builds. It is non-blocking in this run but worth tracking before TestFlight hardening.

## Recommendation

Push this branch for review with `zmanian` and `elliotBraem` tagged as reviewers. Ask them to focus on the trust-language changes, auth failure behavior, Home workflow staging, and whether Soul prompt private/external boundaries match product intent.
