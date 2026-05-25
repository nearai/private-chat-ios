#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/demo/out"
BUILD_DIR="$ROOT_DIR/demo/build"
SCREENSHOT_DIR="$ROOT_DIR/review-artifacts/screenshots-2026-05-24-fresh"
LEGACY_SCREENSHOT_DIR="$ROOT_DIR/review-artifacts/screenshots"
VOICE="${NEAR_DEMO_TTS_VOICE:-Samantha}"
RATE="${NEAR_DEMO_TTS_RATE:-130}"
FINAL_MP4="$OUT_DIR/near-private-chat-demo.mp4"

bash "$ROOT_DIR/demo/preflight.sh"

mkdir -p "$OUT_DIR" "$BUILD_DIR/scenes" "$BUILD_DIR/audio" "$BUILD_DIR/text" "$BUILD_DIR/frames"
rm -f "$BUILD_DIR"/scenes/*.mp4 "$BUILD_DIR"/audio/* "$BUILD_DIR"/text/* "$BUILD_DIR"/frames/* "$BUILD_DIR/concat.txt" "$FINAL_MP4"

make_scene() {
  local scene_id="$1"
  local image="$2"
  local title="$3"
  local caption="$4"
  local narration="$5"
  local title_file="$BUILD_DIR/text/$scene_id-title.txt"
  local caption_file="$BUILD_DIR/text/$scene_id-caption.txt"
  local narration_file="$BUILD_DIR/text/$scene_id-vo.txt"
  local audio_file="$BUILD_DIR/audio/$scene_id.aiff"
  local frame_file="$BUILD_DIR/frames/$scene_id.png"
  local scene_file="$BUILD_DIR/scenes/$scene_id.mp4"
  local duration
  local padded_duration

  printf '%b\n' "$title" > "$title_file"
  printf '%b\n' "$caption" > "$caption_file"
  printf '%s\n' "$narration" > "$narration_file"

  say -v "$VOICE" -r "$RATE" -f "$narration_file" -o "$audio_file"
  duration="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$audio_file")"
  padded_duration="$(awk -v d="$duration" 'BEGIN { printf "%.3f", d + 0.70 }')"

  echo "Rendering $scene_id ($padded_duration s)"
  swift "$ROOT_DIR/demo/render-scene-frame.swift" "$image" "$frame_file" "$title_file" "$caption_file" "$scene_id"

  ffmpeg -hide_banner -loglevel error -y \
    -loop 1 -t "$padded_duration" -i "$frame_file" \
    -i "$audio_file" \
    -vf "format=yuv420p" \
    -map 0:v -map 1:a \
    -r 30 -c:v libx264 -profile:v high -pix_fmt yuv420p \
    -c:a aac -b:a 192k -shortest "$scene_file"

  printf "file '%s'\n" "$scene_file" >> "$BUILD_DIR/concat.txt"
}

make_scene \
  "S01" \
  "$LEGACY_SCREENSHOT_DIR/03-chat-thread.png" \
  "Private chat, with proof" \
  $'A real conversation with sources and a verification shield.\nPrivacy is visible before anyone opens settings.' \
  "NEAR Private Chat is an iOS app for private AI conversations with projects, sources, multiple models, agents, and verifiable proof of the private route behind an answer. This is a real chat. The model is visible at the top, and next to it is the shield. That shield is the key idea: privacy is not just copy in a settings page. It is something the app can show evidence for."

make_scene \
  "S02" \
  "$SCREENSHOT_DIR/01-home.png" \
  "Home is the workspace" \
  $'Private chat first. Projects, shared chats, archived work,\nand agent workflows stay close without taking over.' \
  "Home is private chat first. Projects, shared chats, archived chats, and agent workflows stay close, but the main job is simple: start from a workspace and ask. A project carries its own instructions, files, links, and saved notes, so every chat inside it starts with context instead of asking the user to paste the same material again."

make_scene \
  "S03" \
  "$SCREENSHOT_DIR/02-new-chat-composer.png" \
  "Control what the model can use" \
  $'Focus modes keep context explicit: Auto, Web, Files,\nLinks, or Research.' \
  "The composer is where the user controls context. Auto can decide, or the user can choose live web, project files, saved links, or research. For private work where sources matter, that choice is the product."

make_scene \
  "S04" \
  "$SCREENSHOT_DIR/07-project-context.png" \
  "Projects carry persistent context" \
  $'Files, links, instructions, and saved notes live with the project.\nThe user stops pasting the same material every time.' \
  "This is the project behind the chat. Files, links, instructions, and saved notes all live here. Add a document once, and future chats in the project can reason over it. Save a useful answer, and it becomes part of the workspace instead of disappearing into scrollback."

make_scene \
  "S05" \
  "$SCREENSHOT_DIR/03-model-picker.png" \
  "Model routing stays visible" \
  $'Pick a model, see plan and route context,\nand keep the decision close to the chat.' \
  "The model picker is plan-aware and private-route-aware. For normal work, pick a single model and move. The important thing is that model choice is visible without turning the app into a developer console."

make_scene \
  "S06" \
  "$SCREENSHOT_DIR/04-model-picker-council.png" \
  "Council compares models" \
  $'For important prompts, ask several models in parallel.\nComparison beats one answer pretending to be certainty.' \
  "For important prompts, Council mode asks several models in parallel. Same prompt, multiple models, side by side. The useful part is not just more text. It is seeing comparison before you make a decision."

make_scene \
  "S07" \
  "$LEGACY_SCREENSHOT_DIR/10-security-attestation.png" \
  "Attestation is the differentiator" \
  $'Route, model, nonce, timestamp, and raw evidence.\nProof of what answered, not a claim that the answer is true.' \
  "Back to the shield. This is the part that separates the app from a normal chat client. For private routes, the app can show a signed attestation report: route, model, nonce, timestamp, and raw evidence. It does not prove the answer is true. It proves what route and model produced it. Proof, not a promise."

make_scene \
  "S08" \
  "$LEGACY_SCREENSHOT_DIR/11-share-collaboration.png" \
  "Share and export safely" \
  $'Conversations can leave the app as shared work\nor as verified JSON for later checking.' \
  "When work needs to leave the app, it can leave as a shared conversation or as an export. The important format is verified JSON: the transcript plus the verification envelope. A separate verifier can check whether that transcript was changed after export."

make_scene \
  "S09" \
  "$SCREENSHOT_DIR/05-agent-workspace.png" \
  "Agent work uses the same context" \
  $'IronClaw starts from the project context, sources,\nand instructions instead of becoming a separate product.' \
  "For build and repo work, the same workspace can become an agent surface. IronClaw starts from the project context, the same sources, and the same instructions. It is not a separate product bolted on top. It is the execution layer for the private workspace."

make_scene \
  "S10" \
  "$LEGACY_SCREENSHOT_DIR/03-chat-thread.png" \
  "The loop" \
  $'Ask privately. Control context. Compare models. Verify the route.\nSave, share, or export when the work leaves the room.' \
  "The loop is straightforward: ask privately, control what the model can see, compare models when it matters, verify the route, save the work into a project, and share or export when it leaves the room. Private AI you can actually prove."

ffmpeg -hide_banner -loglevel error -y \
  -f concat -safe 0 -i "$BUILD_DIR/concat.txt" \
  -c copy "$FINAL_MP4"

echo "Wrote $FINAL_MP4"
