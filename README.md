# Phosphorus Writer

A native macOS manuscript editor with Markdown and integrated revision review.

## Run the prototype

Requires macOS 14 or later and a Swift 6 toolchain with the macOS SDK.

```sh
./scripts/run-app.sh
```

The app starts with synthetic sample prose. Edit the draft, toggle Review, move between changes with the review arrows, and use Restore original to revert a change. Undo restores your edit. Deleted text is shown in the review panel and marked with an underline at its anchor.

Open loads a text or Markdown file into memory. Choose original file selects a comparison baseline. Save copy exports the current draft.

This prototype has no autosave, recovery, or Git operations yet. Save a copy before opening another file or quitting.

```sh
swift test
```

See [the build plan](docs/PLAN.md).

With only Command Line Tools selected, XCTest may be unavailable. Use an installed Xcode toolchain after accepting its license to run `swift test`. A standalone check also runs without XCTest:

```sh
swiftc Sources/WriterCore/Review.swift scripts/check-review.swift -o /tmp/phosphorus-review-check
/tmp/phosphorus-review-check
```
