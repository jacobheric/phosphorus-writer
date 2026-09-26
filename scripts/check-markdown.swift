import Foundation

@main
struct CheckMarkdown {
    static func main() {
        let text = "# First light 🌅\n\n***Bold and italic***, **bold**, *italic*, _soft_, __strong__.\n\n`**literal**`\n\n```\n# not a heading\n**not bold**\n```\n\nword_part_word and \\*escaped*\n"
        let spans = MarkdownStyle.spans(in: text)
        func contains(_ value: String, _ kind: MarkdownStyle.Kind) -> Bool {
            spans.contains { $0.kind == kind && (text as NSString).substring(with: $0.range) == value }
        }
        precondition(contains("# First light 🌅", .heading(1)))
        precondition(contains("Bold and italic", .boldItalic))
        precondition(contains("bold", .bold))
        precondition(contains("italic", .italic))
        precondition(contains("soft", .italic))
        precondition(contains("strong", .bold))
        precondition(!contains("literal", .bold))
        precondition(!contains("not bold", .bold))
        precondition(!contains("# not a heading", .heading(1)))
        precondition(!contains("part", .italic))
        precondition(!contains("escaped", .italic))
        precondition(spans.allSatisfy { $0.range.location >= 0 && NSMaxRange($0.range) <= text.utf16.count })
        print("Passed Markdown styling checks for headings, emphasis, Unicode, escapes, and protected code.")
    }
}
