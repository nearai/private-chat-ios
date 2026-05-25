# Web Parity Ledger

Source of truth: public `nearai/private-chat`, cloned locally at `/Users/abhishekvaidyanathan/Documents/Playground/output/upstream-private-chat`.

This ledger is intentionally blunt: every feature confirmed in the web repo is either implemented, partially implemented, or queued with the upstream evidence path.

## Chat Core

| Web feature | Upstream evidence | iOS status | Notes |
| --- | --- | --- | --- |
| OAuth login with hosted callbacks | `src/api/base-client.ts`, `src/pages/WelcomePage.tsx` | Implemented | NEAR, Google, and GitHub OAuth return into `nearprivatechat://auth`. |
| Conversation list/create/items/delete | `src/api/chat/client.ts` | Implemented | Uses `/v1/conversations`, `/v1/conversations/{id}/items`, and delete. |
| Rename chat | `src/components/sidebar/ChatMenu.tsx` | Implemented | Native rename sheet updates conversation metadata title. |
| Pin/unpin chat | `src/api/chat/client.ts` | Implemented | Native leading swipe and toolbar action call `/pin`. |
| Archive/unarchive chat | `src/api/chat/client.ts`, `src/components/common/dialogs/archived-chats/ArchivedChatsModal.tsx` | Implemented | Native trailing swipe archives; Archived sheet restores, deletes, unarchives all, and copies archive JSON. |
| Copy/clone conversation | `src/api/chat/client.ts`, `src/pages/Home.tsx`, `src/pages/PublicConversationPage.tsx` | Implemented | Native `Copy & Continue` calls `/conversations/{id}/clone`; shared previews can copy into owned chats. |
| Stop streaming response | `src/components/chat/MessageInput.tsx` | Implemented | Send button becomes Stop while streaming. |
| Regenerate assistant response | `src/components/chat/messages/ResponseMessage.tsx` | Implemented | Native sends `initiator: "regenerate"`, uses the parent `previous_response_id`, clears stale branch overrides, and follows the newest response branch. |
| Edit user message and branch | `src/components/chat/messages/UserMessage.tsx`, `src/types/index.ts` | Implemented | Native user-message context menu opens an edit sheet, sends `initiator: "edit_message"`, preserves files, clears stale branch overrides, and follows the newest branch. |
| Multiple response variants/siblings | `src/components/chat/messages/MultiResponseMessages.tsx`, `src/pages/Home.tsx` | Implemented | iOS groups same-turn LLM Council responses in a native comparison view and shows a compact response-variant picker for regenerated or edited historical sibling branches. |
| Multi-model responses | `src/types/index.ts`, `src/pages/Home.tsx`, IronClaw `skills/llm-council/SKILL.md` | Implemented | Native LLM Council mode persists 2-4 selected models, offers a default cross-vendor lineup, streams each model in parallel, isolates per-model failures, and adds a synthesis response. |

## Models And Output

| Web feature | Upstream evidence | iOS status | Notes |
| --- | --- | --- | --- |
| Model list from API | `src/api/chat/client.ts` | Implemented | Ranked native model picker pulls `/v1/model/list`. |
| Prioritize strong reasoning/frontier models | User requirement plus model metadata | Implemented | GPT-5.5, Claude Opus/Sonnet, GPT-5.4, Gemini, Qwen/DeepSeek aliases are elevated; o3/mini/lite/flash are demoted. |
| Web search tool | `src/pages/ChatController.tsx` | Implemented | Sends `tools: [{ type: "web_search" }]` and includes source paths when enabled. |
| Formatted Markdown output | `src/lib/markdown.ts`, `src/lib/utils/marked-katex-extension.ts` | Partial | Headings, bullets, quotes, code, tables, and selectable text are native. KaTeX/math rendering is not yet native. |
| System prompt / advanced params | `src/components/common/dialogs/settings/GeneralSettings.tsx`, `src/types/index.ts` | Implemented | iOS syncs system prompt, web-search default, `temperature`, `top_p`, and `max_tokens` through `/users/me/settings` and sends them with responses. |
| Reasoning/web-search status events | `src/api/base-client.ts` | Implemented | Native status labels show reasoning/searching and source chips. |

## Files And Attachments

| Web feature | Upstream evidence | iOS status | Notes |
| --- | --- | --- | --- |
| File upload to `/files` | `src/api/chat/client.ts`, `src/components/chat/MessageInput.tsx` | Implemented | Native file importer uploads multipart `purpose=user_data` and sends `input_file`. |
| Delete uploaded file | `src/api/chat/client.ts`, `src/components/chat/MessageInput.tsx` | Implemented | Native file library exposes explicit `DELETE /v1/files/{id}` so removing a prompt/project reference does not delete the underlying file by accident. |
| 10 MB upload cap | `src/components/chat/MessageInput.tsx` | Implemented | Native uploader rejects files over 10 MB. |
| Drag/drop overlay | `src/components/chat/MessageInput.tsx` | Not applicable yet | iOS file picker covers native path; iPad drag/drop can be added separately. |
| Large pasted text as file | `src/components/chat/MessageInput.tsx`, `src/types/index.ts` | Implemented | Native detects large pasted text, uploads it as a `.txt` attachment, and syncs the `largeTextAsFile` setting. |
| Image paste/upload | `src/components/chat/MessageInput.tsx` | Aligned | Web explicitly says images are not supported yet, so iOS does not promise image upload. |
| File list/content viewer | `src/api/chat/client.ts` | Implemented | Native Project Context has a private file library backed by `/v1/files`, `/v1/files/{id}`, and `/v1/files/{id}/content`, with preview, attach-to-prompt, add-to-project, and delete actions. |

## Sharing And Collaboration

| Web feature | Upstream evidence | iOS status | Notes |
| --- | --- | --- | --- |
| Public read-only link | `src/components/chat/ShareConversationDialog.tsx` | Implemented | Native share sheet enables/disables public links and copies URL. |
| Read shared/public conversation | `src/pages/PublicConversationPage.tsx`, `src/pages/Home.tsx` | Implemented | Native Shared Link sheet loads readable conversations before or after sign-in. |
| Copy shared read-only chat | `src/pages/Home.tsx`, `src/pages/PublicConversationPage.tsx` | Implemented | Native shared preview exposes `Copy & Continue`. |
| Direct user sharing with read/write | `src/components/chat/ShareConversationDialog.tsx`, `src/types/index.ts` | Implemented | Native share sheet supports email/NEAR-account invites, read/write permission, access list, and removal. |
| Group sharing | `src/components/chat/ManageShareGroupsDialog.tsx` | Implemented | Native share sheet lists share groups, creates/edits/deletes reusable groups, previews members, and shares a conversation to a selected group. |
| Organization sharing | `src/components/chat/ShareConversationDialog.tsx` | Implemented | Native share sheet supports organization email patterns with read/write permission and removal. |
| Shared-with-me list | `src/api/chat/client.ts`, `src/pages/SharedPage.tsx` | Implemented | Native Shared With Me inbox calls `/v1/shared-with-me`, previews readable conversations, and supports copy-and-continue. |
| Write-access shared conversations | `src/pages/Home.tsx` | Implemented | Native shared previews carry `can_write`; writable shared chats expose Open Chat and continue through the normal composer, while read-only shares remain preview/clone-only. |
| Owner/author display | `src/pages/Home.tsx`, `src/types/index.ts` | Partial | Native decodes share owner for share settings, but messages do not show shared author metadata. |

## Organization, Settings, And Export

| Web feature | Upstream evidence | iOS status | Notes |
| --- | --- | --- | --- |
| Local/remote settings tabs | `src/components/common/dialogs/settings/SettingsDialog.tsx` | Partial | Native has account and security sheets; full General/Chats/About parity is missing. |
| Remote user settings | `src/api/users/client.ts`, `src/types/index.ts` | Partial | Native account sheet reads/saves system prompt and web search. Appearance and notifications are still missing. |
| Chat import from JSON | `src/components/common/dialogs/settings/ChatsSettings.tsx` | Implemented | Native Account settings imports NEAR Private Chat export JSON and legacy history JSON, creates imported conversations, and posts message batches to conversation items. |
| Download JSON/TXT/PDF | `src/components/chat/DownloadDropdown.tsx` | Implemented | Native can copy transcripts and export current chats as TXT, JSON, or paginated PDF files. |
| Archived chat export | `src/components/common/dialogs/archived-chats/ArchivedChatsModal.tsx` | Implemented | Native archived chats can be copied as JSON or exported as a JSON file through the iOS file exporter. |
| Offline cache | `src/lib/offlineCache.ts` | Partial | Native caches conversation list/projects locally, not full message history. |
| Subscriptions/plans and low-balance UX | `src/api/users/client.ts`, `src/components/chat/MessageInput.tsx` | Implemented | Native Account fetches `/v1/subscriptions/plans` and `/v1/subscriptions`, shows billing status, gates unavailable models, and surfaces payment/credit-required retry copy. |
| Admin/user management | `src/api/users/client.ts` | Not in mobile scope | Public web repo has admin endpoints; not appropriate for consumer iOS first pass unless requested. |

## Priority Queue

1. Remote settings with appearance, notifications, and fuller account/about parity.
2. KaTeX/math output rendering parity.
3. Shared author metadata in message rows.
4. iPad drag/drop polish for attachments.
