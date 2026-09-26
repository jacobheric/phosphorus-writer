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
        let markers = ["MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply"]
        let locations = try git(["rev-parse"] + markers.flatMap { ["--git-path", $0] }, at: root)
        for location in locations.split(separator: "\n") {
            let url = URL(fileURLWithPath: String(location), relativeTo: root)
            guard !FileManager.default.fileExists(atPath: url.path) else { throw failure("Finish the current Git operation first.") }
        }
        let head = try head(at: root)
        let indexTree = try git(["write-tree"], at: root)
        return try withIndex { index in
            try git(["read-tree", path == nil ? indexTree : head], at: root, index: index)
            try git(path.map { ["add", "--", ":(literal)" + $0] } ?? ["add", "-A"], at: root, index: index)
            let tree = try git(["write-tree"], at: root, index: index)
            let records = try git(["diff", "--raw", "--no-abbrev", "--no-renames", "-z", head, tree], at: root)
                .split(separator: "\0").map(String.init)
            var entries: [(path: String, fields: [String])] = []
            guard records.count.isMultiple(of: 2) else { throw failure("Could not read changed files.") }
            for offset in stride(from: 0, to: records.count, by: 2) {
                let fields = records[offset].dropFirst().split(separator: " ").map(String.init)
                guard fields.count == 5 else { throw failure("Could not read changed files.") }
                entries.append((records[offset + 1], fields))
            }
            let objectIDs: [String] = entries.flatMap { entry -> [String] in
                [0, 1].filter { entry.fields[$0] != "160000" }.map { entry.fields[$0 + 2] }
            }
            let ids = Set(objectIDs.filter { !$0.allSatisfy { $0 == "0" } })
            let blobs = try readBlobs(ids.sorted(), at: root)
            func text(_ id: String, mode: String) -> String? {
                if mode == "000000" { return "" }
                guard mode != "160000", let bytes = blobs[id], !bytes.contains(0) else { return nil }
                return String(data: bytes, encoding: .utf8)
            }
            let files = entries.map { entry in
                let fields = entry.fields
                return CommitFile(path: entry.path, status: fields[4], original: text(fields[2], mode: fields[0]), current: text(fields[3], mode: fields[1]),
                                  oldMode: fields[0] == "000000" ? "" : fields[0], newMode: fields[1] == "000000" ? "" : fields[1])
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

    private static func readBlobs(_ ids: [String], at root: URL) throws -> [String: Data] {
        guard !ids.isEmpty else { return [:] }
        let data = try gitData(["cat-file", "--batch"], at: root, input: Data((ids.joined(separator: "\n") + "\n").utf8))
        var cursor = 0
        var result: [String: Data] = [:]
        for id in ids {
            guard let newline = data[cursor...].firstIndex(of: 10) else { throw failure("Incomplete Git object.") }
            let fields = String(decoding: data[cursor..<newline], as: UTF8.self).split(separator: " ")
            guard fields.count == 3, fields[0] == id, let size = Int(fields[2]), size >= 0 else { throw failure("Could not read Git object.") }
            cursor = newline + 1
            guard size < data.count - cursor, data[cursor + size] == 10 else { throw failure("Incomplete Git object.") }
            if fields[1] == "blob" { result[id] = data.subdata(in: cursor..<(cursor + size)) }
            cursor += size + 1
        }
        return result
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

    private static func gitData(_ arguments: [String], at root: URL, index: String? = nil, input: Data? = nil) throws -> Data {
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
        let inputURL = FileManager.default.temporaryDirectory.appendingPathComponent("phosphorus-input-" + UUID().uuidString)
        var inputFile: FileHandle?
        defer {
            try? inputFile?.close()
            if input != nil { try? FileManager.default.removeItem(at: inputURL) }
        }
        if let input {
            // A file avoids blocking on stdin while Git is filling its stdout pipe.
            try input.write(to: inputURL)
            inputFile = try FileHandle(forReadingFrom: inputURL)
        }
        process.standardInput = inputFile ?? FileHandle.nullDevice
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
