import SwiftUI

extension RGBA {
    // The colour as the screen can best show it: in sRGB where it lies there, else in Display P3,
    // which a Mac's screen shows, clipped only where it lies beyond that too.
    var shown: Color {
        if inSRGB { let c = clamped; return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: a) }
        let (p, q, s) = Gamut.p3.channels(self)
        return Color(.displayP3, red: min(1, max(0, p)), green: min(1, max(0, q)), blue: min(1, max(0, s)), opacity: a)
    }
}

// The CIE 1931 chromaticity diagram, as the working of a colour shows it: the horseshoe of every colour
// the eye sees, filled with them, its curved edge the colours of the spectrum marked in nanometres; the
// triangle of a screen's gamut, sRGB, Display P3 or Rec. 2020, with the white point D65; and the colours
// of the answer where they truly lie, beyond the triangle or not, with dashed lines from the colours that
// make another to what they make, or the path a mixture goes along.
//
// The colours typed can be dragged about it, each keeping its luminance Y, and what they make moves with
// them; dragged past the edge of the horseshoe, a colour slides along the edge, where the pointer goes
// on beyond it. The result of a mixture can be dragged along its path, or moved there with the slider.
// A click on a colour gives its x, y and Y exactly. As the graph does, it zooms with a pinch about the
// pointer, and with + and −, while scrolling scrolls the panel; dragging elsewhere moves about; a
// double-click goes back. The card above is as it was typed.
struct ChromaticityDiagram: View {
    let diagram: Chromaticity

    @State private var inputs: [RGBA]?
    @State private var share: Double?
    @State private var selected: Int?
    @State private var dragging: Int?
    @State private var view: (x: ClosedRange<Double>, y: ClosedRange<Double>)?    // nil: the whole diagram
    @State private var panStart: (x: ClosedRange<Double>, y: ClosedRange<Double>)?

    // The spectral locus of the CIE 1931 2° observer: (wavelength in nm, x, y).
    static let locus: [(Int, Double, Double)] = [
        (380, 0.1741, 0.0050), (400, 0.1733, 0.0048), (420, 0.1714, 0.0051), (430, 0.1689, 0.0069), (440, 0.1644, 0.0109),
        (450, 0.1566, 0.0177), (460, 0.1440, 0.0297), (465, 0.1355, 0.0399), (470, 0.1241, 0.0578), (475, 0.1096, 0.0868),
        (480, 0.0913, 0.1327), (485, 0.0687, 0.2007), (490, 0.0454, 0.2950), (495, 0.0235, 0.4127), (500, 0.0082, 0.5384),
        (505, 0.0039, 0.6548), (510, 0.0139, 0.7502), (515, 0.0389, 0.8120), (520, 0.0743, 0.8338), (525, 0.1142, 0.8262),
        (530, 0.1547, 0.8059), (535, 0.1929, 0.7816), (540, 0.2296, 0.7543), (545, 0.2658, 0.7243), (550, 0.3016, 0.6923),
        (555, 0.3373, 0.6589), (560, 0.3731, 0.6245), (565, 0.4087, 0.5896), (570, 0.4441, 0.5547), (575, 0.4788, 0.5202),
        (580, 0.5125, 0.4866), (585, 0.5448, 0.4544), (590, 0.5752, 0.4242), (595, 0.6029, 0.3965), (600, 0.6270, 0.3725),
        (605, 0.6482, 0.3514), (610, 0.6658, 0.3340), (620, 0.6915, 0.3083), (630, 0.7079, 0.2920), (640, 0.7190, 0.2809),
        (650, 0.7260, 0.2740), (660, 0.7300, 0.2700), (680, 0.7334, 0.2666), (700, 0.7347, 0.2653),
    ]
    static let labelled: Set<Int> = [460, 480, 520, 540, 560, 580, 600, 620]
    static let white = (0.3127, 0.3290)   // D65
    static let span = (x: 0.8, y: 0.9)

    // Whether x and y lie among the colours the eye sees: inside the horseshoe.
    static func visible(_ x: Double, _ y: Double) -> Bool {
        var c = false, j = locus.count - 1
        for i in locus.indices {
            let (xi, yi) = (locus[i].1, locus[i].2), (xj, yj) = (locus[j].1, locus[j].2)
            if (yi > y) != (yj > y), x < (xj - xi) * (y - yi) / (yj - yi) + xi { c.toggle() }
            j = i
        }
        return c
    }

    // The nearest point to x, y among the colours the eye sees: itself where it is inside the
    // horseshoe, else the nearest point of its edge, a hair inside, so that a colour dragged out of it
    // slides along the edge.
    static func nearestVisible(_ x: Double, _ y: Double) -> (Double, Double) {
        if visible(x, y) { return (x, y) }
        var best = (x, y), distance = Double.infinity
        for i in locus.indices {
            let a = (locus[i].1, locus[i].2), b = (locus[(i + 1) % locus.count].1, locus[(i + 1) % locus.count].2)
            let (dx, dy) = (b.0 - a.0, b.1 - a.1)
            let t = max(0, min(1, ((x - a.0) * dx + (y - a.1) * dy) / max(dx * dx + dy * dy, 1e-12)))
            let p = (a.0 + t * dx, a.1 + t * dy)
            let d = (p.0 - x) * (p.0 - x) + (p.1 - y) * (p.1 - y)
            if d < distance { (best, distance) = (p, d) }
        }
        // A little towards the white point, to be inside the edge and not on it.
        for k in 1...20 {
            let f = 0.002 * Double(k)
            let q = (best.0 + (white.0 - best.0) * f, best.1 + (white.1 - best.1) * f)
            if visible(q.0, q.1) { return q }
        }
        return white
    }

    // The horseshoe's colours for the part of the diagram in view, at each point the colour of that x
    // and y at the brightest that can be shown; drawn again only when the view has moved.
    private final class Fill {
        static var key: [Double] = []
        static var image: CGImage?
        // At twice the points of the plot, as a Retina screen shows it.
        static func image(_ xs: ClosedRange<Double>, _ ys: ClosedRange<Double>, _ size: CGSize) -> CGImage? {
            let (w, h) = (min(1800, Int(size.width * 2)), min(1200, Int(size.height * 2)))
            let wanted = [xs.lowerBound, xs.upperBound, ys.lowerBound, ys.upperBound, Double(w), Double(h)]
            if wanted == key, let image { return image }
            key = wanted
            image = w > 0 && h > 0 ? make(xs, ys, w, h) : nil
            return image
        }
        // Every pixel coloured, inside the horseshoe or not: its smooth outline, drawn as a curve, is what
        // clips it, so that its edge is never a staircase of pixels.
        private static func make(_ xs: ClosedRange<Double>, _ ys: ClosedRange<Double>, _ w: Int, _ h: Int) -> CGImage? {
            var pixels = [UInt8](repeating: 0, count: w * h * 4)
            func encode(_ c: Double) -> Double { c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055 }
            let (xw, yh) = (xs.upperBound - xs.lowerBound, ys.upperBound - ys.lowerBound)
            // The rows at once, each core taking some: drawn again at every step of a pinch, the fill
            // must take a few milliseconds, not the tens it takes on one core.
            pixels.withUnsafeMutableBufferPointer { pixels in
            DispatchQueue.concurrentPerform(iterations: h) { row in
                let y = ys.upperBound - (Double(row) + 0.5) / Double(h) * yh
                guard y > 0.001 else { return }
                for col in 0..<w {
                    let x = xs.lowerBound + (Double(col) + 0.5) / Double(w) * xw
                    guard x >= -0.05, x + y <= 1.05 else { continue }
                    var (r, g, b) = Gamut.srgb.fromXYZ((x / y, 1, (1 - x - y) / y))
                    let low = min(r, g, b)
                    if low < 0 { r -= low; g -= low; b -= low }
                    let high = max(r, g, b, 1e-9)
                    let i = (row * w + col) * 4
                    pixels[i] = UInt8(encode(r / high) * 255); pixels[i + 1] = UInt8(encode(g / high) * 255)
                    pixels[i + 2] = UInt8(encode(b / high) * 255); pixels[i + 3] = 255
                }
            }
            }
            guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
            return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil,
                           shouldInterpolate: true, intent: .defaultIntent)
        }
    }

    // Where the plot is in the view, the part of the diagram in view, and the way between x, y and
    // points on it. The plot is the whole of its box, edge to edge; a unit across is as long as a unit up,
    // so what is in view across is as wide as the box allows, about the middle of the view kept.
    struct Layout {
        let plot: CGRect
        let xs: ClosedRange<Double>, ys: ClosedRange<Double>
        init(_ size: CGSize, _ xs: ClosedRange<Double>, _ ys: ClosedRange<Double>) {
            plot = CGRect(origin: .zero, size: size)
            let perPoint = (ys.upperBound - ys.lowerBound) / Double(max(size.height, 1))
            let middle = (xs.lowerBound + xs.upperBound) / 2, half = perPoint * Double(size.width) / 2
            (self.xs, self.ys) = ((middle - half)...(middle + half), ys)
        }
        var perPoint: Double { (ys.upperBound - ys.lowerBound) / Double(max(plot.height, 1)) }
        func at(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: plot.minX + CGFloat((x - xs.lowerBound) / (xs.upperBound - xs.lowerBound)) * plot.width,
                    y: plot.maxY - CGFloat((y - ys.lowerBound) / (ys.upperBound - ys.lowerBound)) * plot.height)
        }
        func xy(_ p: CGPoint) -> (Double, Double) {
            (xs.lowerBound + Double((p.x - plot.minX) / plot.width) * (xs.upperBound - xs.lowerBound),
             ys.lowerBound + Double((plot.maxY - p.y) / plot.height) * (ys.upperBound - ys.lowerBound))
        }
        // Grid lines a round step apart, about eight across.
        var step: Double {
            let raw = (xs.upperBound - xs.lowerBound) / 8
            let power = pow(10, floor(log10(raw)))
            return [1, 2, 5, 10].map { $0 * power }.first { $0 >= raw } ?? raw
        }
    }

    // The whole horseshoe, with a little room about it; across, as much as the box is wide.
    private var whole: (x: ClosedRange<Double>, y: ClosedRange<Double>) { (0...0.75, -0.04...0.9) }
    private var shownView: (x: ClosedRange<Double>, y: ClosedRange<Double>) { view ?? whole }

    private var currentInputs: [RGBA] { inputs ?? diagram.inputs }
    private var currentShare: Double { share ?? diagram.share ?? 0.5 }
    private var scene: Chromaticity.Scene { diagram.make(currentInputs, currentShare) }
    private var changed: Bool { inputs != nil || share != nil }
    // How each gamut's triangle is drawn: sRGB solid, Display P3 dashed, Rec. 2020 dotted.
    private static func style(_ g: Gamut) -> StrokeStyle {
        switch g {
        case .srgb: StrokeStyle(lineWidth: 1.1)
        case .p3: StrokeStyle(lineWidth: 1, dash: [5, 3])
        case .rec2020: StrokeStyle(lineWidth: 1.1, lineCap: .round, dash: [0.1, 3.2])
        }
    }

    // A change made gently over a third of a second, the diagram drawn at each step: what is drawn on a
    // canvas does not animate by itself.
    private func glide(_ step: @escaping (Double) -> Void, done: @escaping () -> Void) {
        let start = Date(), duration = 0.35
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { timer in
            MainActor.assumeIsolated {
                let t = min(1, Date().timeIntervalSince(start) / duration)
                step(1 - pow(1 - t, 3))
                if t >= 1 { timer.invalidate(); done() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    // Back to the colours as typed: each glides back along the straight line in x and y, its Y with it.
    private func backToTyped() {
        let from = currentInputs, fromShare = currentShare, to = diagram.inputs, toShare = diagram.share ?? fromShare
        glide({ e in
            inputs = zip(from, to).map { a, b in
                let (p, q) = (a.xyY, b.xyY)
                return RGBA(x: p.0 + (q.0 - p.0) * e, y: p.1 + (q.1 - p.1) * e, Y: p.2 + (q.2 - p.2) * e, a: a.a + (b.a - a.a) * e)
            }
            share = fromShare + (toShare - fromShare) * e
        }, done: { inputs = nil; share = nil })
    }

    // Back to the whole diagram, gliding there.
    private func backToWhole() {
        let (fx, fy) = shownView, (tx, ty) = whole
        func lerp(_ a: ClosedRange<Double>, _ b: ClosedRange<Double>, _ e: Double) -> ClosedRange<Double> {
            (a.lowerBound + (b.lowerBound - a.lowerBound) * e)...(a.upperBound + (b.upperBound - a.upperBound) * e)
        }
        glide({ e in view = (lerp(fx, tx, e), lerp(fy, ty, e)) }, done: { view = nil })
    }
    // The colour whose values are given below: the one clicked, else the result.
    private var focus: Int? {
        let marks = scene.marks
        if let selected, selected < marks.count { return selected }
        return marks.lastIndex { $0.result } ?? (marks.isEmpty ? nil : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geometry in
                let (xs, ys) = shownView
                let layout = Layout(geometry.size, xs, ys), scene = scene
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in draw(&context, layout, scene) }
                        .allowsHitTesting(false)
                    DiagramInput(press: { press($0, layout, scene) },
                                 drag: { location, translation in drag(location, translation, layout, scene) },
                                 release: { dragging = nil; panStart = nil },
                                 zoom: { factor, point in zoom(factor, about: layout.xy(point)) },
                                 reset: { backToWhole() })
                    ZoomControls(zoomIn: { zoom(0.6, about: centre) }, zoomOut: { zoom(1 / 0.6, about: centre) }, reset: { backToWhole() })
                        .position(ZoomControls.place(in: layout.plot))
                }
            }
            .frame(height: 400)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if diagram.share != nil {
                    Text("A").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { currentShare }, set: { share = $0 }), in: 0...1)
                        .controlSize(.small)
                    Text("B").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if changed {
                    Button("As typed") { backToTyped() }
                        .controlSize(.small)
                }
            }
            .frame(minHeight: diagram.share != nil || changed ? 22 : 0)
            if let focus { readout(scene.marks[focus]) }
            ZoomControls.Hint(before: hints)
            }
            .padding(14)
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quaternary.opacity(0.5)))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("The CIE 1931 chromaticity diagram")
    }

    private var centre: (Double, Double) {
        let (xs, ys) = shownView
        return ((xs.lowerBound + xs.upperBound) / 2, (ys.lowerBound + ys.upperBound) / 2)
    }


    // About the point given, which stays where it is; from the whole diagram in to a span of 0.005.
    private func zoom(_ factor: Double, about point: (Double, Double)) {
        let (xs, ys) = shownView
        let height = ys.upperBound - ys.lowerBound
        let f = min(max(factor, 0.005 / height), 1.6 / height)
        func scaled(_ r: ClosedRange<Double>, _ c: Double) -> ClosedRange<Double> { (c + (r.lowerBound - c) * f)...(c + (r.upperBound - c) * f) }
        view = (scaled(xs, point.0), scaled(ys, point.1))
    }

    // What else the diagram can do, said before how to move about it, in the same short form.
    private var hints: [String] {
        var parts: [String] = []
        if scene.marks.contains(where: { $0.input != nil }) { parts.append("Drag a colour typed to move it") }
        if scene.onPath != nil { parts.append("Drag the result along its path") }
        parts.append("Click a colour for its xyY")
        return parts
    }

    // The colour's name here, its hex, x, y and Y, the share where it is a mixture, and the gamuts it lies in.
    private func readout(_ mark: Chromaticity.Mark) -> some View {
        let (x, y, Y) = mark.colour.xyY
        let place = Colour.beyond(mark.colour) ?? "within sRGB, and so every gamut drawn"
        return HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(mark.colour.shown)
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5))
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(Self.caption(mark)).font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Text(mark.result && diagram.share != nil ? "\(Colour.number(currentShare * 100))% A · \(place)" : place)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text(String(format: "x = %.4f    y = %.4f    Y = %.4f", x, y, Y))
                    .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // "A  #FF0000", or the hex alone where that is its name.
    static func caption(_ mark: Chromaticity.Mark) -> String {
        let hex = Colour.written(mark.colour, .hex)
        return mark.label.isEmpty || mark.label == hex ? hex : "\(mark.label)  \(hex)"
    }

    // A press on a colour picks it, to be dragged; a press elsewhere is to move about the diagram.
    private func press(_ point: CGPoint, _ layout: Layout, _ scene: Chromaticity.Scene) {
        let near = scene.marks.indices.map { i -> (Int, CGFloat) in
            let p = layout.at(scene.marks[i].colour.xy.0, scene.marks[i].colour.xy.1)
            return (i, hypot(p.x - point.x, p.y - point.y))
        }.filter { $0.1 < 14 }.min { $0.1 < $1.1 }
        if let (i, _) = near {
            dragging = i
            selected = i
        } else {
            dragging = nil
            panStart = shownView
        }
    }

    // A colour typed goes where the pointer is, keeping its Y, and along the horseshoe's edge where the
    // pointer is beyond it; the result of a mixture to the nearest point of its path; anywhere else,
    // the diagram moves with the pointer.
    private func drag(_ location: CGPoint, _ translation: CGSize, _ layout: Layout, _ scene: Chromaticity.Scene) {
        if let start = panStart {
            let perPoint = (start.y.upperBound - start.y.lowerBound) / Double(max(layout.plot.height, 1))
            let dx = Double(translation.width) * perPoint, dy = Double(translation.height) * perPoint
            view = ((start.x.lowerBound - dx)...(start.x.upperBound - dx), (start.y.lowerBound + dy)...(start.y.upperBound + dy))
            return
        }
        guard let i = dragging, i < scene.marks.count else { return }
        let mark = scene.marks[i]
        if let input = mark.input {
            let (x, y) = ChromaticityDiagram.nearestVisible(layout.xy(location).0, layout.xy(location).1)
            var all = currentInputs
            let Y = max(all[input].xyY.2, 0.02)
            all[input] = RGBA(x: x, y: y, Y: Y, a: all[input].a)
            inputs = all
        } else if i == scene.onPath, !scene.path.isEmpty {
            // The nearest of the path's colours to the pointer, as a share of A.
            let points = scene.path.map { layout.at($0.xy.0, $0.xy.1) }
            let k = points.indices.min { hypot(points[$0].x - location.x, points[$0].y - location.y) < hypot(points[$1].x - location.x, points[$1].y - location.y) }!
            share = 1 - Double(k) / Double(points.count - 1)
        }
    }

    private func draw(_ context: inout GraphicsContext, _ layout: Layout, _ scene: Chromaticity.Scene) {
        let plot = layout.plot
        func at(_ x: Double, _ y: Double) -> CGPoint { layout.at(x, y) }
        let faint = Color.secondary.opacity(0.35)
        let step = layout.step, places = max(0, Int(-floor(log10(step)) + (step / pow(10, floor(log10(step))) == 1 ? 0 : 0)))

        // The grid: a line every step. Its numbers go inside the edges, over everything, at the end.
        var xTicks: [Double] = [], yTicks: [Double] = []
        var k = (layout.xs.lowerBound / step).rounded(.up)
        while k * step <= layout.xs.upperBound + 1e-12 {
            let v = k * step
            var tick = Path(); tick.move(to: at(v, layout.ys.lowerBound)); tick.addLine(to: at(v, layout.ys.upperBound))
            context.stroke(tick, with: .color(faint.opacity(0.4)), lineWidth: 0.5)
            xTicks.append(v)
            k += 1
        }
        k = (layout.ys.lowerBound / step).rounded(.up)
        while k * step <= layout.ys.upperBound + 1e-12 {
            let v = k * step
            var tick = Path(); tick.move(to: at(layout.xs.lowerBound, v)); tick.addLine(to: at(layout.xs.upperBound, v))
            context.stroke(tick, with: .color(faint.opacity(0.4)), lineWidth: 0.5)
            yTicks.append(v)
            k += 1
        }

        let above = context   // for the key, drawn last, over everything and not clipped
        // Everything else within the plot only, however far it is zoomed.
        context.clip(to: Path(plot))

        // The horseshoe, its colours and its edge: a smooth curve through the spectrum's points (Catmull–Rom),
        // closed by the straight line of purples.
        let edge = Self.locus.map { at($0.1, $0.2) }
        var shoe = Path()
        shoe.move(to: edge[0])
        for i in 0..<(edge.count - 1) {
            let p0 = edge[max(i - 1, 0)], p1 = edge[i], p2 = edge[i + 1], p3 = edge[min(i + 2, edge.count - 1)]
            shoe.addCurve(to: p2, control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        shoe.closeSubpath()
        if let fill = Fill.image(layout.xs, layout.ys, plot.size) {
            context.drawLayer { layer in
                layer.clip(to: shoe)
                layer.opacity = 0.85
                layer.draw(Image(decorative: fill, scale: 1), in: plot)
            }
        }
        context.stroke(shoe, with: .color(.primary.opacity(0.5)), lineWidth: 0.8)
        let centre = at(Self.white.0, Self.white.1)
        for point in Self.locus where Self.labelled.contains(point.0) {
            let p = at(point.1, point.2)
            let away = CGVector(dx: p.x - centre.x, dy: p.y - centre.y), length = max(hypot(away.dx, away.dy), 1)
            context.draw(Text("\(point.0)").font(.system(size: 8)).foregroundStyle(.secondary),
                         at: CGPoint(x: p.x + away.dx / length * 13, y: p.y + away.dy / length * 9))
        }

        // The three gamuts, to compare what each kind of screen can show; their white, D65.
        for g in Gamut.allCases {
            var triangle = Path()
            for (i, corner) in g.primaries.enumerated() { i == 0 ? triangle.move(to: at(corner.0, corner.1)) : triangle.addLine(to: at(corner.0, corner.1)) }
            triangle.closeSubpath()
            context.stroke(triangle, with: .color(.black.opacity(0.6)), style: Self.style(g))
        }
        var cross = Path()
        cross.move(to: CGPoint(x: centre.x - 4, y: centre.y)); cross.addLine(to: CGPoint(x: centre.x + 4, y: centre.y))
        cross.move(to: CGPoint(x: centre.x, y: centre.y - 4)); cross.addLine(to: CGPoint(x: centre.x, y: centre.y + 4))
        context.stroke(cross, with: .color(.black.opacity(0.6)), lineWidth: 1)
        context.draw(Text("D65").font(.system(size: 8)).foregroundStyle(.black.opacity(0.6)), at: CGPoint(x: centre.x + 14, y: centre.y + 7))

        // The answer's colours: the path and the lines first, then the marks over them, the result larger.
        let points = scene.marks.map { at($0.colour.xy.0, $0.colour.xy.1) }
        if scene.path.count > 1 {
            var path = Path()
            path.addLines(scene.path.map { at($0.xy.0, $0.xy.1) })
            context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(.black.opacity(0.7)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round, dash: [4, 3]))
        }
        for (a, b) in scene.lines {
            var line = Path(); line.move(to: points[a]); line.addLine(to: points[b])
            context.stroke(line, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            context.stroke(line, with: .color(.black.opacity(0.75)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [4, 3]))
        }
        var placed: [CGRect] = []
        for (i, (mark, p)) in zip(scene.marks, points).enumerated() {
            let r: CGFloat = mark.small ? 3 : mark.result ? 6.5 : 5
            let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            context.fill(dot, with: .color(mark.colour.shown))
            context.stroke(dot, with: .color(.white), lineWidth: 1.5)
            // Beyond sRGB: a dashed ring, as most screens cannot show it as it is.
            let outside = !mark.colour.inSRGB
            context.stroke(Path(ellipseIn: CGRect(x: p.x - r - 1, y: p.y - r - 1, width: 2 * r + 2, height: 2 * r + 2)), with: .color(.black.opacity(0.65)),
                           style: StrokeStyle(lineWidth: outside ? 1 : 0.6, dash: outside ? [2, 2] : []))
            if i == focus {
                context.stroke(Path(ellipseIn: CGRect(x: p.x - r - 4, y: p.y - r - 4, width: 2 * r + 8, height: 2 * r + 8)), with: .color(.black.opacity(0.75)), lineWidth: 1.5)   // chosen by the pointer: no accent, as everywhere
            }
            // A label beside it, moved down where another is already there.
            guard !mark.label.isEmpty else { continue }
            let text = mark.input == nil && !mark.result ? mark.label : Self.caption(mark)
            let label = context.resolve(Text(text).font(.system(size: 10, weight: mark.result ? .semibold : .regular, design: .monospaced)).foregroundStyle(.black))
            let size = label.measure(in: CGSize(width: 240, height: 20))
            var plate = CGRect(x: p.x + r + 4, y: p.y - size.height / 2 - 1, width: size.width + 4, height: size.height + 2)
            if plate.maxX > plot.maxX { plate.origin.x = p.x - r - 4 - plate.width }
            while placed.contains(where: { $0.intersects(plate) }) { plate.origin.y += size.height + 3 }
            placed.append(plate)
            context.fill(Path(roundedRect: plate, cornerRadius: 3), with: .color(.white.opacity(0.85)))
            context.draw(label, at: CGPoint(x: plate.minX + 2, y: plate.midY), anchor: .leading)
        }

        // The numbers of the grid, inside the edges: across along the foot, up along the left.
        var key = above
        func number(_ v: Double) -> Text { Text(String(format: "%.\(places)f", v)).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary) }
        for v in xTicks where at(v, 0).x > plot.minX + 26 && at(v, 0).x < plot.maxX - 12 {
            key.draw(number(v), at: CGPoint(x: at(v, 0).x, y: plot.maxY - 8))
        }
        for v in yTicks where at(0, v).y > plot.minY + 10 && at(0, v).y < plot.maxY - 18 {
            key.draw(number(v), at: CGPoint(x: plot.minX + 6, y: at(0, v).y), anchor: .leading)
        }
        key.draw(Text("x").font(.system(size: 10, weight: .medium).italic()).foregroundStyle(.secondary), at: CGPoint(x: plot.maxX - 8, y: plot.maxY - 8))
        key.draw(Text("y").font(.system(size: 10, weight: .medium).italic()).foregroundStyle(.secondary), at: CGPoint(x: plot.minX + 8, y: plot.minY + 10))

        // The key to the triangles, in the corner at the top right, on a plate so that it reads over the colours.
        let right = plot.maxX - 44
        key.fill(Path(roundedRect: CGRect(x: right - 88, y: plot.minY + 3, width: 92, height: 44), cornerRadius: 5), with: .color(.white.opacity(0.75)))
        for (row, g) in Gamut.allCases.enumerated() {
            let y = plot.minY + 12 + CGFloat(row) * 13
            key.draw(Text(g.rawValue).font(.system(size: 9.5, weight: .medium)).foregroundStyle(.black.opacity(0.7)), at: CGPoint(x: right, y: y), anchor: .trailing)
            var sample = Path(); sample.move(to: CGPoint(x: right - 82, y: y)); sample.addLine(to: CGPoint(x: right - 62, y: y))
            key.stroke(sample, with: .color(.black.opacity(0.6)), style: Self.style(g))
        }
    }
}

// The diagram's mouse and trackpad, taken in AppKit, where they arrive though the panel is never the
// key window: a press and the drag after it, which go on reaching it wherever the pointer goes until
// the button is let go; a pinch to zoom; a double-click to go back. The wheel and two-finger scrolling
// go on to the panel.
private struct DiagramInput: NSViewRepresentable {
    var press: (CGPoint) -> Void
    var drag: (CGPoint, CGSize) -> Void
    var release: () -> Void
    var zoom: (Double, CGPoint) -> Void     // factor (under 1 zooms in) and where, from the top left
    var reset: () -> Void

    func makeNSView(context: Context) -> DiagramInputView { DiagramInputView() }
    func updateNSView(_ view: DiagramInputView, context: Context) { view.input = self }
}

private final class DiagramInputView: NSView {
    var input: DiagramInput?
    private var start: NSPoint?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func point(_ event: NSEvent) -> NSPoint { convert(event.locationInWindow, from: nil) }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { return input?.reset() ?? () }
        start = point(event)
        input?.press(start!)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let p = point(event)
        input?.drag(p, CGSize(width: p.x - start.x, height: p.y - start.y))
    }

    override func mouseUp(with event: NSEvent) {
        start = nil
        input?.release()
    }

    override func magnify(with event: NSEvent) { pinch(event.magnification, at: event.locationInWindow) }
}

extension DiagramInputView: Pinchable {
    func pinch(_ magnification: CGFloat, at windowPoint: NSPoint) {
        input?.zoom(1 / (1 + Double(magnification)), convert(windowPoint, from: nil))
    }
}
