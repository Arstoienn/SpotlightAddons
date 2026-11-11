import SwiftUI

// The truth table: the inputs, a rule, then the outputs, a row to each combination of the inputs,
// its number at the left; 1 strong and 0 faint, so the rows where an output is 1 stand out. The row the
// circuit is set to is marked, and clicking a row sets the circuit's inputs to it.
struct TruthTableView: View {
    let table: TruthTable
    var probe: CircuitProbe?

    var body: some View {
        Grid(alignment: .center, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                Text("#").font(.system(size: 11)).foregroundStyle(.tertiary).frame(width: 30)
                ForEach(Array(table.inputs.enumerated()), id: \.offset) { _, name in heading(name) }
                Rectangle().fill(.separator).frame(width: 1, height: 22)
                ForEach(Array(table.outputs.enumerated()), id: \.offset) { _, name in heading(name).fontWeight(.semibold) }
            }
            Divider().gridCellUnsizedAxes(.horizontal)
            ForEach(Array(table.rows.enumerated()), id: \.offset) { r, row in
                let current = probe?.row == r
                GridRow {
                    Text("\(r)").font(.system(size: 11, design: .monospaced)).foregroundStyle(current ? Color.accentColor : Color.secondary.opacity(0.6)).frame(width: 30)
                    ForEach(0..<table.inputs.count, id: \.self) { k in cell(row[k], strong: false) }
                    Rectangle().fill(.separator).frame(width: 1, height: 20)
                    ForEach(0..<table.outputs.count, id: \.self) { k in cell(row[table.inputs.count + k], strong: true) }
                }
                .background(current ? Color.accentColor.opacity(0.16) : r % 2 == 1 ? Color.primary.opacity(0.035) : .clear)
                .overlay { if let probe { ClickTarget { probe.row = r } } }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func heading(_ name: String) -> Text {
        Text(subscripted(name, size: 13)).font(.system(size: 13))
    }

    private func cell(_ v: Bool, strong: Bool) -> some View {
        Text(v ? "1" : "0")
            .font(.system(size: 13, weight: v && strong ? .semibold : .regular, design: .monospaced))
            .foregroundStyle(v ? (strong ? Color.primary : Color.secondary) : Color.secondary.opacity(0.45))
            .frame(minWidth: 44)
            .padding(.vertical, 2)
    }
}

// The gates as a textbook draws them: AND a D, OR a shield, XOR a shield with a second curve behind,
// NOT a triangle, and a small circle on the output of NAND, NOR, XNOR and NOT. Drawn at the size
// laid out, or smaller to fit the width.
//
// It works, as the row the truth table is set to has it: each input and output with its 0 or 1, and
// every wire that carries a 1 lit. Clicking an input, its name or its terminal, switches it.
struct CircuitDiagram: View {
    let layout: CircuitLayout
    var probe: CircuitProbe?

    var body: some View {
        let values = layout.values(row: probe?.row ?? 0, order: layout.order)
        VStack(alignment: .leading, spacing: 8) {
            Canvas { context, size in
                let (scale, dx) = fit(size)
                context.translateBy(x: dx, y: 0)
                context.scaleBy(x: scale, y: scale)
                draw(&context, values)
            }
            .overlay {
                if probe != nil {
                    GeometryReader { geometry in
                        PointClick { point in click(point, geometry.size) }
                    }
                }
            }
            .aspectRatio(layout.size.width / max(layout.size.height, 1), contentMode: .fit)
            .frame(maxWidth: layout.size.width)
            .frame(maxWidth: .infinity)
            if probe != nil, !layout.inputs.isEmpty {
                Text("Click an input to switch it between 0 and 1, or a row of the truth table to set them all; the wires carrying 1 are lit.")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityLabel("A circuit of \(layout.gates.count) gates")
    }

    // How much smaller it is drawn to fit, and how far across it is put to stand in the middle.
    private func fit(_ size: CGSize) -> (CGFloat, CGFloat) {
        let scale = min(1, size.width / max(layout.size.width, 1))
        return (scale, (size.width - layout.size.width * scale) / 2)
    }

    // An input clicked, on its terminal or its name and its value to the left: switched.
    private func click(_ point: CGPoint, _ size: CGSize) {
        guard let probe else { return }
        let (scale, dx) = fit(size)
        let p = CGPoint(x: (point.x - dx) / scale, y: point.y / scale)
        guard let end = layout.inputs.first(where: { abs(p.y - $0.at.y) < 12 && p.x > $0.at.x - $0.labelWidth - 34 && p.x < $0.at.x + 10 }),
              let k = layout.order.firstIndex(of: end.name) else { return }
        probe.row ^= 1 << (layout.order.count - 1 - k)
    }

    private func draw(_ context: inout GraphicsContext, _ values: [Bool]) {
        let ink = Color.primary.opacity(0.85), live = Color.accentColor
        let on = { (node: Int) -> Bool in probe != nil && node >= 0 && node < values.count && values[node] }

        // The wires as two paths, those carrying 0 and those carrying 1, so that where two run together
        // the line is no darker.
        var off = Path(), lit = Path()
        for (wire, node) in zip(layout.wires, layout.signals.count == layout.wires.count ? layout.signals : Array(repeating: -1, count: layout.wires.count)) {
            if on(node) { lit.addLines(wire) } else { off.addLines(wire) }
        }
        context.stroke(off, with: .color(ink), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
        context.stroke(lit, with: .color(live), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
        for gate in layout.gates { draw(gate, in: &context, ink: ink) }
        for (k, dot) in layout.dots.enumerated() {
            let node = k < layout.dotSignals.count ? layout.dotSignals[k] : -1
            context.fill(Path(ellipseIn: CGRect(x: dot.x - 3, y: dot.y - 3, width: 6, height: 6)), with: .color(on(node) ? live : ink))
        }
        for point in layout.terminals {
            let ring = Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6))
            context.fill(ring, with: .color(Color(nsColor: .windowBackgroundColor)))
            context.stroke(ring, with: .color(ink), lineWidth: 1.2)
        }
        for label in layout.labels {
            let text = Text(subscripted(label.text, size: 13)).font(.system(size: 13, weight: .medium))
            context.draw(text, at: label.at, anchor: label.leading ? .leading : .trailing)
        }
        guard probe != nil else { return }
        // Each input's value before its name, and each output's after its name: 1 lit, 0 faint.
        func badge(_ value: Bool, at point: CGPoint) {
            let box = CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16)
            context.fill(Path(roundedRect: box, cornerRadius: 4), with: .color(value ? live : Color.primary.opacity(0.08)))
            context.draw(Text(value ? "1" : "0").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(value ? Color.white : Color.secondary),
                         at: point)
        }
        for end in layout.inputs { badge(on(end.node), at: CGPoint(x: end.at.x - end.labelWidth - 18, y: end.at.y)) }
        for end in layout.outputs { badge(on(end.node), at: CGPoint(x: end.at.x + end.labelWidth + 18, y: end.at.y)) }
    }

    private func draw(_ gate: CircuitLayout.Gate, in context: inout GraphicsContext, ink: Color) {
        let f = gate.frame
        let bubble: Bool = [.nand, .nor, .xnor, .not].contains(gate.kind)
        let body = CGRect(x: f.minX, y: f.minY, width: f.width - (bubble ? 8 : 0), height: f.height)
        var shape = Path(), back = Path()
        // How far into the gate a wire goes to meet its back, curved for OR and XOR.
        var reach: (CGFloat) -> CGFloat = { _ in 0 }
        switch gate.kind {
        case .and, .nand:
            let straight = max(body.width - body.height / 2, body.width * 0.4)
            shape.move(to: CGPoint(x: body.minX, y: body.minY))
            shape.addLine(to: CGPoint(x: body.minX + straight, y: body.minY))
            shape.addCurve(to: CGPoint(x: body.minX + straight, y: body.maxY),
                           control1: CGPoint(x: body.maxX + (body.width - straight) * 0.33, y: body.minY),
                           control2: CGPoint(x: body.maxX + (body.width - straight) * 0.33, y: body.maxY))
            shape.addLine(to: CGPoint(x: body.minX, y: body.maxY))
            shape.closeSubpath()
        case .or, .nor, .xor, .xnor:
            let shift: CGFloat = gate.kind == .xor || gate.kind == .xnor ? 7 : 0
            let b = CGRect(x: body.minX + shift, y: body.minY, width: body.width - shift, height: body.height)
            let depth = b.width * 0.22
            shape.move(to: CGPoint(x: b.minX, y: b.minY))
            shape.addQuadCurve(to: CGPoint(x: b.maxX, y: b.midY), control: CGPoint(x: b.minX + b.width * 0.62, y: b.minY))
            shape.addQuadCurve(to: CGPoint(x: b.minX, y: b.maxY), control: CGPoint(x: b.minX + b.width * 0.62, y: b.maxY))
            shape.addQuadCurve(to: CGPoint(x: b.minX, y: b.minY), control: CGPoint(x: b.minX + depth * 2, y: b.midY))
            shape.closeSubpath()
            if shift > 0 {
                back.move(to: CGPoint(x: body.minX, y: body.minY))
                back.addQuadCurve(to: CGPoint(x: body.minX, y: body.maxY), control: CGPoint(x: body.minX + depth * 2, y: body.midY))
            }
            reach = { y in
                let t = (y - b.minY) / max(b.height, 1)
                return shift + 2 * depth * 2 * t * (1 - t) * 0.5 * 2
            }
        case .not:
            shape.move(to: CGPoint(x: body.minX, y: body.minY + 3))
            shape.addLine(to: CGPoint(x: body.maxX, y: body.midY))
            shape.addLine(to: CGPoint(x: body.minX, y: body.maxY - 3))
            shape.closeSubpath()
        }
        // The wires carried on to the back of the gate.
        for y in gate.pins where reach(y) > 0.5 {
            var stub = Path()
            stub.move(to: CGPoint(x: f.minX, y: y))
            stub.addLine(to: CGPoint(x: f.minX + reach(y), y: y))
            context.stroke(stub, with: .color(ink), lineWidth: 1.3)
        }
        context.fill(shape, with: .color(Color(nsColor: .controlBackgroundColor)))
        context.stroke(shape, with: .color(ink), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        context.stroke(back, with: .color(ink), lineWidth: 1.5)
        if bubble {
            let circle = Path(ellipseIn: CGRect(x: body.maxX, y: f.midY - 4, width: 8, height: 8))
            context.fill(circle, with: .color(Color(nsColor: .controlBackgroundColor)))
            context.stroke(circle, with: .color(ink), lineWidth: 1.4)
        }
    }
}

// A click and where it was, taken in AppKit: the panel is never key, where SwiftUI would not see it.
private struct PointClick: NSViewRepresentable {
    var action: (CGPoint) -> Void

    func makeNSView(context: Context) -> PointClickView { PointClickView() }
    func updateNSView(_ view: PointClickView, context: Context) { view.action = action }
}

private final class PointClickView: NSView {
    var action: (CGPoint) -> Void = { _ in }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if bounds.contains(p) { action(p) }
    }
}
