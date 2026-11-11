import Foundation

// Products integrated, in the forms a calculus course has: f(g(x))·g′(x) by substitution,
// e^(ax)·sin(bx) and e^(ax)·cos(bx) by their formula, and a polynomial times e^(ax), sin(bx) or
// cos(bx) by integrating by parts as often as the polynomial's degree.
extension Algebra {
    static func product(_ f: Expr, _ g: Expr) -> Expr? {
        // e^u·e^v is e^(u + v).
        if let u = exponent(f), let v = exponent(g) { return integrated(.op("^", .num(M_E), Differential.tidy(.op("+", u, v)))) }
        return substituted(f, g) ?? exponentialTrig(f, g) ?? polynomialTimes(f, g)
    }

    // Describe the same branch product() actually uses, including the substitution or the
    // first integration-by-parts step. This is not a method inferred from the final answer.
    static func productSteps(_ f: Expr, _ g: Expr, name: String) -> [Step]? {
        func w(_ e: Expr) -> Math { typeset(cleaned(e), name) }
        func integral(_ e: Expr, variable: String) -> Math { row(t("∫ "), termMath(e, variable), t(" d\(variable)")) }
        if let u = exponent(f), let v = exponent(g) {
            let combined = Differential.tidy(.op("+", u, v))
            return [Step(label: "Combining exponentials with the same base", math: row(w(.op("*", f, g)), t(" = "), w(.op("^", .num(M_E), combined))),
                         note: "Use eᵘ·eᵛ = e^(u + v), then integrate the combined exponential.")]
        }
        if let substitution = substitution(f, g) {
            let inner = substitution.inner, derivative = substitution.derivative
            let inU = cleaned(substitution.integrand)
            let relation = Expr.op("-", f, .op("*", .num(substitution.coefficient), derivative))
            // The integration engine also recognises candidates by sampling f/u′. That alone
            // cannot justify an equality in a derivation. Only show it as such after cancellation.
            guard Simplification.collected(relation.substitutingUnknown(.index(name)))?.isEmpty == true else {
                return [Step(label: "Numerically suggested substitution", math: row(t("u = "), w(inner)),
                             note: "The ratio of the remaining factor to du/d\(name) agrees at sampled values. This is numerical evidence, not a symbolic proof; a full derivation of this substitution is unavailable.")]
            }
            var steps = [Step(label: "Choosing the substitution", math: row(t("u = "), w(inner), t(",  du = "), w(derivative), t(" d\(name)"))),
                         Step(label: "Rewriting the integral in u", math: row(integral(.op("*", f, g), variable: name), t(" = "), integral(inU, variable: "u")),
                              note: "The remaining factor is the constant multiple of du shown by the substitution.")]
            if let primitive = integrated(inU) {
                steps.append(Step(label: "Integrating with respect to u", math: row(integral(inU, variable: "u"), t(" = "), typeset(cleaned(primitive), "u"), t(" + C"))))
            }
            steps.append(Step(label: "Substituting back", math: row(t("F(\(name)) = "), w(substitution.primitive))))
            return steps
        }
        if exponentialTrig(f, g) != nil, let u = exponent(f), let (a, _) = linear(u) {
            let argument: Expr
            if case .call(_, let v) = g { argument = v } else { return nil }
            guard let (b, _) = linear(argument) else { return nil }
            return [Step(label: "Exponential and trigonometric product rule", math: t("a = \(decimal(a)),  b = \(decimal(b))"),
                         note: "For e^(ax+p) sin(bx+q), the primitive is e^(ax+p)(a sin(bx+q) − b cos(bx+q))/(a²+b²). For cosine, use a cos(bx+q) + b sin(bx+q). The formula follows by applying integration by parts twice.")]
        }
        guard polynomialTimes(f, g) != nil, let du = differentiated(f), let v = integrated(g) else { return nil }
        var steps = [Step(label: "Integration by parts formula", math: row(t("∫ u dv = uv − ∫ v du"))),
                     Step(label: "Choosing u and dv", math: row(t("u = "), w(f), t(",  dv = "), w(g), t(" d\(name)"))),
                     Step(label: "Differentiating u and integrating dv", math: row(t("du = "), w(du), t(" d\(name),  v = "), w(v))),
                     Step(label: "Applying integration by parts", math: row(integral(.op("*", f, g), variable: name), t(" = "), w(.op("*", f, v)), t(" − "), integral(cleaned(.op("*", v, du)), variable: name)))]
        if let rest = integrated(cleaned(.op("*", v, du))) {
            steps.append(Step(label: "Integrating the remaining term", math: row(integral(cleaned(.op("*", v, du)), variable: name), t(" = "), w(rest), t(" + C"))))
        } else {
            steps.append(Step(label: "Repeating integration by parts", math: nil, note: "Repeat with the remaining polynomial factor. Its degree decreases by one each time until only a constant remains."))
        }
        return steps
    }

    // e^u, as e^(…) or exp(…): its u.
    private static func exponent(_ e: Expr) -> Expr? {
        if case .op("^", .num(let base), let u) = e, abs(base - M_E) < 1e-15 { return u }
        if case .call("exp", let u) = e { return u }
        return nil
    }

    private static func power(_ x: Expr, _ n: Double) -> Expr { n == 1 ? x : .op("^", x, .num(n)) }
    private static func number(_ v: Double) -> Expr {
        if v == v.rounded() { return .num(v) }
        if let (p, q) = rational(v) { return .op("/", .num(Double(p)), .num(Double(q))) }
        return .num(v)
    }
    // k·e, a fraction k written over its lower half, x·sin(3x)/3, so that it is not worked out as a decimal.
    private static func times(_ k: Double, _ e: Expr) -> Expr {
        if k == 1 { return e }
        if k == -1 { return .neg(e) }
        if k != k.rounded(), let (p, q) = rational(k) { return .op("/", times(Double(p), e), .num(Double(q))) }
        return .op("*", number(k), e)
    }

    // c·u′·F′(u), c a number: c·F(u). F′ is e^u, sin u, cos u or a power of u.
    private static func substituted(_ f: Expr, _ g: Expr) -> Expr? { substitution(f, g)?.primitive }

    private static func substitution(_ f: Expr, _ g: Expr) -> (primitive: Expr, inner: Expr, derivative: Expr, integrand: Expr, coefficient: Double)? {
        // u·u′, sin(x)cos(x) among them: u²/2.
        if let derivative = differentiated(g), !(poly(g).map { trim($0).count <= 2 } ?? false) {
            let ratios = [0.31, 0.73, 1.17, 1.61, 2.29].map { f.eval($0) / derivative.eval($0) }.filter(\.isFinite)
            if ratios.count >= 3, let c = ratios.first, ratios.allSatisfy({ abs($0 - c) <= 1e-9 * max(1, abs(c)) }) {
                let k = (c * 1e9).rounded() / 1e9
                return (times(k / 2, .op("^", g, .num(2))), g, derivative, times(k, .unknown), k)
            }
        }
        let inner: Expr, outer: (Expr) -> Expr, inU: Expr
        if let u = exponent(g) {
            inner = u; outer = { _ in g }; inU = .op("^", .num(M_E), .unknown)
        } else if case .call("sin", let u) = g {
            inner = u; outer = { .neg(.call("cos", $0)) }; inU = .call("sin", .unknown)
        } else if case .call("cos", let u) = g {
            inner = u; outer = { .call("sin", $0) }; inU = .call("cos", .unknown)
        } else if case .op("^", let u, .num(let n)) = g, u.hasUnknown {
            inner = u; outer = { n == -1 ? .call("ln", .call("abs", $0)) : .op("/", .op("^", $0, .num(n + 1)), .num(n + 1)) }; inU = .op("^", .unknown, .num(n))
        } else { return nil }
        guard linear(inner) == nil, let derivative = differentiated(inner) else { return nil }
        // f over u′ must be the same number wherever both are worked out.
        let ratios = [0.31, 0.73, 1.17, 1.61, 2.29].map { f.eval($0) / derivative.eval($0) }.filter(\.isFinite)
        guard ratios.count >= 3, let c = ratios.first, ratios.allSatisfy({ abs($0 - c) <= 1e-9 * max(1, abs(c)) }) else { return nil }
        let k = (c * 1e9).rounded() / 1e9
        return (times(k, outer(inner)), inner, derivative, times(k, inU), k)
    }

    // ∫ e^(ax + p) sin(bx + q) dx = e^(ax + p)(a sin(bx + q) − b cos(bx + q))/(a² + b²), and with
    // cos, e^(ax + p)(a cos(bx + q) + b sin(bx + q))/(a² + b²).
    private static func exponentialTrig(_ f: Expr, _ g: Expr) -> Expr? {
        guard let u = exponent(f), let (a, _) = linear(u) else { return nil }
        let isSine: Bool, v: Expr
        if case .call("sin", let w) = g { isSine = true; v = w } else if case .call("cos", let w) = g { isSine = false; v = w } else { return nil }
        guard let (b, _) = linear(v) else { return nil }
        let sine = Expr.call("sin", v), cosine = Expr.call("cos", v)
        let inside: Expr = isSine ? .op("-", times(a, sine), times(b, cosine)) : .op("+", times(a, cosine), times(b, sine))
        return .op("/", .op("*", f, inside), number(a * a + b * b))
    }

    // A polynomial P times e^(kx + p): e^(kx + p) Σ (−1)ʲ P⁽ʲ⁾/kʲ⁺¹. Times sin(mx + q) or
    // cos(mx + q): the same by parts, each derivative of P with the next integral of the sine.
    private static func polynomialTimes(_ f: Expr, _ g: Expr) -> Expr? {
        guard let p = poly(f).map(trim), p.count >= 2, p.count <= 9 else { return nil }
        var derivatives: [Poly] = [p]
        while let last = derivatives.last, last.count > 1 { derivatives.append(Array(last.enumerated().dropFirst().map { Double($0.offset) * $0.element })) }
        // The polynomials over the one lower half they share, in whole numbers: (9x² − 6x + 2)/27.
        var denominator = 1
        func bottom(_ q: Poly) { for c in q where abs(c) > 1e-12 { if let (_, d) = rational(c) { denominator = lcm(denominator, d) } } }
        func written(_ q: Poly) -> Expr? {
            var out: Expr?
            for (k, c) in q.enumerated().reversed() where abs(c) > 1e-12 {
                let whole = (c * Double(denominator)).rounded()
                let x: Expr = k == 0 ? .num(abs(whole)) : (abs(whole) == 1 ? power(.unknown, Double(k)) : .op("*", .num(abs(whole)), power(.unknown, Double(k))))
                if let sum = out { out = whole < 0 ? .op("-", sum, x) : .op("+", sum, x) } else { out = whole < 0 ? .neg(x) : x }
            }
            return out
        }
        func over(_ e: Expr) -> Expr { denominator == 1 ? e : .op("/", e, .num(Double(denominator))) }
        func sum(_ parts: [(Poly, Double)]) -> Poly {
            var out: Poly = []
            for (q, k) in parts {
                if out.count < q.count { out += Array(repeating: 0, count: q.count - out.count) }
                for (i, c) in q.enumerated() { out[i] += k * c }
            }
            return out
        }
        if let u = exponent(g), let (k, _) = linear(u) {
            let q = sum(derivatives.enumerated().map { j, d in (d, (j % 2 == 0 ? 1 : -1) / pow(k, Double(j + 1))) })
            bottom(q)
            return written(q).map { over(.op("*", $0, g)) }
        }
        let isSine: Bool, v: Expr
        if case .call("sin", let w) = g { isSine = true; v = w } else if case .call("cos", let w) = g { isSine = false; v = w } else { return nil }
        guard let (m, _) = linear(v) else { return nil }
        var cosPart: [(Poly, Double)] = [], sinPart: [(Poly, Double)] = []
        for (j, d) in derivatives.enumerated() {
            let scale = 1 / pow(m, Double(j + 1)), even = j % 2 == 0
            if isSine {
                if even { cosPart.append((d, ((j / 2) % 2 == 0 ? -1 : 1) * scale)) } else { sinPart.append((d, (((j - 1) / 2) % 2 == 0 ? 1 : -1) * scale)) }
            } else {
                if even { sinPart.append((d, ((j / 2) % 2 == 0 ? 1 : -1) * scale)) } else { cosPart.append((d, (((j - 1) / 2) % 2 == 0 ? 1 : -1) * scale)) }
            }
        }
        bottom(sum(cosPart)); bottom(sum(sinPart))
        let c = written(sum(cosPart)).map { Expr.op("*", $0, .call("cos", v)) }
        let s = written(sum(sinPart)).map { Expr.op("*", $0, .call("sin", v)) }
        switch (c, s) {
        case let (c?, s?): return over(.op("+", c, s))
        case let (c?, nil): return over(c)
        case let (nil, s?): return over(s)
        default: return nil
        }
    }
}
