#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cat >&2 <<'EOF'
demo/make-demo-video.sh is now a compatibility wrapper.
The narrated storyboard generator was removed; running the real simulator capture instead.
EOF

exec bash "$ROOT_DIR/demo/record-supademo-raw.sh" "$@"
