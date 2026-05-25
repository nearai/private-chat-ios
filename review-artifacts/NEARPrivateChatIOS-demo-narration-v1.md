# NEAR Private Chat iOS Automated Demo Narration v1

Target runtime: 4:45-5:30
Capture style: one-shot automated simulator recording driven by seeded demo data and UI automation
Voice register: founder demo, quiet and declarative

This file is designed for Codex/Claude to turn into:
- `demo/shot-list.md`
- `demo/narration.txt`
- `DemoVideoUITests.swift`
- `demo/make-demo-video.sh`

No manual cutting should be required. Each scene has a deterministic UI action, a hold duration, and narration text. If a live network-dependent beat is unreliable, use seeded/preloaded demo state rather than recording a live wait.

## Demo Positioning

One-line:

> NEAR Private Chat is a private AI workspace for iOS where chats use project context, compare models, run agents, and ship with verifiable proof of the route that produced each answer.

Core story:

1. Private chat is the base.
2. Projects provide persistent context.
3. Focus modes control what the model can use.
4. Council compares models when a prompt matters.
5. Attestation proves the private route/model.
6. Sharing/export preserves the work.
7. IronClaw turns the same workspace into an agent surface.

Do not present it as three separate products. Present it as one private workspace with deeper layers.

## Demo Data Required

Seed this before capture:

- Project: `Acme Launch Review`
- Project files:
  - `launch-brief.pdf`
  - `risk-table.csv`
- Project link:
  - `Acme market memo`
- Project instruction:
  - `Prioritize privacy, cite source material, and call out launch risks clearly.`
- Chat 1:
  - Title: `Launch risk summary`
  - One user prompt
  - One completed assistant answer
  - Sources visible
  - Valid attestation snapshot less than 2 minutes old, or a deterministic demo attestation state
- Chat 2:
  - Title: `Council launch review`
  - One completed Council response with 3-4 model answers and a synthesis/disagreement summary
- Share state:
  - Share screen has invite/public/export affordances visible
  - Do not require enabling a live public link during capture
- Agent state:
  - IronClaw Agent workspace visible
  - Skills/status/context strip populated
  - Do not require a live agent run during capture

Hide during demo mode:
- QA project names
- Endpoint URLs
- Callback URLs
- Session tokens
- Bridge tokens
- Raw diagnostics unless explicitly inside Security/Attestation
- Developer settings by default

## Required Demo Configuration And Preflight

The demo generator must fail before recording if required configuration is missing. Do not let the app limp into the video with missing keys, empty model lists, auth prompts, disabled routes, or blank seeded data.

Required local config:

- Signed-in/demo session available before recording starts.
- NEAR Cloud API key installed if any NEAR Cloud route/model appears in the demo.
- Private route available for the attestation scenes.
- At least one model available for normal chat.
- Council lineup available with 3-4 usable seeded model answers.
- Project files and links seeded.
- Share/export screen reachable.
- Agent workspace reachable, even if live agent execution is not run.

Recommended local secret inputs for the automation:

```bash
NEAR_DEMO_SESSION_TOKEN=...
NEAR_DEMO_NEAR_CLOUD_API_KEY=...
NEAR_DEMO_IRONCLAW_ENDPOINT=...
NEAR_DEMO_IRONCLAW_TOKEN=...
```

Store these in `demo/.env.local` or a local keychain-backed setup step. Never commit them. Never show them in the simulator recording. The video script should print only pass/fail status, not secret values.

NEAR Cloud key handling:

- The app currently stores the NEAR Cloud key in Keychain via Account -> NEAR Cloud.
- For the automated demo, Codex should add a demo-safe setup path that reads `NEAR_DEMO_NEAR_CLOUD_API_KEY` and saves it through the same app/keychain path before capture.
- If the key is missing and the video uses NEAR Cloud, stop with a clear error:

```text
Missing NEAR_DEMO_NEAR_CLOUD_API_KEY. Add it to demo/.env.local or remove NEAR Cloud scenes from the demo.
```

- Do not open Account and paste the key during recording.
- Do not show the NEAR Cloud key field during recording.
- Do not rely on manually saved simulator state unless the preflight verifies it.

Preflight checklist the script should run before `recordVideo`:

1. Boot simulator and install app.
2. Launch in demo mode.
3. Verify signed-in/demo session.
4. Verify seeded project exists: `Acme Launch Review`.
5. Verify seeded files exist: `launch-brief.pdf`, `risk-table.csv`.
6. Verify seeded chat exists: `Launch risk summary`.
7. Verify seeded Council chat exists: `Council launch review`.
8. Verify selected private model is available.
9. Verify attestation demo state or fresh attestation snapshot is available.
10. Verify NEAR Cloud key is configured if a Cloud model appears in any demo scene.
11. Verify Share screen can open.
12. Verify Agent workspace can open.
13. Verify no secret-bearing UI is visible in the starting scene.

Fail fast if any check fails. A failed preflight is better than a polished video of broken state.

Route rule:

- Use a NEAR Private model for the attestation scene.
- Use NEAR Cloud only if the key is configured and the route is part of the story.
- Do not imply NEAR Cloud is covered by the same private-route attestation. If shown, treat it as a separate model route.

## Timing Table

| Scene | Time | Screen | Hold |
| --- | --- | --- | --- |
| S01 | 0:00-0:22 | Existing chat with answer, source chip, attestation shield | 5s |
| S02 | 0:22-0:55 | Home and selected project | 6s |
| S03 | 0:55-1:35 | New chat composer and Focus row | 8s |
| S04 | 1:35-2:15 | Project Context / Files / Instructions | 8s |
| S05 | 2:15-2:55 | Model picker and Council tab | 8s |
| S06 | 2:55-3:30 | Preloaded Council response | 8s |
| S07 | 3:30-4:10 | Security and Attestation sheet | 10s |
| S08 | 4:10-4:42 | Share and verified export | 8s |
| S09 | 4:42-5:12 | Agent workspace | 8s |
| S10 | 5:12-5:30 | Return to chat with shield | 5s |

The UI test should pause on each scene long enough for the narration. If using TTS, generate audio first and let scene holds be adjusted from narration length plus 0.5-1.0s padding.

## Narration Script

### S01: Hook

Screen:
- Open directly inside `Launch risk summary`
- Assistant answer visible
- Source chip visible
- Model chip and attestation shield visible

VO:

> NEAR Private Chat is an iOS app for private AI conversations with projects, sources, multiple models, agents, and verifiable proof of the private route behind an answer.

> This is a real chat. The model is visible at the top, and next to it is the shield. That shield is the key idea: privacy is not just copy in a settings page. It is something the app can show evidence for.

Automation:
- Start recording here, not on auth/setup.
- Hold on the shield for one beat before navigating back.

### S02: Home

Screen:
- Navigate back to Home
- Show `Acme Launch Review`
- Select the project if not already selected

VO:

> Home is private chat first. Projects, shared chats, archived chats, and agent workflows stay close, but the main job is simple: start from a workspace and ask.

> A project carries its own instructions, files, links, and saved notes. So every chat inside it starts with context instead of asking the user to paste the same material again.

Automation:
- Do not open Account.
- Do not show Developer settings.
- Do not dwell on every chip.

### S03: Composer And Focus Modes

Screen:
- Open a new chat inside `Acme Launch Review`
- Show empty prompt suggestions
- Show Focus row: Auto, Web, Files, Links, Research
- Tap `Files`
- Fill draft with the demo prompt

Demo prompt:

```text
Using this project's files, summarize the launch risks and cite the source documents.
```

VO:

> The composer is where the user controls context. Auto can decide, or the user can choose live web, project files, saved links, or research.

> For this prompt, we choose Files. The model is constrained to the project material, which is what you want for private work where sources matter.

Automation:
- Prefer a preloaded/seeded response after sending.
- If live streaming is unreliable, type the prompt, tap send, hold for 1-2 streaming tokens, then navigate to the preloaded completed chat.
- Do not wait on a long live model response during recording.

### S04: Project Context

Screen:
- Open Project Context
- Show sources/files/instructions/notes area
- Show `launch-brief.pdf` and `risk-table.csv`
- Show project instruction if available

VO:

> This is the project behind the chat. Files, links, instructions, and saved notes all live here.

> Add a document once, and future chats in the project can reason over it. Save a useful answer, and it becomes part of the workspace instead of disappearing into scrollback.

Automation:
- If current tabs still read `Sources / Library / Guide / Saved`, show them but do not mention those exact labels in VO.
- Do not delete or upload files during recording.

### S05: Model Picker

Screen:
- Open model picker from model chip
- Show Models tab
- Switch to Council tab

VO:

> The model picker is plan-aware and private-route-aware. For normal work, pick a single model and move.

> For important prompts, Council mode asks several models in parallel. That gives you comparison instead of a single answer pretending to be certainty.

Automation:
- Do not scroll through the entire model list.
- Hold briefly on Council lineup.

### S06: Council Response

Screen:
- Open `Council launch review` or navigate to a preloaded Council response
- Show multiple model answer chips/tabs
- Show synthesis/disagreement if available

VO:

> Here is the Council result. Same prompt, multiple models, side by side.

> The useful part is not just more text. It is seeing where the models agree, where they disagree, and what a synthesis looks like after that comparison.

Automation:
- This must be preloaded.
- Do not run Council live during video capture.
- If disagreement UI is not implemented yet, show grouped model answers and say "comparison" rather than "disagreement report."

### S07: Security And Attestation

Screen:
- Tap shield
- Open Security sheet
- Show route/model status
- Show timestamp, nonce, model hash or raw report disclosure
- Show education copy if visible

VO:

> Back to the shield. This is the part that separates the app from a normal chat client.

> For private routes, the app can show a signed attestation report: route, model, nonce, timestamp, and raw evidence. It does not prove the answer is true. It proves what route and model produced it.

> That distinction matters. This is proof, not a promise.

Automation:
- Use seeded attestation state.
- Do not fetch attestation live during capture unless it is already known fast and reliable.
- Hold long enough for timestamp/nonce/model fields to be readable.

### S08: Share And Verified Export

Screen:
- Open Share or overflow/export surface
- Show public link/invite controls
- Show `Export Verified JSON` if accessible

VO:

> When work needs to leave the app, it can leave as a shared conversation or as an export.

> The important format is verified JSON: the transcript plus the verification envelope. A separate verifier can check whether that transcript was changed after export.

Automation:
- Do not enable a public link live unless the safety preview is implemented.
- If export UI is behind overflow, show the menu and hold on `Export Verified JSON`.
- Do not expose recipient emails or private account data.

### S09: Agent Workspace

Screen:
- Open Agent workspace
- Show Start an Agent
- Show Skills/status/context strip
- Show project context if visible

VO:

> For build and repo work, the same workspace can become an agent surface. IronClaw starts from the project context, the same sources, and the same instructions.

> It is not a separate product bolted on top. It is the execution layer for the private workspace.

Automation:
- Do not start a live agent run.
- Show a prepared result only if it is already seeded and stable.
- Avoid showing bridge URLs, tokens, or diagnostics.

### S10: Close

Screen:
- Return to chat
- Assistant answer visible
- Source chip visible
- Attestation shield visible

VO:

> The loop is straightforward: ask privately, control what the model can see, compare models when it matters, verify the route, save the work into a project, and share or export when it leaves the room.

> Private AI you can actually prove.

Automation:
- End on chat answer plus shield.
- Hold 1s after final line before stopping recording.

## TTS Version

If generating voiceover from this file, use only the `VO:` text blocks. Exclude all headings, automation notes, and bracketed implementation comments.

Recommended macOS fallback:

```bash
say -v Samantha -r 155 -f demo/narration.txt -o demo/out/narration.aiff
```

Better voiceover can use any TTS provider, but the video generator should work with macOS `say` without API keys.

## Automation Guardrails

- Run the Required Demo Configuration And Preflight checks before recording starts.
- Do not start `xcrun simctl io booted recordVideo` until preflight passes.
- Do not continue if the NEAR Cloud key is missing and the selected script includes NEAR Cloud.
- Do not continue if the app launches to auth, setup, empty home, empty model picker, or a missing project.
- The capture must not depend on a successful live model response.
- The capture must not depend on a successful live attestation fetch.
- The capture must not depend on a successful live agent run.
- Use seeded data for all high-variance moments.
- No auth screen in the final recording.
- No setup wizard in the final recording.
- No developer settings in the final recording.
- No tokens, endpoints, callback URLs, bridge URLs, or diagnostics outside the Security sheet.
- If a screen fails to open, fail the automation instead of recording a bad fallback.

Suggested script behavior:

```bash
bash demo/preflight.sh
bash demo/make-demo-video.sh
```

`demo/make-demo-video.sh` should call `demo/preflight.sh` internally too, so the user cannot accidentally skip it.

## UI Test Accessibility Labels Needed

Add or verify stable labels for:

- `demo.chat.thread`
- `demo.home`
- `demo.project.acmeLaunchReview`
- `demo.newChat`
- `demo.focus.auto`
- `demo.focus.web`
- `demo.focus.files`
- `demo.focus.links`
- `demo.focus.research`
- `demo.projectContext`
- `demo.modelPicker`
- `demo.modelPicker.models`
- `demo.modelPicker.council`
- `demo.councilResponse`
- `demo.attestationShield`
- `demo.securitySheet`
- `demo.shareSheet`
- `demo.exportVerifiedJSON`
- `demo.agentWorkspace`

If adding labels is too invasive, the UI test can use visible text, but labels will make the one-shot video far less brittle.

## Fallback Lines

Use these only if the automation needs a seeded fallback scene:

Council fallback:

> Council runs multiple models in parallel. This saved run shows the comparison without waiting on live inference during capture.

Attestation fallback:

> The attestation is preloaded for the demo so the video shows the report instead of waiting on a network request.

Agent fallback:

> Agent runs are intentionally shown from the workspace here; live execution can be recorded separately once the bridge is connected.

## Cut-Down Variants

These are for future automated exports, not manual editing.

30-second trailer:
- S01 Hook
- S06 Council response
- S07 Security
- S10 Close

90-second overview:
- S01 Hook
- S03 Composer
- S06 Council response
- S07 Security
- S10 Close

3-minute product demo:
- S01 Hook
- S02 Home
- S03 Composer
- S04 Project Context
- S06 Council response
- S07 Security
- S10 Close
