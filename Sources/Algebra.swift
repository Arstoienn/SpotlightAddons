import Foundation

// Asked for by name, for what is typed with no = in it: expand((x+1)^2), factor(x^2-5x+6),
// derivative(x^3+2x), integrate(x^2, 0, 1), d/dx sin(x), ∫ x^2 dx. Each is worked in the one letter
// of the expression, or in several for expand.
struct Algebra {
    var solution: Solution
    var details: Details
    var copyText: String
    var values: [Double]
    // Calculus, a derivative, integral or limit, as against an expression multiplied out or
    // factorised: the card's sign is ƒ(x) for the one and ( ) for the other.
    var calculus = true

    private enum Kind { case expand, factor, derivative, integral, limit }

    private static func plain(_ s: String) -> String { s.replacingOccurrences(of: "−", with: "-") }

    static func parse(_ input: String) -> Algebra? {
        let (order, typed) = orderOfDerivative(input.trimmingCharacters(in: .whitespaces))
        guard let (kind, arguments, variable) = read(typed),
              let first = arguments.first, !first.isEmpty else { return nil }
        var rest = Array(arguments.dropFirst())
        // integrate(f, x, 0, 1): the letter may be named before the limits.
        var named = variable
        if let lone = rest.first, lone.range(of: "^[A-Za-z]$", options: .regularExpression) != nil, kind == .derivative || kind == .integral {
            named = lone
            rest.removeFirst()
        }
        guard var tokens = try? Parser.tokenize(first), !tokens.isEmpty else { return nil }
        let ks = Parser.indices(tokens)
        var letters: [String] = []
        for token in tokens { if case .letter(let s) = token, !letters.contains(s), !ks.contains(s) { letters.append(s) } }
        if kind == .limit { named = nil; rest = Array(arguments.dropFirst()) }
        if named == nil || named != "e" { tokens = tokens.map { $0 == .letter("e") && named != "e" ? .constant(M_E) : $0 } }
        letters.removeAll { $0 == "e" && named != "e" }
        switch kind {
        case .expand: return expand(tokens, letters).map { var a = $0; a.calculus = false; return a }
        case .factor: return factor(first, tokens, letters).map { var a = $0; a.calculus = false; return a }
        case .limit:
            // limit(f, x, a): the letter, then where it goes.
            guard rest.count == 2, rest[0].range(of: "^[A-Za-z]$", options: .regularExpression) != nil,
                  var state = Optional(Parser.State(tokens: tokens, unknown: rest[0], bound: letters.filter { $0 != rest[0] })),
                  let expr = try? state.expression(), state.at == tokens.count else { return nil }
            return limit(expr, rest[0], toward: rest[1])
        case .derivative, .integral:
            let name = named ?? (letters.contains("x") ? "x" : letters.count == 1 ? letters[0] : "x")
            guard letters.count <= 1 || letters.contains(name) else { return nil }
            // The other letters are constants of the differentiation: a in ax².
            var state = Parser.State(tokens: tokens, unknown: name, bound: letters.filter { $0 != name })
            guard let expr = try? state.expression(), state.at == tokens.count else { return nil }
            return kind == .derivative ? derivative(expr, name, point: rest.first, order: order) : integral(expr, name, limits: rest)
        }
    }

    // d2/dx2 f, d^2/dx^2 f, second derivative of f: the order of the derivative, and the same in the
    // first-order form it is read in.
    private static func orderOfDerivative(_ s: String) -> (Int, String) {
        if let m = s.range(of: "^d\\^?\\{?(\\d+)\\}?\\s*/\\s*d([A-Za-z])\\^?\\{?\\1\\}?", options: .regularExpression) {
            let head = String(s[m])
            let digits = head.dropFirst().prefix { $0.isNumber || $0 == "^" || $0 == "{" }.filter(\.isNumber)
            let v = head.last { $0.isLetter }!
            return (Int(digits) ?? 1, "d/d\(v)" + s[m.upperBound...])
        }
        let words = ["second": 2, "2nd": 2, "third": 3, "3rd": 3, "fourth": 4, "4th": 4]
        for (word, n) in words {
            if let m = s.range(of: "^\\s*\\(?\(word)\\s+(?:derivative|diff)\\s+(?:of\\s+)?", options: [.regularExpression, .caseInsensitive]) {
                return (n, "derivative " + s[m.upperBound...])
            }
        }
        return (1, s)
    }

    // The command, its arguments, and the letter if it was named in the command, as in d/dy.
    private static func read(_ s: String) -> (Kind, [String], String?)? {
        func split(_ inner: String) -> [String] {
            var parts: [String] = [], depth = 0, current = ""
            for c in inner {
                if c == "(" || c == "[" { depth += 1 }
                if c == ")" || c == "]" { depth -= 1 }
                if c == ",", depth == 0 { parts.append(current); current = "" } else { current.append(c) }
            }
            return (parts + [current]).map { $0.trimmingCharacters(in: .whitespaces) }
        }
        let names: [(String, Kind)] = [("expand", .expand), ("factorise", .factor), ("factorize", .factor), ("factor", .factor),
                                       ("differentiate", .derivative), ("derivative", .derivative), ("diff", .derivative),
                                       ("integrate", .integral), ("integral", .integral), ("antiderivative", .integral), ("limit", .limit), ("lim", .limit)]
        // expand((x+1)^2), expand ((x+1)^2), expand (x+1)^2 and expand 3(x+2): the name, and then
        // either the brackets that hold all its arguments, or the expression itself.
        let lower = s.lowercased()
        for (name, kind) in names where lower.hasPrefix(name) {
            let after = s[s.index(s.startIndex, offsetBy: name.count)...]
            guard let first = after.first, first == "(" || first == " " else { continue }
            let rest = after.trimmingCharacters(in: .whitespaces)
            if rest.hasPrefix("("), closes(rest) {
                return (kind, split(String(rest.dropFirst().dropLast())), nil)
            }
            // With a bracket that is only the start of the expression, or none: the whole is one.
            if kind != .limit, !rest.isEmpty { return (kind, kind == .derivative || kind == .integral ? split(rest) : [rest], nil) }
        }
        // derivative(f) at 3, and diff(f) at x = 3.
        if let at = s.range(of: "\\)\\s*at\\s+(?:[A-Za-z]\\s*=\\s*)?([^=]+)$", options: [.regularExpression, .caseInsensitive]) {
            let head = String(s[..<at.lowerBound]) + ")"
            let point = s[at].replacingOccurrences(of: "(?i)\\)\\s*at\\s+([A-Za-z]\\s*=\\s*)?", with: "", options: .regularExpression)
            if let (kind, args, v) = read(head), kind == .derivative { return (kind, args + [point], v) }
        }
        // d/dx x^3, d/dx(x^3), d/dx [x^3]
        if let m = s.range(of: "^d\\s*/\\s*d([A-Za-z])\\s*", options: .regularExpression) {
            let v = String(s[m]).filter { $0.isLetter }.last.map(String.init)!
            var body = String(s[m.upperBound...]).trimmingCharacters(in: .whitespaces)
            if body.isEmpty { return nil }
            var point: String?
            if let at = body.range(of: "\\s+at\\s+(?:[A-Za-z]\\s*=\\s*)?([^=]+)$", options: [.regularExpression, .caseInsensitive]) {
                point = String(body[at]).replacingOccurrences(of: "(?i)\\s+at\\s+([A-Za-z]\\s*=\\s*)?", with: "", options: .regularExpression)
                body = String(body[..<at.lowerBound])
            }
            if (body.hasPrefix("(") && body.hasSuffix(")")) || (body.hasPrefix("[") && body.hasSuffix("]")) { body = String(body.dropFirst().dropLast()) }
            return (.derivative, [body] + (point.map { [$0] } ?? []), v)
        }
        // ∫ x^2 dx, ∫_0^1 x^2 dx, ∫(x^2) dx
        if s.hasPrefix("∫") {
            var body = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
            var limits: [String] = []
            if let m = body.range(of: "^_[\\{(]?([^\\s^{}()]+)[\\})]?\\^[\\{(]?([^\\s{}()]+)[\\})]?", options: .regularExpression) {
                let found = String(body[m])
                let parts = found.dropFirst().components(separatedBy: "^")
                limits = parts.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "{}() ")) }
                body = String(body[m.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
            guard let d = body.range(of: "\\s*d([A-Za-z])$", options: .regularExpression) else { return nil }
            let v = String(body[d]).trimmingCharacters(in: .whitespaces).dropFirst()
            body = String(body[..<d.lowerBound])
            if body.hasPrefix("("), body.hasSuffix(")") { body = String(body.dropFirst().dropLast()) }
            return (.integral, [body] + limits, String(v))
        }
        return nil
    }

    // Whether the bracket the text opens with is the one it ends with.
    private static func closes(_ text: String) -> Bool {
        var depth = 0
        for (offset, c) in text.enumerated() {
            if c == "(" { depth += 1 } else if c == ")" { depth -= 1 }
            if depth == 0 { return offset == text.count - 1 }
        }
        return false
    }

    // MARK: Expanding

    private static func expand(_ tokens: [Parser.Token], _ letters: [String]) -> Algebra? {
        guard !letters.isEmpty else { return nil }
        var state = Parser.State(tokens: tokens, unknown: "", bound: letters)
        guard let expr = try? state.expression(), state.at == tokens.count, var terms = Simplification.collected(expr) else { return nil }
        // The highest power first.
        terms.sort { a, b in
            let (da, db) = (a.powers.values.reduce(0, +), b.powers.values.reduce(0, +))
            if da != db { return da > db }
            for letter in letters where a.powers[letter] != b.powers[letter] { return (a.powers[letter] ?? 0) > (b.powers[letter] ?? 0) }
            return false
        }
        let writer = Simplification(expr: expr, letters: letters, terms: terms)
        let result = writer.math(terms)
        var d = Details(name: "", equation: typeset(expr, ""), steps: [Step(label: "Multiplying out and collecting like terms", math: result)],
                        solutions: [result], note: nil, f: { _ in .nan }, roots: [])
        d.graph = nil
        return Algebra(solution: Solution(exact: result.plain, approx: nil), details: d, copyText: plain(result.plain), values: [])
    }

    // MARK: Factorising

    private static func factor(_ typed: String, _ tokens: [Parser.Token], _ letters: [String]) -> Algebra? {
        // A number is its primes.
        if letters.isEmpty, let facts = NumberFacts.parse(typed.trimmingCharacters(in: .whitespaces)), facts.whole != nil {
            return Algebra(solution: facts.solution, details: facts.details, copyText: facts.solution.exact, values: [])
        }
        guard letters.count == 1, let name = letters.first, let expr = try? Parser.expression(tokens, constants: []),
              let p = poly(expr).map(trim), p.count >= 2, p.count <= 9, let ints = integerCoefficients(p) else {
            // Letters together: what every term has in common.
            var state = Parser.State(tokens: tokens, unknown: "", bound: letters)
            guard letters.count > 1, let expr = try? state.expression(), state.at == tokens.count, let terms = Simplification.collected(expr) else { return nil }
            let writer = Simplification(expr: expr, letters: letters, terms: terms)
            guard writer.factor != nil else { return nil }
            let result = writer.result
            return Algebra(solution: Solution(exact: result.plain, approx: nil),
                           details: Details(name: "", equation: typeset(expr, ""), steps: [Step(label: "Taking out the common factor", math: result)], solutions: [result], note: nil, f: { _ in .nan }, roots: []),
                           copyText: plain(result.plain), values: [])
        }
        // p = content × the polynomial in whole numbers, with its leading coefficient positive.
        var whole = ints
        var content = p[p.count - 1] / Double(whole[whole.count - 1])
        if whole[whole.count - 1] < 0 { whole = whole.map { -$0 }; content = -content }
        var (cn, cd) = rational(content) ?? (1, 1)
        if cd < 0 { cn = -cn; cd = -cd }

        var rest = whole.map(Double.init)
        var roots: [(Int, Int)] = []   // (p, q): the factor qx − p
        while rest.count > 1 {
            guard let root = rationalRoot(rest) else { break }
            roots.append(root)
            rest = divide(rest, byRoot: root)
        }
        var pieces: [Math] = []
        var steps: [Step] = []
        let leftover = rest.count > 1 ? rest.map { Int($0.rounded()) } : []
        // The roots, nearest to −∞ first, each once with its power.
        let ordered = roots.sorted { a, b in
            if (a.0 == 0) != (b.0 == 0) { return a.0 == 0 }
            return Double(a.0) / Double(a.1) < Double(b.0) / Double(b.1)
        }
        var i = 0
        while i < ordered.count {
            var j = i
            while j + 1 < ordered.count, ordered[j + 1] == ordered[i] { j += 1 }
            let factor = t(linearFactor(ordered[i], name))
            pieces.append(j > i ? .power(factor, t("\(j - i + 1)")) : factor)
            i = j + 1
        }
        if !leftover.isEmpty {
            let math = polyMath(leftover.map(Double.init), name)
            pieces.append(row(t("("), math, t(")")))
        }
        if roots.isEmpty, cn == 1, cd == 1, !leftover.isEmpty { pieces = [polyMath(leftover.map(Double.init), name)] }
        let prefix = cn == 1 ? "" : cn == -1 ? "−" : "\(cn)"
        var result = Math.row((prefix.isEmpty ? [] : [t(prefix)]) + pieces)
        if cd > 1 { result = row(.row(pieces.isEmpty ? [t("1")] : (prefix.isEmpty ? [] : [t(prefix)]) + pieces), t("/\(cd)")) }
        let expanded = typeset(expr, name)
        let irreducible = roots.isEmpty && cn == 1 && cd == 1
        if cn != 1 || cd != 1 {
            steps.append(Step(label: "Taking out the common factor", math: row(t(cd == 1 ? minus(cn) : "\(minus(cn))/\(cd)"), t(" × "), t("("), polyMath(whole.map(Double.init), name), t(")"))))
        }
        // A quadratic with two rational roots is factorised by the AC method, as it is by hand;
        // not x² or x² + 3x, where x is a common factor and there is no ac to split.
        let byAC = whole.count == 3 && whole[0] != 0 && ordered.count == 2 && leftover.isEmpty
        var last = irreducible ? "Testing for rational roots" : "Writing as a product of factors"
        if byAC {
            let (worked, common) = acSteps(whole, ordered, name)
            steps += worked
            last = "Taking out the common factor \(common)"
        } else if !roots.isEmpty {
            let values = ordered.map { "\(name) = \(fraction($0.0, $0.1))" }
            var seen: [String] = []
            for v in values where !seen.contains(v) { seen.append(v) }
            steps.append(Step(label: "Finding the rational roots", math: t(seen.joined(separator: ", "))))
        }
        steps.append(Step(label: last, math: irreducible ? nil : result,
                          note: irreducible ? "The polynomial has no rational root and no common factor; it cannot be factorised further over the rational numbers." : (leftover.isEmpty ? nil : "The factor remaining has no rational root.")))
        var d = Details(name: name, equation: expanded, steps: steps, solutions: [result], note: nil, f: { x in p.reversed().reduce(0) { $0 * x + $1 } }, roots: ordered.map { Double($0.0) / Double($0.1) })
        d.graph = nil
        let solution = Solution(exact: result.plain, approx: irreducible ? "Irreducible over the rational numbers" : nil)
        return Algebra(solution: solution, details: d, copyText: plain(result.plain), values: [])
    }

    // The AC method for ax² + bx + c in whole numbers with roots p₁/q₁ and p₂/q₂: two numbers whose
    // product is ac and whose sum is b, the middle term split into them, the four terms grouped in
    // pairs, and the bracket the pairs share taken out. 2x² + 3x − 2: ac = −4 and b = 3 give 4 and
    // −1; 2x² + 4x − x − 2; 2x(x + 2) − (x + 2); hence (x + 2)(2x − 1). The numbers are taken in the
    // order that makes the shared bracket the answer's first factor, q₁x − p₁: they are −q₂p₁ and
    // −q₁p₂, the first pair being q₂x(q₁x − p₁) and the second −p₂(q₁x − p₁). Also the bracket.
    static func acSteps(_ c: [Int], _ roots: [(Int, Int)], _ name: String) -> ([Step], String) {
        let ((p1, q1), (p2, q2)) = (roots[0], roots[1])
        let (a, b, k) = (c[2], c[1], c[0])
        let (m, n) = (-q2 * p1, -q1 * p2)
        func bracketed(_ v: Int) -> String { v < 0 ? "(\(minus(v)))" : "\(v)" }
        // + 4x and − x; + 2 and − 2.
        func term(_ v: Int) -> String { "\(v < 0 ? " − " : " + ")\(abs(v) == 1 ? "" : "\(abs(v))")\(name)" }
        func number(_ v: Int) -> String { "\(v < 0 ? " − " : " + ")\(abs(v))" }
        let common = linearFactor(roots[0], name)
        let other = -p2
        // linearFactor writes its own brackets: (x + 2).
        let firstPair = "\(q2 == 1 ? "" : "\(q2)")\(name)\(common)"
        let secondPair = "\(other < 0 ? " − " : " + ")\(abs(other) == 1 ? "" : "\(abs(other))")\(common)"
        return ([
            Step(label: "Finding two numbers with product ac and sum b", math: t("ac = \(minus(a * k)),  b = \(minus(b)):  \(minus(m)) and \(minus(n))"),
                 note: "\(minus(m)) × \(bracketed(n)) = \(minus(a * k)), and \(minus(m)) + \(bracketed(n)) = \(minus(b))."),
            Step(label: "Splitting the middle term", math: row(polyMath([0, 0, Double(a)], name), t(term(m) + term(n) + number(k)))),
            Step(label: "Grouping in pairs", math: t(firstPair + secondPair)),
        ], common)
    }

    // A rational root p/q of the polynomial with whole coefficients (lowest power first), found
    // among those the leading and constant coefficients allow.
    private static func rationalRoot(_ c: [Double]) -> (Int, Int)? {
        guard c.count > 1 else { return nil }
        let ints = c.map { Int($0.rounded()) }
        if ints[0] == 0 { return (0, 1) }
        func divisors(_ n: Int) -> [Int] {
            let n = abs(n)
            guard n > 0, n <= 10_000_000 else { return [] }
            var out: [Int] = [], d = 1
            while d * d <= n { if n % d == 0 { out.append(d); if d * d != n { out.append(n / d) } }; d += 1 }
            return out
        }
        let scale = c.map(abs).max() ?? 1
        for q in divisors(ints[ints.count - 1]).sorted() {
            for p in divisors(ints[0]).sorted() {
                for sign in [1, -1] where gcd(p, q) == 1 {
                    let r = Double(sign * p) / Double(q)
                    let v = c.reversed().reduce(0.0) { $0 * r + $1 }
                    if abs(v) <= 1e-9 * scale * max(1, pow(abs(r), Double(c.count - 1))) { return (sign * p, q) }
                }
            }
        }
        return nil
    }

    // The polynomial (lowest power first) divided by qx − p, in whole numbers.
    private static func divide(_ c: [Double], byRoot root: (Int, Int)) -> [Double] {
        let r = Double(root.0) / Double(root.1)
        var quotient: [Double] = []
        var carry = 0.0
        for k in stride(from: c.count - 1, through: 1, by: -1) {
            carry = c[k] + carry * r
            quotient.append(carry)
        }
        // c = (x − r)·Q, and qx − p is q(x − r): so the quotient by it is Q/q.
        return quotient.reversed().map { ($0 / Double(root.1)).rounded() }
    }

    // MARK: Differentiating

    private static func derivative(_ expr: Expr, _ name: String, point: String?, order: Int = 1) -> Algebra? {
        guard var raw = differentiated(expr) else { return nil }
        var steps = Working.derivative(expr, name)
        if order > 1 { steps.insert(Step(label: "Derivative 1 of \(order)", math: nil, note: "Differentiate the original expression first, then differentiate each result in turn."), at: 0) }
        // Again for each order more, from the tidied form.
        for _ in 1..<max(order, 1) {
            let previous = cleaned(raw)
            guard let next = differentiated(previous) else { return nil }
            if steps.count < 60 {
                steps.append(Step(label: "Differentiating once more", math: row(t("d/d\(name) "), .group(typeset(previous, name)))))
                steps += Working.derivative(previous, name)
            }
            raw = next
        }
        let result = cleaned(raw)
        // A polynomial, in the form it is usually written, where that is the shorter.
        var shown = typeset(result, name)
        if let p = poly(result).map(trim), !p.isEmpty {
            let expanded = polyMath(p, name)
            if expanded.plain.count <= shown.plain.count { shown = expanded }
        }
        let original = typeset(expr, name)
        let operatorName = order > 1 ? "d\(superscript(order))/d\(name)\(superscript(order))" : "d/d\(name)"
        steps.append(Step(label: "Simplifying the full derivative", math: row(t("\(operatorName) "), .group(original), t(" = "), shown)))
        var d = Details(name: name, equation: row(t("\(operatorName) "), original.plain.contains(" ") ? row(t("("), original, t(")")) : original), steps: steps,
                        solutions: [shown], note: nil, f: { result.eval($0) }, roots: [])
        d.graph = nil
        if let point, let at = try? Parser.constant(point), !at.hasUnknown {
            let x = at.eval(0), v = result.eval(x)
            guard v.isFinite else { return nil }
            let evaluation = Evaluation(name: nil, expr: .num(v))
            let line = evaluation.solution
            steps.append(Step(label: "Substituting \(name) = \(decimal(x))", math: row(typeset(result.substitutingUnknown(at), name), t(" \(isExact(v) ? "=" : "≈") \(decimal(v))"))))
            d.steps = steps
            d.solutions = line.map(answerLines) ?? [t("= \(decimal(v))")]
            return Algebra(solution: line ?? Solution(exact: "= \(decimal(v))", approx: nil), details: d, copyText: String(format: "%.12g", v), values: [v])
        }
        return Algebra(solution: Solution(exact: shown.plain, approx: order > 1 ? "The derivative of order \(order) with respect to \(name)" : "The derivative with respect to \(name)"), details: d, copyText: plain(shown.plain), values: [])
    }

    // The derivative as the rules give it, before it is tidied; nil where there is no rule.
    static func differentiated(_ e: Expr) -> Expr? {
        switch e {
        case .num, .constant, .index: return .num(0)
        case .unknown: return .num(1)
        case .neg(let a): return differentiated(a).map { .neg($0) }
        case .op(let o, let a, let b):
            guard let da = differentiated(a), let db = differentiated(b) else { return nil }
            switch o {
            case "+", "-": return .op(o, da, db)
            case "*": return .op("+", .op("*", da, b), .op("*", a, db))
            case "/": return b.hasUnknown ? .op("/", .op("-", .op("*", da, b), .op("*", a, db)), .op("^", b, .num(2))) : .op("/", da, b)
            case "^":
                if !b.hasUnknown { return .op("*", .op("*", b, .op("^", a, .op("-", b, .num(1)))), da) }
                if !a.hasUnknown { return .op("*", .op("*", e, .call("ln", a)), db) }
                return .op("*", e, .op("+", .op("*", db, .call("ln", a)), .op("/", .op("*", b, da), a)))
            default: return nil
            }
        case .call(let f, let a):
            guard let da = differentiated(a) else { return nil }
            func chain(_ outer: Expr) -> Expr { .op("*", outer, da) }
            switch f {
            case "sin": return chain(.call("cos", a))
            case "cos": return chain(.neg(.call("sin", a)))
            case "tan": return .op("/", da, .op("^", .call("cos", a), .num(2)))
            case "exp": return chain(.call("exp", a))
            case "ln": return .op("/", da, a)
            case "log": return .op("/", da, .op("*", a, .call("ln", .num(10))))
            case "sqrt": return .op("/", da, .op("*", .num(2), .call("sqrt", a)))
            case "asin": return .op("/", da, .call("sqrt", .op("-", .num(1), .op("^", a, .num(2)))))
            case "acos": return .neg(.op("/", da, .call("sqrt", .op("-", .num(1), .op("^", a, .num(2))))))
            case "atan": return .op("/", da, .op("+", .num(1), .op("^", a, .num(2))))
            case "sinh": return chain(.call("cosh", a))
            case "cosh": return chain(.call("sinh", a))
            case "tanh": return .op("/", da, .op("^", .call("cosh", a), .num(2)))
            case "abs": return .op("*", .op("/", a, .call("abs", a)), da)
            default: return nil
            }
        case .sum, .apply: return nil
        }
    }

    // Nothing times one, nothing plus nought, numbers worked out, a minus of a minus.
    static func cleaned(_ e: Expr) -> Expr {
        switch e {
        case .neg(let a):
            switch cleaned(a) {
            case .num(let v): return .num(-v)
            case .neg(let b): return b
            case let c: return .neg(c)
            }
        case .op(let o, let a, let b):
            let (x, y) = (cleaned(a), cleaned(b))
            if case .num(let u) = x, case .num(let v) = y, o != "^" || (u != 0 || v >= 0) {
                let value = Expr.op(o, x, y).eval(0)
                if value.isFinite, abs(value) < 1e15, o != "/" || value == value.rounded() || rational(value) != nil, o != "^" || v == v.rounded() { return .num(value) }
            }
            func isNum(_ e: Expr, _ v: Double) -> Bool { if case .num(let n) = e { n == v } else { false } }
            switch o {
            case "+":
                if isNum(x, 0) { return y }
                if isNum(y, 0) { return x }
                if case .neg(let n) = y { return .op("-", x, n) }
            case "-":
                if isNum(y, 0) { return x }
                if isNum(x, 0) { return cleaned(.neg(y)) }
            case "*":
                if isNum(x, 0) || isNum(y, 0) { return .num(0) }
                // The numbers of a product are multiplied together and put first, 6x(x² + 1)², and
                // the powers of the unknown come before the rest.
                var factors: [Expr] = []
                var coefficient = 1.0
                func gather(_ e: Expr) {
                    switch e {
                    case .op("*", let l, let r): gather(l); gather(r)
                    case .num(let v): coefficient *= v
                    case .neg(let inner): coefficient *= -1; gather(inner)
                    default: factors.append(e)
                    }
                }
                gather(x)
                gather(y)
                func priority(_ e: Expr) -> Int {
                    switch e {
                    case .index: return 0
                    case .unknown, .op("^", .unknown, _): return 1
                    default: return 2
                    }
                }
                factors = factors.enumerated().sorted { (priority($0.element), $0.offset) < (priority($1.element), $1.offset) }.map(\.element)
                guard var product = factors.first else { return .num(coefficient) }
                for f in factors.dropFirst() { product = .op("*", product, f) }
                if abs(coefficient) != 1 { product = .op("*", .num(abs(coefficient)), product) }
                return coefficient < 0 ? .neg(product) : product
            case "/":
                if isNum(y, 1) { return x }
                if isNum(y, -1) { return cleaned(.neg(x)) }
                if isNum(x, 0) { return .num(0) }
                if case .num(let v) = y, v < 0 { return cleaned(.neg(.op("/", x, .num(-v)))) }
                if typeset(x, "x").plain == typeset(y, "x").plain { return .num(1) }
            case "^":
                if isNum(y, 1) { return x }
                if isNum(y, 0) { return .num(1) }
                // x to a power below nought is one over x to the power above it.
                if case .num(let v) = y, v < 0 { return cleaned(.op("/", .num(1), .op("^", x, .num(-v)))) }
            default: break
            }
            return .op(o, x, y)
        case .call(let f, let a):
            let c = cleaned(a)
            if f == "ln", case .num(let v) = c, v == M_E { return .num(1) }
            return .call(f, c)
        default: return e
        }
    }

    // MARK: Limits

    // Where f settles as x comes in towards a from both sides, or as it grows without bound.
    private static func limit(_ f: Expr, _ name: String, toward typedTarget: String) -> Algebra? {
        // With a letter in it besides the unknown, sin(ax) − a sin x, the limit is read from the series.
        if Series.hasLetter(f) { return Series.limitAnswer(f, name, at: typedTarget) }
        // 0+ and 0^+ come in from the right alone, and 0- from the left.
        var target = typedTarget, only: Double?
        if let m = target.range(of: "^(.+?)\\s*\\^?\\s*\\(?\\s*([+−-])\\s*\\)?$", options: .regularExpression), !target[..<target.index(before: target.endIndex)].hasSuffix("(") {
            let sign = target.last { "+−-".contains($0) } == "+" ? 1.0 : -1.0
            let head = target[m].replacingOccurrences(of: "\\s*\\^?\\s*\\(?\\s*[+−-]\\s*\\)?$", with: "", options: .regularExpression)
            if !head.isEmpty, let _ = try? Parser.constant(head) { target = head; only = sign }
        }
        let infinite = ["inf", "∞", "+inf", "+∞", "-inf", "−inf", "-∞", "−∞"].contains(target.replacingOccurrences(of: " ", with: "").lowercased())
        let negative = target.contains("-") || target.contains("−")
        snapsToZero = false
        defer { snapsToZero = true }
        func sample(_ side: Double) -> [Double] {
            if infinite { return (3...9).map { pow(10, Double($0)) * (negative ? -1 : 1) } }
            guard let a = (try? Parser.constant(target))?.eval(0), a.isFinite else { return [] }
            return (2...8).map { a + side * pow(10, -Double($0)) * max(1, abs(a)) }
        }
        var sides: [[Double]] = infinite ? [sample(1)] : only.map { [sample($0)] } ?? [sample(-1), sample(1)]
        guard sides.allSatisfy({ !$0.isEmpty }) else { return nil }
        var values: [Double] = []
        var describe: [String] = []
        var named: [String] = []
        // A side where the function has no value is no side: ln x is only come at from the right.
        var kept: [[Double]] = []
        for (i, points) in sides.enumerated() {
            if points.contains(where: { f.eval($0).isNaN }) { named.append(i == 0 ? "left" : "right"); continue }
            kept.append(points)
        }
        guard !kept.isEmpty, kept.count + named.count == sides.count else { return nil }
        let oneSided = only != nil
        sides = kept
        for points in sides {
            let ys = points.map { f.eval($0) }
            let n = ys.count
            // Grown past all bounds, step after step.
            if abs(ys[n - 1]) > 100, abs(ys[n - 1]) > 5 * abs(ys[n - 3]), ys[n - 1].sign == ys[n - 3].sign, ys[n - 1].sign == ys[n - 2].sign {
                values.append(ys[n - 1] > 0 ? .infinity : -.infinity)
                describe.append(ys[n - 1] > 0 ? "∞" : "−∞")
                continue
            }
            // Falling to nothing, step after step: 0.
            if abs(ys[n - 1]) < 1e-3, abs(ys[n - 4]) < 0.1, (n - 3..<n).allSatisfy({ abs(ys[$0]) < 0.5 * abs(ys[$0 - 1]) || ys[$0 - 1] == 0 }) {
                values.append(0)
                describe.append("0")
                continue
            }
            // Otherwise the sample where moving in a step changes it least: closer in the shape
            // of the function is truer, and further in the rounding of the machine is worse.
            var best = 1
            for i in 2..<n where abs(ys[i] - ys[i - 1]) < abs(ys[best] - ys[best - 1]) { best = i }
            let spread = abs(ys[best] - ys[best - 1]) / max(1, abs(ys[best]))
            guard spread <= 1e-3 else { return nil }
            var settled = ys[best]
            // Where the sample came in by a tenth with each step and the changes fell by a tenth
            // too, what is left of the error is a ninth of the last change.
            if best >= 2 {
                let d1 = ys[best] - ys[best - 1], d0 = ys[best - 1] - ys[best - 2]
                if d1 != 0, abs(d0 / d1) > 6, abs(d0 / d1) < 16 { settled += d1 / 9 }
            }
            // The simplest fraction within what the sampling can tell apart.
            for q in 1...20 {
                let p = (settled * Double(q)).rounded()
                if abs(p / Double(q) - settled) <= max(2e-5, 3 * spread) * max(1, abs(settled)) { settled = p / Double(q); break }
            }
            values.append(settled)
            describe.append(decimal(settled))
        }
        let shownTarget = target.replacingOccurrences(of: "inf", with: "∞", options: .caseInsensitive).replacingOccurrences(of: "-∞", with: "−∞")
        let heading = row(t("lim "), t("\(name) → \(shownTarget)"), t(" "), typeset(f, name))
        var d = Details(name: name, equation: heading, steps: [], solutions: [], note: nil, f: { f.eval($0) }, roots: [])
        if sides.count == 2 {
            d.steps.append(Step(label: "Approaching from the left", math: t("→ \(describe[0])")))
            d.steps.append(Step(label: "Approaching from the right", math: t("→ \(describe[1])")))
        } else if !infinite {
            let side = oneSided ? (only! > 0 ? "right" : "left") : (named.first == "left" ? "right" : "left")
            d.steps.append(Step(label: "Approaching from the \(side)", math: t("→ \(describe[0])"),
                                note: oneSided ? nil : "The function has no value on the \(named.first ?? "other") side."))
        } else {
            d.steps.append(Step(label: "Letting \(name) grow without bound", math: t("→ \(describe[0])")))
        }
        let agree = values.count == 1 || values[0] == values[1] || (values[0].isFinite && values[1].isFinite && abs(values[0] - values[1]) <= 1e-6 * max(1, abs(values[0])))
        guard agree else {
            let solution = Solution(exact: "Does not exist", approx: "From the left \(describe[0]); from the right \(describe[1]).")
            d.solutions = [t(solution.exact), t(solution.approx ?? "")]
            return Algebra(solution: solution, details: d, copyText: "", values: [])
        }
        let v = values[0]
        if !v.isFinite {
            let solution = Solution(exact: v > 0 ? "∞" : "−∞", approx: "The limit grows without bound.")
            d.solutions = [t(solution.exact)]
            return Algebra(solution: solution, details: d, copyText: solution.exact, values: [])
        }
        guard let line = Evaluation(name: nil, expr: .num(v)).solution else { return nil }
        d.solutions = answerLines(line)
        d.steps.append(Step(label: "Hence", math: t(line.exact)))
        return Algebra(solution: line, details: d, copyText: String(format: "%.12g", v), values: [v])
    }

    // MARK: Integrating

    private static func integral(_ expr: Expr, _ name: String, limits: [String]) -> Algebra? {
        let antiderivative = integrated(expr).map(cleaned)
        if limits.count == 2 {
            guard let lo = (try? Parser.constant(limits[0]))?.eval(0), let hi = (try? Parser.constant(limits[1]))?.eval(0), lo.isFinite, hi.isFinite else { return nil }
            let original = typeset(expr, name)
            // The sign with its limits below and above it, as Σ has them, each limit as it was typed: π/2, not 1.5708.
            func limit(_ typed: String, _ value: Double) -> Math { (try? Parser.constant(typed)).map { typeset($0, "") } ?? t(decimal(value)) }
            let sign = Math.bigOperator("∫", lower: limit(limits[0], lo), upper: limit(limits[1], hi))
            var d = Details(name: name, equation: row(sign, termMath(expr, name), t(" d\(name)")), steps: [], solutions: [],
                            note: nil, f: { expr.eval($0) }, roots: [])
            // Where the integrand is unbounded, at a limit or between them, F(b) − F(a) is not the
            // integral: 1/x² from −1 to 1 is not −2. Each such point is tested for whether F has a
            // finite limit there, from each side it is approached.
            let unbounded = poles({ expr.eval($0) }, min(lo, hi), max(lo, hi))
            var value: Double
            if !unbounded.isEmpty {
                // Without an antiderivative, the integral itself stands for one, worked numerically
                // from the middle of each piece between the points.
                let primitive: (Double, Double) -> (Double) -> Double
                let what: String
                if let F = antiderivative {
                    d.steps += Working.integral(expr, primitive: F, name: name)
                    primitive = { _, _ in { F.eval($0) } }
                    what = "F(\(name))"
                } else {
                    primitive = { p, q in let middle = (p + q) / 2; return { numeric(expr, middle, $0) } }
                    what = "The integral up to \(name), worked numerically,"
                }
                switch across(primitive, unbounded, lo, hi) {
                case .diverges(let point):
                    let solution = Solution(exact: "Does not converge", approx: "The integrand is unbounded at \(name) = \(decimal(point)), and the integral diverges there.")
                    d.steps.append(Step(label: "Examining \(name) = \(decimal(point)), where the integrand is unbounded", math: nil,
                                        note: "\(what) has no finite limit as \(name) approaches \(decimal(point)); hence the integral does not converge."))
                    d.solutions = [t(solution.exact)]
                    return Algebra(solution: solution, details: d, copyText: solution.exact, values: [])
                case .undefined:
                    // Said as any value with no real number is, below.
                    value = .nan
                case .converges(let total):
                    value = total
                    let points = unbounded.map(decimal).joined(separator: ", ")
                    d.steps.append(Step(label: "Taking limits at \(name) = \(points), where the integrand is unbounded", math: nil,
                                        note: "\(what) has a finite limit as \(name) approaches each of these from either side; hence the integral converges, and is the sum of the changes between them."))
                }
            } else {
                value = antiderivative.map { $0.eval(hi) - $0.eval(lo) } ?? numeric(expr, lo, hi)
                if !value.isFinite { value = numeric(expr, lo, hi) }
                if let F = antiderivative {
                    d.steps += Working.integral(expr, primitive: F, name: name)
                    d.steps.append(Step(label: "Fundamental theorem of calculus", math: row(sign, termMath(expr, name), t(" d\(name) = F(b) − F(a)")),
                                        note: "Evaluate the antiderivative at the upper limit, then subtract its value at the lower limit."))
                    d.steps.append(Step(label: "Substituting the integration limits", math: row(t("F(\(limit(limits[1], hi).plain)) − F(\(limit(limits[0], lo).plain)) = "),
                                        .group(typeset(F.substitutingUnknown((try? Parser.constant(limits[1])) ?? .num(hi)), name)), t(" − "),
                                        .group(typeset(F.substitutingUnknown((try? Parser.constant(limits[0])) ?? .num(lo)), name)))))
                }
            }
            value = Double(String(format: "%.13g", value)) ?? value
            if antiderivative == nil, unbounded.isEmpty {
                d.steps.append(Step(label: "Integrating numerically", math: nil,
                                    note: "No antiderivative in closed form is known to the calculator; the integral is found by adaptive Gauss–Kronrod quadrature."))
            }
            let evaluation = Evaluation(name: nil, expr: .num(value))
            guard let line = evaluation.solution else { return nil }
            d.steps.append(Step(label: "Hence", math: t(line.exact)))
            d.solutions = answerLines(line)
            return Algebra(solution: line, details: d, copyText: String(format: "%.12g", value), values: [value])
        }
        guard limits.isEmpty, let F = antiderivative else { return nil }
        let shown = typeset(F, name)
        let result = row(shown, t(" + C"))
        var d = Details(name: name, equation: row(t("∫ "), termMath(expr, name), t(" d\(name)")),
                        steps: Working.integral(expr, primitive: F, name: name) + [Step(label: "Adding the constant of integration", math: result,
                            note: "The derivative of any constant is zero, so every antiderivative differs by a constant C on the interval considered.")], solutions: [result], note: nil, f: { expr.eval($0) }, roots: [])
        d.graph = nil
        return Algebra(solution: Solution(exact: result.plain, approx: "The integral with respect to \(name), up to a constant C"), details: d, copyText: plain(result.plain), values: [])
    }

    // The points from a to b at which f is unbounded, 1/x² at 0 and 1/√x at 0: the limits where f
    // grows without bound towards them, and those between where |f| peaks on a grid of a thousand
    // steps, each found exactly by narrowing in on the peak. A peak that levels off, however
    // high, 1/(x² + 10⁻⁶), is no such point.
    static func poles(_ f: (Double) -> Double, _ a: Double, _ b: Double) -> [Double] {
        let width = b - a
        guard width > 0 else { return [] }
        let steps = 1000
        let xs = (0...steps).map { a + width * Double($0) / Double(steps) }
        let ys = xs.map { abs(f($0)) }
        let finite = ys.filter(\.isFinite).sorted()
        let typical = max(1, finite.isEmpty ? 1 : finite[finite.count / 2])
        // Unbounded at c: |f| at a hundred-millionth of the width from it is ten times or more what
        // it is at a ten-thousandth, and large, on whichever side lies within the limits.
        func unbounded(_ c: Double) -> Bool {
            if f(c).isInfinite { return true }
            // A limit is a pole only where the integrand is unbounded at it, not merely large and
            // growing towards a point beyond it. How far off the pole is, is told by how fast it
            // grows: tan x at the decimal nearest π/2 is within rounding of its pole, and is one;
            // 1/x at −10⁻³⁰⁰ is as far from its pole at 0 as from nought itself, and is not.
            // Where it has no value there, sin(x)/x² at 0, how it grows towards it decides, as below.
            if c == a || c == b, !f(c).isNaN {
                let value = abs(f(c))
                guard value > 1e3 * typical else { return false }
                let h = 1e-8 * width, inside = abs(f(c == a ? c + h : c - h))
                guard inside.isFinite, inside > 0 else { return true }
                return h * inside / value <= 1e-12 * abs(c)
            }
            for side in [-1.0, 1.0] where (side < 0 ? c > a : c < b) {
                let near = abs(f(c + side * 1e-8 * width)), far = abs(f(c + side * 1e-4 * width))
                if near.isInfinite || (near > 10 * far && near > 1e3 * typical) { return true }
            }
            return false
        }
        var found: [Double] = []
        func add(_ c: Double) {
            let c = abs(c - a) < 1e-12 * width ? a : abs(c - b) < 1e-12 * width ? b : abs(c) < 1e-12 * max(1, width) ? 0 : c
            if !found.contains(where: { abs($0 - c) <= 1e-9 * width }), unbounded(c) { found.append(c) }
        }
        // The peak of |f| between two points, narrowed in on by thirds.
        func peak(_ from: Double, _ to: Double) -> Double {
            var (l, r) = (from, to)
            for _ in 0..<100 {
                let (m1, m2) = (l + (r - l) / 3, r - (r - l) / 3)
                let (y1, y2) = (abs(f(m1)), abs(f(m2)))
                if !y1.isFinite { r = m1; l = m1; break }
                if !y2.isFinite { l = m2; r = m2; break }
                if y1 < y2 { l = m1 } else { r = m2 }
            }
            return Double(String(format: "%.12g", (l + r) / 2)) ?? (l + r) / 2
        }
        add(a)
        add(b)
        for i in 1..<steps {
            if ys[i].isInfinite { add(xs[i]); continue }
            guard ys[i].isFinite, ys[i] > 100 * typical, ys[i] >= ys[i - 1] || !ys[i - 1].isFinite, ys[i] >= ys[i + 1] || !ys[i + 1].isFinite else { continue }
            add(peak(xs[i - 1], xs[i + 1]))
        }
        // A pole in the first step or the last, between a limit and the grid's next point, as
        // 1/(x − 0.999999) from −1 to 1 has: no point of the grid is a peak there, |f| rising all
        // the way to the limit. The peak within that step is a pole where it is short of the limit.
        for (from, to) in [(xs[0], xs[1]), (xs[steps - 1], xs[steps])] {
            let c = peak(from, to)
            if abs(c - a) > 1e-9 * width, abs(c - b) > 1e-9 * width { add(c) }
        }
        return found.sorted()
    }

    // undefined: the antiderivative has no real value at an end that is no pole, as ln x below nought.
    enum Across { case converges(Double), diverges(at: Double), undefined }

    // ∫ from lo to hi, the integrand being unbounded at these points: the sum of the changes in an
    // antiderivative between them, each end taken as its limit there, where it has one. The
    // antiderivative is asked for afresh for each piece, (p, q), as one worked numerically from the
    // middle of the piece is.
    static func across(_ primitive: (Double, Double) -> (Double) -> Double, _ points: [Double], _ lo: Double, _ hi: Double) -> Across {
        let (a, b) = (min(lo, hi), max(lo, hi)), width = b - a
        let cuts = [a] + points.filter { $0 > a && $0 < b } + [b]
        let unbounded = Set(points)
        var total = 0.0
        for (p, q) in zip(cuts, cuts.dropFirst()) {
            let F = primitive(p, q)
            let (startPole, endPole) = (unbounded.contains(p), unbounded.contains(q))
            if !startPole, !F(p).isFinite { return .undefined }
            if !endPole, !F(q).isFinite { return .undefined }
            let start = startPole ? limit(F, p, fromAbove: true, width) : F(p)
            let end = endPole ? limit(F, q, fromAbove: false, width) : F(q)
            guard let start, start.isFinite else { return .diverges(at: p) }
            guard let end, end.isFinite else { return .diverges(at: q) }
            total += end - start
        }
        return .converges(hi >= lo ? total : -total)
    }

    // F's limit at c from one side, where it has one: F(c ± h) for h a hundredth of the width down
    // to a ten-billionth, whose differences must shrink, by as much each time, for it to settle.
    // 2√x settles at 0; ln|x| and −1/x do not.
    private static func limit(_ F: (Double) -> Double, _ c: Double, fromAbove: Bool, _ width: Double) -> Double? {
        // Nearer each time; given up as soon as the differences plainly do not shrink, as they do
        // not for ln|x|, since the nearest points cost the most to integrate numerically.
        var values: [Double] = []
        for k in 2...10 {
            let v = F(fromAbove ? c + width * pow(10, -Double(k)) : c - width * pow(10, -Double(k)))
            guard v.isFinite else { return nil }
            values.append(v)
            if values.count >= 4 {
                let (first, latest) = (abs(values[1] - values[0]), abs(values[values.count - 1] - values[values.count - 2]))
                if latest > 1e-13 * max(1, abs(v)), latest >= 0.9 * first { return nil }
            }
        }
        guard let last = values.last else { return nil }
        let differences = zip(values, values.dropFirst()).map { abs($1 - $0) }
        guard let first = differences.first, let final = differences.last else { return last }
        if final <= 1e-13 * max(1, abs(last)) || first == 0 { return last }
        let ratio = pow(final / first, 1 / Double(differences.count - 1))
        guard ratio < 0.99 else { return nil }
        // What is left of a geometric tail, added on.
        return last + (last - values[values.count - 2]) * ratio / (1 - ratio)
    }

    // The coefficient and constant of a linear expression in the unknown: (2, 3) for 2x + 3.
    static func linear(_ g: Expr) -> (a: Double, b: Double)? {
        guard g.hasUnknown, let p = poly(g).map(trim), p.count == 2 else { return nil }
        return (p[1], p[0])
    }

    private static func over(_ e: Expr, _ a: Double) -> Expr { a == 1 ? e : .op("/", e, .num(a)) }

    // An antiderivative, where the form is one it knows: polynomials, and the standard functions of
    // a linear expression, and sums and multiples of them.
    static func integrated(_ e: Expr) -> Expr? {
        if !e.hasUnknown { return .op("*", e, .unknown) }
        if let p = poly(e).map(trim), !p.isEmpty { return antiderivative(of: p) }
        switch e {
        case .neg(let a): return integrated(a).map { .neg($0) }
        case .op("+", let a, let b): if let x = integrated(a), let y = integrated(b) { return .op("+", x, y) }; return nil
        case .op("-", let a, let b): if let x = integrated(a), let y = integrated(b) { return .op("-", x, y) }; return nil
        case .op("*", let a, let b):
            if !a.hasUnknown { return integrated(b).map { .op("*", a, $0) } }
            if !b.hasUnknown { return integrated(a).map { .op("*", $0, b) } }
            return product(a, b) ?? product(b, a)
        case .op("/", let a, let b):
            if !b.hasUnknown { return integrated(a).map { .op("/", $0, b) } }
            if !a.hasUnknown, let p = poly(b).map(trim), p.count == 3, p[1] == 0, p[0] > 0, p[2] > 0 {
                let k = (p[0] / p[2]).squareRoot()
                let argument: Expr = k == 1 ? .unknown : .op("/", .unknown, .num(k))
                return cleaned(.op("*", .op("/", a, .num(p[2] * k)), .call("atan", argument)))
            }
            if !a.hasUnknown, case .call("sqrt", let inside) = b, let p = poly(inside).map(trim),
               p.count == 3, p[1] == 0, p[0] > 0, p[2] == -1 {
                let k = p[0].squareRoot()
                let argument: Expr = k == 1 ? .unknown : .op("/", .unknown, .num(k))
                return cleaned(.op("*", a, .call("asin", argument)))
            }
            if !a.hasUnknown, let (k, _) = linear(b) { return .op("*", over(a, k), .call("ln", .call("abs", b))) }
            if !a.hasUnknown, case .op("^", .unknown, .num(let n)) = b, n != 1 {
                if n > 1 { return .neg(.op("/", a, .op("*", .num(n - 1), .op("^", .unknown, .num(n - 1))))) }
                return .op("/", .op("*", a, .op("^", .unknown, .num(1 - n))), .num(1 - n))
            }
            return nil
        case .op("^", let a, let b):
            if !b.hasUnknown, let (k, _) = linear(a), case .num(let n) = b {
                if n == -1 { return over(.call("ln", .call("abs", a)), k) }
                return over(.op("/", .op("^", a, .num(n + 1)), .num(n + 1)), k)
            }
            if !a.hasUnknown, let (k, _) = linear(b), a.eval(0) > 0, a.eval(0) != 1 {
                if case .num(let base) = a, abs(base - M_E) < 1e-12 { return over(e, k) }
                return .op("/", e, .op("*", .num(k), .call("ln", a)))
            }
            return nil
        case .call(let f, let g):
            guard let (k, _) = linear(g) else { return nil }
            switch f {
            case "sin": return over(.neg(.call("cos", g)), k)
            case "cos": return over(.call("sin", g), k)
            case "exp": return over(e, k)
            case "sinh": return over(.call("cosh", g), k)
            case "cosh": return over(.call("sinh", g), k)
            case "tan": return over(.neg(.call("ln", .call("abs", .call("cos", g)))), k)
            case "sqrt": return over(.op("/", .op("*", .num(2), .op("^", g, .op("/", .num(3), .num(2)))), .num(3)), k)
            case "ln": return over(.op("-", .op("*", g, .call("ln", g)), g), k)
            default: return nil
            }
        default: return nil
        }
    }

    // c₀ + c₁x + c₂x² + … integrated: c₀x + c₁x²/2 + …
    private static func antiderivative(of p: Poly) -> Expr {
        var terms: [Expr] = []
        for (k, c) in p.enumerated().reversed() where c != 0 {
            let power: Expr = k == 0 ? .unknown : .op("^", .unknown, .num(Double(k + 1)))
            let x: Expr = k == 0 ? .unknown : power
            let (numerator, denominator) = rational(c).map { reducedPair($0.0, $0.1 * (k + 1)) } ?? (c, Double(k + 1))
            var term: Expr = numerator == 1 || numerator == -1 ? x : .op("*", .num(abs(numerator)), x)
            if denominator != 1 { term = .op("/", term, .num(denominator)) }
            terms.append(numerator < 0 ? .neg(term) : term)
        }
        return terms.dropFirst().reduce(terms[0]) { acc, term in
            if case .neg(let inner) = term { return .op("-", acc, inner) }
            return .op("+", acc, term)
        }
    }

    private static func reducedPair(_ p: Int, _ q: Int) -> (Double, Double) {
        let g = max(gcd(p, q), 1)
        return (Double(p / g), Double(q / g))
    }

    // Adaptive Gauss–Kronrod (7, 15) quadrature.
    static func numeric(_ e: Expr, _ a: Double, _ b: Double) -> Double {
        let xgk = [0.991455371120812639206854697526329, 0.949107912342758524526189684047851, 0.864864423359769072789712788640926,
                   0.741531185599394439863864773280788, 0.586087235467691130294144838258730, 0.405845151377397166906606412076961,
                   0.207784955007898467600689403773245, 0.0]
        let wgk = [0.022935322010529224963732008058970, 0.063092092629978553290700663189204, 0.104790010322250183839876322541518,
                   0.140653259715525918745189590510238, 0.169004726639267902826583426598550, 0.190350578064785409913256402421014,
                   0.204432940075298892414161999234649, 0.209482141084727828012999174891714]
        let wg = [0.129484966168869693270611432679082, 0.279705391489276667901467771423780, 0.381830050505118944950369775488975,
                  0.417959183673469387755102040816327]
        func panel(_ lo: Double, _ hi: Double) -> (k: Double, g: Double) {
            let c = (lo + hi) / 2, h = (hi - lo) / 2
            var k = wgk[7] * e.eval(c), g = wg[3] * e.eval(c)
            for i in 0..<7 {
                let s = h * xgk[i], v = e.eval(c - s) + e.eval(c + s)
                k += wgk[i] * v
                if i % 2 == 1 { g += wg[i / 2] * v }
            }
            return (k * h, g * h)
        }
        func go(_ lo: Double, _ hi: Double, _ depth: Int) -> Double {
            let (k, g) = panel(lo, hi)
            if !k.isFinite { return .nan }
            if depth >= 40 || abs(k - g) <= 1e-13 * max(abs(k), 1e-3) * max(1, (hi - lo)) { return k }
            let m = (lo + hi) / 2
            return go(lo, m, depth + 1) + go(m, hi, depth + 1)
        }
        return a == b ? 0 : a < b ? go(a, b, 0) : -go(b, a, 0)
    }
}
