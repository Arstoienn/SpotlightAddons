import Foundation

// Two or three linear equations in x, y (and z) whose coefficients are other letters:
// ax + by = 1, bx + ay = 2. Solved by Cramer's rule, the determinants worked in those letters:
// x = (a − 2b)/(a² − b²), y = (2a − b)/(a² − b²), where a² − b² ≠ 0.
struct LetterSystem {
    typealias Polynomial = [Simplification.Term]
    var unknowns: [String]
    var letters: [String]                   // the coefficients' letters, a and b
    var matrix: [[Polynomial]]              // coefficients of the unknowns, one row per equation
    var right: [Polynomial]                 // the right-hand sides
    var determinant: Polynomial
    var numerators: [Polynomial]            // D_x, D_y, D_z
    var header: Math

    static func parse(_ input: String) -> LetterSystem? {
        let parts = LinearSystem.parts(input)
        guard (2...3).contains(parts.count) else { return nil }
        var all: [String] = []
        var sides: [(Expr, Expr)] = []
        for part in parts {
            guard let tokens = try? Parser.tokenize(part), tokens.filter({ $0 == .symbol("=") }).count == 1 else { return nil }
            for token in tokens { if case .letter(let s) = token, !all.contains(s) { all.append(s) } }
            sides.append((.num(0), .num(0)))
        }
        let unknowns = ["x", "y", "z"].filter(all.contains)
        let letters = all.filter { !unknowns.contains($0) && $0 != "e" }
        guard unknowns.count == parts.count, !letters.isEmpty else { return nil }
        var matrix: [[Polynomial]] = [], right: [Polynomial] = []
        var shown: [Math] = []
        for part in parts {
            guard let tokens = try? Parser.tokenize(part) else { return nil }
            var state = Parser.State(tokens: tokens, unknown: "", bound: all)
            guard let l = try? state.expression(), state.take("="), let r = try? state.expression(), state.at == tokens.count,
                  let terms = Simplification.collected(.op("-", l, r)) else { return nil }
            shown.append(row(typeset(l, ""), t(" = "), typeset(r, "")))
            // Each term has at most one unknown, to the first power: linear in the unknowns.
            var row = Array(repeating: Polynomial(), count: unknowns.count), constant = Polynomial()
            for term in terms {
                let inThis = unknowns.filter { term.powers[$0] != nil }
                guard inThis.count <= 1, inThis.allSatisfy({ term.powers[$0] == 1 }) else { return nil }
                let rest: Simplification.Term = (term.coefficient, term.powers.filter { !unknowns.contains($0.key) })
                if let u = inThis.first, let i = unknowns.firstIndex(of: u) { row[i].append(rest) } else { constant.append((-rest.coefficient, rest.powers)) }
            }
            matrix.append(row.map { Simplification.sum($0) })
            right.append(Simplification.sum(constant))
        }
        // The coefficients must have a letter in them somewhere; plain numbers are LinearSystem's.
        guard matrix.joined().contains(where: { $0.contains { !$0.powers.isEmpty } }) else { return nil }
        guard let d = determinant(matrix), !d.isEmpty else { return nil }
        var numerators: [Polynomial] = []
        for i in unknowns.indices {
            var replaced = matrix
            for r in replaced.indices { replaced[r][i] = right[r] }
            guard let n = determinant(replaced) else { return nil }
            numerators.append(n)
        }
        let header = Math.row(shown.enumerated().flatMap { i, m in (i == 0 ? [] : [t(",   ")]) + [m] })
        return LetterSystem(unknowns: unknowns, letters: letters, matrix: matrix, right: right, determinant: d, numerators: numerators, header: header)
    }

    // By the first row: two by two and three by three.
    static func determinant(_ m: [[Polynomial]]) -> Polynomial? {
        func times(_ a: Polynomial, _ b: Polynomial) -> Polynomial? { Simplification.product(a, b) }
        if m.count == 2 {
            guard let ad = times(m[0][0], m[1][1]), let bc = times(m[0][1], m[1][0]) else { return nil }
            return Simplification.sum(ad + bc.map { (-$0.coefficient, $0.powers) })
        }
        guard m.count == 3 else { return nil }
        var total = Polynomial()
        for j in 0..<3 {
            let minor = [1, 2].map { r in (0..<3).filter { $0 != j }.map { m[r][$0] } }
            guard let d = determinant(minor), let term = times(m[0][j], d) else { return nil }
            total += j == 1 ? term.map { (-$0.coefficient, $0.powers) } : term
        }
        return Simplification.sum(total)
    }

    private var writer: Simplification { Simplification(expr: .num(0), letters: letters, terms: []) }

    // The highest power first: a² − 2a + 1.
    private func ordered(_ p: Polynomial) -> Polynomial {
        p.sorted { a, b in
            let (da, db) = (a.powers.values.reduce(0, +), b.powers.values.reduce(0, +))
            if da != db { return da > db }
            for letter in letters where a.powers[letter] != b.powers[letter] { return (a.powers[letter] ?? 0) > (b.powers[letter] ?? 0) }
            return false
        }
    }

    // D with its first term positive.
    private var positive: Polynomial {
        let d = ordered(determinant)
        return d.first.map { $0.coefficient < 0 } == true ? d.map { (-$0.coefficient, $0.powers) } : d
    }

    // In one letter, a factor the top and the bottom share cancels: (a − 1)²/((a − 1)²(a + 2)) is 1/(a + 2).
    private func cancelled(_ top: Polynomial, _ bottom: Polynomial) -> (Polynomial, Polynomial) {
        guard letters.count == 1, let a = letters.first else { return (top, bottom) }
        func coefficients(_ p: Polynomial) -> [Double]? {
            var out: [Double] = []
            for term in p {
                guard term.coefficient.isExact, let k = term.powers[a] ?? Optional(0), k >= 0, term.powers.count <= 1 else { return nil }
                if out.count <= k { out += Array(repeating: 0, count: k + 1 - out.count) }
                out[k] += term.coefficient.double
            }
            return trim(out)
        }
        func divide(_ n: [Double], _ d: [Double]) -> (q: [Double], r: [Double]) {
            var r = n, q = Array(repeating: 0.0, count: max(n.count - d.count + 1, 1))
            while r.count >= d.count, let lead = r.last, abs(lead) > 1e-9 {
                let shift = r.count - d.count, k = lead / d.last!
                q[shift] = k
                for (i, c) in d.enumerated() { r[i + shift] -= k * c }
                r = trim(r.map { abs($0) < 1e-9 ? 0 : $0 })
                if r.count == 1, abs(r[0]) < 1e-9 { r = [] }
            }
            return (q, r)
        }
        guard let n = coefficients(top), let d = coefficients(bottom), n.count > 1 || d.count > 1 else { return (top, bottom) }
        var (x, y) = (n, d)
        while !y.isEmpty, !(y.count == 1 && abs(y[0]) < 1e-9) { (x, y) = (y, divide(x, y).r) }
        guard x.count > 1 else { return (top, bottom) }
        let (q1, r1) = divide(n, x), (q2, r2) = divide(d, x)
        guard r1.isEmpty, r2.isEmpty else { return (top, bottom) }
        // Back to terms, the bottom's leading coefficient made 1 where the top's are then whole.
        let lead = q2.last ?? 1
        func back(_ c: [Double]) -> Polynomial {
            c.enumerated().compactMap { k, v in abs(v) < 1e-12 ? nil : (Number((v / lead * 1e9).rounded() / 1e9), k == 0 ? [:] : [a: k]) }
        }
        return (back(q1), back(q2))
    }

    // D_x/D, cancelled where it can be, with D's first term positive, and a D that is a number divided through.
    private func quotient(_ i: Int) -> Math {
        var top = numerators[i], bottom = determinant
        if let first = ordered(bottom).first, first.coefficient < 0 {
            top = top.map { (-$0.coefficient, $0.powers) }
            bottom = bottom.map { (-$0.coefficient, $0.powers) }
        }
        (top, bottom) = cancelled(top, bottom)
        (top, bottom) = (ordered(top), ordered(bottom))
        if top.isEmpty { return t("0") }
        if bottom.count == 1, bottom[0].powers.isEmpty {
            let k = bottom[0].coefficient
            return writer.math(top.map { ($0.coefficient / k, $0.powers) })
        }
        return .fraction(writer.math(top), writer.math(bottom))
    }

    var condition: String { writer.math(positive).plain + " ≠ 0" }

    var solution: Solution {
        let answers = unknowns.indices.map { "\(unknowns[$0]) = " + quotient($0).plain }
        return Solution(exact: answers.joined(separator: ", "), approx: "Where " + condition)
    }

    var details: Details {
        var steps: [Step] = []
        let names = unknowns.map { "D_\($0)" }
        steps.append(Step(label: "Finding the determinant of the coefficients", math: row(t("D = "), writer.math(ordered(determinant)))))
        for (i, u) in unknowns.enumerated() {
            steps.append(Step(label: "Replacing the \(u) column by the right-hand side", math: row(t("\(names[i]) = "), writer.math(ordered(numerators[i])))))
        }
        for (i, u) in unknowns.enumerated() {
            steps.append(Step(label: i == 0 ? "By Cramer's rule" : "Likewise", math: row(t("\(u) = \(names[i])/D = "), quotient(i))))
        }
        return Details(name: unknowns.joined(separator: ", "), equation: header, steps: steps,
                       solutions: unknowns.indices.map { row(t("\(unknowns[$0]) = "), quotient($0)) },
                       note: "These hold where \(condition); where D = 0 there is no single solution.", f: { _ in .nan }, roots: [])
    }
}
