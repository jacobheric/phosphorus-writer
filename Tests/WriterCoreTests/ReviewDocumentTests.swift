import XCTest
@testable import WriterCore

final class ReviewDocumentTests: XCTestCase {
    func testProjectionPreservesSourceAndProtectsOriginal() {
        let current = "# Draft\n\nA new paragraph.\n"
        let document = ReviewDocument(original: "# Draft\n\nAn old paragraph.\n", current: current, reviewing: true)
        let source = document.spans.compactMap { span -> String? in
            guard span.source != nil else { return nil }
            return (document.text as NSString).substring(with: span.display)
        }.joined()
        XCTAssertEqual(source, current)
        for span in document.spans where span.source == nil && span.display.length > 0 {
            XCTAssertNil(document.sourceRange(for: span.display))
        }
    }

    func testSourceSelectionAcrossUnchangedLines() {
        let text = "one\n\ntwo\n"
        let document = ReviewDocument(original: text, current: text, reviewing: true)
        let range = NSRange(location: 0, length: text.utf16.count)
        XCTAssertEqual(document.sourceRange(for: range), range)
    }

    func testReviewOffIsExactSource() {
        let text = "café 🌅\r\n"
        let document = ReviewDocument(original: "old", current: text, reviewing: false)
        XCTAssertEqual(document.text, text)
    }
}
