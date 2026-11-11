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
    var complexValues: (Complex, Complex)? = nil

    var isDefined: Bool {
        guard let (a, b) = complexValues else { return true }
        guard a.isFinite, b.isFinite else { return false }
        if a.im == 0 && b.im == 0 { return true }
        return [.equal, .identical, .notEqual, .approximately].contains(relation)
    }

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
        let all = relations(in: input)
        return all.count == 1 ? all[0] : nil
    }

    // Every relation in the text, in order, outside brackets.
    static func relations(in input: String) -> [(range: Range<String.Index>, relation: Relation)] {
        var found: [(range: Range<String.Index>, relation: Relation)] = []
        var i = input.startIndex, depth = 0
        while i < input.endIndex {
            if input[i] == "(" || input[i] == "[" { depth += 1 } else if input[i] == ")" || input[i] == "]" { depth -= 1 }
            guard depth == 0, let (text, relation) = spellings.first(where: { input[i...].hasPrefix($0.0) }) else {
                i = input.index(after: i)
                continue
            }
            // 5!=120 is five factorial; with a space before it, 5 != 120, it is ≠.
            if text == "!=", i > input.startIndex, input[input.index(before: i)] != " " {
                i = input.index(after: i)
                continue
            }
            let end = input.index(i, offsetBy: text.count)
            found.append((i..<end, relation))
            i = end
        }
        return found
    }

    // A chain, 2 = 2 = 2 or 1 < 2 ≤ 3, as it is meant in mathematics: each relation between the
    // sides either side of it, every one of which must hold, 1 > 1 > 1 being 1 > 1 and 1 > 1. Each
    // side may be worked out first, 1+1 = 2 = 4/2. Nil for one relation, which is no chain.
    static func chain(_ input: String) -> [Comparison]? {
        let found = relations(in: input)
        guard found.count >= 2 else { return nil }
        var sides: [Substring] = [], start = input.startIndex
        for f in found { sides.append(input[start..<f.range.lowerBound]); start = f.range.upperBound }
        sides.append(input[start...])
        var links: [Comparison] = []
        for (n, f) in found.enumerated() {
            guard let link = parse(String(sides[n]) + String(input[f.range]) + String(sides[n + 1])) else { return nil }
            links.append(link)
        }
        return links
    }

    static func parse(_ input: String) -> Comparison? {
        guard let found = relation(in: input) else { return nil }
        // With =, an e is still the unknown it has always been: 2e − 3 = 1 is solved for e.
        let sides = [String(input[..<found.range.lowerBound]), String(input[found.range.upperBound...])]
        guard var l = try? Parser.tokenize(sides[0]), var r = try? Parser.tokenize(sides[1]) else { return nil }
        let hasI = (l + r).contains(.letter("i"))
        // i is the imaginary unit on either side of a comparison, including i alone. It must
        // not become an unknown merely because an equals sign is present.
        if hasI {
            let letters = (l + r).compactMap { if case .letter(let n) = $0 { return n }; return nil }
            guard letters.allSatisfy({ $0 == "i" || $0 == "e" }) else { return nil }
            func expression(_ tokens: [Parser.Token]) -> Expr? {
                let tokens = tokens.map { $0 == .letter("e") ? .constant(M_E) : $0 }
                var state = Parser.State(tokens: tokens, unknown: "", bound: ["i"])
                guard let e = try? state.expression(), state.at == tokens.count else { return nil }
                return e
            }
            guard let left = expression(l), let right = expression(r) else { return nil }
            let a = ComplexValue.evaluate(left) ?? Complex(.nan, .nan)
            let b = ComplexValue.evaluate(right) ?? Complex(.nan, .nan)
            return Comparison(left: left, right: right, relation: found.relation, complexValues: (a, b))
        }
        if found.relation == .equal || found.relation == .identical, (l + r).contains(.letter("e")) { return nil }
        let ks = Parser.indices(l + r)
        (l, r) = (l.map { $0 == .letter("e") && !ks.contains("e") ? .constant(M_E) : $0 },
                  r.map { $0 == .letter("e") && !ks.contains("e") ? .constant(M_E) : $0 })
        guard let roles = Parser.roles(l + [.symbol("=")] + r), roles.unknown == nil,
              let left = try? Parser.expression(l, constants: roles.constants),
              let right = try? Parser.expression(r, constants: roles.constants) else { return nil }
        if !left.eval(0).isFinite || !right.eval(0).isFinite {
            guard let a = ComplexValue.evaluate(left), let b = ComplexValue.evaluate(right), a.isFinite, b.isFinite else { return nil }
            return Comparison(left: left, right: right, relation: found.relation, complexValues: (a, b))
        }
        return Comparison(left: left, right: right, relation: found.relation)
    }

    // Equal to within rounding: 0.1 + 0.2 = 0.3 holds, and 1/3 = 0.3333 does not.
    private static func equal(_ a: Double, _ b: Double) -> Bool { added(a, -b) == 0 }

    // Whether the sides are exactly equal: as fractions, where both can be worked out as one
    // (numbers, + − × ÷, whole powers, factorials), and otherwise, an irrational side being only
    // ever a decimal, to within rounding.
    private var same: Bool {
        if let (a, b) = complexValues {
            // Scale the rounding allowance with the values, so tiny nonzero complex numbers
            // are not silently equated to zero, while exp(iπ)'s round-off is tolerated.
            return complexDistance(a, b) <= 32 * Double.ulpOfOne
        }
        guard relation == .identical else { return Comparison.equal(left.eval(0), right.eval(0)) }
        if let a = left.typedNumber?.rational, let b = right.typedNumber?.rational { return a == b }
        return Comparison.equal(left.eval(0), right.eval(0))
    }

    // Within a tenth of a percent of the larger; beside zero, where no percentage can be taken,
    // within 10⁻⁹.
    private static func close(_ a: Double, _ b: Double) -> Bool {
        if a == 0 || b == 0 { return abs(a - b) <= 1e-9 }
        return abs(a - b) <= 0.001 * max(abs(a), abs(b))
    }

    var holds: Bool {
        if let (a, b) = complexValues {
            guard isDefined else { return false }
            switch relation {
            case .equal, .identical: return same
            case .notEqual: return !same
            case .approximately: return same || complexDistance(a, b) <= 0.001
            case .less: return !same && a.re < b.re
            case .greater: return !same && a.re > b.re
            case .atMost: return same || a.re < b.re
            case .atLeast: return same || a.re > b.re
            }
        }
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
        if let (a, b) = complexValues {
            let (l, r) = (complexText(a), complexText(b))
            if !same && l == r { return nil }
            return "\(l) \(same ? (a == b ? "=" : "≈") : "≠") \(r)"
        }
        let (a, b) = (left.eval(0), right.eval(0))
        let equal = same
        if !equal, decimal(a) == decimal(b) { return nil }
        return "\(decimal(a)) \(equal ? "=" : a < b ? "<" : a > b ? ">" : "≠") \(decimal(b))"
    }

    // The same in a sentence, with what ≈ allowed.
    private var verdict: String {
        if let (a, b) = complexValues {
            if !a.isFinite || !b.isFinite { return "A complex expression is undefined, unsupported, or beyond the numeric range." }
            if !isDefined { return "Non-real complex numbers have no natural ordering; <, >, ≤ and ≥ do not apply." }
            return same ? "The real parts are equal and the imaginary parts are equal, to numerical rounding."
                : "The real parts or the imaginary parts differ."
        }
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
        if !isDefined { return Solution(exact: "Undefined", approx: verdict) }
        let unequal = !same
        return Solution(exact: holds ? "True" : "False", approx: relation == .approximately && unequal ? verdict : found ?? verdict)
    }

    func statement(_ l: Expr, _ r: Expr) -> Math { row(typeset(l, ""), t(" \(relation.rawValue) "), typeset(r, "")) }

    // Both sides worked out together, a round at a time, and then compared.
    var details: Details {
        if complexValues != nil { return complexDetails }
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

    private func complexText(_ z: Complex) -> String { ComplexValue(value: z, expr: .num(0)).text }

    private func complexDistance(_ a: Complex, _ b: Complex) -> Double {
        let scale = max(abs(a.re), abs(a.im), abs(b.re), abs(b.im))
        if scale == 0 { return 0 }
        let x = Complex(a.re / scale, a.im / scale), y = Complex(b.re / scale, b.im / scale)
        return (x - y).modulus / max(x.modulus, y.modulus)
    }

    private var complexDetails: Details {
        let (a, b) = complexValues!
        var d = Details(name: "", equation: statement(left, right), steps: [], solutions: [t(solution.exact)], note: nil, f: { _ in .nan }, roots: [])
        guard a.isFinite, b.isFinite else {
            d.steps = [Step(label: "Why there is no comparison", math: nil, note: verdict)]
            return d
        }
        var roots = Set<String>()
        func explainRoots(_ e: Expr) {
            switch e {
            case .call("sqrt", let inside):
                explainRoots(inside)
                if let z = ComplexValue.evaluate(inside), z.im == 0, z.re < 0,
                   roots.insert(typeset(e, "").plain).inserted {
                    d.steps.append(Step(label: "Principal square root", math: row(typeset(e, ""), t(" = \(complexText(Complex.sqrt(z)))")),
                                        note: "√z denotes the principal square root. For a negative real number it has positive imaginary part. Solving w² = z is a different question and gives both signs."))
                }
            case .neg(let x), .call(_, let x): explainRoots(x)
            case .op(_, let x, let y): explainRoots(x); explainRoots(y)
            default: break
            }
        }
        explainRoots(left); explainRoots(right)
        d.steps.append(Step(label: "Evaluating the left-hand side", math: row(typeset(left, ""), t(" = \(complexText(a))"))))
        d.steps.append(Step(label: "Evaluating the right-hand side", math: row(typeset(right, ""), t(" = \(complexText(b))"))))
        d.steps.append(Step(label: isDefined ? "Comparing real and imaginary parts" : "Why this comparison is undefined", math: isDefined ? found.map(t) : nil, note: verdict))
        return d
    }
}

// Statements joined by && or and (both), || or or (either) and negated by ! or not, with
// brackets to group: 3+1=4 || 3=1 is True, and !(3=1) is True. && binds before ||, and ! before
// both. Each statement is a comparison of its own.
indirect enum Logic {
    case atom(Comparison)
    case chain([Comparison])    // 2 = 2 = 2: each link a comparison, all of which must hold
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
        guard let tree = build(text), tree.isCompound, tree.atoms.allSatisfy(\.isDefined) else { return nil }
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
        if let links = Comparison.chain(t) { return .chain(links) }
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
        case .chain(let links): links
        case .value: []
        case .not(let a): a.atoms
        case .all(let a), .any(let a): a.flatMap(\.atoms)
        }
    }

    var holds: Bool {
        switch self {
        case .atom(let c): c.holds
        case .chain(let links): links.allSatisfy(\.holds)
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
        // As written, each side once: 2 = 2 = 2.
        case .chain(let links):
            let s = typeset(links[0].left, "").plain + links.map { " \($0.relation.rawValue) " + typeset($0.right, "").plain }.joined()
            return rank > 2 ? "(" + s + ")" : s
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
        // A chain is its links taken together: True && True.
        case .chain(let links): .all(links.map { .value($0.holds) })
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
        case .atom, .chain, .value: return (self, [])
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

// A statement in brackets used as a number, (0 = 0) = 0 or (2 < 3) + 5, is 1 where it is true and
// 0 where it is false, as an Iverson bracket is: (0 = 0) = 0 is 1 = 0, and False. Only where the
// brackets stand beside a relation or an operator of arithmetic: brackets round statements joined
// by && or ||, or after ! or not, are those statements still, and 0 = 0 = 0, with none, is a chain.
enum Iverson {
    // The text with each such statement put as 1 or 0, innermost first, and what was taken for each.
    static func substituted(_ input: String) -> (text: String, notes: [String]) {
        var text = input, notes: [String] = []
        while let (range, inner) = operand(in: text), let holds = judge(inner) {
            notes.append("(\(shown(inner))) is \(holds ? "True" : "False"), taken as \(holds ? 1 : 0)")
            text.replaceSubrange(range, with: holds ? "1" : "0")
        }
        return (text, notes)
    }

    // The innermost bracket holding a relation of its own and standing as a number.
    private static func operand(in text: String) -> (Range<String.Index>, String)? {
        let chars = Array(text)
        var opens: [Int] = []
        for (i, c) in chars.enumerated() {
            if c == "(" { opens.append(i); continue }
            guard c == ")", let start = opens.popLast() else { continue }
            let inner = String(chars[(start + 1)..<i])
            guard !inner.contains("("), !Comparison.relations(in: inner).isEmpty else { continue }
            func neighbour(_ from: Int, _ step: Int) -> Character? {
                var j = from + step
                while j >= 0, j < chars.count, chars[j] == " " { j += step }
                return j >= 0 && j < chars.count ? chars[j] : nil
            }
            let arithmetic = Set("=<>≈≠≤≥+-−*/^×÷·%")
            let before = neighbour(start, -1), after = neighbour(i, 1)
            guard before.map(arithmetic.contains) == true || after.map(arithmetic.contains) == true,
                  before != "!", !(after == "&" || after == "|" || before == "&" || before == "|") else { continue }
            return (text.index(text.startIndex, offsetBy: start)..<text.index(text.startIndex, offsetBy: i + 1), inner)
        }
        return nil
    }

    // True or False for a statement of numbers alone; nil for one with a letter in it, x = 2.
    private static func judge(_ inner: String) -> Bool? {
        if let logic = Logic.parse(inner) { return logic.holds }
        if let links = Comparison.chain(inner) { return links.allSatisfy(\.holds) }
        return Comparison.parse(inner)?.holds
    }

    private static func shown(_ inner: String) -> String {
        if let c = Comparison.parse(inner) { return c.statement(c.left, c.right).plain }
        return inner.trimmingCharacters(in: .whitespaces)
    }
}
