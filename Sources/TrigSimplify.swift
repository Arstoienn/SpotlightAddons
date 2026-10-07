import Foundation

// sin²x + cos²x is 1; sin x / cos x is tan x; 2 sin x cos x is sin 2x; 1 − 2 sin²x is cos 2x. An expression
// in the sines, cosines and tangents of the one letter is looked at as a function of that letter,
// and the simplest expression of a few kinds that is the same function is put in its place: a
// number, one function of x or a multiple of x, or the sum of two. It is the same function when
// it comes out equal at every one of a few dozen values of x, to the last figures.
struct TrigSimplification {
    var expr: Expr
    var result: Expr
    var name: String
    var approximate = false      // the numbers in it written as decimals

    private static let sampleXs: [Double] = (0..<48).map { (i: Int) -> Double in
        let step: Double = Double(i) * 0.1331
        let wobble: Double = sin(Double(i) * 1.7) * 0.05
        return 0.13 + step + wobble
    }

    // How much there is in it: the sines and the like first, then everything.
    private static func size(_ e: Expr) -> (calls: Int, nodes: Int) {
        switch e {
        case .num, .unknown, .index, .constant: return (0, 1)
        case .neg(let a): let s = size(a); return (s.calls, s.nodes + 1)
        case .op(_, let a, let b): let (x, y) = (size(a), size(b)); return (x.calls + y.calls, x.nodes + y.nodes + 1)
        case .call(_, let a): let s = size(a); return (s.calls + 1, s.nodes + 1)
        case .apply(_, let args): let s = args.map(size); return (s.reduce(0) { $0 + $1.calls }, s.reduce(0) { $0 + $1.nodes } + 1)
        case .sum: return (99, 99)
        }
    }

    // The sines, cosines and tangents in it, with their arguments; nil where there is anything else
    // that is a function of the letter (e^x, √x), which this is not for.
    private static func trigCalls(_ e: Expr, _ found: inout [(name: String, argument: Expr)], _ constants: inout [Expr]) -> Bool {
        switch e {
        case .num, .unknown, .constant: return true
        case .index, .sum, .apply: return false
        case .neg(let a): return trigCalls(a, &found, &constants)
        case .op(let o, let a, let b):
            guard Binary.table[o] == nil else { return false }
            return trigCalls(a, &found, &constants) && trigCalls(b, &found, &constants)
        case .call(let f, let a):
            let name = f.hasSuffix("°") ? String(f.dropLast()) : f
            guard ["sin", "cos", "tan", "sec", "csc", "cot"].contains(name) else { return false }
            // sin 0.3 is a number, to be taken as one.
            if !a.hasUnknown { constants.append(e); return true }
            guard poly(a).map(trim)?.count == 2 else { return false }
            found.append((f, a))
            return true
        }
    }

    static func parse(_ input: String) -> TrigSimplification? {
        guard Options.algebra, !input.contains("="), input.contains(where: { "sctSCT".contains($0) }) else { return nil }
        guard var tokens = try? Parser.tokenize(input), tokens.contains(where: { if case .function = $0 { true } else { false } }) else { return nil }
        tokens = tokens.map { $0 == .letter("e") ? .constant(M_E) : $0 }
        var letters: [String] = []
        for token in tokens { if case .letter(let s) = token, !letters.contains(s) { letters.append(s) } }
        guard letters.count == 1, let name = letters.first,
              let expr = try? Parser.expression(tokens, constants: []) else { return nil }
        var calls: [(name: String, argument: Expr)] = []
        var constants: [Expr] = []
        guard trigCalls(expr, &calls, &constants), !calls.isEmpty else { return nil }
        // All in radians or all in degrees.
        let degrees = calls.contains { $0.name.hasSuffix("°") }
        guard calls.allSatisfy({ $0.name.hasSuffix("°") == degrees }) else { return nil }
        let suffix = degrees ? "°" : ""

        // What it is, at each of the values.
        let xs = sampleXs.map { degrees ? $0 * 180 / .pi : $0 }
        let target = xs.map { expr.eval($0) }
        guard target.filter(\.isFinite).count >= 36, target.allSatisfy({ !$0.isFinite || abs($0) < 1e8 }) else { return nil }
        let usable = target.indices.filter { target[$0].isFinite }

        // The candidates: the arguments are x and its multiples, and the arguments there are.
        func argument(_ k: Double) -> Expr { k == 1 ? .unknown : k < 1 ? .op("/", .unknown, .num(1 / k)) : .op("*", .num(k), .unknown) }
        var arguments: [Expr] = [argument(1)]
        func addArgument(_ e: Expr) {
            let text = typeset(e, name).plain
            if !arguments.contains(where: { typeset($0, name).plain == text }) { arguments.append(e) }
        }
        // What was typed, and twice and half of that: a sine of 2x meets a cosine of x, and one of 4x.
        for call in calls {
            addArgument(call.argument)
            if let p = poly(call.argument).map(trim), p.count == 2, p[0] == 0 {
                addArgument(argument(p[1] * 2))
                addArgument(argument(p[1] / 2))
            }
        }
        let functions = degrees ? ["sin", "cos", "tan"] : ["sin", "cos", "tan", "cot", "sec", "csc"]
        var bases: [(expr: Expr, values: [Double])] = []
        for arg in arguments {
            for f in functions {
                for power in [1.0, 2.0] {
                    let base: Expr = .call(f + suffix, arg)
                    let e: Expr = power == 1 ? base : .op("^", base, .num(2))
                    let values = xs.map { e.eval($0) }
                    if usable.allSatisfy({ values[$0].isFinite }) { bases.append((e, values)) }
                }
            }
        }
        let one = (expr: Expr.num(1), values: [Double](repeating: 1, count: xs.count))
        bases.append(one)

        let own = size(expr)
        // Nothing at all: 1 − sin²x − cos²x.
        if usable.allSatisfy({ abs(target[$0]) < 1e-9 }) {
            guard own.calls > 0 else { return nil }
            return TrigSimplification(expr: expr, result: .num(0), name: name)
        }
        var best: (expr: Expr, score: (Int, Int, Int))?
        func consider(_ e: Expr, terms: Int) {
            let s = size(e)
            let score = (s.calls, terms, s.nodes)
            if let b = best, !(score < b.score) { return }
            best = (e, score)
        }
        func close(_ fit: [Double], _ basisValues: [[Double]]) -> Bool {
            usable.allSatisfy { i in
                let g = zip(fit, basisValues).reduce(0.0) { $0 + $1.0 * $1.1[i] }
                return abs(g - target[i]) <= 1e-9 * max(1, abs(target[i]))
            }
        }
        // A coefficient that is a plain fraction: 1/2, 2, −1.
        func nice(_ c: Double) -> Double? {
            guard c.isFinite, abs(c) < 50 else { return nil }
            for q in 1...6 where abs(c * Double(q) - (c * Double(q)).rounded()) < 1e-9 { return (c * Double(q)).rounded() / Double(q) }
            return nil
        }
        func term(_ c: Double, _ e: Expr) -> Expr {
            if case .num = e { return .num(c) }
            let (p, q) = rational(abs(c)) ?? (Int(abs(c)), 1)
            var t: Expr = p == 1 ? e : .op("*", .num(Double(p)), e)
            if q != 1 { t = .op("/", t, .num(Double(q))) }
            return c < 0 ? .neg(t) : t
        }
        func sum(_ parts: [Expr]) -> Expr {
            parts.dropFirst().reduce(parts[0]) { acc, t in
                if case .neg(let inner) = t { return .op("-", acc, inner) }
                return .op("+", acc, t)
            }
        }

        // One term.
        for b in bases {
            let n = usable.reduce(0.0) { $0 + b.values[$1] * b.values[$1] }
            guard n > 1e-12 else { continue }
            let c = usable.reduce(0.0) { $0 + b.values[$1] * target[$1] } / n
            if let c = nice(c), c != 0, close([c], [b.values]) { consider(term(c, b.expr), terms: 1) }
            // A multiple of a number that was in it, sin 0.3 times a function of x.
            else if close([c], [b.values]) {
                for k in constants {
                    let value = k.eval(0)
                    guard value.isFinite, abs(value) > 1e-9, let r = nice(c / value), r != 0 else { continue }
                    consider(term(r, .op("*", k, b.expr)), terms: 1)
                }
            }
        }
        // Two terms, where one was not enough or is not the simplest.
        if best == nil || best!.score.0 > 1 {
            // The first few values settle most pairs; the rest are looked at for those that survive.
            let few = Array(usable.prefix(5)), spare = Array(usable.dropFirst(5).prefix(4))
            for i in bases.indices {
                for j in bases.indices where j > i {
                    let (u, v) = (bases[i], bases[j])
                    var (qa, qb, qd, qy, qz) = (0.0, 0.0, 0.0, 0.0, 0.0)
                    for k in few { qa += u.values[k] * u.values[k]; qb += u.values[k] * v.values[k]; qd += v.values[k] * v.values[k]; qy += u.values[k] * target[k]; qz += v.values[k] * target[k] }
                    let qdet = qa * qd - qb * qb
                    guard abs(qdet) > 1e-9 * max(1, qa * qd) else { continue }
                    let (q1, q2) = ((qy * qd - qz * qb) / qdet, (qa * qz - qb * qy) / qdet)
                    guard spare.allSatisfy({ abs(q1 * u.values[$0] + q2 * v.values[$0] - target[$0]) <= 1e-6 * max(1, abs(target[$0])) }) else { continue }
                    var (a, b, d, ty, tz) = (0.0, 0.0, 0.0, 0.0, 0.0)
                    for k in usable { a += u.values[k] * u.values[k]; b += u.values[k] * v.values[k]; d += v.values[k] * v.values[k]; ty += u.values[k] * target[k]; tz += v.values[k] * target[k] }
                    let det = a * d - b * b
                    guard abs(det) > 1e-9 * max(1, a * d) else { continue }
                    let c1 = (ty * d - tz * b) / det, c2 = (a * tz - b * ty) / det
                    guard let n1 = nice(c1), let n2 = nice(c2), n1 != 0, n2 != 0, close([n1, n2], [u.values, v.values]) else { continue }
                    consider(sum([term(n1, u.expr), term(n2, v.expr)]), terms: 2)
                }
            }
        }
        let theirs = (own.calls, 99, own.nodes)
        if let found = best, found.score.0 < theirs.0 || (found.score.0 == theirs.0 && found.score.2 < theirs.2) {
            return TrigSimplification(expr: expr, result: found.expr, name: name)
        }
        // Nothing simpler in sines of x; but a sine of a number is a number, and is written as one.
        if !constants.isEmpty {
            func folded(_ e: Expr) -> Expr {
                if !e.hasUnknown { return .num(e.eval(0)) }
                switch e {
                case .neg(let a): return .neg(folded(a))
                case .op(let o, let a, let b): return .op(o, folded(a), folded(b))
                case .call(let f, let a): return .call(f, folded(a))
                default: return e
                }
            }
            let result = Algebra.cleaned(folded(expr))
            if typeset(result, name).plain != typeset(expr, name).plain { return TrigSimplification(expr: expr, result: result, name: name, approximate: true) }
        }
        return nil
    }

    private var shown: Math { typeset(result, name) }

    var solution: Solution {
        approximate ? Solution(exact: "≈ " + shown.plain, approx: "The numbers in it worked out")
                    : Solution(exact: "= " + shown.plain, approx: "By a trigonometric identity")
    }

    var details: Details {
        var d = Details(name: name, equation: typeset(expr, name), steps: [], solutions: [row(t(approximate ? "≈ " : "= "), shown)], note: nil, f: { [expr] in expr.eval($0) }, roots: [])
        d.steps.append(approximate
            ? Step(label: "Working out the numbers", math: row(t("≈ "), shown), note: "A sine or cosine of a number is a number, and is written here as a decimal.")
            : Step(label: "Simplifying with trigonometric identities", math: row(t("= "), shown),
                   note: "The two expressions agree at every one of 48 values of \(name) tried, to the last figures: they are the same function."))
        return d
    }

    var copyText: String { shown.plain.replacingOccurrences(of: "−", with: "-") }
}
