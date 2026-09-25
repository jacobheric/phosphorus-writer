# Phosphorus Writer

A native macOS Markdown editor for reviewing and revising prose in the same window.

## Stack

Swift, SwiftUI for window structure, AppKit NSTextView with TextKit 2 for editing. Use installed Git through background processes. Plain Markdown remains the source of truth.

## Build phases

1. Validate the editor with synthetic prose: typography, word-level changes, pure deletions, navigation, direct editing, and undoable restoration. Open a Markdown file into memory and save a copy. Compare against an independently chosen original file.
2. Add a chapter sidebar, atomic saves, recovery drafts, external-change detection, and Git baselines. Support index versus working tree, HEAD versus index, and previous committed chapter versions. Stage whole chapters, review the exact staged snapshot, commit, and push outgoing commits.
3. Add partial-hunk staging, project search, richer Markdown styling, and optional side-by-side comparison.

## Git rules

Pending means working content differs from the index. Staged is a fixed snapshot; later typing must not silently restage it. Commits are local history; pushes publish commits, not selected files. Show unrelated staged files before a commit. Serialize writes and check repository state before applying operations. Never force-push or rewrite history automatically.

## Safety and performance

Preserve whitespace, line endings, and Markdown source. Unchanged open/save must produce no diff. Save atomically and keep a recovery draft. Detect external writes before overwriting. Keep Git and diff computation off the typing path, debounce review, and reject stale results. Validate Unicode ranges, selection, undo, deletion anchors, and long paragraphs.

## Local and cloud work

Native UI builds and interaction testing run on macOS. Portable Swift review logic and Git parsing can run in cloud tasks after a Swift toolchain is configured. Use synthetic fixtures in this repository; do not copy the private manuscript here. Agree on interfaces before assigning independent cloud work.

## Prototype limits

The first prototype is not the daily-use editor. It has no autosave, recovery, Git integration, or external-file monitoring. Open loads a draft into memory; Save copy exports it. Review compares with the opened file or a chosen original. The sample deliberately includes replacements and a deletion.

## Review layout decision

Use a unified comparison inspired by Fork: original paragraphs in red above current editable paragraphs in green, with stronger word-level highlights. Use Charter and comfortable spacing with bounded reading width. Keep the source buffer separate from the display projection so labels and old text never enter saved Markdown. Protected-region selections require switching to clean editing for broad edits. The current prototype rebuilds this projection synchronously; incremental rendering and native composition/undo grouping need validation before daily use.
