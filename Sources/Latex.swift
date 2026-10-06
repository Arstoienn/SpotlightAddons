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
        if parts.count == 1, !plain || named || input.contains(where: { $0.isNumber || "+-*/^()!√×÷−%".contains($0) }),
           let expr = try? Parser.constant(input, physical: !plain), isWork(expr) {
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

    var solution: Solution? {
        let v = value
        guard v.isFinite else { return nil }
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


// What is typed into Spotlight is mostly not mathematics, and what is not must bring up no card:
// r2d2, 9to5mac, wi-fi 6, 5 ft 10, 2026-10-06, $100. This is the test of whether it is words, a
// price or a date, and not letters and numbers to be worked.
enum Prose {
    static func reads(_ input: String) -> Bool {
        if input.contains("\\") { return false }
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
        if spelled.range(of: "[A-Za-z][0-9]|[0-9][A-Za-z]+[0-9]", options: .regularExpression) != nil { return true }

        // Two things side by side with only a space between, one of them a word: 5 ft 10, wi-fi 6.
        // 2 x and sin x are not words, x being a letter and sin a name.
        var known = Set(Functions.names + Array(Greek.names.keys) + ["pi", "ans", "Ans", "clip", "of", "deg", "rad", "mod"])
        // and, or and not are words of the language of statements, where there is a relation.
        if input.contains(where: { "=<>≈≠≤≥".contains($0) }) { known.formUnion(["and", "or", "not", "AND", "OR", "NOT", "And", "Or", "Not"]) }
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
        if input.contains("\\") { return input }
        var s = input
        func replace(_ pattern: String, _ template: String) {
            s = s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        // 1,000,000: a comma between groups of three, with no digit before the first group or
        // after the last.
        let grouped = try! NSRegularExpression(pattern: "(?<![0-9,.])[0-9]{1,3}(,[0-9]{3})+(?![0-9])")
        for match in grouped.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
            guard let range = Range(match.range, in: s) else { continue }
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
