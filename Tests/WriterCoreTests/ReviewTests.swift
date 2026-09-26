import XCTest
@testable import WriterCore

final class ReviewTests: XCTestCase {
    func testRestoringChangesReconstructsOriginalExactly() {
        let cases = [
            ("", "new"), ("old", ""), ("same", "same"),
            ("The sky was grey.", "The sky is blue."),
            ("café 👨‍👩‍👧‍👦\n\nhello", "cafe 🌅\nhello!"),
            ("one two one two", "two one three two"),
            ("a\r\nb  ", "a\nb\t"),
            ("a b c", "c b a")
        ]
        for (original, current) in cases {
            let result = NSMutableString(string: current)
            for change in Review.changes(from: original, to: current).reversed() {
                XCTAssertEqual(result.substring(with: change.range), change.replacement)
                result.replaceCharacters(in: change.range, with: change.original)
            }
            XCTAssertEqual(result as String, original)
        }
    }

    func testPureDeletionHasInsertionAnchor() {
        let changes = Review.changes(from: "hello world", to: "hello")
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].range, NSRange(location: 5, length: 0))
        XCTAssertEqual(changes[0].original, " world")
    }
}
