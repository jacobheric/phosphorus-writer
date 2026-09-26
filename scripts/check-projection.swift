import Foundation

@main
struct CheckProjection {
    static func main() {
        let old = "# Dawn 🌅\n\nAn **old** word.\n"
        let current = "# Dawn 🌅\n\nA **new** word.\n\n*Quiet.*\n"
        for reviewing in [false, true] {
            let document = ReviewDocument(original: old, current: current, reviewing: reviewing)
            for active in [nil, Optional((current as NSString).paragraphRange(for: (current as NSString).range(of: "new")))] {
                let hidden = MarkdownStyle.hiddenMarkers(in: document, original: old, current: current, activeParagraph: active)
                let projection = TextProjection(document.text, hiding: hidden)
                precondition(!projection.text.contains("# "))
                precondition(!projection.text.contains("*Quiet.*"))
                precondition(projection.text.contains(active == nil ? "A new word." : "A **new** word."))
                let visible = (projection.text as NSString).range(of: "new")
                let source = document.sourceRange(for: projection.sourceRange(visible))!
                precondition((current as NSString).substring(with: source) == "new")
                precondition((current as NSString).replacingCharacters(in: source, with: "bright") == current.replacingOccurrences(of: "new", with: "bright"))
                if reviewing {
                    let original = (projection.text as NSString).range(of: "old")
                    precondition(document.sourceRange(for: projection.sourceRange(original)) == nil)
                }
            }
        }
        let projection = TextProjection("**🌅**", hiding: [NSRange(location: 0, length: 2), NSRange(location: 4, length: 2)])
        precondition(projection.text == "🌅")
        precondition(projection.sourceRange(NSRange(location: 0, length: 2)) == NSRange(location: 2, length: 2))
        precondition(projection.displayOffset(3) == 1)
        print("Passed hidden marker, reveal, Unicode, source edit, and protected diff checks.")
    }
}
