import AppKit
import SwiftUI

// The answer, on a glass card just above Spotlight and as wide as it, so it reads as part of
// Spotlight without covering any of its results. It never becomes key, so typing carries on
// going to Spotlight; resting the pointer on it opens the working.
final class ResultPanel {
    var onHover: () -> Void = {}
    private let panel: NSPanel
    private let face = NSHostingView(rootView: CardView(answer: Solution(exact: "", approx: nil)))
    private let height: CGFloat = 64
    private let gap: CGFloat = 8
    private(set) var isVisible = false
    var frame: NSRect { panel.frame }
    var level: NSWindow.Level { panel.level }

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))  // above Spotlight's
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // The window's own shadow, which falls outside the window and so never catches a click
        // meant for Spotlight's search bar just below.
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let content = ClickView()
        content.onEnter = { [weak self] in self?.onHover() }
        face.autoresizingMask = [.width, .height]
        content.addSubview(face)
        panel.contentView = content
    }

    // window is Spotlight's panel, in points from the top left of the main display.
    func show(_ solution: Solution, window: CGRect) {
        face.rootView = CardView(answer: solution)
        place(window)
        if isVisible { panel.alphaValue = 1 }   // in case it was concealed under the detail panel
        if !isVisible {
            isVisible = true
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.12; panel.animator().alphaValue = 1 }
        }
    }

    // Above Spotlight, whose top edge stays put while its results grow downwards; below it when
    // there is no room above. Called every frame while Spotlight is dragged.
    func place(_ window: CGRect) {
        let primary = NSScreen.screens.first?.frame ?? .zero
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: window.midX, y: primary.height - window.midY)) }
        let top = primary.height - (screen?.visibleFrame.maxY ?? primary.height)
        let y = window.minY - gap - height >= top ? window.minY - gap - height : window.maxY + gap
        let frame = NSRect(x: window.minX, y: primary.height - y - height, width: window.width, height: height)
        // Moving only, as while Spotlight is dragged, needs no redraw of the glass.
        if panel.frame.size == frame.size { panel.setFrameOrigin(frame.origin) } else { panel.setFrame(frame, display: true) }
    }

    // Out of sight while the detail panel, which starts as an exact copy of the card, is over it;
    // back without a fade when the panel has shrunk back into it.
    func conceal() { panel.alphaValue = 0 }
    func reveal() { if isVisible { panel.alphaValue = 1 } }

    // Spotlight is being dragged: the card steps aside rather than trail behind it, and comes back
    // where Spotlight is put down.
    func vanish() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup { $0.duration = 0.08; panel.animator().alphaValue = 0 }
    }

    func reappear() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup { $0.duration = 0.16; panel.animator().alphaValue = 1 }
    }

    func hide(fade: TimeInterval = 0.1) {
        guard isVisible else { return }
        isVisible = false
        NSAnimationContext.runAnimationGroup({ $0.duration = fade; panel.animator().alphaValue = 0 }) { [weak self] in
            if self?.isVisible == false { self?.panel.orderOut(nil) }
        }
    }
}

// Notices the pointer coming to rest on the card, even though the card is never key. A pointer
// passing over it, or arriving with a button held (dragging Spotlight, say), opens nothing.
private final class ClickView: NSView {
    var onEnter: () -> Void = {}
    private var pending: DispatchWorkItem?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) {
        pending?.cancel()
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, NSEvent.pressedMouseButtons == 0,
                  window?.frame.contains(NSEvent.mouseLocation) == true else { return }
            onEnter()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    override func mouseExited(with event: NSEvent) {
        pending?.cancel()
        pending = nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
}

// The card: its face on the same glass the detail panel uses.
struct CardView: View {
    let answer: Solution

    var body: some View {
        CardFace(answer: answer)
            .frame(maxWidth: .infinity)
            .spotlightGlass()
    }
}

// "F_n = 6.55" with the n smaller and below the line, for text outside the typeset maths.
func subscripted(_ s: String, size: CGFloat) -> AttributedString {
    var out = AttributedString()
    for run in subscriptRuns(s) {
        var piece = AttributedString(run.text)
        if run.lowered {
            piece.font = .system(size: size * 0.66)
            piece.baselineOffset = -size * 0.2
        }
        out += piece
    }
    return out
}

// What the card shows, and what the detail panel shows at its top, drawn by the same view so the
// panel opening out of the card does not move or redraw a single character. Line the icon up
// with Spotlight's magnifying glass and the answer with what was typed: 20 and 60 points in from
// the panel's edge, as drawn. (Accessibility puts the search field about 40 points right of
// where it is drawn, so its frame cannot be used for this.)
struct CardFace: View {
    let answer: Solution

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "function")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 33, height: 30)
                .padding(.leading, 16)
                .padding(.trailing, 11)
            VStack(alignment: .leading, spacing: 1) {
                // A digest is sixty-four characters: it is made smaller rather than cut short.
                Text(subscripted(answer.exact, size: 22)).font(.system(size: 22)).minimumScaleFactor(0.4)
                if let approx = answer.approx {
                    Text(approx).font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 24)
            CopyButton()
        }
        .frame(height: 64)
    }
}
