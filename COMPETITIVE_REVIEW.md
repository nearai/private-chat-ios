# Competitive Review: Private Chat iOS

Date: 2026-05-22

## What The Best Apps Converge On

Comparable apps are no longer just chat, model picker, and history. The strongest pattern is a durable workspace: project instructions, reusable files, source controls, collaboration, search, and a side surface for reusable outputs.

## Comparison

| App | Strong pattern | NEAR Private Chat iOS status | Improvement |
| --- | --- | --- | --- |
| ChatGPT | Projects group chats, files, project instructions, memory, sharing, Canvas, voice, web search, deep research, image tools, and branch chats. | Projects, files, web search, sharing links, and model routing exist. Project instructions were missing. | Add durable project instructions, then project memory/summaries and branch/regenerate UI. |
| Claude | Projects have a knowledge base plus project instructions; Artifacts move substantial documents/code/apps into a dedicated editable surface. | Project files exist; output remains only inline chat. | Add an artifact/output drawer for long Markdown/code/tables, with versioning/export. |
| Perplexity | Spaces combine custom instructions, file search, web/link/source selection, collaborators, pinned assets, and task modes. | Web search is global; project files are reused, but source selection and project search are thin. | Add project source controls: Web, Files, Links, Web + Files, plus pinned source links. |
| Venice | Privacy-positioned multi-model studio: chat, image/video/audio/code, characters, system prompt, document upload, temperature/top-p, API, and visible privacy tiers. | Privacy/TEE is a NEAR advantage, advanced params exist, chat-only app is focused. | Make privacy tiers and model capability tiers clearer; avoid exposing weak/denied models. |
| Gemini | Deep Research, Canvas, Gems, Google Workspace sources, file uploads, and research reports. | Web search and files exist, but no explicit research workflow or report artifact. | Add a Research mode that plans, searches, cites, and saves a report artifact. |
| Mistral Le Chat | Agents, project folders, enterprise search, document libraries, connectors, web search, OCR, audio input, and deploy/control story. | IronClaw Mobile exists, project buckets exist, no connectors/OCR/audio. | Make IronClaw a visible phone-native agent mode with clear available actions, then add OCR/audio ingestion. |

## Priority Queue

1. Project instructions and workspace context.
   - Shipped: each local project can store instructions, memory, files, and saved outputs, and model calls receive that context with the global system prompt.

2. Source controls per prompt/project.
   - Shipped: the composer now has Auto, Web, Links, Files, and Web + Files source modes.
   - Shipped: projects now support reusable source links alongside uploads.
   - Shipped: active context is mode-aware, so Web no longer silently includes saved links, Saved links does not imply project files, and the composer shows only the context that will actually be sent.

3. Artifact drawer.
   - Shipped: long docs, tables, code, and reports open in a full-screen output sheet with copy and save-to-project actions.
   - Shipped: assistant responses also have inline copy, regenerate, save, and open actions.
   - Next: add versioning and export.

4. Project memory without waiting on backend.
   - Shipped: project memory can be edited locally, assistant responses can be saved as project notes, and both are included in project-scoped prompts.

5. Research mode.
   - Shipped: a visible composer research mode now forces web-capable source behavior and adds report-style answer guidance with date stamps and source handling.
   - Save the result into the project as a reusable note.

6. Collaboration parity.
   - Build shared-with-me inbox, read/write grants, group/org sharing, and project sharing when APIs allow it.

7. Multimodal ingestion.
   - Shipped: readable PDFs are extracted to text before upload; small text, Markdown, CSV, and JSON files work as prompt or project context.
   - OCR scanned PDFs/images locally when possible.
   - Add audio upload/transcription once a private route exists.

## Sources

- ChatGPT Projects: https://help.openai.com/en/articles/10169521-using-projects-in-chatgpt
- Claude Projects: https://support.claude.com/en/articles/9517075-what-are-projects
- Claude Artifacts: https://support.claude.com/en/articles/9487310-what-are-artifacts-and-how-do-i-use-them
- Perplexity Spaces: https://www.perplexity.ai/help-center/en/articles/10352961-what-are-spaces/
- Venice AI features: https://venice.ai/features
- Venice API overview: https://docs.venice.ai/overview/about-venice
- Gemini Deep Research: https://support.google.com/gemini/answer/15719111
- Mistral Le Chat: https://mistral.ai/products/le-chat
