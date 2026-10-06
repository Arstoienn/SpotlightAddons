import Foundation

// What the card opens into: the equation typeset, the key steps to the answer, every solution,
// and the function to plot with its roots marked.

struct Step {
    var label: String       // "Factorising"
    var math: Math?         // (2n + 1)(n + 1) = 0
    var note: String? = nil // a sentence, where the step is a method rather than a line of algebra
}

struct Details {
    var name: String
    var equation: Math
    var steps: [Step]
    var solutions: [Math]
    var note: String?           // "A further 306 solutions lie in the interval −1000 ≤ n ≤ 1000."
    var f: (Double) -> Double   // left side minus right side
    var roots: [Double]         // the solutions listed, to mark on the plot
    var graph: Graph? = nil      // none for a value worked out, which has nothing to plot
    var whole: String? = nil     // what copying any line of the solutions gives, where they are one value over several lines
}

// Lines and curves in the plane, and the points where they cross. One equation is drawn as its
// two sides, y = left and y = right; a system as one line per equation.
struct Graph {
    struct Curve {
        enum Shape {
            case function((Double) -> Double)   // y as a function of x
            case vertical(Double)               // x = a constant
            case implicit((Double, Double) -> Double)   // where g(x, y) = 0: a circle, say
        }
        var shape: Shape
        var label: Math
    }
    var xName: String
    var yName: String
    var curves: [Curve]
    var points: [CGPoint]
}

extension Solver {
    static func details(_ typed: String) -> Details? {
        if let hash = Hash.parse(typed) { return hash.details }
        guard let typed = Hash.numbers(in: typed) else { return nil }
        let input = Latex.plain(typed)
        if LinearSystem.parts(input).count >= 2 { return LinearSystem.parse(input)?.details ?? NonlinearSystem.parse(input)?.details }
        if Options.numberFacts, let number = NumberFacts.parse(input) { return number.details }
        if let comparison = Comparison.parse(input) { return comparison.details }
        if let evaluation = Evaluation.parse(input, hadLatex: typed.contains("\\")) { return evaluationDetails(evaluation) }
        guard let eq = try? Parser.parse(input) else { return nil }
        let n = eq.unknown
        let (leftMath, rightMath) = (typeset(eq.left, n), typeset(eq.right, n))
        let header = row(leftMath, t(" = "), rightMath)
        let f = { (x: Double) in eq.left.eval(x) - eq.right.eval(x) }
        // With a physical constant in it, the equation is worked on with the value written in,
        // and in decimals: the constant is only a few figures itself.
        let constants = eq.constants
        let worked = Equation(left: eq.left.withValues, right: eq.right.withValues, unknown: n)
        let written = constants.isEmpty ? header : row(typeset(worked.left, n), t(" = "), typeset(worked.right, n))
        var d: Details
        if let l = poly(worked.left), let r = poly(worked.right) {
            d = polynomialDetails(trim(sub(l, r)), n, written, f, exact: constants.isEmpty && Options.exact)
        } else {
            d = numericDetails(worked, n, written, f)
        }
        if !constants.isEmpty {
            d.equation = header
            d.steps.insert(Step(label: "Substituting " + Constants.values(constants), math: written), at: 0)
        }
        // x_1 = 10 is its own answer, shown for the sake of its subscript: there is no working.
        if case .unknown = eq.left, case .num = eq.right { d.steps = [] }
        // A height that is only rounding noise is marked as zero. Nothing is drawn at all round
        // the mass of the Earth or the charge on an electron: there is no scale to draw it to.
        let points = d.roots.map { x in
            let y = eq.left.eval(x)
            return CGPoint(x: x, y: abs(y) < 1e-12 ? 0 : y)
        }
        if points.allSatisfy({ ($0.x == 0 || abs($0.x) > 1e-9) && abs($0.x) < 1e12 && !(abs($0.y) >= 1e12) }) {
            d.graph = Graph(xName: n, yName: "y",
                            curves: [Graph.Curve(shape: .function { eq.left.eval($0) }, label: row(t("y = "), leftMath)),
                                     Graph.Curve(shape: .function { eq.right.eval($0) }, label: row(t("y = "), rightMath))],
                            points: points)
        }
        return d
    }
}

// MARK: - Values worked out

// Arithmetic done the way it is on paper: every operation whose inputs are already numbers is
// done at once, and the expression written out again, until one number is left. The nested
// fractions of a PES calculation come down subtraction, then division, then division.
func evaluationDetails(_ ev: Evaluation) -> Details {
    // With no name the sum stands by itself, and each line of working begins with its "=".
    let lead = ev.name.map { "\($0) = " } ?? "= "
    var d = Details(name: ev.name ?? "", equation: row(t(ev.name == nil ? "" : lead), typeset(ev.expr, "")), steps: [], solutions: [],
                    note: nil, f: { _ in .nan }, roots: [])
    // A sum on its own is written out term by term, each term worked out, then added up.
    if case .sum(let k, let from, let to, let body, let product) = ev.expr,
       let range = Expr.range(from.eval(0), to.eval(0)), !range.isEmpty {
        let all = Array(range)
        let shown: [Int?] = all.count <= 6 ? all : Array(all.prefix(3)) + [nil] + Array(all.suffix(2))
        func line(_ term: (Int) -> Math) -> Math {
            var parts: [Math] = [t(lead)]
            for (i, n) in shown.enumerated() {
                if i > 0 { parts.append(t(product ? " × " : " + ")) }
                parts.append(n.map(term) ?? t("…"))
            }
            return .row(parts)
        }
        d.steps.append(Step(label: product ? "Writing out the factors" : "Writing out the terms", math: line { termMath(body.setting(k, to: Double($0))) }))
        if case .index = body {} else {
            d.steps.append(Step(label: product ? "Evaluating each factor" : "Evaluating each term", math: line { t(decimal(body.setting(k, to: Double($0)).eval(0))) }))
        }
        d.steps.append(Step(label: product ? "Multiplying the factors" : "Adding the terms", math: t(lead + decimal(ev.value))))
        d.solutions = evaluationSolutions(ev)
        return d
    }

    var e = ev.expr
    // A physical constant is first written in as its value.
    let constants = e.constants
    if !constants.isEmpty {
        e = e.withValues
        d.steps.append(Step(label: "Substituting " + Constants.values(constants), math: row(t(lead), typeset(e, ""))))
    }
    while true {
        let factorials = readyFactorials(e)
        let (next, done) = reduceOnce(e)
        e = next
        guard !done.isEmpty else { break }
        d.steps.append(Step(label: reductionLabel(done, factorials: factorials), math: row(t(lead), typeset(e, ""))))
    }
    d.solutions = evaluationSolutions(ev)
    return d
}

// The value, and its decimal where the card gives one. What was taken for a constant is in the
// working, not among the answers.
private func evaluationSolutions(_ ev: Evaluation) -> [Math] {
    guard let solution = ev.solution else { return [] }
    guard let approx = solution.approx, ev.expr.constants.isEmpty else { return [t(solution.exact)] }
    return [t(solution.exact), t(approx)]
}

// What a round of reduceOnce did, as the title of its step: "Multiplying", or "Simplifying" where
// it did more than one kind of thing.
func reductionLabel(_ done: Set<Character>, factorials: Int) -> String {
    let names: [Character: String] = ["+": "Adding", "-": "Subtracting", "*": "Multiplying", "/": "Dividing", "^": "Evaluating the power",
                                      "f": "Evaluating the function", "!": "Evaluating the factorial", "s": "Evaluating the sum",
                                      "°": "Converting to radians"]
    if done == ["!"], factorials > 1 { return "Evaluating the factorials" }
    return done.count == 1 ? names[done.first!] ?? "Simplifying" : "Simplifying"
}

// One round: every operation on numbers alone is replaced by its result. Returns which kinds of
// operation were done ("f" for a function, "!" for a factorial); a lone minus on a number is
// folded in silently.
func reduceOnce(_ e: Expr) -> (Expr, Set<Character>) {
    switch e {
    case .num, .unknown, .index, .constant:
        return (e, [])
    case .sum:
        return e.hasUnknown ? (e, []) : (.num(e.eval(0)), ["s"])
    case .neg(let a):
        if case .num(let v) = a { return (.num(-v), []) }
        let (r, done) = reduceOnce(a)
        if case .num(let v) = r, done.isEmpty { return (.num(-v), []) }
        return (.neg(r), done)
    case .op(let o, let a, let b):
        if case .num = a, case .num = b { return (.num(e.eval(0)), [o]) }
        let (l, dl) = reduceOnce(a), (r, dr) = reduceOnce(b)
        return (.op(o, l, r), dl.union(dr))
    case .call(let f, let a):
        if case .num = a { return (.num(e.eval(0)), [f == "fact" ? "!" : f == "deg" ? "°" : "f"]) }
        let (r, done) = reduceOnce(a)
        return (.call(f, r), done)
    }
}

// How many factorials are of plain numbers, to be worked out in the next round.
func readyFactorials(_ e: Expr) -> Int {
    switch e {
    case .call("fact", .num): return 1
    case .neg(let a), .call(_, let a): return readyFactorials(a)
    case .op(_, let a, let b): return readyFactorials(a) + readyFactorials(b)
    default: return 0
    }
}

// MARK: - Polynomials

private let negativeSquare = "The square of a real number is never negative; the equation therefore has no real solution."
private let negativeDiscriminant = "The discriminant is negative; the equation therefore has no real solution."

// exact: whole-number coefficients are worked in fractions and surds. Without it, as when a
// physical constant has gone in, everything is in decimals.
func polynomialDetails(_ p: Poly, _ n: String, _ header: Math, _ f: @escaping (Double) -> Double, exact: Bool = true) -> Details {
    var d = Details(name: n, equation: header, steps: [], solutions: [], note: nil, f: f, roots: [])
    switch p.count {
    case 0:
        d.steps = [Step(label: "Simplifying", math: t("0 = 0"), note: "This holds for every real value of \(n).")]
        d.solutions = [t("\(n) ∈ ℝ")]
        return d
    case 1:
        d.steps = [Step(label: "Simplifying", math: t("\(decimal(p[0])) = 0"), note: "This is a contradiction; no value of \(n) satisfies the equation.")]
        d.solutions = [t("No solution")]
        return d
    default:
        break
    }

    guard exact, var c = integerCoefficients(p), c.count <= 3 else {
        let p = p.last! < 0 ? p.map { -$0 } : p
        let roots = realRoots(p).sorted()
        let standard = row(polyMath(p, n), t(" = 0"))
        if standard.plain != header.plain { d.steps.append(Step(label: "Writing in standard form", math: standard)) }
        if p.count <= 3 {
            d.steps += decimalSteps(p, n)
        } else if let factored = rationalFactors(p, roots, n) {
            d.steps.append(Step(label: "Factorising", math: row(factored, t(" = 0"))))
        } else {
            d.steps.append(Step(label: "Solving numerically", math: nil,
                                note: "This polynomial of degree \(p.count - 1) is not readily factorised; its real roots are therefore determined numerically."))
        }
        d.roots = roots
        d.solutions = roots.isEmpty ? [t("No real solutions")] : roots.map { solutionLine(n, $0) }
        return d
    }
    if c.last! < 0 { c = c.map { -$0 } }
    let standard = row(polyMath(c.map(Double.init), n), t(" = 0"))
    if standard.plain != header.plain { d.steps.append(Step(label: "Writing in standard form", math: standard)) }

    if c.count == 2 {
        let (b, a) = (c[0], c[1])
        let root = fractionMath(-b, a)
        if a == 1 {
            d.steps.append(Step(label: "Hence", math: row(t("\(n) = "), root)))
        } else {
            d.steps.append(Step(label: "Rearranging", math: t("\(a)\(n) = \(minus(-b))")))
            d.steps.append(Step(label: "Dividing by \(a)", math: row(t("\(n) = "), root)))
        }
        d.roots = [-Double(b) / Double(a)]
        d.solutions = [exactLine(n, root, d.roots[0])]
        return d
    }

    let (cc, b, a) = (c[0], c[1], c[2])
    let disc = b * b - 4 * a * cc
    let (k, m) = disc > 0 ? squareFactor(disc) : (0, disc == 0 ? 1 : 0)   // a double root counts as rational

    if disc >= 0, m == 1 {
        // Rational roots p/q: the polynomial is (q₁x − p₁)(q₂x − p₂).
        let r1 = reduced(-b - k, 2 * a), r2 = reduced(-b + k, 2 * a)
        let factored: Math = disc == 0 ? .power(t(linearFactor(r1, n)), t("2")) : t(linearFactor(r1, n) + linearFactor(r2, n))
        d.steps.append(Step(label: "Factorising", math: row(factored, t(" = 0"))))
        func value(_ r: (Int, Int)) -> Double { Double(r.0) / Double(r.1) }
        let values: [(Int, Int)] = disc == 0 ? [r1] : (value(r1) < value(r2) ? [r1, r2] : [r2, r1])
        var answer: [Math] = []
        for (i, v) in values.enumerated() {
            answer += [t((i == 0 ? "" : " or ") + "\(n) = "), fractionMath(v.0, v.1)]
        }
        d.steps.append(Step(label: "Hence", math: .row(answer)))
        d.roots = values.map(value)
        d.solutions = zip(values, d.roots).map { exactLine(n, fractionMath($0.0, $0.1), $1) }
        return d
    }

    if b == 0 {
        // ax² + c = 0: x² = −c/a, then a square root.
        d.steps.append(Step(label: "Isolating \(n)²", math: row(squared(n), t(" = "), fractionMath(-cc, a))))
        guard disc > 0 else {
            d.steps.append(Step(label: "Hence", math: row(squared(n), t(" < 0")),
                                note: negativeSquare))
            d.solutions = [t("No real solutions"), t("Complex solutions: \(n) = ±\(imaginary(a, disc))")]
            return d
        }
        let (_, kk, _, den) = radicalForm(a, 0, disc)
        let radical = radicalMath(kk, m)
        let root: Math = den == 1 ? radical : .fraction(radical, t("\(den)"))
        d.steps.append(Step(label: "Taking the square root", math: row(t("\(n) = ±"), root)))
        let v = Double(disc).squareRoot() / Double(2 * a)
        d.roots = [-v, v]
        d.solutions = [row(t("\(n) = −"), root, t(" ≈ \(decimal(-v))")), row(t("\(n) = "), root, t(" ≈ \(decimal(v))"))]
        return d
    }

    d.steps.append(Step(label: "Evaluating the discriminant",
                        math: row(squared("b"), t(" − 4ac = "), .power(t(paren(b)), t("2")),
                                  t(" − 4·\(paren(a))·\(paren(cc)) = \(minus(disc))"))))
    guard disc > 0 else {
        d.steps.append(Step(label: "Hence", math: row(squared("b"), t(" − 4ac < 0")),
                            note: negativeDiscriminant))
        d.solutions = [t("No real solutions"), row(t("Complex solutions: \(n) = "), fractionMath(-b, 2 * a), t(" ± \(imaginary(a, disc))"))]
        return d
    }
    let (bb, kk, _, den) = radicalForm(a, b, disc)
    let radical = radicalMath(kk, m)
    func over(_ sign: String) -> Math {
        let top = row(t("\(minus(bb)) \(sign) "), radical)
        return den == 1 ? top : .fraction(top, t("\(den)"))
    }
    let formula = Math.fraction(row(t("−b ± "), .root(row(squared("b"), t(" − 4ac")))), t("2a"))
    d.steps.append(Step(label: "Applying the quadratic formula", math: row(t("\(n) = "), formula, t(" = "), over("±"))))
    let s = Double(disc).squareRoot()
    let values = [(-Double(b) - s) / Double(2 * a), (-Double(b) + s) / Double(2 * a)]
    d.roots = values.sorted()
    d.solutions = zip([over("−"), over("+")], values).sorted { $0.1 < $1.1 }
        .map { row(t("\(n) = "), $0.0, t(" ≈ \(decimal($0.1))")) }
    return d
}

// A linear or quadratic equation with decimal coefficients, the leading one positive: worked as
// one with whole numbers is, in decimals throughout.
func decimalSteps(_ p: Poly, _ n: String) -> [Step] {
    // 3×10⁸ is bracketed where it is squared or multiplied, and not run together with a letter.
    func bracketed(_ v: Double) -> String {
        let text = decimal(v)
        return v < 0 || text.contains("×") ? "(\(text))" : text
    }
    func times(_ v: Double) -> String {
        let text = decimal(v)
        return text.contains("×") ? text + "·" : text
    }

    if p.count == 2 {
        let (b, a) = (p[0], p[1])
        let answer = t("\(n) \(approxOrEqual(-b / a))")
        if a == 1 { return [Step(label: "Hence", math: answer)] }
        return [Step(label: "Rearranging", math: t("\(times(a))\(n) = \(decimal(-b))")),
                Step(label: "Dividing by \(decimal(a))", math: answer)]
    }

    let (c, b, a) = (p[0], p[1], p[2])
    if b == 0 {
        let square = -c / a
        let isolated = Step(label: "Isolating \(n)²", math: row(squared(n), t(" = \(decimal(square))")))
        guard square >= 0 else {
            return [isolated, Step(label: "Hence", math: row(squared(n), t(" < 0")), note: negativeSquare)]
        }
        let root = square.squareRoot()
        return [isolated, Step(label: "Taking the square root",
                               math: t("\(n) \(isExact(root) ? "=" : "≈") \(root == 0 ? "" : "±")\(decimal(root))"))]
    }

    let disc = added(b * b, -4 * a * c)
    let discriminant = Step(label: "Evaluating the discriminant",
                            math: row(squared("b"), t(" − 4ac = "), .power(t(bracketed(b)), t("2")),
                                      t(" − 4·\(bracketed(a))·\(bracketed(c)) = \(decimal(disc))")))
    guard disc >= 0 else {
        return [discriminant, Step(label: "Hence", math: row(squared("b"), t(" − 4ac < 0")), note: negativeDiscriminant)]
    }
    let formula = Math.fraction(row(t("−b ± "), .root(row(squared("b"), t(" − 4ac")))), t("2a"))
    let values = Math.fraction(row(t("\(decimal(-b)) ± "), .root(t(decimal(disc)))), t(decimal(2 * a)))
    return [discriminant, Step(label: "Applying the quadratic formula", math: row(t("\(n) = "), formula, t(" = "), values))]
}

// p/q in lowest terms with q > 0.
func reduced(_ p: Int, _ q: Int) -> (Int, Int) {
    let g = max(gcd(p, q), 1)
    return q < 0 ? (-p / g, -q / g) : (p / g, q / g)
}

// The factor that is zero at p/q: qx − p, written (2n + 1), (n − 3) or n.
func linearFactor(_ r: (Int, Int), _ n: String) -> String {
    let (p, q) = r
    if p == 0 { return q == 1 ? n : "\(q)\(n)" }
    return "(\(q == 1 ? "" : "\(q)")\(n) \(p < 0 ? "+" : "−") \(abs(p)))"
}

func radicalMath(_ k: Int, _ m: Int) -> Math { k == 1 ? .root(t("\(m)")) : row(t("\(k)"), .root(t("\(m)"))) }

// For degree three and up: (x − 1)(x − 2)(x − 3) when every root is rational and they account
// for the whole degree.
func rationalFactors(_ p: Poly, _ roots: [Double], _ n: String) -> Math? {
    guard roots.count == p.count - 1 else { return nil }
    var factors: [(Int, Int)] = []
    var product: Poly = [1]
    for r in roots {
        guard let (num, den) = rational(r), den <= 100 else { return nil }
        factors.append((num, den))
        product = mul(product, [-Double(num), Double(den)])
    }
    // What is left over is a constant, the same for every coefficient.
    let scale = p.last! / product.last!
    guard zip(p, product).allSatisfy({ abs($0 - $1 * scale) <= 1e-9 * max(1, abs($0)) }) else { return nil }
    let lead = scale == 1 ? "" : scale == -1 ? "−" : decimal(scale)
    return t(lead + factors.map { linearFactor($0, n) }.joined())
}

func imaginary(_ a: Int, _ disc: Int) -> String {
    let v = Double(-disc).squareRoot() / Double(2 * abs(a))
    return (v == 1 ? "" : decimal(v)) + "i"
}

func paren(_ n: Int) -> String { n < 0 ? "(\(minus(n)))" : "\(n)" }

func exactLine(_ n: String, _ exact: Math, _ value: Double) -> Math {
    exact.hasFraction ? row(t("\(n) = "), exact, t(" ≈ \(decimal(value))")) : row(t("\(n) = "), exact)
}

func solutionLine(_ n: String, _ x: Double) -> Math {
    t(isExact(x) ? "\(n) = \(decimal(x))" : "\(n) ≈ \(decimal(x))")
}

// MARK: - Everything else

func numericDetails(_ eq: Equation, _ n: String, _ header: Math, _ f: @escaping (Double) -> Double) -> Details {
    var d = Details(name: n, equation: header, steps: [], solutions: [], note: nil, f: f, roots: [])
    d.steps += closedForm(eq, n)
    if let trig = trigEquation(eq) { d.steps += trigSteps(trig, n, header) }
    if d.steps.isEmpty {
        let rightIsZero = poly(eq.right).map(trim)?.isEmpty == true
        let difference = typeset(rightIsZero ? eq.left : .op("-", eq.left, eq.right), n)
        d.steps = [Step(label: "Solving numerically", math: row(difference, t(" = 0")),
                        note: "Each root is located by a change of sign and thereafter refined by bisection.")]
    }

    // b^x = c, ln x = c, log x = c and √x = c have the one solution the working has just found.
    if let root = closedRoot(eq) {
        if root.value.isFinite, root.value != 0 || root.power == nil {
            d.roots = [root.value]
            d.solutions = [solutionLine(n, root.value)]
            return d
        }
        if let power = root.power {
            d.solutions = [row(t("\(n) = "), power)]
            d.note = "This is too \(root.value == 0 ? "small" : "large") to be written out as a decimal."
            return d
        }
    }

    let roots = numericRoots(eq) ?? []
    guard !roots.isEmpty else {
        d.solutions = [t("No real solutions in the interval −1000 ≤ \(n) ≤ 1000")]
        return d
    }
    // An angle is given for one turn from zero, in degrees and in radians; the general solution
    // has the rest.
    let unit = angleUnit(eq)
    let turn = unit.map { unit in roots.filter { $0 >= 0 && $0 <= unit.turn * (1 + 1e-12) }.sorted() } ?? []
    if let unit, !turn.isEmpty {
        d.roots = Array(turn.prefix(12))
        d.solutions = d.roots.map { angleLine(n, $0, unit) }
        if turn.count > 12 {
            d.note = "The first twelve of the \(turn.count) solutions for \(unit.range(n)) are shown."
        } else if roots.count > turn.count {
            d.note = "These are the solutions for \(unit.range(n)); further solutions lie outside this interval."
        }
        return d
    }
    // Up to twelve, nearest zero first; the rest are counted.
    let shown = Array(roots.sorted { abs($0) < abs($1) }.prefix(12)).sorted()
    d.roots = shown
    d.solutions = shown.map { x in unit.map { angleLine(n, x, $0) } ?? solutionLine(n, x) }
    if roots.count > shown.count {
        let more = roots.count - shown.count
        d.note = (more == 1 ? "One further solution lies" : "A further \(more) solutions lie") + " in the interval −1000 ≤ \(n) ≤ 1000."
    }
    return d
}

// One side a function of the unknown alone, the other a constant: b^x = c, ln x = c, √x = c;
// swapped when the unknown was typed on the right.
func isolated(_ eq: Equation) -> (Expr, Double, swapped: Bool)? {
    for (side, other, swapped) in [(eq.left, eq.right, false), (eq.right, eq.left, true)] {
        if let c = poly(other).map(trim), c.count <= 1 { return (side, c.first ?? 0, swapped) }
    }
    return nil
}

// The solution of b^x = c, ln x = c, log x = c or √x = c, worked out directly rather than
// searched for. Where it is beyond what a decimal can hold, as 10⁴⁹⁹ is, the power is the answer.
func closedRoot(_ eq: Equation) -> (value: Double, power: Math?)? {
    guard let (side, c, _) = isolated(eq) else { return nil }
    switch side {
    case .op("^", .num(let b), .unknown) where b > 0 && b != 1 && c > 0: return (log(c) / log(b), nil)
    case .call("ln", .unknown): return (exp(c), .power(t("e"), t(decimal(c))))
    case .call("log", .unknown): return (pow(10, c), .power(t("10"), t(decimal(c))))
    case .call("sqrt", .unknown) where c >= 0: return (c * c, nil)
    default: return nil
    }
}

// What the copy button and Return put on the pasteboard: the answer as another program would
// read it, 2.5 for 10/4 and for 4x = 10, each root of an equation with a comma between, the
// digest of a hash. Nothing for a number typed by itself, which has no answer but itself.
extension Solver {
    static func copy(_ typed: String) -> String? {
        func number(_ x: Double) -> String { x == 0 ? "0" : String(format: "%.12g", x) }
        func plain(_ s: String) -> String { s.replacingOccurrences(of: "−", with: "-") }
        if let hash = Hash.parse(typed) { return hash.written }
        // As shown, where that is asked for: the card's own line, without the "x = " before a
        // single answer.
        if Options.copyAsShown {
            guard let shown = solve(typed)?.exact else { return nil }
            if let sign = shown.range(of: "= ") ?? shown.range(of: "≈ "), !shown[sign.upperBound...].contains("=") {
                return plain(String(shown[sign.upperBound...]))
            }
            return plain(shown)
        }
        guard let numbered = Hash.numbers(in: typed) else { return nil }
        let input = Latex.plain(numbered)
        if LinearSystem.parts(input).count < 2 {
            if NumberFacts.parse(input) != nil { return nil }
            if let comparison = Comparison.parse(input) { return comparison.holds ? "True" : "False" }
            if let evaluation = Evaluation.parse(input, hadLatex: numbered.contains("\\")) {
                return evaluation.value.isFinite ? number(evaluation.value) : nil
            }
        }
        guard let answer = solve(typed), let d = details(typed) else { return nil }
        return d.roots.isEmpty ? plain(answer.exact) : d.roots.map(number).joined(separator: ", ")
    }
}

// The one number an answer is, for ans to be next time: what was worked out, or the root of an
// equation that has just the one. Nil for anything else.
extension Solver {
    static func value(_ typed: String) -> Double? {
        guard Hash.parse(typed) == nil, let numbered = Hash.numbers(in: typed) else { return nil }
        let input = Latex.plain(numbered)
        guard LinearSystem.parts(input).count < 2, NumberFacts.parse(input) == nil, Comparison.parse(input) == nil else { return nil }
        if let evaluation = Evaluation.parse(input, hadLatex: numbered.contains("\\")) {
            return evaluation.value.isFinite ? evaluation.value : nil
        }
        guard let d = details(typed), d.roots.count == 1 else { return nil }
        return d.roots[0]
    }
}

// The working for b^x = c, ln x = c, log x = c and √x = c, as it would be written out: the
// unknown brought to the left first, then one move per line.
func closedForm(_ eq: Equation, _ n: String) -> [Step] {
    guard let (side, c, swapped) = isolated(eq) else { return [] }
    let cText = decimal(c)
    var steps: [Step] = []
    if swapped { steps.append(Step(label: "Interchanging the sides", math: row(typeset(side, n), t(" = \(cText)")))) }

    switch side {
    case .op("^", .num(let b), .unknown) where b > 0 && b != 1 && c > 0:
        return steps + exponentialSteps(b, c, n)
    // e⁸⁰⁰ and 10⁴⁹⁹ are left as they are: there is no decimal to go on to.
    case .call("ln", .unknown):
        let value = exp(c), written = value.isFinite && value != 0
        return steps + [Step(label: "Rewriting in exponential form", math: row(t("\(n) = "), .power(t("e"), t(cText))))]
            + (written ? [Step(label: "Hence", math: t("\(n) \(approxOrEqual(value))"))] : [])
    case .call("log", .unknown):
        let value = pow(10, c), written = value.isFinite && value != 0
        return steps + [Step(label: "Rewriting in exponential form", math: row(t("\(n) = "), .power(t("10"), t(cText))))]
            + (written ? [Step(label: "Hence", math: t("\(n) \(approxOrEqual(value))"))] : [])
    case .call("sqrt", .unknown) where c >= 0:
        return steps + [Step(label: "Squaring both sides", math: row(t("\(n) = "), .power(t(cText), t("2")))),
                        Step(label: "Hence", math: t("\(n) \(approxOrEqual(c * c))"))]
    default:
        return []
    }
}

// bˣ = c. When b and c are both whole powers of one base, as 0.1 = 10⁻¹ and 10 = 10¹ are, the
// exponents are compared directly; otherwise logarithms bring the x down.
func exponentialSteps(_ b: Double, _ c: Double, _ n: String) -> [Step] {
    let bText = decimal(b), cText = decimal(c)
    func power(_ base: String, _ exponent: String) -> Math { .power(t(base), t(exponent)) }

    if let (base, p, q) = commonBase(b, c) {
        let B = "\(base)"
        var steps: [Step] = []
        let left = p == 1 ? power(B, n) : .power(row(t("("), power(B, minus(p)), t(")")), t(n))
        steps.append(Step(label: "Expressing both sides as powers of \(B)", math: row(left, t(" = "), power(B, minus(q)))))
        let exponent = p == 1 ? n : p == -1 ? "−\(n)" : "\(minus(p))\(n)"
        if p != 1 {
            steps.append(Step(label: "Multiplying the exponents", math: row(power(B, exponent), t(" = "), power(B, minus(q)))))
        }
        steps.append(Step(label: "Equating the exponents", math: t("\(exponent) = \(minus(q))")))
        if p != 1 { steps.append(Step(label: "Hence", math: row(t("\(n) = "), fractionMath(q, p)))) }
        return steps
    }

    if b == M_E {
        return [Step(label: "Taking the natural logarithm of both sides", math: row(t("ln("), power("e", n), t(") = ln \(cText)"))),
                Step(label: "Simplifying", math: t("\(n) = ln \(cText)")),
                Step(label: "Hence", math: t("\(n) \(approxOrEqual(log(c)))"))]
    }
    return [Step(label: "Taking the logarithm of both sides", math: row(t("ln("), power(bText, n), t(") = ln \(cText)"))),
            Step(label: "Applying the power rule for logarithms", math: t("\(n)·ln \(bText) = ln \(cText)")),
            Step(label: "Dividing by ln \(bText)", math: row(t("\(n) = "), .fraction(t("ln \(cText)"), t("ln \(bText)")))),
            Step(label: "Hence", math: t("\(n) \(approxOrEqual(log(c) / log(b)))"))]
}

// The smallest whole base B, up to 100, with b = Bᵖ and c = Bᵠ for whole p ≠ 0 and q.
func commonBase(_ b: Double, _ c: Double) -> (Int, Int, Int)? {
    for base in 2...100 {
        let p = log(b) / log(Double(base)), q = log(c) / log(Double(base))
        let (pr, qr) = (p.rounded(), q.rounded())
        guard abs(p - pr) < 1e-9, abs(q - qr) < 1e-9, pr != 0, abs(pr) <= 30, abs(qr) <= 30 else { continue }
        return (base, Int(pr), Int(qr))
    }
    return nil
}

func approxOrEqual(_ x: Double) -> String { isExact(x) ? "= \(decimal(x))" : "≈ \(decimal(x))" }

// MARK: - Angles

enum AngleUnit {
    case degrees, radians

    var turn: Double { self == .degrees ? 360 : 2 * .pi }
    func range(_ n: String) -> String { self == .degrees ? "0° ≤ \(n) ≤ 360°" : "0 ≤ \(n) ≤ 2π" }
}

// sin, cos or tan, whether it works in radians or, as sin°, in degrees.
func trigFunction(_ f: String) -> (name: String, unit: AngleUnit)? {
    let name = f.hasSuffix("°") ? String(f.dropLast()) : f
    return Angle.functions.contains(name) ? (name, f.hasSuffix("°") ? .degrees : .radians) : nil
}

// Whether the unknown is an angle, and in what: it appears only inside sin, cos and tan, as x or
// 2x + 1 and not as x², and in the one unit throughout. Such an equation is answered for one
// turn from zero, in degrees and in radians.
func angleUnit(_ eq: Equation) -> AngleUnit? {
    var units: Set<AngleUnit> = []
    func angular(_ e: Expr) -> Bool {
        switch e {
        case .unknown: return false
        case .num, .index, .constant: return true
        case .neg(let a): return angular(a)
        case .op(_, let a, let b): return angular(a) && angular(b)
        case .call(let f, let a):
            if let (_, unit) = trigFunction(f), poly(a).map(trim)?.count == 2 {
                units.insert(unit)
                return true
            }
            return angular(a)
        case .sum(_, let from, let to, let body, _): return angular(from) && angular(to) && angular(body)
        }
    }
    guard angular(eq.left), angular(eq.right), units.count == 1 else { return nil }
    return units.first
}

// Degrees first, "x = 30° (π/6)" and "x ≈ 14.6867° (0.256 rad)", where the unknown is in them;
// "x = π/6 ≈ 0.524 (30°)" and "x ≈ 0.256332 (14.6867°)" where it is in radians.
func angleLine(_ n: String, _ x: Double, _ unit: AngleUnit) -> Math {
    guard unit == .degrees else {
        let degrees = "(\(decimal(x * 180 / .pi))°)"
        guard Options.exact, let fraction = piFraction(x), fraction.plain != "0" else {
            return t("\(n) \(isExact(x) ? "=" : "≈") \(decimal(x)) \(degrees)")
        }
        return row(t("\(n) = "), fraction, t(" ≈ \(threePlaces(x)) \(degrees)"))
    }
    let radians = x * .pi / 180, start = "\(n) \(wholeDegrees(x) ? "=" : "≈") \(degreesText(x))"
    if x == 0 { return t(start) }
    guard Options.exact, let fraction = piFraction(radians) else { return t("\(start) (\(threePlaces(radians)) rad)") }
    return row(t("\(start) ("), fraction, t(")"))
}

// 180 is found as 179.9999997 where the curve only touches: that is a whole number of degrees.
func wholeDegrees(_ x: Double) -> Bool { abs(x - x.rounded()) < 1e-6 }
func degreesText(_ x: Double) -> String { decimal(wholeDegrees(x) ? x.rounded() : x) + "°" }

// The card for an angle: the unit it was asked in on the first line, the other underneath.
func angleCard(_ name: String, _ shown: [Double], more: Bool, _ unit: AngleUnit) -> Solution {
    let rest = more ? ", …" : ""
    let radians = unit == .degrees ? shown.map { $0 * .pi / 180 } : shown
    let degrees = unit == .degrees ? shown : shown.map { $0 * 180 / .pi }
    // π/6 where every one of them is such a part of π: a list half in π and half in decimals reads badly.
    let fractions = radians.compactMap(piFraction).map(\.plain)
    let inPi = Options.exact && fractions.count == shown.count && fractions.contains { $0 != "0" }
    let whole = degrees.allSatisfy(wholeDegrees)
    let degreeList = "\(whole ? "=" : "≈") \(degrees.map(degreesText).joined(separator: ", "))\(rest)"
    if unit == .degrees {
        let radianList = inPi ? "= \(fractions.joined(separator: ", "))" : "≈ \(radians.map(threePlaces).joined(separator: ", "))"
        return Solution(exact: "\(name) \(degreeList)", approx: "\(radianList)\(rest) rad, for \(unit.range(name))")
    }
    let values = (inPi ? fractions : shown.map(decimal)).joined(separator: ", ")
    let decimals = inPi ? "≈ \(shown.map(threePlaces).joined(separator: ", "))\(rest) " : ""
    return Solution(exact: "\(name) \(inPi || shown.allSatisfy(isExact) ? "=" : "≈") \(values)\(rest)",
                    approx: "\(decimals)\(degreeList), for \(unit.range(name))")
}

// An angle found numerically that is π/6, 5π/4 or the like, to as many figures as it was found.
// A whole number of degrees is so many 180ths of π, so 39° is 13π/60.
func piFraction(_ x: Double) -> Math? {
    let fraction = piMath(x, within: 1e-7)
    if fraction.plain.contains("π") || fraction.plain == "0" { return fraction }
    let degrees = x * 180 / .pi
    guard abs(degrees - degrees.rounded()) < 1e-6, abs(degrees) < 1e6 else { return nil }
    return piMultiple(Int(degrees.rounded()), 180)
}

func threePlaces(_ x: Double) -> String { x == 0 ? "0" : String(format: "%.3f", x).replacingOccurrences(of: "-", with: "−") }

// An equation that comes down to sin(ax + b) = c, or the same of cos or tan: there is one such
// function of the unknown in it, and nothing is done to that but multiplying and adding, as in
// 20²·sin(2x)/9.81 = 20.
struct TrigEquation {
    var fn: String       // sin
    var unit: AngleUnit  // what its angle is in
    var call: Expr       // sin(2x)
    var argument: Expr   // 2x
    var a: Double, b: Double, c: Double
}

func trigEquation(_ eq: Equation) -> TrigEquation? {
    // The equation with sin(2x) taken as the unknown, to be solved for it as a linear equation.
    var calls: [(String, Expr)] = []
    var stray = false
    func lifted(_ e: Expr) -> Expr {
        switch e {
        case .unknown:
            stray = true
            return e
        case .num, .index, .constant, .sum: return e
        case .neg(let a): return .neg(lifted(a))
        case .op(let o, let a, let b): return .op(o, lifted(a), lifted(b))
        case .call(let f, let a):
            guard trigFunction(f) != nil, a.hasUnknown else { return .call(f, lifted(a)) }
            calls.append((f, a))
            return .unknown
        }
    }
    guard !eq.left.hasSum, !eq.right.hasSum else { return nil }
    let (left, right) = (lifted(eq.left), lifted(eq.right))
    guard !stray, calls.count == 1, let (f, argument) = calls.first, let (fn, unit) = trigFunction(f),
          let inner = poly(argument).map(trim), inner.count == 2,
          let l = poly(left), let r = poly(right) else { return nil }
    let line = trim(sub(l, r))
    guard line.count == 2 else { return nil }
    return TrigEquation(fn: fn, unit: unit, call: .call(f, argument), argument: argument, a: inner[1], b: inner[0], c: -line[0] / line[1])
}

// The angles within one period at which the function is c, and the period; none when c is out
// of its range.
func trigAngles(_ fn: String, _ c: Double) -> (angles: [Double], period: Double)? {
    switch fn {
    case "tan":
        return ([atan(c)], .pi)
    case "sin":
        guard abs(c) <= 1 else { return nil }
        if c == 0 { return ([0], .pi) }
        return (abs(c) == 1 ? [asin(c)] : [asin(c), .pi - asin(c)], 2 * .pi)
    default:
        guard abs(c) <= 1 else { return nil }
        if c == 0 { return ([.pi / 2], .pi) }
        return (abs(c) == 1 ? [acos(c)] : [acos(c), -acos(c)], 2 * .pi)
    }
}

// The working: the function isolated, every angle it allows, and, where the angle is 2x rather
// than x, every x that gives.
func trigSteps(_ trig: TrigEquation, _ n: String, _ header: Math) -> [Step] {
    let call = typeset(trig.call, n)
    let isolated = row(call, t(" = \(decimal(trig.c))"))
    var steps: [Step] = []
    if isolated.plain != header.plain { steps.append(Step(label: "Isolating \(call.plain)", math: isolated)) }
    var direct = false
    if case .unknown = trig.argument { direct = true }
    if trig.unit == .degrees {
        // In degrees: x = 30° + 360°k, and for 2x the same halved.
        guard let (angles, period) = trigAngles(trig.fn, trig.c) else {
            return steps + [Step(label: "Stating the general solution", math: t("No solution, since −1 ≤ \(direct ? "\(trig.fn) \(n)" : call.plain) ≤ 1"))]
        }
        let (inDegrees, turn) = (angles.map { $0 * 180 / .pi }, period * 180 / .pi)
        steps.append(Step(label: "Stating the general solution", math: degreeSolution(inDegrees, turn, of: typeset(trig.argument, n))))
        if !direct {
            steps.append(Step(label: "Hence", math: degreeSolution(inDegrees.map { ($0 - trig.b) / trig.a }, turn / abs(trig.a), of: t(n))))
        }
        return steps
    }
    let general = generalSolution(trig.fn, trig.c, of: typeset(trig.argument, n), named: direct ? "\(trig.fn) \(n)" : call.plain)
    steps.append(Step(label: "Stating the general solution", math: general))
    guard !direct, let (angles, period) = trigAngles(trig.fn, trig.c) else { return steps }

    // ax + b = θ + kP gives x = (θ − b)/a + kP/a, for each θ.
    var parts: [Math] = []
    for (i, angle) in angles.enumerated() {
        let start = piMath((angle - trig.b) / trig.a)
        parts.append(t(i == 0 ? "\(n) = " : " or \(n) = "))
        if start.plain != "0" { parts += [start, t(" + ")] }
        parts.append(periodMath(period / abs(trig.a)))
    }
    return steps + [Step(label: "Hence", math: .row(parts + [t(", k ∈ ℤ")]))]
}

// "x = 30° + 360°k or x = 150° + 360°k, k ∈ ℤ": each angle and every turn on from it. A pair
// either side of zero, as a cosine gives, is written ±60°.
func degreeSolution(_ angles: [Double], _ period: Double, of subject: Math) -> Math {
    func degrees(_ x: Double) -> String { degreesText(abs(x - x.rounded()) < 1e-9 ? x.rounded() : x) }
    let turns = "\(degrees(period))k"
    var parts: [Math] = []
    if angles.count == 2, added(angles[0], angles[1]) == 0 {
        parts = [subject, t(" = ±\(degrees(abs(angles[0]))) + \(turns)")]
    } else {
        for (i, angle) in angles.enumerated() {
            if i > 0 { parts.append(t(" or ")) }
            parts += [subject, t(" = " + (abs(angle) < 1e-9 ? turns : "\(degrees(angle)) + \(turns)"))]
        }
    }
    return .row(parts + [t(", k ∈ ℤ")])
}

// sin θ = c, cos θ = c and tan θ = c have every solution in one line.
func generalSolution(_ fn: String, _ c: Double, of angle: Math, named name: String) -> Math {
    let k = t(", k ∈ ℤ")
    let equals = row(angle, t(" = "))
    func plus(_ angle: Double, _ period: String) -> Math {
        let a = piMath(angle)
        return a.plain == "0" ? t(period) : row(a, t(" + \(period)"))
    }
    switch fn {
    case "tan":
        return row(equals, plus(atan(c), "kπ"), k)
    case "sin":
        guard abs(c) <= 1 else { return t("No solution, since −1 ≤ \(name) ≤ 1") }
        if c == 0 { return row(equals, t("kπ"), k) }
        if abs(c) == 1 { return row(equals, plus(asin(c), "2kπ"), k) }
        return row(equals, plus(asin(c), "2kπ"), t(" or "), equals, plus(.pi - asin(c), "2kπ"), k)
    default:
        guard abs(c) <= 1 else { return t("No solution, since −1 ≤ \(name) ≤ 1") }
        if c == 0 { return row(equals, Math.fraction(t("π"), t("2")), t(" + kπ"), k) }
        if abs(c) == 1 { return row(equals, plus(acos(c), "2kπ"), k) }
        return row(equals, t("±"), piMath(acos(c)), t(" + 2kπ"), k)
    }
}

// kπ, 2kπ, kπ/2: a period as so many of k.
func periodMath(_ period: Double) -> Math {
    for q in 1...12 {
        let p = (period / .pi * Double(q)).rounded()
        guard p > 0, abs(p / Double(q) * .pi - period) < 1e-12 else { continue }
        let (num, den) = reduced(Int(p), q)
        let top = t(num == 1 ? "kπ" : "\(num)kπ")
        return den == 1 ? top : .fraction(top, t("\(den)"))
    }
    return t(period == 1 ? "k" : "\(decimal(period))k")
}

// π/6, 2π/3, −π/2 when x is a simple multiple of π, its decimal otherwise.
func piMath(_ x: Double, within tolerance: Double = 1e-12) -> Math {
    for q in 1...12 {
        let p = (x / .pi * Double(q)).rounded()
        guard abs(p / Double(q) * .pi - x) < tolerance else { continue }
        return piMultiple(Int(p), q)
    }
    return t(decimal(x))
}

// p/q of π in lowest terms: π/6, 2π, −5π/4, and 0.
func piMultiple(_ p: Int, _ q: Int) -> Math {
    let (num, den) = reduced(p, q)
    if num == 0 { return t("0") }
    let top = t(abs(num) == 1 ? "π" : "\(abs(num))π")
    let value: Math = den == 1 ? top : .fraction(top, t("\(den)"))
    return num < 0 ? row(t("−"), value) : value
}

// MARK: - Typesetting expressions

// "2n² + 3n + 1": highest power first, with real minus signs.
func polyMath(_ p: Poly, _ n: String) -> Math {
    var parts: [Math] = []
    for k in stride(from: p.count - 1, through: 0, by: -1) where p[k] != 0 {
        let magnitude = abs(p[k])
        var coefficient = magnitude == 1 && k > 0 ? "" : decimal(magnitude)
        if k > 0, coefficient.contains("×") { coefficient += "·" }   // 6.67×10⁻¹¹·x, not run together
        let sign = p[k] < 0 ? (parts.isEmpty ? "−" : " − ") : (parts.isEmpty ? "" : " + ")
        let power: Math = k == 0 ? t("") : k == 1 ? t(n) : .power(t(n), t("\(k)"))
        parts += [t(sign + coefficient), power]
    }
    return parts.isEmpty ? t("0") : .row(parts)
}

// An expression as it would be written by hand: 2n², 3sin(x), (x + 1)(x − 1), x over 3, √x.
func typeset(_ e: Expr, _ n: String) -> Math { render(e, n).math }

// One term of a sum written out: bracketed when it is itself a sum, so 1 + (0 + 1) stays clear.
func termMath(_ e: Expr) -> Math {
    let r = render(e, "")
    return r.level < 2 ? row(t("("), r.math, t(")")) : r.math
}

// level: 1 a sum, 2 a product, 3 a power, 4 an atom; a child below what its place needs is
// bracketed. Fractions need no brackets: the bar does their grouping.
private func render(_ e: Expr, _ n: String) -> (math: Math, level: Int) {
    func wrap(_ r: (math: Math, level: Int), _ needed: Int) -> Math { r.level < needed ? row(t("("), r.math, t(")")) : r.math }
    switch e {
    case .num(let v):
        if v == .pi { return (t("π"), 4) }
        if v == M_E { return (t("e"), 4) }
        // 3×10⁸ is a product: bracketed under a power, and not run together with a letter.
        let text = decimal(v)
        return (t(text), v < 0 ? 1 : text.contains("×") ? 2 : 4)
    case .unknown:
        return (t(n), 4)
    case .constant(let name, _):
        return (t(name), 4)
    case .index(let k):
        return (t(k), 4)
    case .sum(let k, let from, let to, let body, let product):
        let sign = Math.bigOperator(product ? "∏" : "∑", lower: row(t("\(k) = "), render(from, n).math), upper: render(to, n).math)
        return (row(sign, wrap(render(body, n), 2)), 2)
    case .neg(let a):
        return (row(t("−"), wrap(render(a, n), 2)), 1)
    case .op("+", let a, let b):
        if case .neg(let inner) = b { return (row(render(a, n).math, t(" − "), wrap(render(inner, n), 2)), 1) }
        if case .num(let v) = b, v < 0 { return (row(render(a, n).math, t(" − \(decimal(-v))")), 1) }
        return (row(render(a, n).math, t(" + "), render(b, n).math), 1)
    case .op("-", let a, let b):
        return (row(render(a, n).math, t(" − "), wrap(render(b, n), 2)), 1)
    case .op("*", let a, let b):
        let l = wrap(render(a, n), 2), r = wrap(render(b, n), 2)
        // Juxtaposed as on paper, 2n and (x + 1)(x − 1); a dot where that would misread, 2·3 and x·x.
        let first = r.plain.first
        if first == "(" { return (row(l, r), 2) }
        if case .num = a, !l.plain.contains("×"), let first, first.isLetter || "√|π".contains(first) { return (row(l, r), 2) }
        return (row(l, t("·"), r), 2)
    case .op("/", let a, let b):
        return (.fraction(render(a, n).math, render(b, n).math), 2)
    case .op(_, let a, let b):
        return (.power(wrap(render(a, n), 4), render(b, n).math), 3)
    case .call(let f, let a):
        // 5! and (n − 1)!; under a power it is bracketed, (n!)².
        if f == "fact" { return (row(wrap(render(a, n), 4), t("!")), 3) }
        if f == "deg" { return (row(wrap(render(a, n), 4), t("°")), 3) }
        if f == "rad" { return (row(wrap(render(a, n), 4), t(" rad")), 3) }
        // In degrees: sin(2x°), and asin as it is, its answer being the angle.
        if f.hasSuffix("°") {
            let name = String(f.dropLast())
            if Angle.functions.contains(name) { return (row(t("\(name)("), wrap(render(a, n), 2), t("°)")), 4) }
            return (row(t("\(name)("), render(a, n).math, t(")")), 4)
        }
        let inner = render(a, n).math
        if f == "sqrt" { return (.root(inner), 4) }
        if f == "abs" { return (row(t("|"), inner, t("|")), 4) }
        return (row(t("\(f)("), inner, t(")")), 4)
    }
}
