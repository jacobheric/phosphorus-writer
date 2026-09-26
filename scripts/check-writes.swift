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
        precondition(preview.files.count == 1)
        precondition(preview.files[0].current == text)
        precondition(tryGit(["show", ":notes.md"], at: root) == "Staged elsewhere\n")
        _ = try RepositoryWrites.save(text + "Later edit.\n", to: url, expected: saved)
        try RepositoryWrites.commit(preview, message: "reviewed snapshot", at: root)
        do {
            try RepositoryWrites.commit(preview, message: "stale", at: root)
            fatalError("stale commit succeeded")
        } catch { }
        precondition(tryGit(["show", "HEAD:notes.md"], at: root) == "Notes\n")
        precondition(tryGit(["show", ":notes.md"], at: root) == "Staged elsewhere\n")
        precondition(!tryGit(["show", "HEAD:manuscript/chapters/01.md"], at: root).contains("Later edit"))
        let before = tryGit(["write-tree"], at: root)
        let all = try RepositoryWrites.prepareCommit(at: root, path: nil)
        precondition(tryGit(["write-tree"], at: root) == before)
        precondition(all.files.contains { $0.path == "notes.md" })
        precondition(all.files.contains { $0.path == "deleted.md" && $0.status == "D" && $0.current == "" })
        precondition(all.files.contains { $0.path == "new.md" && $0.status == "A" && $0.original == "" })
        precondition(all.files.contains { $0.path == "binary.dat" && $0.current == nil })
        try "A still later edit\n".write(to: url, atomically: true, encoding: .utf8)
        try RepositoryWrites.commit(all, message: "all files", at: root)
        precondition(tryGit(["diff", "--cached", "--name-only"], at: root).isEmpty)
        precondition(tryGit(["show", "HEAD:manuscript/chapters/01.md"], at: root).contains("Later edit"))
        precondition(tryData(url) == Data("A still later edit\n".utf8))
        let stale = try RepositoryWrites.prepareCommit(at: root, path: nil)
        _ = tryGit(["add", "-A"], at: root)
        do {
            try RepositoryWrites.commit(stale, message: "stale index", at: root)
            fatalError("stale index accepted")
        } catch { }
        let push = try RepositoryWrites.preparePush(at: root)
        precondition(push.commits.contains("reviewed snapshot"))
        try RepositoryWrites.push(push, at: root)
        print("Passed safe saves, chapter isolation, staged-file preservation, full review, deletion/addition/binary previews, frozen snapshots, stale HEAD/index rejection, and local push.")
    }
    static func tryGit(_ arguments: [String], at root: URL) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = root
        let output = Pipe()
        process.standardOutput = output
        try! process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        precondition(process.terminationStatus == 0)
        return String(decoding: data, as: UTF8.self)
    }
    static func tryData(_ url: URL) -> Data { try! Data(contentsOf: url) }
}
