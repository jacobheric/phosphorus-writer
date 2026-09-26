import Foundation

public struct CommitFile: Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let status: String
    public let original: String?
    public let current: String?
    public let oldMode: String
    public let newMode: String
}

public struct CommitPreview: Sendable {
    public let tree: String
    public let indexTree: String
    public let head: String
    public let branch: String
    public let chapter: String?
    public let files: [CommitFile]
}

public struct PushPreview: Sendable {
    public let head: String
    public let branch: String
    public let remote: String
    public let destination: String
    public let commits: String
}

public enum RepositoryWrites {
    public static func save(_ text: String, to url: URL, expected: Data?) throws -> Data {
        let current = try Data(contentsOf: url)
        guard current == expected else { throw failure("This file changed on disk. Your edits are still here; save a copy before reopening the file.") }
        let data = Data(text.utf8)
        try data.write(to: url, options: .atomic)
        return data
    }

    public static func prepareCommit(at root: URL, path: String?) throws -> CommitPreview {
        let branch = try git(["symbolic-ref", "--short", "HEAD"], at: root).trimmingCharacters(in: .newlines)
        guard try git(["ls-files", "-u"], at: root).isEmpty else { throw failure("Resolve conflicts first.") }
        for marker in ["MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply"] {
            let location = try git(["rev-parse", "--git-path", marker], at: root).trimmingCharacters(in: .newlines)
            let url = URL(fileURLWithPath: location, relativeTo: root)
            guard !FileManager.default.fileExists(atPath: url.path) else { throw failure("Finish the current Git operation first.") }
        }
        let head = try head(at: root)
        let indexTree = try git(["write-tree"], at: root)
        return try withIndex { index in
            try git(["read-tree", path == nil ? indexTree : head], at: root, index: index)
            try git(path.map { ["add", "--", ":(literal)" + $0] } ?? ["add", "-A"], at: root, index: index)
            let tree = try git(["write-tree"], at: root, index: index)
            let records = try git(["diff", "--name-status", "--no-renames", "-z", head, tree], at: root)
                .split(separator: "\0").map(String.init)
            var files: [CommitFile] = []
            for offset in stride(from: 0, to: records.count, by: 2) {
                let path = records[offset + 1]
                let old = try blob(head, path: path, at: root)
                let new = try blob(tree, path: path, at: root)
                files.append(CommitFile(path: path, status: records[offset], original: old.text, current: new.text,
                                        oldMode: old.mode, newMode: new.mode))
            }
            guard !files.isEmpty else { throw failure("No changes to commit.") }
            return CommitPreview(tree: tree, indexTree: indexTree, head: head, branch: branch, chapter: path, files: files)
        }
    }

    public static func commit(_ preview: CommitPreview, message: String, at root: URL) throws {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw failure("Add a message.") }
        let indexPath = try git(["rev-parse", "--path-format=absolute", "--git-path", "index"], at: root).trimmingCharacters(in: .newlines)
        let indexURL = URL(fileURLWithPath: indexPath)
        let originalIndex = try Data(contentsOf: indexURL)
        guard try head(at: root) == preview.head,
              try git(["write-tree"], at: root) == preview.indexTree,
              try git(["symbolic-ref", "--short", "HEAD"], at: root).trimmingCharacters(in: .newlines) == preview.branch else {
            throw failure("Git changed. Reopen this review.")
        }
        // Keep other Git clients out while committing the reviewed snapshot and updating the real index.
        let lock = URL(fileURLWithPath: indexPath + ".lock")
        try Data().write(to: lock, options: .withoutOverwriting)
        defer { try? FileManager.default.removeItem(at: lock) }
        guard try Data(contentsOf: indexURL) == originalIndex else { throw failure("Git changed. Reopen this review.") }
        try withIndex { nextIndex in
            try git(["read-tree", preview.chapter == nil ? preview.tree : preview.indexTree], at: root, index: nextIndex)
            if let path = preview.chapter {
                try git(["restore", "--source=" + preview.tree, "--staged", "--", ":(literal)" + path], at: root, index: nextIndex)
            }
            let nextData = try Data(contentsOf: URL(fileURLWithPath: nextIndex))
            // A private index keeps later working edits out of the commit and preserves unrelated staged files.
            try withIndex { commitIndex in
                try git(["read-tree", preview.tree], at: root, index: commitIndex)
                try git(["commit", "-m", message], at: root, index: commitIndex)
            }
            do { try nextData.write(to: indexURL, options: .atomic) }
            catch { throw failure("Committed, but the index could not be updated. Check Git before committing again.") }
        }
    }

    private static func blob(_ tree: String, path: String, at root: URL) throws -> (text: String?, mode: String) {
        let entry = try git(["ls-tree", "-z", tree, "--", ":(literal)" + path], at: root)
        guard !entry.isEmpty else { return ("", "") }
        let fields = entry.prefix(while: { $0 != "\t" }).split(separator: " ")
        guard fields.count == 3 else { throw failure("Could not read file.") }
        let mode = String(fields[0])
        guard fields[1] == "blob" else { return (nil, mode) }
        let bytes = try gitData(["cat-file", "blob", String(fields[2])], at: root)
        let text = bytes.contains(0) ? nil : String(data: bytes, encoding: .utf8)
        return (text, mode)
    }

    private static func withIndex<T>(_ action: (String) throws -> T) throws -> T {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("phosphorus-index-" + UUID().uuidString).path
        defer {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: path + ".lock")
        }
        return try action(path)
    }

    public static func preparePush(at root: URL) throws -> PushPreview {
        let branch = try git(["symbolic-ref", "--short", "HEAD"], at: root).trimmingCharacters(in: .newlines)
        let remote = try git(["config", "--get", "branch.\(branch).remote"], at: root).trimmingCharacters(in: .newlines)
        let destination = try git(["config", "--get", "branch.\(branch).merge"], at: root).trimmingCharacters(in: .newlines)
        guard remote != ".", !remote.hasPrefix("-"), destination.hasPrefix("refs/heads/") else { throw failure("Set a remote upstream branch before pushing.") }
        _ = try git(["fetch", "--no-tags", remote, destination], at: root)
        _ = try git(["merge-base", "--is-ancestor", "FETCH_HEAD", "HEAD"], at: root)
        let commits = try git(["log", "--oneline", "FETCH_HEAD..HEAD"], at: root)
        guard !commits.isEmpty else { throw failure("Everything is already pushed.") }
        return PushPreview(head: try head(at: root), branch: branch, remote: remote, destination: destination, commits: commits)
    }

    public static func push(_ preview: PushPreview, at root: URL) throws {
        guard try head(at: root) == preview.head,
              try git(["symbolic-ref", "--short", "HEAD"], at: root).trimmingCharacters(in: .newlines) == preview.branch else {
            throw failure("The branch changed. Review outgoing commits again.")
        }
        _ = try git(["push", preview.remote, "\(preview.head.trimmingCharacters(in: .newlines)):\(preview.destination)"], at: root)
    }

    private static func head(at root: URL) throws -> String {
        try git(["rev-parse", "--verify", "HEAD"], at: root)
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "Phosphorus", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    @discardableResult
    private static func git(_ arguments: [String], at root: URL, index: String? = nil) throws -> String {
        String(decoding: try gitData(arguments, at: root, index: index), as: UTF8.self).trimmingCharacters(in: .newlines)
    }

    private static func gitData(_ arguments: [String], at root: URL, index: String? = nil) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = root
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes"
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        if let index { environment["GIT_INDEX_FILE"] = index }
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        let errorURL = FileManager.default.temporaryDirectory.appendingPathComponent("phosphorus-git-" + UUID().uuidString)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let errorFile = try FileHandle(forWritingTo: errorURL)
        defer { try? errorFile.close(); try? FileManager.default.removeItem(at: errorURL) }
        process.standardError = errorFile
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: (try? Data(contentsOf: errorURL)) ?? data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw failure(text.isEmpty ? "Git could not complete this action. Check the upstream branch and repository state." : text)
        }
        return data
    }
}
