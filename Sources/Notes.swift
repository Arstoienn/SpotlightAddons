import Foundation

// What the person typing should know about how their question was read, shown beside it on the
// card and under it in the working: where what they typed could be read two ways, and where the
// unknown cannot go (a denominator nought, a root of something below nought, a logarithm of
// something not above it).
enum Notes {
    static func of(_ input: String, roles: Roles?) -> [String] {
        var notes: [String] = []
        if !Differential.mentionsDerivative(input), let ambiguous = slashed(input) { notes.append(ambiguous) }
        if let roles, let conditions = conditions(roles) { notes.append(conditions) }
        return notes
    }

    // 1/ax² is (1/a)x², as 1/2mv² is (1/2)mv²; where the letter after the slash is followed by
    // another letter, a reader may well have meant 1/(ax²), and is told how it was taken.
    static func slashed(_ input: String) -> String? {
        guard let tokens = try? Parser.tokenize(input) else { return nil }
        func name(_ t: Parser.Token) -> String? {
            if case .letter(let s) = t { return Greek.names[s] ?? s }
            return nil
        }
        for i in tokens.indices.dropLast(2) where tokens[i] == .symbol("/") {
            guard let first = name(tokens[i + 1]) else { continue }
            // The factors run together after it: letters, and a power on the last.
            var j = i + 2, run: [String] = [first]
            while j < tokens.count, let next = name(tokens[j]) {
                run.append(next)
                j += 1
            }
            guard run.count >= 2 else { continue }
            var power = ""
            if j + 1 < tokens.count, tokens[j] == .symbol("^"), case .number(let p) = tokens[j + 1] {
                // A whole power raised, b²; any other written as it was typed, b^2.5 and b^1e20.
                power = p == p.rounded() ? Int(fitting: p).map(superscript) ?? "^" + decimal(p) : "^" + decimal(p)
            }
            let rest = run.dropFirst().joined() + power
            return "1/\(run.joined())\(power) is read as (1/\(first))·\(rest); for 1/(\(run.joined())\(power)), write the brackets."
        }
        // 84/21a⁶ is (84/21)a⁶, as 1/2x is (1/2)x; but it may have been copied from a fraction with 21a⁶
        // under its line. Said how it was taken, and, in an equation, what the other way gives.
        for i in tokens.indices.dropLast(2) where i > 0 && tokens[i] == .symbol("/") {
            guard case .number(let below) = tokens[i + 1], let first = name(tokens[i + 2]) else { continue }
            let above: String
            switch tokens[i - 1] {
            case .number(let n): above = decimal(n)
            case .letter(let l): above = Greek.names[l] ?? l
            default: continue
            }
            // A half before letters, ½mv² and ½at², is always the coefficient; and values given are a formula's.
            if above == "1" && below == 2 || input.contains(",") { continue }
            var j = i + 3, run = first
            while j < tokens.count, let next = name(tokens[j]) { run += next; j += 1 }
            var power = ""
            if j + 1 < tokens.count, tokens[j] == .symbol("^"), case .number(let p) = tokens[j + 1] {
                power = p == p.rounded() ? Int(fitting: p).map(superscript) ?? "^" + decimal(p) : "^" + decimal(p)
            }
            let term = decimal(below) + run + power
            var note = "\(above)/\(term) is read as (\(above)/\(decimal(below)))·\(run)\(power)"
            if input.contains("="), let other = fractions(input), let solved = Solver.solve(other), !solved.exact.contains("Insufficient") {
                let shown = other.replacingOccurrences(of: "\\^([0-9]+)", with: "$1", options: .regularExpression)
                    .replacingOccurrences(of: "*", with: "")
                note += "; written " + superscripted(shown) + ", it gives " + solved.exact
            } else {
                note += "; for \(above)/(\(term)), write the brackets"
            }
            return note + "."
        }
        return nil
    }

    // Each number over a number and letters, 84/21a^6, with what is below the line bracketed: 84/(21a^6).
    static func fractions(_ input: String) -> String? {
        let pattern = "(?<![A-Za-z0-9.)])([0-9.]+|[A-Za-z])/([0-9.]+[A-Za-z]+(?:\\^[0-9.]+)?)"
        let out = input.replacingOccurrences(of: pattern, with: "$1/($2)", options: .regularExpression)
        return out == input ? nil : out
    }

    private static func superscripted(_ s: String) -> String {
        // a^6 as a⁶ in what is said.
        let raised: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹"]
        var out = "", after = false
        for c in s {
            if c.isLetter { after = true; out.append(c) }
            else if after, let r = raised[c] { out.append(r) }
            else { after = false; out.append(c) }
        }
        return out.replacingOccurrences(of: "=", with: " = ").replacingOccurrences(of: "+", with: " + ")
            .replacingOccurrences(of: "(?<=[0-9A-Za-z)⁰¹²³⁴⁵⁶⁷⁸⁹])-", with: " − ", options: .regularExpression)
    }

    // Where the one unknown of an equation or expression in one letter cannot be: x ≠ 2, x > 1.
    static func conditions(_ roles: Roles) -> String? {
        let letters = roles.letters.filter { !(roles.euler && $0 == "e") && !roles.given.contains($0) && !roles.constants.contains($0) }
        guard letters.count == 1, let name = letters.first, roles.tree.count == 1, let statement = roles.tree.first else { return nil }
        var found: [String] = []
        func note(_ s: String) { if !found.contains(s) { found.append(s) } }
        func look(_ e: Expr) {
            switch e {
            case .op("/", let a, let b):
                look(a); look(b)
                let lowered = b.lowered(unknown: name, constants: Set(roles.constants), euler: roles.euler)
                guard lowered.hasUnknown, let p = poly(lowered).map(trim), p.count >= 2, p.count <= 4 else { return }
                for r in realRoots(p) { note("\(name) ≠ \(shown(r))") }
            case .call(let f, let a):
                look(a)
                let lowered = a.lowered(unknown: name, constants: Set(roles.constants), euler: roles.euler)
                guard lowered.hasUnknown, let p = poly(lowered).map(trim), p.count == 2, p[1] != 0 else { return }
                let r = -p[0] / p[1], up = p[1] > 0
                switch f {
                case "sqrt": note("\(name) \(up ? "≥" : "≤") \(shown(r))")
                case "ln", "log", "lg", "lb", "log2", "log10": note("\(name) \(up ? ">" : "<") \(shown(r))")
                default: break
                }
            case .op(_, let a, let b): look(a); look(b)
            case .neg(let a): look(a)
            default: break
            }
        }
        look(statement.left)
        if let right = statement.right { look(right) }
        return found.isEmpty ? nil : "Where " + found.joined(separator: ", ")
    }

    private static func shown(_ v: Double) -> String {
        if let (p, q) = rational(v), abs(Double(p) / Double(q) - v) < 1e-12 { return fraction(p, q) }
        return decimal(v)
    }
}
