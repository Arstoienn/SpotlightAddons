import Foundation

// x^2 - 4 > 0 is not solved for a number but for the numbers that satisfy it: x < −2 or x > 2. The
// two sides are put on one side, where the expression is a polynomial, and the intervals between
// its roots are each tried for the sign it takes.
struct Inequality {
    var left: Expr, right: Expr
    var relation: Comparison.Relation
    var name: String
    var p: Poly?              // left − right, where that is a polynomial
    var roots: [Double]       // distinct, in order

    private enum Piece { case region(Int), root(Int) }

    static func parse(_ input: String, forSet: Bool = false) -> Inequality? {
        guard Options.inequalities, let found = Comparison.relation(in: input),
              [.less, .greater, .atMost, .atLeast, .notEqual].contains(found.relation) else { return nil }
        let sides = [String(input[..<found.range.lowerBound]), String(input[found.range.upperBound...])]
        guard var l = try? Parser.tokenize(sides[0]), var r = try? Parser.tokenize(sides[1]), !l.isEmpty, !r.isEmpty else { return nil }
        let ks = Parser.indices(l + r)
        (l, r) = (l.map { $0 == .letter("e") && !ks.contains("e") ? .constant(M_E) : $0 },
                  r.map { $0 == .letter("e") && !ks.contains("e") ? .constant(M_E) : $0 })
        guard let roles = Parser.roles(l + [.symbol("=")] + r), let name = roles.unknown,
              let left = try? Parser.expression(l, constants: roles.constants),
              let right = try? Parser.expression(r, constants: roles.constants) else { return nil }
        // x > 3 is already its own answer.
        if !forSet, found.relation != .notEqual, case .unknown = left, case .num = right { return nil }
        var candidates: [Double]
        var p: Poly?
        if let a = poly(left), let b = poly(right) {
            let q = trim(sub(a, b))
            guard q.count <= 9, q.allSatisfy(\.isFinite) else { return nil }
            p = q
            candidates = q.count >= 2 ? realRoots(q).sorted() : []
        } else {
            // Not a polynomial: only what is defined all along the line, abs and exp and the like,
            // where the signs between the roots can be tried without meeting a gap.
            guard total(left), total(right), left.hasUnknown || right.hasUnknown,
                  let roots = numericRoots(Equation(left: left, right: right, unknown: name)) else { return nil }
            candidates = roots.sorted()
        }
        var distinct: [Double] = []
        for root in candidates {
            if let last = distinct.last, abs(root - last) <= 1e-9 * max(1, abs(root)) { continue }
            distinct.append(root)
        }
        return Inequality(left: left, right: right, relation: found.relation, name: name, p: p, roots: distinct)
    }

    // Whether the expression has a value for every real number.
    private static func total(_ e: Expr) -> Bool {
        switch e {
        case .num, .constant, .unknown, .index: return true
        case .neg(let a): return total(a)
        case .op(let o, let a, let b):
            guard total(a), total(b) else { return false }
            if o == "/" { return !b.hasUnknown }
            if o == "^" { return !(a.hasUnknown && b.hasUnknown) && (a.hasUnknown ? { if case .num(let n) = b { n == n.rounded() && n >= 0 } else { false } }() : a.eval(0) > 0) }
            return Binary.table[o] == nil
        case .call(let f, let a): return ["abs", "exp", "atan", "sinh", "cosh", "tanh", "cbrt"].contains(f) && total(a)
        case .sum, .apply: return false
        }
    }

    private func value(at x: Double) -> Double {
        if let p { return p.reversed().reduce(0) { $0 * x + $1 } }
        return left.eval(x) - right.eval(x)
    }

    private func satisfied(by v: Double) -> Bool {
        switch relation {
        case .greater: return v > 0
        case .less: return v < 0
        case .atLeast: return v >= 0
        case .atMost: return v <= 0
        default: return v != 0
        }
    }

    // A point inside each region, and the pieces in order: region, root, region, …, region.
    private var tests: [Double] {
        guard !roots.isEmpty else { return [0] }
        var points = [roots[0] - max(1, abs(roots[0]) * 0.5)]
        for i in 1..<roots.count { points.append((roots[i - 1] + roots[i]) / 2) }
        points.append(roots[roots.count - 1] + max(1, abs(roots[roots.count - 1]) * 0.5))
        return points
    }

    private var pieces: [(piece: Piece, holds: Bool)] {
        let points = tests
        var out: [(Piece, Bool)] = []
        for i in points.indices {
            out.append((.region(i), satisfied(by: value(at: points[i]))))
            if i < roots.count { out.append((.root(i), satisfied(by: 0))) }
        }
        return out.map { (piece: $0.0, holds: $0.1) }
    }

    // A boundary as exactly as it can be written: a fraction, or the surd of a quadratic with whole
    // coefficients; otherwise a decimal.
    private func label(_ i: Int, exactly: Bool) -> String {
        let x = roots[i]
        guard exactly else { return decimal(x) }
        if let (top, bottom) = rational(x), abs(value(at: x)) <= 1e-9 * max(1, p?.map(abs).max() ?? abs(left.eval(x)) + abs(right.eval(x))) { return fraction(top, bottom) }
        if let p, p.count == 3, let c = integerCoefficients(p), c[1] * c[1] - 4 * c[2] * c[0] > 0 {
            let (a, b, cc) = (c[2], c[1], c[0])
            let d = b * b - 4 * a * cc
            let (bb, kk, m, den) = radicalForm(a, b, d)
            let radical = (kk == 1 ? "" : "\(kk)") + "√\(m)"
            let lower = roots.count == 2 ? i == 0 : x < Double(-b) / Double(2 * a)
            let sign = lower ? "−" : "+"
            let top = bb == 0 ? (lower ? "−" : "") + radical : "\(minus(bb)) \(sign) \(radical)"
            return den == 1 ? top : bb == 0 ? "\(top)/\(den)" : "(\(top))/\(den)"
        }
        return decimal(x)
    }

    // The numbers that satisfy it, as intervals with their ends written exactly and in decimals.
    var set: IntervalSet {
        func bound(_ i: Int) -> Bound { Bound(value: roots[i], exact: label(i, exactly: true), decimal: label(i, exactly: false)) }
        let all = pieces
        var items: [Interval] = []
        var i = 0
        while i < all.count {
            guard all[i].holds else { i += 1; continue }
            var j = i
            while j + 1 < all.count, all[j + 1].holds { j += 1 }
            var item = Interval()
            switch all[i].piece {
            case .region(0): break
            case .region(let k): item.lower = bound(k - 1)
            case .root(let k): item.lower = bound(k); item.lowerClosed = true
            }
            switch all[j].piece {
            case .region(let k) where k == roots.count: break
            case .region(let k): item.upper = bound(k)
            case .root(let k): item.upper = bound(k); item.upperClosed = true
            }
            items.append(item)
            i = j + 1
        }
        return IntervalSet(items: items)
    }

    private func text(exactly: Bool) -> String { set.text(name, exactly: exactly) }

    var solution: Solution {
        let exact = text(exactly: true), approx = text(exactly: false)
        return Solution(exact: exact, approx: approx == exact ? nil : "≈ \(approx)")
    }

    // The relation as typed, for the working.
    private var sign: String { relation == .notEqual ? "≠" : relation.rawValue }

    var details: Details {
        var d = Details(name: name, equation: row(typeset(left, name), t(" \(sign) "), typeset(right, name)), steps: [], solutions: [t(solution.exact)] + (solution.approx.map { [t($0)] } ?? []),
                        note: nil, f: { [left, right] x in left.eval(x) - right.eval(x) }, roots: roots)
        if let p, p.isEmpty {
            d.steps.append(Step(label: "Moving every term to one side", math: row(t("0 \(sign) 0")),
                                note: "The two sides are the same expression."))
            return d
        }
        if let p { d.steps.append(Step(label: "Moving every term to one side", math: row(polyMath(p, name), t(" \(sign) 0")))) }
        if p.map({ $0.count >= 2 }) ?? true {
            d.steps.append(Step(label: "Finding where the expression is zero",
                                math: roots.isEmpty ? nil : t(roots.indices.map { "\(name) = \(label($0, exactly: true))" }.joined(separator: ", ")),
                                note: roots.isEmpty ? "The expression has no real root, and so keeps one sign throughout." : nil))
        }
        let points = tests
        for (i, point) in points.enumerated() {
            let v = value(at: point)
            let region = pieces.first { if case .region(let k) = $0.piece, k == i { true } else { false } }!
            let bounds = i == 0 ? (roots.isEmpty ? "all \(name)" : "\(name) < \(label(0, exactly: true))")
                : i == roots.count ? "\(name) > \(label(roots.count - 1, exactly: true))"
                : "\(label(i - 1, exactly: true)) < \(name) < \(label(i, exactly: true))"
            d.steps.append(Step(label: "Testing the sign of the expression for \(bounds)",
                                math: t("\(name) = \(decimal(point)): \(decimal(v))"),
                                note: "The expression is \(v > 0 ? "positive" : "negative") here; the inequality is \(region.holds ? "satisfied" : "not satisfied")."))
        }
        d.steps.append(Step(label: "Hence", math: t(solution.exact)))
        return d
    }
}


// Several inequalities in one letter, taken together: 1 < x < 5, x > 1 && x < 5, x^2 > 4 || x = 0 is no
// inequality, but x^2 > 4 and x < 10 is. && and and keep what the two share; || and or give both.
struct InequalitySet {
    var name: String
    var set: IntervalSet
    var atoms: [Inequality]
    var text: String

    static func parse(_ input: String) -> InequalitySet? {
        guard Options.inequalities else { return nil }
        var text = input
        text = text.replacingOccurrences(of: "(?i)(?<=[\\s)])and(?=[\\s(])", with: "&&", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)(?<=[\\s)])or(?=[\\s(])", with: "||", options: .regularExpression)
        var atoms: [Inequality] = []
        guard let set = build(text, &atoms), let first = atoms.first, atoms.allSatisfy({ $0.name == first.name }),
              atoms.count >= 2 else { return nil }
        return InequalitySet(name: first.name, set: set, atoms: atoms, text: input)
    }

    private static func split(_ text: String, on separator: String) -> [String] {
        var parts: [String] = [], depth = 0, current = "", i = text.startIndex
        while i < text.endIndex {
            if text[i...].hasPrefix(separator), depth == 0 {
                parts.append(current)
                current = ""
                i = text.index(i, offsetBy: separator.count)
                continue
            }
            if text[i] == "(" { depth += 1 } else if text[i] == ")" { depth -= 1 }
            current.append(text[i])
            i = text.index(after: i)
        }
        return parts + [current]
    }

    private static func build(_ text: String, _ atoms: inout [Inequality]) -> IntervalSet? {
        let t = text.trimmingCharacters(in: .whitespaces)
        for (separator, combine) in [("||", { (a: IntervalSet, b: IntervalSet) in a.union(b) }), ("&&", { (a: IntervalSet, b: IntervalSet) in a.intersection(b) })] {
            let parts = split(t, on: separator)
            if parts.count > 1 {
                var result: IntervalSet?
                for part in parts {
                    guard let one = build(part, &atoms) else { return nil }
                    result = result.map { combine($0, one) } ?? one
                }
                return result
            }
        }
        if t.first == "(", t.last == ")", split(t, on: "\u{0}").count == 1 {
            var depth = 0, wraps = true
            for (offset, c) in t.enumerated() {
                if c == "(" { depth += 1 } else if c == ")" { depth -= 1 }
                if depth == 0, offset != t.count - 1 { wraps = false; break }
            }
            if wraps { return build(String(t.dropFirst().dropLast()), &atoms) }
        }
        // One inequality, or a chain of two: 1 < x < 5 is 1 < x and x < 5.
        guard let regex = try? NSRegularExpression(pattern: "<=|>=|≤|≥|<|>") else { return nil }
        let ns = t as NSString
        let hits = regex.matches(in: t, range: NSRange(location: 0, length: ns.length))
        switch hits.count {
        case 1:
            guard let a = Inequality.parse(t, forSet: true) else { return nil }
            atoms.append(a)
            return a.set
        case 2:
            let first = ns.substring(with: hits[0].range), second = ns.substring(with: hits[1].range)
            let up = ["<", "<=", "≤"], down = [">", ">=", "≥"]
            guard (up.contains(first) && up.contains(second)) || (down.contains(first) && down.contains(second)) else { return nil }
            let a = ns.substring(to: hits[0].range.location)
            let middle = ns.substring(with: NSRange(location: hits[0].range.upperBound, length: hits[1].range.location - hits[0].range.upperBound))
            let b = ns.substring(from: hits[1].range.upperBound)
            guard let x = Inequality.parse("\(a)\(first)\(middle)", forSet: true), let y = Inequality.parse("\(middle)\(second)\(b)", forSet: true) else { return nil }
            atoms += [x, y]
            return x.set.intersection(y.set)
        default: return nil
        }
    }

    var solution: Solution {
        let exact = set.text(name), approx = set.text(name, exactly: false)
        return Solution(exact: exact, approx: approx == exact ? nil : "≈ \(approx)")
    }

    var details: Details {
        var d = Details(name: name, equation: t(text.trimmingCharacters(in: .whitespaces)), steps: [], solutions: [t(solution.exact)] + (solution.approx.map { [t($0)] } ?? []),
                        note: nil, f: { _ in .nan }, roots: [])
        for (i, atom) in atoms.enumerated() {
            d.steps.append(Step(label: "Solving inequality \(i + 1)", math: row(typeset(atom.left, name), t(" \(atom.relation.rawValue) "), typeset(atom.right, name)),
                                note: "\(atom.solution.exact)."))
        }
        d.steps.append(Step(label: text.contains("||") || text.lowercased().contains(" or ") ? "Taking the numbers in either" : "Taking the numbers in both", math: t(solution.exact)))
        return d
    }
}
