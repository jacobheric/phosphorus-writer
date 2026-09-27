import Foundation

@main
struct CheckCommits {
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
        let other = original.replacingOccurrences(of: "slept", with: "wakes")
        try write(path, other)
        _ = try git(["add", "--", path])
        try write(path, current)
        let indexBefore = try git(["write-tree"])
        let preview = try RepositoryWrites.prepareChange(hunk, original: original, current: current, at: root, path: path)
        precondition(preview.partial && preview.files[0].current == original.replacingOccurrences(of: "quiet", with: "bright"))
        precondition(try! git(["write-tree"]) == indexBefore)
        precondition(try! RepositoryWrites.committedText(at: root, path: path) == original)
        let all = try RepositoryWrites.prepareCommit(at: root, path: nil)
        precondition(all.files.count == 2 && all.files.first { $0.path == path }?.current == current)
        try Data().write(to: root.appendingPathComponent(".git/index.lock"))
        do {
            try RepositoryWrites.commit(preview, message: "locked", at: root)
            fatalError("Ignored lock")
        } catch { }
        try FileManager.default.removeItem(at: root.appendingPathComponent(".git/index.lock"))
        try write(path, current + "Later edit\r\n")
        try RepositoryWrites.commit(preview, message: "Approve dawn", at: root)
        precondition(try! RepositoryWrites.committedText(at: root, path: path) == preview.files[0].current)
        precondition(try! RepositoryWrites.stagedText(at: root, path: path) == current)
        precondition(try! git(["show", ":notes.md"]) == "Other staged work\n")
        precondition(try! String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) == current + "Later edit\r\n")
        do {
            try RepositoryWrites.commit(preview, message: "stale", at: root)
            fatalError("Accepted stale preview")
        } catch { }
        let chapter = try RepositoryWrites.prepareCommit(at: root, path: path)
        try RepositoryWrites.commit(chapter, message: "Finish chapter", at: root)
        precondition(try! git(["show", ":notes.md"]) == "Other staged work\n")
        let base = try RepositoryWrites.committedText(at: root, path: path)
        try write(path, base.replacingOccurrences(of: "bright", with: "golden"))
        _ = try git(["add", "--", path])
        let working = base.replacingOccurrences(of: "bright", with: "pink")
        try write(path, working)
        let conflict = try RepositoryWrites.prepareChange(ReviewDocument(original: base, current: working, reviewing: true).hunks[0], original: base, current: working, at: root, path: path)
        let beforeConflict = try git(["rev-parse", "HEAD"])
        do {
            try RepositoryWrites.commit(conflict, message: "conflicting approval", at: root)
            fatalError("Lost overlapping staging")
        } catch { }
        precondition(try! git(["rev-parse", "HEAD"]) == beforeConflict)
        precondition(try! RepositoryWrites.stagedText(at: root, path: path) == base.replacingOccurrences(of: "bright", with: "golden"))
        try write(path, base)
        let repository = try ManuscriptRepository.scan(at: root)
        precondition(repository.files.first { $0.path == path }?.changed == false)
        let newPath = "new\tchapter\n🌅.md"
        let newText = "# New\n\nHello 🌅\n"
        try write(newPath, newText)
        let newHunk = ReviewDocument(original: "", current: newText, reviewing: true).hunks[0]
        let addition = try RepositoryWrites.prepareChange(newHunk, original: "", current: newText, at: root, path: newPath)
        try RepositoryWrites.commit(addition, message: "Add chapter", at: root)
        precondition(try! RepositoryWrites.committedText(at: root, path: newPath) == newText)
        try FileManager.default.removeItem(at: root.appendingPathComponent(newPath))
        let deletion = try RepositoryWrites.prepareChange(ReviewDocument(original: newText, current: "", reviewing: true).hunks[0], original: newText, current: "", at: root, path: newPath)
        try RepositoryWrites.commit(deletion, message: "Remove chapter", at: root)
        precondition(try! git(["ls-files", "--", newPath]).isEmpty)
        print("Passed direct hunk commits, HEAD baselines, mixed staging, same-file and unrelated staging preservation, cancel, locks, stale previews, overlapping staging rejection, later edits, Unicode/CRLF and additions/deletions.")
    }
}
