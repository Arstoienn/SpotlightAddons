import AppKit
import CoreText
import SwiftUI

// Typesets Math in SF Pro, the way Apple's Math Notes does: a box for each piece with a width,
// a height above the baseline and a depth below it, put together like TeX does, and drawn
// with Core Text.

struct Box {
    var width: CGFloat
    var ascent: CGFloat
    var descent: CGFloat
    var draw: (CGContext, CGPoint) -> Void   // at the left end of the baseline, y up
}

enum Typesetter {
    static func box(_ m: Math, _ size: CGFloat) -> Box {
        switch m {
        case .text(let s): return text(s, size)
        case .row(let parts): return row(parts.map { box($0, size) })
        case .fraction(let n, let d): return fraction(box(n, size * 0.88), box(d, size * 0.88), size)
        case .root(let x): return root(box(x, size), size)
        case .power(let b, let e): return power(box(b, size), box(e, size * 0.64), size)
        case .bigOperator(let symbol, let lower, let upper):
            return bigOperator(symbol, box(lower, size * 0.62), box(upper, size * 0.62), size)
        }
    }

    // Heights from the type's proportions rather than the font's line metrics, which leave room
    // for accents and would set fractions loose.
    static func text(_ s: String, _ size: CGFloat) -> Box {
        // F_n: the n smaller and below the line.
        let runs = subscriptRuns(s)
        guard runs.count == 1 else {
            return row(runs.map { run in
                guard run.lowered else { return plain(run.text, size) }
                let small = plain(run.text, size * 0.66), drop = size * 0.2
                return Box(width: small.width + size * 0.03, ascent: max(0, small.ascent - drop), descent: small.descent + drop) { ctx, o in
                    small.draw(ctx, CGPoint(x: o.x + size * 0.02, y: o.y - drop))
                }
            })
        }
        return plain(s, size)
    }

    static func plain(_ s: String, _ size: CGFloat) -> Box {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size),
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attributes))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        return Box(width: width, ascent: size * 0.76, descent: size * 0.22) { ctx, origin in
            ctx.textPosition = origin
            CTLineDraw(line, ctx)
        }
    }

    static func row(_ boxes: [Box]) -> Box {
        let width = boxes.reduce(0) { $0 + $1.width }
        return Box(width: width, ascent: boxes.map(\.ascent).max() ?? 0, descent: boxes.map(\.descent).max() ?? 0) { ctx, origin in
            var x = origin.x
            for b in boxes {
                b.draw(ctx, CGPoint(x: x, y: origin.y))
                x += b.width
            }
        }
    }

    // The bar sits on the maths axis, the height of a minus sign, so it lines up with = and −.
    static func fraction(_ n: Box, _ d: Box, _ size: CGFloat) -> Box {
        let axis = size * 0.28, rule = max(1, size * 0.055), gap = size * 0.14, pad = size * 0.14
        let width = max(n.width, d.width) + 2 * pad
        let ascent = axis + rule / 2 + gap + n.descent + n.ascent
        let descent = rule / 2 + gap + d.ascent + d.descent - axis
        return Box(width: width, ascent: ascent, descent: descent) { ctx, o in
            ctx.fill(CGRect(x: o.x + pad / 2, y: o.y + axis - rule / 2, width: width - pad, height: rule))
            n.draw(ctx, CGPoint(x: o.x + (width - n.width) / 2, y: o.y + axis + rule / 2 + gap + n.descent))
            d.draw(ctx, CGPoint(x: o.x + (width - d.width) / 2, y: o.y + axis - rule / 2 - gap - d.ascent))
        }
    }

    // A tick, a stroke down, a long stroke up, and the bar over what is under the root.
    static func root(_ x: Box, _ size: CGFloat) -> Box {
        let rule = max(1, size * 0.06), clearance = size * 0.12, sign = size * 0.52, inset = size * 0.04
        let ascent = x.ascent + clearance + rule, descent = x.descent + size * 0.04
        let width = sign + inset + x.width + size * 0.08
        return Box(width: width, ascent: ascent, descent: descent) { ctx, o in
            let top = o.y + ascent - rule / 2, bottom = o.y - descent, height = top - bottom
            ctx.saveGState()
            ctx.setLineWidth(rule)
            ctx.setLineJoin(.round)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: o.x + sign * 0.06, y: bottom + height * 0.44))
            ctx.addLine(to: CGPoint(x: o.x + sign * 0.24, y: bottom + height * 0.52))
            ctx.addLine(to: CGPoint(x: o.x + sign * 0.52, y: bottom + rule / 2))
            ctx.addLine(to: CGPoint(x: o.x + sign, y: top))
            ctx.addLine(to: CGPoint(x: o.x + width - size * 0.02, y: top))
            ctx.strokePath()
            ctx.restoreGState()
            x.draw(ctx, CGPoint(x: o.x + sign + inset, y: o.y))
        }
    }

    // A large ∑ centred on the maths axis, its limits small and centred above and below it.
    static func bigOperator(_ symbol: String, _ lower: Box, _ upper: Box, _ size: CGFloat) -> Box {
        let big = size * 1.7, sign = text(symbol, big)
        let capTop = big * 0.74                        // the sign is about as tall as a capital,
        let drop = size * 0.28 - capTop / 2            // centred on the maths axis
        let gap = size * 0.1, after = size * 0.14
        let column = max(sign.width, lower.width, upper.width)
        let top = drop + capTop, bottom = drop - big * 0.14   // its foot dips below its baseline
        return Box(width: column + after,
                   ascent: top + gap + upper.descent + upper.ascent,
                   descent: -bottom + gap + lower.ascent + lower.descent) { ctx, o in
            sign.draw(ctx, CGPoint(x: o.x + (column - sign.width) / 2, y: o.y + drop))
            upper.draw(ctx, CGPoint(x: o.x + (column - upper.width) / 2, y: o.y + top + gap + upper.descent))
            lower.draw(ctx, CGPoint(x: o.x + (column - lower.width) / 2, y: o.y + bottom - gap - lower.ascent))
        }
    }

    static func power(_ base: Box, _ exponent: Box, _ size: CGFloat) -> Box {
        let shift = size * 0.34, gap = size * 0.03
        return Box(width: base.width + gap + exponent.width,
                   ascent: max(base.ascent, shift + exponent.ascent),
                   descent: max(base.descent, exponent.descent - shift)) { ctx, o in
            base.draw(ctx, o)
            exponent.draw(ctx, CGPoint(x: o.x + base.width + gap, y: o.y + shift))
        }
    }
}

// What a line of the panel copies: a click gives LaTeX or the line as shown, as chosen on the
// Clipboard page, and its menu either. A line with no LaTeX (a digest over several lines) copies its text.
struct MathCopy {
    var latex: String?
    var text: String
    var copied: () -> Void
}

final class MathNSView: NSView {
    private var box: Box
    private let margin: CGFloat = 2
    private var hovering = false { didSet { if hovering != oldValue { needsDisplay = true } } }

    // Set for a line in the panel. The panel is never key, so the click is taken here in AppKit.
    var copying: MathCopy? {
        didSet { if (copying == nil) != (oldValue == nil) { updateTrackingAreas(); needsDisplay = true } }
    }

    init(_ math: Math, size: CGFloat) {
        box = Typesetter.box(math, size)
        super.init(frame: .zero)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { copying != nil }

    override func mouseDown(with event: NSEvent) {
        if copying == nil { super.mouseDown(with: event) }
    }

    override func mouseUp(with event: NSEvent) {
        guard copying != nil else { return super.mouseUp(with: event) }
        if bounds.contains(convert(event.locationInWindow, from: nil)) { put(asLatex: Prefs.copyLatex) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let copying else { return super.menu(for: event) }
        let menu = NSMenu()
        if copying.latex != nil { menu.addItem(withTitle: "Copy LaTeX", action: #selector(copyLatex), keyEquivalent: "").target = self }
        menu.addItem(withTitle: copying.latex == nil ? "Copy" : "Copy as Text", action: #selector(copyText), keyEquivalent: "").target = self
        return menu
    }

    @objc private func copyLatex() { put(asLatex: true) }
    @objc private func copyText() { put(asLatex: false) }

    private func put(asLatex: Bool) {
        guard let copying else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString((asLatex ? copying.latex : nil) ?? copying.text, forType: .string)
        copying.copied()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        if copying != nil {
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        } else {
            hovering = false
        }
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        NSCursor.pointingHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        NSCursor.arrow.set()
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(_ math: Math, size: CGFloat) {
        box = Typesetter.box(math, size)
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil(box.width + 2 * margin), height: ceil(box.ascent + box.descent + 2 * margin))
    }

    // A line too long for the space it is given is drawn smaller rather than spilling out of it.
    var scale: CGFloat { min(1, bounds.width / max(intrinsicContentSize.width, 1)) }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // A line that copies shows it can be clicked, faintly, while the pointer is on it.
        if hovering, copying != nil {
            NSColor.labelColor.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
        }
        ctx.scaleBy(x: scale, y: scale)
        ctx.textMatrix = .identity
        NSColor.labelColor.setFill()     // resolved for this view's appearance while drawing
        NSColor.labelColor.setStroke()
        box.draw(ctx, CGPoint(x: margin, y: margin + box.descent))
    }

    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}

struct MathText: NSViewRepresentable {
    let math: Math
    var size: CGFloat = 19
    var copying: MathCopy? = nil

    func makeNSView(context: Context) -> MathNSView {
        let view = MathNSView(math, size: size)
        view.copying = copying
        return view
    }

    func updateNSView(_ view: MathNSView, context: Context) {
        view.update(math, size: size)
        view.copying = copying
    }

    // Its natural size, or narrower and in proportion when that is all the room there is.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MathNSView, context: Context) -> CGSize? {
        let natural = nsView.intrinsicContentSize
        let width = min(natural.width, proposal.width ?? natural.width)
        return CGSize(width: width, height: natural.height * width / max(natural.width, 1))
    }
}
