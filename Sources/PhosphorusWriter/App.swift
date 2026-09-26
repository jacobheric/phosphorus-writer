import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WriterCore

enum Paper {
    static let sheet = NSColor.white
    static let margin = Color(white: 0.975)
    static let ink = NSColor(srgbRed: 0.24, green: 0.23, blue: 0.21, alpha: 1)
    static let accent = Color(red: 0.48, green: 0.39, blue: 0.27)
}

struct QuietButton: View {
    @Environment(\.isEnabled) private var isEnabled
    let symbol: String
    let help: String
    var active = false
    var dimWhenDisabled = true
    let action: () -> Void

    var body: some View {
        Button(action: { TooltipAnchor.hideActive(); action() }) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .frame(width: 28, height: 28)
                .foregroundStyle(active ? Paper.accent : Color(nsColor: Paper.ink).opacity(0.65))
                .background(active ? Paper.accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled || !dimWhenDisabled ? 1 : 0.35)
        .background(FastTooltip(text: help))
        .accessibilityLabel(help)
    }
}

private let sampleOriginal = """
# First light

The house was quiet before dawn. Mara stood by the window and watched the last stars disappear over the orchard.

She had left the letter on the table. There was nothing more to say.

Outside, the grass held the night's rain. She opened the door and waited.
"""
private let sampleDraft = """
# First light

The house was still before dawn. Mara stood by the window and watched the last stars fade over the orchard.

She had left the letter on the table.

Outside, the grass held a thousand drops of light. She opened the door.
"""

@MainActor
final class Draft: ObservableObject {
    @Published var formatted = UserDefaults.standard.bool(forKey: "formattedMarkdown") {
        didSet { UserDefaults.standard.set(formatted, forKey: "formattedMarkdown") }
    }
    @Published var fontSize = UserDefaults.standard.object(forKey: "proseFontSize") as? Double ?? 20 {
        didSet { UserDefaults.standard.set(fontSize, forKey: "proseFontSize") }
    }
    func resizeText(_ step: Double) { fontSize = min(36, max(12, fontSize + step)) }

    @Published var text = sampleDraft
    @Published var baseline = sampleOriginal
    @Published var title = "First light"
    @Published var changes: [Change] = []
    @Published var selected = 0
    @Published var reviewing = true
    @Published var calculating = false
    @Published var error: String?
    @Published var repository: ManuscriptRepository?
    @Published var changedOnly = false
    @Published var activePath: String?
    @Published var sidebarPath: String?
    @Published var loading = false
    @Published var writing = false
    @Published var commitPreview: CommitPreview?
    @Published var pushPreview: PushPreview?
    @Published var commitMessage = ""
    @Published var notice: String?
    private var fileURL: URL?
    private var diskSnapshot: Data?
    private var repositoryDirectory: URL?
    private var loadID = UUID()
    private var scanID = UUID()
    var unsaved: Bool { text != savedText }
    var visibleFiles: [ManuscriptFile] {
        (repository?.files ?? []).filter { !changedOnly || $0.changed || ($0.path == activePath && unsaved) }
    }
    weak var editor: NSTextView?
    var editorCoordinator: NativeEditor.Coordinator?
    private var calculation: Task<Void, Never>?
    private var savedText = sampleDraft

    init() {
        let arguments = CommandLine.arguments
        changedOnly = arguments.contains("--changed-only")
        guard let index = arguments.firstIndex(of: "--draft"), arguments.indices.contains(index + 1) else { return }
        do {
            let url = URL(fileURLWithPath: arguments[index + 1])
            repositoryDirectory = url.deletingLastPathComponent()
            let data = try Data(contentsOf: url)
            guard let contents = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
            fileURL = url
            diskSnapshot = data
            text = contents
            baseline = contents
            savedText = contents
            title = url.deletingPathExtension().lastPathComponent
            if let originalIndex = arguments.firstIndex(of: "--original"), arguments.indices.contains(originalIndex + 1) {
                baseline = try String(contentsOfFile: arguments[originalIndex + 1], encoding: .utf8)
            }
        } catch { self.error = error.localizedDescription }
    }

    func openManuscript() {
        guard !writing else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "Choose your manuscript's Git repository"
        guard panel.runModal() == .OK, let url = panel.url, canDiscard() else { return }
        loadID = UUID()
        activePath = nil
        sidebarPath = nil
        fileURL = nil
        diskSnapshot = nil
        savedText = text
        repositoryDirectory = url
        refreshRepository(selectFirst: true)
    }

    func refreshRepository(selectFirst: Bool = false) {
        guard let directory = repositoryDirectory, !loading else { return }
        let request = UUID()
        scanID = request
        Task {
            do {
                let snapshot = try await Task.detached { try ManuscriptRepository.scan(at: directory) }.value
                guard repositoryDirectory == directory, scanID == request else { return }
                let previousRoot = repository?.root
                repository = snapshot
                if activePath == nil, !selectFirst {
                    activePath = snapshot.files.first(where: { URL(fileURLWithPath: $0.path).deletingPathExtension().lastPathComponent == title })?.path
                    sidebarPath = activePath
                }
                if selectFirst || (activePath == nil && previousRoot != snapshot.root) {
                    if let first = snapshot.files.first { selectFile(first) }
                }
            } catch { self.error = error.localizedDescription }
        }
    }

    func selectFile(_ file: ManuscriptFile, focusEditor: Bool = true) {
        guard !writing, let repository else { return }
        if file.path == sidebarPath {
            if focusEditor && !loading { editor?.window?.makeFirstResponder(editor) }
            return
        }
        guard canDiscard() else { return }
        let request = UUID()
        loadID = request
        sidebarPath = file.path
        if file.path == activePath {
            if focusEditor { editor?.window?.makeFirstResponder(editor) }
            loading = false
            return
        }
        loading = true
        Task {
            defer { if loadID == request { loading = false } }
            do {
                let contents = try await Task.detached { try repository.read(file) }.value
                guard loadID == request else { return }
                calculation?.cancel()
                activePath = file.path
                baseline = contents.original
                text = contents.current
                fileURL = repository.root.appendingPathComponent(file.path)
                diskSnapshot = Data(contents.current.utf8)
                savedText = contents.current
                title = file.title
                selected = 0
                changes = []
                editor?.undoManager?.removeAllActions()
                editorCoordinator?.render(cursor: 0)
                editor?.scrollRangeToVisible(NSRange(location: 0, length: 0))
                if focusEditor { editor?.window?.makeFirstResponder(editor) }
                refresh()
            } catch {
                guard loadID == request else { return }
                sidebarPath = activePath
                self.error = error.localizedDescription
            }
        }
    }

    func canDiscard() -> Bool {
        guard !writing else { return false }
        guard text != savedText else { return true }
        let alert = NSAlert()
        alert.messageText = "Discard unsaved draft?"
        alert.informativeText = "Save your edits before leaving this chapter."
        alert.addButton(withTitle: "Keep editing")
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        let response = alert.runModal()
        if response == .alertSecondButtonReturn { save(); return !unsaved }
        return response == .alertThirdButtonReturn
    }

    func refresh() {
        calculation?.cancel()
        calculating = true
        let old = baseline
        let new = text
        calculation = Task {
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            let result = await Task.detached(priority: .userInitiated) {
                Review.changes(from: old, to: new)
            }.value
            guard !Task.isCancelled, text == new, baseline == old else { return }
            changes = result
            selected = min(selected, max(0, result.count - 1))
            calculating = false
        }
    }

    func navigate(_ delta: Int) {
        guard !changes.isEmpty, !calculating else { return }
        selected = (selected + delta + changes.count) % changes.count
        editorCoordinator?.reveal(changes[selected].range)
    }

    func restore() {
        guard !writing, !calculating, changes.indices.contains(selected), let editor else { return }
        let change = changes[selected]
        editorCoordinator?.replace(change.range, with: change.original)
        editor.undoManager?.setActionName("Restore original")
    }

    func openDraft() {
        guard canDiscard() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .text]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard let contents = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
            fileURL = url
            diskSnapshot = data
            loadID = UUID()
            scanID = UUID()
            loading = false
            repository = nil
            activePath = nil
            sidebarPath = nil
            repositoryDirectory = url.deletingLastPathComponent()
            baseline = contents
            text = contents
            savedText = contents
            title = url.deletingPathExtension().lastPathComponent
            editor?.undoManager?.removeAllActions()
            refresh()
            refreshRepository()
        } catch { self.error = error.localizedDescription }
    }

    func chooseBaseline() {
        guard !writing else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .text]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            baseline = try String(contentsOf: url, encoding: .utf8)
            refresh()
        } catch { self.error = error.localizedDescription }
    }

    func save() {
        guard !loading, !writing else { return }
        do {
            if let fileURL {
                if !unsaved { return }
                diskSnapshot = try RepositoryWrites.save(text, to: fileURL, expected: diskSnapshot)
            } else {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = "\(title).md"
                guard panel.runModal() == .OK, let url = panel.url else { return }
                let data = Data(text.utf8)
                try data.write(to: url, options: .atomic)
                fileURL = url
                diskSnapshot = data
                repositoryDirectory = url.deletingLastPathComponent()
            }
            savedText = text
            notice = "Saved"
            refreshRepository()
        } catch { self.error = error.localizedDescription }
    }

    func prepareCommit(path: String? = nil) {
        guard !loading, !writing, let repository else { return }
        if path == nil || path == activePath {
            save()
            guard !unsaved else { return }
        }
        writing = true
        Task {
            defer { writing = false }
            do {
                commitPreview = try await Task.detached { try RepositoryWrites.prepareCommit(at: repository.root, path: path) }.value
                commitMessage = ""
            } catch { self.error = error.localizedDescription }
        }
    }

    func commit() {
        guard !writing, let repository, let preview = commitPreview else { return }
        let message = commitMessage
        writing = true
        Task {
            defer { writing = false }
            do {
                try await Task.detached { try RepositoryWrites.commit(preview, message: message, at: repository.root) }.value
                commitPreview = nil
                notice = "Committed"
                if let file = repository.files.first(where: { $0.path == activePath }) {
                    let contents = try await Task.detached { try repository.read(file) }.value
                    baseline = contents.original
                    refresh()
                }
                refreshRepository()
            } catch { self.error = error.localizedDescription }
        }
    }

    func preparePush() {
        guard !writing, !loading, let repository else { return }
        writing = true
        Task {
            defer { writing = false }
            do {
                pushPreview = try await Task.detached { try RepositoryWrites.preparePush(at: repository.root) }.value
            } catch { self.error = error.localizedDescription }
        }
    }

    func push() {
        guard !writing, let repository, let preview = pushPreview else { return }
        writing = true
        Task {
            defer { writing = false }
            do {
                try await Task.detached { try RepositoryWrites.push(preview, at: repository.root) }.value
                pushPreview = nil
                notice = "Pushed"
            } catch { self.error = error.localizedDescription }
        }
    }

    func saveCopy() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(title)-draft.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        catch { self.error = error.localizedDescription }
    }
}

@MainActor
final class Lifecycle: NSObject, NSApplicationDelegate, NSWindowDelegate {
    weak var draft: Draft?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        draft?.canDiscard() == false ? .terminateCancel : .terminateNow
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { draft?.canDiscard() ?? true }
}

@main
struct WriterApp: App {
    @NSApplicationDelegateAdaptor(Lifecycle.self) private var lifecycle
    @StateObject private var draft = Draft()
    var body: some Scene {
        WindowGroup("Phosphorus") {
            ContentView(draft: draft)
                .frame(minWidth: 850, minHeight: 580)
                .preferredColorScheme(.light)
                .tint(Paper.accent)
                .onAppear {
                    lifecycle.draft = draft
                    NSApp.windows.first?.delegate = lifecycle
                    NSApp.windows.first?.backgroundColor = Paper.sheet
                    NSApp.windows.first?.titlebarAppearsTransparent = true
                    NSApp.windows.first?.titlebarSeparatorStyle = .none
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    draft.refresh()
                    draft.refreshRepository()
                }
        }
        .defaultSize(width: 1180, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Markdown…", action: draft.openDraft).keyboardShortcut("o")
                Button("Save", action: draft.save).keyboardShortcut("s").disabled(draft.loading || draft.writing)
                Button("Save Draft Copy…", action: draft.saveCopy).keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button("Larger Text") { draft.resizeText(2) }.keyboardShortcut("+")
                Button("Smaller Text") { draft.resizeText(-2) }.keyboardShortcut("-")
                Button("Actual Size") { draft.fontSize = 20 }.keyboardShortcut("0")
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var draft: Draft
    @FocusState private var sidebarFocused: Bool
    @State private var sidebarCursor: String?
    private let sections = ["Front matter", "Chapters", "Back matter"]

    private func browse(_ delta: Int, scroll: ScrollViewProxy) -> KeyPress.Result {
        let entries = sections.flatMap { section -> [String] in
            let paths = draft.visibleFiles.filter { $0.section == section }.map(\.path)
            return paths.isEmpty ? [] : ["section:" + section] + paths
        }
        guard !entries.isEmpty else { return .handled }
        let index = entries.firstIndex(of: sidebarCursor ?? draft.sidebarPath ?? "") ?? 0
        let next = entries[min(entries.count - 1, max(0, index + delta))]
        if let file = draft.visibleFiles.first(where: { $0.path == next }) {
            draft.selectFile(file, focusEditor: false)
            guard draft.sidebarPath == next else { return .handled }
        }
        sidebarCursor = next
        scroll.scrollTo(next)
        return .handled
    }

    private func editFromSidebar() -> KeyPress.Result {
        if let cursor = sidebarCursor, cursor.hasPrefix("section:"),
           let file = draft.visibleFiles.first(where: { "section:" + $0.section == cursor }) {
            draft.selectFile(file)
        } else if !draft.loading {
            draft.editor?.window?.makeFirstResponder(draft.editor)
        }
        sidebarFocused = false
        return .handled
    }
    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Text("Manuscript")
                        .font(.system(size: 15, weight: .medium, design: .serif))
                    Spacer()
                    QuietButton(symbol: "line.3.horizontal.decrease", help: draft.changedOnly ? "All files" : "Changes only", active: draft.changedOnly) {
                        draft.changedOnly.toggle()
                    }
                    .accessibilityValue(draft.changedOnly ? "On" : "Off")
                    QuietButton(symbol: "arrow.clockwise", help: "Refresh") {
                        draft.refreshRepository()
                    }
                }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 2)
                if draft.repository != nil {
                    ScrollViewReader { scroll in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(sections, id: \.self) { section in
                                    let files = draft.visibleFiles.filter { $0.section == section }
                                    if !files.isEmpty {
                                        Button {
                                            sidebarCursor = "section:" + section
                                            sidebarFocused = true
                                        } label: {
                                            Text(section).font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(.secondary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.horizontal, 12).frame(height: 24)
                                                .contentShape(Rectangle())
                                        }.buttonStyle(.plain)
                                            .background(sidebarFocused && sidebarCursor == "section:" + section ? Color.black.opacity(0.045) : .clear,
                                                        in: RoundedRectangle(cornerRadius: 9))
                                            .padding(.top, 4).padding(.bottom, 2)
                                            .id("section:" + section)
                                        ForEach(files) { file in
                                            HStack(spacing: 4) {
                                                Button { sidebarFocused = false; sidebarCursor = file.path; draft.selectFile(file) } label: {
                                                    Text(file.title).font(.system(size: 14, design: .serif))
                                                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                                        .frame(height: 34).contentShape(Rectangle())
                                                }.buttonStyle(.plain)
                                                    .accessibilityAddTraits(file.path == draft.sidebarPath ? .isSelected : [])
                                                if file.changed || (file.path == draft.activePath && draft.unsaved) {
                                                    QuietButton(symbol: "checkmark.circle", help: "Commit", dimWhenDisabled: draft.writing) {
                                                        draft.prepareCommit(path: file.path)
                                                    }
                                                    .disabled(draft.loading || draft.writing)
                                                    .accessibilityLabel("Commit " + file.title)
                                                } else {
                                                    Color.clear.frame(width: 28, height: 28)
                                                }
                                            }
                                            .padding(.leading, 12).padding(.trailing, 6).frame(height: 34)
                                            .background((sidebarFocused ? file.path == sidebarCursor : file.path == draft.sidebarPath) ? Color.black.opacity(0.045) : .clear,
                                                        in: RoundedRectangle(cornerRadius: 9))
                                            .id(file.path)
                                        }
                                    }
                                }
                            }.padding(.horizontal, 8).padding(.bottom, 8)
                        }
                        .focusable().focusEffectDisabled().focused($sidebarFocused)
                        .onKeyPress(.upArrow) { browse(-1, scroll: scroll) }
                        .onKeyPress(.downArrow) { browse(1, scroll: scroll) }
                        .onKeyPress(.return) { editFromSidebar() }
                        .onKeyPress(.escape) { editFromSidebar() }

                    }
                    if draft.visibleFiles.isEmpty {
                        Text("No changed chapters").font(.callout).foregroundStyle(.secondary).padding(16)
                    }
                } else {
                    Text(draft.title).padding(16)
                    Button("Open manuscript…", action: draft.openManuscript).padding(.horizontal, 16)
                    Spacer()
                }
                Text("\(draft.repository?.files.count ?? 1) files · \(draft.repository?.files.filter(\.changed).count ?? 0) changed")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 16)
            }.frame(minWidth: 210, idealWidth: 245, maxWidth: 440).background(Paper.margin)
                .layoutPriority(1)
            VStack(spacing: 0) {
                NativeEditor(draft: draft)
                HStack {
                    Text("\(draft.text.split(whereSeparator: { $0.isWhitespace }).count) words")
                    Spacer()
                    Text(draft.writing ? "Working…" : draft.unsaved ? "Unsaved" : draft.notice ?? "")
                    Spacer()
                    Text(draft.calculating ? "Updating review…" : "\(draft.changes.count) changes")
                }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 16)
            }

        }
        .background(Color(nsColor: Paper.sheet))
        .foregroundStyle(Color(nsColor: Paper.ink))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            draft.refreshRepository()
        }
        .toolbar {
            ToolbarItemGroup {
                QuietButton(symbol: "folder", help: "Open", action: draft.openManuscript)
                QuietButton(symbol: "textformat", help: "Format", active: draft.formatted) { draft.formatted.toggle() }
                    .accessibilityValue(draft.formatted ? "On" : "Off")
                QuietButton(symbol: "text.badge.checkmark", help: draft.reviewing ? "Hide changes" : "Show changes", active: draft.reviewing) {
                    draft.reviewing.toggle()
                }
                .accessibilityValue(draft.reviewing ? "On" : "Off")
                HStack(spacing: 4) {
                    QuietButton(symbol: "chevron.up", help: "Previous change") { draft.navigate(-1) }
                    QuietButton(symbol: "chevron.down", help: "Next change") { draft.navigate(1) }
                    QuietButton(symbol: "arrow.uturn.backward", help: "Restore", action: draft.restore)
                }
                .disabled(draft.changes.isEmpty || draft.calculating)
                QuietButton(symbol: "doc.on.doc", help: "Compare", action: draft.chooseBaseline)
                QuietButton(symbol: "square.and.arrow.down", help: "Save", action: draft.save)
                    .disabled(draft.loading || draft.writing)
                QuietButton(symbol: "checkmark.circle", help: "Commit") { draft.prepareCommit() }

                    .disabled(draft.repository == nil || draft.loading || draft.writing)
                QuietButton(symbol: "arrow.up", help: "Push", action: draft.preparePush)
                    .disabled(draft.repository == nil || draft.loading || draft.writing)
            }
        }
        .sheet(isPresented: Binding(get: { draft.commitPreview != nil }, set: { if !$0 { draft.commitPreview = nil } })) {
            if let preview = draft.commitPreview {
                CommitReview(draft: draft, preview: preview)
            }
        }
        .sheet(isPresented: Binding(get: { draft.pushPreview != nil }, set: { if !$0 { draft.pushPreview = nil } })) {
            if let preview = draft.pushPreview {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Push to \(preview.remote)/\(preview.destination.replacingOccurrences(of: "refs/heads/", with: ""))").font(.title2)
                    ScrollView { Text(preview.commits).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    HStack {
                        Button("Cancel") { draft.pushPreview = nil }.keyboardShortcut(.cancelAction)
                        Spacer()
                        Button(draft.writing ? "Pushing…" : "Push", action: draft.push).keyboardShortcut(.defaultAction)
                    }
                }.padding(24).frame(width: 560, height: 320).disabled(draft.writing).interactiveDismissDisabled(draft.writing)
                    .alert("Could not push", isPresented: Binding(get: { draft.error != nil }, set: { if !$0 { draft.error = nil } })) {
                        Button("OK") { draft.error = nil }
                    } message: { Text(draft.error ?? "") }
            }
        }
        .alert("Could not complete action", isPresented: Binding(get: { draft.error != nil && draft.commitPreview == nil && draft.pushPreview == nil }, set: { if !$0 { draft.error = nil } })) {
            Button("OK") { draft.error = nil }
        } message: { Text(draft.error ?? "") }
    }
}

final class ProseTextView: NSTextView {
    var resizeText: ((Double) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .control, .option]) == .command {
            switch event.charactersIgnoringModifiers {
            case "=", "+": resizeText?(2); return true
            case "-": resizeText?(-2); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        textContainerInset = NSSize(width: max(48, (newSize.width - 760) / 2), height: 36)
    }
}

struct NativeEditor: NSViewRepresentable {
    @ObservedObject var draft: Draft
    func makeCoordinator() -> Coordinator { Coordinator(draft: draft) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let editor = ProseTextView(usingTextLayoutManager: true)
        editor.resizeText = { [weak draft] step in draft?.resizeText(step) }
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.textContainerInset = NSSize(width: 52, height: 36)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.backgroundColor = Paper.sheet
        editor.insertionPointColor = Paper.ink
        scroll.backgroundColor = Paper.sheet
        scroll.documentView = editor
        scroll.hasVerticalScroller = true
        draft.editor = editor
        draft.editorCoordinator = context.coordinator
        editor.delegate = context.coordinator
        context.coordinator.render()
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.render()
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        unowned let draft: Draft
        var document = ReviewDocument(original: "", current: "", reviewing: false)
        var lastText: String?
        var lastOriginal: String?
        var lastReview: Bool?
        var lastFontSize: Double?
        var lastFormatted: Bool?
        var rendering = false
        init(draft: Draft) { self.draft = draft }

        func render(cursor: Int? = nil) {
            guard let editor = draft.editor else { return }
            guard lastText != draft.text || lastOriginal != draft.baseline || lastReview != draft.reviewing || lastFontSize != draft.fontSize || lastFormatted != draft.formatted else { return }
            let sourceCursor = cursor ?? document.sourceRange(for: editor.selectedRange())?.location ?? 0
            rendering = true
            defer { rendering = false }
            document = ReviewDocument(original: draft.baseline, current: draft.text, reviewing: draft.reviewing)
            let rendered = ReviewAppearance.render(document, original: draft.baseline, current: draft.text, reviewing: draft.reviewing, fontSize: draft.fontSize, formatted: draft.formatted)
            editor.textStorage?.setAttributedString(rendered.text)
            editor.typingAttributes = rendered.typing
            editor.setSelectedRange(NSRange(location: document.displayOffset(for: min(sourceCursor, draft.text.utf16.count)), length: 0))
            lastText = draft.text
            lastOriginal = draft.baseline
            lastReview = draft.reviewing
            lastFontSize = draft.fontSize
            lastFormatted = draft.formatted
        }

        func replace(_ range: NSRange, with replacement: String) {
            guard let editor = draft.editor else { return }
            let old = (draft.text as NSString).substring(with: range)
            editor.undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.replace(NSRange(location: range.location, length: replacement.utf16.count), with: old)
                }
            }
            draft.text = (draft.text as NSString).replacingCharacters(in: range, with: replacement)
            render(cursor: range.location + replacement.utf16.count)
            draft.refresh()
        }

        func reveal(_ range: NSRange) {
            let display = NSRange(location: document.displayOffset(for: range.location), length: 0)
            draft.editor?.setSelectedRange(display)
            draft.editor?.scrollRangeToVisible(display)
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard !draft.loading, !draft.writing, let replacementString else { return false }
            guard let source = document.sourceRange(for: affectedCharRange) else { NSSound.beep(); return false }
            replace(source, with: replacementString)
            return false
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !rendering, !draft.calculating, let editor = draft.editor,
                  let source = document.sourceRange(for: editor.selectedRange()) else { return }
            if let index = draft.changes.firstIndex(where: { source.location >= $0.range.location && source.location <= NSMaxRange($0.range) }), draft.selected != index {
                draft.selected = index
            }
        }
    }
}
