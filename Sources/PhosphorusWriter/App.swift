import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WriterCore

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
        guard let index = arguments.firstIndex(of: "--draft"), arguments.indices.contains(index + 1) else { return }
        do {
            let url = URL(fileURLWithPath: arguments[index + 1])
            repositoryDirectory = url.deletingLastPathComponent()
            let contents = try String(contentsOf: url, encoding: .utf8)
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
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "Choose your manuscript's Git repository"
        guard panel.runModal() == .OK, let url = panel.url, canDiscard() else { return }
        loadID = UUID()
        activePath = nil
        sidebarPath = nil
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

    func selectFile(_ file: ManuscriptFile) {
        guard file.path != sidebarPath, let repository else { return }
        guard canDiscard() else { return }
        let request = UUID()
        loadID = request
        sidebarPath = file.path
        if file.path == activePath {
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
                savedText = contents.current
                title = file.title
                selected = 0
                changes = []
                editor?.undoManager?.removeAllActions()
                editorCoordinator?.render(cursor: 0)
                editor?.scrollRangeToVisible(NSRange(location: 0, length: 0))
                refresh()
            } catch {
                guard loadID == request else { return }
                sidebarPath = activePath
                self.error = error.localizedDescription
            }
        }
    }

    func canDiscard() -> Bool {
        guard text != savedText else { return true }
        let alert = NSAlert()
        alert.messageText = "Discard unsaved draft?"
        alert.informativeText = "Save a draft copy first if you want to keep these edits."
        alert.addButton(withTitle: "Keep editing")
        alert.addButton(withTitle: "Discard")
        return alert.runModal() == .alertSecondButtonReturn
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
        guard !calculating, changes.indices.contains(selected), let editor else { return }
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
            let contents = try String(contentsOf: url, encoding: .utf8)
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
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .text]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            baseline = try String(contentsOf: url, encoding: .utf8)
            refresh()
        } catch { self.error = error.localizedDescription }
    }

    func saveCopy() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(title)-draft.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            savedText = text
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
        WindowGroup("Phosphorus Writer") {
            ContentView(draft: draft)
                .frame(minWidth: 850, minHeight: 580)
                .onAppear {
                    lifecycle.draft = draft
                    NSApp.windows.first?.delegate = lifecycle
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
                Button("Save Draft Copy…", action: draft.saveCopy).keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var draft: Draft
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("MANUSCRIPT").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(action: { draft.changedOnly.toggle() }) {
                        Image(systemName: draft.changedOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .foregroundStyle(draft.changedOnly ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(draft.changedOnly ? "Show all files" : "Show only files with local changes")
                    .accessibilityLabel("Filter changed files")
                    .accessibilityValue(draft.changedOnly ? "On" : "Off")
                    Button(action: { draft.refreshRepository() }) { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).help("Refresh local changes")
                }.padding(.horizontal, 16).padding(.top, 20)
                if draft.repository != nil {
                    List(selection: Binding<String?>(get: { draft.sidebarPath }, set: { path in
                        if let file = draft.repository?.files.first(where: { $0.path == path }) { draft.selectFile(file) }
                    })) {
                        ForEach(["Front matter", "Chapters", "Back matter"], id: \.self) { section in
                            let files = draft.visibleFiles.filter { $0.section == section }
                            if !files.isEmpty {
                                Section(section) {
                                    ForEach(files) { file in
                                        HStack {
                                            Text(file.title).lineLimit(1)
                                            Spacer()
                                            if file.changed || (file.path == draft.activePath && draft.unsaved) {
                                                Circle().fill(.orange).frame(width: 6, height: 6)
                                                    .accessibilityLabel("Local changes")
                                            }
                                        }.tag(file.path).help(file.path + (file.changed ? " — local changes" : ""))
                                    }
                                }
                            }
                        }
                    }.listStyle(.sidebar)
                    if draft.visibleFiles.isEmpty {
                        Text("No changed chapters").font(.callout).foregroundStyle(.secondary).padding(16)
                    }
                } else {
                    Text(draft.title).padding(16)
                    Button("Open manuscript…", action: draft.openManuscript).padding(.horizontal, 16)
                    Spacer()
                }
                Text("\(draft.repository?.files.count ?? 1) files · \(draft.repository?.files.filter(\.changed).count ?? 0) changed")
                    .font(.caption).foregroundStyle(.secondary).padding(16)
            }.frame(width: 225).background(.bar)
            Divider()
            VStack(spacing: 0) {
                NativeEditor(draft: draft).disabled(draft.loading)
                Divider()
                HStack {
                    Text("\(draft.text.split(whereSeparator: { $0.isWhitespace }).count) words")
                    Spacer()
                    Text(draft.calculating ? "Updating review…" : "\(draft.changes.count) changes")
                }.font(.caption).foregroundStyle(.secondary).padding(12)
            }

        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            draft.refreshRepository()
        }
        .toolbar {
            Button("Open manuscript…", action: draft.openManuscript)
            Toggle("Review", isOn: $draft.reviewing)
            Button(action: { draft.navigate(-1) }) { Image(systemName: "chevron.up") }
                .help("Previous change")
            Button(action: { draft.navigate(1) }) { Image(systemName: "chevron.down") }
                .help("Next change")
            Button("Restore change", action: draft.restore).disabled(draft.changes.isEmpty || draft.calculating)
            Button("Compare with…", action: draft.chooseBaseline)
            Button("Save copy…", action: draft.saveCopy)
        }
        .alert("Could not complete action", isPresented: Binding(get: { draft.error != nil }, set: { if !$0 { draft.error = nil } })) {
            Button("OK") { draft.error = nil }
        } message: { Text(draft.error ?? "") }
    }
}

final class ProseTextView: NSTextView {
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
        editor.backgroundColor = .textBackgroundColor
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
        var rendering = false
        init(draft: Draft) { self.draft = draft }

        func render(cursor: Int? = nil) {
            guard let editor = draft.editor else { return }
            guard lastText != draft.text || lastOriginal != draft.baseline || lastReview != draft.reviewing else { return }
            let sourceCursor = cursor ?? document.sourceRange(for: editor.selectedRange())?.location ?? 0
            rendering = true
            defer { rendering = false }
            document = ReviewDocument(original: draft.baseline, current: draft.text, reviewing: draft.reviewing)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 8
            paragraph.paragraphSpacing = 8
            let font = NSFont(name: "Charter", size: 20) ?? .systemFont(ofSize: 20)
            let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph]
            let result = NSMutableAttributedString(string: document.text, attributes: base)
            for span in document.spans {
                switch span.kind {
                case .original:
                    result.addAttribute(.backgroundColor, value: NSColor.systemRed.withAlphaComponent(0.13), range: span.display)
                    result.addAttribute(.foregroundColor, value: NSColor.labelColor.withAlphaComponent(0.75), range: span.display)
                case .current:
                    result.addAttribute(.backgroundColor, value: NSColor.systemGreen.withAlphaComponent(0.14), range: span.display)
                case .label:
                    result.addAttributes([.font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: NSColor.secondaryLabelColor], range: span.display)
                case .unchanged: break
                }
            }
            if draft.reviewing {
                for change in Review.changes(from: draft.baseline, to: draft.text) where change.range.length > 0 {
                    for span in document.spans {
                        guard let source = span.source else { continue }
                        let overlap = NSIntersectionRange(source, change.range)
                        guard overlap.length > 0 else { continue }
                        let range = NSRange(location: span.display.location + overlap.location - source.location, length: overlap.length)
                        result.addAttribute(.backgroundColor, value: NSColor.systemGreen.withAlphaComponent(0.33), range: range)
                    }
                }
                for change in Review.changes(from: draft.text, to: draft.baseline) where change.range.length > 0 {
                    // Original blocks follow the baseline in order; locate them without adding their text to the saved draft.
                    var originalPosition = 0
                    for span in document.spans {
                        if span.kind == .original || span.kind == .unchanged {
                            let oldRange = NSRange(location: originalPosition, length: span.display.length)
                            let overlap = NSIntersectionRange(oldRange, change.range)
                            if span.kind == .original && overlap.length > 0 {
                                result.addAttribute(.backgroundColor, value: NSColor.systemRed.withAlphaComponent(0.3), range: NSRange(location: span.display.location + overlap.location - oldRange.location, length: overlap.length))
                            }
                            originalPosition += span.display.length
                        }
                    }
                }
            }
            editor.textStorage?.setAttributedString(result)
            editor.typingAttributes = base
            editor.setSelectedRange(NSRange(location: document.displayOffset(for: min(sourceCursor, draft.text.utf16.count)), length: 0))
            lastText = draft.text
            lastOriginal = draft.baseline
            lastReview = draft.reviewing
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
            guard !draft.loading, let replacementString else { return false }
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
