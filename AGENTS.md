# Working on Phosphorus Writer

Use idiomatic Swift. Prefer simple value types and pure functions for review logic. Keep AppKit and SwiftUI out of WriterCore so it can run on macOS and Linux.

Use branches named jacob/[feature-name]. Keep prose plain and comments short; explain why only when needed.

Never copy or modify the Dew manuscript as a fixture. Use synthetic text. Preserve exact source text and Unicode boundaries. Test diff restoration and Git state transitions.

Run `swift test`. Native UI verification requires macOS. Do not claim native UI behavior was tested from Linux.

Read docs/PLAN.md before expanding scope. PR descriptions start with # Summary and use short, plain paragraphs.
