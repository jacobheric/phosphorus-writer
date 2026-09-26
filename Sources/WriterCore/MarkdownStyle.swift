import Foundation

public struct MarkdownStyle: Sendable {
    public enum Kind: Sendable, Equatable { case heading(Int), bold, italic, boldItalic, code, marker }
    public let range: NSRange
    public let kind: Kind

    public static func spans(in text: String) -> [MarkdownStyle] {
        let source = text as NSString
        let full = NSRange(location: 0, length: source.length)
        func matches(_ pattern: String) -> [NSTextCheckingResult] {
            (try? NSRegularExpression(pattern: pattern).matches(in: text, range: full)) ?? []
        }
        let fences = matches("(?ms)^ {0,3}(`{3,}|~{3,})[^\\n]*\\n.*?(?:^ {0,3}\\1[ \\t]*$|\\z)").map(\.range)
        let inlineCode = matches("(?<![\\\\`])(`+)([^`\\n]+)\\1(?!`)").map(\.range)
        let code = fences + inlineCode
        func outsideCode(_ range: NSRange) -> Bool { !code.contains { NSIntersectionRange($0, range).length > 0 } }
        var result = code.map { MarkdownStyle(range: $0, kind: .code) }
        for match in matches("(?m)^ {0,3}(#{1,6})[ \\t]+[^\\r\\n]+$") where outsideCode(match.range) {
            result.append(MarkdownStyle(range: match.range, kind: .heading(match.range(at: 1).length)))
            result.append(MarkdownStyle(range: match.range(at: 1), kind: .marker))
        }
        let emphasis: [(String, Kind)] = [("***", .boldItalic), ("**", .bold), ("*", .italic), ("__", .bold), ("_", .italic)]
        var used: [NSRange] = []
        for (delimiter, kind) in emphasis {
            let escaped = NSRegularExpression.escapedPattern(for: delimiter)
            let character = delimiter.first == "*" ? "\\*" : "_"
            let pattern = "(?<![\\\\\\p{L}\\p{N}" + character + "])(" + escaped + ")(?=\\S)([^\\r\\n]*?\\S)(" + escaped + ")(?![" + character + "\\p{L}\\p{N}])"
            for match in matches(pattern) where outsideCode(match.range) && !used.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                used.append(match.range)
                result.append(MarkdownStyle(range: match.range(at: 2), kind: kind))
                result.append(MarkdownStyle(range: match.range(at: 1), kind: .marker))
                result.append(MarkdownStyle(range: match.range(at: 3), kind: .marker))
            }
        }
        return result
    }
}
