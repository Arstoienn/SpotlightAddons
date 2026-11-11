import Foundation

// An identity in two angles or more, sin(A + B) = sin A cos B + cos A sin B, proved as on paper: each
// sine and cosine of a sum or difference of the angles written by the compound-angle formulas, from
// cos(A + B) + i sin(A + B) = (cos A + i sin A)(cos B + i sin B), each side multiplied out, and every
// cos² put as 1 − sin²; where the two sides then come to the same expression, the equation holds for
// every A and B. An identity in one angle is TrigProof's.
struct AngleIdentity {
    // sinᵃA cosᵇA sinᶜB …: the power of each, "sA" and "cA" for sin A and cos A.
    struct Monomial: Hashable { var powers: [String: Int] }
    typealias Terms = [Monomial: Double]

    var left: Expr, right: Expr
    var angles: [String]
    var expandedLeft: Terms, expandedRight: Terms
    var squaresRewritten: Bool      // whether a cos² had to be put as 1 − sin²

    static func prove(_ input: String) -> AngleIdentity? {
        guard let roles = Roles.of(input), roles.tree.count == 1, let statement = roles.tree.first, let right = statement.right else { return nil }
        let angles = roles.letters.filter { $0 != "e" }
        guard angles.count >= 2, let l = expanded(statement.left), let r = expanded(statement.right!) else { return nil }
        let (rl, rr) = (reduced(l), reduced(r))
        guard (Array(rl.keys) + Array(rr.keys)).contains(where: { !$0.powers.isEmpty }) || !l.isEmpty,
              isZero(sum(rl, scaled(rr, -1))) else { return nil }
        return AngleIdentity(left: statement.left, right: right, angles: angles, expandedLeft: rl, expandedRight: rr, squaresRewritten: rl != l || rr != r)
    }

    private var every: String { angles.count == 2 ? "\(angles[0]) and \(angles[1])" : angles.dropLast().joined(separator: ", ") + " and " + angles.last! }

    var solution: Solution {
        Solution(exact: angles.joined(separator: ", ") + " ∈ ℝ", approx: "An identity: the two sides are equal for every \(every).")
    }

    // MARK: Working

    var details: Details {
        var steps: [Step] = [], formulas = Set<String>()
        // Each sine or cosine of a sum, a difference or a multiple, written by its formula.
        func rewrite(_ e: Expr) -> Expr {
            switch e {
            case .call(let f, let a) where f == "sin" || f == "cos":
                guard let combination = AngleIdentity.combination(a), combination.count > 1 || combination.values.contains(where: { abs($0) > 1 }) else { return e }
                let replacement = AngleIdentity.expr(AngleIdentity.angle(f, combination))
                if formulas.insert(typeset(e, "").plain).inserted {
                    steps.append(Step(label: combination.count > 1 ? "Applying the compound-angle formula" : "Applying the multiple-angle formula",
                                      math: row(typeset(e, ""), t(" = "), typeset(replacement, ""))))
                }
                return replacement
            case .neg(let a): return .neg(rewrite(a))
            case .op(let o, let a, let b): return .op(o, rewrite(a), rewrite(b))
            default: return e
            }
        }
        let (l, r) = (rewrite(left), rewrite(right))
        let (shownLeft, shownRight) = (AngleIdentity.expr(expandedLeft), AngleIdentity.expr(expandedRight))
        if typeset(shownLeft, "").plain != typeset(l, "").plain || typeset(shownRight, "").plain != typeset(r, "").plain {
            steps.append(Step(label: "Expanding and collecting like terms", math: row(typeset(shownLeft, ""), t(" = "), typeset(shownRight, "")),
                              note: squaresRewritten ? "Each square of a cosine is written as 1 less the square of the sine." : nil))
        }
        steps.append(Step(label: "Hence", math: nil, note: "The two sides are the same expression; the equation is an identity, true for every \(every)."))
        return Details(name: "", equation: row(typeset(left, ""), t(" = "), typeset(right, "")), steps: steps,
                       solutions: [t(solution.exact)], note: nil, f: { _ in .nan }, roots: [])
    }

    // MARK: Writing in sines and cosines of each angle

    private static func expanded(_ e: Expr) -> Terms? {
        switch e {
        case .num(let v): return v == 0 ? [:] : [Monomial(powers: [:]): v]
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
            return expanded(a).map { scaled($0, 1 / k) }
        case .op("^", let a, .num(let k)) where k == k.rounded() && k >= 0 && k <= 8:
            guard let x = expanded(a) else { return nil }
            var result: Terms = [Monomial(powers: [:]): 1]
            for _ in 0..<Int(k) { guard let next = product(result, x) else { return nil }; result = next }
            return result
        case .call(let f, let argument) where f == "sin" || f == "cos":
            guard let combination = combination(argument) else { return nil }
            return angle(f, combination)
        default:
            return nil
        }
    }

    // A + B, A − 2B, 3A: each angle with its whole multiple, and nothing added to them.
    private static func combination(_ e: Expr) -> [String: Int]? {
        switch e {
        case .index(let name): return [name: 1]
        case .neg(let a): return combination(a).map { $0.mapValues { -$0 } }
        case .op("+", let a, let b), .op("-", let a, let b):
            guard let x = combination(a), var y = combination(b) else { return nil }
            if case .op("-", _, _) = e { y = y.mapValues { -$0 } }
            return x.merging(y, uniquingKeysWith: +).filter { $0.value != 0 }
        case .op("*", .num(let k), let a), .op("*", let a, .num(let k)):
            guard k == k.rounded(), abs(k) <= 8, let x = combination(a) else { return nil }
            return x.mapValues { $0 * Int(k) }
        default: return nil
        }
    }

    // cos and sin of Σ kᵥ v: the real and imaginary parts of the product of (cos v + i sin v)^kᵥ.
    private static func angle(_ f: String, _ combination: [String: Int]) -> Terms {
        var real: Terms = [Monomial(powers: [:]): 1], imaginary: Terms = [:]
        for (name, k) in combination.sorted(by: { $0.key < $1.key }) {
            let sign: Double = k < 0 ? -1 : 1
            for _ in 0..<abs(k) {
                // (re + i im)(cos v + i·sign·sin v)
                let cosine: Terms = [Monomial(powers: ["c" + name: 1]): 1], sine: Terms = [Monomial(powers: ["s" + name: 1]): sign]
                let newReal = sum(product(real, cosine) ?? [:], scaled(product(imaginary, sine) ?? [:], -1))
                let newImaginary = sum(product(real, sine) ?? [:], product(imaginary, cosine) ?? [:])
                (real, imaginary) = (newReal, newImaginary)
            }
        }
        return f == "cos" ? real : imaginary
    }

    // MARK: Arithmetic on them

    private static func cleaned(_ t: Terms) -> Terms { t.filter { abs($0.value) > 1e-12 } }
    private static func scaled(_ t: Terms, _ k: Double) -> Terms { cleaned(t.mapValues { $0 * k }) }
    private static func sum(_ a: Terms, _ b: Terms) -> Terms { cleaned(a.merging(b, uniquingKeysWith: +)) }
    private static func product(_ a: Terms, _ b: Terms) -> Terms? {
        guard a.count * b.count <= 2000 else { return nil }
        var out: Terms = [:]
        for (p, x) in a {
            for (q, y) in b { out[Monomial(powers: p.powers.merging(q.powers, uniquingKeysWith: +)), default: 0] += x * y }
        }
        return cleaned(out)
    }
    private static func isZero(_ t: Terms) -> Bool { t.values.allSatisfy { abs($0) <= 1e-9 } }

    // Every cos² of an angle put as 1 − its sin², until no cosine is above the first power.
    private static func reduced(_ t: Terms) -> Terms {
        var t = t
        while let (mono, value) = t.first(where: { $0.key.powers.contains { $0.key.hasPrefix("c") && $0.value >= 2 } }) {
            let key = mono.powers.first { $0.key.hasPrefix("c") && $0.value >= 2 }!.key
            let sine = "s" + key.dropFirst()
            t[mono] = nil
            var lower = mono.powers, raised = mono.powers
            lower[key]! -= 2
            raised[key]! -= 2
            raised[sine, default: 0] += 2
            t[Monomial(powers: lower.filter { $0.value != 0 }), default: 0] += value
            t[Monomial(powers: raised.filter { $0.value != 0 }), default: 0] -= value
            t = cleaned(t)
        }
        return t
    }

    // MARK: Writing them down

    // The terms as an expression to typeset, the higher powers first, each angle's sine before its cosine.
    static func expr(_ t: Terms) -> Expr {
        func degree(_ m: Monomial) -> Int { m.powers.values.reduce(0, +) }
        func order(_ m: Monomial) -> String { m.powers.keys.sorted { ($0.dropFirst(), $0.first == "s" ? 0 : 1) < ($1.dropFirst(), $1.first == "s" ? 0 : 1) }.map { "\($0)\(m.powers[$0]!)" }.joined() }
        let monomials = t.keys.sorted { degree($0) != degree($1) ? degree($0) > degree($1) : order($0) < order($1) }
        var result: Expr?
        for mono in monomials {
            guard let value = t[mono] else { continue }
            let keys = mono.powers.keys.sorted { ($0.dropFirst(), $0.first == "s" ? 0 : 1) < ($1.dropFirst(), $1.first == "s" ? 0 : 1) }
            var factors: [Expr] = []
            for key in keys {
                let call = Expr.call(key.first == "s" ? "sin" : "cos", .index(String(key.dropFirst())))
                let power = mono.powers[key]!
                factors.append(power == 1 ? call : .op("^", call, .num(Double(power))))
            }
            let size = abs(value)
            var term = factors.dropFirst().reduce(factors.first ?? .num(size)) { .op("*", $0, $1) }
            if !factors.isEmpty, abs(size - 1) > 1e-12 { term = .op("*", .num(size), term) }
            if let sofar = result { result = .op(value < 0 ? "-" : "+", sofar, term) } else { result = value < 0 ? .neg(term) : term }
        }
        return result ?? .num(0)
    }
}
