import Foundation

// A statement with no unknown in it, "2^2 = 4" or "1/3 ≈ 0.3333", is not solved but judged: each
// side is worked out, and the card says True or False. = holds to within rounding, as does ==;
// === is exact, and 1/3 === 0.3333 is False however many threes are written; ≈ allows a tenth of
// a percent. Statements are joined by && and ||.
struct Comparison {
    enum Relation: String {
        case equal = "=", identical = "===", notEqual = "≠", approximately = "≈", less = "<", greater = ">", atMost = "≤", atLeast = "≥"
    }

    var left: Expr
    var right: Expr
    var relation: Relation

    // As they are typed, the longer first: ~= is ≈, != is ≠, >= is ≥ and <= is ≤.
    private static let spellings: [(String, Relation)] = [
        ("===", .identical), ("==", .equal), ("~=", .approximately), ("≈", .approximately), ("!=", .notEqual), ("≠", .notEqual),
        (">=", .atLeast), ("≥", .atLeast), ("<=", .atMost), ("≤", .atMost),
        (">", .greater), ("<", .less), ("=", .equal),
    ]

    // One relation, with an expression of numbers alone on either side of it. A letter makes it
    // an equation to solve instead, so g = 9.8 is not a comparison. !g = 9.8 is: the mark makes
    // the g that would have been the unknown the constant.
    // The one relation in the text, and where: nil for none, or for more than one.
    static func relation(in input: String) -> (range: Range<String.Index>, relation: Relation)? {
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
        return found
    }

    static func parse(_ input: String) -> Comparison? {
        guard let found = relation(in: input) else { return nil }
        // With =, an e is still the unknown it has always been: 2e − 3 = 1 is solved for e.
        let sides = [String(input[..<found.range.lowerBound]), String(input[found.range.upperBound...])]
        guard var l = try? Parser.tokenize(sides[0]), var r = try? Parser.tokenize(sides[1]) else { return nil }
        if found.relation == .equal || found.relation == .identical, (l + r).contains(.letter("e")) { return nil }
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

    // Whether the sides are exactly equal: as fractions, where both can be worked out as one
    // (numbers, + − × ÷, whole powers, factorials), and otherwise, an irrational side being only
    // ever a decimal, to within rounding.
    private var same: Bool {
        guard relation == .identical else { return Comparison.equal(left.eval(0), right.eval(0)) }
        if let a = Exact(left), let b = Exact(right) { return a == b }
        return Comparison.equal(left.eval(0), right.eval(0))
    }

    // Within a tenth of a percent of the larger; beside zero, where no percentage can be taken,
    // within 10⁻⁹.
    private static func close(_ a: Double, _ b: Double) -> Bool {
        if a == 0 || b == 0 { return abs(a - b) <= 1e-9 }
        return abs(a - b) <= 0.001 * max(abs(a), abs(b))
    }

    var holds: Bool {
        let (a, b) = (left.eval(0), right.eval(0))
        let equal = same
        switch relation {
        case .equal, .identical: return equal
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
        let equal = same
        if !equal, decimal(a) == decimal(b) { return nil }
        return "\(decimal(a)) \(equal ? "=" : a < b ? "<" : a > b ? ">" : "≠") \(decimal(b))"
    }

    // The same in a sentence, with what ≈ allowed.
    private var verdict: String {
        let (a, b) = (left.eval(0), right.eval(0))
        if same { return relation == .identical ? "The two sides are exactly equal." : "The two sides are equal." }
        let difference = decimal(abs(a - b))
        switch relation {
        case .approximately:
            let judged = holds ? "is within" : "exceeds"
            if a == 0 || b == 0 { return "The two sides differ by \(difference), which \(judged) the tolerance of 10⁻⁹ allowed beside zero." }
            return "The two sides differ by \(decimal(100 * abs(a - b) / max(abs(a), abs(b))))%, which \(judged) the tolerance of 0.1%."
        case .identical:
            return a == b ? "The two sides are not exactly equal." : "The two sides are not exactly equal: they differ by \(difference)."
        case .equal, .notEqual:
            return found == nil ? "The two sides are not equal: they differ by \(difference)." : "The two sides are not equal."
        case .less, .greater, .atMost, .atLeast:
            return a < b ? "The left side is less than the right." : "The left side is greater than the right."
        }
    }

    var solution: Solution {
        let unequal = !same
        return Solution(exact: holds ? "True" : "False", approx: relation == .approximately && unequal ? verdict : found ?? verdict)
    }

    func statement(_ l: Expr, _ r: Expr) -> Math { row(typeset(l, ""), t(" \(relation.rawValue) "), typeset(r, "")) }

    // Both sides worked out together, a round at a time, and then compared.
    var details: Details {
        func line(_ l: Expr, _ r: Expr) -> Math { statement(l, r) }
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

// A number as a fraction, for === : worked out in whole numbers, so that nothing is lost to
// rounding. Nil for anything that is not one, or too large to hold.
struct Exact: Equatable {
    var top: Int, bottom: Int

    init?(top: Int, bottom: Int) {
        guard bottom != 0 else { return nil }
        let g = gcd(top, bottom)
        let sign = bottom < 0 ? -1 : 1
        self.top = sign * top / g
        self.bottom = sign * bottom / g
    }

    // A decimal as it is written: 0.33 is 33 over 100.
    init?(decimal v: Double) {
        guard v.isFinite else { return nil }
        let parts = String(format: "%.15g", v).split(separator: "e", omittingEmptySubsequences: false)
        let mantissa = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard let whole = Int(mantissa[0] + (mantissa.count > 1 ? mantissa[1] : "")),
              var power = parts.count > 1 ? Int(parts[1]) : 0 else { return nil }
        power -= mantissa.count > 1 ? mantissa[1].count : 0
        var top = whole, bottom = 1
        for _ in 0..<abs(power) {
            if power > 0 {
                let (t, o) = top.multipliedReportingOverflow(by: 10); if o { return nil }; top = t
            } else {
                let (b, o) = bottom.multipliedReportingOverflow(by: 10); if o { return nil }; bottom = b
            }
        }
        self.init(top: top, bottom: bottom)
    }

    init?(_ e: Expr) {
        func product(_ a: Exact, _ b: Exact) -> Exact? {
            let (t, o1) = a.top.multipliedReportingOverflow(by: b.top), (d, o2) = a.bottom.multipliedReportingOverflow(by: b.bottom)
            return o1 || o2 ? nil : Exact(top: t, bottom: d)
        }
        switch e {
        case .num(let v): self.init(decimal: v)
        case .neg(let a): guard let a = Exact(a) else { return nil }; self.init(top: -a.top, bottom: a.bottom)
        case .op(let o, let l, let r):
            guard let a = Exact(l), let b = Exact(r) else { return nil }
            switch o {
            case "*": guard let p = product(a, b) else { return nil }; self = p
            case "/": guard b.top != 0, let p = product(a, Exact(top: b.bottom, bottom: b.top)!) else { return nil }; self = p
            case "+", "-":
                let sign = o == "+" ? 1 : -1
                let (x, o1) = a.top.multipliedReportingOverflow(by: b.bottom), (y, o2) = b.top.multipliedReportingOverflow(by: a.bottom)
                let (s, o3) = x.addingReportingOverflow(sign * y), (d, o4) = a.bottom.multipliedReportingOverflow(by: b.bottom)
                guard !(o1 || o2 || o3 || o4) else { return nil }
                self.init(top: s, bottom: d)
            case "^":
                guard b.bottom == 1, abs(b.top) <= 64, !(a.top == 0 && b.top < 0) else { return nil }
                var result = Exact(top: 1, bottom: 1)!
                for _ in 0..<abs(b.top) { guard let p = product(result, a) else { return nil }; result = p }
                self = b.top < 0 ? Exact(top: result.bottom, bottom: result.top)! : result
            default: return nil
            }
        case .call("fact", let a):
            guard let a = Exact(a), a.bottom == 1, (0...20).contains(a.top) else { return nil }
            self.init(top: (1...max(1, a.top)).reduce(1, *), bottom: 1)
        default: return nil
        }
    }
}

// Statements joined by && or and (both), || or or (either) and negated by ! or not, with
// brackets to group: 3+1=4 || 3=1 is True, and !(3=1) is True. && binds before ||, and ! before
// both. Each statement is a comparison of its own.
indirect enum Logic {
    case atom(Comparison)
    case value(Bool)            // a statement once it has been judged
    case not(Logic)
    case all([Logic])
    case any([Logic])

    // not is written with a marker of its own, so that it cannot be taken for a factorial.
    private static let negation: Character = "¬"

    static func parse(_ input: String) -> Logic? {
        guard input.contains("=") || input.contains("<") || input.contains(">") || input.contains("≈") || input.contains("≠")
                || input.contains("≤") || input.contains("≥") else { return nil }
        var text = input
        text = text.replacingOccurrences(of: "(?i)(?<=[\\s)])and(?=[\\s(!])", with: "&&", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)(?<=[\\s)])or(?=[\\s(!])", with: "||", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)(?<![A-Za-z0-9_])not(?=[\\s(])", with: "¬", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?<![0-9)A-Za-z])!(?=\\s*\\()", with: "¬", options: .regularExpression)
        guard let tree = build(text), tree.isCompound else { return nil }
        return tree
    }

    private static func build(_ text: String) -> Logic? {
        let t = text.trimmingCharacters(in: .whitespaces)
        for (separator, make) in [("||", { Logic.any($0) }), ("&&", { Logic.all($0) })] as [(String, ([Logic]) -> Logic)] {
            let parts = split(t, on: separator)
            if parts.count > 1 {
                var built: [Logic] = []
                for part in parts { guard let one = build(part) else { return nil }; built.append(one) }
                return make(built)
            }
        }
        if t.first == negation { return build(String(t.dropFirst())).map { .not($0) } }
        if t.first == "(", t.last == ")", split(t, on: nil).count == 1, closes(t) { return build(String(t.dropFirst().dropLast())) }
        return Comparison.parse(t).map { .atom($0) }
    }

    // The pieces of the text between the separator, outside any brackets. With none, the text
    // whole: the way of asking whether it is all inside one pair of brackets, as closes does.
    private static func split(_ text: String, on separator: String?) -> [String] {
        guard let separator else { return [text] }
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
        parts.append(current)
        return parts
    }

    // Whether the bracket the text opens with is the one it closes with.
    private static func closes(_ text: String) -> Bool {
        var depth = 0
        for (offset, c) in text.enumerated() {
            if c == "(" { depth += 1 } else if c == ")" { depth -= 1 }
            if depth == 0 { return offset == text.count - 1 }
        }
        return false
    }

    var isCompound: Bool { if case .atom = self { false } else { true } }

    var atoms: [Comparison] {
        switch self {
        case .atom(let c): [c]
        case .value: []
        case .not(let a): a.atoms
        case .all(let a), .any(let a): a.flatMap(\.atoms)
        }
    }

    var holds: Bool {
        switch self {
        case .atom(let c): c.holds
        case .value(let v): v
        case .not(let a): !a.holds
        case .all(let a): a.allSatisfy(\.holds)
        case .any(let a): a.contains(where: \.holds)
        }
    }

    // As it is written, with brackets where a lower binding operator is inside a higher.
    func text(_ rank: Int = 0) -> String {
        switch self {
        case .atom(let c): return c.statement(c.left, c.right).plain
        case .value(let v): return v ? "True" : "False"
        case .not(let a):
            if case .atom = a { return "!(" + a.text() + ")" }
            if case .value = a { return "!" + a.text() }
            return "!(" + a.text() + ")"
        case .all(let a):
            let s = a.map { $0.text(2) }.joined(separator: " && ")
            return rank > 2 ? "(" + s + ")" : s
        case .any(let a):
            let s = a.map { $0.text(1) }.joined(separator: " || ")
            return rank > 1 ? "(" + s + ")" : s
        }
    }

    // Each statement said to be True or False.
    var judged: Logic {
        switch self {
        case .atom(let c): .value(c.holds)
        case .value: self
        case .not(let a): .not(a.judged)
        case .all(let a): .all(a.map(\.judged))
        case .any(let a): .any(a.map(\.judged))
        }
    }

    // One round of working out: each operator whose operands are all True or False now is
    // replaced by what it comes to. Hence && is done before the || it is inside, and ! before both.
    func reduced() -> (logic: Logic, done: [String]) {
        func isValue(_ l: Logic) -> Bool { if case .value = l { true } else { false } }
        switch self {
        case .atom, .value: return (self, [])
        case .not(let a):
            if case .value(let v) = a { return (.value(!v), ["!"]) }
            let (r, d) = a.reduced()
            return (.not(r), d)
        case .all(let a), .any(let a):
            let isAll: Bool
            if case .all = self { isAll = true } else { isAll = false }
            if a.allSatisfy(isValue) {
                return (.value(isAll ? a.allSatisfy(\.holds) : a.contains(where: \.holds)), [isAll ? "&&" : "||"])
            }
            let steps = a.map { $0.reduced() }
            let done = steps.flatMap(\.done)
            return (isAll ? .all(steps.map(\.logic)) : .any(steps.map(\.logic)), done)
        }
    }

    var solution: Solution {
        let told = atoms.map { "\($0.statement($0.left, $0.right).plain) is \($0.holds ? "True" : "False")" }
        return Solution(exact: holds ? "True" : "False", approx: told.joined(separator: "; ") + ".")
    }

    var details: Details {
        var d = Details(name: "", equation: t(text()), steps: [], solutions: [t(holds ? "True" : "False")],
                        note: nil, f: { _ in .nan }, roots: [])
        for (number, c) in atoms.enumerated() {
            let inner = c.details
            d.steps.append(Step(label: "Judging statement \(number + 1)", math: c.statement(c.left, c.right),
                                note: "It is \(c.holds ? "True" : "False"). " + (inner.steps.last?.note ?? "")))
        }
        var current = judged
        d.steps.append(Step(label: "Writing each statement as True or False", math: t(current.text())))
        while true {
            let (next, done) = current.reduced()
            guard !done.isEmpty else { break }
            current = next
            var kinds: [String] = []
            for symbol in ["!", "&&", "||"] where done.contains(symbol) { kinds.append(symbol) }
            let name = kinds.count == 2 ? kinds.joined(separator: " and ") : kinds.joined(separator: ", ")
            d.steps.append(Step(label: "Evaluating \(name)", math: t(current.text())))
        }
        return d
    }
}
