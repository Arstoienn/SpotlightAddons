import Foundation

// Mathematics as it is laid out rather than typed: fractions stacked, roots under a bar, powers
// raised. The same tree prints as one line of text (for the tests, and for copying) and is
// typeset in the detail panel.
indirect enum Math: Equatable {
    case text(String)
    case row([Math])
    case fraction(Math, Math)
    case root(Math)
    case power(Math, Math)
    case bigOperator(String, lower: Math, upper: Math)   // ∑ or ∏ with its limits
    case group(Math)                                     // in brackets that grow with what is inside

    // "(−3 ± √17)/4", "n²", "e^2.5": brackets only where a single line needs them.
    var plain: String {
        switch self {
        case .text(let s): return s
        case .row(let parts): return parts.map(\.plain).joined()
        case .fraction(let n, let d):
            // On one line a product below the line needs brackets as much as a sum does: y/(77b).
            var below = Math.bracketed(d)
            // cos(x) needs no brackets of its own.
            let isCall = below.range(of: "^[A-Za-z]+\\([^()]*\\)$", options: .regularExpression) != nil
            if case .row(let parts) = d, parts.filter({ !$0.plain.isEmpty }).count > 1, !below.hasPrefix("("), !isCall { below = "(\(below))" }
            return Math.bracketed(n) + "/" + below
        case .root(let x): return "√" + Math.bracketed(x)
        case .power(let base, let exponent):
            let e = exponent.plain
            // Plain digits only: ² is a whole number too, as far as Swift is concerned, and 2^3² is not 2 to the 32.
            if !e.isEmpty, e.allSatisfy({ $0.isASCII && $0.isNumber }), let k = Int(e) { return base.plain + superscript(k) }
            // 2x in an exponent is a product, as much as 2·x is: e^(2x).
            if let first = e.first, first.isNumber, e.dropFirst().contains(where: { $0.isLetter }) { return base.plain + "^(" + e + ")" }
            return base.plain + "^" + Math.bracketed(exponent)
        case .bigOperator(let symbol, let lower, let upper):
            return "\(symbol)(\(lower.plain)…\(upper.plain)) "
        case .group(let x): return "(" + x.plain + ")"
        }
    }

    // The same tree as LaTeX, for pasting into a document: \frac{20}{3}, x^{2} - 5x + 6 = 0, \sin(30^{\circ}).
    var latex: String {
        var s = latexParts
        s = s.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
        // A command needs a space before a letter (\pi r), but none before a bracket or a script.
        s = s.replacingOccurrences(of: "(\\\\[A-Za-z]+) (?=[)\\]},;!.'|^_])", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\{ ", with: "{").replacingOccurrences(of: " \\}", with: "}")
        return Math.sizedBrackets(s.trimmingCharacters(in: .whitespaces))
    }

    // Brackets round something tall (a fraction, a sum) grow with it: (\frac{1}{2})^{2} is
    // \left(\frac{1}{2}\right)^{2}. Those round a single line stay as they are.
    private static func sizedBrackets(_ s: String) -> String {
        let chars = Array(s)
        var open: [Int] = []
        var grown: [Int: Bool] = [:]   // index of a bracket -> true for "(" and false for ")"
        for (i, c) in chars.enumerated() {
            if c == "(" { open.append(i) }
            else if c == ")", let start = open.popLast() {
                let inside = String(chars[(start + 1)..<i])
                if ["\\frac", "\\sum", "\\prod"].contains(where: inside.contains) { grown[start] = true; grown[i] = false }
            }
        }
        if grown.isEmpty { return s }
        var out = ""
        for (i, c) in chars.enumerated() {
            if let opening = grown[i] { out += opening ? "\\left(" : "\\right)" } else { out.append(c) }
        }
        return out
    }

    private var latexParts: String {
        switch self {
        case .text(let s):
            // F_n is cut where its subscript starts; the subscript is taken as it is.
            return subscriptRuns(s).map { $0.lowered ? "_{\($0.text)}" : Math.latexText($0.text) }.joined()
        case .row(let parts): return parts.map(\.latexParts).joined()
        case .group(let x): return "(" + x.latexParts + ")"   // \left( \right) where it holds a fraction: sizedBrackets
        case .fraction(let n, let d): return "\\frac{\(n.latexParts)}{\(d.latexParts)}"
        case .root(let x): return "\\sqrt{\(x.latexParts)}"
        case .power(let base, let exponent): return "\(base.latexParts)^{\(exponent.latexParts)}"
        case .bigOperator(let symbol, let lower, let upper):
            return "\(symbol == "∏" ? "\\prod" : "\\sum")_{\(lower.latexParts)}^{\(upper.latexParts)} "
        }
    }

    private static let latexSymbols: [Character: String] = [
        "−": "-", "·": " \\cdot ", "×": " \\times ", "÷": " \\div ", "±": " \\pm ", "∓": " \\mp ",
        "≤": " \\le ", "≥": " \\ge ", "≠": " \\ne ", "≈": " \\approx ", "→": " \\to ", "⇒": " \\Rightarrow ",
        "∈": " \\in ", "∉": " \\notin ", "∪": " \\cup ", "∩": " \\cap ", "∧": " \\land ", "∨": " \\lor ", "¬": "\\lnot ",
        "∞": "\\infty ", "∅": "\\emptyset ", "…": "\\ldots ", "%": "\\%", "°": "^{\\circ}",
        "ℝ": "\\mathbb{R} ", "ℂ": "\\mathbb{C} ", "ℤ": "\\mathbb{Z} ", "ℕ": "\\mathbb{N} ", "ℚ": "\\mathbb{Q} ",
        "α": "\\alpha ", "β": "\\beta ", "γ": "\\gamma ", "δ": "\\delta ", "ε": "\\varepsilon ", "ζ": "\\zeta ",
        "η": "\\eta ", "θ": "\\theta ", "ι": "\\iota ", "κ": "\\kappa ", "λ": "\\lambda ", "μ": "\\mu ", "ν": "\\nu ",
        "ξ": "\\xi ", "π": "\\pi ", "ρ": "\\rho ", "σ": "\\sigma ", "τ": "\\tau ", "υ": "\\upsilon ", "φ": "\\varphi ",
        "χ": "\\chi ", "ψ": "\\psi ", "ω": "\\omega ", "Γ": "\\Gamma ", "Δ": "\\Delta ", "Θ": "\\Theta ",
        "Λ": "\\Lambda ", "Ξ": "\\Xi ", "Π": "\\Pi ", "Σ": "\\Sigma ", "Φ": "\\Phi ", "Ψ": "\\Psi ", "Ω": "\\Omega ",
    ]
    private static let superscripts: [Character: Character] = [
        "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9", "⁻": "-", "⁺": "+",
    ]
    // Names LaTeX has a command for; any other name before a bracket is an \operatorname.
    private static let latexFunctions: Set<String> = [
        "sin", "cos", "tan", "sec", "csc", "cot", "sinh", "cosh", "tanh", "coth", "arcsin", "arccos", "arctan",
        "ln", "log", "lg", "exp", "det", "gcd", "max", "min", "arg", "dim", "ker", "lim", "sup", "Pr",
    ]

    private static func latexText(_ s: String) -> String {
        var s = s
        // The commas between the equations of a system.
        s = s.replacingOccurrences(of: ",\\s{2,}", with: ", \\\\quad ", options: .regularExpression)
        s = s.replacingOccurrences(of: " mod ", with: " \\bmod ")
        // sin( is \sin(, asin( \arcsin(, lcm( \operatorname{lcm}(.
        if let call = try? NSRegularExpression(pattern: "(?<![A-Za-z\\\\])([A-Za-z]{2,})(?=[(|])") {
            for match in call.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
                guard let range = Range(match.range(at: 1), in: s) else { continue }
                var name = String(s[range])
                if ["asin", "acos", "atan"].contains(name) { name = "arc" + name.dropFirst() }
                s.replaceSubrange(range, with: latexFunctions.contains(name) ? "\\\(name)" : "\\operatorname{\(name)}")
            }
        }
        // 20/3 and 2π/3, where an answer is written on one line.
        s = s.replacingOccurrences(of: "(?<![0-9.A-Za-zπ)])([0-9]*\\.?[0-9]*π|[0-9]+(?:\\.[0-9]+)?)/([0-9]+(?:\\.[0-9]+)?)(?![0-9.])",
                                   with: "\\\\frac{$1}{$2}", options: .regularExpression)
        // √2 and √(x + 1), where a root is written on one line.
        s = s.replacingOccurrences(of: "√\\(([^()]*)\\)", with: "\\\\sqrt{$1}", options: .regularExpression)
        s = s.replacingOccurrences(of: "√([0-9A-Za-z.]+)", with: "\\\\sqrt{$1}", options: .regularExpression)
        var out = ""
        var raised = ""
        for c in s {
            if let digit = superscripts[c] { raised.append(digit); continue }
            if !raised.isEmpty { out += "^{\(raised)}"; raised = "" }
            out += latexSymbols[c] ?? String(c)
        }
        if !raised.isEmpty { out += "^{\(raised)}" }
        return out
    }

    var hasFraction: Bool {
        switch self {
        case .text: return false
        case .row(let parts): return parts.contains(where: \.hasFraction)
        case .fraction: return true
        case .root(let x): return x.hasFraction
        case .power(let b, let e): return b.hasFraction || e.hasFraction
        case .bigOperator: return false
        case .group(let x): return x.hasFraction
        }
    }

    // An operator anywhere but at the very start (a leading minus is part of the number).
    private static func bracketed(_ m: Math) -> String {
        let s = m.plain
        return s.dropFirst().contains(where: { "+−±·×/".contains($0) }) ? "(\(s))" : s
    }
}

func t(_ s: String) -> Math { .text(s) }
func row(_ parts: Math...) -> Math { .row(parts) }
func squared(_ base: String) -> Math { .power(.text(base), .text("2")) }

// p/q in lowest terms, the minus sign outside the fraction.
func fractionMath(_ p: Int, _ q: Int) -> Math {
    let (num, den) = reduced(p, q)
    if den == 1 { return t(minus(num)) }
    let f = Math.fraction(t("\(abs(num))"), t("\(den)"))
    return num < 0 ? row(t("−"), f) : f
}

// A name with a subscript is written F_n, as it is typed: this cuts "F_n = 6.55" into F, n
// (lowered) and " = 6.55" for whatever draws it. A subscript is letters or digits, not both, so
// that v_0t is v₀ times t.
func subscriptRuns(_ s: String) -> [(text: String, lowered: Bool)] {
    var runs: [(text: String, lowered: Bool)] = []
    var current = ""
    var i = s.startIndex
    while i < s.endIndex {
        let next = s.index(after: i)
        if s[i] == "_", let before = current.last, before.isLetter, next < s.endIndex, s[next].isASCII, s[next].isLetter || s[next].isNumber {
            let digits = s[next].isNumber
            var j = next
            while j < s.endIndex, s[j].isASCII, digits ? s[j].isNumber : s[j].isLetter { j = s.index(after: j) }
            runs.append((current, false))
            runs.append((String(s[next..<j]), true))
            current = ""
            i = j
        } else {
            current.append(s[i])
            i = next
        }
    }
    if !current.isEmpty || runs.isEmpty { runs.append((current, false)) }
    return runs.filter { !$0.text.isEmpty || runs.count == 1 }
}

func superscript(_ k: Int) -> String {
    let digits = Array("⁰¹²³⁴⁵⁶⁷⁸⁹")
    return String(String(k).compactMap { $0.wholeNumberValue.map { digits[$0] } })
}
