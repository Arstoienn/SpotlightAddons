import Foundation

// Formulas are often copied as LaTeX: \frac{a}{b}, \sqrt{x}, x^{2}, \cdot, \left( \right),
// wrapped in \( \) or $ $. This turns them into the plain form the parser reads; anything it
// does not know (\le, subscripts, matrices) makes it give up, and the input is left alone.
enum Latex {
    static func plain(_ input: String) -> String {
        // Pasted LaTeX often comes over several lines.
        var s = input.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        for delimiter in ["\\(", "\\)", "\\[", "\\]", "$"] { s = s.replacingOccurrences(of: delimiter, with: "") }
        guard s.contains("\\") || s.contains("{") else { return s }
        return convert(Substring(s)) ?? s
    }

    private static let names: [String: String] = [
        "cdot": "*", "times": "*", "div": "/", "pi": "π",
        "sin": "sin", "cos": "cos", "tan": "tan", "ln": "ln", "log": "log", "exp": "exp",
        "arcsin": "asin", "arccos": "acos", "arctan": "atan",
        "approx": "≈", "ne": "≠", "neq": "≠", "le": "≤", "leq": "≤", "ge": "≥", "geq": "≥",
        "theta": "θ", "omega": "ω", "lambda": "λ", "alpha": "α", "beta": "β", "phi": "φ", "varphi": "φ",
        "rho": "ρ", "tau": "τ", "mu": "μ",
        // spacing
        "quad": " ", "qquad": " ", "enspace": " ", "thinspace": " ", "medspace": " ", "thickspace": " ",
    ]

    private static func convert(_ s: Substring) -> String? {
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            i = s.index(after: i)
            switch c {
            case "\\":
                var name = ""
                while i < s.endIndex, s[i].isLetter { name.append(s[i]); i = s.index(after: i) }
                if name.isEmpty {
                    // \, \; \! and "\ " are spacing; \{ \} are braces; \\ ends a line, which in
                    // a system of equations ends one equation.
                    guard i < s.endIndex else { break }
                    let next = s[i]
                    i = s.index(after: i)
                    if next == "{" { out += "(" } else if next == "}" { out += ")" } else if next == "\\" { out += ";" }
                } else if name == "begin" || name == "end" {
                    // \begin{cases}, \begin{aligned}, …: the equations inside are what matter.
                    guard let (_, after) = group(s, i) else { return nil }
                    i = after
                } else if name == "left" || name == "right" {
                    // \left( is just (, but \left\{ and \right. only decorate a system.
                    if i < s.endIndex, s[i] == "." {
                        i = s.index(after: i)
                    } else if s[i...].hasPrefix("\\{") || s[i...].hasPrefix("\\}") {
                        i = s.index(i, offsetBy: 2)
                    }
                } else if name == "text" || name == "mathrm" {
                    // Words in a formula: dropped, as a word would not parse anyway.
                    guard let (_, after) = group(s, i) else { return nil }
                    i = after
                } else if ["frac", "dfrac", "tfrac"].contains(name) {
                    guard let (a, afterA) = group(s, i), let (b, afterB) = group(s, afterA),
                          let top = convert(a), let bottom = convert(b) else { return nil }
                    out += "((\(top))/(\(bottom)))"
                    i = afterB
                } else if name == "sqrt" {
                    var index: String?
                    if i < s.endIndex, s[i] == "[", let close = s[i...].firstIndex(of: "]") {
                        guard let n = convert(s[s.index(after: i)..<close]) else { return nil }
                        index = n
                        i = s.index(after: close)
                    }
                    guard let (a, after) = group(s, i), let inner = convert(a) else { return nil }
                    out += index.map { "((\(inner))^(1/(\($0))))" } ?? "sqrt(\(inner))"
                    i = after
                } else if name == "sum" || name == "prod" {
                    guard let (sum, after) = bigOperator(name, s, i) else { return nil }
                    out += sum
                    i = after
                } else if let plain = names[name] {
                    out += plain
                } else {
                    return nil
                }
            case "{", "[": out += "("
            case "}", "]": out += ")"
            case "&": break   // alignment in aligned and cases
            case "_":
                // F_{net} is the subscript the parser reads as F_net.
                guard i < s.endIndex, s[i] == "{", let (inner, after) = group(s, i) else { out.append(c); break }
                out += "_" + inner
                i = after
            default: out.append(c)
            }
        }
        return out
    }

    // \sum_{k=a}^{b} term → sum(k,a,b,term). The term runs to the next + or − (or =, or closing
    // bracket) outside any brackets, as it is read on paper: \sum_{k=1}^{n} k + 1 adds 1 once.
    private static func bigOperator(_ name: String, _ s: Substring, _ start: Substring.Index) -> (String, Substring.Index)? {
        var i = start, lower: String?, upper: String?
        for _ in 0..<2 {
            while i < s.endIndex, s[i] == " " { i = s.index(after: i) }
            guard i < s.endIndex, s[i] == "_" || s[i] == "^" else { break }
            let isLower = s[i] == "_"
            guard let (g, after) = group(s, s.index(after: i)), let text = convert(g) else { return nil }
            if isLower { lower = text } else { upper = text }
            i = after
        }
        guard let lower, let upper else { return nil }
        let bounds = lower.split(separator: "=", maxSplits: 1)
        guard bounds.count == 2 else { return nil }
        let k = bounds[0].trimmingCharacters(in: .whitespaces)
        guard k.count == 1, k.first!.isLetter, k.first!.isASCII else { return nil }

        let termStart = i
        var depth = 0
        while i < s.endIndex {
            let c = s[i]
            if "({[".contains(c) { depth += 1 }
            if ")}]".contains(c) { if depth == 0 { break }; depth -= 1 }
            if depth == 0, "+-=".contains(c), s[termStart..<i].contains(where: { $0 != " " }) { break }
            i = s.index(after: i)
        }
        guard let term = convert(s[termStart..<i]), !term.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return ("\(name)(\(k),(\(bounds[1])),(\(upper)),(\(term)))", i)
    }

    // A braced argument, or else the single character after any spaces, as in \frac12.
    private static func group(_ s: Substring, _ start: Substring.Index) -> (Substring, Substring.Index)? {
        var i = start
        while i < s.endIndex, s[i] == " " { i = s.index(after: i) }
        guard i < s.endIndex else { return nil }
        guard s[i] == "{" else { return (s[i...i], s.index(after: i)) }
        var depth = 0
        var j = i
        while j < s.endIndex {
            if s[j] == "{" { depth += 1 }
            if s[j] == "}" {
                depth -= 1
                if depth == 0 { return (s[s.index(after: i)..<j], s.index(after: j)) }
            }
            j = s.index(after: j)
        }
        return nil
    }
}

// "PES = (some arithmetic)": a name on the left and only numbers on the right is a value to
// work out, not an equation to solve. So is arithmetic with no = at all, 2+2 and 5!/(3!2!).
struct Evaluation {
    var name: String?
    var expr: Expr

    var value: Double { expr.eval(0) }

    static func parse(_ input: String, hadLatex: Bool) -> Evaluation? {
        let parts = input.split(separator: "=", omittingEmptySubsequences: false)
        if parts.count == 2 {
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            let reserved = Functions.names + ["pi", "e", "ans", "Ans", "clip"]
            guard name.range(of: "^[A-Za-z][A-Za-z0-9]*(_([A-Za-z]+|[0-9]+))?$", options: .regularExpression) != nil,
                  !reserved.contains(name),
                  let expr = try? Parser.constant(String(parts[1]), naming: name), isWork(expr) else { return nil }
            // theta and mu_k are shown as θ and μ_k.
            let pieces = name.split(separator: "_", maxSplits: 1).map(String.init)
            let shown = ([Greek.names[pieces[0]] ?? pieces[0]] + pieces.dropFirst()).joined(separator: "_")
            return Evaluation(name: shown, expr: expr)
        }
        // Typed plainly, it must look like arithmetic, a digit or an operator in it, no letter
        // standing for a constant and no two numbers side by side, so that a search for "pie",
        // "c" or "2026 10" brings up no card.
        let plain = !hadLatex
        if plain, parts.count == 1, !Options.arithmetic { return nil }
        if plain, let tokens = try? Parser.tokenize(input),
           zip(tokens, tokens.dropFirst()).contains(where: { if case (.number, .number) = $0 { true } else { false } }) { return nil }
        let named = (try? Parser.tokenize(input))?.contains(where: { if case .named = $0 { true } else { false } }) == true
        if parts.count == 1, !plain || named || input.contains(where: { $0.isNumber || "+-*/^()!√×÷−".contains($0) }),
           let expr = try? Parser.constant(input, physical: !plain), isWork(expr) {
            return Evaluation(name: nil, expr: expr)
        }
        return nil
    }

    // Something to work out; "a = 1" is not.
    private static func isWork(_ e: Expr) -> Bool {
        switch e {
        case .num: return false
        case .neg(let a): return isWork(a)
        default: return true
        }
    }

    var solution: Solution? {
        let v = value
        guard v.isFinite else { return nil }
        let lead = name.map { "\($0) " } ?? ""
        // Worked out from a physical constant, itself only a few figures: a decimal, not a fraction.
        let constants = expr.constants
        if !constants.isEmpty { return Solution(exact: lead + approxOrEqual(v), approx: "Taking " + Constants.values(constants)) }
        // Decimals only, where that is what is asked for: = where the decimal is the whole of it,
        // as 2.5 is of 10/4, and ≈ where it is cut short.
        if !Options.exact {
            let whole = Double(String(format: "%.\(Options.figures - 1)e", v)).map { abs($0 - v) <= 1e-12 * abs(v) } ?? false
            return Solution(exact: "\(lead)\(whole ? "=" : "≈") \(decimal(v))", approx: nil)
        }
        if isExact(v) { return Solution(exact: "\(lead)= \(decimal(v))", approx: nil) }
        if let (p, q) = rational(v), p != 0 { return Solution(exact: "\(lead)= \(fraction(p, q))", approx: "≈ \(decimal(v))") }
        return Solution(exact: "\(lead)≈ \(decimal(v))", approx: nil)
    }
}
