import Foundation

// An astronomy method's formula, as the engine writes it on one line in Unicode, typeset as it is
// printed: t₀ = ∫₀∞ dz/[(1+z)H(z)] with the integral's limits above and below its sign and the
// fraction over its line. Only what is wholly understood is typeset. The formula is read in parts
// between "; " and ", ", and a part with words in it (Catalogue lookup, solve quadratic for t) is
// left as the text it is; a formula with no part that can be typeset gives nil, and is shown as text.
//
// Juxtaposed letters are multiplied, as in physics: GM is G times M. A fraction takes everything
// multiplied before its line, as far back as a ×, ·, + or −, and below it what follows without a
// space: 2GM/R² is 2GM over R², μ/2ε is μ over 2ε, (R_s+R_p)/a × (1+e sin ω)/(1−e²) is two fractions.
// An integral or a sum takes what follows it, to the next + or −.
enum AstronomyFormula {
    static func math(_ formula: String) -> Math? {
        var pieces: [Math] = []
        var typeset = 0
        for (part, separator) in parts(formula) {
            var reader = Reader(part)
            if let m = reader.whole() { pieces.append(m); typeset += 1 } else { pieces.append(.text(part)) }
            if let separator { pieces.append(.text(separator)) }
        }
        return typeset == 0 ? nil : .row(pieces)
    }

    // The formula between "; " and ", " that are outside every bracket.
    static func parts(_ formula: String) -> [(String, String?)] {
        let chars = Array(formula)
        var out: [(String, String?)] = []
        var depth = 0, start = 0, i = 0
        while i < chars.count {
            let c = chars[i]
            if "([".contains(c) { depth += 1 } else if ")]".contains(c) { depth = max(0, depth - 1) }
            if depth == 0, c == ";" || c == ",", i + 1 < chars.count, chars[i + 1] == " " {
                out.append((String(chars[start..<i]), String(c) + " "))
                i += 2; start = i; continue
            }
            i += 1
        }
        out.append((String(chars[start...]), nil))
        return out.filter { !$0.0.isEmpty }
    }

    // Written small after a letter, a number or a bracket: indices, powers, primes, the Sun's sign.
    static let suffixes: Set<Character> = Set("₀₁₂₃₄₅₆₇₈₉ₐₑₒₓₕₖₗₘₙₚₛₜᵢⱼᵣᵤᵥ₊₋⁰¹²³⁴⁵⁶⁷⁸⁹⁻⁺ᵀ′″☉⊕*")
    static let smallLetters: [Character: Character] = ["ₐ": "a", "ₑ": "e", "ₒ": "o", "ₓ": "x", "ₕ": "h", "ₖ": "k", "ₗ": "l", "ₘ": "m",
                                                       "ₙ": "n", "ₚ": "p", "ₛ": "s", "ₜ": "t", "ᵢ": "i", "ⱼ": "j", "ᵣ": "r", "ᵤ": "u", "ᵥ": "v"]
    static let raised: [Character: Character] = ["⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9", "⁻": "−", "⁺": "+"]
    static let lowered: [Character: Character] = ["₀": "0", "₁": "1", "₂": "2", "₃": "3", "₄": "4", "₅": "5", "₆": "6", "₇": "7", "₈": "8", "₉": "9",
                                                  "ᵢ": "i", "ⱼ": "j", "ₙ": "n", "ₖ": "k"]
    // Written upright with a space after, the argument following: sin α, log₁₀(d/10pc).
    static let functions = ["expm1", "arccos", "arcsin", "arctan", "atan2", "asin", "acos", "atan", "sinh", "cosh", "tanh",
                            "sin", "cos", "tan", "log", "exp", "sgn", "ln"]
    // Words that make a part prose, though they are short: a + b N2 or a + b O3N2.
    static let words: Set<String> = ["or", "and", "for", "in", "of", "to", "at", "by", "mod", "per", "from", "with", "the"]

    private struct Reader {
        let c: [Character]
        var i = 0
        var inAbs = false
        init(_ s: String) { c = Array(s.trimmingCharacters(in: .whitespaces)) }

        var peek: Character? { i < c.count ? c[i] : nil }
        mutating func spaces() -> Bool { let s = i; while peek == " " { i += 1 }; return i > s }
        func isLetter(_ ch: Character) -> Bool { ch.unicodeScalars.first.map { CharacterSet.letters.contains($0) } ?? false }

        // The whole part, read to its end, or nil.
        mutating func whole() -> Math? {
            guard !c.isEmpty, let m = relation() else { return nil }
            _ = spaces()
            return i == c.count ? m : nil
        }

        // a = b ≈ c, each side a sum.
        mutating func relation() -> Math? {
            guard var left = sum() else { return nil }
            while true {
                let save = i
                _ = spaces()
                guard let ch = peek, "=≈≤≥<>".contains(ch) else { i = save; break }
                i += 1; _ = spaces()
                guard let right = sum() else { return nil }
                left = .row([left, .text(" \(ch) "), right])
            }
            return left
        }

        // Terms with + − ± ∓ between them, the first perhaps with a sign of its own.
        mutating func sum() -> Math? {
            var parts: [Math] = []
            _ = spaces()
            if let ch = peek, "−-".contains(ch) { i += 1; parts.append(.text("−")) }
            guard let first = term() else { return nil }
            parts.append(first)
            while true {
                let save = i
                _ = spaces()
                guard let ch = peek, "+−-±∓".contains(ch) else { i = save; break }
                i += 1
                guard let next = term() else { return nil }
                parts.append(.text(" \(ch == "-" ? "−" : ch) "))
                parts.append(next)
            }
            return parts.count == 1 ? parts[0] : .row(parts)
        }

        // Products, each perhaps a fraction, with × or · between them.
        mutating func term() -> Math? {
            guard var left = product() else { return nil }
            while true {
                let save = i
                _ = spaces()
                guard let ch = peek, "×·".contains(ch) else { i = save; break }
                i += 1
                guard let right = product() else { return nil }
                left = .row([left, .text(ch == "×" ? " × " : "·"), right])
            }
            return left
        }

        // Factors side by side, multiplied; a / makes what has gone before the numerator and what
        // follows without a space the denominator.
        mutating func product() -> Math? {
            var parts: [Math] = []
            _ = spaces()
            while true {
                let save = i
                let spaced = spaces()
                guard let ch = peek else { i = save; break }
                if ch == "/" {
                    guard !parts.isEmpty else { return nil }
                    i += 1; _ = spaces()
                    guard let below = denominator() else { return nil }
                    parts = [.fraction(Reader.unwrapped(.row(parts)), Reader.unwrapped(below))]
                    continue
                }
                guard startsFactor(ch), let f = factor() else { i = save; break }
                // A function stands a word's space from what it follows (5 log₁₀, 2 atan); letters a thin one.
                if !parts.isEmpty, case .row(let r) = f, case .text(let name)? = r.first,
                   AstronomyFormula.functions.contains(where: { name.hasPrefix($0) }) {
                    parts.append(.text(" "))
                } else if spaced, !parts.isEmpty {
                    parts.append(.text("\u{2009}"))
                }
                parts.append(f)
                // An integral or a sum has taken the rest.
                if case .row(let r) = f, case .bigOperator? = r.first { break }
            }
            guard !parts.isEmpty else { return nil }
            return parts.count == 1 ? parts[0] : .row(parts)
        }

        // What follows a / without a space: R² in 2GM/R², 2ε in μ/2ε, H(z′) in dz′/H(z′).
        mutating func denominator() -> Math? {
            var parts: [Math] = []
            while let ch = peek, ch != " ", ch != "/", startsFactor(ch), let f = factor() {
                parts.append(f)
                if case .group = f { if peek != "(" && peek != "[" { break } }
            }
            return parts.isEmpty ? nil : parts.count == 1 ? parts[0] : .row(parts)
        }

        func startsFactor(_ ch: Character) -> Bool {
            isLetter(ch) || ch.isNumber || "([√∫Σ∞".contains(ch) || (ch == "|" && !inAbs)
        }

        // One thing and its power: a letter with its index, a number, a function and its argument,
        // a bracket, a root, an integral or a sum, |x|.
        mutating func factor() -> Math? {
            guard var base = atom() else { return nil }
            if peek == "^" {
                i += 1
                guard let power = exponent() else { return nil }
                base = .power(base, power)
            }
            return base
        }

        mutating func exponent() -> Math? {
            if let ch = peek, "([".contains(ch) { return group().map(Reader.unwrapped) }
            var s = ""
            if let ch = peek, "−-".contains(ch) { s = "−"; i += 1 }
            while let ch = peek, ch.isNumber || ch == "." || isLetter(ch) { s.append(ch); i += 1 }
            return s.isEmpty || s == "−" ? nil : .text(s)
        }

        mutating func suffix() -> String {
            var s = ""
            // A letter written small, rⱼ, is the panel's own lowered letter, r_j: the small Unicode
            // letters come from another font, set apart from the letter they belong to.
            while let ch = peek, AstronomyFormula.suffixes.contains(ch) {
                if let letter = AstronomyFormula.smallLetters[ch] { s += "_" + String(letter) } else { s.append(ch) }
                i += 1
            }
            // _esc, _TDB, T_CMB,0: an index written out after an underscore.
            if peek == "_", i + 1 < c.count, c[i + 1].isASCII, c[i + 1].isLetter || c[i + 1].isNumber {
                s.append("_"); i += 1
                while let ch = peek, ch.isASCII, ch.isLetter || ch.isNumber { s.append(ch); i += 1 }
                if peek == ",", i + 1 < c.count, c[i + 1].isASCII, c[i + 1].isLetter || c[i + 1].isNumber {
                    s.append(","); i += 1
                    while let ch = peek, ch.isASCII, ch.isLetter || ch.isNumber { s.append(ch); i += 1 }
                }
                while let ch = peek, AstronomyFormula.suffixes.contains(ch) { s.append(ch); i += 1 }
            }
            return s
        }

        mutating func atom() -> Math? {
            guard let ch = peek else { return nil }
            if ch == "(" || ch == "[" {
                guard let g = group() else { return nil }
                let after = suffix()
                // (R_p/R_s)²: the power at the height of the bracket, as ^2 would put it.
                if !after.isEmpty, after.allSatisfy({ AstronomyFormula.raised[$0] != nil }) {
                    return .power(g, .text(String(after.compactMap { AstronomyFormula.raised[$0] })))
                }
                return after.isEmpty ? g : .row([g, .text(after)])
            }
            if ch == "|" {
                i += 1
                let was = inAbs; inAbs = true
                defer { inAbs = was }
                guard let inside = relation(), peek == "|" else { return nil }
                i += 1
                return .row([.text("|"), inside, .text("|" + suffix())])
            }
            if ch == "√" {
                i += 1
                if let next = peek, next == "(" || next == "[" { return group().map { .root(Reader.unwrapped($0)) } }
                return atom().map { .root($0) }
            }
            if ch == "∞" { i += 1; return .text("∞" + suffix()) }
            if ch == "∫" || ch == "Σ" { return bigOperator() }
            if ch.isNumber {
                var s = ""
                while let d = peek, d.isNumber || (d == "." && i + 1 < c.count && c[i + 1].isNumber) { s.append(d); i += 1 }
                return .text(s + suffix())
            }
            guard isLetter(ch) else { return nil }
            // A run of letters: a function, a word that makes this prose, or letters multiplied.
            var run = ""
            var j = i
            while j < c.count, c[j].isASCII, c[j].isLetter { run.append(c[j]); j += 1 }
            if let name = AstronomyFormula.functions.first(where: { function in
                let n = Array(function)
                guard i + n.count <= c.count, Array(c[i..<(i + n.count)]) == n else { return false }
                return i + n.count == c.count || !(c[i + n.count].isASCII && c[i + n.count].isLetter)
            }) {
                i += name.count
                let index = suffix()
                let spaced = spaces()
                guard let next = peek else { return nil }
                if next == "(" || next == "[" { return group().map { .row([.text(name + index), $0]) } }
                guard spaced, let argument = factor() else { return nil }
                return .row([.text(name + index + " "), argument])
            }
            if AstronomyFormula.words.contains(run) || (run.count >= 3 && run.allSatisfy(\.isLowercase)) { return nil }
            i += 1
            return .text(String(ch) + suffix())
        }

        // (…) or […], drawn with brackets that grow; inside, things with commas between.
        mutating func group() -> Math? {
            guard let open = peek, open == "(" || open == "[" else { return nil }
            let close: Character = open == "(" ? ")" : "]"
            i += 1
            let was = inAbs; inAbs = false
            defer { inAbs = was }
            var items: [Math] = []
            while true {
                guard let item = relation() else { return nil }
                items.append(item)
                _ = spaces()
                if peek == "," { i += 1; continue }
                break
            }
            guard peek == close else { return nil }
            i += 1
            var inside: [Math] = []
            for (k, item) in items.enumerated() { if k > 0 { inside.append(.text(", ")) }; inside.append(item) }
            return .group(inside.count == 1 ? inside[0] : .row(inside))
        }

        // ∫₀∞, ∫z∞, ∫₀z or ∫ alone, and Σ with its index; then what they take, to the next + or −.
        mutating func bigOperator() -> Math? {
            let sign = c[i]; i += 1
            var lower = "", upper = ""
            if sign == "∫" {
                while let ch = peek, let digit = AstronomyFormula.lowered[ch] { lower.append(digit); i += 1 }
                if lower.isEmpty, let ch = peek, ch.isASCII, ch.isLetter, i + 1 < c.count, c[i + 1] == "∞" || (c[i + 1].isASCII && c[i + 1].isLetter) {
                    lower.append(ch); i += 1
                }
                if !lower.isEmpty, let ch = peek, ch == "∞" || (ch.isASCII && ch.isLetter) { upper.append(ch); i += 1 }
                if !lower.isEmpty && upper.isEmpty { return nil }
            } else {
                while let ch = peek, let index = AstronomyFormula.lowered[ch] { lower.append(index); i += 1 }
            }
            guard let taken = product() else { return nil }
            let symbol: Math = sign == "∫"
                ? (lower.isEmpty ? .text("∫") : .bigOperator("∫", lower: .text(lower), upper: .text(upper)))
                : (lower.isEmpty ? .text("Σ") : .bigOperator("∑", lower: .text(lower), upper: .text("")))
            return .row([symbol, .text("\u{2009}"), taken])
        }

        // Brackets are written by the fraction's line, a root's bar and a power's height; not again.
        static func unwrapped(_ m: Math) -> Math {
            if case .group(let inside) = m { return inside }
            if case .row(let parts) = m, parts.count == 1 { return unwrapped(parts[0]) }
            return m
        }
    }
}
