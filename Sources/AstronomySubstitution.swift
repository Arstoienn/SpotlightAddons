import Foundation

// An astronomy formula with its numbers in it, as working on paper shows it:
//     v_esc = √(2GM/R) = √(2(6.6743 × 10⁻¹¹)(5.9722 × 10²⁴)/(6.371 × 10⁶)) = 11186.2 m s⁻¹
// Each letter of the formula's right-hand side is given either a constant (G, c, σ, k_B, h, ℏ, M☉…) or
// one of the values the method looked up as it worked, of the kind the letter stands for: M or m a
// mass, R, r, a or d a length, T a temperature, L a luminosity, and so on. Where several values could
// stand for the letters, each way of giving them is tried. The formula is shown with the numbers in
// only where it then gives the engine's own answer, to a part in a million: the working never shows a
// substitution that is not what was worked out. The formula is read as AstronomyFormula reads it, so
// that what is evaluated is what is typeset: letters side by side multiplied, a / taking everything
// multiplied before it over what follows it without a space.
enum AstronomySubstitution {
    struct Worked {
        let assigned: [(symbol: String, used: AstronomyWorking.Used)]   // each letter given a looked-up value, in order
        let line: Math                                                   // left = with the numbers = the answer
    }

    static let constants: [String: Double] = [
        "G": 6.6743e-11, "c": 299_792_458, "σ": 5.670374419e-8, "k_B": 1.380649e-23, "h": 6.62607015e-34, "ℏ": 1.054571817e-34,
        "M☉": 1.988409870698051e30, "R☉": 6.957e8, "L☉": 3.828e26, "M⊕": 5.9722e24, "R⊕": 6.3781e6, "AU": 1.495978707e11, "π": .pi,
        "g₀": 9.80665, "pc": 3.0856775814913673e16,
    ]

    // What a letter may stand for, by the letter: the kinds of value the engine reports, likeliest first.
    // Any letter may also be a plain number, as M is a magnitude in m = M + 5 log₁₀(d/10pc); the check
    // against the answer settles which.
    static func kinds(_ symbol: String) -> [String] {
        guard let first = symbol.first else { return [] }
        let named: [String]
        if symbol.hasPrefix("Δv") { named = ["speed"] } else {
            switch first {
            case "M", "m": named = ["mass"]
            case "ṁ": named = ["massflow"]
            case "R", "r", "d", "D", "a", "b", "λ", "s", "h": named = ["radius", "length", "a"]
            case "T": named = ["temperature", "time"]
            case "L": named = ["luminosity"]
            case "t", "P", "τ", "I": named = ["time"]
            case "v", "u", "V": named = ["speed"]
            case "μ": named = ["mu"]
            case "θ", "α", "β", "φ", "δ", "i", "ι", "ω", "Ω", "z": named = ["angle"]
            case "F": named = ["force", "flux"]
            case "g": named = ["acceleration"]
            case "ν", "f": named = ["frequency"]
            case "E": named = ["energy"]
            case "ρ": named = ["density"]
            case "κ": named = ["opacity"]
            case "S", "B": named = ["flux"]
            default: named = []
            }
        }
        return named + ["number", "value"]
    }

    static func work(_ w: AstronomyWorking) -> Worked? {
        guard let target = w.si, target.isFinite else { return nil }
        for (part, _) in AstronomyFormula.parts(w.formula) {
            guard let (left, right) = split(part) else { continue }
            // v² = GM(2/r − 1/a): the right side is the answer squared.
            var power = 1.0
            if let last = left.last, AstronomyFormula.raised[last] != nil {
                let digits = String(left.reversed().prefix { AstronomyFormula.raised[$0] != nil }.reversed()).compactMap { AstronomyFormula.raised[$0] }
                power = Double(String(digits).replacingOccurrences(of: "−", with: "-")) ?? 1
            }
            let goal = pow(target, power)
            var reader = Reader(right)
            guard reader.read() != nil else { continue }
            let symbols = reader.symbols.map(\.name).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            // Each letter's choices: the values of its kind, or its constant. e is the eccentricity where
            // one was used, and Euler's number otherwise.
            var choices: [[Int?]] = []
            for symbol in symbols {
                let order = kinds(symbol)
                let fitting = w.values.indices.filter { order.contains(w.values[$0].kind) }
                    .sorted { order.firstIndex(of: w.values[$0].kind)! < order.firstIndex(of: w.values[$1].kind)! }
                if symbol == "e" { choices.append(fitting.map { $0 } + [nil]); continue }
                if constants[symbol] != nil { choices.append([nil]); continue }
                guard !fitting.isEmpty else { choices = []; break }
                choices.append(fitting.map { $0 })
            }
            guard choices.count == symbols.count else { continue }
            var tried = 0, repeats = false
            var found: [Int?]?
            func attempt(_ k: Int, _ picked: [Int?]) {
                guard found == nil, tried < 5000 else { return }
                if k == choices.count {
                    tried += 1
                    var values: [String: Double] = [:]
                    for (symbol, pick) in zip(symbols, picked) {
                        values[symbol] = pick.map { w.values[$0].value } ?? constants[symbol] ?? (symbol == "e" ? M_E : .nan)
                    }
                    var evaluator = Reader(right, values: values)
                    if let v = evaluator.read(), v.isFinite, abs(v - goal) <= 1e-6 * max(abs(goal), 1e-300) { found = picked }
                    return
                }
                for choice in choices[k] {
                    // Two letters are two values: m and M are not both the Earth's mass.
                    if let choice, !repeats, picked.contains(choice) { continue }
                    attempt(k + 1, picked + [choice])
                }
            }
            attempt(0, [])
            // The same value may stand for two letters only where nothing else will do: chirp_mass(30 M_sun,
            // 30 M_sun) has m₁ and m₂ both 30 solar masses, looked up once.
            if found == nil { repeats = true; tried = 0; attempt(0, []) }
            guard let found else { continue }
            var numbers: [String: String] = [:]
            var assigned: [(symbol: String, used: AstronomyWorking.Used)] = []
            for (symbol, pick) in zip(symbols, found) {
                if let pick {
                    numbers[symbol] = written(w.values[pick].value)
                    assigned.append((symbol, w.values[pick]))
                } else if symbol != "π", symbol != "e", let constant = constants[symbol] {
                    numbers[symbol] = written(constant)
                }
            }
            let substituted = reader.substituted(numbers)
            let unit = w.siUnit.isEmpty ? "" : " " + w.siUnit
            let answer = written(target, figures: 6) + unit
            // For v², the square as worked out, and then v.
            let subject = String(left.reversed().drop { AstronomyFormula.raised[$0] != nil }.reversed())
            let line = power == 1 ? left + " = " + substituted + " = " + answer
                : left + " = " + substituted + " = " + written(goal, figures: 6) + ",  " + subject + " = " + answer
            return Worked(assigned: assigned, line: AstronomyFormula.math(line) ?? .text(line))
        }
        return nil
    }

    // a = b, or a ≈ b: the two sides, where there is one = or ≈ outside every bracket.
    private static func split(_ part: String) -> (String, String)? {
        var depth = 0
        var at: String.Index?
        for i in part.indices {
            let c = part[i]
            if "([".contains(c) { depth += 1 } else if ")]".contains(c) { depth -= 1 }
            if depth == 0, c == "=" || c == "≈" {
                if at != nil { return nil }
                at = i
            }
        }
        guard let at else { return nil }
        let left = part[..<at].trimmingCharacters(in: .whitespaces), right = part[part.index(after: at)...].trimmingCharacters(in: .whitespaces)
        return left.isEmpty || right.isEmpty ? nil : (left, right)
    }

    // 6.6743 × 10⁻¹¹, 11186.2: as many figures as are worth showing, in standard form beyond a million or below a thousandth.
    static func written(_ v: Double, figures: Int = 5) -> String {
        guard v != 0 else { return "0" }
        let a = abs(v)
        if a < 1e7, v == v.rounded() { return String(Int(v)).replacingOccurrences(of: "-", with: "−") }
        if a >= 1e-3, a < 1e5 {
            var s = String(format: "%.\(figures)g", v)
            if s.contains("e") { s = String(format: "%.\(max(0, figures - 1))f", v) }
            return s.replacingOccurrences(of: "-", with: "−")
        }
        let exponent = Int(floor(log10(a)))
        var mantissa = String(format: "%.\(figures - 1)f", v / pow(10, Double(exponent)))
        while mantissa.contains("."), mantissa.hasSuffix("0") { mantissa.removeLast() }
        if mantissa.hasSuffix(".") { mantissa.removeLast() }
        let raised: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"]
        return mantissa.replacingOccurrences(of: "-", with: "−") + " × 10" + String(String(exponent).map { raised[$0] ?? $0 })
    }

    // The right-hand side read for its value, by the same reading AstronomyFormula typesets: the letters
    // it has (each with where its name is written, for the numbers to be put in), and what it comes to
    // with the values given. Integrals, sums and anything it does not wholly understand give nil.
    struct Reader {
        struct Symbol { let name: String; let range: Range<Int> }
        let c: [Character]
        let values: [String: Double]
        var i = 0
        var symbols: [Symbol] = []

        init(_ s: String, values: [String: Double] = [:]) { c = Array(s); self.values = values }

        var peek: Character? { i < c.count ? c[i] : nil }
        mutating func spaces() -> Bool { let s = i; while peek == " " { i += 1 }; return i > s }
        func isLetter(_ ch: Character) -> Bool { ch.unicodeScalars.first.map { CharacterSet.letters.contains($0) } ?? false }

        mutating func read() -> Double? {
            guard let v = sum() else { return nil }
            _ = spaces()
            return i == c.count ? v : nil
        }

        // The text again, each letter given a number put in as a bracket: 2GM/R² as 2(…)(…)/(…)².
        func substituted(_ numbers: [String: String]) -> String {
            var out = "", k = 0
            for s in symbols.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) where s.range.lowerBound >= k {
                guard let number = numbers[s.name] else { continue }
                out += String(c[k..<s.range.lowerBound]) + "(" + number + ")"
                k = s.range.upperBound
            }
            return out + String(c[k...])
        }

        mutating func sum() -> Double? {
            _ = spaces()
            var sign = 1.0
            if let ch = peek, "−-".contains(ch) { i += 1; sign = -1 }
            guard var total = term().map({ $0 * sign }) else { return nil }
            while true {
                let save = i
                _ = spaces()
                guard let ch = peek, "+−-".contains(ch) else { i = save; break }
                i += 1
                guard let next = term() else { return nil }
                total += ch == "+" ? next : -next
            }
            return total
        }

        mutating func term() -> Double? {
            guard var left = product() else { return nil }
            while true {
                let save = i
                _ = spaces()
                guard let ch = peek, "×·".contains(ch) else { i = save; break }
                i += 1
                guard let right = product() else { return nil }
                left *= right
            }
            return left
        }

        mutating func product() -> Double? {
            var value: Double?
            _ = spaces()
            while true {
                let save = i
                _ = spaces()
                guard let ch = peek else { i = save; break }
                if ch == "/" {
                    guard let above = value else { return nil }
                    i += 1; _ = spaces()
                    guard let below = denominator() else { return nil }
                    value = above / below
                    continue
                }
                guard startsFactor(ch), let f = factor() else { i = save; break }
                value = (value ?? 1) * f
            }
            return value
        }

        mutating func denominator() -> Double? {
            var value: Double?
            while let ch = peek, ch != " ", ch != "/", startsFactor(ch) {
                let wasGroup = ch == "(" || ch == "["
                guard let f = factor() else { return nil }
                value = (value ?? 1) * f
                if wasGroup, peek != "(", peek != "[" { break }
            }
            return value
        }

        func startsFactor(_ ch: Character) -> Bool { isLetter(ch) || ch.isNumber || "([√|".contains(ch) }

        mutating func factor() -> Double? {
            guard var base = atom() else { return nil }
            if peek == "^" {
                i += 1
                guard let power = exponent() else { return nil }
                base = pow(base, power)
            }
            return base
        }

        mutating func exponent() -> Double? {
            if let ch = peek, "([".contains(ch) { return group() }
            var s = ""
            if let ch = peek, "−-".contains(ch) { s = "-"; i += 1 }
            while let ch = peek, ch.isNumber || ch == "." { s.append(ch); i += 1 }
            return Double(s)
        }

        // A suffix split into what names the letter (an index, a prime, the Sun's sign) and a power written raised.
        mutating func suffix() -> (name: String, power: Double?) {
            var name = "", raised = ""
            while let ch = peek, AstronomyFormula.suffixes.contains(ch) {
                if let digit = AstronomyFormula.raised[ch] { raised.append(digit == "−" ? "-" : digit) }
                else if let letter = AstronomyFormula.smallLetters[ch] { name += "_" + String(letter) }
                else { name.append(ch) }
                i += 1
            }
            if peek == "_", i + 1 < c.count, c[i + 1].isASCII, c[i + 1].isLetter || c[i + 1].isNumber {
                name.append("_"); i += 1
                while let ch = peek, ch.isASCII, ch.isLetter || ch.isNumber { name.append(ch); i += 1 }
                while let ch = peek, AstronomyFormula.suffixes.contains(ch) {
                    if let digit = AstronomyFormula.raised[ch] { raised.append(digit == "−" ? "-" : digit) } else { name.append(ch) }
                    i += 1
                }
            }
            return (name, raised.isEmpty ? nil : Double(raised))
        }

        mutating func atom() -> Double? {
            guard let ch = peek else { return nil }
            if ch == "(" || ch == "[" {
                guard let g = group() else { return nil }
                let after = suffix()
                guard after.name.isEmpty else { return nil }
                return after.power.map { pow(g, $0) } ?? g
            }
            if ch == "|" {
                i += 1
                guard let inside = sum(), peek == "|" else { return nil }
                i += 1
                return abs(inside)
            }
            if ch == "√" {
                i += 1
                if let next = peek, next == "(" || next == "[" { return group().map { $0.squareRoot() } }
                return atom().map { $0.squareRoot() }
            }
            if ch.isNumber {
                var s = ""
                while let d = peek, d.isNumber || (d == "." && i + 1 < c.count && c[i + 1].isNumber) { s.append(d); i += 1 }
                guard let v = Double(s) else { return nil }
                let after = suffix()
                guard after.name.isEmpty else { return nil }
                return after.power.map { pow(v, $0) } ?? v
            }
            guard isLetter(ch) else { return nil }
            var run = ""
            var j = i
            while j < c.count, c[j].isASCII, c[j].isLetter { run.append(c[j]); j += 1 }
            if let name = AstronomyFormula.functions.first(where: { f in
                let n = Array(f)
                guard i + n.count <= c.count, Array(c[i..<(i + n.count)]) == n else { return false }
                return i + n.count == c.count || !(c[i + n.count].isASCII && c[i + n.count].isLetter)
            }) {
                i += name.count
                let index = suffix()
                let spaced = spaces()
                guard let next = peek else { return nil }
                let argument: Double?
                if next == "(" || next == "[" { argument = group() } else if spaced { argument = factor() } else { argument = nil }
                guard let x = argument else { return nil }
                switch name {
                case "sin": return sin(x)
                case "cos": return cos(x)
                case "tan": return tan(x)
                case "asin", "arcsin": return asin(x)
                case "acos", "arccos": return acos(x)
                case "atan", "arctan": return atan(x)
                case "sinh": return sinh(x)
                case "cosh": return cosh(x)
                case "tanh": return tanh(x)
                case "exp": return exp(x)
                case "ln": return log(x)
                case "log": return index.name.isEmpty || index.name == "₁₀" || index.name == "10" ? log10(x) : nil
                default: return nil
                }
            }
            if AstronomyFormula.words.contains(run) || (run.count >= 3 && run.allSatisfy(\.isLowercase)) { return nil }
            // 10pc: a parsec, after a number, not p times c.
            if run == "pc", i > 0, c[i - 1].isNumber {
                let start = i
                i += 2
                symbols.append(Symbol(name: "pc", range: start..<i))
                return values["pc"] ?? 1
            }
            // AU is one constant, not A times U.
            if run.hasPrefix("AU"), run.count == 2 || !c[i + 2].isLetter {
                let start = i
                i += 2
                symbols.append(Symbol(name: "AU", range: start..<i))
                return values["AU"] ?? 1
            }
            let start = i
            i += 1
            // Δv, Δλ: a change in one letter is one name.
            var head = String(ch)
            if ch == "Δ", let next = peek, isLetter(next) { head.append(next); i += 1 }
            let after = suffix()
            let name = head + after.name
            // Where its name ends, before a power written raised: R² is R, squared.
            var end = i
            if after.power != nil { while end > start + 1, AstronomyFormula.raised[c[end - 1]] != nil { end -= 1 } }
            symbols.append(Symbol(name: name, range: start..<end))
            let v = values[name] ?? 1
            return after.power.map { pow(v, $0) } ?? v
        }

        mutating func group() -> Double? {
            guard let open = peek, open == "(" || open == "[" else { return nil }
            let close: Character = open == "(" ? ")" : "]"
            i += 1
            guard let inside = sum() else { return nil }
            _ = spaces()
            guard peek == close else { return nil }
            i += 1
            return inside
        }
    }
}
