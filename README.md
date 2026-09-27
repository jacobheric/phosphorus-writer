# Phosphorus

A native macOS manuscript editor with Markdown and integrated revision review.

## Install and update

Requires macOS 14 or later, Git, and a Swift 6 toolchain with the macOS SDK.
Save your work and quit Phosphorus, then run this from the repository:

```sh
./scripts/install-app.sh
```

This builds an optimized app and installs it at `/Applications/Phosphorus.app`.
Open it from Finder or Spotlight and choose Keep in Dock from its Dock menu.
Use the folder button to open your manuscript repository. ⌘S saves your edits.

To update after improvements merge into `main`, quit the app and run:

```sh
git switch main
git pull --ff-only
./scripts/install-app.sh
```

The installer replaces the app while keeping its preferences and your manuscript files.
Updates are manual for now. To install only for your user, use
`./scripts/install-app.sh "$HOME/Applications"` instead.

## Run the prototype

Requires macOS 14 or later and a Swift 6 toolchain with the macOS SDK.

```sh
./scripts/run-app.sh
```

The app starts with synthetic sample prose. Review shows original paragraphs in red immediately above editable current paragraphs in green. Stronger highlights mark individual changed words. Unchanged prose stays in the reading flow. The editor uses Charter with generous spacing and a bounded text width. Toggle Review for a clean writing surface. Use the arrows and Restore change to revert a change; Undo restores your edit.

Open loads a text or Markdown file into memory. Compare with selects a comparison baseline. Save copy exports the current draft.

⌘S saves the current file atomically and refuses to overwrite a file changed on disk since it was loaded or saved. Unsaved edits are marked in the footer. There is no autosave or crash recovery yet.

```sh
swift test
```

See [the build plan](docs/PLAN.md).

With only Command Line Tools selected, XCTest may be unavailable. Use an installed Xcode toolchain after accepting its license to run `swift test`. A standalone check also runs without XCTest:

```sh
swiftc Sources/WriterCore/Review.swift Sources/WriterCore/ReviewDocument.swift scripts/check-review.swift -o /tmp/phosphorus-review-check
/tmp/phosphorus-review-check
```

Review mode protects original passages. Selections crossing those protected regions cannot be replaced; switch Review off for broad edits. Typing currently undoes one input event at a time. Diff layout is rebuilt while typing in this prototype; incremental layout, composition input, and large-document performance remain follow-up work.

## Reading layout

Drag the sidebar divider to resize it. Chapter rows keep the same height whether they have changes or not. ⌘+ (or ⌘=) and ⌘− resize the writing text; ⌘0 restores the default. Text size is remembered across launches.

The Format toggle styles headings, bold, italics, and code directly in the editable text. Heading and emphasis markers stay hidden until you enter their paragraph, then hide again when you leave. Formatting never changes the source. This is basic live styling, not a full Markdown renderer.

## Manuscript sidebar

Open manuscript selects a Git repository. If it has a `manuscript/` folder, the sidebar lists its Markdown files under Front matter, Chapters, and Back matter. Otherwise it lists Markdown files throughout the repository. A small commit icon marks chapters with local changes, including unsaved edits. The filter icon toggles changed-only filtering. Button labels appear after a 150 ms hover.

Click a section heading to focus the sidebar, then use ↑/↓ to browse headings and files. Enter moves into the editor. Clicking a chapter directly also focuses its text. Selecting a file compares its working copy with the last local commit. New files compare with an empty baseline; deleted files show their last committed contents as deletions. The app asks before discarding unsaved edits when switching files. Status refreshes when the app becomes active or when you click the sidebar refresh button. It does not reload the active buffer during a status refresh.

## Save, commit, and push

⌘S and the save icon write the current draft back to its file. Save Draft Copy remains available with ⇧⌘S and does not mark the original file as saved.

Hover over a changed paragraph, or place the caret in it, to reveal a small Commit checkmark in the margin. Clicking opens a visual review of that change with a message and Commit / Cancel. Committing saves that hunk in local history and removes its diff from the reading view. Adjacent changed lines can form one hunk. Later edits appear against the last commit. Hunk commits are available for repository files in Review mode, not custom comparisons.

Each changed chapter has a commit icon. It saves that chapter if open, then reviews all its uncommitted changes. The toolbar Commit icon reviews all changes across the repository, including files outside the manuscript. Staging is not part of the app’s workflow: edits staged in other Git tools remain visible here. Text uses the same red/green word highlights as the editor; binary files and mode changes are identified separately.

Reviews batch Git object reads and calculate each file’s diff in the background. Revisited file previews are cached while the dialog is open. Reviews capture an immutable snapshot without changing staged contents. Cancel closes the review without committing. A chapter commit preserves other staged files. A hunk commit also preserves compatible staged edits in the same file; overlapping edits that cannot be merged safely require committing the chapter together. Later working edits stay uncommitted; changes to HEAD, branch, or the real index require reopening the review. The app holds the Git index lock while committing and updating the index. Push remains a separate action.

Direct-commit checks use a disposable synthetic repository:

```sh
swiftc Sources/WriterCore/ReviewDocument.swift Sources/WriterCore/RepositoryWrites.swift Sources/WriterCore/ManuscriptRepository.swift scripts/check-commits.swift -o /tmp/phosphorus-commits-check
/tmp/phosphorus-commits-check
```

The paragraph-staging checks use a disposable synthetic repository:

```sh
swiftc Sources/WriterCore/ReviewDocument.swift Sources/WriterCore/RepositoryWrites.swift scripts/check-staging.swift -o /tmp/phosphorus-staging-check
/tmp/phosphorus-staging-check
```

Git writes are serialized within the app. Initial commits, merge/rebase resolution, word-level staging, autosave, recovery, and live external-file reload remain follow-up work.

## License

[MIT](LICENSE) © 2026 Jacob Heric.
