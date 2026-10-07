import Foundation

// Asked for by name, for what is typed with no = in it: expand((x+1)^2), factor(x^2-5x+6),
// derivative(x^3+2x), integrate(x^2, 0, 1), d/dx sin(x), ∫ x^2 dx. Each is worked in the one letter
// of the expression, or in several for expand.
struct Algebra {
    var solution: Solution
    var details: Details
    var copyText: String
    var values: [Double]

    private enum Kind { case expand, factor, derivative, integral, limit }

    private static func plain(_ s: String) -> String { s.replacingOccurrences(of: "−", with: "-") }

    static func parse(_ input: String) -> Algebra? {
        let (order, typed) = orderOfDerivative(input.trimmingCharacters(in: .whitespaces))
        guard Options.algebra, let (kind, arguments, variable) = read(typed),
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
        case .expand: return expand(tokens, letters)
        case .factor: return factor(first, tokens, letters)
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
            steps.append(Step(label: "Taking out the common factor", math: row(t(cd == 1 ? "\(cn)" : "\(cn)/\(cd)"), t(" × "), t("("), polyMath(whole.map(Double.init), name), t(")"))))
        }
        if !roots.isEmpty {
            let values = ordered.map { "\(name) = \(fraction($0.0, $0.1))" }
            var seen: [String] = []
            for v in values where !seen.contains(v) { seen.append(v) }
            steps.append(Step(label: "Finding the rational roots", math: t(seen.joined(separator: ", "))))
        }
        steps.append(Step(label: irreducible ? "Testing for rational roots" : "Writing as a product of factors", math: irreducible ? nil : result,
                          note: irreducible ? "The polynomial has no rational root and no common factor; it cannot be factorised further over the rational numbers." : (leftover.isEmpty ? nil : "The factor remaining has no rational root.")))
        var d = Details(name: name, equation: expanded, steps: steps, solutions: [result], note: nil, f: { x in p.reversed().reduce(0) { $0 * x + $1 } }, roots: ordered.map { Double($0.0) / Double($0.1) })
        d.graph = nil
        let solution = Solution(exact: result.plain, approx: irreducible ? "Irreducible over the rational numbers" : nil)
        return Algebra(solution: solution, details: d, copyText: plain(result.plain), values: [])
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
        // Again for each order more, from the tidied form.
        for _ in 1..<max(order, 1) {
            guard let next = differentiated(cleaned(raw)) else { return nil }
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
        var steps = [Step(label: "Applying the rules of differentiation", math: row(t("\(operatorName) = "), typeset(cleaned(raw), name)))]
        _ = steps
        steps = []
        let rawShown = typeset(raw, name)
        if rawShown.plain != shown.plain { steps.append(Step(label: "Applying the rules of differentiation", math: row(t("\(operatorName) = "), rawShown))) }
        steps.append(Step(label: "Simplifying", math: row(t("\(operatorName) = "), shown)))
        var d = Details(name: name, equation: row(t("\(operatorName) "), original.plain.contains(" ") ? row(t("("), original, t(")")) : original), steps: steps,
                        solutions: [shown], note: nil, f: { result.eval($0) }, roots: [])
        d.graph = nil
        if let point, let at = try? Parser.constant(point), !at.hasUnknown {
            let x = at.eval(0), v = result.eval(x)
            guard v.isFinite else { return nil }
            let evaluation = Evaluation(name: nil, expr: .num(v))
            let line = evaluation.solution
            steps.append(Step(label: "Substituting \(name) = \(decimal(x))", math: t("= \(decimal(v))")))
            d.steps = steps
            d.solutions = [t(line?.exact ?? "= \(decimal(v))")] + (line?.approx.map { [t($0)] } ?? [])
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
        d.solutions = [t(line.exact)] + (line.approx.map { [t($0)] } ?? [])
        d.steps.append(Step(label: "Hence", math: t(line.exact)))
        return Algebra(solution: line, details: d, copyText: String(format: "%.12g", v), values: [v])
    }

    // MARK: Integrating

    private static func integral(_ expr: Expr, _ name: String, limits: [String]) -> Algebra? {
        let antiderivative = integrated(expr).map(cleaned)
        if limits.count == 2 {
            guard let lo = (try? Parser.constant(limits[0]))?.eval(0), let hi = (try? Parser.constant(limits[1]))?.eval(0), lo.isFinite, hi.isFinite else { return nil }
            var value = antiderivative.map { $0.eval(hi) - $0.eval(lo) } ?? numeric(expr, lo, hi)
            if !value.isFinite { value = numeric(expr, lo, hi) }
            value = Double(String(format: "%.13g", value)) ?? value
            let original = typeset(expr, name)
            var d = Details(name: name, equation: row(t("∫ from \(decimal(lo)) to \(decimal(hi)) of "), original, t(" d\(name)")), steps: [], solutions: [],
                            note: nil, f: { expr.eval($0) }, roots: [])
            if let F = antiderivative {
                d.steps.append(Step(label: "Finding an antiderivative", math: row(t("F(\(name)) = "), typeset(F, name))))
                d.steps.append(Step(label: "Evaluating F(b) − F(a)", math: t("F(\(decimal(hi))) − F(\(decimal(lo))) = \(decimal(F.eval(hi))) − \(decimal(F.eval(lo)))")))
            } else {
                d.steps.append(Step(label: "Integrating numerically", math: nil,
                                    note: "No antiderivative in closed form is known to the calculator; the integral is found by adaptive Gauss–Kronrod quadrature."))
            }
            let evaluation = Evaluation(name: nil, expr: .num(value))
            guard let line = evaluation.solution else { return nil }
            d.steps.append(Step(label: "Hence", math: t(line.exact)))
            d.solutions = [t(line.exact)] + (line.approx.map { [t($0)] } ?? [])
            return Algebra(solution: line, details: d, copyText: String(format: "%.12g", value), values: [value])
        }
        guard limits.isEmpty, let F = antiderivative else { return nil }
        let shown = typeset(F, name)
        let result = row(shown, t(" + C"))
        var d = Details(name: name, equation: row(t("∫ "), typeset(expr, name), t(" d\(name)")),
                        steps: [Step(label: "Integrating term by term", math: result)], solutions: [result], note: nil, f: { expr.eval($0) }, roots: [])
        d.graph = nil
        return Algebra(solution: Solution(exact: result.plain, approx: "The integral with respect to \(name), up to a constant C"), details: d, copyText: plain(result.plain), values: [])
    }

    // The coefficient and constant of a linear expression in the unknown: (2, 3) for 2x + 3.
    private static func linear(_ g: Expr) -> (a: Double, b: Double)? {
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
            return nil
        case .op("/", let a, let b):
            if !b.hasUnknown { return integrated(a).map { .op("/", $0, b) } }
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
