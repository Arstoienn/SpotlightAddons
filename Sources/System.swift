import Foundation

// Several equations at once, separated by commas or semicolons: "2x+y=5, x-y=1". Linear ones are
// solved together, by elimination, the way it is done by hand; with two unknowns (or one) they
// are drawn as lines in the plane, crossing at the answer.

struct LinearSystem {
    var variables: [String]          // sorted: x before y
    var equations: [(left: Expr, right: Expr)]
    var rows: [[Double]]             // each equation as a₁x + a₂y + … = c: [a₁, a₂, …, c]

    // Splits at commas and semicolons outside brackets, so sum(k,1,3,k) stays whole.
    static func parts(_ input: String) -> [String] {
        var parts: [String] = [], current = "", depth = 0
        for c in input {
            if c == "(" { depth += 1 }
            if c == ")" { depth -= 1 }
            if depth == 0, c == "," || c == ";" {
                parts.append(current)
                current = ""
            } else {
                current.append(c)
            }
        }
        parts.append(current)
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    // The equations of a system and its unknowns, linear or not.
    static func read(_ input: String) -> (variables: [String], equations: [(left: Expr, right: Expr)])? {
        let texts = parts(input)
        guard texts.count >= 2, texts.count <= 4, texts.allSatisfy({ $0.filter { $0 == "=" }.count == 1 }) else { return nil }
        guard let tokenized = try? texts.map(Parser.tokenize) else { return nil }

        let all = tokenized.flatMap { $0 }
        var letters = Set(all.compactMap { if case .letter(let s) = $0 { s } else { nil } }).subtracting(Parser.indices(all))
        if letters.count > 1 { letters.remove("e") }
        guard !letters.isEmpty, letters.count <= 4 else { return nil }
        let variables = letters.sorted()

        var equations: [(left: Expr, right: Expr)] = []
        for tokens in tokenized {
            let tokens = tokens.map { $0 == .letter("e") && !letters.contains("e") ? .constant(M_E) : $0 }
            var p = Parser.State(tokens: tokens, unknown: "", bound: variables)
            guard let left = try? p.expression(), p.take("="), let right = try? p.expression(), p.at == tokens.count
            else { return nil }
            equations.append((left, right))
        }
        return (variables, equations)
    }

    static func parse(_ input: String) -> LinearSystem? {
        guard let (variables, equations) = read(input) else { return nil }

        // Linear means: the left side minus the right is a constant plus a multiple of each
        // unknown. Read the coefficients off at zero and at each unit point, then check them
        // against a few other points.
        var rows: [[Double]] = []
        for (left, right) in equations {
            func f(_ values: [Double]) -> Double {
                let env = Dictionary(uniqueKeysWithValues: zip(variables, values))
                return left.eval(0, env) - right.eval(0, env)
            }
            let zero = Array(repeating: 0.0, count: variables.count)
            let c0 = f(zero)
            let coefficients = variables.indices.map { i -> Double in
                var unit = zero
                unit[i] = 1
                return f(unit) - c0
            }
            for probe in [[1.7, -2.3, 0.6, 3.1], [-4.2, 0.9, 2.5, -1.4], [3.3, 5.1, -0.7, 2.2]] {
                let point = Array(probe.prefix(variables.count))
                let predicted = c0 + zip(coefficients, point).map(*).reduce(0, +)
                guard abs(f(point) - predicted) <= 1e-9 * max(1, abs(predicted)) else { return nil }
            }
            guard c0.isFinite, coefficients.allSatisfy(\.isFinite) else { return nil }
            rows.append(coefficients + [-c0])
        }
        return LinearSystem(variables: variables, equations: equations, rows: rows)
    }

    enum Outcome {
        case unique([Double])
        case none
        case infinite
    }

    // Gaussian elimination with partial pivoting; the ranks of the coefficients and of the whole
    // rows tell no solution and infinitely many apart.
    var outcome: Outcome {
        var m = rows
        let n = variables.count
        var rank = 0
        var pivots: [Int] = []
        for col in 0..<n where rank < m.count {
            guard let p = (rank..<m.count).max(by: { abs(m[$0][col]) < abs(m[$1][col]) }), abs(m[p][col]) > 1e-12 else { continue }
            m.swapAt(rank, p)
            for r in 0..<m.count where r != rank {
                let k = m[r][col] / m[rank][col]
                for c in col...n { m[r][c] -= k * m[rank][c] }
            }
            pivots.append(col)
            rank += 1
        }
        let scale = rows.flatMap { $0 }.map(abs).max() ?? 1
        for r in rank..<m.count where abs(m[r][n]) > 1e-9 * max(1, scale) { return .none }
        guard rank == n else { return .infinite }
        var values = Array(repeating: 0.0, count: n)
        for (r, col) in pivots.enumerated() { values[col] = m[r][n] / m[r][col] }
        return .unique(values.map { abs($0) < 1e-12 ? 0 : $0 })
    }

    var solution: Solution {
        switch outcome {
        case .none:
            return Solution(exact: "No solution", approx: variables.count <= 2 ? "The lines are parallel and do not intersect." : "The equations are inconsistent.")
        case .infinite:
            return Solution(exact: "Infinitely many solutions", approx: variables.count <= 2 ? "The equations represent the same line." : nil)
        case .unique(let values):
            let exact = zip(variables, values).map { "\($0) = \(exactText($1))" }.joined(separator: ", ")
            let needsApprox = values.contains { abs($0 - $0.rounded()) > 1e-9 }
            return Solution(exact: exact, approx: needsApprox ? "≈ " + values.map(decimal).joined(separator: ", ") : nil)
        }
    }
}

// 2/3 for a simple fraction, the decimal otherwise.
func exactText(_ v: Double) -> String {
    if abs(v - v.rounded()) < 1e-9 { return decimal(v) }
    if let (p, q) = rational(v), q <= 1000 { return fraction(p, q) }
    return decimal(v)
}

func exactMath(_ v: Double) -> Math {
    if abs(v - v.rounded()) > 1e-9, let (p, q) = rational(v), q <= 1000 { return fractionMath(p, q) }
    return t(decimal(v))
}

// MARK: - Working

extension LinearSystem {
    // Each equation tidied to a₁x + a₂y = c with whole numbers and no common factor.
    var integerRows: [[Int]]? {
        var out: [[Int]] = []
        for row in rows {
            guard var ints = integerCoefficients(row) else { return nil }
            if let lead = ints.dropLast().first(where: { $0 != 0 }), lead < 0 { ints = ints.map { -$0 } }
            out.append(ints)
        }
        return out
    }

    func standardForm(_ row: [Int]) -> Math {
        var parts: [Math] = []
        for (a, v) in zip(row.dropLast(), variables) where a != 0 {
            let sign = a < 0 ? (parts.isEmpty ? "−" : " − ") : (parts.isEmpty ? "" : " + ")
            parts.append(t(sign + (abs(a) == 1 ? "" : "\(abs(a))") + v))
        }
        if parts.isEmpty { parts.append(t("0")) }
        return .row(parts + [t(" = \(minus(row.last!))")])
    }

    var details: Details {
        let header = Math.row(equations.enumerated().flatMap { i, eq in
            (i == 0 ? [] : [t(",   ")]) + [typeset(eq.left, ""), t(" = "), typeset(eq.right, "")]
        })
        var d = Details(name: variables.joined(separator: ", "), equation: header, steps: [], solutions: [], note: nil,
                        f: { _ in .nan }, roots: [])
        let ints = integerRows

        if let ints {
            // Numbered, to be referred to; written out again only where that tidies them.
            for (i, r) in ints.enumerated() {
                let typed = row(typeset(equations[i].left, ""), t(" = "), typeset(equations[i].right, ""))
                let standard = standardForm(r)
                d.steps.append(Step(label: standard.plain == typed.plain ? "(\(i + 1))" : "Writing (\(i + 1)) in standard form", math: standard))
            }
        }
        if variables.count == 2, ints?.count == 2, let ints { d.steps += eliminationSteps(ints) }
        else if variables.count == 1, let ints {
            for (i, r) in ints.enumerated() where r[0] != 0 {
                d.steps.append(Step(label: "Solving (\(i + 1))", math: row(t("\(variables[0]) = "), fractionMath(r[1], r[0]))))
            }
        } else {
            d.steps.append(Step(label: "Solving by elimination", math: nil,
                                note: "Each unknown is eliminated in turn until a single unknown remains; the others then follow by back-substitution."))
        }

        switch outcome {
        case .unique(let values):
            d.solutions = zip(variables, values).map { v, x in
                exactMath(x).hasFraction ? row(t("\(v) = "), exactMath(x), t(" ≈ \(decimal(x))")) : row(t("\(v) = "), exactMath(x))
            }
        case .none:
            d.solutions = [t("No solution")]
            d.note = variables.count <= 2 ? "The lines are parallel and do not intersect." : "The equations are inconsistent."
        case .infinite:
            d.solutions = [t("Infinitely many solutions")]
            d.note = variables.count <= 2 ? "Both equations represent the same line." : nil
        }

        if variables.count <= 2 { d.graph = graph }
        return d
    }

    // Two equations in x and y: make the y terms match, subtract to lose y, solve for x, and put
    // x back into an equation that still has y in it.
    private func eliminationSteps(_ r: [[Int]]) -> [Step] {
        let (x, y) = (variables[0], variables[1])
        let (a1, b1, c1) = (r[0][0], r[0][1], r[0][2]), (a2, b2, c2) = (r[1][0], r[1][1], r[1][2])
        var steps: [Step] = []
        let det = a1 * b2 - a2 * b1
        guard det != 0 else {
            steps.append(Step(label: "Comparing the coefficients", math: t("\(paren(a1))·\(paren(b2)) − \(paren(a2))·\(paren(b1)) = 0"),
                              note: "The coefficients of \(x) and \(y) are in the same ratio in both equations; the lines therefore have the same gradient."))
            return steps
        }
        guard b1 != 0, b2 != 0 else {
            // One equation has no y: it gives x straight away.
            let (i, a, c) = b1 == 0 ? (1, a1, c1) : (2, a2, c2)
            if a != 1 { steps.append(Step(label: "Solving (\(i)) for \(x)", math: row(t("\(x) = "), fractionMath(c, a)))) }
            return steps + substitution(into: b1 == 0 ? 2 : 1, x: Double(c) / Double(a), r)
        }
        // Multiply so the y terms match, the smallest way: (1) × b₂/g and (2) × b₁/g.
        let g = gcd(b1, b2)
        var (m1, m2) = (b2 / g, b1 / g)
        if m1 < 0 { (m1, m2) = (-m1, -m2) }
        func times(_ eq: Int, _ m: Int) -> String { m == 1 ? "(\(eq))" : "(\(eq)) × \(m)" }
        let label = "Eliminating \(y): \(times(1, m1)) \(m2 < 0 ? "+" : "−") \(times(2, abs(m2)))"
        let ax = a1 * m1 - a2 * m2, c = c1 * m1 - c2 * m2
        steps.append(Step(label: label, math: t("\(ax == 1 ? "" : ax == -1 ? "−" : "\(ax)")\(x) = \(minus(c))")))
        steps.append(Step(label: "Hence", math: row(t("\(x) = "), fractionMath(c, ax))))
        return steps + substitution(into: 1, x: Double(c) / Double(ax), r)
    }

    // x written into the equation in place of its letter, "2·2 + y = 5", then y worked out.
    private func substitution(into eq: Int, x: Double, _ r: [[Int]]) -> [Step] {
        let (xName, y) = (variables[0], variables[1])
        let (a, b, c) = (r[eq - 1][0], r[eq - 1][1], r[eq - 1][2])
        // An equation with no x in it has nothing to substitute; it already says y, or nearly.
        if a == 0 {
            return b == 1 ? [] : [Step(label: "Solving (\(eq)) for \(y)", math: row(t("\(y) = "), fractionMath(c, b)))]
        }
        let value = exactMath(x)
        let xMath = x < 0 || value.hasFraction ? row(t("("), value, t(")")) : value
        var parts: [Math] = []
        if a != 0 { parts += [t(a == 1 ? "" : a == -1 ? "−" : "\(a)·"), xMath] }
        let bText = abs(b) == 1 ? "" : "\(abs(b))"
        parts.append(t(parts.isEmpty ? (b < 0 ? "−\(bText)\(y)" : "\(bText)\(y)") : (b < 0 ? " − \(bText)\(y)" : " + \(bText)\(y)")))
        parts.append(t(" = \(minus(c))"))
        return [Step(label: "Substituting \(xName) = \(exactText(x)) into (\(eq))", math: .row(parts)),
                Step(label: "Hence", math: row(t("\(y) = "), exactMath((Double(c) - Double(a) * x) / Double(b))))]
    }

    // Each equation a line in the plane of the two unknowns (with y as the other axis when there
    // is only one): y as a function of x where it has a y term, a vertical line where it has not.
    var graph: Graph {
        let xName = variables[0], yName = variables.count > 1 ? variables[1] : "y"
        var curves: [Graph.Curve] = []
        for (i, row) in rows.enumerated() {
            let a = row[0], b = variables.count > 1 ? row[1] : 0, c = row.last!
            let label = row.count == (variables.count + 1) ? (integerRows.map { standardForm($0[i]) } ?? typeset(equations[i].left, "")) : t("")
            if b != 0 {
                curves.append(Graph.Curve(shape: .function { (c - a * $0) / b }, label: label))
            } else if a != 0 {
                curves.append(Graph.Curve(shape: .vertical(c / a), label: label))
            }
        }
        var points: [CGPoint] = []
        if variables.count == 2, case .unique(let v) = outcome { points = [CGPoint(x: v[0], y: v[1])] }
        return Graph(xName: xName, yName: yName, curves: curves, points: points)
    }
}

// MARK: - Not linear

// x² + y² = 25, x + y = 7, or the symmetric x² + y + z = 3 and its kin: as many equations as
// unknowns, two or three of them, solved numerically. Newton's method is started from a grid of
// points round the origin; every answer it settles on is checked in every equation, and the
// same answer found twice is kept once. Values that are simple fractions or a + b√k are written
// that way.
struct NonlinearSystem {
    var variables: [String]
    var equations: [(left: Expr, right: Expr)]
    var solutions: [[Double]]

    static func parse(_ input: String) -> NonlinearSystem? {
        guard let (variables, equations) = LinearSystem.read(input), variables.count >= 2, variables.count <= 3,
              equations.count == variables.count else { return nil }
        var system = NonlinearSystem(variables: variables, equations: equations, solutions: [])
        system.solutions = system.solve()
        return system
    }

    func residuals(_ p: [Double]) -> [Double] {
        let env = Dictionary(uniqueKeysWithValues: zip(variables, p))
        return equations.map { $0.left.eval(0, env) - $0.right.eval(0, env) }
    }

    private func solve() -> [[Double]] {
        let n = variables.count
        let seeds: [Double] = n == 2 ? stride(from: -6.0, through: 6.0, by: 0.85).map { $0 + 0.13 } : [-5, -3, -1.7, -0.6, 0.45, 1.3, 2.6, 4.4]
        var starts: [[Double]] = [[]]
        for _ in 0..<n { starts = starts.flatMap { s in seeds.map { s + [$0] } } }

        var found: [[Double]] = []
        for start in starts {
            guard let p = newton(start) else { continue }
            if !found.contains(where: { zip($0, p).allSatisfy { abs($0 - $1) <= 1e-6 * max(1, abs($1)) } }) { found.append(p) }
        }
        return found.sorted { a, b in
            for (x, y) in zip(a, b) where abs(x - y) > 1e-9 { return x < y }
            return false
        }
    }

    // Damped Newton with a finite-difference Jacobian; nil if it wanders off or stalls.
    private func newton(_ start: [Double]) -> [Double]? {
        let n = variables.count
        var p = start
        func size(_ f: [Double]) -> Double { f.map(abs).max() ?? .infinity }
        for _ in 0..<60 {
            let f = residuals(p)
            guard f.allSatisfy(\.isFinite) else { return nil }
            if size(f) < 1e-13 { break }
            var jacobian = Array(repeating: Array(repeating: 0.0, count: n), count: n)
            for j in 0..<n {
                var q = p
                let h = 1e-7 * max(1, abs(p[j]))
                q[j] += h
                let g = residuals(q)
                for i in 0..<n { jacobian[i][j] = (g[i] - f[i]) / h }
            }
            guard let step = solveLinear(jacobian, f.map { -$0 }) else { return nil }
            var lambda = 1.0
            while lambda > 1e-3 {
                let q = zip(p, step).map { $0 + lambda * $1 }
                if size(residuals(q)) < size(f) { break }
                lambda /= 2
            }
            p = zip(p, step).map { $0 + lambda * $1 }
            if p.contains(where: { abs($0) > 1e6 }) { return nil }
            if step.map(abs).max()! * lambda < 1e-14 * (1 + p.map(abs).max()!) { break }
        }
        let scale = 1 + p.map(abs).max()!
        guard size(residuals(p)) < 1e-9 * scale else { return nil }
        return p.map { abs($0 - $0.rounded()) < 1e-10 ? $0.rounded() : $0 }
    }

    var solution: Solution {
        guard !solutions.isEmpty else {
            return Solution(exact: "No real solutions found", approx: "The search was conducted from numerous starting points about the origin.")
        }
        if solutions.count == 1 {
            let exact = zip(variables, solutions[0]).map { "\($0) = \(closedForm($1).plain)" }.joined(separator: ", ")
            let approx = solutions[0].contains { closedForm($0).plain != decimal($0) } ? "≈ " + solutions[0].map(decimal).joined(separator: ", ") : nil
            return Solution(exact: exact, approx: approx)
        }
        let tuples = solutions.prefix(2).map { "(" + $0.map { closedForm($0).plain }.joined(separator: ", ") + ")" }
        return Solution(exact: "(\(variables.joined(separator: ", "))) = " + tuples.joined(separator: ", ") + (solutions.count > 2 ? ", …" : ""),
                        approx: "\(solutions.count) real solutions")
    }

    var details: Details {
        let header = Math.row(equations.enumerated().flatMap { i, eq in
            (i == 0 ? [] : [t(",   ")]) + [typeset(eq.left, ""), t(" = "), typeset(eq.right, "")]
        })
        var d = Details(name: variables.joined(separator: ", "), equation: header, steps: [], solutions: [], note: nil,
                        f: { _ in .nan }, roots: [])
        for (i, eq) in equations.enumerated() {
            d.steps.append(Step(label: "(\(i + 1))", math: row(typeset(eq.left, ""), t(" = "), typeset(eq.right, ""))))
        }
        d.steps.append(Step(label: "Solving numerically", math: nil,
                            note: "The system is non-linear; Newton's method is therefore applied from numerous starting points about the origin, and each solution obtained is verified in every equation."))
        if solutions.isEmpty {
            d.solutions = [t("No real solutions found")]
        } else {
            d.solutions = solutions.map { values in
                var parts: [Math] = [t("(")]
                for (i, v) in values.enumerated() { parts += (i == 0 ? [] : [t(", ")]) + [closedForm(v)] }
                parts.append(t(")"))
                if values.contains(where: { closedForm($0).plain != decimal($0) }) {
                    parts.append(t(" ≈ (" + values.map(decimal).joined(separator: ", ") + ")"))
                }
                return .row(parts)
            }
            d.note = "Each solution is given as (\(variables.joined(separator: ", "))); \(solutions.count) real solution\(solutions.count == 1 ? " was" : "s were") found."
        }
        if variables.count == 2 {
            let curves = equations.enumerated().map { i, eq in
                Graph.Curve(shape: .implicit { x, y in
                    let env = [variables[0]: x, variables[1]: y]
                    return eq.left.eval(0, env) - eq.right.eval(0, env)
                }, label: row(typeset(eq.left, ""), t(" = "), typeset(eq.right, "")))
            }
            d.graph = Graph(xName: variables[0], yName: variables[1], curves: curves,
                            points: solutions.map { CGPoint(x: $0[0], y: $0[1]) })
        }
        return d
    }
}

// A value as a fraction, or as a + b√k, when it is one of those exactly enough to be sure;
// otherwise its decimal.
func closedForm(_ v: Double) -> Math {
    if abs(v - v.rounded()) < 1e-9 { return t(decimal(v)) }
    if let (p, q) = rational(v), q <= 100 { return fractionMath(p, q) }
    for k in [2, 3, 5, 6, 7, 10, 11, 13, 14, 15] {
        let root = Double(k).squareRoot()
        for den in [1, 2, 3, 4, 6] {
            for num in 1...12 {
                for b in [Double(num) / Double(den), -Double(num) / Double(den)] {
                    let a = v - b * root
                    guard let (ap, aq) = rational(a), aq <= 12, abs(ap) <= 200,
                          abs(Double(ap) / Double(aq) + b * root - v) < 1e-10 else { continue }
                    // Over a common denominator: (A ± B√k)/d.
                    let (bp, bq) = reduced(b < 0 ? -num : num, den)
                    let d = lcm(aq, bq)
                    let A = ap * (d / aq), B = bp * (d / bq)
                    let radical: Math = abs(B) == 1 ? .root(t("\(k)")) : row(t("\(abs(B))"), .root(t("\(k)")))
                    var top: [Math] = []
                    if A != 0 { top.append(t(minus(A))) }
                    top.append(t(A == 0 ? (B < 0 ? "−" : "") : (B < 0 ? " − " : " + ")))
                    top.append(radical)
                    return d == 1 ? .row(top) : .fraction(.row(top), t("\(d)"))
                }
            }
        }
    }
    return t(decimal(v))
}

// A·x = b by Gaussian elimination with partial pivoting; nil when A is (nearly) singular.
func solveLinear(_ a: [[Double]], _ b: [Double]) -> [Double]? {
    let n = b.count
    var m = zip(a, b).map { $0 + [$1] }
    for col in 0..<n {
        guard let p = (col..<n).max(by: { abs(m[$0][col]) < abs(m[$1][col]) }), abs(m[p][col]) > 1e-14 else { return nil }
        m.swapAt(col, p)
        for r in 0..<n where r != col {
            let k = m[r][col] / m[col][col]
            for c in col...n { m[r][c] -= k * m[col][c] }
        }
    }
    return (0..<n).map { m[$0][n] / m[$0][$0] }
}
