import CoreGraphics
import Foundation
import Observation

// A logic circuit, written as its equations, in words, in symbols or in LaTeX:
//   s0 = a0 xor b0, c1 = a0 and b0, s1 = a1 xor b1 xor c1, Cout = (a1 and b1) or (c1 and (a1 xor b1))
//   \begin{aligned} s_0 &= a_0\oplus b_0 \\ c_1 &= a_0\land b_0 \\ … \end{aligned}
// or one expression, A and not B or C, or two said to be equal, not (A and B) = not A or not B. The
// card names its inputs and outputs, or for one output the rows where it is 1; the working gives the
// truth table, each output in its simplest sum of products, and the circuit drawn with its gates,
// a signal used twice (c₁) made once and branching. ∧ binds before ⊕, ⊕ before ∨, ∨ before →.
indirect enum Switching: Equatable {
    case name(String)
    case constant(Bool)
    case not(Switching)
    case binary(Op, Switching, Switching)

    enum Op: String {
        case and = "∧", or = "∨", xor = "⊕", xnor = "⊙", nand = "↑", nor = "↓", implies = "→", iff = "↔"

        var precedence: Int {
            switch self {
            case .implies, .iff: 1
            case .or, .nor: 2
            case .xor, .xnor: 3
            case .and, .nand: 4
            }
        }

        func apply(_ a: Bool, _ b: Bool) -> Bool {
            switch self {
            case .and: a && b
            case .or: a || b
            case .xor: a != b
            case .xnor, .iff: a == b
            case .nand: !(a && b)
            case .nor: !(a || b)
            case .implies: !a || b
            }
        }
    }

    func value(_ env: [String: Bool]) -> Bool {
        switch self {
        case .name(let n): env[n] ?? false
        case .constant(let v): v
        case .not(let a): !a.value(env)
        case .binary(let op, let a, let b): op.apply(a.value(env), b.value(env))
        }
    }

    // Every name in it, each once, in the order they are first written.
    var names: [String] {
        switch self {
        case .name(let n): [n]
        case .constant: []
        case .not(let a): a.names
        case .binary(_, let a, let b): a.names + b.names.filter { !a.names.contains($0) }
        }
    }

    // As it is written in logic: ¬, ∧, ⊕, ∨, with brackets only where they are needed.
    func written(_ outer: Int = 0) -> String {
        switch self {
        case .name(let n): return n
        case .constant(let v): return v ? "1" : "0"
        case .not(let a): return "¬" + a.written(5)
        case .binary(let op, let a, let b):
            let p = op.precedence, right = op == .implies
            let s = a.written(right ? p + 1 : p) + " \(op.rawValue) " + b.written(right ? p : p + 1)
            // Bracketed where it must be, and where ∧ meets ∨ or ⊕, for the eye: (a ∧ b) ∨ c.
            return p < outer || (outer > 0 && outer < 5 && outer != p) ? "(" + s + ")" : s
        }
    }
}

struct Circuit {
    enum Kind {
        case table                                  // outputs worked out from the inputs
        case equivalence                            // two sides compared, row by row
        case refused(String)
    }

    var kind: Kind
    var outputs: [(name: String, expr: Switching)]   // as written; an equivalence's two sides are L and R
    var inputs: [String]
    var order: [Int] = []                            // the outputs in an order in which each is worked out after what it uses

    // MARK: Reading

    static func parse(_ typed: String) -> Circuit? {
        var text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        // "truth table …", "circuit …", "logic …": a logic expression is asked about, whatever it is written with.
        var asked = false
        if let m = text.range(of: "^(?i)(truth\\s*table|logic\\s*circuit|logic|circuit|boolean)(\\s+of)?\\s*:?\\s+", options: .regularExpression) {
            text = String(text[m.upperBound...])
            asked = true
        }
        text = latex(text)
        text = words(text)
        // Only where something says it is logic: a word, ∧ ∨ ⊕ ¬ and the rest, && or ||, or the question.
        guard asked || text.contains(where: { "∧∨⊕⊙↑↓→↔¬".contains($0) }) || text.contains("&&") || text.contains("||") else { return nil }
        text = symbols(text)

        let statements = split(text)
        guard !statements.isEmpty, statements.count <= 40 else { return nil }
        var sides: [(left: String?, right: String, label: Bool)] = []
        for statement in statements {
            // A=B ≔ …: a label, whatever is in it, and the expression.
            let defined = topLevel(statement, "≔")
            if defined.count == 2 { sides.append((defined[0], defined[1], true)); continue }
            guard defined.count == 1 else { return nil }
            let parts = topLevel(statement, "=")
            guard parts.count <= 2 else { return nil }
            sides.append(parts.count == 2 ? (parts[0], parts[1], false) : (nil, parts[0], false))
        }
        // < > ≤ ≥ ≠ are comparisons of numbers, not logic, outside a label.
        guard !sides.contains(where: { $0.right.contains(where: { "<>≤≥≠".contains($0) }) || (!$0.label && ($0.left ?? "").contains(where: { "<>≤≥≠".contains($0) })) }) else { return nil }

        // Equations giving names: each left side one name, multi-letter names allowed (Cout, s0), or a
        // name with a prime, b0' or b'_0, which is then a signal of its own and not "not b0"; or a label.
        let names = sides.map { side in side.left.flatMap { side.label ? (lhsName($0) ?? label($0)) : lhsName($0) } }
        if names.allSatisfy({ $0 != nil }) {
            let known = Set(names.compactMap { $0 })
            var outputs: [(String, Switching)] = []
            for (side, name) in zip(sides, names) {
                guard let name, let expr = SwitchingParser.parse(side.right, singleLetters: false, known: known) else { return nil }
                // One equation whose name is in its own right side is a statement to check, A = A ∧ 1.
                if sides.count == 1, expr.names.contains(name) { break }
                guard outputs.allSatisfy({ $0.0 != name }) else { return Circuit(kind: .refused("\(name) is given twice."), outputs: [], inputs: []) }
                outputs.append((name, expr))
            }
            if outputs.count == sides.count { return made(.table, outputs) }
        }
        // One expression, or two said to be equal: each letter its own input, AB being A and B.
        guard sides.count == 1 else { return nil }
        // Not prose: "me or you" has letters together, which are not taken as a product unless asked.
        if !asked, text.range(of: "\\p{L}\\p{L}", options: .regularExpression) != nil { return nil }
        guard let right = SwitchingParser.parse(sides[0].right, singleLetters: true) else { return nil }
        if let leftText = sides[0].left {
            guard let left = SwitchingParser.parse(leftText, singleLetters: true) else { return nil }
            return made(.equivalence, [("L", left), ("R", right)])
        }
        let taken = Set(right.names)
        let name = ["Q", "F", "Y", "Z", "X"].first { !taken.contains($0) } ?? "Out"
        return made(.table, [(name, right)])
    }

    // The name a left side gives: letters and digits, a subscript, and primes before the subscript or after
    // the whole, b0', b'_0, b_0', all b′_0. nil for what is not one name.
    static func lhsName(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespaces)
        let pattern = "^([A-Za-z][A-Za-z]*)([0-9]*)(['’′]*)(?:_\\(?([A-Za-z0-9]+)\\)?)?(['’′]*)$"
        guard let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) else { return nil }
        func group(_ i: Int) -> String { Range(m.range(at: i), in: t).map { String(t[$0]) } ?? "" }
        let (base, digits, before, sub, after) = (group(1), group(2), group(3), group(4), group(5))
        guard digits.isEmpty || sub.isEmpty else { return nil }
        return SwitchingParser.canonical(base, primes: before.count + after.count, sub: digits.isEmpty ? sub : digits)
    }

    // A label to the left of &=, A>B or A=B, kept as it is written but for its spaces.
    private static func label(_ text: String) -> String? {
        let t = text.replacingOccurrences(of: " ", with: "")
        return t.isEmpty || t.count > 16 ? nil : t
    }

    // The inputs, the names used and not given, in the order written, and the order to work them out in.
    private static func made(_ kind: Kind, _ outputs: [(String, Switching)]) -> Circuit {
        let given = Set(outputs.map(\.0))
        var inputs: [String] = []
        for (_, expr) in outputs { for n in expr.names where !given.contains(n) && !inputs.contains(n) { inputs.append(n) } }
        // Bits numbered, a1 a0 b1 b0: as a number is read, each name's bits together, the highest first, the
        // names in alphabetical order, so that a row's number is the numbers it holds written one after another.
        if inputs.contains(where: { $0.range(of: "_[0-9]+$", options: .regularExpression) != nil }) {
            func key(_ n: String) -> (String, Int) {
                guard let r = n.range(of: "_[0-9]+$", options: .regularExpression) else { return (n.lowercased(), Int.max) }
                return (String(n[..<r.lowerBound]).lowercased(), Int(n[r].dropFirst()) ?? 0)
            }
            inputs.sort { key($0).0 != key($1).0 ? key($0).0 < key($1).0 : key($0).1 > key($1).1 }
        }
        guard inputs.count <= 12 else {
            return Circuit(kind: .refused("At most 12 inputs are worked through: this has \(inputs.count)."), outputs: [], inputs: [])
        }
        // Each output after the ones it uses; one that uses itself, through others or not, is a latch.
        var order: [Int] = [], done = Set<String>()
        while order.count < outputs.count {
            guard let next = outputs.indices.first(where: { i in !order.contains(i) && outputs[i].1.names.allSatisfy { !given.contains($0) || done.contains($0) } }) else {
                let stuck = outputs.indices.filter { !order.contains($0) }.map { outputs[$0].0 }
                return Circuit(kind: .refused("\(stuck.joined(separator: ", ")) depend\(stuck.count == 1 ? "s" : "") on \(stuck.count == 1 ? "itself" : "each other"): a circuit with feedback, as a latch has, has no truth table of this kind."),
                               outputs: [], inputs: [])
            }
            order.append(next)
            done.insert(outputs[next].0)
        }
        return Circuit(kind: kind, outputs: outputs.map { (name: $0.0, expr: $0.1) }, inputs: inputs, order: order)
    }

    // LaTeX as the booklets and notes write logic: \oplus, \land, \overline{A}, C_{\text{out}}, aligned.
    static func latex(_ input: String) -> String {
        guard input.contains("\\") || input.contains("{") else { return input }
        var s = input
        s = s.replacingOccurrences(of: "\\\\begin\\{[a-z*]+\\}|\\\\end\\{[a-z*]+\\}", with: " ", options: .regularExpression)
        // In aligned, &= is where the definition begins: what is before it is the output's label, however
        // it is written (A>B, A=B); and a row ends only at \\, so an equation may run over two lines.
        if s.contains("\\\\") { s = s.replacingOccurrences(of: "\n", with: " ") }
        s = s.replacingOccurrences(of: "&\\s*(=|\\\\equiv|:=)", with: "≔", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\\\", with: ";")
        s = s.replacingOccurrences(of: "\\\\(left|right|,|;|!|quad|qquad)(?![a-zA-Z])", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\\\(text|mathrm|mathit|mathbf|operatorname)\\s*\\{([^{}]*)\\}", with: "$2", options: .regularExpression)
        // _{out}, _{1}: the subscript written after an underscore, as the rest of the app writes it.
        s = s.replacingOccurrences(of: "_\\{\\s*([A-Za-z0-9]+)\\s*\\}", with: "_$1", options: .regularExpression)
        // \overline{A ∧ B} and \bar{A}: not, of all that is under the bar.
        while let r = s.range(of: "\\\\(overline|bar)\\s*\\{", options: .regularExpression) {
            var depth = 1, j = r.upperBound
            while j < s.endIndex, depth > 0 {
                if s[j] == "{" { depth += 1 } else if s[j] == "}" { depth -= 1 }
                if depth > 0 { j = s.index(after: j) }
            }
            guard j < s.endIndex else { return input }
            let inner = String(s[r.upperBound..<j])
            s.replaceSubrange(r.lowerBound...j, with: "¬(" + inner + ")")
        }
        let commands: [(String, String)] = [
            ("oplus", "⊕"), ("veebar", "⊕"), ("land", "∧"), ("wedge", "∧"), ("lor", "∨"), ("vee", "∨"), ("lnot", "¬"), ("neg", "¬"),
            ("odot", "⊙"), ("uparrow", "↑"), ("downarrow", "↓"), ("implies", "→"), ("Rightarrow", "→"), ("rightarrow", "→"), ("to", "→"),
            ("iff", "↔"), ("Leftrightarrow", "↔"), ("leftrightarrow", "↔"), ("equiv", "="), ("cdot", "·"), ("times", "×"), ("top", "1"), ("bot", "0"),
        ]
        for (name, symbol) in commands {
            s = s.replacingOccurrences(of: "\\\\\(name)(?![A-Za-z])", with: symbol, options: .regularExpression)
        }
        s = s.replacingOccurrences(of: "{", with: "(").replacingOccurrences(of: "}", with: ")")
        return s
    }

    // and, or, xor, not, nand, nor, xnor, implies, iff, true, false: as words, whole.
    private static func words(_ input: String) -> String {
        var s = input
        for (word, symbol) in [("xnor", "⊙"), ("nand", "↑"), ("nor", "↓"), ("xor", "⊕"), ("and", "∧"), ("or", "∨"), ("not", "¬"),
                               ("implies", "→"), ("iff", "↔"), ("true", "1"), ("false", "0")] {
            s = s.replacingOccurrences(of: "(?i)(?<![A-Za-z0-9_])\(word)(?![A-Za-z0-9_])", with: " \(symbol) ", options: .regularExpression)
        }
        for (written, symbol) in [("&&", "∧"), ("||", "∨"), ("⇒", "→"), ("⇔", "↔"), ("<->", "↔"), ("->", "→"), ("==", "="), (":=", "≔"), ("≡", "=")] {
            s = s.replacingOccurrences(of: written, with: symbol)
        }
        return s
    }

    // The marks that are logic only once something else has said it is: & | ! ~ · * + ^.
    private static func symbols(_ input: String) -> String {
        var s = input
        for (written, symbol) in [("&", "∧"), ("|", "∨"), ("!", "¬"), ("~", "¬"), ("·", "∧"), ("⋅", "∧"), ("*", "∧"), ("×", "∧"), ("+", "∨"), ("^", "⊕")] {
            s = s.replacingOccurrences(of: written, with: symbol)
        }
        return s
    }

    // The statements: one to a line, or between ; and commas, outside brackets.
    // A line that ends with an operator or an open bracket, or one that begins with an operator, goes on
    // with the equation before it.
    private static func split(_ text: String) -> [String] {
        var lines: [String] = []
        for line in text.components(separatedBy: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) where !line.isEmpty {
            let joins = "∧∨⊕⊙↑↓→↔"
            if let last = lines.last, last.last.map({ joins.contains($0) || $0 == "(" || $0 == "¬" || $0 == "≔" || $0 == "=" }) == true
                || line.first.map({ joins.contains($0) }) == true {
                lines[lines.count - 1] = last + " " + line
            } else {
                lines.append(line)
            }
        }
        return topLevel(lines.joined(separator: ";").replacingOccurrences(of: ",", with: ";"), ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func topLevel(_ text: String, _ mark: Character) -> [String] {
        var parts: [String] = [], current = "", depth = 0
        for c in text {
            if c == "(" || c == "[" { depth += 1 } else if c == ")" || c == "]" { depth -= 1 }
            if c == mark, depth == 0 { parts.append(current); current = "" } else { current.append(c) }
        }
        parts.append(current)
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: Working out

    // Every row: the inputs counted up in binary, the first the most significant, and each output.
    var rows: [(inputs: [Bool], outputs: [Bool])] {
        (0..<(1 << inputs.count)).map { r in
            var env: [String: Bool] = [:]
            let values = inputs.indices.map { r >> (inputs.count - 1 - $0) & 1 == 1 }
            for (n, v) in zip(inputs, values) { env[n] = v }
            for i in order { env[outputs[i].name] = outputs[i].expr.value(env) }
            return (values, outputs.map { env[$0.name] ?? false })
        }
    }

    // The rows where each output is 1, by their number.
    func minterms(_ output: Int) -> [Int] { rows.enumerated().filter { $0.element.outputs[output] }.map(\.offset) }

    // The simplest sum of products, by the Quine–McCluskey method: the rows where it is 1 combined two
    // by two while they differ in one input only, and the fewest of what is left that cover them all.
    static func simplest(_ minterms: [Int], _ inputs: [String]) -> String {
        let n = inputs.count, all = 1 << n
        if minterms.isEmpty { return "0" }
        if minterms.count == all { return "1" }
        struct Implicant: Hashable { var value: Int; var dashes: Int }
        var current = Set(minterms.map { Implicant(value: $0, dashes: 0) }), primes = Set<Implicant>()
        while !current.isEmpty {
            var next = Set<Implicant>(), used = Set<Implicant>()
            let list = Array(current)
            for i in list.indices {
                for j in (i + 1)..<list.count where list[i].dashes == list[j].dashes {
                    let differ = list[i].value ^ list[j].value
                    guard differ.nonzeroBitCount == 1 else { continue }
                    next.insert(Implicant(value: list[i].value & ~differ, dashes: list[i].dashes | differ))
                    used.insert(list[i]); used.insert(list[j])
                }
            }
            primes.formUnion(current.subtracting(used))
            current = next
        }
        func covers(_ p: Implicant, _ m: Int) -> Bool { (m & ~p.dashes) == p.value }
        var chosen: [Implicant] = [], left = Set(minterms)
        // The essential ones first, the only cover of some row; then whichever covers most of what is left.
        for m in minterms {
            let by = primes.filter { covers($0, m) }
            if by.count == 1, let only = by.first, !chosen.contains(only) { chosen.append(only) }
        }
        for p in chosen { left = left.filter { !covers(p, $0) } }
        while !left.isEmpty {
            let best = primes.max { a, b in
                let (ca, cb) = (left.filter { covers(a, $0) }.count, left.filter { covers(b, $0) }.count)
                return ca != cb ? ca < cb : a.dashes.nonzeroBitCount < b.dashes.nonzeroBitCount
            }!
            chosen.append(best)
            left = left.filter { !covers(best, $0) }
        }
        // Each term its inputs in order; the shorter terms first, then as the inputs come.
        let literals = chosen.map { p -> [(Int, Bool)] in
            (0..<n).compactMap { i in
                let bit = 1 << (n - 1 - i)
                return p.dashes & bit != 0 ? nil : (i, p.value & bit == 0)
            }
        }.sorted { a, b in
            if a.count != b.count { return a.count < b.count }
            // As the rows count: an input's 0 (¬A) before its 1 (A).
            for (x, y) in zip(a, b) where x != y { return x.0 != y.0 ? x.0 < y.0 : x.1 && !y.1 }
            return false
        }
        let terms = literals.map { $0.map { ($0.1 ? "¬" : "") + inputs[$0.0] } }
        if terms.count == 1 { return terms[0].joined(separator: " ∧ ") }
        return terms.map { $0.count == 1 ? $0[0] : "(" + $0.joined(separator: " ∧ ") + ")" }.joined(separator: " ∨ ")
    }

    private static func sigma(_ m: [Int]) -> String { "Σm(" + m.map(String.init).joined(separator: ", ") + ")" }

    // MARK: Card

    var solution: Solution {
        switch kind {
        case .refused(let why): return Solution(exact: "No truth table", approx: why)
        case .equivalence:
            let table = rows
            guard let differ = table.firstIndex(where: { $0.outputs[0] != $0.outputs[1] }) else {
                return Solution(exact: "True", approx: "The two sides agree in all \(table.count) rows: they are equivalent.")
            }
            let at = zip(inputs, table[differ].inputs).map { "\($0) = \($1 ? 1 : 0)" }.joined(separator: ", ")
            return Solution(exact: "False", approx: "They differ where \(at).")
        case .table:
            if inputs.isEmpty {
                let v = rows[0].outputs
                return Solution(exact: outputs.count == 1 ? (v[0] ? "= 1" : "= 0") : zip(outputs, v).map { "\($0.name) = \($1 ? 1 : 0)" }.joined(separator: ", "),
                                approx: outputs.count == 1 ? (v[0] ? "True" : "False") : nil)
            }
            let count = 1 << inputs.count
            if outputs.count == 1 {
                let m = minterms(0), name = outputs[0].name
                if m.count == count { return Solution(exact: "Always 1", approx: "A tautology: true in all \(count) rows.") }
                if m.isEmpty { return Solution(exact: "Always 0", approx: "A contradiction: false in all \(count) rows.") }
                let simplest = inputs.count <= 8 ? "; simplest, " + Circuit.simplest(m, inputs) : ""
                return Solution(exact: "\(name) = " + Circuit.sigma(m), approx: "True in \(m.count) of \(count) rows" + simplest)
            }
            return Solution(exact: inputs.joined(separator: ", ") + " → " + outputs.map(\.name).joined(separator: ", "),
                            approx: "\(gateCount) gate\(gateCount == 1 ? "" : "s"); a truth table of \(count) rows")
        }
    }

    // One output: its simplest form; several: the table, a tab between columns, to paste into a spreadsheet.
    var copyText: String? {
        switch kind {
        case .refused: return nil
        case .equivalence: return solution.exact
        case .table:
            if inputs.isEmpty { return rows[0].outputs.map { $0 ? "1" : "0" }.joined(separator: ", ") }
            if outputs.count == 1, inputs.count <= 8 { return "\(outputs[0].name) = " + Circuit.simplest(minterms(0), inputs) }
            let head = (inputs + outputs.map(\.name)).joined(separator: "\t")
            return ([head] + rows.map { ($0.inputs + $0.outputs).map { $0 ? "1" : "0" }.joined(separator: "\t") }).joined(separator: "\n")
        }
    }

    // MARK: Working

    var details: Details? {
        if case .refused = kind { return nil }
        let heading: String
        if case .equivalence = kind { heading = outputs[0].expr.written() + " = " + outputs[1].expr.written() }
        else if outputs.count == 1, case .table = kind, !inputs.contains(outputs[0].name), outputs[0].name == implicitName { heading = outputs[0].expr.written() }
        else { heading = outputs.map { "\($0.name) = \($0.expr.written())" }.joined(separator: ";  ") }
        var steps: [Step] = []
        let graph = network
        let count = 1 << inputs.count

        if !inputs.isEmpty {
            var note = "\(inputs.count) input\(inputs.count == 1 ? "" : "s"), \(inputs.joined(separator: ", ")), so \(count) rows of the truth table."
            if case .table = kind, outputs.count > 1 {
                let used = outputs.filter { o in outputs.contains { $0.name != o.name && $0.expr.names.contains(o.name) } }
                for o in used {
                    let by = outputs.filter { $0.expr.names.contains(o.name) }.map(\.name)
                    note += " \(o.name) is used again in \(by.joined(separator: " and "))."
                }
            }
            steps.append(Step(label: "Finding the inputs", math: nil, note: note))
        }
        let tally = graph.tally
        if !tally.isEmpty {
            var note: String?
            let shared = graph.shared
            if !shared.isEmpty { note = shared.map { "\($0) is made once and used twice or more." }.joined(separator: " ") }
            steps.append(Step(label: "Counting the gates", math: t(tally), note: note))
        }
        var solutions: [Math] = []
        switch kind {
        case .equivalence:
            let (l, r) = (minterms(0), minterms(1))
            steps.append(Step(label: "Working out the left side in every row", math: t("Σm: " + (l.isEmpty ? "none" : l.map(String.init).joined(separator: ", ")))))
            steps.append(Step(label: "Working out the right side in every row", math: t("Σm: " + (r.isEmpty ? "none" : r.map(String.init).joined(separator: ", ")))))
            steps.append(Step(label: "Comparing them", math: nil,
                              note: l == r ? "They are 1 in the same rows, and 0 in the same rows: the two sides are equivalent." : solution.approx ?? ""))
            solutions = [t(solution.exact)]
        default:
            for (i, o) in outputs.enumerated() {
                let m = minterms(i)
                if !inputs.isEmpty {
                    steps.append(Step(label: "Reading where \(o.name) is 1", math: t("\(o.name) = " + (m.isEmpty ? "0 in every row" : Circuit.sigma(m))),
                                      note: m.isEmpty || m.count == count ? nil : "The rows are numbered by their inputs read as a binary number, \(inputs.first!) the most significant."))
                }
                solutions.append(t("\(o.name) = " + (inputs.count <= 8 ? Circuit.simplest(m, inputs) : Circuit.sigma(m))))
            }
        }
        var d = Details(name: "", equation: t(heading), steps: steps, solutions: solutions,
                        note: inputs.count <= 8 && !inputs.isEmpty && { if case .table = kind { return true } else { return false } }()
                            ? "Each in its simplest sum of products, by the Quine–McCluskey method." : nil,
                        f: { _ in .nan }, roots: [])
        if inputs.count <= 6 {
            d.truthTable = TruthTable(inputs: inputs, outputs: outputs.map(\.name), rows: rows.map { $0.inputs + $0.outputs })
        }
        if graph.nodes.count <= 80 {
            var layout = graph.layout
            layout.order = inputs
            d.circuit = layout
        }
        if d.truthTable != nil || d.circuit != nil { d.probe = CircuitProbe() }
        return d
    }

    // The name given to a single expression's output.
    private var implicitName: String {
        let taken = Set(outputs.flatMap { $0.expr.names })
        return ["Q", "F", "Y", "Z", "X"].first { !taken.contains($0) } ?? "Out"
    }

    private var gateCount: Int { network.nodes.filter { if case .gate = $0 { true } else { false } }.count }

    // MARK: The circuit

    var network: Network {
        var net = Network()
        var signal: [String: Int] = [:]
        for name in inputs { signal[name] = net.add(.input(name)) }
        for i in order { signal[outputs[i].name] = net.build(outputs[i].expr, signal) }
        net.outputs = outputs.map { ($0.name, signal[$0.name]!) }
        return net
    }
}

// The gates as they are wired: each made once, a gate fed by the same signals as another being that
// gate, and an output a gate already made where one is named and used again.
struct Network {
    enum Gate: String { case and = "AND", or = "OR", xor = "XOR", xnor = "XNOR", nand = "NAND", nor = "NOR", not = "NOT" }
    enum Node: Hashable {
        case input(String)
        case constant(Bool)
        case gate(Gate, [Int])
    }

    var nodes: [Node] = []
    var outputs: [(name: String, node: Int)] = []
    private var made: [Node: Int] = [:]

    init() {}
    init(nodes: [Node]) { self.nodes = nodes }

    mutating func add(_ node: Node) -> Int {
        var key = node
        if case .gate(let g, let inputs) = node, g != .not { key = .gate(g, inputs.sorted()) }
        if let existing = made[key] { return existing }
        nodes.append(node)
        made[key] = nodes.count - 1
        return nodes.count - 1
    }

    mutating func build(_ e: Switching, _ signal: [String: Int]) -> Int {
        switch e {
        case .name(let n): return signal[n] ?? add(.input(n))
        case .constant(let v): return add(.constant(v))
        case .not(let a): return add(.gate(.not, [build(a, signal)]))
        case .binary(let op, let a, let b):
            switch op {
            // ∧ and ∨ written in a row are one gate of up to four inputs.
            case .and, .or:
                var parts: [Switching] = []
                func gather(_ x: Switching) {
                    if case .binary(let o, let l, let r) = x, o == op { gather(l); gather(r) } else { parts.append(x) }
                }
                gather(e)
                var ins = parts.map { build($0, signal) }
                while ins.count > 4 { ins = [add(.gate(op == .and ? .and : .or, Array(ins.prefix(4))))] + ins.dropFirst(4) }
                return add(.gate(op == .and ? .and : .or, ins))
            case .xor: return add(.gate(.xor, [build(a, signal), build(b, signal)]))
            case .xnor, .iff: return add(.gate(.xnor, [build(a, signal), build(b, signal)]))
            case .nand: return add(.gate(.nand, [build(a, signal), build(b, signal)]))
            case .nor: return add(.gate(.nor, [build(a, signal), build(b, signal)]))
            case .implies: return add(.gate(.or, [add(.gate(.not, [build(a, signal)])), build(b, signal)]))
            }
        }
    }

    // The value of every node, the inputs given: the gates come after what feeds them.
    func values(_ inputs: [String: Bool]) -> [Bool] {
        var v = [Bool](repeating: false, count: nodes.count)
        for (i, node) in nodes.enumerated() {
            switch node {
            case .input(let n): v[i] = inputs[n] ?? false
            case .constant(let b): v[i] = b
            case .gate(let g, let ins):
                let x = ins.map { v[$0] }
                switch g {
                case .and: v[i] = x.allSatisfy { $0 }
                case .or: v[i] = x.contains(true)
                case .xor: v[i] = x.filter { $0 }.count % 2 == 1
                case .xnor: v[i] = x.filter { $0 }.count % 2 == 0
                case .nand: v[i] = !x.allSatisfy { $0 }
                case .nor: v[i] = !x.contains(true)
                case .not: v[i] = !x[0]
                }
            }
        }
        return v
    }

    // "2 XOR, 3 AND, 1 OR".
    var tally: String {
        var counts: [Gate: Int] = [:], order: [Gate] = []
        for node in nodes {
            guard case .gate(let g, _) = node else { continue }
            if counts[g] == nil { order.append(g) }
            counts[g, default: 0] += 1
        }
        return order.map { "\(counts[$0]!) \($0.rawValue)" }.joined(separator: ", ")
    }

    // Gates, not named, that feed more than one other, as the expressions they make.
    var shared: [String] {
        var uses = [Int](repeating: 0, count: nodes.count)
        for node in nodes { if case .gate(_, let ins) = node { for i in ins { uses[i] += 1 } } }
        for o in outputs { uses[o.node] += 1 }
        let named = Set(outputs.map(\.node))
        return nodes.indices.filter { i in
            guard uses[i] > 1, !named.contains(i), case .gate = nodes[i] else { return false }
            return true
        }.map { expression($0) }
    }

    func expression(_ i: Int, _ outer: Int = 0) -> String {
        switch nodes[i] {
        case .input(let n): return n
        case .constant(let v): return v ? "1" : "0"
        case .gate(.not, let ins): return "¬" + expression(ins[0], 5)
        case .gate(let g, let ins):
            let (symbol, p): (String, Int) = switch g {
            case .and: ("∧", 4); case .nand: ("↑", 4); case .or: ("∨", 2); case .nor: ("↓", 2); case .xor: ("⊕", 3); default: ("⊙", 3)
            }
            let s = ins.map { expression($0, p + 1) }.joined(separator: " \(symbol) ")
            return p < outer ? "(" + s + ")" : s
        }
    }

    // MARK: Laying it out

    // In columns by depth, the inputs on the left and the outputs on the right; a wire that passes a
    // column goes straight through it, the gates in each column put in the order that crosses fewest
    // wires, and each as near level with what feeds it as there is room for.
    var layout: CircuitLayout {
        var level = [Int](repeating: 0, count: nodes.count)
        for (i, node) in nodes.enumerated() { if case .gate(_, let ins) = node { level[i] = 1 + (ins.map { level[$0] }.max() ?? 0) } }
        let last = (level.max() ?? 0) + 1

        enum Kind { case node(Int), pass, output(String) }
        struct Vertex { var kind: Kind; var column: Int; var y: CGFloat = 0; var height: CGFloat = 0; var source = -1 }
        var vertices: [Vertex] = [], edges: [(from: Int, to: Int)] = []
        var vertexOf: [Int: Int] = [:], passes: [String: Int] = [:]
        // Inputs first, in the order written, then the rest, which come after what feeds them.
        for (i, node) in nodes.enumerated() {
            let height: CGFloat
            if case .gate(let g, let ins) = node { height = g == .not ? 30 : max(36, CGFloat(ins.count) * 16 + 6) } else { height = 0 }
            vertexOf[i] = vertices.count
            vertices.append(Vertex(kind: .node(i), column: level[i], height: height))
        }
        // From a signal to a column further on, through a pass in each column between, one per signal.
        func reach(_ source: Int, _ column: Int) -> Int {
            var at = vertexOf[source]!
            for c in (level[source] + 1)..<max(level[source] + 1, column) {
                let key = "\(source):\(c)"
                if let p = passes[key] { at = p; continue }
                vertices.append(Vertex(kind: .pass, column: c, source: source))
                edges.append((at, vertices.count - 1))
                passes[key] = vertices.count - 1
                at = vertices.count - 1
            }
            return at
        }
        for (i, node) in nodes.enumerated() {
            guard case .gate(_, let ins) = node else { continue }
            for input in ins { edges.append((reach(input, level[i]), vertexOf[i]!)) }
        }
        for o in outputs {
            let from = reach(o.node, last)   // first: it may add passes
            vertices.append(Vertex(kind: .output(o.name), column: last, source: o.node))
            edges.append((from, vertices.count - 1))
        }

        // The order down each column: by where what feeds each is, then by where what each feeds is.
        var columns = [[Int]](repeating: [], count: last + 1)
        for (v, vertex) in vertices.enumerated() { columns[vertex.column].append(v) }
        var into = [[Int]](repeating: [], count: vertices.count), out = [[Int]](repeating: [], count: vertices.count)
        for e in edges { into[e.to].append(e.from); out[e.from].append(e.to) }
        func positions() -> [Int: Double] {
            var p: [Int: Double] = [:]
            for column in columns { for (k, v) in column.enumerated() { p[v] = Double(k) } }
            return p
        }
        for _ in 0..<4 {
            for c in 1...last {
                let p = positions()
                columns[c] = columns[c].enumerated().sorted { a, b in
                    let (x, y) = (into[a.element].map { p[$0]! }, into[b.element].map { p[$0]! })
                    let (bx, by) = (x.isEmpty ? Double(a.offset) : x.reduce(0, +) / Double(x.count), y.isEmpty ? Double(b.offset) : y.reduce(0, +) / Double(y.count))
                    return bx != by ? bx < by : a.offset < b.offset
                }.map(\.element)
            }
            for c in stride(from: last - 1, through: 1, by: -1) {
                let p = positions()
                columns[c] = columns[c].enumerated().sorted { a, b in
                    let (x, y) = (out[a.element].map { p[$0]! }, out[b.element].map { p[$0]! })
                    let (bx, by) = (x.isEmpty ? p[a.element]! : x.reduce(0, +) / Double(x.count), y.isEmpty ? p[b.element]! : y.reduce(0, +) / Double(y.count))
                    return bx != by ? bx < by : a.offset < b.offset
                }.map(\.element)
            }
        }

        // Heights: the inputs evenly; each later one level with what feeds it, pushed down only where
        // that would crowd the one above, so that a wire runs straight wherever it can.
        let top: CGFloat = 18
        func gap(_ a: Vertex, _ b: Vertex) -> CGFloat { max((a.height + b.height) / 2 + 14, 26) }
        var outY: [Int: CGFloat] = [:]
        for (k, v) in columns[0].enumerated() { vertices[v].y = top + CGFloat(k) * 34; outY[v] = vertices[v].y }
        for c in 1...last {
            let column = columns[c]
            var wanted: [CGFloat] = []
            for v in column {
                let feeds = into[v].compactMap { outY[$0] }
                wanted.append(feeds.isEmpty ? top : feeds.reduce(0, +) / CGFloat(feeds.count))
            }
            var placed: [CGFloat] = []
            for (k, v) in column.enumerated() {
                var y = max(wanted[k], top + vertices[v].height / 2)
                if k > 0 { y = max(y, placed[k - 1] + gap(vertices[column[k - 1]], vertices[v])) }
                placed.append(y)
            }
            for (k, v) in column.enumerated() { vertices[v].y = placed[k]; outY[v] = placed[k] }
        }

        // Across: the inputs' names, then each column of gates, with room between for the wires that turn.
        func written(_ v: Vertex) -> String {
            switch v.kind {
            case .node(let i): if case .input(let n) = nodes[i] { return n }; if case .constant(let b) = nodes[i] { return b ? "1" : "0" }; return ""
            case .output(let n): return n
            case .pass: return ""
            }
        }
        func labelWidth(_ s: String) -> CGFloat { CGFloat(s.replacingOccurrences(of: "_", with: "").count) * 7.5 + 4 }
        var widths = [CGFloat](repeating: 0, count: last + 1)
        widths[0] = (columns[0].map { labelWidth(written(vertices[$0])) }.max() ?? 10) + 22 + 16   // and its 0 or 1
        for c in 1..<last {
            widths[c] = columns[c].map { v -> CGFloat in
                if case .node(let i) = vertices[v].kind, case .gate(let g, _) = nodes[i] { return g == .not ? 36 : 48 }
                return 0
            }.max() ?? 0
        }
        // The turns in each gap: one upright for each signal that goes up or down to what it feeds.
        func pinY(_ edge: (from: Int, to: Int), _ pins: [Int: [Int: CGFloat]]) -> CGFloat { pins[edge.to]?[edge.from] ?? vertices[edge.to].y }
        var pins: [Int: [Int: CGFloat]] = [:]
        for (v, vertex) in vertices.enumerated() {
            guard case .node(let i) = vertex.kind, case .gate(let g, _) = nodes[i] else { continue }
            let feeds = into[v].sorted { vertices[$0].y < vertices[$1].y }
            var map: [Int: CGFloat] = [:]
            for (k, f) in feeds.enumerated() {
                map[f] = g == .not ? vertex.y : vertex.y - vertex.height / 2 + vertex.height * CGFloat(k + 1) / CGFloat(feeds.count + 1)
            }
            pins[v] = map
        }
        var turning = [[Int]](repeating: [], count: last)
        for c in 0..<last {
            let sources = Set(edges.filter { vertices[$0.from].column == c && abs(pinY($0, pins) - vertices[$0.from].y) > 0.5 }.map(\.from))
            turning[c] = sources.sorted { vertices[$0].y < vertices[$1].y }
        }
        var left = [CGFloat](repeating: 8, count: last + 1)
        for c in 1...last { left[c] = left[c - 1] + widths[c - 1] + 34 + CGFloat(turning[c - 1].count) * 10 }
        func right(_ c: Int) -> CGFloat { left[c] + widths[c] }

        var layout = CircuitLayout(size: .zero, gates: [], wires: [], dots: [], labels: [])
        layout.nodes = nodes
        // Each wire with the signal it carries: the node its vertex is, or passes on.
        func signal(_ v: Int) -> Int { if case .node(let i) = vertices[v].kind { return i }; return vertices[v].source }
        func wire(_ points: [CGPoint], _ node: Int) { layout.wires.append(points); layout.signals.append(node) }
        var gateFrame: [Int: CGRect] = [:]
        for (v, vertex) in vertices.enumerated() {
            let c = vertex.column
            switch vertex.kind {
            case .node(let i):
                switch nodes[i] {
                case .gate(let g, _):
                    let w: CGFloat = g == .not ? 36 : 48
                    let frame = CGRect(x: left[c] + (widths[c] - w) / 2, y: vertex.y - vertex.height / 2, width: w, height: vertex.height)
                    gateFrame[v] = frame
                    layout.gates.append(.init(kind: g, frame: frame, pins: (pins[v] ?? [:]).values.sorted()))
                    if frame.maxX < right(c) - 0.5 { wire([CGPoint(x: frame.maxX, y: vertex.y), CGPoint(x: right(c), y: vertex.y)], i) }
                default:
                    layout.labels.append(.init(text: written(vertex), at: CGPoint(x: right(0) - 18, y: vertex.y), leading: false))
                    wire([CGPoint(x: right(0) - 14, y: vertex.y), CGPoint(x: right(0), y: vertex.y)], i)
                    layout.terminals.append(CGPoint(x: right(0) - 14, y: vertex.y))
                    if case .input(let n) = nodes[i] {
                        layout.inputs.append(.init(name: n, node: i, at: CGPoint(x: right(0) - 14, y: vertex.y), labelWidth: labelWidth(n)))
                    }
                }
            case .pass:
                wire([CGPoint(x: left[c], y: vertex.y), CGPoint(x: right(c), y: vertex.y)], vertex.source)
            case .output(let name):
                wire([CGPoint(x: left[c], y: vertex.y), CGPoint(x: left[c] + 14, y: vertex.y)], vertex.source)
                layout.terminals.append(CGPoint(x: left[c] + 14, y: vertex.y))
                layout.labels.append(.init(text: name, at: CGPoint(x: left[c] + 20, y: vertex.y), leading: true))
                layout.outputs.append(.init(name: name, node: vertex.source, at: CGPoint(x: left[c] + 14, y: vertex.y), labelWidth: labelWidth(name)))
            }
        }
        // The wires across each gap: straight where what is fed is level, else along, up or down, and along.
        for c in 0..<last {
            for (k, source) in turning[c].enumerated() {
                let x = right(c) + 17 + CGFloat(k) * 10
                let ys = vertices[source].y
                let targets = edges.filter { $0.from == source }.map { e -> (CGFloat, CGFloat) in (gateFrame[e.to]?.minX ?? left[c + 1], pinY(e, pins)) }
                for (tx, ty) in targets {
                    wire(abs(ty - ys) < 0.5 ? [CGPoint(x: right(c), y: ys), CGPoint(x: tx, y: ys)]
                                            : [CGPoint(x: right(c), y: ys), CGPoint(x: x, y: ys), CGPoint(x: x, y: ty), CGPoint(x: tx, y: ty)], signal(source))
                }
                // A dot where a wire branches: three or more ways meeting on the upright.
                let ys2 = targets.map(\.1) + [ys]
                let (low, high) = (ys2.min()!, ys2.max()!)
                for y in Set(ys2.map { ($0 * 2).rounded() / 2 }) {
                    let rights = targets.filter { abs($0.1 - y) < 0.5 }.count, lefts = abs(y - ys) < 0.5 ? 1 : 0
                    let ways = rights + lefts + (y > low + 0.5 ? 1 : 0) + (y < high - 0.5 ? 1 : 0)
                    if ways >= 3 { layout.dots.append(CGPoint(x: x, y: y)); layout.dotSignals.append(signal(source)) }
                }
            }
            for e in edges where vertices[e.from].column == c && !turning[c].contains(e.from) {
                wire([CGPoint(x: right(c), y: vertices[e.from].y), CGPoint(x: gateFrame[e.to]?.minX ?? left[c + 1], y: vertices[e.from].y)], signal(e.from))
            }
        }
        let width = right(last) + 26 + (outputs.map { labelWidth($0.name) }.max() ?? 0) + 22   // and its 0 or 1
        let height = (vertices.map { $0.y + $0.height / 2 }.max() ?? 0) + top
        layout.size = CGSize(width: width, height: height)
        return layout
    }
}

// The circuit as it is drawn: each gate in its place, the wires as lines that turn at right angles,
// a dot where one branches, and the names of the inputs and outputs.
struct CircuitLayout {
    struct Gate { var kind: Network.Gate; var frame: CGRect; var pins: [CGFloat] }
    struct Label { var text: String; var at: CGPoint; var leading: Bool }
    struct End { var name: String; var node: Int; var at: CGPoint; var labelWidth: CGFloat }   // an input or an output, at its terminal
    var size: CGSize
    var gates: [Gate]
    var wires: [[CGPoint]]
    var dots: [CGPoint]
    var labels: [Label]
    var terminals: [CGPoint] = []
    // What makes it work: every node, the one each wire and dot carries, and the inputs and outputs.
    var nodes: [Network.Node] = []
    var signals: [Int] = []
    var dotSignals: [Int] = []
    var inputs: [End] = []
    var outputs: [End] = []
    var order: [String] = []    // the inputs as the truth table has them, the first the most significant

    // The value of every node, as the inputs are in the row given; the first input the most significant bit.
    func values(row: Int, order: [String]) -> [Bool] {
        var given: [String: Bool] = [:]
        for (k, name) in order.enumerated() { given[name] = row >> (order.count - 1 - k) & 1 == 1 }
        return Network(nodes: nodes).values(given)
    }
}

// The row the working is looking at, shared by the truth table and the circuit drawn: clicking an input
// of the circuit switches it, and clicking a row of the table sets every input as that row has them.
// Its number is the inputs read as a binary number, the first the most significant.
@Observable final class CircuitProbe {
    var row = 0
}

// The truth table: the inputs counted up in binary, and each output in its row.
struct TruthTable {
    var inputs: [String]
    var outputs: [String]
    var rows: [[Bool]]
}

// The tokens and the grammar: ¬ and a ′ after binding tightest, then ∧ (and two side by side), ⊕,
// ∨, and → and ↔ loosest.
struct SwitchingParser {
    enum Token: Equatable { case name(String), constant(Bool), op(Switching.Op), not, prime, open, close }
    var tokens: [Token]
    var at = 0

    // b, two primes and 0 below: b″_0 — the one way a primed name is written, however it was typed.
    static func canonical(_ base: String, primes: Int, sub: String) -> String {
        base + String(repeating: "′", count: primes) + (sub.isEmpty ? "" : "_" + sub)
    }

    static func parse(_ text: String, singleLetters: Bool, known: Set<String> = []) -> Switching? {
        guard let tokens = tokenize(text, singleLetters: singleLetters, known: known), !tokens.isEmpty else { return nil }
        var p = SwitchingParser(tokens: tokens)
        guard let e = p.implication(), p.at == tokens.count else { return nil }
        return e
    }

    // A name is a letter, its digits and what follows an underscore, a0 being a_0; or, where whole
    // names are allowed, the letters and digits together, Cout.
    // A name with a prime that is one of the names given, b0' where b0' = b0 ⊕ M, is that name; any
    // other prime is "not".
    static func tokenize(_ text: String, singleLetters: Bool, known: Set<String> = []) -> [Token]? {
        let primes: Set<Character> = ["'", "’", "′"]
        let chars = Array(text)
        var out: [Token] = [], i = 0
        let ops: [Character: Token] = ["∧": .op(.and), "∨": .op(.or), "⊕": .op(.xor), "⊙": .op(.xnor), "↑": .op(.nand), "↓": .op(.nor),
                                       "→": .op(.implies), "↔": .op(.iff), "¬": .not, "'": .prime, "’": .prime, "′": .prime,
                                       "(": .open, "[": .open, ")": .close, "]": .close]
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            if let t = ops[c] { out.append(t); i += 1; continue }
            if c == "0" || c == "1" {
                guard i + 1 == chars.count || !(chars[i + 1].isLetter || chars[i + 1].isNumber) else { return nil }
                out.append(.constant(c == "1")); i += 1; continue
            }
            guard c.isLetter else { return nil }
            var j = i + 1
            if singleLetters {
                while j < chars.count, chars[j].isASCII, chars[j].isNumber { j += 1 }
            } else {
                while j < chars.count, chars[j].isLetter || (chars[j].isASCII && chars[j].isNumber) { j += 1 }
            }
            var name = String(chars[i..<j])
            // b'_0: the primes written before the subscript.
            if !known.isEmpty, j < chars.count, primes.contains(chars[j]) {
                var k = j
                while k < chars.count, primes.contains(chars[k]) { k += 1 }
                if k + 1 < chars.count, chars[k] == "_" {
                    var e = k + 1
                    let braced = chars[e] == "("
                    if braced { e += 1 }
                    let start = e
                    while e < chars.count, chars[e].isASCII, chars[e].isLetter || chars[e].isNumber { e += 1 }
                    if braced, e < chars.count, chars[e] == ")" { e += 1 }
                    let sub = String(chars[start..<min(e, chars.count)]).replacingOccurrences(of: ")", with: "")
                    let candidate = canonical(name, primes: k - j, sub: sub)
                    if known.contains(candidate) { out.append(.name(candidate)); i = e; continue }
                }
            }
            if j + 1 < chars.count, chars[j] == "_", chars[j + 1].isASCII, chars[j + 1].isLetter || chars[j + 1].isNumber {
                var k = j + 1
                while k < chars.count, chars[k].isASCII, chars[k].isLetter || chars[k].isNumber { k += 1 }
                name += String(chars[j..<k])
                j = k
            } else if let m = name.range(of: "^[A-Za-z]+(?=[0-9]+$)", options: .regularExpression) {
                // a0 is a with 0 below: a_0.
                name = String(name[m]) + "_" + String(name[m.upperBound...])
            }
            // b0' and b_0': the primes after the whole.
            if !known.isEmpty, j < chars.count, primes.contains(chars[j]) {
                var k = j
                while k < chars.count, primes.contains(chars[k]) { k += 1 }
                let parts = name.split(separator: "_", maxSplits: 1).map(String.init)
                let candidate = canonical(parts[0], primes: k - j, sub: parts.count == 2 ? parts[1] : "")
                if known.contains(candidate) { out.append(.name(candidate)); i = k; continue }
            }
            out.append(.name(name))
            i = j
        }
        return out
    }

    private var next: Token? { at < tokens.count ? tokens[at] : nil }

    mutating func implication() -> Switching? {
        guard let left = disjunction() else { return nil }
        if case .op(let op)? = next, op == .implies || op == .iff {
            at += 1
            guard let right = implication() else { return nil }
            return .binary(op, left, right)
        }
        return left
    }

    private mutating func disjunction() -> Switching? {
        guard var left = exclusive() else { return nil }
        while case .op(let op)? = next, op == .or || op == .nor {
            at += 1
            guard let right = exclusive() else { return nil }
            left = .binary(op, left, right)
        }
        return left
    }

    private mutating func exclusive() -> Switching? {
        guard var left = conjunction() else { return nil }
        while case .op(let op)? = next, op == .xor || op == .xnor {
            at += 1
            guard let right = conjunction() else { return nil }
            left = .binary(op, left, right)
        }
        return left
    }

    // AB, A(B ∨ C) and A ¬B, side by side, are A and B.
    private mutating func conjunction() -> Switching? {
        guard var left = unary() else { return nil }
        while let t = next {
            var op = Switching.Op.and
            if case .op(let o) = t, o == .and || o == .nand { op = o; at += 1 }
            else if case .name = t {} else if case .constant = t {} else if t == .open || t == .not {} else { break }
            guard let right = unary() else { return nil }
            left = .binary(op, left, right)
        }
        return left
    }

    private mutating func unary() -> Switching? {
        if next == .not { at += 1; return unary().map { .not($0) } }
        guard var p = primary() else { return nil }
        while next == .prime { at += 1; p = .not(p) }
        return p
    }

    private mutating func primary() -> Switching? {
        switch next {
        case .name(let n)?: at += 1; return .name(n)
        case .constant(let v)?: at += 1; return .constant(v)
        case .open?:
            at += 1
            guard let e = implication(), next == .close else { return nil }
            at += 1
            return e
        default: return nil
        }
    }
}
