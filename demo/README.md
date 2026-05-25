# NEAR Private Chat Demo Video

This folder generates a narrated demo MP4 without manual editing.

Current mode: screenshot-driven simulation video using the latest clean app screenshots plus seeded narration.

Run:

```bash
bash demo/make-demo-video.sh
```

Output:

```bash
demo/out/near-private-chat-demo.mp4
```

Optional local secrets for future live capture can go in `demo/.env.local`. Do not commit that file.

```bash
NEAR_DEMO_SESSION_TOKEN=...
NEAR_DEMO_NEAR_CLOUD_API_KEY=...
NEAR_DEMO_IRONCLAW_ENDPOINT=...
NEAR_DEMO_IRONCLAW_TOKEN=...
```

The screenshot simulation does not require these secrets. A future live simulator/UI-test capture should call `demo/preflight.sh` before recording.

