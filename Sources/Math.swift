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

    // "(−3 ± √17)/4", "n²", "e^2.5": brackets only where a single line needs them.
    var plain: String {
        switch self {
        case .text(let s): return s
        case .row(let parts): return parts.map(\.plain).joined()
        case .fraction(let n, let d):
            // On one line a product below the line needs brackets as much as a sum does: y/(77b).
            var below = Math.bracketed(d)
            if case .row(let parts) = d, parts.filter({ !$0.plain.isEmpty }).count > 1, !below.hasPrefix("(") { below = "(\(below))" }
            return Math.bracketed(n) + "/" + below
        case .root(let x): return "√" + Math.bracketed(x)
        case .power(let base, let exponent):
            let e = exponent.plain
            // Plain digits only: ² is a whole number too, as far as Swift is concerned, and 2^3² is not 2 to the 32.
            if !e.isEmpty, e.allSatisfy({ $0.isASCII && $0.isNumber }), let k = Int(e) { return base.plain + superscript(k) }
            return base.plain + "^" + Math.bracketed(exponent)
        case .bigOperator(let symbol, let lower, let upper):
            return "\(symbol)(\(lower.plain)…\(upper.plain)) "
        }
    }

    var hasFraction: Bool {
        switch self {
        case .text: return false
        case .row(let parts): return parts.contains(where: \.hasFraction)
        case .fraction: return true
        case .root(let x): return x.hasFraction
        case .power(let b, let e): return b.hasFraction || e.hasFraction
        case .bigOperator: return false
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
