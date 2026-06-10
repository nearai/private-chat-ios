# Build 7 — Research-Program Overhaul Completion

Date: 2026-06-10
Program: `docs/product/2026-06-10-research-synthesis-build7-program.md` (the seven-lane plan distilled from the June-1 design program, claude-design kit, and copy audits).
Method: 4 parallel Codex workers (git worktrees) for the mechanical lanes + main-worktree lanes for the security/trust work, then adversarial review by 3 reviewers (Claude + 2 Codex) before ship.

## What shipped

| Lane | Delivered | By |
|---|---|---|
| Render == Export | PDF and DOCX now generate from the same `MarkdownBlock` AST the screen renders: tables stay tables, nested lists keep nesting + numbering, code keeps monospace, blockquotes/links/bold/italic survive, math source stays verbatim. A term-sheet answer exports with structure intact. | Codex (export) |
| Math rendering | New no-dependency `MathFormulaView` renders a LaTeX subset as real math — superscript/subscript, `\frac` as a stacked fraction with divider, `\sqrt`, Greek + relation symbols, `\text{}`, nesting to depth 3; anything unparsable falls back to a clean source card, never a code dump. Wired into block + inline markdown. | Codex (math) |
| Design tokens + a11y | `AppRadius`/`AppSpacing` scales; WCAG-AA text tokens (`actionPrimaryText` #005EA5, darkened proof greens/ambers — all ≥4.5:1 on light, unit-asserted); reusable `PrimaryButton`; SecurityView radius drift collapsed. | Codex (tokens) |
| Council answer tabs | After a council run settles: Synthesis | per-model | Sources tabs (Perplexity precedent), Synthesis splits the four canonical headings with Agreement/Disagreements/Next-step expandable chips, sources de-duped. Running batches keep the existing progress rows. | Codex (council) |
| Prompt/PII hardening | The composed user-preferences block is fenced before the wire (`PrivateChatMessageAPI.fencedUserInstruction`): BEGIN/END markers, an explicit lower-priority precedence statement, case/whitespace/unicode-insensitive forged-marker neutralization, a 6k cap; the advanced system-prompt field is capped at 4k at source. soul.md route-gated injection (identity private-route only) was already in place. | main |
| Trust copy | "Attestation refreshed." → "Proof refreshed."; attestation fetch errors routed through the failure-copy mapper. Canonical verification sentence and general-purpose auth positioning were already conformant. | main |

## Adversarial review (the reason this didn't ship broken)

Three reviewers attacked the diff in parallel. They **independently converged on one HIGH ship-blocker**: the math parser spun forever on a leading/orphan `^` or `_` (`$^2$`, `$$_x$$`) — reachable from *any* model answer containing stray math — hanging the render thread. The Claude reviewer proved it with a compiled harness. Fixed (loop bails on failure + the orphan marker is consumed so the index always advances + a script-chain cap + a 2k formula-length guard), with a regression test. Four MEDs also fixed (DOCX control-char corruption, fence case/unicode bypass) or deferred with rationale (DOCX per-list numId restart, PDF >1-page single-block pagination — fidelity refinements, not data loss for typical answers).

## Verification

- **534 unit tests green** (518 from build 6 + 16 new: export fidelity ×4, math parser + hang regression, council section/tab ×5, WCAG contrast + tokens ×2, prompt fencing ×3).
- **Simulator build** (`scripts/build-simulator.sh`) succeeds.
- **ReleaseGate R9** (offline layout gate) passes — now also exercises the math renderer via the markdownGallery demo.
- Visual proof at iPhone width: math renders as actual math (quadratic formula with √ + superscripts, inline `mc²`, Greek relations, summation); the list-render overlap regression introduced by the export refactor was caught in QA and fixed.

## The two steps that need you (unchanged from build 6)

1. **Live ReleaseGate** against production: `export NEAR_DEBUG_SESSION_TOKEN=… && scripts/release-gate.sh`. R4 now exercises the council tabs; R6 the export path; all of it gates the build before your device.
2. **Upload**: build 7 archive is at `build/Archives/NEARPrivateChat-20260610-b7-unsigned.xcarchive`; export/upload command per the build-6 completion report (GUI Xcode session or ASC API key).

## Deferred (tracked)

`brandBlue`→`actionPrimary` rename sweep (~156 sites; pure alias, zero visual change — the accessibility-critical contrast fix already landed); Dynamic-Type/44pt high-volume audit; DOCX numId restart; PDF single-block pagination; per-conversation background streaming; NEP-413 native signing; ChatStore decomposition. All are P1-mechanical or P2 in the research and none block device testing.
