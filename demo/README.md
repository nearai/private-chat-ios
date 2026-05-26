# NEAR Private Chat Supademo Capture

This folder is for real simulator capture only.

Do not generate mock screens, narrated storyboards, captions, callouts, or text overlays. The demo must be the actual iOS simulator running the actual app.

Canonical spec:

```bash
review-artifacts/NEARPrivateChatIOS-supademo-one-cut-video-spec-2026-05-25.md
```

Run:

```bash
bash demo/record-supademo-raw.sh
```

Default raw output:

```bash
demo/out/near-private-chat-supademo-raw.mov
```

Import that raw video into Supademo and disable:

- AI voiceover
- captions
- hotspots
- callouts
- text annotations
- generated step text

Supademo should only trim, pace, subtly zoom/crop, and export landscape / portrait / square.

Optional local secrets for future live capture can go in `demo/.env.local`. Do not commit that file.

```bash
NEAR_DEMO_SESSION_TOKEN=...
NEAR_DEMO_NEAR_CLOUD_API_KEY=...
NEAR_DEMO_IRONCLAW_ENDPOINT=...
NEAR_DEMO_IRONCLAW_TOKEN=...
```
