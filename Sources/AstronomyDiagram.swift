import SwiftUI

// The pictures of Astronomy mode, drawn in the working under the answer: an orbit from above, a star
// on the Hertzsprung–Russell diagram, a black hole to scale, and a spectrum with its lines shifted.
// What each shows is decided in Astronomy.swift (AstroDiagram); this only draws it.
struct AstroDiagramView: View {
    let diagram: AstroDiagram

    var body: some View {
        switch diagram {
        case .orbit(let orbit): OrbitView(orbit: orbit).frame(height: 320)
        case .hr(let hr): HRView(hr: hr).frame(height: 360)
        case .blackHole(let hole): BlackHoleView(hole: hole).frame(height: 300)
        case .spectrum(let spectrum): SpectrumView(spectrum: spectrum).frame(height: 230)
        case .scientific(let picture): AstronomyScientificView(picture: picture)
        }
    }
}

// Text drawn into a canvas, small and grey unless asked otherwise.
private func label(_ ctx: GraphicsContext, _ s: String, at p: CGPoint, anchor: UnitPoint = .leading, size: CGFloat = 11,
                   weight: Font.Weight = .regular, colour: Color = .secondary) {
    ctx.draw(Text(subscripted(s, size: size)).font(.system(size: size, weight: weight)).foregroundColor(colour), at: p, anchor: anchor)
}

private func circle(_ c: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)) }

private func quantity(_ x: Double, _ unit: String, _ dimension: Dimension) -> String {
    if let (v, u) = Format.alternative(x, dimension) { return "\(Format.number(v)) \(u)" }
    return "\(Format.number(x)) \(unit)"
}

// MARK: - Orbit

// From above, the orbit circular and to scale with its neighbours'; what is circled and the body
// on the orbit are marks, far larger than they would be. The body moves anticlockwise.
private struct OrbitView: View {
    let orbit: OrbitPicture

    var body: some View {
        Canvas { ctx, size in
            let centre = CGPoint(x: size.width * 0.56, y: size.height / 2)
            let widest = ([orbit.a] + orbit.others.map(\.a)).max() ?? orbit.a
            let scale = (min(size.height / 2 - 26, size.width * 0.42)) / widest
            let faint = Color.primary.opacity(0.28)

            // The neighbours' orbits, dashed, each named where it crosses the top left.
            for (i, ring) in orbit.others.sorted(by: { $0.a < $1.a }).enumerated() {
                let r = ring.a * scale
                ctx.stroke(circle(centre, r), with: .color(faint), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                let angle = Double.pi * (0.62 + 0.07 * Double(i % 3))
                label(ctx, ring.name, at: CGPoint(x: centre.x + r * cos(angle), y: centre.y - r * sin(angle) - 7), anchor: .center, size: 10)
            }

            // The orbit itself, and what it is round.
            let r = orbit.a * scale
            ctx.stroke(circle(centre, r), with: .color(.primary.opacity(0.8)), lineWidth: 1.6)
            let star = orbit.primaryIsStar
            if star {
                ctx.fill(circle(centre, 16), with: .color(Color(red: 1, green: 0.78, blue: 0.3).opacity(0.25)))
            }
            ctx.fill(circle(centre, star ? 9 : 7), with: .color(star ? Color(red: 1, green: 0.72, blue: 0.2) : Color(red: 0.3, green: 0.55, blue: 0.95)))
            label(ctx, orbit.primary, at: CGPoint(x: centre.x, y: centre.y + 22), anchor: .center, size: 11, weight: .medium, colour: .primary)

            // The body, a little above the right, with its radius and its velocity, a tangent anticlockwise.
            let phi = Double.pi * 0.2
            let body = CGPoint(x: centre.x + r * cos(phi), y: centre.y - r * sin(phi))
            var radius = Path()
            radius.move(to: centre)
            radius.addLine(to: body)
            ctx.stroke(radius, with: .color(.primary.opacity(0.55)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            label(ctx, "a = \(quantity(orbit.a, "m", .length))",
                  at: CGPoint(x: (centre.x + body.x) / 2 + 6, y: (centre.y + body.y) / 2 + 10), anchor: .topLeading, size: 11)

            if let hill = orbit.hill {
                let drawn = max(hill * scale, 10)
                ctx.stroke(circle(body, drawn), with: .color(.accentColor.opacity(0.8)), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
                let enlarged = drawn > hill * scale * 1.05
                label(ctx, enlarged ? "Hill sphere, r_H = \(quantity(hill, "m", .length)) (enlarged ×\(Format.number(drawn / (hill * scale))))"
                                    : "Hill sphere, r_H = \(quantity(hill, "m", .length))",
                      at: CGPoint(x: body.x + drawn + 6, y: body.y + drawn + 4), anchor: .topLeading, size: 10, colour: .accentColor)
            }

            let tangent = CGVector(dx: -sin(phi), dy: -cos(phi))
            let length: CGFloat = 54
            let tip = CGPoint(x: body.x + tangent.dx * length, y: body.y + tangent.dy * length)
            var arrow = Path()
            arrow.move(to: body)
            arrow.addLine(to: tip)
            let back = CGVector(dx: -tangent.dx, dy: -tangent.dy), side = CGVector(dx: -tangent.dy, dy: tangent.dx)
            arrow.move(to: CGPoint(x: tip.x + back.dx * 8 + side.dx * 4, y: tip.y + back.dy * 8 + side.dy * 4))
            arrow.addLine(to: tip)
            arrow.addLine(to: CGPoint(x: tip.x + back.dx * 8 - side.dx * 4, y: tip.y + back.dy * 8 - side.dy * 4))
            ctx.stroke(arrow, with: .color(.primary), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            label(ctx, "v = \(quantity(orbit.speed, "m s⁻¹", .speed))", at: CGPoint(x: tip.x - 4, y: tip.y - 4), anchor: .bottomTrailing, size: 11)

            ctx.fill(circle(body, 5.5), with: .color(.primary))
            if !orbit.satellite.isEmpty {
                label(ctx, orbit.satellite, at: CGPoint(x: body.x + 9, y: body.y - 2), anchor: .bottomLeading, size: 11, weight: .medium, colour: .primary)
            }

            // What was worked out, at the top left.
            let lines = ["T = \(quantity(orbit.period, "s", .time))", "v = \(quantity(orbit.speed, "m s⁻¹", .speed))", "a = \(quantity(orbit.a, "m", .length))"]
            for (i, line) in lines.enumerated() {
                label(ctx, line, at: CGPoint(x: 4, y: 10 + CGFloat(i) * 17), anchor: .leading, size: 12, colour: .primary)
            }
            label(ctx, "Circular, from above; the bodies are marks, not to scale", at: CGPoint(x: 4, y: size.height - 8), anchor: .leading, size: 10)
        }
    }
}

// MARK: - Hertzsprung–Russell diagram

// Temperature falling to the right, as astronomers draw it, and luminosity up, both logarithmic; the
// main sequence as a band, lines of equal radius dashed, and each star in its own colour.
private struct HRView: View {
    let hr: HRPicture

    static let hottest = 40_000.0, coolest = 2_000.0, brightest = 6.0, faintest = -5.0
    // The main sequence, roughly: (temperature in K, luminosity in L☉).
    static let mainSequence: [(Double, Double)] = [(42_000, 5e5), (31_000, 2e4), (15_700, 700), (9_700, 40), (7_300, 6), (5_800, 1),
                                                   (5_300, 0.45), (4_400, 0.15), (3_850, 0.07), (3_050, 0.003), (2_600, 0.0005)]

    var body: some View {
        Canvas { ctx, size in
            let plot = CGRect(x: 48, y: 18, width: size.width - 60, height: size.height - 52)
            func x(_ T: Double) -> CGFloat { plot.minX + (log10(Self.hottest) - log10(T)) / (log10(Self.hottest) - log10(Self.coolest)) * plot.width }
            func y(_ L: Double) -> CGFloat { plot.minY + (Self.brightest - log10(L)) / (Self.brightest - Self.faintest) * plot.height }
            var clipped = ctx
            clipped.clip(to: Path(plot))

            // The frame and its ticks.
            ctx.stroke(Path(plot), with: .color(.primary.opacity(0.25)), lineWidth: 0.8)
            for T in [40_000.0, 20_000, 10_000, 5_000, 2_500] {
                var tick = Path(); tick.move(to: CGPoint(x: x(T), y: plot.maxY)); tick.addLine(to: CGPoint(x: x(T), y: plot.minY))
                ctx.stroke(tick, with: .color(.primary.opacity(0.07)), lineWidth: 0.5)
                label(ctx, T >= 10_000 ? "\(Int(T / 1000)) 000" : "\(Int(T))", at: CGPoint(x: x(T), y: plot.maxY + 9), anchor: .center, size: 10)
            }
            for k in stride(from: -4, through: 6, by: 2) {
                var tick = Path(); tick.move(to: CGPoint(x: plot.minX, y: y(pow(10, Double(k))))); tick.addLine(to: CGPoint(x: plot.maxX, y: y(pow(10, Double(k)))))
                ctx.stroke(tick, with: .color(.primary.opacity(0.07)), lineWidth: 0.5)
                label(ctx, k == 0 ? "1" : "10" + (k < 0 ? "⁻" : "") + superscript(abs(k)), at: CGPoint(x: plot.minX - 6, y: y(pow(10, Double(k)))), anchor: .trailing, size: 10)
            }
            label(ctx, "Surface temperature / K", at: CGPoint(x: plot.midX, y: size.height - 6), anchor: .center, size: 11)
            label(ctx, "L / L☉", at: CGPoint(x: plot.minX - 6, y: 6), anchor: .trailing, size: 11)

            // The main sequence, a soft band, and where the giants and white dwarfs lie.
            var band = Path()
            for (i, (T, L)) in Self.mainSequence.enumerated() {
                let p = CGPoint(x: x(T), y: y(L))
                if i == 0 { band.move(to: p) } else { band.addLine(to: p) }
            }
            clipped.stroke(band, with: .color(.primary.opacity(0.09)), style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round))
            label(clipped, "Main sequence", at: CGPoint(x: x(13_000), y: y(250) - 4), anchor: .bottomLeading, size: 10)
            label(clipped, "Supergiants", at: CGPoint(x: x(9_000), y: y(2e5)), anchor: .center, size: 10)
            label(clipped, "Giants", at: CGPoint(x: x(4_800), y: y(150)), anchor: .center, size: 10)
            label(clipped, "White dwarfs", at: CGPoint(x: x(14_000), y: y(3e-4)), anchor: .center, size: 10)

            // Lines of one radius: L = (R/R☉)² (T/5778 K)⁴.
            for R in [0.01, 1.0, 100.0] {
                var line = Path()
                for (i, T) in stride(from: Self.coolest, through: Self.hottest, by: 500).enumerated() {
                    let p = CGPoint(x: x(T), y: y(R * R * pow(T / 5778, 4)))
                    if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
                }
                clipped.stroke(line, with: .color(.primary.opacity(0.22)), style: StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
                let T = R >= 100 ? 3_000.0 : R >= 1 ? 2_600.0 : 20_000.0
                label(clipped, R == 1 ? "1 R☉" : "\(R < 1 ? "0.01" : "100") R☉", at: CGPoint(x: x(T) - 4, y: y(R * R * pow(T / 5778, 4)) - 4), anchor: .bottomTrailing, size: 9)
            }

            // The stars, the one asked about last, ringed and named in bold.
            for star in hr.stars.sorted(by: { !$0.marked && $1.marked }) {
                let p = CGPoint(x: x(star.temperature), y: y(star.luminosity))
                guard plot.insetBy(dx: -4, dy: -4).contains(p) else { continue }
                let r: CGFloat = star.marked ? 7 : 5
                ctx.fill(circle(p, r), with: .color(Self.colour(star.temperature)))
                ctx.stroke(circle(p, r), with: .color(.primary.opacity(star.marked ? 0.9 : 0.35)), lineWidth: star.marked ? 1.5 : 0.6)
                if star.marked { ctx.stroke(circle(p, r + 4), with: .color(.accentColor), lineWidth: 1.5) }
                let right = p.x < plot.maxX - 110
                label(ctx, star.name, at: CGPoint(x: p.x + (right ? 1 : -1) * (r + 6), y: p.y), anchor: right ? .leading : .trailing,
                      size: star.marked ? 12 : 10, weight: star.marked ? .semibold : .regular, colour: star.marked ? .primary : .secondary)
            }
        }
    }

    // The colour of a black body at T, roughly, as it would look: red at 3000 K, white near 6500 K, blue beyond.
    static func colour(_ T: Double) -> Color {
        let t = T / 100
        let red = t <= 66 ? 255 : 329.698727446 * pow(t - 60, -0.1332047592)
        let green = t <= 66 ? 99.4708025861 * log(t) - 161.1195681661 : 288.1221695283 * pow(t - 60, -0.0755148492)
        let blue = t >= 66 ? 255 : t <= 19 ? 0 : 138.5177312231 * log(t - 10) - 305.0447927307
        func unit(_ v: Double) -> Double { min(max(v, 0), 255) / 255 }
        return Color(red: unit(red), green: unit(green), blue: unit(blue))
    }
}

// MARK: - Black hole

// To scale: the event horizon, the photon sphere at 1.5 r_s, where light can circle, and the
// innermost stable circular orbit at 3 r_s, inside which matter falls in; a scale bar under them.
private struct BlackHoleView: View {
    let hole: BlackHolePicture

    var body: some View {
        Canvas { ctx, size in
            let outer = min(size.height / 2 - 30, size.width * 0.26)
            let centre = CGPoint(x: outer + 20, y: size.height / 2 - 6)
            let scale = outer / (3 * hole.rs)
            let rings: [(factor: Double, name: String, dash: [CGFloat])] = [
                (3, "Innermost stable orbit, 3r_s", [1.5, 3]), (1.5, "Photon sphere, 1.5r_s", [5, 4]), (1, "Event horizon, r_s", [])]
            for ring in rings where ring.factor > 1 {
                ctx.stroke(circle(centre, ring.factor * hole.rs * scale), with: .color(.primary.opacity(0.6)), style: StrokeStyle(lineWidth: 1.2, dash: ring.dash))
            }
            let horizon = hole.rs * scale
            ctx.fill(circle(centre, horizon + 3), with: .color(Color(red: 1, green: 0.55, blue: 0.15).opacity(0.35)))
            ctx.fill(circle(centre, horizon), with: .color(.black))

            // Each named on the right, with a line to its edge.
            let column = centre.x + outer + 34
            for (i, ring) in rings.enumerated() {
                let edge = CGPoint(x: centre.x + ring.factor * hole.rs * scale * cos(0.35), y: centre.y - ring.factor * hole.rs * scale * sin(0.35))
                let at = CGPoint(x: column, y: centre.y - outer * 0.75 + CGFloat(i) * 46)
                var leader = Path()
                leader.move(to: edge)
                leader.addLine(to: CGPoint(x: column - 6, y: at.y))
                ctx.stroke(leader, with: .color(.primary.opacity(0.35)), lineWidth: 0.7)
                label(ctx, ring.name, at: CGPoint(x: column, y: at.y - 7), anchor: .leading, size: 12, weight: .medium, colour: .primary)
                label(ctx, "= " + quantity(ring.factor * hole.rs, "m", .length) + (ring.factor == 1 ? "" : "  (\(Format.number(ring.factor * hole.rs)) m)"),
                      at: CGPoint(x: column, y: at.y + 9), anchor: .leading, size: 11)
            }

            // A scale bar of a round length, under the picture.
            let target = outer * 1.2 / scale
            let power = pow(10, floor(log10(target)))
            let step = [5.0, 2, 1].map { $0 * power }.first { $0 <= target } ?? power
            let bar = step * scale
            let y0 = size.height - 22
            var path = Path()
            path.move(to: CGPoint(x: 20, y: y0 - 4)); path.addLine(to: CGPoint(x: 20, y: y0)); path.addLine(to: CGPoint(x: 20 + bar, y: y0)); path.addLine(to: CGPoint(x: 20 + bar, y: y0 - 4))
            ctx.stroke(path, with: .color(.primary.opacity(0.7)), lineWidth: 1)
            label(ctx, quantity(step, "m", .length), at: CGPoint(x: 20 + bar / 2, y: y0 + 9), anchor: .center, size: 10)

            // How large the body would be drawn at the same scale: points are 0.3528 mm.
            if let R = hole.radius {
                let across = 2 * R * scale * 0.3528e-3
                let said = across >= 1000 ? "\(Format.number(across / 1000)) km" : across >= 1 ? "\(Format.number(across)) m" : "\(Format.number(across * 100)) cm"
                label(ctx, "Drawn at this scale, \(hole.name) as it is would be \(said) across.",
                      at: CGPoint(x: column, y: size.height - 22), anchor: .leading, size: 11)
            }
        }
    }
}

// MARK: - Spectrum

// Two strips of the spectrum, at rest and as seen, with the same absorption lines in each, moved
// by 1 + z; dashed lines join each line to where it has gone.
private struct SpectrumView: View {
    let spectrum: SpectrumPicture

    var body: some View {
        Canvas { ctx, size in
            let factor = 1 + spectrum.z
            let shifted = spectrum.lines.map { $0.rest * factor }
            let low = min(380, (shifted.min() ?? 380) - 25), high = min(max(720, (shifted.max() ?? 720) + 25), 3000)
            let left: CGFloat = 76, right = size.width - 10
            func x(_ nm: Double) -> CGFloat { left + (nm - low) / (high - low) * (right - left) }
            let rest = CGRect(x: left, y: 26, width: right - left, height: 34)
            let seen = CGRect(x: left, y: 122, width: right - left, height: 34)

            for (strip, title) in [(rest, "At rest"), (seen, "Observed")] {
                var px = strip.minX
                while px < strip.maxX {
                    let nm = low + (px - left) / (right - left) * (high - low)
                    ctx.fill(Path(CGRect(x: px, y: strip.minY, width: 1.6, height: strip.height)), with: .color(Self.colour(nm)))
                    px += 1.5
                }
                ctx.stroke(Path(strip), with: .color(.primary.opacity(0.25)), lineWidth: 0.6)
                label(ctx, title, at: CGPoint(x: left - 8, y: strip.midY), anchor: .trailing, size: 11, weight: .medium, colour: .primary)
            }

            for (i, line) in spectrum.lines.enumerated() {
                let marked = spectrum.marked == i
                let a = x(line.rest), b = x(line.rest * factor)
                for (strip, at) in [(rest, a), (seen, b)] where at >= strip.minX && at <= strip.maxX {
                    ctx.fill(Path(CGRect(x: at - 1, y: strip.minY, width: 2, height: strip.height)), with: .color(.black.opacity(0.85)))
                }
                var joint = Path()
                joint.move(to: CGPoint(x: a, y: rest.maxY + 2))
                joint.addLine(to: CGPoint(x: b, y: seen.minY - 2))
                ctx.stroke(joint, with: .color(marked ? .accentColor : .primary.opacity(0.35)), style: StrokeStyle(lineWidth: marked ? 1.5 : 0.8, dash: marked ? [] : [3, 3]))
                label(ctx, line.name, at: CGPoint(x: a, y: rest.minY - 8), anchor: .center, size: 10, weight: marked ? .semibold : .regular, colour: marked ? .primary : .secondary)
                label(ctx, Format.number(line.rest * factor), at: CGPoint(x: b, y: seen.maxY + 9), anchor: .center, size: 9)
            }

            // The wavelength scale, in nm, under the observed strip.
            let span = high - low
            let step = span > 1200 ? 200.0 : span > 600 ? 100 : 50
            var nm = (low / step).rounded(.up) * step
            while nm <= high {
                label(ctx, "\(Int(nm))", at: CGPoint(x: x(nm), y: seen.maxY + 26), anchor: .center, size: 9, colour: .secondary.opacity(0.7))
                nm += step
            }
            label(ctx, "Wavelength / nm", at: CGPoint(x: left, y: size.height - 8), anchor: .leading, size: 10)
            let said = spectrum.z >= 0 ? "Each wavelength × (1 + z) = × \(Format.number(factor)): moved to the red" : "Each wavelength × (1 + z) = × \(Format.number(factor)): moved to the blue"
            label(ctx, said, at: CGPoint(x: right, y: size.height - 8), anchor: .trailing, size: 10)
        }
    }

    // The colour of light of a wavelength, roughly; grey outside what the eye sees.
    static func colour(_ nm: Double) -> Color {
        guard nm >= 380, nm <= 750 else { return Color.primary.opacity(0.12) }
        var (r, g, b): (Double, Double, Double)
        switch nm {
        case ..<440: (r, g, b) = (-(nm - 440) / 60, 0, 1)
        case ..<490: (r, g, b) = (0, (nm - 440) / 50, 1)
        case ..<510: (r, g, b) = (0, 1, -(nm - 510) / 20)
        case ..<580: (r, g, b) = ((nm - 510) / 70, 1, 0)
        case ..<645: (r, g, b) = (1, -(nm - 645) / 65, 0)
        default: (r, g, b) = (1, 0, 0)
        }
        // Dimmer towards the ends, where the eye sees less.
        let edge = nm < 420 ? 0.3 + 0.7 * (nm - 380) / 40 : nm > 700 ? 0.3 + 0.7 * (750 - nm) / 50 : 1
        return Color(red: r * edge, green: g * edge, blue: b * edge)
    }
}
