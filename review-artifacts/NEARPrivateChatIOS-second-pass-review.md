# NEAR Private Chat iOS Second-Pass Review

Date: 2026-05-24
Scope: second pass against the previous feature/design audit after suspected fixes.

## Verification

- `./scripts/build-simulator.sh` passes.
- `xcodebuild test -project NEARPrivateChat.xcodeproj -scheme NEARPrivateChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO` passes.
- Current tests are still only `PrivateChatCoreTests` with 5 tests.

## Verdict

Several important first-pass issues have been fixed, but not all of the audit is closed. The app is currently build-green and test-green, but the remaining high-risk items are still real product bugs or release blockers rather than polish.

## Confirmed Fixed

- OAuth callback state is generated, persisted, passed into auth URLs, and validated before accepting a callback.
  - `NEARPrivateChat/SessionStore.swift` lines 47-52 and 97-101.
  - `NEARPrivateChat/PrivateChatAPI.swift` lines 28-42.
  - Covered by tests in `NEARPrivateChatTests/PrivateChatCoreTests.swift`.
- SSE streams now fail if the stream ends before `response.completed`.
  - `NEARPrivateChat/PrivateChatAPI.swift` lines 501-527.
- `developer` and `tool` roles decode without crashing imports.
  - `NEARPrivateChat/Models.swift` lines 528-544.
  - Covered by tests in `NEARPrivateChatTests/PrivateChatCoreTests.swift`.
- PDF text extraction is detached from the main actor and uploaded as extracted text metadata.
  - `NEARPrivateChat/ChatStore.swift` lines 1516-1533.
- Chat import file reading is detached.
  - `NEARPrivateChat/ChatStore.swift` lines 699-708.
- IronClaw gateway defaults were hardened and the connection test now hits the authenticated chat route.
  - `scripts/start-ironclaw-gateway.sh`.
  - `scripts/start-ironclaw-https-bridge.sh`.
  - `NEARPrivateChat/IronclawAPI.swift` lines 7-36.

## Still Open

### P1: Conversation Loading Race Still Exists

`selectConversation` still starts an untracked task and `loadMessages` still writes the global `messages` array without checking that the user is still viewing the same conversation. Rapid chat switching can show the wrong transcript.

Relevant source:
- `NEARPrivateChat/ChatStore.swift` lines 823-830.
- `NEARPrivateChat/ChatStore.swift` lines 2106-2128.
- `NEARPrivateChat/ChatStore.swift` lines 2132-2138.

Fix packet:
- Track a load generation or selected conversation ID.
- Cancel previous load task on selection.
- Apply fetched messages only when `selectedConversation?.id == conversation.id`.
- Add an out-of-order mock API test.

### P1: Cached Local Messages Still Mask Server Truth

`loadMessages` still returns immediately when local cached messages exist. That protects IronClaw/external responses, but it can permanently hide server-side changes, shared updates, branch updates, or edits from another device.

Relevant source:
- `NEARPrivateChat/ChatStore.swift` lines 2106-2119.
- `NEARPrivateChat/ChatStore.swift` lines 3530-3534.
- `NEARPrivateChat/ChatStore.swift` lines 3652-3661.

Fix packet:
- Show cached messages optimistically, then refresh from server in the background.
- Mark cache entries as local-only/external-only instead of applying the shortcut to every conversation.
- Merge remote messages with locally persisted external assistant turns.

### P1: Permanent Conversation Deletes Still Lack Confirmation

Delete still fires directly from list swipe actions, the chat overflow menu, and archived chats. Archive exists, but permanent delete remains one tap away.

Relevant source:
- `NEARPrivateChat/AppShellView.swift` lines 213-226.
- `NEARPrivateChat/AppShellView.swift` lines 1462-1467.
- `NEARPrivateChat/AppShellView.swift` lines 3703-3709.
- `NEARPrivateChat/ChatStore.swift` lines 1654-1677.

Fix packet:
- Route delete through a confirmation dialog.
- Prefer Archive as the default quick action.
- Add undo or archive-first behavior for recent deletes.

### P1: Coverage Is Still Far Behind The App Surface

The suite still covers only auth state and role/import normalization. There is no coverage for stream parsing, stream truncation, conversation-load races, source modes, file uploads, sharing, billing/model gating, IronClaw polling/gates, setup rerun, export, or destructive actions.

Relevant source:
- `NEARPrivateChatTests/PrivateChatCoreTests.swift` lines 1-70.

Fix packet:
- Introduce protocol seams for `PrivateChatAPI`, `IronclawAPI`, and persistence.
- Add deterministic `ChatStore` tests before further feature work.
- Add a small XCUITest target for auth screen, home-to-chat, source/model menus, share/security sheets.

### P2: Plain File Upload Still Reads Data On The Main Actor

PDF and import reads were fixed, but non-PDF uploads still call `Data(contentsOf:)` inside `PrivateChatAPI.uploadFile`. Since `ChatStore` is `@MainActor` and this read happens before suspension, a large local file can still freeze the UI and the upload body is held fully in memory.

Relevant source:
- `NEARPrivateChat/PrivateChatAPI.swift` lines 169-183.
- `NEARPrivateChat/ChatStore.swift` lines 1498-1537.

Fix packet:
- Read file data from detached/background work before calling upload.
- Consider streaming multipart or stricter memory caps.
- Add cancellation/progress feedback.

### P2: Sensitive And Large App Data Still Lives In UserDefaults

Projects, local message caches, conversation list cache, IronClaw thread IDs, setup profile, and user settings still use UserDefaults. That is fragile for larger payloads and not ideal for sensitive chat/project context.

Relevant source:
- `NEARPrivateChat/ChatStore.swift` lines 116-118.
- `NEARPrivateChat/ChatStore.swift` lines 3525-3541.
- `NEARPrivateChat/ChatStore.swift` lines 5778-5807.
- `NEARPrivateChat/Models.swift` lines 492-505.

Fix packet:
- Move message/project/conversation caches to file-backed JSON or SQLite.
- Set data protection attributes.
- Add size limits, eviction, schema versioning, and clear-cache controls.

### P2: IronClaw SSE Consumer Is Still Dead Code

`streamPrompt` still sends a prompt and polls history. `consumeEvents` exists, but there is no non-recursive call site.

Relevant source:
- `NEARPrivateChat/IronclawAPI.swift` lines 153-211.
- `NEARPrivateChat/IronclawAPI.swift` lines 487-535.

Fix packet:
- Wire SSE into `streamPrompt` and fall back to polling, or delete/quarantine the unused implementation.
- Add tests around running/completed/failed/approval states.

### P2: Saved Links Source Mode Is Now Inconsistent

`ChatSourceMode.links` still exists, is still handled by prompts and IronClaw Mobile, but the composer menu no longer exposes it. A user can land in this mode from saved defaults or IronClaw, but cannot select it directly from the main source menu.

Relevant source:
- `NEARPrivateChat/Models.swift` lines 170-186.
- `NEARPrivateChat/ChatStore.swift` lines 300-313 and 5530-5565.
- `NEARPrivateChat/IronclawMobileStack.swift` lines 459-470.
- `NEARPrivateChat/AppShellView.swift` lines 6381-6417 and 6499-6501.

Fix packet:
- Either re-add `.links` to `composerContextModes`, or remove/merge the mode everywhere.
- Separate "app attaches saved link context" from "model has live web tool" in labels and tests.

### P2: Public/Shared Reads Still Do Not Retry Unauthenticated

Readable conversation endpoints authenticate whenever a token exists. An expired signed-in token can make an otherwise public link fail instead of falling back to an unauthenticated read.

Relevant source:
- `NEARPrivateChat/PrivateChatAPI.swift` lines 233-247.

Fix packet:
- On 401/403 for readable endpoints, retry unauthenticated.
- Preserve authenticated fetch for write/share permission discovery.

### P2: Raw Shared ID Parsing Is Still Narrow

Raw pasted IDs only work for `conv_` and `chatcmpl-`, while `/c/<id>` URLs accept any ID segment.

Relevant source:
- `NEARPrivateChat/ChatStore.swift` lines 2053-2058.
- `NEARPrivateChat/ChatStore.swift` lines 5276-5295.

Fix packet:
- Accept safe raw IDs more generally, or route all raw values through the same path parser rules.
- Add tests for newer backend ID formats.

### P2: Run Setup Again Still Only Clears Completion

The Account action clears the setup completion flag and dismisses the sheet, but `RootView` only presents setup on app appear or session-token change. It likely does not reopen setup immediately after tapping the button.

Relevant source:
- `NEARPrivateChat/NEARPrivateChatApp.swift` lines 43-85.
- `NEARPrivateChat/AppShellView.swift` lines 4142-4148.
- `NEARPrivateChat/Models.swift` lines 492-505.

Fix packet:
- Add an app-level setup rerun binding/action instead of only clearing storage.
- Scope setup completion to the signed-in account if multiple accounts can use the same device.

### P3: Release Readiness Is Still Incomplete

The project still has no signing team, no privacy manifest, no entitlements, iPhone-only target, and portrait-only orientation.

Relevant source:
- `NEARPrivateChat.xcodeproj/project.pbxproj` lines 376-419.
- `NEARPrivateChat/Info.plist` lines 44-47.
- No `PrivacyInfo.xcprivacy` exists under `NEARPrivateChat/`.

Fix packet:
- Add `PrivacyInfo.xcprivacy`.
- Decide iPhone-only vs universal.
- Fill release signing/configuration values outside local-only scripts.

### P3: Documentation Drift Still Exists

`WEB_PARITY.md` still marks subscriptions/plans as missing even though the README and source now include billing plan/subscription fetches and account display.

Relevant source:
- `WEB_PARITY.md` line 70.
- `README.md` line 52.
- `NEARPrivateChat/PrivateChatAPI.swift` lines 112-119.
- `NEARPrivateChat/AppShellView.swift` lines 4237-4244.

Fix packet:
- Update parity docs so Claude/Codex agents do not reimplement already-present billing work.

## Suggested Claude Code Queue

1. Fix conversation load generation/cancellation and local-cache refresh semantics.
2. Add confirmation/undo paths for destructive deletes.
3. Add API/persistence seams plus unit tests for `ChatStore`, source modes, streaming, shared links, and file uploads.
4. Move large/sensitive caches out of UserDefaults.
5. Resolve source-mode taxonomy, especially the hidden `Saved links` mode.
6. Do the release metadata pass: privacy manifest, signing config notes, doc parity.
