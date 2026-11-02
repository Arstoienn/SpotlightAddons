import Foundation

// A formula with some of its letters given: v = u + at, u = 2, a = 3, t = 4. What is given is
// written into the formula, and what is left is solved.
struct Given {
    var assignments: [(name: String, value: Double)]
    var substituted: String       // the equation with the numbers written in
    var solution: Solution
    var details: Details?

    static func parse(_ input: String) -> Given? {
        let parts = LinearSystem.parts(input)
        guard parts.count >= 2 else { return nil }
        var assignments: [(name: String, value: Double)] = []
        var marked: [String: String] = [:]   // what 30° and π/6 are written in as, the unit kept
        var equations: [String] = []
        for part in parts {
            let sides = part.split(separator: "=", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard sides.count == 2 else { return nil }
            if sides[0].range(of: "^[A-Za-zα-ωθ][A-Za-z0-9]*(_[A-Za-z0-9]+)?$", options: .regularExpression) != nil,
               let value = (try? Parser.constant(sides[1], physical: true))?.eval(0), value.isFinite,
               sides[1].contains(where: { $0.isNumber }) || sides[1].contains("pi") || sides[1].contains("π") {
                // theta = 30 gives the θ of the equation.
                let name = Greek.names[sides[0]] ?? sides[0]
                assignments.append((name, value))
                if sides[1].range(of: "°|deg|rad|pi|π", options: .regularExpression) != nil { marked[name] = sides[1] }
            } else {
                equations.append(part)
            }
        }
        guard !assignments.isEmpty, equations.count == 1, let equation = equations.first else { return nil }
        guard let rewritten = write(assignments, marked, into: equation), rewritten != equation, let solution = Solver.solve(rewritten) else { return nil }
        var d = Solver.details(rewritten)
        // An angle is given with its unit: θ = 30° as it was typed, and θ = 30 in what the
        // settings take a sine's angle in, rad unless it is degrees.
        let angles = angles(in: equation)
        let taking = assignments.map { a in
            if let typed = marked[a.name] { return "\(a.name) = " + typed.replacingOccurrences(of: "pi", with: "π")
                    .replacingOccurrences(of: "(?<=[0-9.])\\s*rad", with: " rad", options: .regularExpression)
                    .replacingOccurrences(of: "(?<=[0-9.])\\s*deg", with: "°", options: .regularExpression) }
            return "\(a.name) = \(decimal(a.value))" + (angles.contains(a.name) ? (Options.degrees ? "°" : " rad") : "")
        }.joined(separator: ", ")
        d?.steps.insert(Step(label: "Substituting \(taking)", math: t(rewritten)), at: 0)
        d?.equation = t(equation)
        var shown = solution
        // What was given, with what a constant was taken for, if it was: Taking L = 1, g = 9.8 m s⁻².
        if shown.approx == nil { shown.approx = "Taking " + taking }
        else if let known = shown.approx, known.hasPrefix("Taking ") { shown.approx = "Taking \(taking), \(known.dropFirst("Taking ".count))" }
        return Given(assignments: assignments, substituted: rewritten, solution: shown, details: d)
    }

    // The equation with each given letter replaced by its number, wherever the letter stands by
    // itself or as one of several run together, at in v = u + at.
    private static func write(_ assignments: [(name: String, value: Double)], _ marked: [String: String], into equation: String) -> String? {
        // 30° and π/6 go in as they were typed, so that a sine finds its unit in them.
        func written(_ a: (name: String, value: Double)) -> String { "(\(marked[a.name] ?? String(format: "%.15g", a.value)))" }
        var out = ""
        var run = ""
        func flush() -> Bool {
            guard !run.isEmpty else { return true }
            defer { run = "" }
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
            _ = flush()
            // θ typed as itself, not spelt.
            if Greek.symbols.contains(c), i + 1 == chars.count || chars[i + 1] != "_", let a = assignments.first(where: { $0.name == String(c) }) {
                out += written(a)
                i += 1
                continue
            }
            // A name with a subscript, F_n, is one letter.
            if c == "_" {
                var j = i + 1
                while j < chars.count, chars[j].isLetter || chars[j].isNumber { j += 1 }
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

    var values: [Double] { Solver.values(substituted) }
    var copyText: String? { Solver.copy(substituted) }
}
