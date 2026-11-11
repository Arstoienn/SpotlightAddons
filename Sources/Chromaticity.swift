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
// them; the result of a mixture can be dragged along its path, or moved there with the slider. A click
// on a colour gives its x, y and Y exactly. The card above is as it was typed.
struct ChromaticityDiagram: View {
    let diagram: Chromaticity

    @State private var inputs: [RGBA]?
    @State private var share: Double?
    @State private var selected: Int?
    @State private var gamut: Gamut?
    @State private var dragging: Int?

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

    // The horseshoe's colours, worked out once: at each point inside it, the colour of that x and y
    // at the brightest that can be shown.
    static let fill: CGImage? = {
        let (w, h) = (320, 360)
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        func encode(_ c: Double) -> Double { c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055 }
        for row in 0..<h {
            for col in 0..<w {
                let x = (Double(col) + 0.5) / Double(w) * span.x, y = (1 - (Double(row) + 0.5) / Double(h)) * span.y
                guard y > 0.001, visible(x, y) else { continue }
                var (r, g, b) = Gamut.srgb.fromXYZ((x / y, 1, (1 - x - y) / y))
                let low = min(r, g, b)
                if low < 0 { r -= low; g -= low; b -= low }
                let high = max(r, g, b, 1e-9)
                let i = (row * w + col) * 4
                pixels[i] = UInt8(encode(r / high) * 255); pixels[i + 1] = UInt8(encode(g / high) * 255)
                pixels[i + 2] = UInt8(encode(b / high) * 255); pixels[i + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)
    }()

    // Where the plot is in the view, and the way between x, y and points on it.
    struct Layout {
        let plot: CGRect
        init(_ size: CGSize) {
            let left: CGFloat = 30, bottom: CGFloat = 20
            let height = min(size.height - bottom - 4, (size.width - left - 4) * CGFloat(span.y / span.x))
            let width = height * CGFloat(span.x / span.y)
            plot = CGRect(x: left + (size.width - left - width) / 2, y: 4, width: width, height: height)
        }
        func at(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: plot.minX + CGFloat(x / span.x) * plot.width, y: plot.maxY - CGFloat(y / span.y) * plot.height)
        }
        func xy(_ p: CGPoint) -> (Double, Double) {
            (Double((p.x - plot.minX) / plot.width) * span.x, Double((plot.maxY - p.y) / plot.height) * span.y)
        }
    }

    private var currentInputs: [RGBA] { inputs ?? diagram.inputs }
    private var currentShare: Double { share ?? diagram.share ?? 0.5 }
    private var scene: Chromaticity.Scene { diagram.make(currentInputs, currentShare) }
    private var changed: Bool { inputs != nil || share != nil }
    // The gamut drawn: the one chosen, else the smallest every colour here lies in.
    private var shownGamut: Gamut {
        if let gamut { return gamut }
        let marks = scene.marks
        return Gamut.allCases.first { g in marks.allSatisfy { $0.colour.within(g) } } ?? .rec2020
    }
    // The colour whose values are given below: the one clicked, else the result.
    private var focus: Int? {
        let marks = scene.marks
        if let selected, selected < marks.count { return selected }
        return marks.lastIndex { $0.result } ?? (marks.isEmpty ? nil : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geometry in
                let layout = Layout(geometry.size), scene = scene
                Canvas { context, _ in draw(&context, layout, scene) }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { drag in moved(drag, layout, scene) }.onEnded { _ in dragging = nil })
            }
            .frame(height: 340)

            HStack(spacing: 12) {
                Picker("Gamut", selection: Binding(get: { shownGamut }, set: { gamut = $0 })) {
                    ForEach(Gamut.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                if diagram.share != nil {
                    Text("A").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { currentShare }, set: { share = $0 }), in: 0...1)
                        .controlSize(.small)
                    Text("B").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if changed {
                    Button("As typed") { withAnimation(.smooth(duration: 0.25)) { inputs = nil; share = nil } }
                        .controlSize(.small)
                }
            }
            if let focus { readout(scene.marks[focus]) }
            Text(hint).font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("The CIE 1931 chromaticity diagram")
    }

    private var hint: String {
        var parts: [String] = []
        if scene.marks.contains(where: { $0.input != nil }) { parts.append("Drag a colour typed to move it") }
        if scene.onPath != nil { parts.append("drag the result along its path") }
        parts.append("click a colour for its xyY")
        let joined = parts.joined(separator: "; ")
        return joined.prefix(1).uppercased() + joined.dropFirst() + "."
    }

    // The colour's name here, its hex, x, y and Y, the share where it is a mixture, and the gamuts it lies in.
    private func readout(_ mark: Chromaticity.Mark) -> some View {
        let (x, y, Y) = mark.colour.xyY
        let place = Colour.beyond(mark.colour) ?? "within sRGB"
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(mark.colour.shown)
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5))
                .frame(width: 16, height: 16)
            Text(mark.label.isEmpty ? "Colour" : mark.label).font(.system(size: 12, weight: .semibold))
            Text(Colour.written(mark.colour, .hex)).font(.system(size: 12, design: .monospaced))
            Text(String(format: "x = %.4f   y = %.4f   Y = %.4f", x, y, Y)).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
            Text(mark.result && diagram.share != nil ? "\(Colour.number(currentShare * 100))% A, \(place)" : place)
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    // A press picks the colour under it; dragging moves a colour typed, keeping its Y, or the result of
    // a mixture along its path. Everything made from them is made again as it goes.
    private func moved(_ drag: DragGesture.Value, _ layout: Layout, _ scene: Chromaticity.Scene) {
        if dragging == nil {
            let near = scene.marks.indices.map { i -> (Int, CGFloat) in
                let p = layout.at(scene.marks[i].colour.xy.0, scene.marks[i].colour.xy.1)
                return (i, hypot(p.x - drag.startLocation.x, p.y - drag.startLocation.y))
            }.filter { $0.1 < 14 }.min { $0.1 < $1.1 }
            guard let (i, _) = near else { return }
            dragging = i
            selected = i
        }
        guard let i = dragging, i < scene.marks.count, hypot(drag.translation.width, drag.translation.height) > 1 else { return }
        let mark = scene.marks[i]
        if let input = mark.input {
            let (x, y) = layout.xy(drag.location)
            guard ChromaticityDiagram.visible(x, y) else { return }
            var all = currentInputs
            let Y = max(all[input].xyY.2, 0.02)
            all[input] = RGBA(x: x, y: y, Y: Y, a: all[input].a)
            inputs = all
        } else if i == scene.onPath, !scene.path.isEmpty {
            // The nearest of the path's colours to the pointer, as a share of A.
            let points = scene.path.map { layout.at($0.xy.0, $0.xy.1) }
            let k = points.indices.min { hypot(points[$0].x - drag.location.x, points[$0].y - drag.location.y) < hypot(points[$1].x - drag.location.x, points[$1].y - drag.location.y) }!
            share = 1 - Double(k) / Double(points.count - 1)
        }
    }

    private func draw(_ context: inout GraphicsContext, _ layout: Layout, _ scene: Chromaticity.Scene) {
        let plot = layout.plot
        func at(_ x: Double, _ y: Double) -> CGPoint { layout.at(x, y) }
        let faint = Color.secondary.opacity(0.35)

        // The axes, every 0.1.
        for k in 0...9 {
            let v = Double(k) / 10
            if v <= Self.span.x {
                var tick = Path(); tick.move(to: at(v, 0)); tick.addLine(to: at(v, Self.span.y))
                context.stroke(tick, with: .color(faint.opacity(0.4)), lineWidth: 0.5)
                context.draw(Text(String(format: "%.1f", v)).font(.system(size: 9)).foregroundStyle(.secondary), at: CGPoint(x: at(v, 0).x, y: plot.maxY + 9))
            }
            var tick = Path(); tick.move(to: at(0, v)); tick.addLine(to: at(Self.span.x, v))
            context.stroke(tick, with: .color(faint.opacity(0.4)), lineWidth: 0.5)
            context.draw(Text(String(format: "%.1f", v)).font(.system(size: 9)).foregroundStyle(.secondary), at: CGPoint(x: plot.minX - 13, y: at(0, v).y))
        }
        context.draw(Text("x").font(.system(size: 10, weight: .medium).italic()).foregroundStyle(.secondary), at: CGPoint(x: plot.maxX - 6, y: plot.maxY - 9))
        context.draw(Text("y").font(.system(size: 10, weight: .medium).italic()).foregroundStyle(.secondary), at: CGPoint(x: plot.minX + 8, y: plot.minY + 8))

        // The horseshoe, its colours and its edge.
        var shoe = Path()
        for (i, point) in Self.locus.enumerated() { i == 0 ? shoe.move(to: at(point.1, point.2)) : shoe.addLine(to: at(point.1, point.2)) }
        shoe.closeSubpath()
        if let fill = Self.fill {
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

        // The gamut chosen, solid; the other two faint and dashed, to compare. Its white, D65.
        for g in Gamut.allCases {
            var triangle = Path()
            for (i, corner) in g.primaries.enumerated() { i == 0 ? triangle.move(to: at(corner.0, corner.1)) : triangle.addLine(to: at(corner.0, corner.1)) }
            triangle.closeSubpath()
            if g == shownGamut {
                context.stroke(triangle, with: .color(.black.opacity(0.6)), lineWidth: 1)
                let corner = at(g.primaries[1].0, g.primaries[1].1)
                context.draw(Text(g.rawValue).font(.system(size: 9, weight: .semibold)).foregroundStyle(.black.opacity(0.65)),
                             at: CGPoint(x: corner.x + 6, y: corner.y - 4), anchor: .bottomLeading)
            } else {
                context.stroke(triangle, with: .color(.black.opacity(0.22)), style: StrokeStyle(lineWidth: 0.7, dash: [3, 3]))
            }
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
            // Beyond the gamut drawn: a dashed ring, as the screen cannot show it as it is.
            let outside = !mark.colour.within(shownGamut)
            context.stroke(Path(ellipseIn: CGRect(x: p.x - r - 1, y: p.y - r - 1, width: 2 * r + 2, height: 2 * r + 2)), with: .color(.black.opacity(0.65)),
                           style: StrokeStyle(lineWidth: outside ? 1 : 0.6, dash: outside ? [2, 2] : []))
            if i == focus {
                context.stroke(Path(ellipseIn: CGRect(x: p.x - r - 4, y: p.y - r - 4, width: 2 * r + 8, height: 2 * r + 8)), with: .color(.accentColor), lineWidth: 1.5)
            }
            // A label beside it, moved down where another is already there.
            guard !mark.label.isEmpty else { continue }
            let text = mark.input == nil && !mark.result ? mark.label : "\(mark.label)  \(Colour.written(mark.colour, .hex))"
            let label = context.resolve(Text(text).font(.system(size: 10, weight: mark.result ? .semibold : .regular, design: .monospaced)).foregroundStyle(.black))
            let size = label.measure(in: CGSize(width: 240, height: 20))
            var plate = CGRect(x: p.x + r + 4, y: p.y - size.height / 2 - 1, width: size.width + 4, height: size.height + 2)
            if plate.maxX > plot.maxX + 20 { plate.origin.x = p.x - r - 4 - plate.width }
            while placed.contains(where: { $0.intersects(plate) }) { plate.origin.y += size.height + 3 }
            placed.append(plate)
            context.fill(Path(roundedRect: plate, cornerRadius: 3), with: .color(.white.opacity(0.85)))
            context.draw(label, at: CGPoint(x: plate.minX + 2, y: plate.midY), anchor: .leading)
        }
    }
}
