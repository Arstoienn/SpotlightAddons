import Foundation

// An expression with one equation beside it that settles a letter in it: C(11,4)x⁷k⁴, 330k⁴ = 1320, as a
// binomial question gives the coefficient of x⁷ and asks for k. The equation is the question: it is
// solved, and each value it gives is put into the expression, which is then worked out as far as it
// goes (1320x⁷). Where a value is given as a number, k = 2, it is values given to a formula (Given) and
// not this; where there are two equations, it is a system.
struct Conditioned {
    let unknown: String
    let roots: [Double]
    let equation: Details           // the equation solved
    let expressions: [String]       // as typed, each with the letter in it
    let results: [[(root: Double, value: Math)]]   // each expression with each value put in

    static func parse(_ input: String) -> Conditioned? {
        let parts = LinearSystem.parts(input).map { $0.trimmingCharacters(in: .whitespaces) }
        let equations = parts.filter { $0.contains("=") }, expressions = parts.filter { !$0.contains("=") && !$0.isEmpty }
        guard parts.count >= 2, equations.count == 1, !expressions.isEmpty, !equations[0].contains("?"),
              let solved = Solver.details(equations[0]), !solved.roots.isEmpty, solved.roots.count <= 6,
              solved.name.count == 1 || solved.name.count == 2 else { return nil }
        let unknown = solved.name
        // The letter must be in every expression, or the equation says nothing about them.
        guard expressions.allSatisfy({ mentions($0, unknown) }) else { return nil }
        let roots = solved.roots.map { abs($0) < 1e-12 ? 0 : $0 }
        var results: [[(root: Double, value: Math)]] = []
        for expression in expressions {
            var row: [(root: Double, value: Math)] = []
            for root in roots {
                guard let given = Given.parse("\(expression), \(unknown) = \(String(format: "%.15g", root))"),
                      let value = given.details?.solutions.first else { return nil }
                row.append((root, value))
            }
            results.append(row)
        }
        return Conditioned(unknown: unknown, roots: roots, equation: solved, expressions: expressions, results: results)
    }

    private static func mentions(_ expression: String, _ letter: String) -> Bool {
        guard let tokens = try? Parser.tokenize(expression) else { return false }
        return tokens.contains(.letter(letter))
    }

    // k = ±√2, or k = −1, 3: exactly where that is sure.
    var answer: Math {
        let shown = roots.map(closedForm)
        if roots.count == 2, abs(roots[0] + roots[1]) < 1e-12 * max(1, abs(roots[0])), roots[0] != 0 {
            return row(t("\(unknown) = ±"), closedForm(abs(roots[0])))
        }
        var parts: [Math] = [t("\(unknown) = ")]
        for (i, m) in shown.enumerated() { if i > 0 { parts.append(t(", ")) }; parts.append(m) }
        return .row(parts)
    }

    // Each expression's value: one, where every value of the letter gives the same.
    private func value(_ i: Int) -> Math {
        let row_ = results[i]
        if Set(row_.map(\.value.plain)).count == 1 { return bare(row_[0].value) }
        var parts: [Math] = []
        for (k, r) in row_.enumerated() {
            if k > 0 { parts.append(t(";  ")) }
            parts.append(row(t("\(unknown) = "), closedForm(r.root), t(" gives "), bare(r.value)))
        }
        return .row(parts)
    }

    // A value without the = Given writes before it.
    private func bare(_ m: Math) -> Math {
        if case .row(let parts) = m, case .text(let first)? = parts.first, first.hasPrefix("= ") {
            let rest = String(first.dropFirst(2))
            return .row((rest.isEmpty ? [] : [t(rest)]) + parts.dropFirst())
        }
        if case .text(let text) = m, text.hasPrefix("= ") { return t(String(text.dropFirst(2))) }
        return m
    }

    var solution: Solution {
        Solution(exact: answer.plain, approx: "Hence " + expressions.indices.map { value($0).plain }.joined(separator: "; "))
    }

    var details: Details {
        var d = equation
        d.equation = row(.row(expressions.flatMap { [typesetted($0), t(",   ")] }), equation.equation)
        // The equation's working, then each value put into the expression.
        let first = roots.first.map(closedForm) ?? t("")
        for (i, expression) in expressions.enumerated() {
            let shown = roots.count == 1 ? row(t("\(unknown) = "), first) : answer
            d.steps.append(Step(label: "Substituting " + shown.plain + " into " + typesetted(expression).plain, math: value(i)))
        }
        // The letter, then each expression with what it comes to: C(11, 4)x⁷k⁴ = 1320x⁷.
        d.solutions = [answer] + expressions.indices.map { i in
            Set(results[i].map(\.value.plain)).count == 1 ? row(typesetted(expressions[i]), t(" = "), value(i)) : value(i)
        }
        d.title = "Solutions"
        d.graph = equation.graph
        return d
    }

    // The expression as it is printed, its letters as letters.
    private func typesetted(_ expression: String) -> Math {
        guard let tokens = try? Parser.tokenize(expression) else { return t(expression) }
        let letters = tokens.reduce(into: [String]()) { if case .letter(let l) = $1, !$0.contains(l) { $0.append(l) } }
        var state = Parser.State(tokens: tokens, unknown: "", bound: letters)
        guard let expr = try? state.expression(), state.at == tokens.count else { return t(expression) }
        return typeset(expr, "")
    }

    var copyText: String { roots.map { String(format: "%.12g", $0) }.joined(separator: ", ") }
}
