import Foundation

@main
struct CheckRepository {
    static func main() throws {
        let repository = try ManuscriptRepository.scan(at: URL(fileURLWithPath: CommandLine.arguments[1]))
        precondition(repository.files.count == 6)
        precondition(repository.files.first?.section == "Front matter")
        precondition(repository.files.last?.section == "Back matter")
        let changed = repository.files.filter(\.changed)
        precondition(changed.count == 4)
        let edited = repository.files.first { $0.path.hasSuffix("01 first.md") }!
        let contents = try repository.read(edited)
        precondition(contents.original == "# One\nold\n" && contents.current == "# One\nnew\n")
        let newFile = repository.files.first { $0.path.hasSuffix("04 new.md") }!
        let newContents = try repository.read(newFile)
        precondition(newContents.original.isEmpty)
        let deleted = repository.files.first { $0.path.hasSuffix("03 deleted.md") }!
        let deletedContents = try repository.read(deleted)
        precondition(deletedContents.current.isEmpty)
        let parsed = ManuscriptRepository.parseStatus("R  manuscript/chapters/new name.md\0manuscript/chapters/old name.md\0 M manuscript/chapters/other.md\0")
        precondition(parsed.count == 2 && parsed["manuscript/chapters/new name.md"] == "R ")
        print("Passed repository ordering, staged/unstaged/untracked/deleted status, baseline, and rename parsing checks.")
    }
}
