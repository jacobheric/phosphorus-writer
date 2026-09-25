import Foundation

public struct Change: Equatable, Sendable, Identifiable {
    public let id: Int
    public let range: NSRange
    public let original: String
    public let replacement: String
}

public enum Review {
    public static func changes(from original: String, to current: String) -> [Change] {
        let before = tokens(original)
        let after = tokens(current)
        let difference = after.difference(from: before)
        let removed = Set(difference.removals.map { change -> Int in
            if case let .remove(offset, _, _) = change { return offset }
            return -1
        })
        let inserted = Set(difference.insertions.map { change -> Int in
            if case let .insert(offset, _, _) = change { return offset }
            return -1
        })
        var result: [Change] = []
        var left = 0
        var right = 0
        var position = 0
        while left < before.count || right < after.count {
            if removed.contains(left) || inserted.contains(right) {
                let start = position
                var old = ""
                var new = ""
                while left < before.count && removed.contains(left) {
                    old += before[left]
                    left += 1
                }
                while right < after.count && inserted.contains(right) {
                    new += after[right]
                    position += after[right].utf16.count
                    right += 1
                }
                result.append(Change(id: result.count, range: NSRange(location: start, length: position - start), original: old, replacement: new))
            } else {
                if right < after.count { position += after[right].utf16.count }
                left += 1
                right += 1
            }
        }
        return result
    }

    private static func tokens(_ text: String) -> [String] {
        let expression = try! NSRegularExpression(pattern: #"[\p{L}\p{M}\p{N}_]+|\s+|[^\p{L}\p{M}\p{N}_\s]"#)
        let source = text as NSString
        return expression.matches(in: text, range: NSRange(location: 0, length: source.length)).map { source.substring(with: $0.range) }
    }
}
