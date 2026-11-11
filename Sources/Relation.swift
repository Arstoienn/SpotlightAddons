import Foundation

// A curve to draw: y = x², f(x) = sin x, x² + y² = 5. One equation whose only letters are x and y, or
// a function written with its name, f(x) = …, is a relation between the two coordinates, and there is
// nothing to solve for: it is drawn, and what can be said of its shape is said. A straight line has its
// gradient and intercept, a parabola its vertex, a circle its centre and radius, an ellipse or hyperbola
// its centre; any curve has where it crosses the axes, and a function its turning points. Letters other
// than x and y make it a formula, v = u + at, which is turned round instead (Rearrangement).
struct Relation {
    enum Form {
        case function(Expr, rightSide: String)   // y = f(x), with the right side as typed, for solving f(x) = 0
        case implicit(Expr, Expr)                // left = right, both in x and y
    }

    let form: Form
    let name: String       // y, or f in f(x) = …
    let variable: String   // x, or t in f(t) = …
    let equation: Math     // as it is printed

    // MARK: - Reading

    static func parse(_ input: String) -> Relation? {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard text.filter({ $0 == "=" }).count == 1, !text.contains(","), !text.contains("?") else { return nil }
        let sides = text.split(separator: "=", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
        guard sides.count == 2, !sides[0].isEmpty, !sides[1].isEmpty else { return nil }

        // f(x) = …: a name of one letter, its variable another, and nothing on the right but the variable.
        if let m = sides[0].range(of: "^[A-Za-z]\\s*\\(\\s*[a-z]\\s*\\)$", options: .regularExpression), m == sides[0].startIndex..<sides[0].endIndex {
            let name = String(sides[0].first!), variable = String(sides[0].filter(\.isLetter).dropFirst())
            guard name != variable, letters(sides[1]) == [variable], let f = expression(sides[1], unknown: variable, bound: []) else { return nil }
            return Relation(form: .function(f, rightSide: sides[1]), name: name, variable: variable,
                            equation: row(t("\(name)(\(variable)) = "), typeset(f, variable)))
        }
        guard let left = letters(sides[0]), let right = letters(sides[1]), left.union(right) == ["x", "y"] else { return nil }
        // y = …, with no y on the right: y as a function of x.
        if sides[0] == "y", !right.contains("y"), let f = expression(sides[1], unknown: "x", bound: []) {
            return Relation(form: .function(f, rightSide: sides[1]), name: "y", variable: "x", equation: row(t("y = "), typeset(f, "x")))
        }
        guard let l = expression(sides[0], unknown: "", bound: ["x", "y"]), let r = expression(sides[1], unknown: "", bound: ["x", "y"]) else { return nil }
        return Relation(form: .implicit(l, r), name: "y", variable: "x", equation: row(typeset(l, ""), t(" = "), typeset(r, "")))
    }

    // The letters of a side, e left out as Euler's number; nil where it cannot be read.
    private static func letters(_ side: String) -> Set<String>? {
        guard let tokens = try? Parser.tokenize(side) else { return nil }
        return Set(tokens.compactMap { if case .letter(let l) = $0 { l } else { nil } }).subtracting(["e"])
    }

    private static func expression(_ side: String, unknown: String, bound: [String]) -> Expr? {
        guard var tokens = try? Parser.tokenize(side) else { return nil }
        tokens = tokens.map { $0 == .letter("e") ? .constant(M_E) : $0 }
        var p = Parser.State(tokens: tokens, unknown: unknown, constants: [], bound: bound)
        guard let e = try? p.expression(), p.at == tokens.count else { return nil }
        return e
    }

    // MARK: - The curve

    // Where it is zero: g(x, y) = left − right.
    var g: (Double, Double) -> Double {
        switch form {
        case .function(let f, _): return { x, y in y - f.eval(x) }
        case .implicit(let l, let r): return { x, y in l.eval(0, ["x": x, "y": y]) - r.eval(0, ["x": x, "y": y]) }
        }
    }

    // A function's own value, where it is one.
    var f: ((Double) -> Double)? {
        if case .function(let e, _) = form { return { e.eval($0) } }
        return nil
    }

    // What kind of curve it is, read from the equation: for a function, its polynomial's degree; for
    // any equation of at most the second degree in x and y, the conic it is.
    enum Shape {
        case line(gradient: Double, intercept: Double)
        case vertical(Double)
        case parabola(vertex: (Double, Double), upwards: Bool)
        case sideways(vertex: (Double, Double), rightwards: Bool)   // x = ay² + by + c
        case circle(centre: (Double, Double), radius: Double)
        case ellipse(centre: (Double, Double), semiAxes: (Double, Double)?)
        case hyperbola(centre: (Double, Double))
        case curve
    }

    var shape: Shape {
        if case .function(let e, _) = form {
            guard let p = poly(e).map(trim) else { return .curve }
            if p.count == 2 { return .line(gradient: p[1], intercept: p[0]) }
            if p.count == 3 {
                let h = -p[1] / (2 * p[2])
                return .parabola(vertex: (h, p[0] + p[1] * h + p[2] * h * h), upwards: p[2] > 0)
            }
            return .curve
        }
        guard let fitted = Relation.conic(g) else { return .curve }
        // Noise from the fit taken off, so that a centre at the origin is at the origin.
        let snapped = [fitted.a, fitted.b, fitted.c, fitted.d, fitted.e, fitted.f].map(Relation.tidy)
        let c = (a: snapped[0], b: snapped[1], c: snapped[2], d: snapped[3], e: snapped[4], f: snapped[5])
        let scale = [c.a, c.b, c.c, c.d, c.e, c.f].map(abs).max() ?? 1, tiny = 1e-9 * max(scale, 1)
        if abs(c.a) < tiny, abs(c.b) < tiny, abs(c.c) < tiny {
            if abs(c.e) > tiny { return .line(gradient: -c.d / c.e, intercept: -c.f / c.e) }
            return abs(c.d) > tiny ? .vertical(-c.f / c.d) : .curve
        }
        let discriminant = c.b * c.b - 4 * c.a * c.c
        if abs(discriminant) < tiny {
            // y = ax² + bx + c turned about: y in the square only, or x in the square only.
            if abs(c.c) < tiny, abs(c.e) > tiny {
                let (a, b, k) = (-c.a / c.e, -c.d / c.e, -c.f / c.e), h = -b / (2 * a)
                return .parabola(vertex: (Relation.tidy(h), Relation.tidy(k + b * h + a * h * h)), upwards: a > 0)
            }
            if abs(c.a) < tiny, abs(c.d) > tiny {
                let (a, b, k) = (-c.c / c.d, -c.e / c.d, -c.f / c.d), h = -b / (2 * a)
                return .sideways(vertex: (Relation.tidy(k + b * h + a * h * h), Relation.tidy(h)), rightwards: a > 0)
            }
            return .curve
        }
        // The centre, where both partial derivatives are zero.
        let det = 4 * c.a * c.c - c.b * c.b
        let centre = (Relation.tidy((c.b * c.e - 2 * c.c * c.d) / det), Relation.tidy((c.b * c.d - 2 * c.a * c.e) / det))
        if abs(c.b) < tiny, abs(c.a - c.c) < tiny {
            let r2 = centre.0 * centre.0 + centre.1 * centre.1 - c.f / c.a
            return r2 > tiny ? .circle(centre: centre, radius: Relation.tidy(r2.squareRoot())) : .curve
        }
        if discriminant < 0 {
            // a(x − h)² + c(y − k)² = K, its axes along the axes: the half-lengths of those axes.
            let k = -(c.a * centre.0 * centre.0 + c.b * centre.0 * centre.1 + c.c * centre.1 * centre.1 + c.d * centre.0 + c.e * centre.1 + c.f)
            let axes = abs(c.b) < tiny && k / c.a > 0 && k / c.c > 0 ? (Relation.tidy((k / c.a).squareRoot()), Relation.tidy((k / c.c).squareRoot())) : nil
            return .ellipse(centre: centre, semiAxes: axes)
        }
        return .hyperbola(centre: centre)
    }

    // g as ax² + bxy + cy² + dx + ey + f, where it is that exactly: fitted at a dozen points and checked at others.
    static func conic(_ g: (Double, Double) -> Double) -> (a: Double, b: Double, c: Double, d: Double, e: Double, f: Double)? {
        func terms(_ x: Double, _ y: Double) -> [Double] { [x * x, x * y, y * y, x, y, 1] }
        let fit: [(Double, Double)] = [(0, 0), (1, 0), (0, 1), (-1, 0), (0, -1), (1, 1), (2, -1), (-1, 2), (1.5, 0.5), (-2, -1.5), (0.7, -2.2), (3, 1)]
        // The normal equations of the least squares fit.
        var m = [[Double]](repeating: [Double](repeating: 0, count: 7), count: 6)
        for (x, y) in fit {
            let v = g(x, y), row = terms(x, y)
            guard v.isFinite else { return nil }
            for i in 0..<6 {
                for j in 0..<6 { m[i][j] += row[i] * row[j] }
                m[i][6] += row[i] * v
            }
        }
        for col in 0..<6 {
            guard let pivot = (col..<6).max(by: { abs(m[$0][col]) < abs(m[$1][col]) }), abs(m[pivot][col]) > 1e-12 else { return nil }
            m.swapAt(col, pivot)
            for r in 0..<6 where r != col {
                let k = m[r][col] / m[col][col]
                for j in col..<7 { m[r][j] -= k * m[col][j] }
            }
        }
        let c = (0..<6).map { m[$0][6] / m[$0][$0] }
        for (x, y) in [(0.3, 0.9), (-1.7, 0.4), (2.5, -3.1), (-0.6, -0.8), (4, 2)] {
            let v = g(x, y), fitted = zip(terms(x, y), c).map(*).reduce(0, +)
            guard v.isFinite, abs(v - fitted) <= 1e-7 * max(1, abs(v)) else { return nil }
        }
        return (c[0], c[1], c[2], c[3], c[4], c[5])
    }

    // MARK: - Where it crosses the axes, and turns

    // Zeros of h on the range: each change of sign, closed in on, and each point where it only
    // touches zero, as x² does.
    static func zeros(_ h: (Double) -> Double, in range: ClosedRange<Double> = -50...50, steps: Int = 4000) -> [Double] {
        var found: [Double] = []
        let dx = (range.upperBound - range.lowerBound) / Double(steps)
        var x0 = range.lowerBound, y0 = h(x0)
        for i in 1...steps {
            let x1 = range.lowerBound + Double(i) * dx, y1 = h(x1)
            defer { (x0, y0) = (x1, y1) }
            guard y0.isFinite, y1.isFinite else { continue }
            if y0 == 0 { found.append(x0); continue }
            guard (y0 < 0) != (y1 < 0), y1 != 0 else { continue }
            // Not across a jump, as 1/x is at 0.
            guard abs(y0) + abs(y1) < 1e3 * max(1, dx * 100) else { continue }
            var (a, b, ya) = (x0, x1, y0)
            for _ in 0..<80 {
                let mid = (a + b) / 2, ym = h(mid)
                if (ym < 0) == (ya < 0) { (a, ya) = (mid, ym) } else { b = mid }
            }
            found.append((a + b) / 2)
        }
        // Touching zero without crossing: a minimum of |h| that is zero.
        for i in 1..<steps {
            let x = range.lowerBound + Double(i) * dx
            let (l, m, r) = (abs(h(x - dx)), abs(h(x)), abs(h(x + dx)))
            guard m.isFinite, m <= l, m <= r, m < 1e-6 else { continue }
            let refined = refineMinimum({ abs(h($0)) }, x - dx, x + dx)
            if abs(h(refined)) < 1e-10, !found.contains(where: { abs($0 - refined) < dx }) { found.append(refined) }
        }
        return found.map(tidy).sorted().reduce(into: []) { out, x in if out.last.map({ abs($0 - x) > 1e-7 }) ?? true { out.append(x) } }
    }

    // Where the function turns, each a minimum or a maximum, on the part of it in view.
    static func turningPoints(_ f: (Double) -> Double, in range: ClosedRange<Double> = -20...20) -> [(x: Double, y: Double, minimum: Bool)] {
        let steps = 4000, dx = (range.upperBound - range.lowerBound) / Double(steps)
        var out: [(x: Double, y: Double, minimum: Bool)] = []
        for i in 1..<steps {
            let x = range.lowerBound + Double(i) * dx
            let (l, m, r) = (f(x - dx), f(x), f(x + dx))
            // Not where it runs off to infinity, as 1/x does at 0, which can look like a dip.
            guard l.isFinite, m.isFinite, r.isFinite, max(abs(l), abs(m), abs(r)) < 1e6 else { continue }
            let minimum = m < l && m <= r, maximum = m > l && m >= r
            guard minimum || maximum else { continue }
            let at = tidy(refineMinimum({ minimum ? f($0) : -f($0) }, x - dx, x + dx)), y = f(at)
            guard y.isFinite, abs(y - m) <= abs(l - m) + abs(r - m) + 1e-9 else { continue }
            out.append((at, tidy(y), minimum))
        }
        return out
    }

    private static func refineMinimum(_ h: (Double) -> Double, _ lo: Double, _ hi: Double) -> Double {
        var (a, b) = (lo, hi)
        let ratio = (5.0.squareRoot() - 1) / 2
        for _ in 0..<100 {
            let c = b - ratio * (b - a), d = a + ratio * (b - a)
            if h(c) < h(d) { b = d } else { a = c }
        }
        return (a + b) / 2
    }

    // Rounding noise taken off: 1.9999999999 is 2, and 1e-13 is 0; anything else is left as it is.
    static func tidy(_ x: Double) -> Double {
        if abs(x) < 1e-9 { return 0 }
        return abs(x - x.rounded()) < 1e-9 * max(1, abs(x)) ? x.rounded() : x
    }

    // MARK: - The card and the working

    // Exactly where that is sure: 3/2, 1 + √2, and π/2 or 2π, a multiple of π being the x-intercept of a sine.
    private static func value(_ x: Double) -> Math {
        if x != 0, let (p, q) = rational(x / Double.pi), q <= 12, abs(p) <= 48, abs(Double(p) / Double(q) * Double.pi - x) < 1e-10 {
            let top = abs(p) == 1 ? "π" : "\(abs(p))π"
            return t((p < 0 ? "−" : "") + (q == 1 ? top : top + "/\(q)"))
        }
        return closedForm(x)
    }
    private static func point(_ p: (Double, Double)) -> Math { row(t("("), value(p.0), t(", "), value(p.1), t(")")) }
    private static func list(_ xs: [Double]) -> Math {
        var parts: [Math] = []
        for (i, x) in xs.enumerated() { if i > 0 { parts.append(t(", ")) }; parts.append(value(x)) }
        return .row(parts)
    }

    // The x-intercepts: for a function, the solutions of f(x) = 0 as the solver gives them, exactly;
    // otherwise where the curve meets y = 0.
    private var xIntercepts: (shown: Math?, values: [Double]) {
        if case .function(_, let side) = form, variable == "x", let d = Solver.details(side + " = 0"), !d.solutions.isEmpty,
           !d.solutions.contains(where: { $0.plain.contains("No") || $0.plain.contains("ℝ") }) {
            let values = d.roots.isEmpty ? Relation.zeros({ self.g($0, 0) }) : d.roots
            // Where the solver could only approximate, the values found, exactly where they can be: −√3, not ≈ −1.73205.
            if d.solutions.contains(where: { $0.plain.contains("≈") }), !values.isEmpty {
                return (row(t("x = "), Relation.list(Array(values.prefix(6)))), values)
            }
            return (.row(d.solutions.enumerated().flatMap { i, s in i == 0 ? [s] : [t(";  "), s] }), values)
        }
        let values = Relation.zeros({ self.g($0, 0) })
        return (values.isEmpty ? nil : row(t("x = "), Relation.list(Array(values.prefix(6)))), values)
    }

    private var yIntercepts: [Double] {
        if let f { let y = f(0); return y.isFinite ? [Relation.tidy(y)] : [] }
        return Relation.zeros({ self.g(0, $0) })
    }

    // The card's line: what the curve is.
    var headline: String {
        switch shape {
        case .line(let m, let c): return "Straight line with gradient \(Relation.value(m).plain) and y-intercept \(Relation.value(c).plain)"
        case .vertical(let a): return "Vertical line x = \(Relation.value(a).plain)"
        case .parabola(let v, let up): return "Parabola with vertex \(Relation.point(v).plain), opening \(up ? "upwards" : "downwards")"
        case .circle(let c, let r): return "Circle with centre \(Relation.point(c).plain) and radius \(Relation.value(r).plain)"
        case .sideways(let v, let right): return "Parabola with vertex \(Relation.point(v).plain), opening to the \(right ? "right" : "left")"
        case .ellipse(let c, let axes):
            guard let axes else { return "Ellipse centred at \(Relation.point(c).plain)" }
            return "Ellipse centred at \(Relation.point(c).plain), with semi-axes \(Relation.value(axes.0).plain) and \(Relation.value(axes.1).plain)"
        case .hyperbola(let c): return "Hyperbola centred at \(Relation.point(c).plain)"
        case .curve:
            guard let f else { return "Curve in x and y" }
            // A curve is told by its turning points, where it has a few, and otherwise by where it meets the y-axis.
            let turns = Relation.turningPoints(f)
            if (1...2).contains(turns.count) {
                return "Curve with " + turns.map { "a \($0.minimum ? "minimum" : "maximum") at \(Relation.point(($0.x, $0.y)).plain)" }.joined(separator: " and ")
            }
            let y = f(0)
            return y.isFinite ? "Curve through \(Relation.point((0, Relation.tidy(y))).plain)" : "Curve not meeting the y-axis"
        }
    }

    var solution: Solution {
        var facts: [String] = []
        let xs = xIntercepts.values, ys = yIntercepts
        if !xs.isEmpty, xs.count <= 4 { facts.append("x-intercept\(xs.count == 1 ? "" : "s") " + Relation.list(xs).plain) }
        if !ys.isEmpty, ys.count <= 4 { facts.append("y-intercept\(ys.count == 1 ? "" : "s") " + Relation.list(ys).plain) }
        if case .circle(_, let r) = shape, abs(r - r.rounded()) > 1e-9 { facts.insert("radius ≈ " + decimal(r), at: 0) }
        return Solution(exact: headline, approx: facts.isEmpty ? nil : facts.joined(separator: "; "))
    }

    var details: Details {
        var steps: [Step] = [], features: [Math] = [], marks: [CGPoint] = []
        let x = variable, label = f != nil ? (name == "y" ? "y" : "\(name)(\(x))") : "y"

        switch shape {
        case .line(let m, let c):
            steps.append(Step(label: "Writing it as y = mx + c", math: row(t("y = "), Relation.value(m), t(x), t(" + "), Relation.value(c)),
                              note: "The gradient is m and the y-intercept is c."))
            features.append(row(t("Gradient: "), Relation.value(m)))
        case .parabola(let v, let up):
            steps.append(Step(label: "Locating the vertex", math: row(t("x = "), Relation.value(v.0), t(",  y = "), Relation.value(v.1)),
                              note: "The vertex lies where the gradient is zero."))
            features.append(row(t(up ? "Minimum (vertex): " : "Maximum (vertex): "), Relation.point(v)))
            marks.append(CGPoint(x: v.0, y: v.1))
        case .circle(let c, let r):
            let square: (String, Double) -> Math = { letter, k in
                k == 0 ? row(t(letter), .power(t(""), t("2"))) : row(t("("), t(letter), t(k > 0 ? " − " : " + "), Relation.value(abs(k)), t(")"), .power(t(""), t("2")))
            }
            steps.append(Step(label: "Completing the square", math: row(square("x", c.0), t(" + "), square("y", c.1), t(" = "), Relation.value(r * r)),
                              note: "This is (x − a)² + (y − b)² = r², a circle with centre (a, b) and radius r."))
            features.append(row(t("Centre: "), Relation.point(c)))
            features.append(row(t("Radius: "), Relation.value(r)))
            marks.append(CGPoint(x: c.0, y: c.1))
        case .sideways(let v, _):
            features.append(row(t("Vertex: "), Relation.point(v)))
            marks.append(CGPoint(x: v.0, y: v.1))
        case .ellipse(let c, let axes):
            features.append(row(t("Centre: "), Relation.point(c)))
            if let axes { features.append(row(t("Semi-axes: "), Relation.value(axes.0), t(" along x, "), Relation.value(axes.1), t(" along y"))) }
            marks.append(CGPoint(x: c.0, y: c.1))
        case .hyperbola(let c):
            features.append(row(t("Centre: "), Relation.point(c)))
        default: break
        }

        let (shownX, xs) = xIntercepts
        if let shownX, !xs.isEmpty || f == nil {
            steps.append(Step(label: "Finding the x-intercepts", math: shownX, note: "These are the points where \(label) = 0."))
            if xs.count <= 6 { features.append(row(t("x-intercept\(xs.count == 1 ? "" : "s"): "), Relation.list(xs))) }
            marks += xs.prefix(8).map { CGPoint(x: $0, y: 0) }
        }
        let ys = yIntercepts
        if !ys.isEmpty {
            steps.append(Step(label: "Finding the y-intercept\(ys.count == 1 ? "" : "s")",
                              math: f != nil ? row(t(name == "y" ? "x = 0:  y = " : "\(name)(0) = "), Relation.list(ys)) : row(t("y = "), Relation.list(ys)),
                              note: "These are the points where x = 0."))
            if ys.count <= 6 { features.append(row(t("y-intercept\(ys.count == 1 ? "" : "s"): "), Relation.list(ys))) }
            marks += ys.prefix(8).map { CGPoint(x: 0, y: $0) }
        }
        if let f, case .curve = shape {
            let turns = Relation.turningPoints(f)
            if !turns.isEmpty, turns.count <= 6 {
                let shown: [Math] = turns.enumerated().flatMap { i, p -> [Math] in
                    (i == 0 ? [] : [t(";  ")]) + [Relation.point((p.x, p.y)), t(p.minimum ? " minimum" : " maximum")]
                }
                steps.append(Step(label: "Locating the turning points", math: .row(shown),
                                  note: "These are where the gradient is zero and changes sign, for −20 ≤ \(x) ≤ 20."))
                for p in turns {
                    features.append(row(t(p.minimum ? "Local minimum: " : "Local maximum: "), Relation.point((p.x, p.y))))
                    marks.append(CGPoint(x: p.x, y: p.y))
                }
            }
        }

        // One mark for a point reached twice, as the origin is both intercepts of y = x².
        var points: [CGPoint] = []
        for p in marks where !points.contains(where: { hypot($0.x - p.x, $0.y - p.y) < 1e-9 }) { points.append(p) }
        let curve: Graph.Curve
        if let f {
            curve = Graph.Curve(shape: .function(f), label: equation)
        } else if case .vertical(let a) = shape {
            curve = Graph.Curve(shape: .vertical(a), label: equation)
        } else {
            curve = Graph.Curve(shape: .implicit(g), label: equation)
        }
        var d = Details(name: x, equation: equation, steps: steps, solutions: features.isEmpty ? [t(headline)] : features,
                        note: nil, f: f ?? { _ in .nan }, roots: [])
        d.title = "Features"
        d.graph = Graph(xName: x, yName: label, curves: [curve], points: points.filter { abs($0.x) < 1e6 && abs($0.y) < 1e6 })
        // A curve that turns opens on its turning points and intercepts, with room round them, and not
        // on the far larger values it reaches beside them: y = x³ − 3x between −4 and 4, not −40 and 40.
        if f != nil, case .curve = shape, points.count >= 2, let lowY = points.map(\.y).min(), let highY = points.map(\.y).max(), highY - lowY > 1e-9 {
            let lowX = points.map(\.x).min()!, highX = points.map(\.x).max()!
            let padX = max(1, 0.4 * (highX - lowX)), padY = max(1, 0.6 * (highY - lowY))
            d.graph?.frame = ((Double(lowX) - padX)...(Double(highX) + padX), (Double(lowY) - padY)...(Double(highY) + padY))
        }
        return d
    }

    // Copying gives the curve's equation, as it was understood.
    var copyText: String { equation.plain }
}
