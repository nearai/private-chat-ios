#!/usr/bin/env python3
"""Register Swift files in NEARPrivateChat.xcodeproj (manual membership repo).

Usage:
  python3 scripts/pbxproj-add.py <relative-file-path> [<sibling-file-name>]

The file is inserted next to a SIBLING already registered in the same group
and the same Sources build phase. If sibling is omitted, the first .swift file
already registered from the same directory is used.
"""
import re
import secrets
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PBX = ROOT / "NEARPrivateChat.xcodeproj" / "project.pbxproj"


def fresh_uuid(existing: set) -> str:
    while True:
        candidate = "BA" + secrets.token_hex(11).upper()
        if candidate not in existing:
            existing.add(candidate)
            return candidate


def main() -> int:
    rel_path = sys.argv[1]
    file_name = Path(rel_path).name
    directory = Path(rel_path).parent

    text = PBX.read_text()
    if re.search(rf"/\* {re.escape(file_name)} \*/ = \{{isa = PBXFileReference", text):
        print(f"already registered: {file_name}")
        return 0

    sibling = sys.argv[2] if len(sys.argv) > 2 else None
    if sibling is None:
        for candidate in sorted((ROOT / directory).glob("*.swift")):
            if candidate.name != file_name and f"/* {candidate.name} */ = {{isa = PBXFileReference" in text:
                sibling = candidate.name
                break
    if sibling is None:
        print(f"ERROR: no registered sibling found in {directory}")
        return 1

    sibling_ref = re.search(
        rf"([0-9A-F]{{24}}) /\* {re.escape(sibling)} \*/ = \{{isa = PBXFileReference", text
    )
    sibling_build = re.search(
        rf"([0-9A-F]{{24}}) /\* {re.escape(sibling)} in Sources \*/ = \{{isa = PBXBuildFile", text
    )
    if not sibling_ref or not sibling_build:
        print(f"ERROR: sibling {sibling} not fully registered")
        return 1

    existing = set(re.findall(r"[0-9A-F]{24}", text))
    ref_id = fresh_uuid(existing)
    build_id = fresh_uuid(existing)

    # 1. PBXBuildFile — insert directly after the sibling's build-file line.
    sib_build_line = re.search(
        rf"\t\t{sibling_build.group(1)} /\* {re.escape(sibling)} in Sources \*/ = .*?;\n", text
    ).group(0)
    new_build_line = (
        f"\t\t{build_id} /* {file_name} in Sources */ = "
        f"{{isa = PBXBuildFile; fileRef = {ref_id} /* {file_name} */; }};\n"
    )
    text = text.replace(sib_build_line, sib_build_line + new_build_line, 1)

    # 2. PBXFileReference — after the sibling's reference line.
    sib_ref_line = re.search(
        rf"\t\t{sibling_ref.group(1)} /\* {re.escape(sibling)} \*/ = .*?;\n", text
    ).group(0)
    new_ref_line = (
        f"\t\t{ref_id} /* {file_name} */ = {{isa = PBXFileReference; "
        f"lastKnownFileType = sourcecode.swift; path = {file_name}; sourceTree = \"<group>\"; }};\n"
    )
    text = text.replace(sib_ref_line, sib_ref_line + new_ref_line, 1)

    # 3. Group children — after the sibling's child entry.
    sib_child_line = re.search(
        rf"\t\t\t\t{sibling_ref.group(1)} /\* {re.escape(sibling)} \*/,\n", text
    ).group(0)
    new_child_line = f"\t\t\t\t{ref_id} /* {file_name} */,\n"
    text = text.replace(sib_child_line, sib_child_line + new_child_line, 1)

    # 4. Sources phase — after the sibling's phase entry.
    sib_phase_line = re.search(
        rf"\t\t\t\t{sibling_build.group(1)} /\* {re.escape(sibling)} in Sources \*/,\n", text
    ).group(0)
    new_phase_line = f"\t\t\t\t{build_id} /* {file_name} in Sources */,\n"
    text = text.replace(sib_phase_line, sib_phase_line + new_phase_line, 1)

    PBX.write_text(text)
    print(f"registered {file_name} (ref {ref_id}, build {build_id}) next to {sibling}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
