#!/usr/bin/env bash
# Renders a per-scenario pass/fail/skip table from a ReleaseGate xcresult and
# exports the scenario screenshots. Usage: release-gate-report.sh <bundle.xcresult>
set -euo pipefail

BUNDLE="${1:?Usage: release-gate-report.sh <bundle.xcresult>}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/build/ReleaseGate"
mkdir -p "$OUT_DIR"

SUMMARY="$OUT_DIR/summary.md"

xcrun xcresulttool get test-results tests --path "$BUNDLE" 2>/dev/null | python3 - "$SUMMARY" <<'EOF'
import json
import sys

summary_path = sys.argv[1]
data = json.load(sys.stdin)

rows = []
def walk(node):
    if node.get("nodeType") == "Test Case" and node.get("name", "").startswith("testR"):
        result = node.get("result", "?")
        detail = ""
        for child in node.get("children", []):
            if child.get("nodeType") in ("Failure Message", "Skip Message"):
                detail = child.get("name", "")[:140]
                break
        rows.append((node["name"], result, detail))
    for child in node.get("children", []):
        walk(child)

for node in data.get("testNodes", []):
    walk(node)

icon = {"Passed": "PASS", "Failed": "FAIL", "Skipped": "SKIP", "Expected Failure": "XFAIL"}
lines = ["# ReleaseGate summary", "", "| Scenario | Result | Detail |", "|---|---|---|"]
for name, result, detail in sorted(rows):
    lines.append(f"| {name} | {icon.get(result, result)} | {detail} |")
if not rows:
    lines.append("| (no ReleaseGate scenarios found in bundle) | — | |")

report = "\n".join(lines)
print(report)
with open(summary_path, "w") as fh:
    fh.write(report + "\n")

failed = [r for r in rows if r[1] == "Failed"]
sys.exit(1 if failed else 0)
EOF
REPORT_STATUS=$?

# Export screenshot attachments (best-effort).
SHOTS="$OUT_DIR/screenshots/$(basename "$BUNDLE" .xcresult)"
mkdir -p "$SHOTS"
xcrun xcresulttool export attachments --path "$BUNDLE" --output-path "$SHOTS" >/dev/null 2>&1 || true
echo "Screenshots: $SHOTS"
echo "Summary: $SUMMARY"
exit $REPORT_STATUS
