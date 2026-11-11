import AppKit
import SwiftUI

// The answer, on a glass card just above Spotlight and as wide as it, so it reads as part of
// Spotlight without covering any of its results. It never becomes key, so typing carries on
// going to Spotlight; resting the pointer on it opens the working.
final class ResultPanel {
    var onHover: () -> Void = {}
    private var panel: NSPanel!
    private let face = NSHostingView(rootView: CardView(answer: CardText(solution: Solution(exact: "", approx: nil))))
    private var height = Chrome.cardHeight
    private let gap: CGFloat = 8
    private(set) var isVisible = false
    var frame: NSRect { panel.frame }
    var level: NSWindow.Level { panel.level }

    init() { panel = makePanel() }

    // A new window each time the card comes up. One kept from before can lose its place on every
    // Space, as after the Mac has hibernated, and be left on a single desktop: there it is put up
    // unseen whenever Spotlight is opened anywhere else, over an app in full screen above all, and
    // neither ordering it in again nor setting its behaviour again brings it back. A new window
    // takes a few milliseconds.
    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
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
        panel.contentView = content
        face.removeFromSuperview()
        face.frame = content.bounds
        face.autoresizingMask = [.width, .height]
        content.addSubview(face)
        return panel
    }

    // window is Spotlight's panel, in points from the top left of the main display.
    func show(_ card: CardText, window: CGRect) {
        face.rootView = CardView(answer: card)
        height = card.height
        if isVisible {
            place(window)
            panel.alphaValue = 1   // in case it was concealed under the detail panel
        } else {
            panel.orderOut(nil)    // the last window, perhaps still fading out
            panel = makePanel()
            place(window)
            isVisible = true
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            let panel = panel!
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
        // This window, which the card coming up again before the fade is over will have replaced.
        let panel = panel!
        NSAnimationContext.runAnimationGroup({ $0.duration = fade; panel.animator().alphaValue = 0 }) { panel.orderOut(nil) }
    }
}

// Notices the pointer coming to rest on the card, even though the card is never key. A pointer
// passing over it, or arriving with a button held (dragging Spotlight, say), opens nothing. Nor
// does one that has not moved: a card that comes up under a pointer left where it was, as it
// does at every key while typing, is not the pointer brought to it. Moved on the card, it opens.
private final class ClickView: NSView {
    var onEnter: () -> Void = {}
    private var pending: DispatchWorkItem?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) {
        pending?.cancel()
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let work = DispatchWorkItem { [weak self] in
            // Done with, so that the pointer moved on again tries again.
            self?.pending = nil
            guard let self, NSEvent.pressedMouseButtons == 0,
                  window?.frame.contains(NSEvent.mouseLocation) == true else { return }
            onEnter()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    override func mouseMoved(with event: NSEvent) {
        guard pending == nil else { return }
        mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        pending?.cancel()
        pending = nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }
}

// The card: its face on the same glass the detail panel uses.
struct CardView: View {
    let answer: CardText

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
// The middle of the answer's line, which the card's sign and its button line up with: not the
// middle of the card, which, with what was typed above the answer and a note below it, is not
// beside the answer at all.
extension VerticalAlignment {
    private struct AnswerLine: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[VerticalAlignment.center] }
    }
    static let answerLine = VerticalAlignment(AnswerLine.self)
}

struct CardFace: View {
    let answer: CardText
    // false as the detail panel opens: the input above the answer shrinks away, the working below
    // beginning with it, and grows back as the panel closes into the card.
    var showInput = true

    var body: some View {
        if let list = answer.list { CompletionFace(list: list, symbol: answer.symbol).frame(height: answer.height) } else { face }
    }

    private var face: some View {
        HStack(alignment: .answerLine, spacing: 0) {
            // Close beside the answer it is the sign of, in a box just wide enough for the widest sign.
            Group {
                if let swatch = answer.swatch { SwatchView(swatch: swatch) } else {
                    Image(systemName: answer.symbol)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
                .frame(width: 26, height: 30)
                .padding(.leading, 16)
                .padding(.trailing, 6)
            VStack(alignment: .leading, spacing: 2) {
                // What was typed, as it was understood, first: then the answer to it.
                if let input = answer.input {
                    // How it was read, beside it, where that is worth knowing: x ≠ 2, or 1/ax² taken as (1/a)x².
                    HStack(spacing: 10) {
                        MathText(math: input, size: CardText.inputSize, color: .secondaryLabelColor, wraps: false).layoutPriority(1)
                        if !answer.notes.isEmpty {
                            Text(answer.notes.joined(separator: "; ")).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.tail)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                        // Faded out whole, and a little smaller, sooner than its room closes up,
                        // rather than cut off from below as the room shrinks; back the same way.
                        .scaleEffect(showInput ? 1 : 0.9, anchor: .leading)
                        .opacity(showInput ? 1 : 0)
                        .animation(.easeOut(duration: showInput ? 0.22 : 0.12), value: showInput)
                        .frame(height: showInput ? answer.inputHeight : 0)
                }
                Group {
                    if answer.verbatim {
                        // Exactly as typed: not through subscripted(), which would lower the f of ls my_file.
                        Text(verbatim: answer.solution.exact).font(.system(size: 20, design: .monospaced))
                            .truncationMode(.middle).minimumScaleFactor(0.6)
                    } else if let math = answer.answer {
                        MathText(math: math, size: CardText.answerSize, wraps: false).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        // A digest is sixty-four characters: it is made smaller rather than cut short.
                        Text(subscripted(answer.solution.exact, size: 22)).font(.system(size: 22)).minimumScaleFactor(0.4)
                    }
                }
                .alignmentGuide(.answerLine) { $0[VerticalAlignment.center] }
                if let approx = answer.solution.approx {
                    Text(approx).font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 24)
            CopyButton()
        }
        .frame(height: showInput ? answer.height : CardText(solution: answer.solution, answer: answer.answer).height)
    }
}

// A colour where the card's sign would be: a rounded square of it, with a fine edge so that white
// shows on a light card and black on a dark one; text in one colour on another for a contrast; two
// halves for a distance; the stops in a band for a gradient.
struct SwatchView: View {
    let swatch: Swatch

    private func colour(_ x: RGBA) -> Color { x.shown }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Group {
            switch swatch {
            case .solid(let x): shape.fill(colour(x))
            case .text(let fg, let bg):
                shape.fill(colour(bg)).overlay(Text("Aa").font(.system(size: 11, weight: .semibold)).foregroundStyle(colour(fg)))
            case .pair(let a, let b):
                HStack(spacing: 0) { Rectangle().fill(colour(a)); Rectangle().fill(colour(b)) }.clipShape(shape)
            case .gradient(let stops):
                shape.fill(LinearGradient(colors: stops.map(colour), startPoint: .leading, endPoint: .trailing))
            }
        }
        .overlay(shape.strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5))
        .frame(width: 24, height: 24)
    }
}

// What the card shows: what was typed as it was understood, typeset, above the answer, itself
// typeset where it is one line of mathematics; and how tall that makes the card.
struct CardText {
    var solution: Solution
    var input: Math? = nil
    var answer: Math? = nil
    var notes: [String] = []
    var verbatim = false   // a line for Terminal: drawn as typed, in monospace, never as mathematics
    var symbol = "function"   // the sign on the card's left, for what kind of answer it is
    var swatch: Swatch?        // a colour, drawn in place of the sign
    var list: Completion.List? // completions offered for what is being typed, shown in place of an answer

    static let inputSize: CGFloat = 14, answerSize: CGFloat = 22

    static func of(_ typed: String) -> CardText? {
        guard let found = Solver.answer(typed) else { return nil }
        if Command.parse(typed) != nil { return CardText(solution: found.solution, verbatim: true, symbol: found.symbol) }
        let d = found.details
        // The answer typeset only where the working's one solution is the card's line itself.
        var line = d?.solutions.count == 1 && d?.solutions.first?.plain == found.solution.exact ? d?.solutions.first : nil
        var solution = found.solution
        // A sum too long for the card is its first terms and its last, and how many there are:
        // = 1 + 60x + 1770x² + … + x⁶⁰; the whole is in the working.
        if let whole = line, Typesetter.box(whole, answerSize).width > room, let (short, count) = shortened(whole) {
            line = short
            if solution.approx == nil { solution.approx = "\(count) terms; rest the pointer here for all of them" }
        }
        return CardText(solution: solution, input: found.interpretation, answer: line, notes: found.notes, symbol: found.symbol, swatch: found.swatch)
    }

    // The room across the card for the answer, between the icon and the copy button.
    static let room: CGFloat = 500

    static func shortened(_ m: Math) -> (Math, Int)? {
        var segments: [[Math]] = []
        for piece in Typesetter.flattened(m) {
            if case .text(let s) = piece, [" + ", " − "].contains(s), !(segments.last?.isEmpty ?? true) { segments.append([piece]) }
            else if segments.isEmpty { segments.append([piece]) }
            else { segments[segments.count - 1].append(piece) }
        }
        guard segments.count >= 4, let last = segments.last else { return nil }
        // Each segment measured once, and the first terms added while they fit with … and the last.
        let tail = Typesetter.box(.row([t(" + …")] + last), answerSize).width
        var best: Math?, used: CGFloat = 0
        for k in 1..<(segments.count - 1) {
            used += Typesetter.box(.row(segments[k - 1]), answerSize).width
            guard used + tail <= room else { break }
            best = Math.row(segments.prefix(k).flatMap { $0 } + [t(" + …")] + last)
        }
        return best.map { ($0, segments.count) }
    }

    // Spotlight's own height where that is room enough; taller by what the typeset lines need,
    // the input above and a stacked fraction in the answer, with ten points clear above and below.
    private func tall(_ m: Math, _ size: CGFloat) -> CGFloat { let b = Typesetter.box(m, size); return ceil(b.ascent + b.descent + 4) }
    // The input's own line, without the gap under it.
    var inputHeight: CGFloat { input.map { tall($0, CardText.inputSize) } ?? 0 }

    // The card for a list of completions: what fits where the caret is, with the chosen one marked.
    static func offering(_ list: Completion.List) -> CardText {
        CardText(solution: Solution(exact: "", approx: nil), symbol: "moon.stars", list: list)
    }

    var height: CGFloat {
        if let list { return CompletionFace.height(list) }
        let inputHeight = input.map { tall($0, CardText.inputSize) + 2 } ?? 0
        let answerHeight = answer.map { tall($0, CardText.answerSize) } ?? 27
        let total = 20 + inputHeight + answerHeight + (solution.approx == nil ? 0 : 19)
        return min(max(Chrome.cardHeight, total), 160)
    }
}

// The completions offered as a call after @ is typed: a heading saying what is being chosen, a few
// rows at a time with the chosen one marked as Spotlight marks its own, and the keys that work it.
// The rows scroll with the choice, so the chosen one is always in view.
struct CompletionFace: View {
    let list: Completion.List
    let symbol: String

    static let rows = 6, rowHeight: CGFloat = 28
    static func height(_ list: Completion.List) -> CGFloat {
        20 + 18 + CGFloat(min(list.items.count, rows)) * rowHeight + 20
    }

    private var heading: String {
        switch list.stage {
        case .function: return list.fragment.isEmpty ? "Astronomy: choose a function" : "Functions matching “\(list.fragment)”"
        case .argument(let function, _, let first):
            let parameter = list.parameter ?? first
            return "\(function): \(parameter.name), \(Kind.of(parameter.kind).title)"
        }
    }

    var body: some View {
        let first = max(0, min(list.selected - CompletionFace.rows / 2, list.items.count - CompletionFace.rows))
        let shown = Array(list.items.enumerated()).dropFirst(first).prefix(CompletionFace.rows)
        HStack(alignment: .top, spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 30)
                .padding(.leading, 16)
                .padding(.trailing, 6)
            VStack(alignment: .leading, spacing: 0) {
                Text(heading).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
                    .frame(height: 18, alignment: .center)
                ForEach(Array(shown), id: \.offset) { i, item in
                    let chosen = i == list.selected
                    HStack(spacing: 12) {
                        Text(verbatim: item.title).font(.system(size: 15, design: .monospaced)).lineLimit(1).layoutPriority(1)
                        Spacer(minLength: 8)
                        Text(subscripted(item.detail, size: 12)).font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
                            .foregroundStyle(chosen ? AnyShapeStyle(Color.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                    }
                    .foregroundStyle(chosen ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
                    .padding(.horizontal, 10)
                    .frame(height: CompletionFace.rowHeight)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(chosen ? Color.accentColor : Color.clear))
                }
                Text("↑ ↓ to choose · Tab or Return to complete · Esc to close")
                    .font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
                    .frame(height: 20, alignment: .center)
            }
            .padding(.trailing, 16)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
