import Foundation

// An equation in sines and cosines that is true for every x, proved as it is on paper rather than
// tried at many values: each side written in sin x and cos x alone (sin 2x as 2 sin x cos x and
// cos 2x as cos²x − sin²x, any whole multiple of x by (cos x + i sin x)ⁿ), multiplied out, and
// every cos²x put as 1 − sin²x; where the two sides then come to the same expression, the
// equation is an identity. sin 2x + cos 2x − 1 = 2 sin x(cos x − sin x): the left side is
// 2 sin x cos x + cos²x − sin²x − 1, and both come to 2 sin x cos x − 2 sin²x.
// Only sines and cosines of whole multiples of x, numbers, +, −, ×, division by a number and whole
// powers are taken; anything else (tan x, x by itself) is left to be tried at many values.
struct TrigProof {
    // The coefficient of each sinⁱx cosʲx.
    struct Power: Hashable { var s: Int; var c: Int }
    typealias Terms = [Power: Number]

    var left: Terms, right: Terms                  // each side in sin x and cos x, multiplied out
    var reducedLeft: Terms, reducedRight: Terms    // with every cos²x put as 1 − sin²x
    var typedLeft: Expr, typedRight: Expr

    static func prove(_ eq: Equation) -> TrigProof? {
        guard let l = expanded(eq.left), let r = expanded(eq.right) else { return nil }
        // No sine or cosine in it, and it is a polynomial's to answer, not this.
        guard (Array(l.keys) + Array(r.keys)).contains(where: { $0.s > 0 || $0.c > 0 }) else { return nil }
        let (rl, rr) = (reduced(l), reduced(r))
        guard (Array(l.values) + Array(r.values) + Array(rl.values) + Array(rr.values)).allSatisfy(\.isExact),
              isZero(sum(rl, scaled(rr, -1))) else { return nil }
        return TrigProof(left: l, right: r, reducedLeft: rl, reducedRight: rr, typedLeft: eq.left, typedRight: eq.right)
    }

    // MARK: Working

    func steps(_ n: String) -> [Step] {
        derivation(n, expressionOnly: false)
    }

    // The same proof explains a simplification, not just an equation with an equals sign.
    func simplificationSteps(_ n: String) -> [Step] { derivation(n, expressionOnly: true) }

    private func derivation(_ n: String, expressionOnly: Bool) -> [Step] {
        guard Working.small(typedLeft, limit: 120), Working.small(typedRight, limit: 120) else {
            return [Step(label: "Reducing both sides with trigonometric identities", math: row(typeset(TrigProof.expr(reducedLeft), n), t(" = "), typeset(TrigProof.expr(reducedRight), n)),
                         note: "The expression is too long to display every substitution. Integer multiple-angle formulas and cos²x = 1 − sin²x reduce both sides to the same polynomial, using exact rational coefficients.")]
        }
        var steps: [Step] = [], formulas = Set<String>()
        let sine = Expr.call("sin", .unknown), cosine = Expr.call("cos", .unknown)
        func rewrite(_ e: Expr) -> Expr {
            switch e {
            case .call(let f, let a) where f == "sin" || f == "cos":
                guard let k = TrigProof.multiple(a), abs(k) > 1 else { return e }
                let replacement: Expr
                if k == 2, f == "cos" {
                    replacement = .op("-", .num(1), .op("*", .num(2), .op("^", sine, .num(2))))
                } else { replacement = TrigProof.expr(TrigProof.angle(f, k)) }
                if formulas.insert(typeset(e, n).plain).inserted {
                    steps.append(Step(label: abs(k) == 2 ? "Double-angle formula" : "Multiple-angle formula",
                                      math: row(typeset(e, n), t(" = "), typeset(replacement, n))))
                }
                return replacement
            case .neg(let a): return .neg(rewrite(a))
            case .op(let o, let a, let b): return .op(o, rewrite(a), rewrite(b))
            default: return e
            }
        }
        func transform(_ original: Expr, side: String) -> Terms {
            var current = original
            let replaced = rewrite(current)
            if typeset(replaced, n).plain != typeset(current, n).plain {
                current = replaced
                steps.append(Step(label: "Substituting into the \(side)", math: row(t("= "), typeset(current, n))))
            }
            let expanded = TrigProof.expanded(current)!
            let collected = TrigProof.expr(expanded)
            if typeset(collected, n).plain != typeset(current, n).plain {
                steps.append(Step(label: "Expanding brackets and collecting like terms", math: row(t("= "), typeset(collected, n))))
            }
            let reduced = TrigProof.reduced(expanded)
            if reduced != expanded {
                if formulas.insert("pythagorean").inserted {
                    steps.append(Step(label: "Pythagorean identity", math: row(typeset(.op("+", .op("^", sine, .num(2)), .op("^", cosine, .num(2))), n), t(" = 1")),
                                      note: "Replace cos²\(n) by 1 − sin²\(n)."))
                }
                steps.append(Step(label: "Substituting and collecting like terms in the \(side)", math: row(t("= "), typeset(TrigProof.expr(reduced), n))))
            }
            return reduced
        }
        let common = transform(typedLeft, side: expressionOnly ? "expression" : "left-hand side")
        let canonical = typeset(TrigProof.expr(common), n)
        if right == common {
            let target = typeset(typedRight, n)
            if target.plain != canonical.plain {
                var label = "Rewriting in the form of the right-hand side"
                if case .op("*", let a, let b) = typedRight {
                    if case .op(let op, _, _) = b, op == "+" || op == "-" { label = "Taking out the common factor \(typeset(a, n).plain)" }
                    else if case .op(let op, _, _) = a, op == "+" || op == "-" { label = "Taking out the common factor \(typeset(b, n).plain)" }
                }
                steps.append(Step(label: label, math: row(canonical, t(" = "), target), note: label.hasPrefix("Taking") ? "Use ab + ac = a(b + c), with the signs of the terms preserved." : "This is the same polynomial in sin and cos, written in the requested form."))
            }
        } else {
            _ = transform(typedRight, side: "right-hand side")
            steps.append(Step(label: "Comparing the reduced expressions", math: row(canonical, t(" = "), canonical)))
        }
        steps.append(Step(label: "Conclusion", math: nil, note: expressionOnly
                          ? "The expressions are equal by the identities above."
                          : "The left-hand side equals the right-hand side for every real \(n); the equation is an identity."))
        return steps
    }

    // MARK: Writing in sin x and cos x

    private static func expanded(_ e: Expr) -> Terms? {
        switch e {
        case .num(let v): return v == 0 ? [:] : [Power(s: 0, c: 0): Number(v)]
        case .neg(let a): return expanded(a).map { scaled($0, -1) }
        case .op("+", let a, let b):
            guard let x = expanded(a), let y = expanded(b) else { return nil }
            return sum(x, y)
        case .op("-", let a, let b):
            guard let x = expanded(a), let y = expanded(b) else { return nil }
            return sum(x, scaled(y, -1))
        case .op("*", let a, let b):
            guard let x = expanded(a), let y = expanded(b) else { return nil }
            return product(x, y)
        case .op("/", let a, .num(let k)) where k != 0:
            return expanded(a).map { scaled($0, Number(1) / Number(k)) }
        case .op("^", let a, .num(let k)) where k == k.rounded() && k >= 0 && k <= 12:
            guard let x = expanded(a) else { return nil }
            var result: Terms = [Power(s: 0, c: 0): 1]
            for _ in 0..<Int(k) { guard let next = product(result, x) else { return nil }; result = next }
            return result
        case .call(let f, let argument) where f == "sin" || f == "cos":
            guard let k = multiple(argument) else { return nil }
            return angle(f, k)
        default:
            return nil
        }
    }

    // k in sin(kx): a whole multiple of the unknown, and nothing added to it.
    private static func multiple(_ argument: Expr) -> Int? {
        guard let p = poly(argument).map(trim), p.count == 2, p[0] == 0, p[1] == p[1].rounded(), abs(p[1]) <= 12, p[1] != 0 else { return nil }
        return Int(p[1])
    }

    // cos kx and sin kx, the real and the imaginary parts of (cos x + i sin x)^k.
    private static func angle(_ f: String, _ k: Int) -> Terms {
        let n = abs(k)
        var terms: Terms = [:]
        for j in 0...n where (j % 2 == 0) == (f == "cos") {
            let choose = (0..<j).reduce(1) { $0 * (n - $1) / ($1 + 1) }
            let sign: Double = ((f == "cos" ? j : j - 1) / 2) % 2 == 0 ? 1 : -1
            let power = Power(s: j, c: n - j)
            terms[power] = (terms[power] ?? 0) + Number(Double(choose) * sign)
        }
        // sin(−kx) is −sin kx; cos(−kx) is cos kx.
        return f == "sin" && k < 0 ? scaled(terms, -1) : terms
    }

    // MARK: Arithmetic on them

    private static func cleaned(_ t: Terms) -> Terms { t.filter { !$0.value.isZero || !$0.value.isExact } }
    private static func scaled(_ t: Terms, _ k: Number) -> Terms { cleaned(t.mapValues { $0 * k }) }
    private static func sum(_ a: Terms, _ b: Terms) -> Terms { cleaned(a.merging(b, uniquingKeysWith: +)) }
    private static func product(_ a: Terms, _ b: Terms) -> Terms? {
        guard a.count * b.count <= 400 else { return nil }
        var out: Terms = [:]
        for (p, x) in a { for (q, y) in b {
            let power = Power(s: p.s + q.s, c: p.c + q.c)
            out[power] = (out[power] ?? 0) + x * y
        } }
        return cleaned(out)
    }
    private static func isZero(_ t: Terms) -> Bool { t.values.allSatisfy { $0.isExact && $0.isZero } }

    // Every cos²x put as 1 − sin²x, until no power of cos x above the first is left.
    private static func reduced(_ t: Terms) -> Terms {
        var t = t
        while let (power, value) = t.first(where: { $0.key.c >= 2 }) {
            t[power] = nil
            let lower = Power(s: power.s, c: power.c - 2), raised = Power(s: power.s + 2, c: power.c - 2)
            t[lower] = (t[lower] ?? 0) + value
            t[raised] = (t[raised] ?? 0) - value
            t = cleaned(t)
        }
        return t
    }

    // MARK: Writing them down

    // The terms as an expression to typeset: the highest powers first, those with more of cos x
    // before those with less, so that 2 sin x cos x comes before 2 sin²x; the number last.
    static func expr(_ t: Terms) -> Expr {
        let order = t.keys.sorted { a, b in
            a.s + a.c != b.s + b.c ? a.s + a.c > b.s + b.c : a.c > b.c
        }
        var result: Expr?
        for power in order {
            guard let value = t[power] else { continue }
            var factors: [Expr] = []
            if power.s > 0 { factors.append(power.s == 1 ? .call("sin", .unknown) : .op("^", .call("sin", .unknown), .num(Double(power.s)))) }
            if power.c > 0 { factors.append(power.c == 1 ? .call("cos", .unknown) : .op("^", .call("cos", .unknown), .num(Double(power.c)))) }
            let size = value.magnitude
            let coefficient: Expr = size.rational.map { $0.bottom == 1 ? .num(Double($0.top)) : .op("/", .num(Double($0.top)), .num(Double($0.bottom))) } ?? .num(size.double)
            var term = factors.dropFirst().reduce(factors.first ?? coefficient) { .op("*", $0, $1) }
            if !factors.isEmpty, size != 1 { term = .op("*", coefficient, term) }
            if let sofar = result { result = .op(value < 0 ? "-" : "+", sofar, term) } else { result = value < 0 ? .neg(term) : term }
        }
        return result ?? .num(0)
    }
}
