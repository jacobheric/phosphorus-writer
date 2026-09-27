# Phosphorus

A native macOS Markdown editor for reviewing and revising prose in the same window.

## Stack

Swift, SwiftUI for window structure, AppKit NSTextView with TextKit 2 for editing. Use installed Git through background processes. Plain Markdown remains the source of truth.

## Build phases

1. Validate the editor with synthetic prose: typography, word-level changes, pure deletions, navigation, direct editing, and undoable restoration. Open a Markdown file into memory and save a copy. Compare against an independently chosen original file.
2. Add a chapter sidebar, atomic saves, recovery drafts, external-change detection, and Git baselines. Support index versus working tree, HEAD versus index, and previous committed chapter versions. Stage whole chapters, review the exact staged snapshot, commit, and push outgoing commits.
3. Add partial-hunk staging, project search, richer Markdown styling, and optional side-by-side comparison.

## Git rules

Changes mean working content differs from the last local commit. Staging stays an internal Git detail. Review and commit a hunk, a chapter, or all repository changes; only committed changes leave the reading diff. Commits are local history; pushes publish commits. Serialize writes and check repository state before applying operations. Preserve unrelated staged work and reject conflicting same-file staging during hunk commits. Never force-push or rewrite history automatically.

## Safety and performance

Preserve whitespace, line endings, and Markdown source. Unchanged open/save must produce no diff. Save atomically and keep a recovery draft. Detect external writes before overwriting. Keep Git and diff computation off the typing path, debounce review, and reject stale results. Validate Unicode ranges, selection, undo, deletion anchors, and long paragraphs.

## Local and cloud work

Native UI builds and interaction testing run on macOS. Portable Swift review logic and Git parsing can run in cloud tasks after a Swift toolchain is configured. Use synthetic fixtures in this repository; do not copy the private manuscript here. Agree on interfaces before assigning independent cloud work.

## Prototype limits

The prototype has no autosave, recovery, or external-file monitoring. Save checks the loaded disk snapshot before an atomic write. Review compares with the last local commit or a chosen original. The sample deliberately includes replacements and a deletion.

## Review layout decision

Use a unified comparison inspired by Fork: original paragraphs in red above current editable paragraphs in green, with stronger word-level highlights. Use Charter and comfortable spacing with bounded reading width. Keep the source buffer separate from the display projection so labels and old text never enter saved Markdown. Protected-region selections require switching to clean editing for broad edits. The current prototype rebuilds this projection synchronously; incremental rendering and native composition/undo grouping need validation before daily use.

## Sidebar implementation

The prototype now discovers manuscript Markdown files through Git, groups them in reading order, marks local changes, and supports a Changed only filter. Chapter selection loads the working file against the last local commit in background tasks. Status refresh does not overwrite the active buffer. Unsaved changes require an explicit discard before chapter switches. Atomic in-place saves, chapter-only and all-file visual commit review, and explicit outgoing push review are implemented. Hunk commit review is available on hover or edit. Recovery drafts, automatic external-change reconciliation, and word-level staging remain outstanding.

Commit reviews use private index snapshots. Chapter commits preserve unrelated staged files; all-file commits capture working repository changes. Hunk commits preserve compatible staged edits in the same file. Cancel leaves Git contents unchanged. All scopes share the editor’s visual diff styling.
