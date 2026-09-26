import Foundation

public struct CommitPreview: Sendable {
    public let tree: String
    public let head: String
    public let branch: String
    public let files: String
    public let diff: String
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
        guard try git(["ls-files", "-u"], at: root).isEmpty else { throw failure("Resolve merge conflicts before committing.") }
        for marker in ["MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply"] {
            let location = try git(["rev-parse", "--git-path", marker], at: root).trimmingCharacters(in: .newlines)
            let url = URL(fileURLWithPath: location, relativeTo: root)
            guard !FileManager.default.fileExists(atPath: url.path) else { throw failure("Finish the current Git operation before committing here.") }
        }
        if let path { _ = try git(["add", "--", path], at: root) }
        let files = try git(["diff", "--cached", "--name-status"], at: root)
        guard !files.isEmpty else { throw failure("No staged changes to commit.") }
        return CommitPreview(tree: try git(["write-tree"], at: root), head: try head(at: root), branch: branch,
                             files: files, diff: try git(["diff", "--cached", "--no-ext-diff", "--no-textconv"], at: root))
    }

    public static func commit(_ preview: CommitPreview, message: String, at root: URL) throws {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw failure("Add a commit message.") }
        guard try head(at: root) == preview.head,
              try git(["write-tree"], at: root) == preview.tree,
              try git(["symbolic-ref", "--short", "HEAD"], at: root).trimmingCharacters(in: .newlines) == preview.branch else {
            throw failure("The staged changes or branch changed. Close this review and prepare it again.")
        }
        _ = try git(["commit", "-m", message], at: root)
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

    private static func git(_ arguments: [String], at root: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = root
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw failure(text.isEmpty ? "Git could not complete this action. Check the upstream branch and repository state." : text)
        }
        return text
    }
}
