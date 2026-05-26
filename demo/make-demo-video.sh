#!/usr/bin/env bash
set -euo pipefail

cat >&2 <<'EOF'
This script used to generate a synthetic narrated storyboard.
That is no longer part of the demo pipeline.

Use the real simulator capture flow instead:

  bash demo/record-supademo-raw.sh

Then import the raw recording into Supademo with:
- no AI voiceover
- no captions
- no hotspots
- no callout text
- no generated step text
- only trim, pacing, crop/zoom, and exports

See:
  review-artifacts/NEARPrivateChatIOS-supademo-one-cut-video-spec-2026-05-25.md
EOF

exit 2
