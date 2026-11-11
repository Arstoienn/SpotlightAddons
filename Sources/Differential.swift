import Foundation

// A first-order linear differential equation, dy/dx + P(x)y = Q(x), however it is arranged:
// dy/dx + 2xy = 2x, \frac{dy}{dx} = 3y, y' = cos x. It is solved by the integrating factor
// μ = e^∫P, and the general solution y = (∫μQ dx + C)/μ is put back into the equation and
// checked before it is shown. One it cannot solve shows nothing: never an answer that is wrong.
struct Differential {
    var dependent: String, independent: String
    var p: Expr, q: Expr          // in dy/dx + P y = Q
    var mu: Expr?                 // e^∫P, nil where P is nought
    var integral: Expr            // ∫μQ dx, or ∫Q dx where P is nought
    var general: Expr             // y, with C in it
    var typed: Math

    // Whether a derivative is written in it, dy/dx or y': then it is this, and nothing else.
    static func mentionsDerivative(_ input: String) -> Bool {
        input.range(of: "\\(*d[a-z]\\)*\\s*/\\s*\\(*d[a-z]\\)*|[a-z]['′]", options: .regularExpression) != nil
    }

    static func parse(_ input: String) -> Differential? {
        // dy/dx, (dy)/(dx), y' and y′, each as a letter of its own, the rest of y as y.
        var text = input
        var dependent = "y", independent = "x"
        let fraction = try! NSRegularExpression(pattern: "\\(*d([a-z])\\)*\\s*/\\s*\\(*d([a-z])\\)*")
        if let m = fraction.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let y = Range(m.range(at: 1), in: text), let x = Range(m.range(at: 2), in: text) {
            dependent = String(text[y]); independent = String(text[x])
        } else if let m = text.range(of: "[a-z](?=['′])", options: .regularExpression) {
            dependent = String(text[m])
        }
        guard dependent != independent else { return nil }
        let used = Set(text.filter(\.isLetter).map(String.init))
        guard let slope = ["w", "q", "u", "v", "s"].first(where: { !used.contains($0) }) else { return nil }
        text = fraction.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "(\(slope))")
        text = text.replacingOccurrences(of: "\(dependent)['′]", with: "(\(slope))", options: .regularExpression)
        let typed = input.replacingOccurrences(of: "\\(*d([a-z])\\)*\\s*/\\s*\\(*d([a-z])\\)*", with: "d$1/d$2", options: .regularExpression)

        guard let tokens = try? Parser.tokenize(text), tokens.filter({ $0 == .symbol("=") }).count == 1 else { return nil }
        let letters = Set(tokens.compactMap { if case .letter(let s) = $0 { s } else { nil } })
        guard letters.isSubset(of: [slope, dependent, independent, "e"]) else { return nil }
        let mapped = tokens.map { $0 == .letter("e") ? .constant(M_E) : $0 }
        var state = Parser.State(tokens: mapped, unknown: independent, bound: [slope, dependent])
        guard let left = try? state.expression(), state.take("="), let right = try? state.expression(), state.at == mapped.count else { return nil }
        let e = Expr.op("-", left, right)

        // a(x)·y′ + b(x)·y + c(x) = 0, which it must be, and no other way: y′y and y² are not linear.
        func at(_ dy: Double, _ y: Double) -> Expr { e.setting(slope, to: dy).setting(dependent, to: y) }
        // A coefficient that is the same number everywhere is that number: (1 − cos x) − (0 − cos x) is 1.
        func settled(_ e: Expr) -> Expr {
            let values = [0.37, 0.81, 1.33, 1.9].map { e.eval($0) }
            guard let v = values.first, v.isFinite, values.allSatisfy({ abs($0 - v) <= 1e-12 * max(1, abs(v)) }) else { return e }
            return .num((v * 1e12).rounded() / 1e12)
        }
        let c = at(0, 0), a = settled(Expr.op("-", at(1, 0), c)), b = settled(Expr.op("-", at(0, 1), c))
        for x in [0.37, 0.81, 1.33, 1.9] {
            let (cv, av, bv) = (c.eval(x), a.eval(x), b.eval(x))
            guard av.isFinite, abs(av) > 1e-12, bv.isFinite, cv.isFinite else { return nil }
            for (dy, y) in [(2.0, 0.0), (0.0, 2.0), (1.0, 1.0), (3.0, -1.5)] where abs(at(dy, y).eval(x) - (cv + dy * av + y * bv)) > 1e-9 * max(1, abs(cv) + abs(av) + abs(bv)) { return nil }
        }
        // P and Q read by the tidier where it can, so that they are as simple as they can be written,
        // 1/x and not (1/x − x²) − (0 − x²); worked from a(x), b(x), c(x) as they came where not.
        var p = Algebra.cleaned(.op("/", b, a)), q = Algebra.cleaned(.neg(.op("/", c, a)))
        if let (sp, sq) = symbolic(mapped, slope: slope, dependent: dependent, independent: independent) { (p, q) = (sp, sq) }
        let samples = [0.37, 0.81, 1.33, 1.9]
        let pIsZero = samples.allSatisfy { abs(p.eval($0)) < 1e-12 }, qIsZero = samples.allSatisfy { abs(q.eval($0)) < 1e-12 }

        var mu: Expr? = nil
        let integral: Expr, general: Expr
        let C = Expr.index("C")
        if pIsZero {
            // dy/dx = Q: y is ∫Q dx + C.
            guard let i = Algebra.integrated(q).map(Algebra.cleaned) else { return nil }
            integral = i
            general = .op("+", i, C)
        } else {
            guard let f = Algebra.integrated(p).map(Algebra.cleaned) else { return nil }
            // e^(k ln|u|) is uᵏ, so that 1/x gives the factor x; otherwise e^F.
            let factor: Expr, decay: Expr
            if case .call("ln", .call("abs", let u)) = f {
                factor = u; decay = .op("/", .num(1), u)
            } else if case .op("*", .num(let k), .call("ln", .call("abs", let u))) = f {
                factor = .op("^", u, .num(k)); decay = .op("^", u, .num(-k))
            } else {
                factor = .op("^", .num(M_E), tidy(f)); decay = .op("^", .num(M_E), tidy(.neg(f)))
            }
            mu = factor
            let i = qIsZero ? Expr.num(0) : (Algebra.integrated(Algebra.cleaned(.op("*", factor, q))).map(Algebra.cleaned))
            guard let i else { return nil }
            integral = i
            // (∫μQ + C)/μ, the first part with μ cancelled: 1 + Ce^(−x²), and x³/4 + C/x.
            let particular: Expr? = qIsZero ? nil : combined(.op("*", i, decay), independent)
            // C/x where the factor is x, rather than C·1/x.
            var free = Expr.op("*", C, decay)
            if case .op("/", .num(1), let u) = decay { free = .op("/", C, u) }
            general = particular.map { .op("+", $0, free) } ?? free
        }
        // Put back into the equation, with two values of C, before it is believed.
        for constant in [0.7, -1.3] {
            let y = general.setting("C", to: constant)
            for x in samples {
                let h = 1e-5, slopeValue = (y.eval(x + h) - y.eval(x - h)) / (2 * h)
                let residual = slopeValue + p.eval(x) * y.eval(x) - q.eval(x)
                guard residual.isFinite, abs(residual) <= 1e-5 * max(1, abs(slopeValue) + abs(q.eval(x))) else { return nil }
            }
        }
        return Differential(dependent: dependent, independent: independent, p: p, q: q, mu: mu, integral: integral,
                            general: general, typed: t(typed))
    }

    // a(x)y′ + b(x)y + c(x) read by the tidier, every letter a letter: P = b/a and Q = −c/a written as
    // sums of powers of x, where a is a single term and there is no sine or the like in it.
    private static func symbolic(_ tokens: [Parser.Token], slope: String, dependent: String, independent: String) -> (Expr, Expr)? {
        var state = Parser.State(tokens: tokens, unknown: "", bound: [slope, dependent, independent])
        guard let left = try? state.expression(), state.take("="), let right = try? state.expression(), state.at == tokens.count,
              let terms = Simplification.collected(.op("-", left, right)) else { return nil }
        var a: [Simplification.Term] = [], b: [Simplification.Term] = [], c: [Simplification.Term] = []
        for term in terms {
            guard Set(term.powers.keys).isSubset(of: [slope, dependent, independent]) else { return nil }
            let rest = term.powers.filter { $0.key == independent }
            switch (term.powers[slope] ?? 0, term.powers[dependent] ?? 0) {
            case (1, 0): a.append((term.coefficient, rest))
            case (0, 1): b.append((term.coefficient, rest))
            case (0, 0): c.append((term.coefficient, rest))
            default: return nil
            }
        }
        guard a.count == 1, !a[0].coefficient.isZero else { return nil }
        let inverse: Simplification.Term = (1 / a[0].coefficient, a[0].powers.mapValues { -$0 })
        guard let p = Simplification.product(b, [inverse]), let q = Simplification.product(c.map { (-$0.coefficient, $0.powers) }, [inverse]) else { return nil }
        return (written(p, independent), written(q, independent))
    }

    // Terms c·xᵏ as an expression, the highest power first, fractions kept: x³/4 − 3x + 2/x.
    static func written(_ terms: [Simplification.Term], _ name: String) -> Expr {
        var out: Expr?
        for term in terms.sorted(by: { ($0.powers[name] ?? 0) > ($1.powers[name] ?? 0) }) {
            let k = term.powers[name] ?? 0, size = term.coefficient.magnitude
            var x: Expr = k == 0 ? .num(1) : abs(k) == 1 ? .unknown : .op("^", .unknown, .num(Double(abs(k))))
            var top: Double = size.double, below: Double = 1
            if case .exact(let r) = size { top = Double(r.top); below = Double(r.bottom) }
            if k < 0 { below = below == 1 ? 0 : below }
            var piece: Expr
            if k == 0 { piece = .num(top) } else { piece = top == 1 ? x : .op("*", .num(top), x) }
            if k < 0 {
                x = abs(k) == 1 ? .unknown : .op("^", .unknown, .num(Double(abs(k))))
                piece = .op("/", .num(top), below == 0 ? x : .op("*", .num(below), x))
            } else if below != 1 {
                piece = .op("/", piece, .num(below))
            }
            let negative = term.coefficient < 0
            if let sum = out { out = negative ? .op("-", sum, piece) : .op("+", sum, piece) } else { out = negative ? .neg(piece) : piece }
        }
        return out ?? .num(0)
    }

    // An exponent written as simply as it can be: a polynomial collected, −(−3x) as 3x.
    static func tidy(_ e: Expr) -> Expr {
        guard let p = poly(e).map(trim) else { return Algebra.cleaned(e) }
        let terms: [Simplification.Term] = p.enumerated().compactMap { k, c in c == 0 ? nil : (Number(c), k == 0 ? [:] : ["x": k]) }
        return written(terms, "x")
    }

    // A product with powers of e in it, each brought together into one, and numbers into one:
    // 2e^(x²)/2 · e^(−x²) is 1, and e^(5x)/5 · e^(−2x) is e^(3x)/5. Without e, by the tidier.
    static func combined(_ e: Expr, _ name: String) -> Expr {
        func exponent(_ e: Expr) -> Expr? {
            if case .op("^", .num(let base), let u) = e, abs(base - M_E) < 1e-15 { return u }
            if case .call("exp", let u) = e { return u }
            return nil
        }
        func factors(_ e: Expr) -> (top: [Expr], bottom: [Expr]) {
            switch e {
            case .op("*", let a, let b): let x = factors(a), y = factors(b); return (x.top + y.top, x.bottom + y.bottom)
            case .op("/", let a, let b): let x = factors(a), y = factors(b); return (x.top + y.bottom, x.bottom + y.top)
            case .neg(let a): let x = factors(a); return ([.num(-1)] + x.top, x.bottom)
            default: return ([e], [])
            }
        }
        let (top, bottom) = factors(e)
        var power: Expr = .num(0), number = 1.0, above: [Expr] = [], below: [Expr] = []
        for f in top {
            if let u = exponent(f) { power = .op("+", power, u) } else if !f.hasUnknown { number *= f.eval(0) } else { above.append(f) }
        }
        for f in bottom {
            if let u = exponent(f) { power = .op("-", power, u) } else if !f.hasUnknown { number /= f.eval(0) } else { below.append(f) }
        }
        // Without e, a product of powers of x and numbers is tidied whole: x⁴/4 · 1/x is x³/4.
        let hasPower = [0.37, 0.81, 1.33].contains { abs(power.eval($0)) > 1e-12 }
        if !hasPower, let terms = Simplification.collected(lettered(e, name)) { return written(terms, name) }
        var parts: [Expr] = above
        if hasPower { parts.append(.op("^", .num(M_E), tidy(power))) }
        var result: Expr = parts.isEmpty ? .num(1) : parts.dropFirst().reduce(parts[0]) { .op("*", $0, $1) }
        let k = (number * 1e9).rounded() / 1e9
        if let (p, q) = rational(abs(k)), q != 1 { result = .op("/", p == 1 ? result : .op("*", .num(Double(p)), result), .num(Double(q))) }
        else if abs(k) != 1 { result = .op("*", .num(abs(k)), result) }
        if !below.isEmpty { result = .op("/", result, below.dropFirst().reduce(below[0]) { .op("*", $0, $1) }) }
        return k < 0 ? .neg(result) : result
    }

    // The unknown written as the letter it is, for the tidier, which works in letters.
    static func lettered(_ e: Expr, _ name: String) -> Expr {
        switch e {
        case .unknown: return .index(name)
        case .num, .index, .constant: return e
        case .neg(let a): return .neg(lettered(a, name))
        case .op(let o, let a, let b): return .op(o, lettered(a, name), lettered(b, name))
        case .call(let f, let a): return .call(f, lettered(a, name))
        case .apply(let f, let args): return .apply(f, args.map { lettered($0, name) })
        case .sum: return e
        }
    }

    private func w(_ e: Expr) -> Math { typeset(e, independent) }
    private var y: String { dependent }
    private var x: String { independent }

    var solution: Solution {
        Solution(exact: "\(y) = " + w(general).plain, approx: "The general solution; C is any constant")
    }

    var details: Details {
        var steps: [Step] = []
        let derivative = t("d\(y)/d\(x)")
        if let mu {
            steps.append(Step(label: "Writing in the form d\(y)/d\(x) + P(\(x))\(y) = Q(\(x))",
                              math: row(derivative, t(" + "), Math.group(w(p)), t("\(y) = "), w(q))))
            steps.append(Step(label: "Finding the integrating factor", math: row(t("μ = e^(∫P d\(x)) = "), w(mu))))
            steps.append(Step(label: "Multiplying through by μ", math: row(t("d/d\(x)("), w(mu), t("·\(y)) = "), w(Algebra.cleaned(.op("*", mu, q))))))
            steps.append(Step(label: "Integrating both sides", math: row(w(mu), t("·\(y) = "), w(Differential.combined(integral, x)), t(" + C"))))
        } else {
            steps.append(Step(label: "Integrating both sides", math: row(t("\(y) = ∫"), Math.group(w(q)), t(" d\(x) = "), w(integral), t(" + C"))))
        }
        steps.append(Step(label: "Hence", math: row(t("\(y) = "), w(general))))
        return Details(name: y, equation: typed, steps: steps, solutions: [row(t("\(y) = "), w(general))],
                       note: "C is any constant; each value of it gives one solution.", f: { _ in .nan }, roots: [])
    }
}
