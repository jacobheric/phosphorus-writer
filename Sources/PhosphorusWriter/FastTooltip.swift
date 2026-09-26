import AppKit
import SwiftUI

struct FastTooltip: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> TooltipAnchor { TooltipAnchor() }
    func updateNSView(_ view: TooltipAnchor, context: Context) { view.label = text }
    static func dismantleNSView(_ view: TooltipAnchor, coordinator: ()) { view.hide() }
}

@MainActor
final class TooltipAnchor: NSView {
    private static weak var active: TooltipAnchor?
    static func hideActive() { active?.hide() }
    var label = ""
    private var pending: DispatchWorkItem?
    private var panel: NSPanel?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        Self.hideActive()
        Self.active = self
        let work = DispatchWorkItem { [weak self] in self?.show() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    override func mouseExited(with event: NSEvent) { hide() }
    override func viewWillMove(toWindow newWindow: NSWindow?) { hide() }

    func hide() {
        pending?.cancel()
        pending = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func show() {
        guard let window, window.isKeyWindow else { return }
        let content = NSHostingView(rootView: Text(label).font(.system(size: 12))
            .foregroundStyle(Color.primary).padding(.horizontal, 9).padding(.vertical, 5)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5)))
        let size = content.fittingSize
        let anchor = window.convertToScreen(convert(bounds, to: nil))
        let screen = window.screen?.visibleFrame ?? anchor
        let x = min(max(anchor.midX - size.width / 2, screen.minX + 6), screen.maxX - size.width - 6)
        let tooltip = TooltipPanel(contentRect: NSRect(x: x, y: anchor.minY - size.height - 6, width: size.width, height: size.height),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        tooltip.isOpaque = false
        tooltip.backgroundColor = .clear
        tooltip.hasShadow = true
        tooltip.ignoresMouseEvents = true
        tooltip.hidesOnDeactivate = true
        tooltip.level = .floating
        tooltip.contentView = content
        tooltip.orderFront(nil)
        panel = tooltip
    }
}

private final class TooltipPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
