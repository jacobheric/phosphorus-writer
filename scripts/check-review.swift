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
        let deletion = Review.changes(from: "hello world", to: "hello")
        precondition(deletion.count == 1 && deletion[0].range == NSRange(location: 5, length: 0))
        print("Passed \(count) exact round trips and pure-deletion anchor check.")
    }
}
