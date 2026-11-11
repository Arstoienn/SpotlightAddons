import Foundation

// A formula with some of its letters given: v = u + at, u = 2, a = 3, t = 4. What is given is
// written into the formula, and what is left is solved; an expression, with no = in it, is
// worked out.
struct Given {
    var assignments: [(name: String, value: Double)]
    var substituted: String       // the equation with the numbers written in
    var solution: Solution
    var details: Details?
    var found: [Double]? = nil    // the answers, where several equations were solved one at a time
    var given: [String] = []      // n = 1/2, θ = 30°: the values as they are shown

    static func parse(_ input: String) -> Given? {
        let parts = LinearSystem.parts(input)
        guard parts.count >= 2 else { return nil }
        var assignments: [(name: String, value: Double)] = []
        var marked: [String: String] = [:]   // what 30° and π/6 are written in as, the unit kept
        var equations: [String] = []
        // The letters given a value of their own. One that stands in another's value is that
        // value, not the constant it names: in b = c + 1, c = 3, b is 4, and is found once c is
        // written in.
        let named = Set(parts.compactMap { part -> String? in
            let sides = part.split(separator: "=", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard sides.count == 2, sides[0].range(of: Greek.identifierPattern, options: .regularExpression) != nil else { return nil }
            return Greek.identifier(sides[0])
        })
        func usesNamed(_ value: String) -> Bool {
            ((try? Parser.tokenize(value)) ?? []).contains { if case .letter(let s) = $0 { named.contains(s) } else { false } }
        }
        for part in parts {
            let sides = part.split(separator: "=", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            // An expression with no = in it is worked out with the values written in:
            // mg*1.2 + 1/2mv^2, m = 55, v = 0.9. One with < or > in it is no such expression, nor
            // one with a letter marked !c; the ! of a factorial, n(n − 1)/2!, is part of one.
            if sides.count == 1, part.range(of: "[<>≤≥≠]|(?<![0-9A-Za-z)!])!", options: .regularExpression) == nil { equations.append(part); continue }
            guard sides.count == 2 else { return nil }
            if sides[0].range(of: Greek.identifierPattern, options: .regularExpression) != nil, !usesNamed(sides[1]),
               let value = (try? Parser.constant(sides[1], physical: true))?.eval(0), value.isFinite,
               sides[1].contains(where: { $0.isNumber }) || sides[1].contains("pi") || sides[1].contains("π") {
                // theta = 30 gives the θ of the equation.
                let name = Greek.identifier(sides[0])
                assignments.append((name, value))
                // A fraction, n = 1/3, goes in and is shown as typed, not as 0.333333.
                if sides[1].range(of: "°|deg|rad|pi|π|^-?[0-9]+ */ *[0-9]+$", options: .regularExpression) != nil { marked[name] = sides[1] }
            } else {
                equations.append(part)
            }
        }
        guard !assignments.isEmpty, !equations.isEmpty, equations.count <= 4 else { return nil }
        // An angle is given with its unit: θ = 30° as it was typed, and θ = 30 in what the
        // settings take a sine's angle in, rad unless it is degrees.
        let angles = equations.reduce(into: Set<String>()) { $0.formUnion(Given.angles(in: $1)) }
        let given = assignments.map { a in
            if let typed = marked[a.name], typed.range(of: "°|deg|rad|pi|π", options: .regularExpression) != nil {
                return "\(a.name) = " + typed.replacingOccurrences(of: "pi", with: "π")
                    .replacingOccurrences(of: "(?<=[0-9.])\\s*rad", with: " rad", options: .regularExpression)
                    .replacingOccurrences(of: "(?<=[0-9.])\\s*deg", with: "°", options: .regularExpression)
            }
            let shown = marked[a.name].map { $0.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "−") } ?? decimal(a.value)
            return "\(a.name) = \(shown)" + (angles.contains(a.name) ? (Options.degrees ? "°" : " rad") : "")
        }
        let taking = given.joined(separator: ", ")
        // Several equations are solved one at a time where each in turn has one letter left, as
        // they would be by hand; together, as a system, where they do not.
        if equations.count >= 2, let chained = chain(equations, assignments, marked, given) { return chained }
        let equation = equations.joined(separator: ", ")
        guard let rewritten = write(assignments, marked, into: equation), rewritten != equation else { return nil }
        // An expression with letters still in it once the values are written in is that expression,
        // tidied: x + y with x = 2 is y + 2. Too few values are wanting only in an equation.
        // g and c among the letters left are the constants they name, as they are beside an unknown.
        var tidied: (text: String, constants: [String])?
        if equations.count == 1, !equation.contains("="), let tokens = try? Parser.tokenize(rewritten),
           case let letters = unique(tokens.compactMap { if case .letter(let l) = $0, l != "e" { l } else { nil } }),
           letters.contains(where: { Constants.all[$0] == nil }) {
            tidied = (rewritten, letters.filter { Constants.all[$0] != nil })
        }
        let left = tidied.flatMap { Simplification.parse($0.text, always: true, constants: Set($0.constants)) }
        guard let solution = left?.solution ?? Solver.solve(rewritten) else { return nil }
        var d = left?.details ?? Solver.details(rewritten)
        // Several equations are each written out, with commas between.
        func lines(_ text: String) -> Math {
            let parts = LinearSystem.parts(text)
            return parts.count == 1 ? written(text) : Math.row(parts.enumerated().flatMap { i, e in (i == 0 ? [] : [t(",   ")]) + [written(e)] })
        }
        d?.steps.insert(Step(label: "Substituting \(taking)", math: lines(rewritten)), at: 0)
        // g written in straight after is one substitution with the rest: Substituting m = 55, v = 0.9, g = 9.8 m s⁻².
        if let steps = d?.steps, steps.count > 1, steps[1].label.hasPrefix("Substituting ") {
            d?.steps[1].label = "Substituting \(taking), " + steps[1].label.dropFirst("Substituting ".count)
            d?.steps.remove(at: 0)
        }
        d?.equation = equations.count == 1 ? written(equation, header: true) : lines(equation)
        var shown = solution
        // What was given, with what a constant was taken for, if it was: Taking L = 1, g = 9.8 m s⁻².
        if shown.approx == nil { shown.approx = "Taking " + taking }
        else if let known = shown.approx, known.hasPrefix("Taking ") { shown.approx = "Taking \(taking), \(known.dropFirst("Taking ".count))" }
        if let constants = tidied?.constants, left != nil, !constants.isEmpty {
            shown.approx = "Taking \(taking), " + Constants.values(constants)
            if let first = d?.steps.first, first.label.hasPrefix("Substituting ") { d?.steps[0].label = "Substituting \(taking), " + Constants.values(constants) }
        }
        return Given(assignments: assignments, substituted: rewritten, solution: shown, details: d, given: given)
    }

    // = 3.15625 where the figures shown are the whole of it, ≈ 11.5464 where they are rounded.
    private static func equalOrApprox(_ x: Double) -> String {
        let shown = Double(decimal(x).replacingOccurrences(of: "−", with: "-")) ?? .nan
        return abs(shown - x) <= 1e-12 * max(1, abs(x)) ? "= \(decimal(x))" : "≈ \(decimal(x))"
    }

    // An equation as it is written on paper, v = 2 + 3·4, where it can be read; as typed where not.
    // An expression, with no = in it, is the heading as it stands and a line of working after "= ".
    private static func written(_ equation: String, header: Bool = false) -> Math {
        if !equation.contains("="), let tokens = try? Parser.tokenize(equation) {
            var letters: [String] = []
            for token in tokens { if case .letter(let s) = token, !letters.contains(s) { letters.append(s) } }
            var state = Parser.State(tokens: tokens, unknown: "", bound: letters)
            if let e = try? state.expression(), state.at == tokens.count { return header ? typeset(e, "") : row(t("= "), typeset(e, "")) }
        }
        guard let (left, right) = read(equation) else { return t(equation) }
        return row(typeset(left, ""), t(" = "), typeset(right, ""))
    }

    // Both sides of an equation, every letter in it standing for itself.
    private static func read(_ equation: String) -> (Expr, Expr)? {
        guard let tokens = try? Parser.tokenize(equation) else { return nil }
        var letters: [String] = []
        for token in tokens { if case .letter(let s) = token, !letters.contains(s) { letters.append(s) } }
        var state = Parser.State(tokens: tokens, unknown: "", bound: letters)
        guard let left = try? state.expression(), state.take("="), let right = try? state.expression(), state.at == tokens.count else { return nil }
        return (left, right)
    }

    // 5.05 = 1.6f, f = Nμ, N = mg cos(25°), m = 1.3: N from the third, f from the first, and then
    // μ from the second, each with what is known written in. A letter that is only a step on the
    // way, f = … and N = … used in another equation, is shown with what was given; the rest are
    // the answer.
    private static func chain(_ equations: [String], _ assignments: [(name: String, value: Double)], _ marked: [String: String], _ given: [String]) -> Given? {
        var known = assignments
        var done = Array(repeating: false, count: equations.count)
        var steps: [Step] = []
        var found: [(name: String, value: Double, line: String)] = []
        var constants: [String] = []
        var last = ""
        while done.contains(false) {
            var progress = false
            for (k, equation) in equations.enumerated() where !done[k] {
                guard let rewritten = write(known, marked, into: equation),
                      let eq = try? Parser.parse(rewritten), !known.contains(where: { $0.name == eq.unknown }),
                      let solution = Solver.solve(rewritten), Solver.values(rewritten).count == 1, let value = Solver.values(rewritten).first
                else { continue }
                let letters = Set(((try? Parser.tokenize(equation)) ?? []).compactMap { if case .letter(let s) = $0 { s } else { nil } })
                let used = known.filter { letters.contains($0.name) }
                let math = row(typeset(eq.left.withValues, eq.unknown), t(" = "), typeset(eq.right.withValues, eq.unknown))
                let taken = used.map { a in given.first { $0.hasPrefix(a.name + " = ") } ?? "\(a.name) \(equalOrApprox(a.value))" } + (eq.constants.isEmpty ? [] : [Constants.values(eq.constants)])
                steps.append(Step(label: taken.isEmpty ? "Solving (\(k + 1)) for \(eq.unknown)" : "Substituting \(taken.joined(separator: ", ")) into (\(k + 1))", math: math))
                let line = solution.exact + (solution.approx?.hasPrefix("≈") == true ? " \(solution.approx!)" : "")
                steps.append(Step(label: "Hence", math: t(line)))
                known.append((eq.unknown, value))
                found.append((eq.unknown, value, solution.exact))
                constants = unique(constants + eq.constants)
                done[k] = true
                progress = true
                last = rewritten
            }
            guard progress else { return nil }
        }
        // A letter worked out from f = … and used in another equation is a step on the way.
        func defined(_ name: String) -> Bool {
            equations.contains { $0.split(separator: "=").first.map { Greek.names[$0.trimmingCharacters(in: .whitespaces)] ?? $0.trimmingCharacters(in: .whitespaces) } == name }
        }
        func usedElsewhere(_ name: String) -> Bool {
            equations.filter { e in ((try? Parser.tokenize(e)) ?? []).contains(.letter(name)) }.count > 1
        }
        var answers = found.filter { !(defined($0.name) && usedElsewhere($0.name)) }
        if answers.isEmpty { answers = found }
        let along = found.filter { f in !answers.contains { $0.name == f.name } }.map { "\($0.name) \(equalOrApprox($0.value))" }
        let exact = answers.map(\.line).joined(separator: ", ")
        let decimals = answers.contains { !$0.line.contains("≈") && $0.line != "\($0.name) = \(decimal($0.value))" }
        let taking = "Taking " + (given + along + (constants.isEmpty ? [] : [Constants.values(constants)])).joined(separator: ", ")
        let solution = Solution(exact: exact, approx: decimals ? "≈ " + answers.map { decimal($0.value) }.joined(separator: ", ") : taking)
        let header = Math.row(equations.enumerated().flatMap { i, e in (i == 0 ? [] : [t(",   ")]) + [written(e)] })
        let details = Details(name: answers.map(\.name).joined(separator: ", "), equation: header, steps: steps,
                              solutions: found.map { t($0.line) }, note: nil, f: { _ in .nan }, roots: [])
        return Given(assignments: assignments, substituted: last, solution: solution, details: details,
                     found: answers.map(\.value), given: given)
    }

    // The equation with each given letter replaced by its number, wherever the letter stands by
    // itself or as one of several run together, at in v = u + at.
    static func write(_ assignments: [(name: String, value: Double)], _ marked: [String: String], into equation: String) -> String? {
        // 30° and π/6 go in as they were typed, so that a sine finds its unit in them.
        func written(_ a: (name: String, value: Double)) -> String { "(\(marked[a.name] ?? String(format: "%.15g", a.value)))" }
        // Replace whole declared names before splitting implicit products: N_A is not N
        // followed by a suffix, and omega_i is the same symbol as ω_i.
        var equation = equation
        for a in assignments.sorted(by: { $0.name.count > $1.name.count }) where a.name.count > 1 {
            var aliases = [a.name]
            let pieces = a.name.split(separator: "_", maxSplits: 1).map(String.init)
            if let first = pieces.first {
                for (word, symbol) in Greek.names where symbol == first { aliases.append(([word] + pieces.dropFirst()).joined(separator: "_")) }
                if first.hasPrefix("Δ"), first.count > 1 {
                    for (word, symbol) in Greek.names where symbol == String(first.dropFirst()) { aliases.append((["Δ" + word] + pieces.dropFirst()).joined(separator: "_")) }
                }
            }
            for alias in aliases {
                let pattern = "(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: alias) + "(?![\\p{L}\\p{N}_])"
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                equation = regex.stringByReplacingMatches(in: equation, range: NSRange(equation.startIndex..., in: equation), withTemplate: written(a))
            }
        }
        var out = ""
        var run = ""
        func flush() -> Bool {
            guard !run.isEmpty else { return true }
            defer { run = "" }
            if let a = assignments.first(where: { $0.name == Greek.identifier(run) }) { out += written(a); return true }
            guard let (tokens, _) = try? Parser.splitLetters(run) else { out += run; return true }
            var rebuilt = ""
            for token in tokens {
                switch token {
                case .letter(let s):
                    if let a = assignments.first(where: { $0.name == s }) { rebuilt += written(a) } else { rebuilt += s }
                case .function(let f): rebuilt += f
                case .constant: rebuilt += "pi"
                case .symbol(let c): rebuilt += c == "°" ? "deg" : c == "㎭" ? "rad" : String(c)
                default: out += run; return true
                }
            }
            out += rebuilt
            return true
        }
        var chars = Array(equation)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isLetter, c.isASCII { run.append(c); i += 1; continue }
            // f_s with f given: the f is the first letter of the name f_s, and no f of its own. The
            // letter before the _ is kept back from the run, and the name written whole.
            if c == "_", let last = run.last {
                run.removeLast()
                _ = flush()
                var j = i + 1
                let digits = j < chars.count && chars[j].isNumber
                while j < chars.count, chars[j].isASCII, digits ? chars[j].isNumber : chars[j].isLetter { j += 1 }
                let name = String(last) + String(chars[i..<j])
                out += assignments.first(where: { $0.name == name }).map(written) ?? name
                i = j
                continue
            }
            _ = flush()
            // θ typed as itself, not spelt.
            if Greek.symbols.contains(c), i + 1 == chars.count || chars[i + 1] != "_", let a = assignments.first(where: { $0.name == String(c) }) {
                out += written(a)
                i += 1
                continue
            }
            // A name with a subscript, F_n, is one letter. The subscript is all digits or all
            // letters, as the parser reads it, so that kq_1q_2 is k, q_1 and q_2.
            if c == "_" {
                var j = i + 1
                let digits = j < chars.count && chars[j].isNumber
                while j < chars.count, chars[j].isASCII, digits ? chars[j].isNumber : chars[j].isLetter { j += 1 }
                let name = (out.last.map(String.init) ?? "") + String(chars[i..<j])
                if let a = assignments.first(where: { $0.name == name }), out.last?.isLetter == true {
                    out.removeLast()
                    out += written(a)
                } else { out += String(chars[i..<j]) }
                i = j
                continue
            }
            out.append(c)
            i += 1
        }
        _ = flush()
        chars = []
        return out
    }

    // The letters that stand inside a sine, a cosine or a tangent, and so are angles.
    private static func angles(in equation: String) -> Set<String> {
        guard let tokens = try? Parser.tokenize(equation) else { return [] }
        var letters: [String] = []
        for token in tokens { if case .letter(let s) = token, !letters.contains(s) { letters.append(s) } }
        var state = Parser.State(tokens: tokens, unknown: "", bound: letters)
        guard let left = try? state.expression(), state.take("="), let right = try? state.expression() else { return [] }
        func inside(_ e: Expr, _ angle: Bool) -> Set<String> {
            switch e {
            case .index(let k): return angle ? [k] : []
            case .num, .unknown, .constant: return []
            case .neg(let a): return inside(a, angle)
            case .call(let f, let a): return inside(a, angle || Angle.functions.contains(f.hasSuffix("°") ? String(f.dropLast()) : f))
            case .op(_, let a, let b): return inside(a, angle).union(inside(b, angle))
            case .apply(_, let args): return args.reduce([]) { $0.union(inside($1, angle)) }
            case .sum(_, let from, let to, let body, _): return inside(from, angle).union(inside(to, angle)).union(inside(body, angle))
            }
        }
        return inside(left, false).union(inside(right, false))
    }

    var values: [Double] { found ?? Solver.values(substituted) }
    // What was typed, as it was understood: the formula, then the values given to it.
    var interpretation: Math? { details.map { row($0.equation, t(",   " + given.joined(separator: ",   "))) } }
    var copyText: String? { found.map { $0.map { String(format: "%.12g", $0) }.joined(separator: ", ") } ?? Solver.copy(substituted) }
}
