import AppKit
import Charts
import SwiftUI

// The card, grown: resting the pointer on it opens the working in a glass panel that starts as
// the card and expands downwards over Spotlight; moving the pointer off shrinks it back into the
// card. It never takes the keyboard, so Spotlight stays open underneath and typing goes on
// reaching it.
//
// The window is full size from the start and never resized: resizing a window every frame makes
// AppKit lay out and redraw everything in it each time, and the animation stutters. Instead the
// working is laid out once, at full size, and only the glass shape over it grows and shrinks,
// which SwiftUI animates on the render server like Spotlight's own glass.
final class DetailPanel {
    private var panel: NSPanel?
    private var tracker: ExitTracker?
    private var model: DetailModel?
    private var onCollapsed: () -> Void = {}
    private var shadowTimer: Timer?
    var isOpen: Bool { panel != nil }

    // onCovered: the panel is on screen, drawn, over the card, which can now be put away. Until
    // then both are up, so there is never a frame with neither.
    func show(_ answer: Solution, _ details: Details, from card: NSRect, level: NSWindow.Level,
              onCovered: @escaping () -> Void, onCollapsed: @escaping () -> Void) {
        close(animated: false)
        self.onCollapsed = onCollapsed

        let width = card.width
        let measure = NSHostingView(rootView: DetailContent(answer: answer, d: details).frame(width: width))
        let screen = NSScreen.screens.first { $0.frame.intersects(card) } ?? NSScreen.main
        let room = card.maxY - (screen?.visibleFrame.minY ?? 0) - 24
        let height = min(measure.fittingSize.height, room)
        let target = NSRect(x: card.minX, y: card.maxY - height, width: width, height: height)

        let panel = NSPanel(contentRect: target.insetBy(dx: -Chrome.margin, dy: -Chrome.margin),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = level
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // The system's shadow, with the same fine dark edge as the card's; it is worked out from
        // what the window shows, so it is worked out again every frame while the glass moves.
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let model = DetailModel(cardHeight: card.height)
        let host = FirstMouseHostingView(rootView: ExpandingDetail(answer: answer, d: details, model: model).padding(Chrome.margin))
        panel.contentView = host

        let tracker = ExitTracker { [weak self] in self?.collapse() }
        tracker.inside = { [weak panel] in
            panel.map { $0.frame.insetBy(dx: Chrome.margin, dy: Chrome.margin).contains(NSEvent.mouseLocation) } ?? false
        }
        host.addTrackingArea(NSTrackingArea(rect: host.bounds.insetBy(dx: Chrome.margin, dy: Chrome.margin),
                                            options: [.mouseEnteredAndExited, .activeAlways], owner: tracker, userInfo: nil))
        self.tracker = tracker
        self.model = model
        self.panel = panel
        host.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        panel.orderFrontRegardless()
        DispatchQueue.main.async { [weak self] in
            onCovered()
            self?.followShadow(for: 0.5)
            withAnimation(.spring(duration: 0.42, bounce: 0.1)) {
                model.expanded = true
            } completion: {
                // Only now, at full size, does a scroller mean the working is longer than the panel.
                model.settled = true
            }
        }
    }

    private func followShadow(for duration: TimeInterval) {
        shadowTimer?.invalidate()
        let end = Date().addingTimeInterval(duration)
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] timer in
            self?.panel?.invalidateShadow()
            if Date() > end { timer.invalidate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        shadowTimer = timer
    }

    // The way it came: back up into the card's shape, whose top it never stopped showing, so the
    // card can take over without a seam.
    func collapse() {
        guard let panel, let model else { return }
        self.panel = nil
        self.model = nil
        tracker = nil
        model.settled = false
        let done = onCollapsed
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { _ in panel.invalidateShadow() }
        RunLoop.main.add(timer, forMode: .common)
        withAnimation(.spring(duration: 0.3, bounce: 0)) {
            model.expanded = false
        } completion: {
            timer.invalidate()
            // The card first, then the panel off the top of it a moment later: never neither.
            done()
            DispatchQueue.main.async { panel.orderOut(nil) }
        }
    }

    // When Spotlight goes or moves, or what was typed changes, the panel goes too, without shrinking.
    func close(animated: Bool) {
        guard let panel else { return }
        self.panel = nil
        model = nil
        tracker = nil
        guard animated else { return panel.orderOut(nil) }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }
}

// The card and the panel share their glass and its corners, and both windows draw the system's
// shadow round it.
enum Chrome {
    static let margin: CGFloat = 0
    static let radius: CGFloat = 26
}

extension View {
    func spotlightGlass() -> some View {
        glassEffect(.regular, in: RoundedRectangle(cornerRadius: Chrome.radius, style: .continuous))
    }
}

// How far open the panel is. expanded drives the glass; settled says the opening has finished.
@Observable final class DetailModel {
    let cardHeight: CGFloat
    var expanded = false
    var settled = false
    init(cardHeight: CGFloat) { self.cardHeight = cardHeight }
}

// The working at its full size, behind glass that is the card's height when closed and the
// panel's when open; everything outside the glass is clipped away.
struct ExpandingDetail: View {
    let answer: Solution
    let d: Details
    let model: DetailModel

    var body: some View {
        GeometryReader { geometry in
            DetailView(answer: answer, d: d, model: model)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                .frame(height: model.expanded ? geometry.size.height : model.cardHeight, alignment: .top)
                .clipShape(RoundedRectangle(cornerRadius: Chrome.radius, style: .continuous))
                .spotlightGlass()
        }
    }
}

// The panel is never key, so without this the first click of a drag on the graph would be spent
// making it so.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class ExitTracker: NSResponder {
    let onExit: () -> Void
    init(_ onExit: @escaping () -> Void) {
        self.onExit = onExit
        super.init()
    }
    required init?(coder: NSCoder) { fatalError() }

    // Dragging the graph can carry the pointer out of the panel; that is not leaving it. Once the
    // button is let go, the panel closes only if the pointer is still outside.
    override func mouseExited(with event: NSEvent) {
        guard NSEvent.pressedMouseButtons != 0 else { return onExit() }
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard NSEvent.pressedMouseButtons == 0 else { return }
            timer.invalidate()
            if let self, !inside() { onExit() }
        }
    }

    var inside: () -> Bool = { false }
}

// The graph's mouse and trackpad, taken in AppKit, where they arrive even though the panel is
// never the key window: drag, scroll wheel or two-finger scroll, pinch, double-click. Scrolling
// over the graph zooms it rather than scrolling the panel.
private struct GraphInput: NSViewRepresentable {
    var onDrag: (CGSize) -> Void
    var onDragEnd: () -> Void
    var onZoom: (Double, CGPoint) -> Void   // factor (under 1 zooms in) and where, from the top left
    var onReset: () -> Void

    func makeNSView(context: Context) -> GraphInputView { GraphInputView() }
    func updateNSView(_ view: GraphInputView, context: Context) { view.input = self }
}

private final class GraphInputView: NSView {
    var input: GraphInput?
    private var start: NSPoint?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func point(_ event: NSEvent) -> NSPoint { convert(event.locationInWindow, from: nil) }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { return input?.onReset() ?? () }
        start = point(event)
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let p = point(event)
        input?.onDrag(CGSize(width: p.x - start.x, height: p.y - start.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        start = nil
        NSCursor.pop()
        input?.onDragEnd()
    }

    override func scrollWheel(with event: NSEvent) {
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
        guard dy != 0 else { return }
        input?.onZoom(exp(-Double(dy) * 0.01), point(event))
    }

    override func magnify(with event: NSEvent) {
        input?.onZoom(1 / (1 + Double(event.magnification)), point(event))
    }
}

// MARK: - Content

// Until the panel has finished opening it is shorter than what is in it only because it is still
// growing, and a scroller would come and go for nothing.
struct DetailView: View {
    let answer: Solution
    let d: Details
    let model: DetailModel

    var body: some View {
        ScrollView { DetailContent(answer: answer, d: d) }
            .scrollIndicators(model.settled ? .automatic : .hidden)
            .scrollDisabled(!model.settled)
    }
}

// The top is the card exactly as it was, f(x) and answer in the same places, so the panel reads
// as the card growing rather than something new arriving. Under it, the working, the solutions
// and the graph sit on rounded platters inside the glass, and rise into place one after another.
struct DetailContent: View {
    let answer: Solution
    let d: Details
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardFace(answer: answer)

            VStack(alignment: .leading, spacing: 14) {
                platter("Working", index: 0) {
                    row(label: "Equation") { copyable(d.equation, size: 19) }
                    ForEach(Array(d.steps.enumerated()), id: \.offset) { _, step in
                        Divider().padding(.leading, 16)
                        row(label: step.label) {
                            if let math = step.math { copyable(math, size: 19) }
                            if let note = step.note {
                                Text(subscripted(note, size: 13)).font(.system(size: 13)).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                platter("Solutions", index: 1) {
                    VStack(alignment: .leading, spacing: 10) {
                        // A periodic function's dozen go in columns, so the graph stays in view.
                        if d.solutions.count > 3, d.whole == nil {
                            // Wide enough for the longest, an angle with its degrees after it.
                            let widest = CGFloat(d.solutions.map(\.plain.count).max() ?? 0) * 11.5
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: max(180, widest)), alignment: .leading)], alignment: .leading, spacing: 10) {
                                ForEach(Array(d.solutions.enumerated()), id: \.offset) { copyable($1, size: 20) }
                            }
                        } else {
                            // The answer is what the panel is for: larger than the working above it.
                            // One value over several lines is set smaller, so that its lines are all of a size.
                            ForEach(Array(d.solutions.enumerated()), id: \.offset) { copyable($1, size: d.whole == nil ? 26 : 15, copying: d.whole) }
                        }
                        if let note = d.note {
                            Text(note).font(.system(size: 13)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }

                if let graph = d.graph {
                    platter("Graph", index: 2) {
                        Plot(graph: graph)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                    }
                }

                HStack {
                    Spacer()
                    SettingsButton()
                }
                .opacity(shown ? 1 : 0)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .onAppear { shown = true }
    }

    // A titled, rounded group, concentric with the panel's corners; each one rises a moment
    // after the one above it.
    private func platter<Content: View>(_ title: String, index: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
            VStack(alignment: .leading, spacing: 0, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.primary.opacity(0.05)))
        }
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 12)
        .animation(.spring(response: 0.45, dampingFraction: 0.86).delay(0.06 + 0.05 * Double(index)), value: shown)
    }

    private func row<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(subscripted(label, size: 12)).font(.system(size: 12)).foregroundStyle(.secondary)
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // Maths can't be selected like text, so each line copies itself, as one line, from a menu.
    private func copyable(_ math: Math, size: CGFloat, copying whole: String? = nil) -> some View {
        MathText(math: math, size: size)
            .contextMenu {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(whole ?? math.plain, forType: .string)
                }
            }
    }
}

// Each curve or line in the graph, the first solid, the next dashed, then dotted, crossing at the
// marked points, which are labelled with where they are, over the two axes. As in Desmos: drag
// to move about, scroll or pinch to zoom, double-click to go back. Monochrome, in the label
// colour, so it sits in the glass like the text does. Where a curve jumps (tan x, 1/x) its line
// is broken rather than drawn up the asymptote.
private struct Plot: View {
    let graph: Graph

    // Dashes long and dark enough not to be taken for the grid, which is solid and faint.
    private static let styles: [(opacity: Double, dash: [CGFloat])] = [(0.85, []), (0.7, [7, 4]), (0.7, [1.5, 4]), (0.7, [9, 3, 2, 3])]
    private func style(_ i: Int) -> (opacity: Double, dash: [CGFloat]) { Plot.styles[i % Plot.styles.count] }

    @State private var view: (x: ClosedRange<Double>, y: ClosedRange<Double>)?
    @State private var gestureStart: (x: ClosedRange<Double>, y: ClosedRange<Double>)?

    struct Point: Identifiable {
        let id: String
        let x: Double
        let y: Double
        let series: String
        let curve: Int
    }

    var body: some View {
        let (xs, ys) = view ?? initial()
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                RuleMark(y: .value("x axis", 0)).foregroundStyle(Color.primary.opacity(0.35)).lineStyle(StrokeStyle(lineWidth: 1))
                RuleMark(x: .value("y axis", 0)).foregroundStyle(Color.primary.opacity(0.35)).lineStyle(StrokeStyle(lineWidth: 1))
                ForEach(samples(xs, ys)) { p in
                    LineMark(x: .value(graph.xName, p.x), y: .value(graph.yName, p.y), series: .value("curve", p.series))
                        .foregroundStyle(Color.primary.opacity(style(p.curve).opacity))
                        // Butt ends: Charts draws a long line in pieces, and round ends overlapping
                        // in a translucent colour leave darker dots where the pieces meet.
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .butt, lineJoin: .round, dash: style(p.curve).dash))
                }
                ForEach(Array(graph.curves.enumerated()), id: \.offset) { i, curve in
                    if case .vertical(let x) = curve.shape {
                        RuleMark(x: .value(graph.xName, x))
                            .foregroundStyle(Color.primary.opacity(style(i).opacity))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: style(i).dash))
                    }
                }
                ForEach(Array(graph.points.enumerated()).filter { xs.contains(Double($0.element.x)) }, id: \.offset) { _, point in
                    let (px, py) = (Double(point.x), Double(point.y))
                    PointMark(x: .value(graph.xName, px), y: .value(graph.yName, py))
                        .symbol {
                            Circle().strokeBorder(Color.primary, lineWidth: 2)
                                .background(Circle().fill(.background))
                                .frame(width: 11, height: 11)
                        }
                }
            }
            .chartXScale(domain: xs)
            .chartYScale(domain: ys)
            .chartXAxis { AxisMarks { AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.primary.opacity(0.1)); AxisValueLabel() } }
            .chartYAxis { AxisMarks(position: .leading) { AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.primary.opacity(0.1)); AxisValueLabel() } }
            .chartPlotStyle { $0.clipped() }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    let plot = proxy.plotFrame.map { geometry[$0] } ?? geometry.frame(in: .local)
                    // Curves given only as g(x, y) = 0 are traced over what is in view and drawn here.
                    Canvas { context, _ in
                        context.clip(to: Path(plot))
                        for (i, curve) in graph.curves.enumerated() {
                            guard case .implicit(let g) = curve.shape else { continue }
                            var path = Path()
                            for line in Contour.lines(g, xs, ys) {
                                let points = line.map { CGPoint(x: plot.minX + ($0.x - xs.lowerBound) / span(xs) * plot.width,
                                                                y: plot.minY + (ys.upperBound - $0.y) / span(ys) * plot.height) }
                                path.addLines(points)
                            }
                            context.stroke(path, with: .color(Color.primary.opacity(style(i).opacity)),
                                           style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: style(i).dash))
                        }
                        if graph.points.count <= 4 { label(&context, plot, xs, ys) }
                    }
                    .allowsHitTesting(false)
                    GraphInput(
                        onDrag: { translation in
                            let start = gestureStart ?? (xs, ys)
                            gestureStart = start
                            view = (shift(start.x, -translation.width / plot.width * span(start.x)),
                                    shift(start.y, translation.height / plot.height * span(start.y)))
                        },
                        onDragEnd: { gestureStart = nil },
                        onZoom: { factor, point in
                            // About the point under the pointer, which stays where it is, as in Desmos.
                            // From the latest view: scroll events can come faster than redraws.
                            let (cx, cy) = view ?? (xs, ys)
                            let x = cx.lowerBound + (point.x - plot.minX) / plot.width * span(cx)
                            let y = cy.upperBound - (point.y - plot.minY) / plot.height * span(cy)
                            view = (scale(cx, factor, about: x), scale(cy, factor, about: y))
                        },
                        onReset: { withAnimation(.smooth(duration: 0.3)) { view = nil } })
                }
            }
            .frame(height: 210)

            HStack(spacing: 16) {
                ForEach(Array(graph.curves.enumerated()), id: \.offset) { i, curve in legend(i, curve.label) }
                Spacer()
                Text("Drag to move · scroll or pinch to zoom · double-click to reset")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // Each marked point's coordinates beside it: up and to the right for choice, and otherwise
    // whichever corner is clear of the other labels, the other points and the curves, or a line
    // further up. One with nowhere clear to go is left out rather than written over another.
    private func label(_ context: inout GraphicsContext, _ plot: CGRect, _ xs: ClosedRange<Double>, _ ys: ClosedRange<Double>) {
        func place(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: plot.minX + (x - xs.lowerBound) / span(xs) * plot.width, y: plot.minY + (ys.upperBound - y) / span(ys) * plot.height)
        }
        // Whether a curve runs through the rectangle: at one of its points, or from above it to below.
        func crossed(_ r: CGRect) -> Bool {
            for curve in graph.curves {
                switch curve.shape {
                case .vertical(let x):
                    if (r.minX...r.maxX).contains(place(x, 0).x) { return true }
                case .function(let f):
                    var above = false, below = false
                    for k in 0...12 {
                        let x = xs.lowerBound + (r.minX + r.width * CGFloat(k) / 12 - plot.minX) / plot.width * span(xs)
                        let y = place(x, f(x)).y
                        guard y.isFinite else { continue }
                        if y < r.minY - 2 { above = true } else if y > r.maxY + 2 { below = true } else { return true }
                    }
                    if above && below { return true }
                case .implicit:
                    break
                }
            }
            return false
        }
        let marks = graph.points.map { place(Double($0.x), Double($0.y)) }
        var taken: [CGRect] = []
        for (i, point) in graph.points.enumerated().sorted(by: { $0.element.x < $1.element.x }) where plot.contains(marks[i]) {
            let text = context.resolve(Text("(" + decimal(Double(point.x)) + ", " + decimal(Double(point.y)) + ")")
                .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary))
            let size = text.measure(in: plot.size), gap: CGFloat = 7, at = marks[i]
            // To the right or left, above or below, and the upper two again a line higher.
            let corners: [(right: Bool, up: Bool, lift: CGFloat)] = [(true, true, 0), (false, true, 0), (true, false, 0), (false, false, 0),
                                                                      (true, true, 1), (false, true, 1)]
            let places = corners.map { corner in
                CGRect(x: corner.right ? at.x + gap : at.x - gap - size.width,
                       y: (corner.up ? at.y - gap - size.height : at.y + gap) - corner.lift * (size.height + 3),
                       width: size.width, height: size.height)
            }
            func clear(_ r: CGRect, ofCurves: Bool) -> Bool {
                plot.contains(r) && !taken.contains { $0.insetBy(dx: -3, dy: -1).intersects(r) }
                    && !marks.enumerated().contains { $0.offset != i && r.insetBy(dx: -7, dy: -7).contains($0.element) }
                    && !(ofCurves && crossed(r))
            }
            guard let rect = places.first(where: { clear($0, ofCurves: true) }) ?? places.first(where: { clear($0, ofCurves: false) }) else { continue }
            taken.append(rect)
            context.draw(text, in: rect)
        }
    }

    private func legend(_ i: Int, _ math: Math) -> some View {
        HStack(spacing: 6) {
            Path { $0.move(to: CGPoint(x: 0, y: 1)); $0.addLine(to: CGPoint(x: 18, y: 1)) }
                .stroke(Color.primary.opacity(style(i).opacity), style: StrokeStyle(lineWidth: 2, dash: style(i).dash))
                .frame(width: 18, height: 2)
            MathText(math: math, size: 12).fixedSize()
        }
    }

    private func span(_ r: ClosedRange<Double>) -> Double { r.upperBound - r.lowerBound }
    private func shift(_ r: ClosedRange<Double>, _ by: Double) -> ClosedRange<Double> { (r.lowerBound + by)...(r.upperBound + by) }
    private func scale(_ r: ClosedRange<Double>, _ k: Double, about c: Double) -> ClosedRange<Double> {
        let lower = c - (c - r.lowerBound) * k, upper = c + (r.upperBound - c) * k
        guard upper - lower > 1e-9, upper - lower < 1e9 else { return r }
        return lower...upper
    }

    // Wide enough for the four solutions nearest zero with room either side (a periodic
    // function's dozen would squash it flat); tall enough for most of both curves, ignoring the
    // far tails, and always showing where they cross.
    private var functions: [(Double) -> Double] {
        graph.curves.compactMap { if case .function(let f) = $0.shape { f } else { nil } }
    }

    // Wide enough for the four marked points nearest the origin, and any vertical lines, with
    // room either side (a periodic function's dozen would squash it flat); tall enough for most
    // of the curves, ignoring the far tails, and always showing the marked points.
    private func initial() -> (ClosedRange<Double>, ClosedRange<Double>) {
        if graph.curves.contains(where: { if case .implicit = $0.shape { true } else { false } }) { return framedCurves() }
        let framed = graph.points.sorted { hypot($0.x, $0.y) < hypot($1.x, $1.y) }.prefix(4)
        let verticals = graph.curves.compactMap { if case .vertical(let x) = $0.shape { x } else { nil } }
        let px = framed.map { Double($0.x) }, py = framed.map { Double($0.y) }
        let xs = px + verticals
        var lo = xs.min() ?? -10, hi = xs.max() ?? 10
        let pad = max(2, (hi - lo) * 0.25)
        lo -= pad
        hi += pad
        var values = (0...200).flatMap { i -> [Double] in
            let x = lo + (hi - lo) * Double(i) / 200
            return functions.map { $0(x) }
        }.filter(\.isFinite).sorted()
        values += py
        guard values.count > 10 else {
            let mid = py.isEmpty ? 0 : (py.min()! + py.max()!) / 2
            return (lo...hi, (mid - (hi - lo) / 3)...(mid + (hi - lo) / 3))
        }
        var bottom = values[values.count / 20], top = values[values.count * 19 / 20]
        for y in py { bottom = min(bottom, y); top = max(top, y) }
        if top - bottom < 1e-9 { bottom -= 1; top += 1 }
        let margin = (top - bottom) * 0.18
        return (lo...hi, (bottom - margin)...(top + margin))
    }

    // For curves given as g(x, y) = 0: the whole of any closed one (a circle, an ellipse) and
    // every marked point, at the same scale across as up, so a circle looks round. The plot is
    // about two and a half times as wide as it is tall.
    private func framedCurves() -> (ClosedRange<Double>, ClosedRange<Double>) {
        var box = CGRect.null
        for p in graph.points { box = box.union(CGRect(origin: p, size: .zero)) }
        for curve in graph.curves {
            guard case .implicit(let g) = curve.shape else { continue }
            for line in Contour.lines(g, -20...20, -20...20, columns: 80, rows: 80) where line.count > 2 && line.first == line.last {
                for p in line { box = box.union(CGRect(origin: p, size: .zero)) }
            }
        }
        if box.isNull { box = CGRect(x: -5, y: -5, width: 10, height: 10) }
        let pad = max(1, max(box.width, box.height) * 0.15)
        box = box.insetBy(dx: -pad, dy: -pad)
        let aspect = 0.38
        let width = max(Double(box.width), Double(box.height) / aspect), height = width * aspect
        return ((Double(box.midX) - width / 2)...(Double(box.midX) + width / 2),
                (Double(box.midY) - height / 2)...(Double(box.midY) + height / 2))
    }

    private func samples(_ xs: ClosedRange<Double>, _ ys: ClosedRange<Double>) -> [Point] {
        let height = span(ys)
        var points: [Point] = []
        for (c, curve) in graph.curves.enumerated() {
            guard case .function(let f) = curve.shape else { continue }
            var segment = 0
            var previous: Double?
            for i in 0...400 {
                let x = xs.lowerBound + span(xs) * Double(i) / 400
                let y = f(x)
                guard y.isFinite else { previous = nil; segment += 1; continue }
                if let p = previous, abs(y - p) > height * 3 { segment += 1 }
                // Far off the chart only needs to be off the chart.
                let shown = min(max(y, ys.lowerBound - height), ys.upperBound + height)
                points.append(Point(id: "\(c)-\(i)", x: x, y: shown, series: "\(c)-\(segment)", curve: c))
                previous = y
            }
        }
        return points
    }
}

// Traces g(x, y) = 0 across a rectangle by marching squares: g is sampled on a grid, the curve
// crosses each cell edge whose ends differ in sign, at the point found by interpolating, and the
// crossings in a cell are joined. Neighbouring cells share their edges, so the pieces join up
// into whole lines, which keeps a dashed line's dashes even.
enum Contour {
    static func lines(_ g: (Double, Double) -> Double, _ xs: ClosedRange<Double>, _ ys: ClosedRange<Double>,
                      columns: Int = 160, rows: Int = 100) -> [[CGPoint]] {
        let dx = (xs.upperBound - xs.lowerBound) / Double(columns), dy = (ys.upperBound - ys.lowerBound) / Double(rows)
        var v = [[Double]](repeating: [Double](repeating: 0, count: columns + 1), count: rows + 1)
        for j in 0...rows { for i in 0...columns { v[j][i] = g(xs.lowerBound + Double(i) * dx, ys.lowerBound + Double(j) * dy) } }

        // Each crossing is named by its edge: horizontal edges even, vertical odd.
        var at: [Int: CGPoint] = [:]
        var links: [Int: [Int]] = [:]
        func crossing(_ i: Int, _ j: Int, horizontal: Bool) -> Int? {
            let (a, b) = horizontal ? (v[j][i], v[j][i + 1]) : (v[j][i], v[j + 1][i])
            guard a.isFinite, b.isFinite, (a < 0) != (b < 0) else { return nil }
            let id = (j * (columns + 1) + i) * 2 + (horizontal ? 0 : 1)
            if at[id] == nil {
                let f = a / (a - b)
                let x = xs.lowerBound + (Double(i) + (horizontal ? f : 0)) * dx
                let y = ys.lowerBound + (Double(j) + (horizontal ? 0 : f)) * dy
                at[id] = CGPoint(x: x, y: y)
            }
            return id
        }
        func link(_ a: Int, _ b: Int) {
            links[a, default: []].append(b)
            links[b, default: []].append(a)
        }
        for j in 0..<rows {
            for i in 0..<columns {
                let bottom = crossing(i, j, horizontal: true), top = crossing(i, j + 1, horizontal: true)
                let left = crossing(i, j, horizontal: false), right = crossing(i + 1, j, horizontal: false)
                let found = [bottom, right, top, left].compactMap { $0 }
                if found.count == 2 {
                    link(found[0], found[1])
                } else if found.count == 4, let bottom, let right, let top, let left {
                    // A saddle: the value at the middle says which way the two pieces bend.
                    let centre = (v[j][i] + v[j][i + 1] + v[j + 1][i] + v[j + 1][i + 1]) / 4
                    if (centre < 0) == (v[j][i] < 0) { link(bottom, right); link(top, left) } else { link(bottom, left); link(top, right) }
                }
            }
        }

        // Walk the joins: open lines from their ends first, then whatever is left, which is loops.
        var seen: Set<Int> = []
        var out: [[CGPoint]] = []
        let starts = links.keys.filter { links[$0]!.count == 1 } + links.keys.filter { links[$0]!.count != 1 }
        for start in starts where !seen.contains(start) {
            var line: [CGPoint] = []
            var current: Int? = start
            while let c = current, !seen.contains(c) {
                seen.insert(c)
                line.append(at[c]!)
                current = links[c]?.first { !seen.contains($0) }
            }
            if let first = links[start], first.count == 2, let close = at[start], line.count > 2 { line.append(close) }
            if line.count > 1 { out.append(line) }
        }
        return out
    }
}
