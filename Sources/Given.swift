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
        var equations: [String] = []
        for part in parts {
            let sides = part.split(separator: "=", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard sides.count == 2 else { return nil }
            if sides[0].range(of: "^[A-Za-zα-ωθ][A-Za-z0-9]*(_[A-Za-z0-9]+)?$", options: .regularExpression) != nil,
               let value = (try? Parser.constant(sides[1], physical: true))?.eval(0), value.isFinite,
               sides[1].contains(where: { $0.isNumber }) || sides[1].contains("pi") || sides[1].contains("π") {
                assignments.append((sides[0], value))
            } else {
                equations.append(part)
            }
        }
        guard !assignments.isEmpty, equations.count == 1, let equation = equations.first else { return nil }
        guard let rewritten = write(assignments, into: equation), rewritten != equation, let solution = Solver.solve(rewritten) else { return nil }
        var d = Solver.details(rewritten)
        let taking = assignments.map { "\($0.name) = \(decimal($0.value))" }.joined(separator: ", ")
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
    private static func write(_ assignments: [(name: String, value: Double)], into equation: String) -> String? {
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
                    if let a = assignments.first(where: { $0.name == s }) { rebuilt += "(\(String(format: "%.15g", a.value)))" } else { rebuilt += s }
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
            // A name with a subscript, F_n, is one letter.
            if c == "_" {
                var j = i + 1
                while j < chars.count, chars[j].isLetter || chars[j].isNumber { j += 1 }
                let name = (out.last.map(String.init) ?? "") + String(chars[i..<j])
                if let a = assignments.first(where: { $0.name == name }), out.last?.isLetter == true {
                    out.removeLast()
                    out += "(\(String(format: "%.15g", a.value)))"
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

    var values: [Double] { Solver.values(substituted) }
    var copyText: String? { Solver.copy(substituted) }
}
