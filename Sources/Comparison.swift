import Foundation

// A statement with no unknown in it, "2^2 = 4" or "1/3 ≈ 0.3333", is not solved but judged: each
// side is worked out, and the card says True or False. = is exact; ≈ allows a tenth of a percent.
struct Comparison {
    enum Relation: String {
        case equal = "=", notEqual = "≠", approximately = "≈", less = "<", greater = ">", atMost = "≤", atLeast = "≥"
    }

    var left: Expr
    var right: Expr
    var relation: Relation

    // As they are typed, the longer first: ~= is ≈, != is ≠, >= is ≥ and <= is ≤.
    private static let spellings: [(String, Relation)] = [
        ("~=", .approximately), ("≈", .approximately), ("!=", .notEqual), ("≠", .notEqual),
        (">=", .atLeast), ("≥", .atLeast), ("<=", .atMost), ("≤", .atMost),
        (">", .greater), ("<", .less), ("=", .equal),
    ]

    // One relation, with an expression of numbers alone on either side of it. A letter makes it
    // an equation to solve instead, so g = 9.8 is not a comparison. !g = 9.8 is: the mark makes
    // the g that would have been the unknown the constant.
    static func parse(_ input: String) -> Comparison? {
        var found: (range: Range<String.Index>, relation: Relation)?
        var i = input.startIndex
        while i < input.endIndex {
            guard let (text, relation) = spellings.first(where: { input[i...].hasPrefix($0.0) }) else {
                i = input.index(after: i)
                continue
            }
            // 5!=120 is five factorial; with a space before it, 5 != 120, it is ≠.
            if text == "!=", i > input.startIndex, input[input.index(before: i)] != " " {
                i = input.index(after: i)
                continue
            }
            guard found == nil else { return nil }
            let end = input.index(i, offsetBy: text.count)
            found = (i..<end, relation)
            i = end
        }
        guard let found else { return nil }
        // With =, an e is still the unknown it has always been: 2e − 3 = 1 is solved for e.
        let sides = [String(input[..<found.range.lowerBound]), String(input[found.range.upperBound...])]
        guard var l = try? Parser.tokenize(sides[0]), var r = try? Parser.tokenize(sides[1]) else { return nil }
        if found.relation == .equal, (l + r).contains(.letter("e")) { return nil }
        let ks = Parser.indices(l + r)
        (l, r) = (l.map { $0 == .letter("e") && !ks.contains("e") ? .constant(M_E) : $0 },
                  r.map { $0 == .letter("e") && !ks.contains("e") ? .constant(M_E) : $0 })
        guard let roles = Parser.roles(l + [.symbol("=")] + r), roles.unknown == nil,
              let left = try? Parser.expression(l, constants: roles.constants),
              let right = try? Parser.expression(r, constants: roles.constants),
              left.eval(0).isFinite, right.eval(0).isFinite else { return nil }
        return Comparison(left: left, right: right, relation: found.relation)
    }

    // Equal to within rounding: 0.1 + 0.2 = 0.3 holds, and 1/3 = 0.3333 does not.
    private static func equal(_ a: Double, _ b: Double) -> Bool { added(a, -b) == 0 }

    // Within a tenth of a percent of the larger; beside zero, where no percentage can be taken,
    // within 10⁻⁹.
    private static func close(_ a: Double, _ b: Double) -> Bool {
        if a == 0 || b == 0 { return abs(a - b) <= 1e-9 }
        return abs(a - b) <= 0.001 * max(abs(a), abs(b))
    }

    var holds: Bool {
        let (a, b) = (left.eval(0), right.eval(0))
        let equal = Comparison.equal(a, b)
        switch relation {
        case .equal: return equal
        case .notEqual: return !equal
        case .approximately: return equal || Comparison.close(a, b)
        case .less: return !equal && a < b
        case .greater: return !equal && a > b
        case .atMost: return equal || a < b
        case .atLeast: return equal || a > b
        }
    }

    // How the two values stand, as found: "4 = 4", "0.333333 > 0.3333". Nil where they differ
    // by less than six figures show.
    private var found: String? {
        let (a, b) = (left.eval(0), right.eval(0))
        let equal = Comparison.equal(a, b)
        if !equal, decimal(a) == decimal(b) { return nil }
        return "\(decimal(a)) \(equal ? "=" : a < b ? "<" : ">") \(decimal(b))"
    }

    // The same in a sentence, with what ≈ allowed.
    private var verdict: String {
        let (a, b) = (left.eval(0), right.eval(0))
        if Comparison.equal(a, b) { return "The two sides are equal." }
        let difference = decimal(abs(a - b))
        switch relation {
        case .approximately:
            let judged = holds ? "is within" : "exceeds"
            if a == 0 || b == 0 { return "The two sides differ by \(difference), which \(judged) the tolerance of 10⁻⁹ allowed beside zero." }
            return "The two sides differ by \(decimal(100 * abs(a - b) / max(abs(a), abs(b))))%, which \(judged) the tolerance of 0.1%."
        case .equal, .notEqual:
            return found == nil ? "The two sides are not equal: they differ by \(difference)." : "The two sides are not equal."
        case .less, .greater, .atMost, .atLeast:
            return a < b ? "The left side is less than the right." : "The left side is greater than the right."
        }
    }

    var solution: Solution {
        let unequal = !Comparison.equal(left.eval(0), right.eval(0))
        return Solution(exact: holds ? "True" : "False", approx: relation == .approximately && unequal ? verdict : found ?? verdict)
    }

    // Both sides worked out together, a round at a time, and then compared.
    var details: Details {
        func line(_ l: Expr, _ r: Expr) -> Math { row(typeset(l, ""), t(" \(relation.rawValue) "), typeset(r, "")) }
        var d = Details(name: "", equation: line(left, right), steps: [], solutions: [t(holds ? "True" : "False")],
                        note: nil, f: { _ in .nan }, roots: [])
        var (l, r) = (left, right)
        // A constant marked with ! is first written in as its value.
        let constants = unique(left.constants + right.constants)
        if !constants.isEmpty {
            (l, r) = (l.withValues, r.withValues)
            d.steps.append(Step(label: "Substituting " + Constants.values(constants), math: line(l, r)))
        }
        while true {
            let factorials = readyFactorials(l) + readyFactorials(r)
            let (nextL, doneL) = reduceOnce(l), (nextR, doneR) = reduceOnce(r)
            guard !doneL.isEmpty || !doneR.isEmpty else { break }
            (l, r) = (nextL, nextR)
            d.steps.append(Step(label: reductionLabel(doneL.union(doneR), factorials: factorials), math: line(l, r)))
        }
        d.steps.append(Step(label: "Comparing the two sides", math: found.map(t), note: verdict))
        return d
    }
}
