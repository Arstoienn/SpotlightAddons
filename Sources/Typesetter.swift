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
    // A row of rows as one row: the pieces a line can be broken between.
    // In one pass, rows within rows as deep as they go: a sum of hundreds of terms is a row hundreds
    // deep, and flattening each level into a new array would copy it as many times over.
    static func flattened(_ m: Math) -> [Math] {
        var pieces: [Math] = []
        func walk(_ m: Math) { if case .row(let parts) = m { parts.forEach(walk) } else { pieces.append(m) } }
        walk(m)
        return pieces
    }

    static func box(_ m: Math, _ size: CGFloat) -> Box {
        switch m {
        case .text(let s): return text(s, size)
        case .row(let parts): return row(parts.map { box($0, size) })
        case .fraction(let n, let d): return fraction(box(n, size * 0.88), box(d, size * 0.88), size)
        case .root(let x): return root(box(x, size), size)
        case .radical(let x, let index): return radical(box(x, size), box(index, size * 0.5), size)
        case .group(let x): return group(box(x, size), size)
        case .power(let b, let e): return power(box(b, size), box(e, size * 0.64), size)
        case .bigOperator(let symbol, let lower, let upper):
            return bigOperator(symbol, box(lower, size * 0.62), box(upper, size * 0.62), size)
        case .matrix(let rows): return matrix(rows.map { $0.map { box($0, size) } }, size)
        }
    }

    // A matrix: its entries centred in their columns, the whole centred on the maths axis, between
    // square brackets as tall as it is.
    static func matrix(_ cells: [[Box]], _ size: CGFloat) -> Box {
        let columns = cells.map(\.count).max() ?? 0
        let widths = (0..<columns).map { c in cells.compactMap { $0.indices.contains(c) ? $0[c].width : nil }.max() ?? 0 }
        let heights = cells.map { ($0.map(\.ascent).max() ?? 0, $0.map(\.descent).max() ?? 0) }
        let axis = size * 0.28, lead = size * 0.3, gap = size * 0.9, bracket = size * 0.45
        let total = heights.reduce(0) { $0 + $1.0 + $1.1 } + lead * CGFloat(max(0, cells.count - 1))
        let width = widths.reduce(0, +) + gap * CGFloat(max(0, columns - 1)) + 2 * bracket + size * 0.2
        let columnLeft = (0..<columns).map { c in size * 0.1 + bracket + widths[..<c].reduce(0, +) + gap * CGFloat(c) }
        return Box(width: width, ascent: total / 2 + axis, descent: total / 2 - axis) { ctx, o in
            var top = o.y + total / 2 + axis
            for (r, row) in cells.enumerated() {
                let baseline = top - heights[r].0
                for (c, b) in row.enumerated() { b.draw(ctx, CGPoint(x: o.x + columnLeft[c] + (widths[c] - b.width) / 2, y: baseline)) }
                top = baseline - heights[r].1 - lead
            }
            // Square brackets: an upright, with a short foot top and bottom.
            ctx.saveGState()
            ctx.setLineWidth(max(1, size * 0.055))
            let upper = o.y + total / 2 + axis + size * 0.05, lower = o.y - (total / 2 - axis) - size * 0.05, foot = size * 0.22
            for (edge, inward) in [(o.x + size * 0.15, 1.0), (o.x + width - size * 0.15, -1.0)] {
                ctx.move(to: CGPoint(x: edge + inward * foot, y: upper))
                ctx.addLine(to: CGPoint(x: edge, y: upper))
                ctx.addLine(to: CGPoint(x: edge, y: lower))
                ctx.addLine(to: CGPoint(x: edge + inward * foot, y: lower))
            }
            ctx.strokePath()
            ctx.restoreGState()
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

    static func plain(_ s: String, _ size: CGFloat, font: NSFont? = nil) -> Box {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: size),
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

    // A root with its index small in the crook of the sign, ∛x: the root as above, moved right where
    // the index is wider than the crook, and the index set over the sign's tick.
    static func radical(_ x: Box, _ index: Box, _ size: CGFloat) -> Box {
        let r = root(x, size), crook = size * 0.26
        let shift = max(0, index.width - crook)
        let lift = (r.ascent - r.descent) * 0.5 + index.descent
        return Box(width: shift + r.width, ascent: max(r.ascent, lift + index.ascent), descent: r.descent) { ctx, o in
            index.draw(ctx, CGPoint(x: o.x + max(0, crook - index.width) * 0.5, y: o.y + lift))
            r.draw(ctx, CGPoint(x: o.x + shift, y: o.y))
        }
    }

    // A large ∑ centred on the maths axis, its limits small and centred above and below it.
    static func bigOperator(_ symbol: String, _ lower: Box, _ upper: Box, _ size: CGFloat) -> Box {
        // The sign from a mathematics font, ∑ and ∏ as they are printed: SF's own is a letter's, thin and small.
        // ∫ is a slender sign, set larger than ∑ so that it stands as tall beside what it integrates.
        let big = size * (symbol == "∫" ? 2.1 : 1.5), font = NSFont(name: "STIXTwoMath-Regular", size: big) ?? NSFont.systemFont(ofSize: big)
        let sign = plain(symbol, big, font: font)
        // The sign's own outline, measured, centred on the maths axis; the limits clear of it.
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: symbol, attributes: [.font: font]))
        let ink = CTLineGetImageBounds(line, nil)
        let drop = size * 0.28 - ink.midY
        let gap = size * 0.14, after = size * 0.14
        let column = max(sign.width, lower.width, upper.width)
        let top = drop + ink.maxY, bottom = drop + ink.minY
        return Box(width: column + after,
                   ascent: top + gap + upper.descent + upper.ascent,
                   descent: -bottom + gap + lower.ascent + lower.descent) { ctx, o in
            sign.draw(ctx, CGPoint(x: o.x + (column - sign.width) / 2, y: o.y + drop))
            upper.draw(ctx, CGPoint(x: o.x + (column - upper.width) / 2, y: o.y + top + gap + upper.descent))
            lower.draw(ctx, CGPoint(x: o.x + (column - lower.width) / 2, y: o.y + bottom - gap - lower.ascent))
        }
    }

    // Round brackets: the font's own round a line of text, drawn curves as tall as what they hold
    // round a fraction or a sum.
    static func group(_ x: Box, _ size: CGFloat) -> Box {
        guard x.ascent + x.descent > size * 1.1 else { return row([plain("(", size), x, plain(")", size)]) }
        let rule = max(1, size * 0.055), reach = size * 0.2, side = size * 0.1
        let ascent = x.ascent + size * 0.06, descent = x.descent + size * 0.06
        let width = x.width + 2 * (reach + side)
        return Box(width: width, ascent: ascent, descent: descent) { ctx, o in
            let top = o.y + ascent, bottom = o.y - descent, height = top - bottom
            ctx.saveGState()
            ctx.setLineWidth(rule)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: o.x + side + reach, y: top))
            ctx.addCurve(to: CGPoint(x: o.x + side + reach, y: bottom),
                         control1: CGPoint(x: o.x + side - reach * 0.3, y: top - height * 0.22),
                         control2: CGPoint(x: o.x + side - reach * 0.3, y: bottom + height * 0.22))
            let right = o.x + width - side - reach
            ctx.move(to: CGPoint(x: right, y: top))
            ctx.addCurve(to: CGPoint(x: right, y: bottom),
                         control1: CGPoint(x: right + reach * 1.3, y: top - height * 0.22),
                         control2: CGPoint(x: right + reach * 1.3, y: bottom + height * 0.22))
            ctx.strokePath()
            ctx.restoreGState()
            x.draw(ctx, CGPoint(x: o.x + side + reach + (width - 2 * (side + reach) - x.width) / 2, y: o.y))
        }
    }

    static func power(_ base: Box, _ exponent: Box, _ size: CGFloat) -> Box {
        // Over a base taller than a line, a matrix or a bracket round a fraction, the power goes up
        // to its top corner, as A⁻¹ is printed; over a letter, the usual height.
        let tall = base.ascent > size * 0.95
        let shift = tall ? base.ascent - exponent.ascent * 0.55 : size * 0.34, gap = size * 0.03
        return Box(width: base.width + gap + exponent.width,
                   ascent: max(base.ascent, shift + exponent.ascent),
                   descent: max(base.descent, exponent.descent - shift)) { ctx, o in
            base.draw(ctx, o)
            exponent.draw(ctx, CGPoint(x: o.x + base.width + gap, y: o.y + shift))
        }
    }
}

final class MathNSView: NSView {
    private var math: Math
    private var size: CGFloat
    private var box: Box
    private let margin: CGFloat = 2
    var color: NSColor = .labelColor
    var wraps = true

    init(_ math: Math, size: CGFloat, color: NSColor = .labelColor) {
        self.math = math
        self.size = size
        box = Typesetter.box(math, size)
        self.color = color
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    // SwiftUI updates the view far more often than what it shows changes: it is measured again only
    // when that does.
    func update(_ math: Math, size: CGFloat) {
        guard math != self.math || size != self.size else { return }
        self.math = math
        self.size = size
        box = Typesetter.box(math, size)
        pieces = nil
        cached = nil
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil(box.width + 2 * margin), height: ceil(box.ascent + box.descent + 2 * margin))
    }

    // The places a long sum may be broken, before each + or −, and each piece between them set once;
    // nil where there is no such place. Kept until what is shown changes, for SwiftUI asks for the
    // lines at one width after another while it lays the panel out, and each asking is then only
    // a matter of adding widths.
    private var pieces: [Box]??

    private var segments: [Box]? {
        if let pieces { return pieces }
        var groups: [[Math]] = []
        for piece in Typesetter.flattened(math) {
            if case .text(let s) = piece, [" + ", " − "].contains(s), !(groups.last?.isEmpty ?? true) { groups.append([piece]) }
            else if groups.isEmpty { groups.append([piece]) }
            else { groups[groups.count - 1].append(piece) }
        }
        let found = groups.count > 1 ? groups.map { Typesetter.box(.row($0), size) } : nil
        pieces = .some(found)
        return found
    }

    // A line too long for the space it is given is broken where it is a sum, before a + or a −,
    // each line after the first set in a little, as working is written out by hand; one that will
    // not break, or is not to, is drawn smaller rather than spilling out of it.
    func lines(for width: CGFloat) -> [Box]? {
        guard wraps, box.width + 2 * margin > width, let segments else { return nil }
        if let cached, cached.width == width { return cached.lines }
        let indent = size, room = width - 2 * margin
        var lines: [Box] = [], current: [Box] = [], used: CGFloat = 0
        for segment in segments {
            if !current.isEmpty, used + segment.width + (lines.isEmpty ? 0 : indent) > room {
                lines.append(Typesetter.row(current)); current = [segment]; used = segment.width
            } else {
                current.append(segment); used += segment.width
            }
        }
        if !current.isEmpty { lines.append(Typesetter.row(current)) }
        cached = (width, lines)
        return lines
    }

    private var cached: (width: CGFloat, lines: [Box])?

    private var gap: CGFloat { size * 0.3 }

    func height(for width: CGFloat) -> CGFloat? {
        guard let lines = lines(for: width) else { return nil }
        return ceil(lines.reduce(0) { $0 + $1.ascent + $1.descent } + gap * CGFloat(lines.count - 1) + 2 * margin)
    }

    var scale: CGFloat { min(1, bounds.width / max(intrinsicContentSize.width, 1)) }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.textMatrix = .identity
        color.setFill()     // resolved for this view's appearance while drawing
        color.setStroke()
        if let lines = lines(for: bounds.width) {
            // From the top down, in a view whose y goes up.
            var top = bounds.height - margin
            for (i, line) in lines.enumerated() {
                let x = margin + (i == 0 ? 0 : size)
                let fit = min(1, (bounds.width - x - margin) / max(line.width, 1))
                top -= line.ascent * fit
                ctx.saveGState()
                ctx.translateBy(x: x, y: top)
                ctx.scaleBy(x: fit, y: fit)
                line.draw(ctx, .zero)
                ctx.restoreGState()
                top -= line.descent * fit + gap
            }
            return
        }
        ctx.scaleBy(x: scale, y: scale)
        box.draw(ctx, CGPoint(x: margin, y: margin + box.descent))
    }

    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}

struct MathText: NSViewRepresentable {
    let math: Math
    var size: CGFloat = 19
    var color: NSColor = .labelColor
    var wraps = true   // on the card, one line, made smaller, and no more

    func makeNSView(context: Context) -> MathNSView {
        let view = MathNSView(math, size: size, color: color)
        view.wraps = wraps
        return view
    }
    func updateNSView(_ view: MathNSView, context: Context) { view.color = color; view.wraps = wraps; view.update(math, size: size) }

    // Its natural size; broken over several lines where it is a long sum and there is not the room
    // across; or else narrower and in proportion.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MathNSView, context: Context) -> CGSize? {
        let natural = nsView.intrinsicContentSize
        let width = min(natural.width, proposal.width ?? natural.width)
        if let height = nsView.height(for: width) { return CGSize(width: width, height: height) }
        return CGSize(width: width, height: natural.height * width / max(natural.width, 1))
    }
}
