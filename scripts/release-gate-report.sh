#!/usr/bin/env bash
# Renders a per-scenario pass/fail/skip table from a ReleaseGate xcresult and
# exports the scenario screenshots. Usage: release-gate-report.sh <bundle.xcresult>
set -euo pipefail

BUNDLE="${1:?Usage: release-gate-report.sh <bundle.xcresult>}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/build/ReleaseGate"
mkdir -p "$OUT_DIR"

SUMMARY="$OUT_DIR/summary.md"
TESTS_JSON="$(mktemp)"
trap 'rm -f "$TESTS_JSON"' EXIT

set +e
xcrun xcresulttool get test-results tests --path "$BUNDLE" > "$TESTS_JSON"
XCTESTS_STATUS=$?
set -e
if [[ $XCTESTS_STATUS -ne 0 ]]; then
  echo "release-gate-report: failed to read test results from $BUNDLE" >&2
  XCTESTS_STATUS=1
fi

set +e
python3 - "$SUMMARY" "$TESTS_JSON" <<'EOF'
import json
import sys

summary_path = sys.argv[1]
tests_json_path = sys.argv[2]
with open(tests_json_path) as fh:
    data = json.load(fh)

rows = []
def walk(node):
    if node.get("nodeType") == "Test Case" and node.get("name", "").startswith("testR"):
        result = node.get("result", "?")
        duration = node.get("duration") or ""
        detail = ""
        for child in node.get("children", []):
            if child.get("nodeType") in ("Failure Message", "Skip Message"):
                detail = child.get("name", "")[:140]
                break
        rows.append((node["name"], result, duration, detail))
    for child in node.get("children", []):
        walk(child)

for node in data.get("testNodes", []):
    walk(node)

icon = {"Passed": "PASS", "Failed": "FAIL", "Skipped": "SKIP", "Expected Failure": "XFAIL"}
lines = ["# ReleaseGate summary", "", "| Scenario | Result | Duration | Detail |", "|---|---|---:|---|"]
for name, result, duration, detail in sorted(rows):
    lines.append(f"| {name} | {icon.get(result, result)} | {duration} | {detail} |")
if not rows:
    lines.append("| (no ReleaseGate scenarios found in bundle) | FAIL | | The bundle contains no testR* scenarios. This usually means the selector was wrong or no tests ran. |")

report = "\n".join(lines)
print(report)
with open(summary_path, "w") as fh:
    fh.write(report + "\n")

failed = [r for r in rows if r[1] == "Failed"]
skipped = [r for r in rows if r[1] == "Skipped"]
fail_on_skip = bool(int(__import__("os").environ.get("RELEASE_GATE_FAIL_ON_SKIP", "0")))
sys.exit(1 if failed or not rows or (fail_on_skip and skipped) else 0)
EOF
REPORT_STATUS=$?
set -e
if [[ $XCTESTS_STATUS -ne 0 ]]; then
  REPORT_STATUS=$XCTESTS_STATUS
fi

# Export screenshot attachments (best-effort).
SHOTS="$OUT_DIR/screenshots/$(basename "$BUNDLE" .xcresult)"
mkdir -p "$SHOTS"
xcrun xcresulttool export attachments --path "$BUNDLE" --output-path "$SHOTS" >/dev/null 2>&1 || true
echo "Screenshots: $SHOTS"
echo "Summary: $SUMMARY"
exit $REPORT_STATUS
