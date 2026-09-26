import Foundation

public struct TextProjection {
    public struct Segment {
        public let source: NSRange
        public let display: NSRange
    }
    public let text: String
    public let segments: [Segment]
    public let sourceLength: Int

    public init(_ text: String, hiding ranges: [NSRange]) {
        let source = text as NSString
        sourceLength = source.length
        var position = 0
        var output = ""
        var segments: [Segment] = []
        for range in ranges.sorted(by: { $0.location < $1.location }) {
            guard range.location >= position, NSMaxRange(range) <= source.length else { continue }
            if range.location > position {
                let kept = NSRange(location: position, length: range.location - position)
                segments.append(Segment(source: kept, display: NSRange(location: output.utf16.count, length: kept.length)))
                output += source.substring(with: kept)
            }
            position = NSMaxRange(range)
        }
        let tail = NSRange(location: position, length: source.length - position)
        segments.append(Segment(source: tail, display: NSRange(location: output.utf16.count, length: tail.length)))
        output += source.substring(with: tail)
        self.text = output
        self.segments = segments
    }

    public func sourceOffset(_ offset: Int, trailing: Bool = false) -> Int {
        let candidates = trailing ? segments : segments.reversed().map { $0 }
        for segment in candidates where offset >= segment.display.location && offset <= NSMaxRange(segment.display) {
            return segment.source.location + offset - segment.display.location
        }
        return sourceLength
    }

    public func sourceRange(_ range: NSRange) -> NSRange {
        let start = sourceOffset(range.location)
        let end = sourceOffset(NSMaxRange(range), trailing: range.length > 0)
        return NSRange(location: start, length: max(0, end - start))
    }

    public func displayOffset(_ offset: Int) -> Int {
        for segment in segments {
            if offset < segment.source.location { return segment.display.location }
            if offset <= NSMaxRange(segment.source) { return segment.display.location + offset - segment.source.location }
        }
        return text.utf16.count
    }

    public func displayRange(_ range: NSRange) -> NSRange {
        let start = displayOffset(range.location)
        return NSRange(location: start, length: max(0, displayOffset(NSMaxRange(range)) - start))
    }
}
