import Foundation

@main
struct CheckStaging {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("phosphorus-staging-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func git(_ args: [String]) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = args
            process.currentDirectoryURL = root
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            precondition(process.terminationStatus == 0)
            return String(decoding: data, as: UTF8.self)
        }
        func write(_ path: String, _ text: String) throws {
            try text.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }
        _ = try git(["init", "-b", "main"])
        _ = try git(["config", "user.name", "Test"])
        _ = try git(["config", "user.email", "test@example.invalid"])
        let path = "chapter 🌅.md"
        let original = "# First light\r\n\r\nThe dawn was quiet.\r\n\r\nThe orchard slept.\r\n"
        let current = original.replacingOccurrences(of: "quiet", with: "bright").replacingOccurrences(of: "slept", with: "wakes")
        try write(path, original)
        try write("notes.md", "Notes\n")
        _ = try git(["add", "."])
        _ = try git(["commit", "-m", "baseline"])
        try write("notes.md", "Other staged work\n")
        _ = try git(["add", "notes.md"])
        try write(path, current)
        _ = try git(["update-index", "--split-index"])
        let hunk = ReviewDocument(original: original, current: current, reviewing: true).hunks[0]
        let indexBefore = try Data(contentsOf: root.appendingPathComponent(".git/index"))
        try Data().write(to: root.appendingPathComponent(".git/index.lock"))
        do {
            try RepositoryWrites.stage(hunk, original: original, current: current, at: root, path: path)
            fatalError("Ignored index lock")
        } catch { }
        try FileManager.default.removeItem(at: root.appendingPathComponent(".git/index.lock"))
        precondition(try! Data(contentsOf: root.appendingPathComponent(".git/index")) == indexBefore)
        try RepositoryWrites.stage(hunk, original: original, current: current, at: root, path: path)
        let staged = try RepositoryWrites.stagedText(at: root, path: path)
        precondition(staged == original.replacingOccurrences(of: "quiet", with: "bright"))
        precondition(try! git(["show", ":notes.md"]) == "Other staged work\n")
        precondition(try! String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) == current)
        do {
            try RepositoryWrites.stage(hunk, original: original, current: current, at: root, path: path)
            fatalError("Accepted stale baseline")
        } catch { }
        let next = ReviewDocument(original: staged, current: current, reviewing: true).hunks[0]
        try write(path, current + "External edit\n")
        do {
            try RepositoryWrites.stage(next, original: staged, current: current, at: root, path: path)
            fatalError("Accepted stale working file")
        } catch { }
        try write(path, current)
        let chapter = try RepositoryWrites.prepareCommit(at: root, path: path, stagedOnly: true)
        precondition(chapter.files.count == 1 && chapter.files[0].current == staged)
        let all = try RepositoryWrites.prepareCommit(at: root, path: nil, stagedOnly: true)
        precondition(all.files.count == 2 && all.files.first { $0.path == path }?.current == staged)
        try RepositoryWrites.commit(chapter, message: "approved paragraph", at: root)
        precondition(try! git(["show", "HEAD:" + path]) == staged)
        precondition(try! git(["show", ":notes.md"]) == "Other staged work\n")
        precondition(try! String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) == current)
        try RepositoryWrites.stage(next, original: staged, current: current, at: root, path: path)
        try RepositoryWrites.unstage(at: root, path: path)
        precondition(try! RepositoryWrites.stagedText(at: root, path: path) == staged)
        let empty = try RepositoryWrites.prepareCommit(at: root, path: path, stagedOnly: true)
        precondition(empty.files.isEmpty)
        try RepositoryWrites.stageAll(at: root, path: path)
        precondition(try! RepositoryWrites.stagedText(at: root, path: path) == current)
        let newPath = "new\tchapter\n🌅.md"
        let newText = "# New\n\nHello 🌅\n"
        try write(newPath, newText)
        let newHunk = ReviewDocument(original: "", current: newText, reviewing: true).hunks[0]
        try RepositoryWrites.stage(newHunk, original: "", current: newText, at: root, path: newPath)
        precondition(try! RepositoryWrites.stagedText(at: root, path: newPath) == newText)
        try RepositoryWrites.unstage(at: root, path: newPath)
        precondition(try! RepositoryWrites.stagedText(at: root, path: newPath) == "")
        try FileManager.default.removeItem(at: root.appendingPathComponent(path))
        let deletion = ReviewDocument(original: current, current: "", reviewing: true).hunks[0]
        try RepositoryWrites.stage(deletion, original: current, current: "", at: root, path: path)
        precondition(try! git(["ls-files", "--", path]).isEmpty)
        print("Passed paragraph staging, CRLF/Unicode, new/deleted files, stale-input rejection, staged-only commit isolation, unstage, and explicit stage-all checks.")
    }
}
