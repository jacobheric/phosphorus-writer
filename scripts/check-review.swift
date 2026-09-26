import Foundation

@main
struct CheckReview {
    static func main() {
        let samples = ["", "hello", "hello world", "café 👨‍👩‍👧‍👦\n\nhello", "cafe 🌅\nhello!", "one two one two", "two one three two", "a\r\nb  ", "a\nb\t", "a b c", "c b a"]
        var count = 0
        for original in samples {
            for current in samples {
                let restored = NSMutableString(string: current)
                for change in Review.changes(from: original, to: current).reversed() {
                    precondition(restored.substring(with: change.range) == change.replacement)
                    restored.replaceCharacters(in: change.range, with: change.original)
                }
                precondition(restored as String == original)
                count += 1
            }
        }
        for original in samples {
            for current in samples {
                let document = ReviewDocument(original: original, current: current, reviewing: true)
                let reconstructed = document.spans.compactMap { span -> String? in
                    guard span.source != nil else { return nil }
                    return (document.text as NSString).substring(with: span.display)
                }.joined()
                precondition(reconstructed == current)
                for span in document.spans {
                    if let source = span.source, span.display.length > 0 {
                        precondition(document.sourceRange(for: span.display) == source)
                    } else if span.display.length > 0 {
                        precondition(document.sourceRange(for: span.display) == nil)
                    }
                }
            }
        }
        let deletion = Review.changes(from: "hello world", to: "hello")
        precondition(deletion.count == 1 && deletion[0].range == NSRange(location: 5, length: 0))
        print("Passed \(count) exact round trips and 121 projection/source checks, plus pure-deletion anchor check.")
    }
}
