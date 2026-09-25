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
    weak var editor: NSTextView?
    private var calculation: Task<Void, Never>?
    private var savedText = sampleDraft

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
        editor?.setSelectedRange(changes[selected].range)
        editor?.scrollRangeToVisible(changes[selected].range)
    }

    func restore() {
        guard !calculating, changes.indices.contains(selected), let editor else { return }
        let change = changes[selected]
        editor.insertText(change.original, replacementRange: change.range)
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
            baseline = contents
            text = contents
            savedText = contents
            title = url.deletingPathExtension().lastPathComponent
            editor?.undoManager?.removeAllActions()
            refresh()
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
            VStack(alignment: .leading, spacing: 16) {
                Text("MANUSCRIPT").font(.caption).foregroundStyle(.secondary)
                Label(draft.title, systemImage: "doc.text").font(.headline)
                Text("Editor prototype").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("In-memory draft\nSave a copy to keep your work.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20).frame(width: 180).background(.bar)
            Divider()
            VStack(spacing: 0) {
                NativeEditor(draft: draft)
                Divider()
                HStack {
                    Text("\(draft.text.split(whereSeparator: { $0.isWhitespace }).count) words")
                    Spacer()
                    Text(draft.calculating ? "Updating review…" : "\(draft.changes.count) changes")
                }.font(.caption).foregroundStyle(.secondary).padding(12)
            }
            if draft.reviewing {
                Divider()
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("REVIEW").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(action: { draft.navigate(-1) }) { Image(systemName: "chevron.up") }
                        Button(action: { draft.navigate(1) }) { Image(systemName: "chevron.down") }
                    }
                    if draft.changes.indices.contains(draft.selected) {
                        let change = draft.changes[draft.selected]
                        Text("Change \(draft.selected + 1) of \(draft.changes.count)").font(.headline)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Original").font(.caption).foregroundStyle(.secondary)
                                Text(change.original.isEmpty ? "(nothing)" : change.original)
                                    .textSelection(.enabled).foregroundStyle(.red)
                                Divider()
                                Text("Current").font(.caption).foregroundStyle(.secondary)
                                Text(change.replacement.isEmpty ? "(deleted)" : change.replacement)
                                    .textSelection(.enabled)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Button("Restore original", action: draft.restore).disabled(draft.calculating)
                    } else {
                        Text("No changes").font(.headline)
                        Text("Edit the draft to start reviewing.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Choose original file…", action: draft.chooseBaseline)
                    Text("Comparing with the opened file or chosen original. Git staging comes next.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(20).frame(width: 240)
            }
        }
        .toolbar {
            Button("Open…", action: draft.openDraft)
            Toggle("Review", isOn: $draft.reviewing)
            Button("Save copy…", action: draft.saveCopy)
        }
        .alert("Could not complete action", isPresented: Binding(get: { draft.error != nil }, set: { if !$0 { draft.error = nil } })) {
            Button("OK") { draft.error = nil }
        } message: { Text(draft.error ?? "") }
    }
}

struct NativeEditor: NSViewRepresentable {
    @ObservedObject var draft: Draft

    func makeCoordinator() -> Coordinator { Coordinator(draft: draft) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let editor = NSTextView(usingTextLayoutManager: true)
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isContinuousSpellCheckingEnabled = true
        editor.font = .systemFont(ofSize: 20, weight: .regular).withDesign(.serif)
        editor.textColor = .textColor
        editor.backgroundColor = .textBackgroundColor
        editor.textContainerInset = NSSize(width: 40, height: 36)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.minSize = NSSize(width: 0, height: 0)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 7
        editor.defaultParagraphStyle = paragraph
        editor.typingAttributes = [.font: editor.font!, .paragraphStyle: paragraph, .foregroundColor: NSColor.textColor]
        editor.string = draft.text
        editor.delegate = context.coordinator
        scroll.documentView = editor
        scroll.hasVerticalScroller = true
        draft.editor = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? NSTextView else { return }
        if editor.string != draft.text { editor.string = draft.text }
        guard let storage = editor.textStorage else { return }
        let range = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.removeAttribute(.backgroundColor, range: range)
        storage.removeAttribute(.underlineStyle, range: range)
        if draft.reviewing && !draft.calculating {
            for change in draft.changes {
                if change.range.length > 0 {
                    storage.addAttribute(.backgroundColor, value: NSColor.systemGreen.withAlphaComponent(0.16), range: change.range)
                } else if storage.length > 0 {
                    let location = min(change.range.location, storage.length - 1)
                    let anchor = (storage.string as NSString).rangeOfComposedCharacterSequence(at: location)
                    storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.double.rawValue, range: anchor)
                }
            }
        }
        storage.endEditing()
        editor.typingAttributes.removeValue(forKey: .backgroundColor)
        editor.typingAttributes.removeValue(forKey: .underlineStyle)
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        let draft: Draft
        init(draft: Draft) { self.draft = draft }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            draft.text = editor.string
            draft.refresh()
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !draft.calculating, let editor = notification.object as? NSTextView else { return }
            let cursor = editor.selectedRange().location
            if let index = draft.changes.firstIndex(where: { cursor >= $0.range.location && cursor <= NSMaxRange($0.range) }) {
                if draft.selected != index { draft.selected = index }
            }
        }
    }
}

extension NSFont {
    func withDesign(_ design: NSFontDescriptor.SystemDesign) -> NSFont {
        guard let descriptor = fontDescriptor.withDesign(design) else { return self }
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
