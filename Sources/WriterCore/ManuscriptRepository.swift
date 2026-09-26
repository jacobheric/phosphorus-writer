import Foundation
import Dispatch

public struct ManuscriptFile: Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let title: String
    public let section: String
    public let changed: Bool
    public let status: String
}

public struct ManuscriptRepository: Sendable {
    public let root: URL
    public let files: [ManuscriptFile]

    public static func scan(at directory: URL) throws -> ManuscriptRepository {
        let rootPath = try git(["rev-parse", "--show-toplevel"], at: directory).trimmingCharacters(in: .newlines)
        let root = URL(fileURLWithPath: rootPath)
        let status = try git(["status", "--porcelain=v1", "-z", "--untracked-files=all"], at: root)
        let statuses = parseStatus(status)
        let listed = try git(["ls-files", "--cached", "--others", "--exclude-standard", "-z"], at: root)
        let paths = Set(listed.split(separator: "\0").map(String.init)).union(statuses.keys)
        let hasManuscript = FileManager.default.fileExists(atPath: root.appendingPathComponent("manuscript").path)
        let files = paths.filter { $0.hasSuffix(".md") && (!hasManuscript || $0.hasPrefix("manuscript/")) }.map { path in
            let url = root.appendingPathComponent(path)
            let contents = try? String(contentsOf: url, encoding: .utf8)
            let heading = contents?.components(separatedBy: .newlines).first(where: { $0.hasPrefix("# ") })
            let section = path.contains("/frontmatter/") ? "Front matter" : path.contains("/backmatter/") ? "Back matter" : "Chapters"
            return ManuscriptFile(path: path, title: heading.map { String($0.dropFirst(2)) } ?? url.deletingPathExtension().lastPathComponent, section: section, changed: statuses[path] != nil, status: statuses[path] ?? "")
        }.sorted { first, second in
            let order = ["Front matter": 0, "Chapters": 1, "Back matter": 2]
            if first.section != second.section { return order[first.section, default: 1] < order[second.section, default: 1] }
            return first.path.localizedStandardCompare(second.path) == .orderedAscending
        }
        return ManuscriptRepository(root: root, files: files)
    }

    public func read(_ file: ManuscriptFile) throws -> (current: String, original: String) {
        let url = root.appendingPathComponent(file.path)
        let current: String
        if FileManager.default.fileExists(atPath: url.path) {
            current = try String(contentsOf: url, encoding: .utf8)
        } else if file.status.contains("D") {
            current = ""
        } else {
            throw CocoaError(.fileNoSuchFile)
        }
        let original = try RepositoryWrites.stagedText(at: root, path: file.path)
        return (current, original)
    }

    public static func parseStatus(_ output: String) -> [String: String] {
        let records = output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var result: [String: String] = [:]
        var index = 0
        while index < records.count {
            let record = records[index]
            guard record.count >= 4 else { index += 1; continue }
            let status = String(record.prefix(2))
            result[String(record.dropFirst(3))] = status
            index += status.contains("R") || status.contains("C") ? 2 : 1
        }
        return result
    }

    private static func git(_ arguments: [String], at directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        // The exit callback avoids waitUntilExit’s delay on short Git commands.
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        exited.wait()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "PhosphorusGit", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Could not read Git data in \(directory.lastPathComponent). Check that this is a Git repository."])
        }
        guard let string = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        return string
    }
}
