import Foundation

// An equation with the unknown in a denominator: 1/x + 1/(x+1) = 1. Each side is a polynomial over a
// polynomial; cleared of its fractions it is a polynomial equation, solved as any is, exactly. A root
// that makes a denominator nothing is no solution of what was typed, and is struck out.
struct RationalEquation {
    struct Fraction {
        var top: Poly, bottom: Poly

        static func + (a: Fraction, b: Fraction) -> Fraction { Fraction(top: add(mul(a.top, b.bottom), mul(b.top, a.bottom)), bottom: mul(a.bottom, b.bottom)) }
        static func * (a: Fraction, b: Fraction) -> Fraction { Fraction(top: mul(a.top, b.top), bottom: mul(a.bottom, b.bottom)) }
        var negated: Fraction { Fraction(top: top.map { -$0 }, bottom: bottom) }
        var reciprocal: Fraction? { trim(top).isEmpty ? nil : Fraction(top: bottom, bottom: top) }
    }

    var equation: Equation
    var cleared: Poly              // numerator of left − right, over the denominators
    var excluded: [Double]         // roots of the denominators, where it is undefined
    var removed: [Double]          // excluded values that were roots of the cleared polynomial, taken out of it
    var reduced: Poly              // what is left to solve
    var denominators: Poly

    static func fractionOf(_ e: Expr) -> Fraction? {
        switch e {
        case .num(let v), .constant(_, let v): return Fraction(top: [v], bottom: [1])
        case .unknown: return Fraction(top: [0, 1], bottom: [1])
        case .neg(let a): return fractionOf(a)?.negated
        case .op(let o, let a, let b):
            guard let x = fractionOf(a), let y = fractionOf(b) else { return nil }
            switch o {
            case "+": return x + y
            case "-": return x + y.negated
            case "*": return x * y
            case "/": return y.reciprocal.map { x * $0 }
            case "^":
                guard case .num(let k) = b, k == k.rounded(), abs(k) <= 12 else { return nil }
                var r = Fraction(top: [1], bottom: [1])
                for _ in 0..<Int(abs(k)) { r = r * x }
                return k < 0 ? r.reciprocal : r
            default: return nil
            }
        default: return nil
        }
    }

    static func parse(_ eq: Equation) -> RationalEquation? {
        guard eq.constants.isEmpty, eq.left.hasUnknown || eq.right.hasUnknown, let l = fractionOf(eq.left), let r = fractionOf(eq.right) else { return nil }
        // Only where there is a fraction with the unknown below its line.
        let lowers = [trim(l.bottom), trim(r.bottom)]
        guard lowers.contains(where: { $0.count > 1 }) else { return nil }
        let cleared = trim(sub(mul(l.top, r.bottom), mul(r.top, l.bottom)))
        let denominators = trim(mul(l.bottom, r.bottom))
        guard cleared.count <= 9, denominators.count >= 2, cleared.allSatisfy(\.isFinite), denominators.allSatisfy(\.isFinite) else { return nil }
        let excluded = realRoots(denominators).sorted()
        // A value that is a root of both is struck out of the polynomial, as often as it divides it.
        var reduced = cleared
        var removed: [Double] = []
        for r in excluded {
            var guardCount = 0
            while reduced.count > 1, abs(value(reduced, r)) <= 1e-9 * (reduced.map(abs).max() ?? 1) * max(1, pow(abs(r), Double(reduced.count))), guardCount < 12 {
                reduced = divide(reduced, byRoot: r)
                if !removed.contains(where: { abs($0 - r) < 1e-12 }) { removed.append(r) }
                guardCount += 1
            }
        }
        return RationalEquation(equation: eq, cleared: cleared, excluded: excluded, removed: removed, reduced: trim(reduced), denominators: denominators)
    }

    private static func value(_ p: Poly, _ x: Double) -> Double { p.reversed().reduce(0) { $0 * x + $1 } }

    // p ÷ (x − r), for a root r.
    private static func divide(_ p: Poly, byRoot r: Double) -> Poly {
        var out: Poly = []
        var carry = 0.0
        for k in stride(from: p.count - 1, through: 1, by: -1) {
            carry = p[k] + carry * r
            out.append(carry)
        }
        return Array(out.reversed()).map { abs($0) < 1e-12 ? 0 : $0 }
    }

    // What is excluded, written: x ≠ 0, −1.
    var exclusionText: String? {
        guard !excluded.isEmpty else { return nil }
        return "\(equation.unknown) ≠ " + excluded.map { x in rational(x).map { fraction($0.0, $0.1) } ?? decimal(x) }.joined(separator: ", ")
    }

    var solution: Solution? {
        let name = equation.unknown
        // Everything but the excluded values: the equation was an identity.
        if reduced.isEmpty { return Solution(exact: "\(name) ∈ ℝ, \(exclusionText ?? "")", approx: "Every real number satisfies it where it is defined.") }
        if reduced.count == 1 {
            let values = removed.map { x in rational(x).map { fraction($0.0, $0.1) } ?? decimal(x) }.joined(separator: ", ")
            return Solution(exact: "No solution", approx: removed.isEmpty ? nil : "The cleared equation is satisfied only by \(equation.unknown) = \(values), which makes a denominator zero.")
        }
        var s = solvePolynomial(reduced, name, exact: Options.exact)
        // A root left that is a denominator's must not be offered.
        if let numeric = Optional(realRoots(reduced)), numeric.contains(where: { r in excluded.contains { abs($0 - r) <= 1e-9 * max(1, abs(r)) } }) {
            let kept = numeric.filter { r in !excluded.contains { abs($0 - r) <= 1e-9 * max(1, abs(r)) } }
            s = kept.isEmpty ? Solution(exact: "No solution", approx: nil) : listRoots(kept, name, more: false)
        }
        if let note = exclusionText, s.exact != "No solution", s.approx == nil, !removed.isEmpty { s.approx = "\(note) was struck out." }
        return s
    }

    var roots: [Double] {
        realRoots(reduced).filter { r in !excluded.contains { abs($0 - r) <= 1e-9 * max(1, abs(r)) } }.sorted()
    }

    func details(_ header: Math, f: @escaping (Double) -> Double) -> Details {
        let name = equation.unknown
        var d = polynomialDetails(reduced, name, header, f, exact: Options.exact)
        var steps: [Step] = [Step(label: "Multiplying through by the denominators", math: row(polyMath(cleared, name), t(" = 0")),
                                  note: "Each side is brought over a common denominator, and the denominators are cleared.")]
        if let note = exclusionText {
            steps.append(Step(label: "Excluding what makes a denominator zero", math: t(note),
                              note: removed.isEmpty ? "These values are not in the domain, and are never solutions." : "These values are not in the domain; \(removed.map { decimal($0) }.joined(separator: ", ")) satisfies the cleared equation, and is struck out."))
        }
        if !removed.isEmpty, reduced.count >= 2 { steps.append(Step(label: "Dividing out the factor that vanishes there", math: row(polyMath(reduced, name), t(" = 0")))) }
        d.steps = steps + d.steps
        d.roots = roots
        return d
    }
}
