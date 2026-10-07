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
        // What was LaTeX is tidied as what is typed plainly is: bars, brackets and the like.
        // 30^\circ is 30°, {n \choose k} is \binom{n}{k}, and \left\| v \right\| is the length of v.
        s = s.replacingOccurrences(of: "\\^\\s*\\{?\\s*\\\\(?:circ|degree)\\s*\\}?", with: "°", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\{([^{}\\\\]*?)\\\\choose([^{}]*?)\\}", with: "\\\\binom{$1}{$2}", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\\\left\\\\\\|(.*?)\\\\right\\\\\\|", with: "norm($1)", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\\\lVert(.*?)\\\\rVert", with: "norm($1)", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\\\(?:no)?limits", with: "", options: .regularExpression)
        // x \in [0, 2\pi) says how far x goes, and with which bracket whether it reaches: the
        // brackets are all one thing once converted, so it is written as a chain of inequalities.
        if let interval = try? NSRegularExpression(pattern: "([A-Za-z])\\s*\\\\in\\s*([\\[(])([^,\\[\\]()]+),([^,\\[\\]()]+)([\\])])") {
            for match in interval.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
                guard let whole = Range(match.range, in: s), let v = Range(match.range(at: 1), in: s), let open = Range(match.range(at: 2), in: s),
                      let lo = Range(match.range(at: 3), in: s), let hi = Range(match.range(at: 4), in: s), let close = Range(match.range(at: 5), in: s) else { continue }
                s.replaceSubrange(whole, with: "\(s[lo]) \\\(s[open] == "[" ? "le" : "lt") \(s[v]) \\\(s[close] == "]" ? "le" : "lt") \(s[hi])")
            }
        }
        return convert(Substring(s)).map(Prose.tidy) ?? s
    }

    private static let names: [String: String] = [
        "cdot": "*", "times": "*", "div": "/", "pi": "π",
        "sin": "sin", "cos": "cos", "tan": "tan", "ln": "ln", "log": "log", "exp": "exp",
        "arcsin": "asin", "arccos": "acos", "arctan": "atan",
        "in": "∈", "lt": "<", "gt": ">", "to": "→", "rightarrow": "→", "longrightarrow": "→", "infty": "inf", "lim": "lim", "int": "∫",
        "sinh": "sinh", "cosh": "cosh", "tanh": "tanh", "sec": "sec", "csc": "csc", "cot": "cot",
        "gcd": "gcd", "max": "max", "min": "min", "det": "det", "arg": "arg", "deg": "°", "degree": "°", "circ": "°",
        "lg": "lg", "lb": "lb", "sign": "sign", "bmod": " mod ", "mod": " mod ", "pmod": " mod ",
        "lfloor": "floor(", "rfloor": ")", "lceil": "ceil(", "rceil": ")",
        "top": "T", "intercal": "T", "operatorname_tr": "trace", "lvert": "|", "rvert": "|", "vert": "|", "mid": "|",
        "land": " && ", "wedge": " && ", "lor": " || ", "vee": " || ", "lnot": " not ", "neg": " not ",
        "leqslant": "≤", "geqslant": "≥", "pm": "±", "cdots": " ", "ldots": " ", "dots": " ",
        "displaystyle": "", "limits": "", "nolimits": "", "textstyle": "",
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
                    else if next == "%" || next == "&" { out.append(next) }   // \% is a percentage
                    else if next == "|" { out += "|" }
                } else if name == "begin" || name == "end" {
                    // \begin{cases}, \begin{aligned}, …: the equations inside are what matter.
                    guard let (environment, after) = group(s, i) else { return nil }
                    i = after
                    // \begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix}: [[1, 2], [3, 4]]; a row or a column is a vector.
                    let kind = String(environment)
                    // \begin{array}{l}: the letters after it say how the columns are set, and are no part of it.
                    if name == "begin", kind == "array", let (_, afterSpec) = group(s, i) { i = afterSpec }
                    if name == "begin", ["matrix", "pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix", "smallmatrix"].contains(kind),
                       let close = s[i...].range(of: "\\end{\(kind)}") {
                        let rows = s[i..<close.lowerBound].components(separatedBy: "\\\\")
                            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                            .map { $0.components(separatedBy: "&") }
                        var cells: [[String]] = []
                        for row in rows {
                            var converted: [String] = []
                            for cell in row { guard let c = convert(Substring(cell)) else { return nil }; converted.append(c.trimmingCharacters(in: .whitespaces)) }
                            cells.append(converted)
                        }
                        guard !cells.isEmpty, cells.allSatisfy({ $0.count == cells[0].count }) else { return nil }
                        var literal: String
                        if cells.count == 1 || cells[0].count == 1 {
                            literal = "[" + cells.flatMap { $0 }.joined(separator: ",") + "]"
                        } else {
                            let rowTexts: [String] = cells.map { "[" + $0.joined(separator: ",") + "]" }
                            literal = "[" + rowTexts.joined(separator: ",") + "]"
                        }
                        let determinant = kind.hasPrefix("v") || kind.hasPrefix("V")
                        // \det \begin{pmatrix}…: the function is of the matrix that follows.
                        let before = out.trimmingCharacters(in: .whitespaces)
                        let applied = ["det", "inv", "rank", "trace", "transpose", "norm"].contains { before.hasSuffix($0) }
                        out += determinant ? "det(" + literal + ")" : applied ? "(" + literal + ")" : literal
                        i = close.upperBound
                    }
                } else if name == "left" || name == "right" {
                    // \left( is just (, but \left\{ and \right. only decorate a system.
                    if i < s.endIndex, s[i] == "." {
                        i = s.index(after: i)
                    } else if s[i...].hasPrefix("\\{") || s[i...].hasPrefix("\\}") {
                        i = s.index(i, offsetBy: 2)
                    }
                } else if ["mathrm", "operatorname", "mathbf", "boldsymbol", "mathit", "mathbb", "mathcal", "mathsf", "vec", "hat", "textit", "textrm"].contains(name) {
                    // Only the way a name is set: dm and \operatorname{mean} are the names themselves.
                    guard let (a, after) = group(s, i), let inner = convert(a) else { return nil }
                    out += inner
                    i = after
                } else if name == "overline" || name == "bar" {
                    guard let (a, after) = group(s, i), let inner = convert(a) else { return nil }
                    out += "conj(\(inner))"
                    i = after
                } else if name == "text" {
                    // Words in a formula are dropped, as a word would not parse anyway; but a
                    // unit, and the to and in between two of them, are kept: 5 \text{ km} \text{ to } \text{ mi}.
                    guard let (a, after) = group(s, i) else { return nil }
                    let word = a.trimmingCharacters(in: .whitespaces)
                    if ["to", "in", "into", "as", "at", "mod", "of", "off", "and", "or", "not"].contains(word.lowercased()) || Units.knows(word) { out += " \(word) " }
                    i = after
                } else if ["frac", "dfrac", "tfrac"].contains(name) {
                    guard let (a, afterA) = group(s, i), let (b, afterB) = group(s, afterA),
                          let top = convert(a), let bottom = convert(b) else { return nil }
                    // \frac{d}{dx}: the derivative with respect to x, applied to what follows.
                    if top == "d", bottom.count == 2, bottom.hasPrefix("d"), bottom.last!.isLetter {
                        out += "d/\(bottom) "
                    } else if top.range(of: "^d\\^\\(?(\\d+)\\)?$", options: .regularExpression) != nil, bottom.range(of: "^d[A-Za-z]\\^\\(?\\d+\\)?$", options: .regularExpression) != nil {
                        // \frac{d^2}{dx^2}: the second derivative.
                        out += "d\(top.filter(\.isNumber))/d\(bottom.dropFirst().first!)\(top.filter(\.isNumber)) "
                    } else {
                        out += "((\(top))/(\(bottom)))"
                    }
                    i = afterB
                } else if ["binom", "dbinom", "tbinom"].contains(name) {
                    guard let (a, afterA) = group(s, i), let (b, afterB) = group(s, afterA),
                          let n = convert(a), let k = convert(b) else { return nil }
                    out += "comb((\(n)),(\(k)))"
                    i = afterB
                } else if name == "log", i < s.endIndex, s[i] == "_" {
                    // \log_2 8 and \log_{2}{8}: the logarithm of 8 to base 2.
                    guard let (b, afterBase) = group(s, s.index(after: i)), let base = convert(b),
                          let (argument, after) = argument(s, afterBase), let inner = convert(argument) else { return nil }
                    out += "log((\(inner)),(\(base)))"
                    i = after
                } else if name == "lim" {
                    // \lim_{x\to 0} f(x): the limit of what follows.
                    var j = i
                    while j < s.endIndex, s[j] == " " { j = s.index(after: j) }
                    guard j < s.endIndex, s[j] == "_", let (b, afterBound) = group(s, s.index(after: j)), let bound = convert(b) else { return nil }
                    let parts = bound.components(separatedBy: "→")
                    guard parts.count == 2, let body = convert(s[afterBound...]) else { return nil }
                    out += "limit((\(body.trimmingCharacters(in: .whitespaces))),\(parts[0].trimmingCharacters(in: .whitespaces)),\(parts[1].trimmingCharacters(in: .whitespaces)))"
                    i = s.endIndex
                } else if name == "int" {
                    out += "∫"
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

    // What a function is applied to: a braced group, a bracketed one, or a run of digits or letters.
    private static func argument(_ s: Substring, _ start: Substring.Index) -> (Substring, Substring.Index)? {
        var i = start
        while i < s.endIndex, s[i] == " " { i = s.index(after: i) }
        guard i < s.endIndex else { return nil }
        if s[i] == "{" { return group(s, i) }
        if s[i] == "(" {
            var depth = 0, j = i
            while j < s.endIndex {
                if s[j] == "(" { depth += 1 }
                if s[j] == ")" { depth -= 1; if depth == 0 { return (s[i...j], s.index(after: j)) } }
                j = s.index(after: j)
            }
            return nil
        }
        var j = i
        while j < s.endIndex, s[j].isNumber || s[j] == "." || (s[j].isLetter && s[j].isASCII) { j = s.index(after: j) }
        return j > i ? (s[i..<j], j) : nil
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
        // π by itself, as a calculator gives it; e, c and the like are too often only a letter.
        if plain, ["pi", "π"].contains(input.trimmingCharacters(in: .whitespaces).lowercased()) {
            return Evaluation(name: nil, expr: .num(.pi))
        }
        // Two numbers side by side are no sum: 2026 10. Except in sin^2 30, where the power is the function's.
        if plain, let tokens = try? Parser.tokenize(input),
           tokens.indices.dropLast().contains(where: { i in
               guard case .number = tokens[i], case .number = tokens[i + 1] else { return false }
               if i >= 2, tokens[i - 1] == .symbol("^"), case .function = tokens[i - 2] { return false }
               return true
           }) { return nil }
        let named = (try? Parser.tokenize(input))?.contains(where: { if case .named = $0 { true } else { false } }) == true
        if parts.count == 1, !plain || named || input.contains(where: { $0.isNumber || "+-*/^()!√×÷−%".contains($0) }),
           let expr = try? Parser.constant(input, physical: !plain), isWork(expr) {
            return Evaluation(name: nil, expr: expr)
        }
        // A number written in scientific notation, 2.5e-3, is given as it is: the one number worth
        // a card by itself.
        if plain, parts.count == 1, input.range(of: "^\\s*[0-9.]+[eE][-+]?[0-9]+\\s*$", options: .regularExpression) != nil,
           let expr = try? Parser.constant(input, physical: false) {
            return Evaluation(name: nil, expr: expr)
        }
        return nil
    }

    // Whether it is a word given a plain number, cost = 90, where the word has a function's name
    // in it and would otherwise be read as cos t.
    static func namesNumber(_ input: String) -> Bool {
        let parts = input.split(separator: "=", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let name = parts[0].trimmingCharacters(in: .whitespaces)
        guard name.range(of: "^[A-Za-z][A-Za-z0-9]+$", options: .regularExpression) != nil,
              let tokens = try? Parser.tokenize(name), tokens.contains(where: { if case .function = $0 { true } else { false } }),
              let value = try? Parser.constant(String(parts[1])) else { return false }
        return !isWork(value)
    }

    // Something to work out; "a = 1" is not.
    private static func isWork(_ e: Expr) -> Bool {
        switch e {
        case .num: return false
        case .neg(let a): return isWork(a)
        default: return true
        }
    }

    private func lead(_ name: String?) -> String { name.map { "\($0) " } ?? "" }

    var solution: Solution? {
        let v = value
        // What no number is the answer to, said so and not left blank.
        if !v.isFinite {
            // The square root of a negative number is imaginary: √−4 is 2i.
            if case .call("sqrt", let a) = expr, !a.hasUnknown, a.eval(0) < 0 {
                let m = -a.eval(0)
                let im = m.squareRoot()
                if m == m.rounded(), m < 1e12 {
                    let (k, rest) = squareFactor(Int(m))
                    let exact = rest == 1 ? "\(k == 1 ? "" : "\(k)")i" : "\(k == 1 ? "" : "\(k)")√\(rest) i"
                    return Solution(exact: "\(lead(name))= \(exact)", approx: rest == 1 ? "An imaginary number" : "≈ \(decimal(im))i")
                }
                return Solution(exact: "\(lead(name))≈ \(decimal(im))i", approx: "An imaginary number")
            }
            if let why = expr.undefinedReason { return Solution(exact: "Undefined", approx: why) }
            // A root or a logarithm of a negative number, inside a larger sum: complex.
            if v.isNaN, let z = ComplexValue.evaluate(expr), z.isFinite { return ComplexValue(value: ComplexValue.snapped(z), expr: expr).solution }
            if v.isNaN { return Solution(exact: "Undefined", approx: "It has no real value.") }
            return Solution(exact: "Too large", approx: "It is beyond the largest number that can be held, about 1.8×10³⁰⁸.")
        }
        let lead = name.map { "\($0) " } ?? ""
        // An angle, from asin, acos or atan: in the unit it was worked out in, π/6 where it is
        // that, with the other unit beneath.
        if case .call(let f, _) = expr, let (inDegrees, _) = Angle.givesAngle(f), expr.constants.isEmpty {
            let radians = inDegrees ? v * .pi / 180 : v, degrees = inDegrees ? v : v * 180 / .pi
            let fraction = Options.exact ? piFraction(radians)?.plain : nil
            let whole = wholeDegrees(degrees)
            let inRadians = fraction.map { "= \($0)" } ?? "≈ \(decimal(radians))"
            let inDegreeMeasure = "\(whole ? "=" : "≈") \(degreesText(degrees))"
            return inDegrees ? Solution(exact: lead + inDegreeMeasure, approx: inRadians + " rad")
                             : Solution(exact: lead + inRadians, approx: inDegreeMeasure)
        }
        // A whole number too long for the machine's sixteen figures is written out in full.
        if expr.constants.isEmpty, abs(v) >= 1e15, let big = expr.exactInteger, big.digitCount <= 60 {
            return Solution(exact: "\(lead)= \(big.description)", approx: "≈ \(decimal(v))")
        }
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
        if let (p, q) = rational(v), p != 0 {
            // A decimal first, and the fraction beneath it, unless the fraction is asked to come first.
            if Options.decimalFirst {
                // = where the decimal is the whole of it, 2.5; ≈ where it is cut short, 0.333333.
                let shown = decimal(v)
                let whole = Double(shown.replacingOccurrences(of: "−", with: "-")).map { abs($0 - v) <= 1e-13 * max(1, abs(v)) } ?? false
                return Solution(exact: "\(lead)\(whole ? "=" : "≈") \(shown)", approx: "= \(fraction(p, q))")
            }
            return Solution(exact: "\(lead)= \(fraction(p, q))", approx: "≈ \(decimal(v))")
        }
        return Solution(exact: "\(lead)≈ \(decimal(v))", approx: nil)
    }
}


// What is typed into Spotlight is mostly not mathematics, and what is not must bring up no card:
// r2d2, 9to5mac, wi-fi 6, 5 ft 10, 2026-10-06, $100. This is the test of whether it is words, a
// price or a date, and not letters and numbers to be worked.
enum Prose {
    static func reads(_ input: String) -> Bool {
        if input.contains("\\") { return false }
        // 5 km to miles is a quantity and its unit, which are words with numbers.
        if Conversion.parse(input) != nil || Algebra.parse(input) != nil { return false }
        // A single $ is a price; a pair is LaTeX's brackets.
        if input.filter({ $0 == "$" }).count == 1 { return true }
        // Dates, 2026-10-06 and 10/6/2026.
        if input.range(of: "\\d{4}-\\d{1,2}-\\d{1,2}|\\d{1,2}/\\d{1,2}/\\d{2,4}", options: .regularExpression) != nil { return true }
        // A number with noughts in front of it is a code, not a quantity: 007.
        if input.range(of: "^\\s*0[0-9]+\\s*$", options: .regularExpression) != nil { return true }

        // A letter with a digit straight after it, m1 and e2e, or a digit and a letter and a
        // digit, 9to5: not algebra. A function with its argument, log2, ans2 and 1e5 are.
        var spelled = input
        for name in Functions.names + ["ans", "Ans"] {
            spelled = spelled.replacingOccurrences(of: "\(name)[0-9]", with: " ", options: .regularExpression)
        }
        spelled = spelled.replacingOccurrences(of: "[0-9.][eE][-+]?[0-9]", with: " ", options: .regularExpression)
        // Beside a term written with a subscript, u_5 = 29, a u1 is a slip for u_1, and is the sequence's.
        let sequence = input.contains("=") && input.range(of: "(?<![A-Za-z0-9_])[A-Za-z]_\\{?[0-9]+\\}?\\s*=", options: .regularExpression) != nil
        if !sequence, spelled.range(of: "[A-Za-z][0-9]|[0-9][A-Za-z]+[0-9]", options: .regularExpression) != nil { return true }

        // Two things side by side with only a space between, one of them a word: 5 ft 10, wi-fi 6.
        // 2 x and sin x are not words, x being a letter and sin a name.
        var known = Set(Functions.names + Array(Greek.names.keys) + ["pi", "ans", "Ans", "clip", "of", "deg", "rad", "mod"])
        // and, or and not are words of the language of statements, where there is a relation.
        if input.contains(where: { "=<>≈≠≤≥".contains($0) }) { known.formUnion(["and", "or", "not", "AND", "OR", "NOT", "And", "Or", "Not"]) }
        // x in [0, 2π) is how far x goes.
        if input.range(of: "(?<![A-Za-z])[A-Za-z]\\s+in\\s+[\\[(]", options: .regularExpression) != nil { known.insert("in") }
        func word(_ run: Substring) -> Bool { run.count >= 2 && run.allSatisfy({ $0.isLetter && $0.isASCII }) && !known.contains(String(run)) }
        var runs: [(text: Substring, spaceBefore: Bool)] = []
        var current = input.startIndex, spaced = false
        while current < input.endIndex {
            let c = input[current]
            if c.isLetter && c.isASCII || c.isNumber {
                var end = current
                while end < input.endIndex, input[end].isLetter && input[end].isASCII || input[end].isNumber { end = input.index(after: end) }
                runs.append((input[current..<end], spaced))
                spaced = false
                current = end
            } else {
                // Only spaces between two runs keep them side by side; anything else parts them.
                if c == " " && !runs.isEmpty && current > input.startIndex && (input[input.index(before: current)].isLetter || input[input.index(before: current)].isNumber || input[input.index(before: current)] == " ") { spaced = true } else { spaced = false }
                current = input.index(after: current)
            }
        }
        return zip(runs, runs.dropFirst()).contains { ($1.spaceBefore) && (word($0.text) || word($1.text)) }
    }
}

extension Prose {
    // What people type for arithmetic, said the way the parser reads it: 1,000 + 250, 2**8, 3 x 4,
    // 0xFF, log2(8), and =2+2 or 2+2= as a calculator would show it. Left alone where it means
    // something else: x+y=3, x-y=1 has a comma, and x=? is a question.
    static func tidy(_ input: String) -> String {
        let input = halfwidth(input)
        if input.contains("\\") { return input }
        var s = input
        s = balanced(s)
        // "solve 2x+3=7", "find x: 2x=6", "2x+3=7 solve for x", "what is 15% of 80".
        s = s.replacingOccurrences(of: "^\\s*(?:solve|find)\\s+(?:for\\s+)?([A-Za-z])\\s*[:,]\\s*(.+=.+)$", with: "$2, $1=?", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "^\\s*(?:please\\s+)?(?:solve|find|calculate|calc|compute|evaluate|work\\s+out|what\\s+is|what's|whats)\\s*[:,]?\\s+(?=\\S)", with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "^(.+=.+?)\\s*[,;]?\\s+(?:solve\\s+for|solved\\s+for|find|for)\\s+([A-Za-z])\\s*$", with: "$1, $2=?", options: [.regularExpression, .caseInsensitive])
        func replace(_ pattern: String, _ template: String) {
            s = s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        // 1,000,000: a comma between groups of three, with no digit before the first group or
        // after the last.
        let grouped = try! NSRegularExpression(pattern: "(?<![0-9,.])[0-9]{1,3}(,[0-9]{3})+(?![0-9])")
        for match in grouped.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
            guard let range = Range(match.range, in: s), !insideCall(s, before: range.lowerBound) else { continue }
            s.replaceSubrange(range, with: s[range].replacingOccurrences(of: ",", with: ""))
        }
        replace("\\*\\*", "^")
        // 0xFF and 0b1010 are numbers in other bases.
        for (prefix, radix) in [("0[xX]", 16), ("0[bB]", 2)] {
            let digits = radix == 16 ? "[0-9a-fA-F]{1,15}" : "[01]{1,50}"
            while let range = s.range(of: "(?<![0-9A-Za-z])\(prefix)\(digits)(?![0-9A-Za-z])", options: .regularExpression),
                  let value = Int(s[range].dropFirst(2), radix: radix) {
                s.replaceSubrange(range, with: String(value))
            }
        }
        // 3 x 4 and 3x4 are three times four.
        replace("(?<=[0-9])\\s*[xX×]\\s*(?=[0-9])", "*")
        // log2(8): the logarithm to base 2, log10 the one that log is.
        replace("log10\\(", "log(")
        while let range = s.range(of: "log2(") {
            var depth = 1, end = range.upperBound
            while end < s.endIndex, depth > 0 {
                if s[end] == "(" { depth += 1 } else if s[end] == ")" { depth -= 1 }
                end = s.index(after: end)
            }
            guard depth == 0 else { break }
            let inner = s[range.upperBound..<s.index(before: end)]
            s.replaceSubrange(range.lowerBound..<end, with: "(ln(\(inner))/ln(2))")
        }
        // 1 1/2 + 2 3/4: mixed numbers, a whole number and a fraction less than one.
        if let mixed = try? NSRegularExpression(pattern: "(?<![0-9./^])([0-9]+)\\s+([0-9]+)/([0-9]+)(?![0-9./])") {
            for match in mixed.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
                guard let whole = Range(match.range, in: s), let n = Range(match.range(at: 2), in: s), let d = Range(match.range(at: 3), in: s),
                      let top = Int(s[n]), let bottom = Int(s[d]), top < bottom, let w = Range(match.range(at: 1), in: s) else { continue }
                s.replaceSubrange(whole, with: "(\(s[w])+\(top)/\(bottom))")
            }
        }
        // 1+2+3+…+100 and 2+4+6+...+20: a run of terms with a constant step; 1*2*…*5 the same for a product.
        if let run = try? NSRegularExpression(pattern: "^\\s*([0-9]+(?:\\s*[+*×]\\s*[0-9]+)+?)\\s*([+*×])\\s*(?:\\.\\.\\.|…|⋯)\\s*\\2\\s*([0-9]+)\\s*$"),
           let m = run.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
           let head = Range(m.range(at: 1), in: s), let op = Range(m.range(at: 2), in: s), let tail = Range(m.range(at: 3), in: s) {
            let terms = s[head].split(whereSeparator: { "+*× ".contains($0) }).compactMap { Int($0) }
            if let last = Int(s[tail]), terms.count >= 2 {
                let step = terms[1] - terms[0]
                let steady = zip(terms, terms.dropFirst()).allSatisfy { $1 - $0 == step }
                if steady, step != 0, (last - terms[0]) % step == 0, (last - terms[0]) / step >= terms.count - 1 {
                    let n = (last - terms[0]) / step
                    s = "\(s[op] == "+" ? "sum" : "prod")(k,0,\(n),\(terms[0])+\(step)*k)"
                }
            }
        }
        // sum of 1 to 100
        replace("^\\s*sum\\s+(?:of\\s+)?(?:from\\s+)?([0-9]+)\\s+to\\s+([0-9]+)\\s*$", "sum(k,$1,$2,k)")
        // $12.50 * 3 and 5€ + 2: the sign of the money is no part of the sum. Alone, $100 is a price.
        if s.contains(where: { "+-*/^%×÷".contains($0) }), s.contains(where: { "$€£¥".contains($0) }) {
            replace("[€£¥]", "")
            replace("\\$(?=[0-9.])|(?<=[0-9.])\\$", "")
        }
        // 20% off 80 is 80 less 20% of it.
        replace("([0-9.]+)\\s*%\\s*off\\s+([0-9.]+)", "$2*(1-$1%)")
        // |x| is the size of x, where the bars come in pairs and are none of the || of logic.
        if !s.contains("||"), s.filter({ $0 == "|" }).count >= 2, s.filter({ $0 == "|" }).count % 2 == 0 {
            var open = true, out = ""
            for c in s { if c == "|" { out += open ? "abs(" : ")"; open.toggle() } else { out.append(c) } }
            s = out
        }
        // mean([1, 2, 3]) and median({3, 1, 2}): the list is the arguments.
        let listFunctions = Lists.names + ["min", "max", "gcd", "lcm"]
        replace("(\(listFunctions.joined(separator: "|")))\\(\\s*[\\[{]([^\\[\\]{}()]*)[\\]}]\\s*\\)", "$1($2)")
        // 17 mod 5 is a remainder, as 17 % 5.
        replace("(?<=[0-9)])\\s+mod\\s+(?=[0-9(-])", " % ")
        // 5C2 and 5P2: the ways of choosing, and of arranging.
        replace("(?<![A-Za-z0-9.])([0-9]+)\\s*C\\s*([0-9]+)(?![A-Za-z0-9.])", "($1)⒞($2)")
        replace("(?<![A-Za-z0-9.])([0-9]+)\\s*P\\s*([0-9]+)(?![A-Za-z0-9.])", "($1)⒫($2)")
        // Functions of two numbers, written between their brackets; the reciprocal functions as
        // one over the one they are.
        // Two matrices side by side are multiplied: [[1,2],[3,4]][[0,1],[1,0]].
        replace("\\]\\s*\\[\\[", "]*[[")
        replace("\\]\\]\\s*\\[", "]]*[")
        // 1 << 4 and 6 >> 1 move the bits, 12 & 10 keeps those in both; written as one thing.
        replace("<<", "⇇")
        replace(">>", "⇉")
        replace("(?<![&])&(?![&])", "⋀")
        for (name, symbol) in [("gcd", "⊓"), ("lcm", "⊔"), ("min", "↓"), ("max", "↑"), ("xor", "⊻"), ("bor", "⋁"), ("band", "⋀")] {
            rewrite(&s, name) { $0.count >= 2 ? $0.dropFirst().reduce("(" + $0[0] + ")") { "(\($0)\(symbol)(\($1)))" } : nil }
        }
        for (name, symbol) in [("nCr", "⒞"), ("comb", "⒞"), ("binom", "⒞"), ("nPr", "⒫"), ("perm", "⒫"), ("round", "⌖"), ("log", "⒧"), ("atan2", "⒜")] {
            rewrite(&s, name) { $0.count == 2 ? "((\($0[0]))\(symbol)(\($0[1])))" : nil }
        }
        for (name, symbol) in [("C", "⒞"), ("P", "⒫")] {
            rewrite(&s, name, caseSensitive: true) { $0.count == 2 && $0.allSatisfy({ $0.range(of: "^[0-9]+$", options: .regularExpression) != nil }) ? "((\($0[0]))\(symbol)(\($0[1])))" : nil }
        }
        rewrite(&s, "mod") { $0.count == 2 ? "((\($0[0]))%(\($0[1])))" : nil }
        // =2+2, and 2+2= or 2+2=? : the answer asked for. Not x=? , which names a letter.
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("="), trimmed.dropFirst().contains(where: { $0.isNumber }), trimmed.dropFirst().contains(where: { "+-*/^%()!".contains($0) }), !trimmed.dropFirst().contains("=") {
            s = String(trimmed.dropFirst())
        } else if let range = trimmed.range(of: "\\s*=\\s*\\??\\s*$", options: .regularExpression) {
            let before = trimmed[..<range.lowerBound]
            if before.contains(where: { $0.isNumber }), before.contains(where: { "+-*/^%()!".contains($0) }), !before.contains("="), !before.contains(where: { $0.isLetter }) { s = String(before) }
        }
        return s
    }
}

extension Prose {
    // name(a, b, …) with each call, the innermost first, put in the form the closure gives for its
    // arguments; left as it is where the closure gives nothing.
    static func rewrite(_ s: inout String, _ name: String, caseSensitive: Bool = false, _ make: ([String]) -> String?) {
        var limit = s.count
        let options: String.CompareOptions = caseSensitive ? [.regularExpression, .backwards] : [.regularExpression, .backwards, .caseInsensitive]
        while let found = s.range(of: "(?<![A-Za-z0-9_])\(name)\\(", options: options,
                                  range: s.startIndex..<s.index(s.startIndex, offsetBy: limit)) {
            limit = s.distance(from: s.startIndex, to: found.lowerBound)
            var depth = 1, arguments: [String] = [], current = "", i = found.upperBound
            while i < s.endIndex, depth > 0 {
                let c = s[i]
                if c == "(" { depth += 1; current.append(c) }
                else if c == ")" { depth -= 1; if depth > 0 { current.append(c) } }
                else if c == ",", depth == 1 { arguments.append(current); current = "" }
                else { current.append(c) }
                i = s.index(after: i)
            }
            guard depth == 0 else { continue }
            arguments.append(current)
            guard let replacement = make(arguments.map { $0.trimmingCharacters(in: .whitespaces) }) else { continue }
            s.replaceSubrange(found.lowerBound..<i, with: replacement)
        }
    }
}

extension Prose {
    // Whether the place is in the brackets of a function, where a comma parts the arguments:
    // max(470,323) is two numbers, and not 470323.
    static func insideCall(_ s: String, before index: String.Index) -> Bool {
        var open: [Bool] = []   // each bracket still open: whether a letter came before it
        var previous: Character?
        for c in s[..<index] {
            if c == "(" { open.append(previous.map { $0.isLetter } ?? false) }
            else if c == ")" { _ = open.popLast() }
            previous = c
        }
        return open.contains(true)
    }
}

extension Prose {
    // What a Chinese input method types for the keys of an equation: （x＋1）＾２ is (x+1)^2. The
    // full-width forms of the ASCII characters, and the few punctuation marks that stand for one.
    static func halfwidth(_ input: String) -> String {
        guard input.unicodeScalars.contains(where: { $0.value > 0x7F }) else { return input }
        var out = String.UnicodeScalarView()
        for scalar in input.unicodeScalars {
            switch scalar.value {
            case 0xFF01...0xFF5E: out.append(Unicode.Scalar(scalar.value - 0xFEE0)!)
            case 0x3000: out.append(" ")
            case 0x3002: out.append(".")
            case 0x3001: out.append(",")
            case 0xFE3F, 0x2038: out.append("^")
            case 0xFE35, 0xFE59: out.append("(")
            case 0xFE36, 0xFE5A: out.append(")")
            case 0x300C, 0x300D, 0x201C, 0x201D: out.append("\"")
            case 0x2018, 0x2019: out.append("'")
            default: out.append(scalar)
            }
        }
        return String(out)
    }
}

extension Prose {
    // 29-12)/5 is (29-12)/5: a bracket that closes what was never opened is taken to have been
    // opened at the start of what is being typed, the thought having come after the number. One
    // left open is not closed for the sake of a card: it is not finished. Text in quotation marks
    // is left alone.
    static func balanced(_ input: String) -> String {
        guard input.contains("(") || input.contains(")") else { return input }
        var chars = Array(input)
        // Where each separator is, outside quotation marks, and each bracket.
        func scan() -> (unmatched: Int?, open: Int) {
            var stack: [Character] = [], quote: Character?
            for (i, c) in chars.enumerated() {
                if let q = quote { if c == q { quote = nil }; continue }
                if c == "\"" || c == "“" { quote = c == "“" ? "”" : c; continue }
                // [0, 2π) is an interval, whose ends are not alike: any closer closes any opener.
                if "([{".contains(c) { stack.append(c) }
                else if ")]}".contains(c) { if stack.isEmpty { return (i, 0) }; stack.removeLast() }
            }
            return (nil, stack.count)
        }
        var guardCount = 0
        while let i = scan().unmatched, guardCount < 8 {
            guardCount += 1
            // The start of this part: after the last = , ; < > or && || before it, at the top level.
            var start = 0, depth = 0
            for j in 0..<i {
                if "([{".contains(chars[j]) { depth += 1 } else if ")]}".contains(chars[j]) { depth -= 1 }
                if depth == 0, "=,;<>".contains(chars[j]) { start = j + 1 }
                if depth == 0, j > 0, (chars[j] == "&" && chars[j - 1] == "&") || (chars[j] == "|" && chars[j - 1] == "|") { start = j + 1 }
            }
            while start < i, chars[start] == " " { start += 1 }
            chars.insert("(", at: start)
        }
        return String(chars)
    }
}
