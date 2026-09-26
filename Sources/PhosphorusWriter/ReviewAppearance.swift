import AppKit
import WriterCore

enum ReviewAppearance {
    static func render(_ document: ReviewDocument, original: String, current: String, reviewing: Bool = true, fontSize: Double = 20) -> (text: NSAttributedString, typing: [NSAttributedString.Key: Any]) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = fontSize * 0.4
        paragraph.paragraphSpacing = fontSize * 0.4
        let font = NSFont(name: "Charter", size: fontSize) ?? .systemFont(ofSize: fontSize)
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Paper.ink, .paragraphStyle: paragraph]
        let result = NSMutableAttributedString(string: document.text, attributes: base)
        for span in document.spans {
            switch span.kind {
            case .original:
                result.addAttribute(.toolTip, value: "Original", range: span.display)
                result.addAttribute(.backgroundColor, value: NSColor.systemRed.withAlphaComponent(0.13), range: span.display)
                result.addAttribute(.foregroundColor, value: Paper.ink.withAlphaComponent(0.72), range: span.display)
            case .current:
                result.addAttribute(.toolTip, value: "Draft", range: span.display)
                result.addAttribute(.backgroundColor, value: NSColor.systemGreen.withAlphaComponent(0.14), range: span.display)
            case .label:
                result.addAttributes([.font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: NSColor.secondaryLabelColor], range: span.display)
            case .unchanged: break
            }
        }
        if reviewing {
            for change in Review.changes(from: original, to: current) where change.range.length > 0 {
                for span in document.spans {
                    guard let source = span.source else { continue }
                    let overlap = NSIntersectionRange(source, change.range)
                    guard overlap.length > 0 else { continue }
                    let range = NSRange(location: span.display.location + overlap.location - source.location, length: overlap.length)
                    result.addAttribute(.backgroundColor, value: NSColor.systemGreen.withAlphaComponent(0.33), range: range)
                }
            }
            for change in Review.changes(from: current, to: original) where change.range.length > 0 {
                // Original blocks follow the baseline in order; locate them without adding their text to the saved draft.
                var originalPosition = 0
                for span in document.spans {
                    if span.kind == .original || span.kind == .unchanged {
                        let oldRange = NSRange(location: originalPosition, length: span.display.length)
                        let overlap = NSIntersectionRange(oldRange, change.range)
                        if span.kind == .original && overlap.length > 0 {
                            result.addAttribute(.backgroundColor, value: NSColor.systemRed.withAlphaComponent(0.3), range: NSRange(location: span.display.location + overlap.location - oldRange.location, length: overlap.length))
                        }
                        originalPosition += span.display.length
                    }
                }
            }
        }
        return (result, base)
    }
}
