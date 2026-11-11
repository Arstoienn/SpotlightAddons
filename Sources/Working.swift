import Foundation

// Working is built from the expressions used by the solver. Each line names an operation
// and shows its result; a numerical check is never described as an algebraic proof.
enum Working {
    static func small(_ e: Expr, limit: Int = 100) -> Bool {
        var pending = [e], count = 0
        while let part = pending.popLast() {
            count += 1
            if count > limit { return false }
            switch part {
            case .neg(let a), .call(_, let a): pending.append(a)
            case .op(_, let a, let b): pending += [a, b]
            case .apply(_, let args): pending += args
            case .sum: return false
            default: break
            }
        }
        return true
    }

    static func number(_ v: Double) -> Math {
        if let r = Number(v).rational { return fractionMath(r.top, r.bottom) }
        return t(decimal(v))
    }
    static func number(_ v: Number) -> Math {
        v.rational.map { fractionMath($0.top, $0.bottom) } ?? t(decimal(v.double))
    }

    // Keep fractions as fractions while doing arithmetic. In 2/3 + 1/6, writing 0.666667
    // is neither the common-denominator step nor an exact intermediate value.
    static func arithmetic(_ input: Expr, lead: String) -> [Step]? {
        guard small(input, limit: 80), input.constants.isEmpty,
              input.number?.isExact == true else { return nil }
        func atom(_ e: Expr) -> Rational? {
            func signedNumber(_ e: Expr) -> Bool {
                if case .num = e { return true }
                if case .neg(let a) = e { return signedNumber(a) }
                return false
            }
            switch e {
            case .num: return e.number?.rational
            case .neg(let a): return atom(a).map { -$0 }
            case .op("/", let a, let b) where signedNumber(a) && signedNumber(b): return e.number?.rational
            default: return nil
            }
        }
        func expression(_ r: Rational) -> Expr? {
            guard abs(r.top) < 9_000_000_000_000_000, r.bottom < 9_000_000_000_000_000 else { return nil }
            return r.bottom == 1 ? .num(Double(r.top)) : .op("/", .num(Double(r.top)), .num(Double(r.bottom)))
        }
        func fraction(_ top: Int, _ bottom: Int) -> Expr { bottom == 1 ? .num(Double(top)) : .op("/", .num(Double(top)), .num(Double(bottom))) }
        func writtenDenominator(_ e: Expr, value: Rational) -> Int {
            if case .op("/", .num, .num(let d)) = e, let n = Int(fitting: abs(d)), Double(n) == abs(d), n > 0 { return n }
            if case .neg(let a) = e { return writtenDenominator(a, value: value) }
            return value.bottom
        }
        func next(_ e: Expr) -> (Expr, String)? {
            if let r = atom(e), let simple = expression(r) {
                return typeset(e, "").plain == typeset(simple, "").plain ? nil : (simple, "Reducing the fraction")
            }
            switch e {
            case .op(let o, let a, let b):
                if let x = atom(a), let y = atom(b), let r = e.number?.rational, let result = expression(r) {
                    let dx = writtenDenominator(a, value: x), dy = writtenDenominator(b, value: y)
                    if (o == "+" || o == "-"), dx != dy {
                        let (den, overflow) = (dx / max(gcd(dx, dy), 1)).multipliedReportingOverflow(by: dy)
                        guard !overflow else { return nil }
                        let (p, pOverflow) = x.top.multipliedReportingOverflow(by: den / x.bottom)
                        let (q, qOverflow) = y.top.multipliedReportingOverflow(by: den / y.bottom)
                        guard !pOverflow, !qOverflow, abs(p) < 9_000_000_000_000_000, abs(q) < 9_000_000_000_000_000 else { return nil }
                        return (.op(o, fraction(p, den), fraction(q, den)), "Writing over the common denominator \(den)")
                    }
                    if (o == "+" || o == "-"), dx > 1, dx == dy,
                       let px = x * Rational(dx)!, let py = y * Rational(dy)!, px.isWhole, py.isWhole {
                        let (top, overflow) = o == "+" ? px.top.addingReportingOverflow(py.top) : px.top.subtractingReportingOverflow(py.top)
                        guard !overflow, abs(top) < 9_000_000_000_000_000 else { return nil }
                        return (fraction(top, dx), o == "+" ? "Adding the numerators" : "Subtracting the numerators")
                    }
                    if o == "/", y.top != 0, x.bottom > 1 || y.bottom > 1,
                       let reciprocal = Rational(y.bottom, y.top).flatMap(expression) {
                        return (.op("*", a, reciprocal), "Multiplying by the reciprocal")
                    }
                    let labels: [Character: String] = ["+": "Adding", "-": "Subtracting", "*": x.bottom > 1 || y.bottom > 1 ? "Multiplying the fractions" : "Multiplying", "/": "Dividing", "^": "Evaluating the power"]
                    if let label = labels[o] { return (result, label) }
                }
                if let (inner, label) = next(a) { return (.op(o, inner, b), label) }
                if let (inner, label) = next(b) { return (.op(o, a, inner), label) }
            case .neg(let a): if let (inner, label) = next(a) { return (.neg(inner), label) }
            default: break
            }
            return nil
        }
        var current = input, steps: [Step] = []
        while let (changed, label) = next(current), steps.count < 40 {
            guard typeset(changed, "").plain != typeset(current, "").plain else { break }
            steps.append(Step(label: label, math: row(t(lead), typeset(changed, ""))))
            current = changed
        }
        // Calls, sums, very large fractions and other unsupported nodes use the existing path.
        guard atom(current) != nil else { return nil }
        return steps.isEmpty ? nil : steps
    }

    static func polynomial(_ p: Poly, _ n: String) -> Math {
        polynomial(p.map { Number($0) }, n)
    }

    static func polynomial(_ p: [Number], _ n: String) -> Math {
        var parts: [Math] = []
        for k in p.indices.reversed() where p[k] != 0 {
            let v = p[k]
            parts.append(t(v < 0 ? (parts.isEmpty ? "−" : " − ") : (parts.isEmpty ? "" : " + ")))
            if k == 0 || v.magnitude != 1 { parts.append(number(v.magnitude)) }
            if k > 0 { parts.append(k == 1 ? t(n) : .power(Grouped.isGroup(n) ? .group(t(n)) : t(n), t("\(k)"))) }
        }
        return parts.isEmpty ? t("0") : .row(parts)
    }

    private static func exactPolynomial(_ e: Expr, _ name: String) -> [Number]? {
        guard let terms = Simplification.collected(e.substitutingUnknown(.index(name))),
              terms.allSatisfy({ $0.coefficient.isExact && $0.powers.allSatisfy { $0.key == name && $0.value >= 0 && $0.value <= 2 } }) else { return nil }
        var out = [Number](repeating: 0, count: (terms.map { $0.powers[name] ?? 0 }.max() ?? 0) + 1)
        for term in terms { let k = term.powers[name] ?? 0; out[k] = out[k] + term.coefficient }
        while out.last?.isZero == true { out.removeLast() }
        return out.allSatisfy(\.isExact) ? out : nil
    }

    // Keep the two sides until the same operation has been applied to both. In particular,
    // 3(x+2)=2x+9 should not begin with the unexplained equation x−3=0.
    static func linear(_ eq: Equation) -> [Step]? {
        guard small(eq.left), small(eq.right), let lp = exactPolynomial(eq.left, eq.unknown), let rp = exactPolynomial(eq.right, eq.unknown),
              lp.count <= 2, rp.count <= 2 else { return nil }
        let n = eq.unknown
        let (lc, la) = (lp.first ?? 0, lp.count > 1 ? lp[1] : 0)
        let (rc, ra) = (rp.first ?? 0, rp.count > 1 ? rp[1] : 0)
        let a = la - ra, b = rc - lc
        guard a != 0 else { return nil }
        var steps: [Step] = []
        func equation(_ l: [Number], _ r: [Number]) -> Math { row(polynomial(l, n), t(" = "), polynomial(r, n)) }
        let expanded = equation(lp, rp)
        if expanded.plain != row(typeset(eq.left, n), t(" = "), typeset(eq.right, n)).plain {
            steps.append(Step(label: "Expanding brackets and collecting like terms", math: expanded))
        }
        if ra != 0 {
            steps.append(Step(label: "\(ra > 0 ? "Subtracting" : "Adding") \(polynomial([0, ra.magnitude], n).plain) on both sides",
                              math: equation([lc, a], [rc])))
        }
        if lc != 0 {
            steps.append(Step(label: "\(lc > 0 ? "Subtracting" : "Adding") \(number(lc.magnitude).plain) on both sides",
                              math: equation([0, a], [b])))
        }
        if a != 1 {
            let ratio = b / a
            let division = Math.fraction(b < 0 ? .group(number(b)) : number(b), a < 0 ? .group(number(a)) : number(a))
            let simplified = ratio.rational.map { fractionMath($0.top, $0.bottom) }
            steps.append(Step(label: "Dividing both sides by \(number(a).plain)",
                              math: row(t("\(n) = "), division,
                                        simplified.map { $0.plain == division.plain ? t("") : row(t(" = "), $0) } ?? t(""))))
        }
        return steps
    }

    static func standardForm(_ eq: Equation, target: Poly) -> [Step] {
        guard small(eq.left), small(eq.right), let lp = poly(eq.left), let rp = poly(eq.right),
              (lp + rp + target).allSatisfy({ Number($0).isExact }) else {
            return [Step(label: "Collecting all terms on the left", math: row(polyMath(target, eq.unknown), t(" = 0")))]
        }
        let n = eq.unknown
        var steps: [Step] = []
        let original = row(typeset(eq.left, n), t(" = "), typeset(eq.right, n))
        let expanded = row(polynomial(lp, n), t(" = "), polynomial(rp, n))
        if original.plain != expanded.plain {
            steps.append(Step(label: "Expanding brackets and collecting like terms", math: expanded))
        }
        let difference = trim(sub(lp, rp))
        if !trim(rp).isEmpty {
            steps.append(Step(label: "Subtracting the right-hand side from both sides",
                              math: row(polynomial(lp, n), t(" − "), .group(polynomial(rp, n)), t(" = 0"))))
            steps.append(Step(label: "Collecting like terms", math: row(polynomial(difference, n), t(" = 0"))))
        }
        if difference != target, let a = difference.last, let b = target.last, a != 0 {
            steps.append(Step(label: "Multiplying both sides by \(number(b / a).plain)", math: row(polynomial(target, n), t(" = 0"))))
        }
        return steps
    }

    static func derivative(_ e: Expr, _ name: String) -> [Step] {
        guard small(e, limit: 80) else {
            return [Step(label: "Differentiating the expression", math: nil,
                         note: "The expression is too long to show every local rule. The derivative is evaluated symbolically; the simplified result follows.")]
        }
        var steps: [Step] = [], seen = Set<String>()
        func D(_ e: Expr) -> Math { row(t("d/d\(name) "), .group(typeset(e, name))) }
        func visit(_ e: Expr) {
            guard e.hasUnknown, steps.count < 24 else { return }
            let key = typeset(e, name).plain
            guard seen.insert(key).inserted else { return }
            let label: String, formula: String
            switch e {
            case .unknown: return
            case .neg(let a):
                visit(a); label = "Constant multiple rule"; formula = "(cu)′ = cu′."
            case .op(let o, let a, let b):
                visit(a); visit(b)
                switch o {
                case "+", "-": label = "\(o == "+" ? "Sum" : "Difference") rule"; formula = o == "+" ? "(u + v)′ = u′ + v′." : "(u − v)′ = u′ − v′."
                case "*":
                    label = a.hasUnknown && b.hasUnknown ? "Product rule" : "Constant multiple rule"
                    formula = a.hasUnknown && b.hasUnknown ? "(uv)′ = u′v + uv′." : "(cu)′ = cu′; a constant has derivative 0."
                case "/":
                    label = b.hasUnknown ? "Quotient rule" : "Constant multiple rule"
                    formula = b.hasUnknown ? "(u/v)′ = (u′v − uv′)/v², where v ≠ 0." : "(u/c)′ = u′/c."
                case "^":
                    if !b.hasUnknown { label = "Power rule\(isVariable(a) ? "" : " and chain rule")"; formula = "(uⁿ)′ = n·uⁿ⁻¹·u′, for constant n, wherever the derivative exists." }
                    else if !a.hasUnknown { label = "Exponential rule and chain rule"; formula = "(aᵘ)′ = aᵘ·ln(a)·u′, for a > 0." }
                    else { label = "Logarithmic differentiation"; formula = "(uᵛ)′ = uᵛ(v′ln u + vu′/u), for u > 0." }
                default: return
                }
            case .call(let f, let a):
                visit(a)
                label = "\(f) derivative\(isVariable(a) ? "" : " and chain rule")"
                let rules = ["sin": "(sin u)′ = cos u·u′.", "cos": "(cos u)′ = −sin u·u′.",
                             "tan": "(tan u)′ = u′/cos²u.", "exp": "(exp u)′ = exp u·u′.",
                             "ln": "(ln u)′ = u′/u, for u > 0.", "log": "(log₁₀u)′ = u′/(u·ln 10), for u > 0.",
                             "sqrt": "(√u)′ = u′/(2√u), for u > 0.", "asin": "(asin u)′ = u′/√(1 − u²), for |u| < 1.",
                             "acos": "(acos u)′ = −u′/√(1 − u²), for |u| < 1.", "atan": "(atan u)′ = u′/(1 + u²).",
                             "sinh": "(sinh u)′ = cosh u·u′.", "cosh": "(cosh u)′ = sinh u·u′.",
                             "tanh": "(tanh u)′ = u′/cosh²u.", "abs": "(|u|)′ = (u/|u|)u′ where u ≠ 0; zeros need separate checking."]
                guard let rule = rules[f] else { return }; formula = rule
            default: return
            }
            guard let derivative = Algebra.differentiated(e) else { return }
            steps.append(Step(label: label, math: row(D(e), t(" = "), typeset(Algebra.cleaned(derivative), name)), note: formula))
        }
        visit(e)
        if steps.isEmpty, let derivative = Algebra.differentiated(e) {
            steps.append(Step(label: e.hasUnknown ? "Derivative of the variable" : "Derivative of a constant",
                              math: row(D(e), t(" = "), typeset(derivative, name))))
        }
        if steps.count >= 24 {
            steps.append(Step(label: "Combining the derivatives", math: nil, note: "The remaining terms use the same rules. The derivative of the full expression follows."))
        }
        return steps
    }

    private static func isVariable(_ e: Expr) -> Bool { if case .unknown = e { return true }; return false }

    // Explain only rules whose structure is known here. For a more complicated closed form,
    // display it and differentiate it back, rather than inventing an integration method.
    static func integral(_ e: Expr, primitive F: Expr, name: String) -> [Step] {
        guard small(e, limit: 70), small(F, limit: 100) else {
            return [Step(label: "Finding an antiderivative", math: row(t("F(\(name)) = "), typeset(F, name)))]
        }
        func integral(_ e: Expr) -> Math { row(t("∫ "), termMath(e, name), t(" d\(name)")) }
        var steps: [Step] = []
        if let p = poly(e).map(trim), !p.isEmpty {
            let expanded = polynomial(p, name)
            if expanded.plain != typeset(e, name).plain {
                steps.append(Step(label: "Expanding and collecting the integrand", math: row(t("∫ "), .group(expanded), t(" d\(name)"))))
            }
            steps.append(Step(label: "Power rule for integration", math: row(t("∫ "), .power(t(name), t("n")), t(" d\(name) = "),
                              .fraction(.power(t(name), t("n + 1")), t("n + 1")), t(" + C")), note: "For n ≠ −1. Constant factors are kept outside the integral."))
            for k in p.indices.reversed() where p[k] != 0 {
                let term: Expr = k == 0 ? .num(p[k]) : .op("*", .num(p[k]), k == 1 ? .unknown : .op("^", .unknown, .num(Double(k))))
                guard let antiderivative = Algebra.integrated(term) else { continue }
                steps.append(Step(label: "Integrating the \(k == 0 ? "constant" : "\(name)\(k == 1 ? "" : superscript(k))") term",
                                  math: row(integral(Algebra.cleaned(term)), t(" = "), typeset(Algebra.cleaned(antiderivative), name), t(" + C"))))
                if steps.count >= 12 { break }
            }
        } else {
            switch e {
            case .op("*", let a, let b) where a.hasUnknown && b.hasUnknown:
                steps += Algebra.productSteps(a, b, name: name) ?? Algebra.productSteps(b, a, name: name) ?? []
            case .op(let o, let a, let b) where o == "+" || o == "-":
                steps.append(Step(label: "Splitting the integral", math: row(integral(e), t(" = "), integral(a), t(o == "+" ? " + " : " − "), integral(b)),
                                  note: "Integrate each term separately, then combine the constants of integration."))
                if let x = Algebra.integrated(a), let y = Algebra.integrated(b) {
                    steps.append(Step(label: "Integrating the first term", math: row(integral(a), t(" = "), typeset(Algebra.cleaned(x), name), t(" + C₁"))))
                    steps.append(Step(label: "Integrating the second term", math: row(integral(b), t(" = "), typeset(Algebra.cleaned(y), name), t(" + C₂"))))
                }
            case .call(let f, let u):
                if let (a, _) = Algebra.linear(u) {
                    let formulas = ["sin": "∫ sin u du = −cos u + C.", "cos": "∫ cos u du = sin u + C.",
                                    "exp": "∫ exp u du = exp u + C.", "tan": "∫ tan u du = −ln|cos u| + C.",
                                    "ln": "∫ ln u du = u·ln u − u + C, for u > 0.", "sqrt": "∫ √u du = (2/3)u^(3/2) + C, on a real interval where u ≥ 0.",
                                    "sinh": "∫ sinh u du = cosh u + C.", "cosh": "∫ cosh u du = sinh u + C."]
                    if let formula = formulas[f] {
                        steps.append(Step(label: "Using a linear substitution", math: row(t("u = "), typeset(u, name), t(",  du = "), number(a), t(" d\(name)")), note: formula))
                        steps.append(Step(label: "Accounting for du/d\(name)", math: row(integral(e), t(" = "), typeset(F, name), t(" + C")),
                                          note: "Divide the primitive in u by \(number(a).plain), then substitute u back."))
                    }
                }
            case .op("/", let a, let b) where !a.hasUnknown && Algebra.linear(b) != nil:
                let slope = Algebra.linear(b)!.a
                steps.append(Step(label: "Logarithm rule for integration", math: row(t("∫ "), .fraction(t("1"), t("u")), t(" du = ln|u| + C")), note: "On an interval where u ≠ 0."))
                steps.append(Step(label: "Substituting the linear denominator", math: row(t("u = "), typeset(b, name), t(",  du = "), number(slope), t(" d\(name)"))))
            default: break
            }
        }
        steps.append(Step(label: "Combining the antiderivative", math: row(t("F(\(name)) = "), typeset(F, name))))
        if steps.count == 1, let back = Algebra.differentiated(F) {
            steps.append(Step(label: "Differentiating to check the antiderivative", math: row(t("F′(\(name)) = "), typeset(Algebra.cleaned(back), name)),
                              note: "Differentiating the proposed primitive must give the original integrand. This checks the result; it does not show how the primitive was found."))
        }
        return steps
    }
}

extension Expr {
    // Substitute the free unknown without replacing named constants or bound sum indices.
    func substitutingUnknown(_ value: Expr) -> Expr {
        switch self {
        case .unknown: return value
        case .neg(let a): return .neg(a.substitutingUnknown(value))
        case .op(let o, let a, let b): return .op(o, a.substitutingUnknown(value), b.substitutingUnknown(value))
        case .call(let f, let a): return .call(f, a.substitutingUnknown(value))
        case .apply(let f, let args): return .apply(f, args.map { $0.substitutingUnknown(value) })
        case .sum(let k, let a, let b, let body, let product):
            return .sum(k, from: a.substitutingUnknown(value), to: b.substitutingUnknown(value), body.substitutingUnknown(value), product: product)
        default: return self
        }
    }
}
