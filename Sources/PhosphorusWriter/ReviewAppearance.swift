import AppKit
import WriterCore

enum ReviewAppearance {
    static func render(_ document: ReviewDocument, original: String, current: String, reviewing: Bool = true, fontSize: Double = 20, formatted: Bool = false, changes: [Change]? = nil) -> (text: NSAttributedString, typing: [NSAttributedString.Key: Any]) {
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
            let changes = changes ?? Review.changes(from: original, to: current)
            for change in changes where change.range.length > 0 {
                for span in document.spans {
                    guard let source = span.source else { continue }
                    let overlap = NSIntersectionRange(source, change.range)
                    guard overlap.length > 0 else { continue }
                    let range = NSRange(location: span.display.location + overlap.location - source.location, length: overlap.length)
                    result.addAttribute(.backgroundColor, value: NSColor.systemGreen.withAlphaComponent(0.33), range: range)
                }
            }
            for change in Review.reversed(changes) where change.range.length > 0 {
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
        if formatted {
            let oldStyles = MarkdownStyle.spans(in: original)
            let newStyles = MarkdownStyle.spans(in: current)
            var oldPosition = 0
            for span in document.spans {
                let source = span.kind == .original ? NSRange(location: oldPosition, length: span.display.length) : span.source
                if let source {
                    for style in span.kind == .original ? oldStyles : newStyles {
                        let overlap = NSIntersectionRange(source, style.range)
                        guard overlap.length > 0 else { continue }
                        let range = NSRange(location: span.display.location + overlap.location - source.location, length: overlap.length)
                        switch style.kind {
                        case .marker:
                            result.addAttribute(.foregroundColor, value: Paper.ink.withAlphaComponent(0.45), range: range)
                        case .heading(let level):
                            let size = fontSize * max(1, 1.45 - Double(level) * 0.1)
                            let heading = NSFont(name: "Charter-Bold", size: size) ?? .boldSystemFont(ofSize: size)
                            result.addAttribute(.font, value: heading, range: range)
                        case .bold, .italic, .boldItalic:
                            let traits: NSFontTraitMask = style.kind == .bold ? .boldFontMask : style.kind == .italic ? .italicFontMask : [.boldFontMask, .italicFontMask]
                            result.enumerateAttribute(.font, in: range) { value, subrange, _ in
                                let face = NSFontManager.shared.convert(value as? NSFont ?? font, toHaveTrait: traits)
                                result.addAttribute(.font, value: face, range: subrange)
                            }
                        case .code:
                            result.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: fontSize * 0.85, weight: .regular), range: range)
                        }
                    }
                }
                if span.kind == .original || span.kind == .unchanged { oldPosition += span.display.length }
            }
        }
        return (result, base)
    }
}
