# NEAR Private Chat iOS

Native SwiftUI client for NEAR Private Chat at `https://private.near.ai`.

## Phone-First Architecture

The iPhone app is standalone for normal chat: sign-in, model list, conversations, files, web search, streaming responses, attestation, and the IronClaw Mobile runtime all go over the internet to `https://private.near.ai`. It does not need a Mac or LAN gateway.

IronClaw Mobile is the first native iOS runtime stack: it runs mobile-safe orchestration on the phone, executes native app tools for local projects/chat organization/file context/web-search settings, and uses NEAR Private inference, web search, attachments, and project context for final responses. The desktop-only IronClaw features that need shell access, Docker, Postgres, unsandboxed filesystem access, LAN gateways, or background daemons are intentionally unavailable on iOS. Hosted IronClaw can still be connected by URL, but local `192.168.x.x`, `localhost`, and HTTP gateways are development-only and are not used for the deployable phone experience.

For desktop-powered IronClaw, the phone expects an authenticated public Hosted IronClaw URL, not a raw LAN URL. See `IRONCLAW_REMOTE_BRIDGE.md`.

Quick desktop bridge helper:

```sh
./scripts/start-ironclaw-https-bridge.sh
```

The helper starts the local IronClaw gateway, then exposes it through Cloudflare Tunnel or ngrok if either tool is installed. Paste the generated HTTPS URL and bearer token into Account -> Agent connection.

## What Works

- Browser-based sign-in through the hosted NEAR wallet login page.
- Google and GitHub OAuth through `/v1/auth/{provider}`.
- Secure token persistence in the iOS Keychain when the app is signed. Unsigned simulator builds still keep the session in memory.
- Optional defaults tuning from Account can set source behavior, route preferences, IronClaw, Project, and LLM Council defaults. The app opens directly into the chat/workboard surface after sign-in.
- Conversation list, new conversation creation, reload, delete, pin, unpin, and link copy.
- Sidebar search, conversation rename, archive/unarchive, copy-and-continue cloning, and swipe actions for pinning, archiving, or deleting chats.
- Archived chats sheet with restore, delete, unarchive-all, archive JSON copy, and archive JSON file export.
- Project organization with local project buckets, project-scoped chat lists, move-to-project actions, and project file context.
- New-project creation supports initial project instructions, and any open chat can be promoted into a new project from the conversation menu.
- Project instructions, project memory, reusable source links, and saved assistant outputs that are stored locally and applied to every NEAR Private, NEAR Cloud, and IronClaw Mobile request inside that project.
- Automatic chat grouping into pinned, today, this week, and older sections.
- File attachment upload through `/v1/files` with `input_file` parts on chat requests, including reusable project files, per-prompt source mode controls, and an explicit private file library for previewing, reusing, and deleting uploaded sources.
- Native file library parity for `/v1/files`, `/v1/files/{id}`, and `/v1/files/{id}/content`, with attach-to-prompt and add-to-project actions from Project Context.
- Readable PDFs are converted to text before upload so small text-based PDFs behave like normal chat context; text, Markdown, CSV, and JSON files can be attached per prompt or saved to a project.
- IronClaw Mobile model route for iOS-safe agent orchestration over NEAR Private inference, web search, attachments, and project context.
- Account settings for an authenticated Hosted IronClaw URL, with test/disconnect controls and LAN URL validation.
- IronClaw Mobile native tool stack: Project snapshot, capability report, project create/select, source-link capture, project instructions, project memory, project notes, prompt-file promotion to project context, chat move-to-project, chat rename/pin/archive, web-search toggle, research mode, and source-mode switching.
- NEAR Private models use `/v1/responses` with native `web_search` tools and streamed source events, matching the web app route.
- Optional NEAR AI Cloud route through `https://cloud-api.near.ai/v1/chat/completions`, with the API key stored in Keychain. This route is marked separately from NEAR Private inference because it can call external providers and does not carry NEAR Private proof.
- API-backed public conversation sharing.
- Shared With Me inbox for conversations shared to the signed-in account, with preview, copy-and-continue, and writable-open when the API grants `can_write`.
- Collaboration sharing with public links, direct email/NEAR-account invites, organization email patterns, read/write permissions, and remove-access controls.
- Share groups from the web app are available in the native share sheet, including group creation, editing, deletion, member previews, and sharing a conversation with an existing group.
- Shared-link viewer for `private.near.ai/c/...` conversations before or after sign-in, with read-only clone or writable-open based on API permissions.
- Shared-link copy-and-continue flow through `/v1/conversations/{id}/clone`.
- Remote account settings for appearance, notification preference, web-search default, system prompt, large-paste handling, and advanced model params through `/v1/users/me/settings`.
- Chat import from Account supports native NEAR Private Chat JSON exports and legacy Private Chat history JSON, then creates imported conversations and posts message batches to `/v1/conversations/{id}/items`.
- Advanced model params from the mobile reference app: `temperature`, `top_p`, and `max_tokens` sync through `/v1/users/me/settings` and are sent on `/v1/responses`.
- Large pasted text can be uploaded automatically as a `.txt` file attachment, matching the mobile app's file-context behavior.
- Billing visibility through `/v1/subscriptions/plans` and `/v1/subscriptions`, with clearer payment/credit-required error copy.
- Main-chat transcript copy plus native TXT, JSON, and paginated PDF export from the conversation menu.
- Signed JSON transcript export with per-message hashes, transcript hash, route/attestation metadata, and a device-Keychain Ed25519 signing identity; `verifier/` contains offline CLI and browser verification.
- `nearprivatechat://agent`, `nearprivatechat://verified`, and `nearprivatechat://chat/new?...` deep links open phone-ready Agent or proof-ready private chat starts without colliding with `nearprivatechat://auth` sign-in callbacks.
- Model list from `/v1/model/list`, ranked private-first with GLM and strong Qwen routes at the top, then higher-end frontier routes when the current plan allows them. Older/smaller models such as o3, o4-mini, GPT OSS, mini, lite, flash, Gemma, and stale provider versions are hidden from the picker.
- LLM Council mode based on IronClaw's `llm-council` skill: pick 2-3 available NEAR AI chat models, use a default cross-vendor lineup when available, stream each model in parallel, view grouped per-model answers, and receive a final synthesis while individual model failures stay isolated.
- Open-weight default preference for GLM/Kimi/DeepSeek/Qwen before closed-provider models, while keeping weaker open models available only as hidden fallback where useful.
- IronClaw Mobile uses open-weight base models only; access-denied or stalled models are skipped before final failure, and mobile-visible output is timed out so fake `running` states do not sit forever.
- Web/search behavior is explicit by default: private chat starts in Auto, research setup can turn current-source search on, and users can choose Auto, Web, Saved links, Files, and Web + Files source modes. Search-query/source chips appear when the backend returns structured source URLs.
- Hosted IronClaw and NEAR Cloud routes can use app-side web grounding for live questions, so they receive source packs before model execution instead of replying that web search is unavailable. Hosted IronClaw receives prompt text and attachment metadata by default; file contents must appear as extracted text, excerpts, or source packs to be treated as evidence.
- Phone-first IronClaw launcher with one mission composer, agent-decided routing, quick-start examples for repo/PR/research/planning work, project context, and a compact readiness check instead of exposed playbooks.
- Phone-agent prompts include invisible IronClaw skill routing for code review, security review, QA, planning, product prioritization, decision capture, repo setup, and research-to-code work without adding a separate playbook UI.
- Account diagnostics run model-catalog, app web-grounding, hosted IronClaw, and NEAR Cloud key checks in one place before demos.
- Source modes now have strict active-context semantics: Web means web plus prompt files only; Saved links means project source links plus prompt files; Files means project/prompt files without broad web; Web + Files and Research combine web, files, and saved links.
- Research mode in the composer, which forces web-capable source behavior on NEAR Private routes, adds report-style answer instructions with dates/evidence/source handling, and turns off when the user explicitly chooses another source mode.
- Streaming assistant responses through `/v1/responses`.
- Stale local running states are normalized on reload so interrupted runs do not sit forever as fake in-progress chats.
- Polished Markdown rendering for assistant output, including headings, bullets, numbered lists, quotes, code blocks, tables, source context, and selectable text.
- Artifact-style output sheets for long assistant responses, tables, code, and reports, with copy and save-to-project actions.
- Inline assistant response actions for copy, regenerate, save-to-project, and opening long outputs.
- Regenerate now uses the Responses API's regenerate initiator, follows the newest response branch, and exposes a compact response variant picker when sibling answers exist.
- User message editing starts a new branch with the Responses API's edit-message initiator while preserving the original prompt files, with branch selection available on regenerated/edited sibling answers.
- Two-row mobile composer with full-width prompt entry, explicit source-mode pill, attachment control, research toggle, and active project-context strip.
- Gateway attestation fetch through `/v1/attestation/report`, scoped to the selected model when available.
- NEAR AI brand pass using `#0091FD`, `#EEEEEB`, and official Private Chat icon artwork, with a blue command-card home system, soft-blue selected rows, and matching preview home screen.

## Current Product Contract

- **Source Mode:** Auto decides conservatively; Web uses live web plus prompt attachments; Saved links uses project source links; Files uses project/prompt files without broad web; Web + Files combines web, project files, saved links, and prompt attachments. Research Mode is an explicit source-heavy answer style, not a hidden default.
- **Proof:** Proof reports check route/model evidence from TEE-supported infrastructure when fetched. They do not prove answer truth, answer quality, or that a specific answer was cryptographically bound to a report unless a surface explicitly says so.
- **Cloud:** NEAR AI Cloud is an external-provider route through NEAR Cloud credentials. It is useful for frontier models, but it does not carry a NEAR Private proof report.
- **Hosted IronClaw:** Hosted IronClaw is a user-connected agent route. Before high-trust work, the app should show what prompt, project context, files, and tool class would leave the phone.
- **Trackers:** Trackers are recurring asks. Built-in live-data trackers are optimizations; arbitrary recurring research, analysis, reminders, and action scans should flow through the same tracker/action-plan model.
- **Sharing:** Public links, account invites, group sharing, organization sharing, and signed exports are separate trust models and should stay visually distinct.

## Run

1. Open `NEARPrivateChat.xcodeproj` in Xcode 26.5 or newer.
2. Set the signing team on the `NEARPrivateChat` target for device builds.
3. Run on an iPhone simulator or device.

From the terminal:

```sh
./scripts/build-simulator.sh
./scripts/run-simulator.sh "iPhone 17 Pro"
```

Hosted IronClaw and attachment smoke checks:

```sh
./scripts/seed-simulator-ironclaw.sh "iPhone 17 Pro"
./scripts/ironclaw-preflight.sh
./scripts/attachment-upload-smoke.sh "iPhone 17 Pro"
```

These scripts do not print bearer tokens. `seed-simulator-ironclaw.sh` reads `IRONCLAW_AUTH_TOKEN` when provided, otherwise it can discover the gateway token over SSH using `IRONCLAW_SSH_HOST`, `IRONCLAW_SSH_PORT`, `IRONCLAW_SSH_USER`, and `IRONCLAW_SSH_KEY`.

For a physical iPhone, connect the phone over USB, unlock it, trust the Mac, enable Developer Mode if prompted, then run:

```sh
./scripts/run-device.sh
```

The app registers the custom callback scheme `nearprivatechat://auth`. Production sign-in uses PKCE authorization-code callbacks with an active state verifier; bearer-token callbacks are rejected by the app. The debug token-paste path is internal-only and shown only in debug builds.

## Manual Xcode Steps

1. Open `NEARPrivateChat.xcodeproj`.
2. Select the `NEARPrivateChat` scheme.
3. Pick an iPhone simulator.
4. Press Run.

## API Notes

The app follows the same contract used by `nearai/private-chat`:

- `GET /v1/model/list`
- `GET /v1/users/me/settings`
- `POST /v1/users/me/settings`
- `GET /v1/conversations`
- `POST /v1/conversations`
- `GET /v1/conversations/{id}`
- `GET /v1/conversations/{id}/items`
- `DELETE /v1/conversations/{id}`
- `POST /v1/conversations/{id}/clone`
- `POST /v1/conversations/{id}/archive`
- `DELETE /v1/conversations/{id}/archive`
- `GET /v1/conversations/{id}/shares`
- `POST /v1/conversations/{id}/shares`
- `DELETE /v1/conversations/{id}/shares/{share_id}`
- `POST /v1/files` multipart upload with `purpose: "user_data"`
- `DELETE /v1/files/{id}`
- `POST /v1/responses` with `stream: true`, `signing_algo: "ecdsa"`, optional `input_file` parts, and optional `web_search`
- `GET /v1/attestation/report`
- `POST https://cloud-api.near.ai/v1/chat/completions` for NEAR AI Cloud routes when a Cloud API key is configured.

For internal testing, the sign-in screen also has a developer token path so a known session token can be pasted directly.

## Next Production Pass

- Add native NEP-413 signing instead of using the hosted `/near-login` bridge.
- Add App Store privacy copy.
- Expand remote user settings to appearance and notifications.
- Add KaTeX/math rendering parity for technical answers.
- Show shared author metadata inside message rows.
- Add iPad drag/drop polish for attachments.
- Add server-backed project sync once the API exposes shared/project metadata.
- Add richer citation cards if the backend returns source URLs consistently for web searches.
- Expand attestation detail screens to match the full web verifier.
