# Phosphorus Writer

A native macOS manuscript editor with Markdown and integrated revision review.

## Run the prototype

Requires macOS 14 or later and a Swift 6 toolchain with the macOS SDK.

```sh
./scripts/run-app.sh
```

The app starts with synthetic sample prose. Review shows original paragraphs in red immediately above editable current paragraphs in green. Stronger highlights mark individual changed words. Unchanged prose stays in the reading flow. The editor uses Charter with generous spacing and a bounded text width. Toggle Review for a clean writing surface. Use the arrows and Restore change to revert a change; Undo restores your edit.

Open loads a text or Markdown file into memory. Compare with selects a comparison baseline. Save copy exports the current draft.

This prototype has no autosave, recovery, or Git operations yet. Save a copy before opening another file or quitting.

```sh
swift test
```

See [the build plan](docs/PLAN.md).

With only Command Line Tools selected, XCTest may be unavailable. Use an installed Xcode toolchain after accepting its license to run `swift test`. A standalone check also runs without XCTest:

```sh
swiftc Sources/WriterCore/Review.swift Sources/WriterCore/ReviewDocument.swift scripts/check-review.swift -o /tmp/phosphorus-review-check
/tmp/phosphorus-review-check
```

Review mode protects original passages and labels. Selections crossing those protected regions cannot be replaced; switch Review off for broad edits. Typing currently undoes one input event at a time. Diff layout is rebuilt while typing in this prototype; incremental layout, composition input, and large-document performance remain follow-up work.

## Manuscript sidebar

Open manuscript selects a Git repository. If it has a `manuscript/` folder, the sidebar lists its Markdown files under Front matter, Chapters, and Back matter. Otherwise it lists Markdown files throughout the repository. An amber dot marks staged, unstaged, or untracked local changes; the small filter icon beside MANUSCRIPT toggles changed-only filtering and shows a tooltip. The active file also receives a dot for unsaved in-memory edits.

Selecting a file loads its working copy against HEAD automatically. New files compare with an empty baseline; deleted files show their committed contents as deletions. The app asks before discarding unsaved edits when switching files. Status refreshes when the app becomes active or when you click the sidebar refresh button. It does not reload the active buffer during a status refresh.

Git access is read-only. There is still no staging, committing, or automatic saving.
