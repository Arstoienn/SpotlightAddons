import Foundation

// An equation with the range its unknown is wanted in after it: sin x = √3/2, 0° ≤ x < 360°, or
// x² = 4, x > 0. The roots are found as they are for the equation alone, and those in the range
// are the answer.
struct Domain {
    var equation: String            // as it is solved: with x° where the angles are in degrees
    var name: String
    var lower: (value: Double, closed: Bool)?
    var upper: (value: Double, closed: Bool)?
    var degrees: Bool
    var unit: AngleUnit?            // for an angle
    var roots: [Double]             // in the range, in order

    private static let relations: Set<Character> = ["<", ">", "≤", "≥"]

    static func parse(_ input: String) -> Domain? {
        guard Options.inequalities else { return nil }
        let parts = LinearSystem.parts(input)
        guard parts.count >= 2, let clause = parts.last, parts.dropLast().count == 1 else { return nil }
        let equation = parts[0]
        guard equation.contains("="), !equation.contains(where: { relations.contains($0) }) || equation.contains("≈") == false,
              !clause.contains("=") || clause.contains("<=") || clause.contains(">=") else { return nil }
        var text = clause.replacingOccurrences(of: "<=", with: "≤").replacingOccurrences(of: ">=", with: "≥")
        // x ∈ [a, b) is a ≤ x < b.
        if let m = text.range(of: "^\\s*([A-Za-z])\\s*(?:∈|in)\\s*([\\[(])(.+),(.+)([\\])])\\s*$", options: .regularExpression) {
            let whole = String(text[m])
            let v = String(whole.first { $0.isLetter }!)
            let open = whole.contains("[") ? "≤" : "<", close = whole.last == "]" ? "≤" : "<"
            if let a = whole.firstIndex(where: { "[(".contains($0) }), let z = whole.lastIndex(where: { "])".contains($0) }),
               let comma = whole[a...z].firstIndex(of: ",") {
                let lo = whole[whole.index(after: a)..<comma].trimmingCharacters(in: .whitespaces)
                let hi = whole[whole.index(after: comma)..<z].trimmingCharacters(in: .whitespaces)
                text = "\(lo) \(open) \(v) \(close) \(hi)"
            }
        }
        guard text.contains(where: { relations.contains($0) }), !text.contains("=") else { return nil }
        // Pieces between the relations, and the relations.
        var pieces: [String] = [], signs: [Character] = [], current = ""
        for c in text {
            if relations.contains(c) { pieces.append(current); signs.append(c); current = "" } else { current.append(c) }
        }
        pieces.append(current)
        pieces = pieces.map { $0.trimmingCharacters(in: .whitespaces) }
        guard pieces.count == signs.count + 1, (1...2).contains(signs.count), !pieces.contains(where: \.isEmpty) else { return nil }
        let letter = pieces.first { $0.count == 1 && $0.first!.isLetter && $0.first!.isASCII }
        guard let name = letter else { return nil }
        var degrees = false
        func bound(_ s: String) -> Double? {
            if s.contains("°") { degrees = true }
            return (try? Parser.constant(s.replacingOccurrences(of: "°", with: ""), physical: false))?.eval(0)
        }
        var lower: (Double, Bool)?, upper: (Double, Bool)?
        switch signs.count {
        case 1:
            guard let at = pieces.firstIndex(of: name), let v = bound(pieces[1 - at]) else { return nil }
            // x < v, v > x: an upper bound. x > v, v < x: a lower one.
            let below = (signs[0] == "<" || signs[0] == "≤") == (at == 0)
            let closed = signs[0] == "≤" || signs[0] == "≥"
            if below { upper = (v, closed) } else { lower = (v, closed) }
        default:
            guard pieces[1] == name, let a = bound(pieces[0]), let b = bound(pieces[2]),
                  Set(signs.map { $0 == "<" || $0 == "≤" }).count == 1 else { return nil }
            let rising = signs[0] == "<" || signs[0] == "≤"
            let (first, second) = (signs[0] == "≤" || signs[0] == "≥", signs[1] == "≤" || signs[1] == "≥")
            if rising { lower = (a, first); upper = (b, second) } else { lower = (b, second); upper = (a, first) }
        }

        // The equation, with its unknown in degrees where the range is.
        func marked(_ e: String) -> String {
            e.replacingOccurrences(of: "(?<![A-Za-z0-9_])\(name)(?![A-Za-z0-9_°])", with: "\(name)°", options: .regularExpression)
        }
        degrees = degrees || Options.degrees
        var shown = equation
        var parsed = try? Parser.parse(Latex.plain(equation))
        if degrees, !equation.contains("°"), !equation.contains("deg") {
            let candidate = marked(equation)
            if let attempt = try? Parser.parse(Latex.plain(candidate)), angleUnit(attempt) != nil { shown = candidate; parsed = attempt }
        }
        guard let eq = parsed, eq.unknown == name, !eq.left.hasSum, !eq.right.hasSum else { return nil }
        let unit = angleUnit(eq)
        guard let found = numericRoots(eq) else { return nil }
        let tolerance = 1e-9
        let inside = found.sorted().filter { x in
            if let (lo, closed) = lower, closed ? x < lo - tolerance * max(1, abs(lo)) : x <= lo + tolerance * max(1, abs(lo)) { return false }
            if let (hi, closed) = upper, closed ? x > hi + tolerance * max(1, abs(hi)) : x >= hi - tolerance * max(1, abs(hi)) { return false }
            return true
        }
        // Past what was searched, there is nothing to say.
        if let lo = lower?.0, lo < -1000 { return nil }
        if let hi = upper?.0, hi > 1000 { return nil }
        guard lower != nil || upper != nil else { return nil }
        return Domain(equation: shown, name: name, lower: lower.map { ($0.0, $0.1) }, upper: upper.map { ($0.0, $0.1) },
                      degrees: unit == .degrees, unit: unit, roots: inside)
    }

    // 0° ≤ x < 360°, x > 0.
    var rangeText: String {
        func value(_ v: Double) -> String {
            if unit == .degrees { return degreesText(v) }
            if unit == .radians, Options.exact, let fraction = piFraction(v) { return fraction.plain }
            return decimal(v)
        }
        switch (lower, upper) {
        case (let lo?, let hi?): return "\(value(lo.value)) \(lo.closed ? "≤" : "<") \(name) \(hi.closed ? "≤" : "<") \(value(hi.value))"
        case (let lo?, nil): return "\(name) \(lo.closed ? "≥" : ">") \(value(lo.value))"
        case (nil, let hi?): return "\(name) \(hi.closed ? "≤" : "<") \(value(hi.value))"
        default: return ""
        }
    }

    var solution: Solution {
        guard !roots.isEmpty else { return Solution(exact: "No solution", approx: "None for \(rangeText).") }
        let shown = Array(roots.prefix(8))
        if let unit {
            return angleCard(name, shown, more: roots.count > shown.count, unit, range: rangeText)
        }
        let line = listRoots(shown, name, more: roots.count > shown.count)
        return Solution(exact: line.exact, approx: "for \(rangeText)")
    }

    var details: Details? {
        guard var d = Solver.details(equation) else { return nil }
        let shown = Array(roots.prefix(12))
        d.solutions = roots.isEmpty ? [t("No solution")] : shown.map { x in unit.map { angleLine(name, x, $0) } ?? solutionLine(name, x) }
        d.note = "These are the solutions for \(rangeText)\(roots.count > shown.count ? "; the first \(shown.count) are shown" : "")."
        d.roots = roots
        return d
    }

    var copyText: String { roots.map { String(format: "%.12g", $0) }.joined(separator: ", ") }
}
