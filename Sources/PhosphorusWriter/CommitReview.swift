import AppKit
import SwiftUI
import WriterCore

struct CommitReview: View {
    @ObservedObject var draft: Draft
    let preview: CommitPreview
    @State private var selection: String?
    @State private var prepared: [String: PreparedCommitText] = [:]

    private var selectedFile: CommitFile? {
        preview.files.first { $0.path == selection } ?? preview.files.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(preview.partial ? "Commit change" : preview.chapter == nil ? "Commit" : "Commit chapter").font(.title2)
                Spacer()
                Text("\(preview.files.count) \(preview.files.count == 1 ? "file" : "files") · \(preview.branch)")
                    .font(.callout).foregroundStyle(.secondary)
            }.padding(24)
            Divider()
            HStack(spacing: 0) {
                if preview.chapter == nil {
                    List(preview.files, selection: Binding<String?>(get: { selectedFile?.path }, set: { selection = $0 })) { file in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(URL(fileURLWithPath: file.path).lastPathComponent).lineLimit(1)
                            Text(file.path).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }.padding(.vertical, 6).tag(file.path)
                    }
                    .listStyle(.sidebar).scrollContentBackground(.hidden)
                    .frame(width: 230).background(Paper.margin)
                    Divider()
                }
                if preview.files.isEmpty {
                    Text("No changes").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let file = selectedFile {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(file.path).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(file.status == "A" ? "Added" : file.status == "D" ? "Deleted" : "Modified")
                                .foregroundStyle(.secondary)
                        }.font(.caption).padding(.horizontal, 24).padding(.vertical, 14)
                        if file.oldMode != file.newMode, !file.oldMode.isEmpty, !file.newMode.isEmpty {
                            Text("Mode: \(file.oldMode) → \(file.newMode)").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24)
                        }
                        if file.original != nil, file.current != nil {
                            if let content = prepared[file.path] {
                                CommitText(content: content).id(file.path)
                            } else {
                                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "doc").font(.largeTitle)
                                Text("No text preview").foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            HStack(spacing: 16) {
                TextField("Message", text: $draft.commitMessage).textFieldStyle(.roundedBorder)
                Button("Cancel") { draft.commitPreview = nil }.keyboardShortcut(.cancelAction)
                Button(draft.writing ? "Committing…" : "Commit", action: draft.commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(preview.files.isEmpty || draft.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(24)
        }
        .frame(width: preview.chapter == nil ? 940 : 760, height: 620)
        .background(Color(nsColor: Paper.sheet))
        .task(id: selectedFile?.path) {
            guard let file = selectedFile, prepared[file.path] == nil,
                  let original = file.original, let current = file.current else { return }
            let content = await Task.detached(priority: .userInitiated) {
                PreparedCommitText(original: original, current: current)
            }.value
            guard !Task.isCancelled else { return }
            prepared[file.path] = content
        }
        .disabled(draft.writing).interactiveDismissDisabled(draft.writing)
        .alert("Could not commit", isPresented: Binding(get: { draft.error != nil }, set: { if !$0 { draft.error = nil } })) {
            Button("OK") { draft.error = nil }
        } message: { Text(draft.error ?? "") }
    }
}

private struct PreparedCommitText: Sendable {
    let original: String
    let current: String
    let document: ReviewDocument
    let changes: [Change]

    init(original: String, current: String) {
        self.original = original
        self.current = current
        document = ReviewDocument(original: original, current: current, reviewing: true)
        changes = Review.changes(from: original, to: current)
    }
}

private struct CommitText: NSViewRepresentable {
    let content: PreparedCommitText

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let editor = NSTextView(usingTextLayoutManager: true)
        editor.isEditable = false
        editor.isSelectable = true
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainerInset = NSSize(width: 24, height: 20)
        editor.backgroundColor = Paper.sheet
        editor.textStorage?.setAttributedString(ReviewAppearance.render(content.document, original: content.original, current: content.current, changes: content.changes).text)
        scroll.documentView = editor
        scroll.hasVerticalScroller = true
        scroll.backgroundColor = Paper.sheet
        return scroll
    }

    func updateNSView(_ view: NSScrollView, context: Context) { }
}
