import Foundation

public struct ReviewSpan: Sendable {
    public enum Kind: Sendable { case unchanged, original, current, label }
    public let kind: Kind
    public let display: NSRange
    public let source: NSRange?
}

public struct ReviewHunk: Sendable, Equatable, Identifiable {
    public let id: Int
    public let original: NSRange
    public let current: NSRange
    public let display: NSRange
}

public struct ReviewDocument: Sendable {
    public let text: String
    public let spans: [ReviewSpan]
    public let hunks: [ReviewHunk]

    public init(original: String, current: String, reviewing: Bool) {
        if !reviewing {
            text = current
            hunks = []
            spans = [ReviewSpan(kind: .unchanged, display: NSRange(location: 0, length: current.utf16.count), source: NSRange(location: 0, length: current.utf16.count))]
            return
        }
        func lines(_ value: String) -> [String] {
            var result: [String] = []
            var line = ""
            for character in value {
                line.append(character)
                if character == "\n" || character == "\r\n" { result.append(line); line = "" }
            }
            if !line.isEmpty { result.append(line) }
            return result
        }
        let before = lines(original)
        let after = lines(current)
        let difference = after.difference(from: before)
        let removed = Set(difference.removals.map { if case let .remove(offset, _, _) = $0 { return offset }; return -1 })
        let inserted = Set(difference.insertions.map { if case let .insert(offset, _, _) = $0 { return offset }; return -1 })
        var output = ""
        var regions: [ReviewSpan] = []
        var position = 0
        var originalPosition = 0
        var hunks: [ReviewHunk] = []
        func append(_ value: String, _ kind: ReviewSpan.Kind, source: NSRange? = nil) {
            regions.append(ReviewSpan(kind: kind, display: NSRange(location: output.utf16.count, length: value.utf16.count), source: source))
            output += value
        }
        var left = 0
        var right = 0
        while left < before.count || right < after.count {
            if removed.contains(left) || inserted.contains(right) {
                let sourceStart = position
                let displayStart = output.utf16.count
                var old = ""
                var new = ""
                while left < before.count && removed.contains(left) { old += before[left]; left += 1 }
                while right < after.count && inserted.contains(right) { new += after[right]; right += 1 }
                if !output.isEmpty && !output.hasSuffix("\n") { append("\n", .label) }
                if !old.isEmpty {
                    append(old, .original)
                    if !old.hasSuffix("\n") { append("\n", .label) }
                }
                append(new, .current, source: NSRange(location: position, length: new.utf16.count))
                position += new.utf16.count
                if !new.hasSuffix("\n") { append("\n", .label) }
                hunks.append(ReviewHunk(id: hunks.count, original: NSRange(location: originalPosition, length: old.utf16.count), current: NSRange(location: sourceStart, length: new.utf16.count), display: NSRange(location: displayStart, length: output.utf16.count - displayStart)))
                originalPosition += old.utf16.count
            } else {
                if right < after.count {
                    let line = after[right]
                    append(line, .unchanged, source: NSRange(location: position, length: line.utf16.count))
                    position += line.utf16.count
                    originalPosition += line.utf16.count
                }
                left += 1
                right += 1
            }
        }
        if regions.isEmpty { append("", .unchanged, source: NSRange(location: 0, length: 0)) }
        text = output
        spans = regions
        self.hunks = hunks
    }

    public func sourceRange(for displayRange: NSRange) -> NSRange? {
        let editable = spans.filter { $0.source != nil }
        for (index, span) in editable.enumerated() {
            guard let source = span.source, displayRange.location >= span.display.location,
                  displayRange.location <= NSMaxRange(span.display) else { continue }
            var end = NSMaxRange(span.display)
            var sourceEnd = NSMaxRange(source)
            for next in editable.dropFirst(index + 1) {
                guard next.display.location == end, next.source?.location == sourceEnd else { break }
                end = NSMaxRange(next.display)
                sourceEnd = NSMaxRange(next.source!)
            }
            if NSMaxRange(displayRange) <= end {
                return NSRange(location: source.location + displayRange.location - span.display.location, length: displayRange.length)
            }
        }
        return nil
    }

    public func displayOffset(for sourceOffset: Int) -> Int {
        for span in spans.reversed() {
            if let source = span.source, sourceOffset >= source.location, sourceOffset <= NSMaxRange(source) {
                return span.display.location + sourceOffset - source.location
            }
        }
        return text.utf16.count
    }
}
