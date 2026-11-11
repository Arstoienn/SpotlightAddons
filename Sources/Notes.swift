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
        return nil
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
