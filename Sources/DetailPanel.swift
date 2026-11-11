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
    private var pinches: PinchForwarder?
    var isOpen: Bool { panel != nil }

    // onCovered: the panel is on screen, drawn, over the card, which can now be put away. Until
    // then both are up, so there is never a frame with neither.
    // spotlightBottom is the bottom edge of Spotlight's panel, in screen coordinates, when it is known.
    func show(_ answer: CardText, _ details: Details, from card: NSRect, spotlightBottom: CGFloat?, level: NSWindow.Level,
              onCovered: @escaping () -> Void, onCollapsed: @escaping () -> Void) {
        close(animated: false)
        self.onCollapsed = onCollapsed

        let width = card.width
        let measure = NSHostingView(rootView: DetailContent(answer: answer, d: details, expanded: true).frame(width: width))
        let screen = NSScreen.screens.first { $0.frame.intersects(card) } ?? NSScreen.main
        let room = card.maxY - (screen?.visibleFrame.minY ?? 0) - 24
        // Down to Spotlight's bottom edge, whatever the working: none of Spotlight's list shows from
        // under the panel, and none of the panel hangs below Spotlight; a longer working scrolls
        // within it. Only where Spotlight is hardly taller than its field, which would leave the
        // working a slit, does the panel go on past it, as far as the working or the screen allows.
        // With the card below Spotlight there is nothing under the panel to cover.
        let reach = spotlightBottom.map { card.maxY - $0 } ?? 0
        let fitting = measure.fittingSize.height
        let height = spotlightBottom == nil ? min(fitting, room) : min(max(reach, min(fitting, 360)), room)
        // On Spotlight's bottom edge, the panel lies on Spotlight edge for edge, and its shadow
        // would fall on Spotlight's, darker where they meet and off at the corners.
        let onSpotlight = height == reach
        let target = NSRect(x: card.minX, y: card.maxY - height, width: width, height: height)
        // Lying on Spotlight, the window has room round the glass for the shadow drawn by hand on
        // the part above Spotlight, which Spotlight's own shadow does not reach.
        let margin = onSpotlight ? Chrome.shadowRoom : Chrome.margin

        let panel = NSPanel(contentRect: target.insetBy(dx: -margin, dy: -margin),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = level
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // The system's shadow, with the same fine dark edge as the card's; it is worked out from
        // what the window shows, so it is worked out again every frame while the glass moves.
        // Lying on Spotlight, Spotlight's shadow is the only one.
        panel.hasShadow = !onSpotlight
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let model = DetailModel(cardHeight: card.height)
        // Above Spotlight: the card, and the gap of 8 points between it and Spotlight's top edge.
        let above: CGFloat? = onSpotlight ? card.height + 8 : nil
        let host = FirstMouseHostingView(rootView: ZStack(alignment: .topLeading) {
            if let above { TopShadow(above: above, margin: margin, model: model) }
            ExpandingDetail(answer: answer, d: details, model: model).padding(margin)
        })
        panel.contentView = host

        let tracker = ExitTracker { [weak self] in self?.collapse() }
        tracker.inside = { [weak panel] in
            panel.map { $0.frame.insetBy(dx: margin, dy: margin).contains(NSEvent.mouseLocation) } ?? false
        }
        host.addTrackingArea(NSTrackingArea(rect: host.bounds.insetBy(dx: margin, dy: margin),
                                            options: [.mouseEnteredAndExited, .activeAlways], owner: tracker, userInfo: nil))
        self.tracker = tracker
        self.model = model
        self.panel = panel
        pinches = PinchForwarder(panel)
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
        pinches = nil
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
        pinches = nil
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
    // Glass 64 points high or less is taken for a small control and turns dark over a dark page
    // behind it, light mode or not, where Spotlight's own glass keeps to the system's appearance.
    // A point or two more and the card keeps to it too.
    static let cardHeight: CGFloat = 66
    // Room round the glass for a shadow drawn by hand.
    static let shadowRoom: CGFloat = 40
}

// The shadow of the part of the panel above Spotlight, where the panel lies on Spotlight and the
// system's shadow is off so as not to fall on Spotlight's: drawn round the glass of that part only,
// none of it inside the glass, and fading out at Spotlight's top edge, where Spotlight's own shadow
// carries on. Closed, the glass is the card's, and its shadow goes all round it.
struct TopShadow: View {
    let above: CGFloat       // from the top of the glass to Spotlight's top edge
    let margin: CGFloat
    let model: DetailModel

    var body: some View {
        Canvas { context, size in
            let width = size.width - 2 * margin
            let glass = model.expanded ? above + 2 * Chrome.radius : model.cardHeight
            let shape = Path(roundedRect: CGRect(x: margin, y: margin, width: width, height: glass),
                             cornerRadius: Chrome.radius, style: .continuous)
            var shadow = context
            // As the system draws a window's: a fine dark edge, and a soft fall below and round it.
            shadow.addFilter(.shadow(color: .black.opacity(0.18), radius: 0.8))
            shadow.addFilter(.shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 8))
            shadow.fill(shape, with: .color(.black))
            context.blendMode = .destinationOut
            context.fill(shape, with: .color(.black))
        }
        // Open, it ends at Spotlight's top edge, fading over a few points rather than stopping short.
        .mask {
            GeometryReader { geometry in
                let h = max(geometry.size.height, 1), edge = margin + above
                if model.expanded {
                    LinearGradient(stops: [.init(color: .black, location: 0),
                                           .init(color: .black, location: max(0, (edge - 10) / h)),
                                           .init(color: .clear, location: min(1, (edge + 14) / h))],
                                   startPoint: .top, endPoint: .bottom)
                } else {
                    Color.black
                }
            }
        }
        .allowsHitTesting(false)
    }
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
    let answer: CardText
    let d: Details
    let model: DetailModel

    var body: some View {
        GeometryReader { geometry in
            DetailView(answer: answer, d: d, model: model, fill: geometry.size.height)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                // Open, the glass is thickened, so that Spotlight's list under it does not show through
                // (glass on glass); closed, it is the card's own.
                .background(.background.opacity(model.expanded ? 0.55 : 0))
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
// never the key window: drag, pinch, double-click. Only a pinch zooms: the wheel and two-finger
// scrolling go on to the panel, which scrolls past the graph as it does past everything else.
struct GraphInput: NSViewRepresentable {
    var onDrag: (CGSize) -> Void
    var onDragEnd: () -> Void
    var onZoom: (Double, CGPoint) -> Void   // factor (under 1 zooms in) and where, from the top left
    var onReset: () -> Void

    func makeNSView(context: Context) -> GraphInputView { GraphInputView() }
    func updateNSView(_ view: GraphInputView, context: Context) { view.input = self }
}

final class GraphInputView: NSView {
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

    override func magnify(with event: NSEvent) { pinch(event.magnification, at: event.locationInWindow) }
}

extension GraphInputView: Pinchable {
    func pinch(_ magnification: CGFloat, at windowPoint: NSPoint) {
        input?.onZoom(1 / (1 + Double(magnification)), convert(windowPoint, from: nil))
    }
}

// A view that zooms when pinched. A pinch on the trackpad goes only to the app in front, which while
// the panel is open is Spotlight, not this one; so the panel watches for pinches everywhere and hands
// each one over the panel to the view under the pointer (PinchForwarder). One made over the panel
// while this app is in front reaches the view itself, through magnify(with:).
protocol Pinchable: NSView {
    func pinch(_ magnification: CGFloat, at windowPoint: NSPoint)
}

// While the panel is open: each pinch made with the pointer over it, though sent to Spotlight, zooms
// whatever graph or diagram is under the pointer, as a pinch over Spotlight's own window would. The
// pinches are read from a listening event tap, which only looks: Spotlight still gets each one. (A
// global NSEvent monitor does not see them.) While this app is in front its own windows get them.
final class PinchForwarder {
    private weak var panel: NSPanel?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    init(_ panel: NSPanel) {
        self.panel = panel
        let mask = CGEventMask(1) << 29   // gestures, of which a pinch is one
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<PinchForwarder>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = me.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            } else if let pinch = NSEvent(cgEvent: event), pinch.type == .magnify {
                me.hand(pinch.magnification)
            }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            Log.note("no event tap for pinches: Accessibility is not granted")
            return
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func hand(_ magnification: CGFloat) {
        guard !NSRunningApplication.current.isActive, magnification != 0, let panel, panel.isVisible, let content = panel.contentView else { return }
        let screen = NSEvent.mouseLocation
        guard panel.frame.contains(screen) else { return }
        let point = panel.convertPoint(fromScreen: screen)
        var view = content.hitTest(content.convert(point, from: nil))
        while let v = view, !(v is Pinchable) { view = v.superview }
        guard let target = view as? Pinchable else { return }
        target.pinch(magnification, at: point)
    }

    deinit {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    }
}

// MARK: - Content

// Until the panel has finished opening it is shorter than what is in it only because it is still
// growing, and a scroller would come and go for nothing.
struct DetailView: View {
    let answer: CardText
    let d: Details
    let model: DetailModel
    let fill: CGFloat   // the panel's height, which the working is stretched to where it is shorter

    var body: some View {
        ScrollView { DetailContent(answer: answer, d: d, expanded: model.expanded).frame(minHeight: fill, alignment: .top) }
            .scrollIndicators(model.settled ? .automatic : .hidden)
            .scrollDisabled(!model.settled)
    }
}

// The compact card starts the opening animation. Astronomy expands into a result and its
// supporting data. The standard working keeps the card above its steps, solutions and graph.
struct DetailContent: View {
    let answer: CardText
    let d: Details
    var expanded = true
    @State private var shown = DetailContent.still
    // Set by the preview tool, which draws the panel once into a picture: everything in place
    // from the start, with nothing left to rise in.
    static var still = false
    // The page of Astronomy's working it opens on, for the preview tool to draw each; the first otherwise.
    static var astronomyPage = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardFace(answer: answer, showInput: !expanded)
            if answer.isAstronomy {
                if expanded { AstronomyWorkingView(answer: answer, details: d, shown: shown) }
            } else {
                standardWorking
            }

            Spacer(minLength: 14)
            HStack {
                Spacer()
                SettingsButton()
            }
            .opacity(shown ? 1 : 0)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .onAppear { shown = true }
    }

    private var standardWorking: some View {
        let working = d.presentation
        return VStack(alignment: .leading, spacing: 14) {
            section("Working", index: 0) {
                CopyRow(copy: LineCopy(d.equation)) {
                    labelled("Input") {
                        MathText(math: d.equation, size: 19)
                        ForEach(answer.notes, id: \.self) { note in
                            Text(note).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                // Each step numbered, so that one can be pointed to: 1. Factorising.
                ForEach(Array(working.steps.enumerated()), id: \.offset) { i, step in
                    CopyRow(copy: step.math.map { LineCopy($0) }) {
                        labelled("\(i + 1). \(step.label)") {
                            if let math = step.math { MathText(math: math, size: 19) }
                            if let note = step.note {
                                Text(subscripted(note, size: 13)).font(.system(size: 13)).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }

            section(working.solutionTitle, index: 1) {
                // A periodic function's dozen go in columns, so the graph stays in view.
                if d.solutions.count > 3, d.whole == nil {
                    // Wide enough for the longest, an angle with its degrees after it.
                    let widest = CGFloat(d.solutions.map(\.plain.count).max() ?? 0) * 11.5
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: max(180, widest)), alignment: .leading)], alignment: .leading, spacing: 0) {
                        ForEach(Array(d.solutions.enumerated()), id: \.offset) { _, solution in
                            CopyRow(copy: LineCopy(solution)) { MathText(math: solution, size: 20) }
                        }
                    }
                } else {
                    // The answer is what the panel is for: larger than the working above it.
                    // One value over several lines is set smaller, so that its lines are all of a
                    // size, and each of them copies the whole.
                    ForEach(Array(d.solutions.enumerated()), id: \.offset) { _, solution in
                        // The answer larger than the working, unless it is a long one, which at that size
                        // would be a term to a line: then the size of the working.
                        let long = Typesetter.box(solution, 26).width > 900
                        let size: CGFloat = d.whole != nil ? 15 : long ? 19 : 26
                        CopyRow(copy: LineCopy(solution, whole: d.whole)) {
                            MathText(math: solution, size: size)
                        }
                    }
                }
                if let note = working.solutionNote {
                    Text(subscripted(note, size: 13)).font(.system(size: 13)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.top, 2)
                }
                if let note = d.note {
                    Text(note).font(.system(size: 13)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.top, 2)
                }
            }

            if let table = d.truthTable {
                section("Truth table", index: 2) {
                    TruthTableView(table: table, probe: d.probe)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quaternary.opacity(0.5)))
                }
            }
            if let circuit = d.circuit {
                section("Circuit", index: 3) {
                    CircuitDiagram(layout: circuit, probe: d.probe)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quaternary.opacity(0.5)))
                }
            }
            if let chromaticity = d.chromaticity {
                section("CIE 1931 chromaticity", index: 2) {
                    ChromaticityDiagram(diagram: chromaticity)
                }
            }
            if let graph = d.graph {
                section("Graph", index: 3) {
                    Plot(graph: graph)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quaternary.opacity(0.5)))
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private func section<Content: View>(_ title: String, index: Int, @ViewBuilder content: () -> Content) -> some View {
        WorkingSection(title: title, index: index, shown: shown, content: content)
    }

    private func labelled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        Labelled(label, content: content)
    }
}

// A titled section of the working, its rows straight on the glass as Spotlight's results are; each
// one rises a moment after the one above it. Every kind of working is laid out in these.
private struct WorkingSection<Content: View>: View {
    var title: String?
    var index = 0
    let shown: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 16)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 12)
        .animation(.spring(response: 0.45, dampingFraction: 0.86).delay(0.06 + 0.05 * Double(index)), value: shown)
    }
}

// A line of the working under its small grey name: "2. Splitting the middle term", "Best period".
private struct Labelled<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(subscripted(label, size: 12)).font(.system(size: 12)).foregroundStyle(.secondary)
            content
        }
    }
}

// The card's grey choice of pages, as Spotlight's own pills: the page shown filled in, the others
// plain; grey, as what the pointer chooses is, where what the keyboard chooses is blue. Clicked in
// AppKit, as the panel is never key.
//
// The rule for pages: a working whose parts are different kinds of thing to look at (a result, a
// picture, how it was worked out, where its data come from) has pages, as Astronomy's does; a working
// that reads as one argument from the top down (an equation: its steps, its solutions, its graph) is one
// page.
private struct PageBar<Page: Hashable>: View {
    struct Item: Identifiable {
        let page: Page
        let title: String
        var id: String { title }
    }
    let items: [Item]
    @Binding var selection: Page

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let on = item.page == selection
                Text(item.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(on ? .primary : .secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background { Capsule().fill(.quaternary).opacity(on ? 1 : 0) }
                    .contentShape(Capsule())
                    .overlay(ClickTarget { selection = item.page })
                    .accessibilityElement()
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(Capsule().fill(.quaternary.opacity(0.45)))
    }
}

// Astronomy's working, in the same sections and lines as every other: under the card, its pages, so
// that a result with a picture, many values and a long method is never one crowded column. The result
// first, with what was typed above it; then its picture, if it has one; then how it was worked out;
// then the model and where its data come from.
private struct AstronomyWorkingView: View {
    let answer: CardText
    let details: Details
    let shown: Bool
    @State private var page: Page?

    enum Page: Hashable { case result, picture, working, source }

    private var working: AstronomyWorking? { details.astronomyWorking }
    private var results: [AstronomyWorking.Row] { working?.results ?? [] }
    private var picture: AstroDiagram? { details.diagram.flatMap { $0.hasVisual ? $0 : nil } }

    private var pages: [PageBar<Page>.Item] {
        var pages = [PageBar<Page>.Item(page: .result, title: "Result")]
        if let picture { pages.append(.init(page: .picture, title: picture.title)) }
        if working != nil || !details.steps.isEmpty { pages.append(.init(page: .working, title: "Working")) }
        if working != nil || details.note != nil { pages.append(.init(page: .source, title: "Source")) }
        return pages
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let page = self.page ?? pages[min(DetailContent.astronomyPage, pages.count - 1)].page
            if pages.count > 1 {
                PageBar(items: pages, selection: Binding(get: { page }, set: { self.page = $0 }))
                    .padding(.leading, 12)
                    .opacity(shown ? 1 : 0)
                    .animation(.easeOut(duration: 0.2).delay(0.04), value: shown)
            }
            VStack(alignment: .leading, spacing: 14) {
                switch page {
                case .result: resultPage
                case .picture: picturePage
                case .working: workingPage
                case .source: sourcePage
                }
            }
            .id(page)
            .transition(.opacity)
        }
        .animation(.easeOut(duration: 0.15), value: page)
        .padding(.horizontal, 12)
    }

    // MARK: Pages

    @ViewBuilder private var resultPage: some View {
        let typed = details.equation.plain
        let shownQuery = typed.count > 280 ? String(typed.prefix(280)) + "…" : typed
        WorkingSection(index: 0, shown: shown) {
            CopyRow(copy: LineCopy(details.equation, whole: typed)) {
                Labelled("Input") {
                    MathText(math: AstronomyWorkingText.call(shownQuery), size: 19)
                }
            }
            if results.isEmpty {
                CopyRow(copy: LineCopy(.text(answer.solution.exact), whole: answer.solution.exact)) {
                    Text(AstronomyWorkingText.shown(answer.solution.exact)).font(.system(size: 26)).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                // The answer larger than the rest where it is one value, as Solutions has it.
                rows(results, size: results.count == 1 ? 26 : 19)
            }
        }
    }

    @ViewBuilder private var picturePage: some View {
        if let picture {
            WorkingSection(index: 0, shown: shown) {
                AstroDiagramView(diagram: picture)
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quaternary.opacity(0.5)))
            }
        }
    }

    @ViewBuilder private var workingPage: some View {
        if let working {
            if !working.inputs.isEmpty {
                WorkingSection(title: "Inputs", index: 0, shown: shown) { rows(working.inputs, size: 17) }
            }
            WorkingSection(title: "Method", index: 1, shown: shown) {
                CopyRow(copy: LineCopy(.text(working.formula), whole: working.formula)) {
                    // Typeset where it can be read, t₀ = ∫₀∞ dz/[(1+z)H(z)] with the integral's limits above
                    // and below its sign; a formula that is all words stays as the text it is.
                    Labelled("Formula") {
                        if let math = AstronomyFormula.math(working.formula) {
                            MathText(math: math, size: 19)
                        } else {
                            Text(subscripted(working.formula, size: 19)).font(.system(size: 19)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                substitution(working)
                rows(working.intermediates, size: 17)
            }
            if !working.constants.isEmpty {
                WorkingSection(title: "Constants", index: 2, shown: shown) { rows(working.constants, size: 17) }
            }
        } else if !details.steps.isEmpty {
            WorkingSection(title: "Method", index: 0, shown: shown) {
                ForEach(Array(details.steps.enumerated()), id: \.offset) { i, step in
                    CopyRow(copy: step.math.map { LineCopy($0) }) {
                        Labelled("\(i + 1). \(step.label)") {
                            if case .text(let text)? = step.math {
                                Text(verbatim: text).font(.system(size: 17))
                            } else if let math = step.math {
                                MathText(math: math, size: 19)
                            }
                            if let note = step.note {
                                Text(verbatim: note).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var sourcePage: some View {
        if let working {
            WorkingSection(title: "Model", index: 0, shown: shown) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: AstronomyWorkingText.sentence(working.model)).font(.system(size: 15)).fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(working.notes.enumerated()), id: \.offset) { _, note in
                        Text(verbatim: AstronomyWorkingText.sentence(note)).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            if let url = URL(string: working.source), let host = url.host {
                WorkingSection(title: "Source", index: 1, shown: shown) {
                    Link(host, destination: url)
                        .font(.system(size: 15))
                        .overlay(ClickTarget { NSWorkspace.shared.open(url) })
                        .help(working.source)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
            }
        }
        // The engine's note is mostly the model's own, already given above.
        if let note = details.note, !(working?.notes.contains(note) ?? false) {
            WorkingSection(title: "Notes", index: 2, shown: shown) {
                Text(verbatim: note).font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
    }

    // The numbers the formula was worked with: each value looked up, under what it is, with the letter
    // it stands for where the formula has been worked through; then the formula with them in.
    @ViewBuilder private func substitution(_ working: AstronomyWorking) -> some View {
        let worked = AstronomySubstitution.work(working)
        let shown: [(symbol: String?, used: AstronomyWorking.Used)] = worked.map { $0.assigned.map { (Optional($0.symbol), $0.used) } }
            ?? working.values.map { (nil, $0) }
        ForEach(Array(shown.enumerated()), id: \.offset) { _, entry in
            let number = AstronomySubstitution.written(entry.used.value, figures: 6) + (entry.used.unit.isEmpty ? "" : " " + entry.used.unit)
            let line = (entry.symbol.map { $0 + " = " } ?? "") + number
            CopyRow(copy: LineCopy(.text(line), whole: line)) {
                Labelled(AstronomyWorkingText.label(entry.used.label)) {
                    if let symbol = entry.symbol, let math = AstronomyFormula.math(symbol) {
                        MathText(math: .row([math, .text(" = " + number)]), size: 17)
                    } else {
                        Text(subscripted(line, size: 17)).font(.system(size: 17)).monospacedDigit()
                    }
                }
            }
        }
        if let worked {
            CopyRow(copy: LineCopy(worked.line)) {
                Labelled("Substituting the values") {
                    MathText(math: worked.line, size: 19)
                }
            }
        }
    }

    // MARK: Lines

    // Each value a line of its own under its name, copying the value as the engine gave it.
    private func rows(_ rows: [AstronomyWorking.Row], size: CGFloat) -> some View {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            CopyRow(copy: LineCopy(.text(row.value), whole: row.value)) {
                Labelled(AstronomyWorkingText.name(row.name)) {
                    Text(AstronomyWorkingText.shown(row.value)).font(.system(size: size)).monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = row.detail, !detail.isEmpty {
                        Text(AstronomyWorkingText.shown(detail)).font(.system(size: 13)).foregroundStyle(.secondary).monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

// What a line of the panel copies: its LaTeX, or the line as it is shown. One value over several
// lines (a digest) has no LaTeX, and each of its lines copies the whole.
struct LineCopy {
    var latex: String?
    var text: String

    init(_ math: Math, whole: String? = nil) {
        latex = whole == nil ? math.latex : nil
        text = whole ?? math.plain
    }
}

// A line of the panel. Maths can't be selected like text, so the line copies itself: it is lit
// while the pointer is on it, as Spotlight lights its rows, with the copy sign at its end; a click
// copies it as chosen on the Clipboard page, and its menu offers either. A line with nothing to
// copy (a step that is only a sentence) is neither lit nor clicked.
private struct CopyRow<Content: View>: View {
    let copy: LineCopy?
    var horizontalPadding: CGFloat = 16
    var verticalPadding: CGFloat = 10
    var showsCopyIcon = false
    @ViewBuilder let content: Content
    @State private var hovering = false
    @State private var copied = false
    @State private var generation = 0

    var body: some View {
        HStack(spacing: 8) {
            content.frame(maxWidth: .infinity, alignment: .leading)
            if copy != nil {
                HStack(spacing: 5) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .medium))
                        .contentTransition(.symbolEffect(.replace))
                    if copied { Text("Copied").font(.system(size: 12, weight: .medium)) }
                }
                .foregroundStyle(.secondary)
                .frame(minWidth: showsCopyIcon ? 42 : nil)
                .opacity(showsCopyIcon || hovering || copied ? 1 : 0)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)   // concentric with the panel's corners
                .fill(.quaternary)
                .opacity(hovering && copy != nil ? 1 : 0)
        }
        .overlay {
            if let copy { RowTarget(copy: copy, hovering: $hovering, copied: didCopy) }
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.15), value: copied)
    }

    private func didCopy() {
        copied = true
        generation += 1
        let mine = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { if generation == mine { copied = false } }
    }
}

// The row's pointer and clicks, taken in AppKit: the panel is never key, where SwiftUI would not
// see them.
private struct RowTarget: NSViewRepresentable {
    let copy: LineCopy
    @Binding var hovering: Bool
    let copied: () -> Void

    func makeNSView(context: Context) -> RowTargetView { RowTargetView() }
    func updateNSView(_ view: RowTargetView, context: Context) {
        view.copy = copy
        view.onHover = { hovering = $0 }
        view.copied = copied
    }
}

final class RowTargetView: NSView {
    var copy: LineCopy?
    var onHover: (Bool) -> Void = { _ in }
    var copied: () -> Void = {}
    private(set) var inside = false
    private var watching: NSObjectProtocol?
    // Where the pointer is on the screen: the real one, or a test's.
    nonisolated(unsafe) static var pointer: () -> NSPoint = { NSEvent.mouseLocation }

    // The pointer's own place decides, not only its crossing the row's edge, which AppKit tells only
    // when the pointer moves: the working scrolled under a pointer held still takes the shade off every
    // row it is not on, and puts it on the one it is.
    private func hover(_ now: Bool) {
        guard now != inside else { return }
        inside = now
        onHover(now)
    }

    // On it: inside the row's own box, and where the scroll view shows it. (visibleRect is no help here:
    // inside SwiftUI's scroll view it is the whole of what is shown, row or not.)
    func look() {
        guard let window, !isHiddenOrHasHiddenAncestor else { return hover(false) }
        let screen = RowTargetView.pointer()
        let inWindow = window.convertPoint(fromScreen: screen)
        let shown = enclosingScrollView.map { $0.contentView.bounds.contains($0.contentView.convert(inWindow, from: nil)) } ?? true
        hover(window.frame.contains(screen) && shown && bounds.contains(convert(inWindow, from: nil)))
    }

    // The working's scroll view tells when its content has moved, by the wheel, the trackpad or its
    // momentum, after it has: each row looks again then.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let watching { NotificationCenter.default.removeObserver(watching) }
        watching = nil
        guard window != nil else { return hover(false) }
        guard let clip = enclosingScrollView?.contentView else { return }
        clip.postsBoundsChangedNotifications = true
        watching = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.look() }
        }
    }

    deinit { if let watching { NotificationCenter.default.removeObserver(watching) } }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { put(asLatex: Prefs.copyLatex) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let copy else { return nil }
        let menu = NSMenu()
        if copy.latex != nil { menu.addItem(withTitle: "Copy LaTeX", action: #selector(copyLatex), keyEquivalent: "").target = self }
        menu.addItem(withTitle: copy.latex == nil ? "Copy" : "Copy as Text", action: #selector(copyText), keyEquivalent: "").target = self
        return menu
    }

    @objc private func copyLatex() { put(asLatex: true) }
    @objc private func copyText() { put(asLatex: false) }

    private func put(asLatex: Bool) {
        guard let copy else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString((asLatex ? copy.latex : nil) ?? copy.text, forType: .string)
        copied()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // The row's own box, and not .inVisibleRect, which here would be all that is shown.
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { look() }
    override func mouseMoved(with event: NSEvent) { look() }
    override func mouseExited(with event: NSEvent) { look() }
}

// Each curve or line in the graph, the first solid, the next dashed, then dotted, crossing at the
// marked points, which are labelled with where they are, over the two axes. As in Desmos: drag
// to move about, pinch to zoom, double-click to go back; scrolling scrolls the panel. Monochrome, in the label
// colour, so it sits in the glass like the text does. Where a curve jumps (tan x, 1/x) its line
// is broken rather than drawn up the asymptote.
struct Plot: View {
    let graph: Graph

    // Dashes long and dark enough not to be taken for the grid, which is solid and faint.
    private static let styles: [(opacity: Double, dash: [CGFloat])] = [(0.85, []), (0.7, [7, 4]), (0.7, [1.5, 4]), (0.7, [9, 3, 2, 3])]
    private func style(_ i: Int) -> (opacity: Double, dash: [CGFloat]) { Plot.styles[i % Plot.styles.count] }

    @State private var view: (x: ClosedRange<Double>, y: ClosedRange<Double>)?
    @State private var gestureStart: (x: ClosedRange<Double>, y: ClosedRange<Double>)?
    // The plot's height over its width, as drawn, so that a unit across and a unit up are the same.
    @State private var aspect: Double = 0.5

    var body: some View {
        let (xs, ys) = view ?? initial()
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                RuleMark(y: .value("x axis", 0)).foregroundStyle(Color.primary.opacity(0.35)).lineStyle(StrokeStyle(lineWidth: 1))
                RuleMark(x: .value("y axis", 0)).foregroundStyle(Color.primary.opacity(0.35)).lineStyle(StrokeStyle(lineWidth: 1))
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
            .axisTitles(graph.titles)
            .chartPlotStyle { $0.clipped() }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    let plot = proxy.plotFrame.map { geometry[$0] } ?? geometry.frame(in: .local)
                    // Every curve drawn here, each as whole paths in screen points, so that a dash is the
                    // same length at any zoom and runs on unbroken along the curve; and drawn from the same
                    // view as the axes at every frame, so that they never part, moving or still.
                    Canvas { context, _ in
                        context.clip(to: Path(plot))
                        for (i, curve) in graph.curves.enumerated() {
                            let (paths, phase) = paths(curve.shape, plot, xs, ys)
                            for path in paths {
                                context.stroke(path, with: .color(Color.primary.opacity(style(i).opacity)),
                                               style: StrokeStyle(lineWidth: 2, lineCap: .butt, lineJoin: .round, dash: style(i).dash, dashPhase: phase))
                            }
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
                            // From the latest view: pinch events can come faster than redraws.
                            let (cx, cy) = view ?? (xs, ys)
                            let x = cx.lowerBound + (point.x - plot.minX) / plot.width * span(cx)
                            let y = cy.upperBound - (point.y - plot.minY) / plot.height * span(cy)
                            view = (scale(cx, factor, about: x, x: true), scale(cy, factor, about: y, x: false))
                        },
                        onReset: { glide(to: nil) })
                    // Buttons to zoom about the middle, and to go back to the first view.
                    ZoomControls(zoomIn: { zoom(0.6) }, zoomOut: { zoom(1 / 0.6) }, reset: { glide(to: nil) })
                        .position(ZoomControls.place(in: plot))
                    Color.clear
                        .onAppear { if plot.width > 0 { aspect = Double(plot.height / plot.width) } }
                        .onChange(of: plot.size) { _, size in if size.width > 0 { aspect = Double(size.height / size.width) } }
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 320)

            HStack(spacing: 16) {
                ForEach(Array(graph.curves.enumerated()), id: \.offset) { i, curve in legend(i, curve.label) }
                Spacer()
                ZoomControls.Hint()
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
                case .implicit, .samples:
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

    // About the middle of what is in view, both ways alike, so the scale across and up is kept.
    private func zoom(_ factor: Double) {
        let (xs, ys) = view ?? initial()
        glide(to: (scale(xs, factor, about: (xs.lowerBound + xs.upperBound) / 2, x: true),
                   scale(ys, factor, about: (ys.lowerBound + ys.upperBound) / 2, x: false)))
    }

    // To another view, or back to the first (nil), over a third of a second, the view itself moved at
    // each frame: everything (axes, curves, points) is drawn from it, so all move together. SwiftUI's own
    // animation would tween the axes and the points while the curves jumped.
    @State private var glides = 0
    private func glide(to target: (x: ClosedRange<Double>, y: ClosedRange<Double>)?) {
        let from = view ?? initial(), to = target ?? initial()
        glides += 1
        let mine = glides, start = Date(), duration = 0.3
        func mix(_ a: ClosedRange<Double>, _ b: ClosedRange<Double>, _ e: Double) -> ClosedRange<Double> {
            (a.lowerBound + (b.lowerBound - a.lowerBound) * e)...(a.upperBound + (b.upperBound - a.upperBound) * e)
        }
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { timer in
            guard mine == glides else { return timer.invalidate() }
            let t = min(1, Date().timeIntervalSince(start) / duration), e = 1 - pow(1 - t, 3)
            if t >= 1 { timer.invalidate(); view = target; return }
            view = (mix(from.x, to.x, e), mix(from.y, to.y, e))
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    // A curve as paths on the plot, in screen points, with where its dash begins. A function is sampled
    // across the width at every point and a half, broken where it jumps or is undefined; its dash is
    // measured from x = 0 along the curve, so that moving the graph moves the dashes with it rather than
    // along it. Points given are joined in order, the dash from the first. A vertical line spans the plot.
    private func paths(_ shape: Graph.Curve.Shape, _ plot: CGRect, _ xs: ClosedRange<Double>, _ ys: ClosedRange<Double>) -> ([Path], CGFloat) {
        func at(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: plot.minX + (x - xs.lowerBound) / span(xs) * plot.width, y: plot.minY + (ys.upperBound - y) / span(ys) * plot.height)
        }
        let height = span(ys)
        switch shape {
        case .function(let f):
            let n = max(200, Int(plot.width * 1.5))
            var paths: [Path] = [], path = Path(), previous: (Double, CGPoint)?
            for i in 0...n {
                let x = xs.lowerBound + span(xs) * Double(i) / Double(n), y = f(x)
                guard y.isFinite else { if !path.isEmpty { paths.append(path) }; path = Path(); previous = nil; continue }
                // Far off the plot only needs to be off it.
                let p = at(x, min(max(y, ys.lowerBound - height), ys.upperBound + height))
                if let (py, _) = previous, abs(y - py) > height * 3 { paths.append(path); path = Path(); previous = nil }
                if previous == nil { path.move(to: p) } else { path.addLine(to: p) }
                previous = (y, p)
            }
            if !path.isEmpty { paths.append(path) }
            // From x = 0 to where the drawing begins, along the curve on the screen.
            var phase: CGFloat = 0, last: CGPoint?
            let steps = 300
            for k in 0...steps {
                let x = xs.lowerBound * Double(k) / Double(steps)
                let y = f(x)
                guard y.isFinite else { last = nil; continue }
                let p = at(x, min(max(y, ys.lowerBound - height), ys.upperBound + height))
                if let last { phase += hypot(p.x - last.x, p.y - last.y) }
                last = p
            }
            return (paths, xs.lowerBound >= 0 ? phase : -phase)
        case .samples(let given):
            var paths: [Path] = [], path = Path()
            for p in given {
                guard p.x.isFinite, p.y.isFinite else { if !path.isEmpty { paths.append(path) }; path = Path(); continue }
                let q = at(Double(p.x), Double(p.y))
                if path.isEmpty { path.move(to: q) } else { path.addLine(to: q) }
            }
            if !path.isEmpty { paths.append(path) }
            return (paths, 0)
        case .vertical(let x):
            var path = Path()
            path.move(to: CGPoint(x: at(x, 0).x, y: plot.minY)); path.addLine(to: CGPoint(x: at(x, 0).x, y: plot.maxY))
            return ([path], at(0, ys.upperBound).y - at(0, 0).y)
        case .implicit(let g):
            var path = Path()
            for line in Contour.lines(g, xs, ys) { path.addLines(line.map { at($0.x, $0.y) }) }
            return ([path], 0)
        }
    }

    private func span(_ r: ClosedRange<Double>) -> Double { r.upperBound - r.lowerBound }
    private func shift(_ r: ClosedRange<Double>, _ by: Double) -> ClosedRange<Double> { (r.lowerBound + by)...(r.upperBound + by) }
    // In as far as a millionth of the first view, and out as far as a million times it, on each axis:
    // a strain of 10⁻²¹ zooms as far as a parabola does.
    private func scale(_ r: ClosedRange<Double>, _ k: Double, about c: Double, x: Bool) -> ClosedRange<Double> {
        let lower = c - (c - r.lowerBound) * k, upper = c + (r.upperBound - c) * k
        let first = initial(), base = span(x ? first.0 : first.1)
        guard upper - lower > base * 1e-6, upper - lower < base * 1e6, lower.isFinite, upper.isFinite else { return r }
        return lower...upper
    }

    private var sampled: [CGPoint] {
        graph.curves.flatMap { curve -> [CGPoint] in
            if case .samples(let points) = curve.shape { return points }
            return []
        }.filter { $0.x.isFinite && $0.y.isFinite }
    }

    // Every point in view with a little room round it; for an orbit, the same scale both ways.
    private func framedSamples() -> (ClosedRange<Double>, ClosedRange<Double>) {
        let all = sampled + graph.points
        var lowX = Double(all.map(\.x).min() ?? 0), highX = Double(all.map(\.x).max() ?? 1)
        var lowY = Double(all.map(\.y).min() ?? 0), highY = Double(all.map(\.y).max() ?? 1)
        func widen(_ low: inout Double, _ high: inout Double) {
            let pad = (high - low) * 0.06
            if pad > 0 { low -= pad; high += pad } else { let d = max(abs(low) * 0.05, 1e-300); low -= d; high += d }
        }
        widen(&lowX, &highX); widen(&lowY, &highY)
        guard graph.equalScale else { return (lowX...highX, lowY...highY) }
        let width = max(highX - lowX, (highY - lowY) / aspect), height = width * aspect
        let mx = (lowX + highX) / 2, my = (lowY + highY) / 2
        return ((mx - width / 2)...(mx + width / 2), (my - height / 2)...(my + height / 2))
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
        if let frame = graph.frame { return frame }
        if graph.curves.contains(where: { if case .implicit = $0.shape { true } else { false } }) { return framedCurves() }
        if !sampled.isEmpty { return framedSamples() }
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
        bottom -= margin
        top += margin
        // The same scale across as up, as in Desmos, so that a slope of 1 is at 45° and a circle is
        // round: made wider for it where the curves need not much more height than that, and
        // left to fit them where they would need far more, as y = 100x does.
        let needed = top - bottom, equal = (hi - lo) * aspect, middle = (bottom + top) / 2
        if needed <= equal { return (lo...hi, (middle - equal / 2)...(middle + equal / 2)) }
        if needed <= equal * 2.5 {
            let width = needed / aspect, centre = (lo + hi) / 2
            return ((centre - width / 2)...(centre + width / 2), bottom...top)
        }
        return (lo...hi, bottom...top)
    }

    // For curves given as g(x, y) = 0: the whole of any closed one (a circle, an ellipse) and
    // every marked point, at the same scale across as up, so a circle looks round.
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
        let width = max(Double(box.width), Double(box.height) / aspect), height = width * aspect
        return ((Double(box.midX) - width / 2)...(Double(box.midX) + width / 2),
                (Double(box.midY) - height / 2)...(Double(box.midY) + height / 2))
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

extension View {
    // A chart's axis titles, where it has them; none, and no room kept for them, where it has not.
    @ViewBuilder func axisTitles(_ titles: (x: String, y: String)?) -> some View {
        if let titles { chartXAxisLabel(titles.x).chartYAxisLabel(titles.y) } else { self }
    }
}

// A drawing that zooms as the graph does: pinched about the pointer or zoomed with + and −, dragged to
// move about, double-clicked back to the whole. It is drawn again at the larger size rather than
// enlarged as a picture, so its lines stay sharp and its labels the size they are; it fills its box,
// and never shows less than the whole of it.
struct ZoomableDiagram<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero     // the drawing's top left from the box's: zero or less
    @State private var dragStart: CGSize?

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                content
                    .frame(width: size.width * zoom, height: size.height * zoom)
                    .offset(offset)
                    .allowsHitTesting(false)
                GraphInput(onDrag: { translation in
                               let start = dragStart ?? offset
                               dragStart = start
                               offset = kept(CGSize(width: start.width + translation.width, height: start.height + translation.height), size, zoom)
                           },
                           onDragEnd: { dragStart = nil },
                           onZoom: { factor, point in zoom(by: 1 / factor, about: point, size) },
                           onReset: { withAnimation(.smooth(duration: 0.3)) { zoom = 1; offset = .zero } })
                ZoomControls(zoomIn: { withAnimation(.smooth(duration: 0.2)) { zoom(by: 1 / 0.6, about: CGPoint(x: size.width / 2, y: size.height / 2), size) } },
                             zoomOut: { withAnimation(.smooth(duration: 0.2)) { zoom(by: 0.6, about: CGPoint(x: size.width / 2, y: size.height / 2), size) } },
                             reset: { withAnimation(.smooth(duration: 0.3)) { zoom = 1; offset = .zero } })
                    .position(ZoomControls.place(in: CGRect(origin: .zero, size: size)))
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
        }
        .safeAreaInset(edge: .bottom, spacing: 8) { HStack { Spacer(); ZoomControls.Hint() } }
    }

    // From the whole to eight times it, about the point given, which stays where it is.
    private func zoom(by k: CGFloat, about point: CGPoint, _ size: CGSize) {
        let next = min(max(zoom * k, 1), 8), actual = next / zoom
        let moved = CGSize(width: point.x - (point.x - offset.width) * actual, height: point.y - (point.y - offset.height) * actual)
        zoom = next
        offset = kept(moved, size, next)
    }

    // The drawing kept over the whole box: never dragged so far that an edge of it comes inside.
    private func kept(_ o: CGSize, _ size: CGSize, _ zoom: CGFloat) -> CGSize {
        CGSize(width: min(0, max(o.width, size.width - size.width * zoom)), height: min(0, max(o.height, size.height - size.height * zoom)))
    }

}

// The zoom buttons every graph and drawing has, alike and in the same place on each, at the top right
// of what is drawn: in, out, and back to the first view; and the one line, under it, saying how to move
// about. The graph, the colour diagram and Astronomy's drawings all use these, so that each is worked
// the same way.
struct ZoomControls: View {
    let zoomIn: () -> Void
    let zoomOut: () -> Void
    let reset: () -> Void

    static let hint = "Drag to move · Pinch or + and − to zoom · Double-click to go back"
    // Where the buttons' middle goes within what is drawn.
    static func place(in rect: CGRect) -> CGPoint { CGPoint(x: rect.maxX - 20, y: rect.minY + 50) }

    var body: some View {
        VStack(spacing: 0) {
            button("plus", "Zoom in", zoomIn)
            Divider().frame(width: 22)
            button("minus", "Zoom out", zoomOut)
            Divider().frame(width: 22)
            button("arrow.counterclockwise", "Back to the first view", reset)
        }
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
    }

    private func button(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).frame(width: 28, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }

    // The line saying how, with whatever else a drawing can do before it: Click a colour for its xyY · Drag to move ….
    struct Hint: View {
        var before: [String] = []
        var body: some View {
            Text((before + [ZoomControls.hint]).joined(separator: " · "))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
