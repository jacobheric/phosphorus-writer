import Foundation

@main
struct CheckWrites {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let url = root.appendingPathComponent("manuscript/chapters/01.md")
        let old = try Data(contentsOf: url)
        let text = "# First light\n\nA new morning. 🌅\r\n"
        let saved = try RepositoryWrites.save(text, to: url, expected: old)
        precondition(saved == Data(text.utf8))
        do {
            _ = try RepositoryWrites.save("lost", to: url, expected: old)
            fatalError("stale save succeeded")
        } catch { }
        precondition(tryData(url) == saved)
        let preview = try RepositoryWrites.prepareCommit(at: root, path: "manuscript/chapters/01.md")
        precondition(preview.files.contains("notes.md") && preview.files.contains("01.md"))
        precondition(preview.diff.contains("A new morning"))
        _ = try RepositoryWrites.save(text + "Later edit.\n", to: url, expected: saved)
        try RepositoryWrites.commit(preview, message: "reviewed snapshot", at: root)
        do {
            try RepositoryWrites.commit(preview, message: "stale", at: root)
            fatalError("stale commit succeeded")
        } catch { }
        let push = try RepositoryWrites.preparePush(at: root)
        precondition(push.commits.contains("reviewed snapshot"))
        try RepositoryWrites.push(push, at: root)
        print("Passed safe save, stale save, full staged review, fixed staged snapshot, stale commit, and local remote push checks.")
    }
    static func tryData(_ url: URL) -> Data { try! Data(contentsOf: url) }
}
