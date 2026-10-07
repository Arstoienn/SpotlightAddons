import Foundation

// A sequence given by some of its terms: u_1 = 12, u_5 = 29. It is taken to be arithmetic, with a
// common difference d, and to be geometric, with a common ratio r, and whichever it can be is
// worked out: d, r, the first term, and what is asked for: u_10 = ?, S_10 = ?. A first term with d
// or with r given is enough to say what it is.
struct Sequence {
    struct Progression {
        var geometric: Bool
        var first: Double          // u_1
        var step: Double           // d or r
        var exactStep: String      // 17/4, ±(29/12)^(1/4)
        var alsoNegative = false   // r and −r both fit, the terms being an even number of steps apart

        var symbol: String { geometric ? "r" : "d" }
    }

    var letter: String
    var terms: [(index: Int, value: Double)]
    var progressions: [Progression]
    var queries: [String]         // u_10, S_10
    var given: String
    var wanted: Bool?             // asked for the difference (false) or the ratio (true) by name, d or r
    var failure: String?          // what is asked for does not exist

    // MARK: Reading

    static func parse(_ input: String) -> Sequence? {
        let parts = LinearSystem.parts(input)
        guard parts.count >= 2 else { return nil }
        var letter: String?
        var terms: [Int: Double] = [:]
        var d: Double?, r: Double?
        var queries: [String] = []
        var wanted: Bool?
        // The letters that have terms written with a subscript: a term written u+1 or u1 beside them is a slip for u_1.
        var lettered = Set<String>()
        for part in parts {
            if let m = part.range(of: "^\\s*([A-Za-z])_\\{?[0-9]+\\}?\\s*=", options: .regularExpression) { lettered.insert(String(part[m].first { $0.isLetter }!)) }
        }
        for part in parts {
            // d and r by themselves, with or without ? or =?: the difference, or the ratio, is what is wanted.
            let bare = part.replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "?", with: "").trimmingCharacters(in: .whitespaces)
            if (bare == "d" || bare == "r"), !part.contains("=") || part.hasSuffix("?") {
                wanted = bare == "r"
                continue
            }
            let sides = part.split(separator: "=", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard sides.count == 2 else { return nil }
            var (left, right) = (sides[0], sides[1])
            if let m = left.range(of: "^([A-Za-z])[+\\-−]?([0-9]+)$", options: .regularExpression), lettered.contains(String(left.first!)) {
                left = "\(left.first!)_\(left[m].filter(\.isNumber))"
            }
            let asked = right == "?"
            let value: Double? = asked ? nil : (try? Parser.constant(right, physical: false))?.eval(0)
            guard asked || (value?.isFinite ?? false) else { return nil }
            if let m = left.range(of: "^([A-Za-z])_\\{?([0-9]+)\\}?$", options: .regularExpression) {
                let text = String(left[m])
                let name = String(text.first!), index = Int(text.filter(\.isNumber))!
                if name == "S" {
                    guard asked else { return nil }
                    queries.append("S_\(index)")
                    continue
                }
                if let l = letter, l != name { return nil }
                letter = name
                if asked { queries.append("\(name)_\(index)") }
                else if let known = terms[index], known != value { return nil }
                else { terms[index] = value }
            } else if left == "d" || left == "r" {
                if asked { wanted = left == "r" } else if left == "d" { d = value } else { r = value }
            } else {
                return nil
            }
        }
        guard let letter, !terms.isEmpty else { return nil }
        let known = terms.sorted { $0.key < $1.key }.map { (index: $0.key, value: $0.value) }
        guard known.count >= 2 || d != nil || r != nil else { return nil }
        var progressions: [Progression] = []

        // Arithmetic: from d if it is given, else from the first two terms; the rest must agree.
        func arithmetic() -> Progression? {
            let step: Double
            if let d { step = d } else if known.count >= 2 { step = (known[1].value - known[0].value) / Double(known[1].index - known[0].index) } else { return nil }
            guard known.allSatisfy({ abs(known[0].value + step * Double($0.index - known[0].index) - $0.value) <= 1e-9 * max(1, abs($0.value)) }) else { return nil }
            let first = known[0].value - step * Double(known[0].index - 1)
            return Progression(geometric: false, first: first, step: step, exactStep: number(step))
        }
        func geometric() -> Progression? {
            if let r {
                guard r != 0, known[0].value != 0 else { return nil }
                guard known.allSatisfy({ abs(known[0].value * pow(r, Double($0.index - known[0].index)) - $0.value) <= 1e-9 * max(1, abs($0.value)) }) else { return nil }
                return Progression(geometric: true, first: known[0].value / pow(r, Double(known[0].index - 1)), step: r, exactStep: number(r))
            }
            guard known.count >= 2, known[0].value != 0 else { return nil }
            let gap = known[1].index - known[0].index
            let ratio = known[1].value / known[0].value
            guard ratio != 0, !(ratio < 0 && gap % 2 == 0) else { return nil }
            let magnitude = pow(abs(ratio), 1 / Double(gap))
            let step = ratio < 0 ? -magnitude : magnitude
            // The rest must agree for r, or for −r where that is as good.
            func fits(_ q: Double) -> Bool { known.allSatisfy { abs(known[0].value * pow(q, Double($0.index - known[0].index)) - $0.value) <= 1e-9 * max(1, abs($0.value)) } }
            let both = gap % 2 == 0 && ratio > 0 && fits(magnitude) && fits(-magnitude)
            guard fits(step) || both else { return nil }
            var exact = exactRoot(ratio, gap)
            if both { exact = "±" + exact }
            return Progression(geometric: true, first: known[0].value / pow(step, Double(known[0].index - 1)), step: step, exactStep: exact, alsoNegative: both)
        }
        if r == nil, wanted != true, let a = arithmetic() { progressions.append(a) }
        if d == nil, wanted != false, let g = geometric() { progressions.append(g) }
        // Nothing is said until it is asked for: d, r, a term, or a sum. Before that it is only terms.
        guard wanted != nil || !queries.isEmpty else { return nil }
        var failure: String?
        if progressions.isEmpty {
            // Asked for by name, it is said why there is none.
            guard let wanted else { return nil }
            failure = wanted ? "These terms are not those of a geometric sequence: no common ratio fits them."
                             : "These terms are not those of an arithmetic sequence: no common difference fits them."
        }
        return Sequence(letter: letter, terms: known, progressions: progressions, queries: queries, given: parts.joined(separator: ", "), wanted: wanted, failure: failure)
    }

    // MARK: Numbers

    static func number(_ x: Double) -> String {
        if let (p, q) = rational(x), abs(Double(p) / Double(q) - x) <= 1e-12 * max(1, abs(x)) { return fraction(p, q) }
        return decimal(x)
    }

    // u_n = 12·r^(n − 1); or, where r may be taken with either sign, from the term that was given: 6·r^(n − 2).
    private func geometricTerm(_ p: Progression) -> String {
        if p.alsoNegative, let g = terms.first { return "\(letter)_n = \(Sequence.number(g.value))·r^(n − \(g.index))" }
        return "\(letter)_n = \(Sequence.number(p.first))·r^(n − 1)"
    }

    static func paren(_ x: Double) -> String { x < 0 ? "(\(number(x)))" : number(x) }

    // The k-th root of a positive ratio: whole or rational where it is, and (29/12)^(1/4) where it is not.
    static func exactRoot(_ ratio: Double, _ k: Int) -> String {
        let positive = abs(ratio)
        // A square root is written as √(P/Q) = (a√m)/Q, in lowest terms.
        if k == 2, let (p, q) = rational(positive) {
            let (a, m) = squareFactor(p * q)
            let g = max(gcd(a, q), 1)
            let (top, bottom) = (a / g, q / g)
            let radical = m == 1 ? "\(top)" : (top == 1 ? "" : "\(top)") + "√\(m)"
            let root = bottom == 1 ? radical : m == 1 ? fraction(top, bottom) : "\(radical)/\(bottom)"
            return (ratio < 0 ? "−" : "") + root
        }
        if let (p, q) = rational(positive) {
            let a = pow(Double(p), 1 / Double(k)).rounded(), b = pow(Double(q), 1 / Double(k)).rounded()
            if pow(a, Double(k)) == Double(p), pow(b, Double(k)) == Double(q) {
                let root = fraction(Int(a), Int(b))
                return ratio < 0 ? "−" + root : root
            }
            let inside = q == 1 ? "\(p)" : "(\(p)/\(q))"
            return (ratio < 0 ? "−" : "") + inside + "^(1/\(k))"
        }
        return decimal(pow(positive, 1 / Double(k))) 
    }

    // The nth term, and the sum of the first n.
    private func term(_ p: Progression, _ n: Int, sign: Double = 1) -> Double {
        let step = p.step * sign
        // With r of either sign, the terms are measured from one that was given, whose value is the same for both.
        if p.geometric, p.alsoNegative, let g = terms.first { return g.value * pow(step, Double(n - g.index)) }
        return p.geometric ? p.first * pow(step, Double(n - 1)) : p.first + step * Double(n - 1)
    }

    private func sum(_ p: Progression, _ n: Int, sign: Double = 1) -> Double {
        if p.geometric, p.alsoNegative { return (1...max(n, 1)).reduce(0) { $0 + term(p, $1, sign: sign) } }
        let step = p.step * sign
        if !p.geometric { return Double(n) / 2 * (2 * p.first + Double(n - 1) * step) }
        return step == 1 ? Double(n) * p.first : p.first * (1 - pow(step, Double(n))) / (1 - step)
    }

    // MARK: Showing

    private func asked(_ p: Progression, _ q: String) -> String? {
        let parts = q.split(separator: "_")
        if q == "d", !p.geometric { return "d = \(Sequence.number(p.step))" }
        if q == "r", p.geometric { return "r = \(p.exactStep)" }
        guard parts.count == 2, let n = Int(parts[1]) else { return nil }
        let isSum = parts[0] == "S"
        func value(_ sign: Double) -> Double { isSum ? sum(p, n, sign: sign) : term(p, n, sign: sign) }
        let (a, b) = (value(1), value(-1))
        let text = Sequence.number(a)
        if p.alsoNegative, abs(a - b) > 1e-9 * max(1, abs(a)) {
            let exact = isExact(a) && isExact(b)
            return "\(q) \(exact ? "=" : "≈") \(exact ? Sequence.number(a) : decimal(a)) or \(exact ? Sequence.number(b) : decimal(b))"
        }
        return "\(q) = \(text)"
    }

    private func name(_ p: Progression) -> String { p.geometric ? "Geometric" : "Arithmetic" }

    var solution: Solution {
        if let failure { return Solution(exact: wanted == true ? "No common ratio" : "No common difference", approx: failure) }
        let both = progressions.count == 2
        var lines: [String] = []
        for p in progressions {
            let answer: String
            if queries.isEmpty {
                answer = p.geometric ? "r = \(p.exactStep)" + (p.exactStep.contains("^") || p.exactStep.contains("√") || p.exactStep.contains("/") ? " ≈ \(p.alsoNegative ? "±" : "")\(decimal(abs(p.step)))" : "") : "d = \(Sequence.number(p.step))"
            } else {
                answer = queries.compactMap { asked(p, $0) }.joined(separator: ", ")
            }
            lines.append(both ? "\(name(p)): \(answer)" : answer)
        }
        if both { return Solution(exact: lines[0], approx: lines[1]) }
        let p = progressions[0]
        // The ratio or the difference by name: what it is, and its decimal where it is not a whole or a fraction.
        if wanted != nil, queries.isEmpty {
            let general = p.geometric ? geometricTerm(p) : "\(letter)_n = \(Sequence.number(p.first)) + \(Sequence.number(p.step).contains("/") ? "(\(Sequence.number(p.step)))" : Sequence.number(p.step))(n − 1)"
            if p.geometric, p.exactStep.contains("^") || p.exactStep.contains("√") { return Solution(exact: "r = \(p.exactStep)", approx: "≈ \(p.alsoNegative ? "±" : "")\(decimal(abs(p.step))), \(general)") }
            return Solution(exact: "\(p.symbol) = \(p.exactStep)", approx: general)
        }
        let general = p.geometric ? geometricTerm(p).replacingOccurrences(of: "\(letter)_n", with: "u_n") : "u_n = \(Sequence.number(p.first)) + \(Sequence.number(p.step).contains("/") ? "(\(Sequence.number(p.step)))" : Sequence.number(p.step))(n − 1)"
        return Solution(exact: lines[0], approx: queries.isEmpty ? general.replacingOccurrences(of: "u_n", with: "\(letter)_n") : "u_1 = \(Sequence.number(p.first)), \(p.symbol) = \(p.exactStep)")
    }

    var details: Details {
        var d = Details(name: "n", equation: t(given), steps: [], solutions: [], note: nil, f: { _ in .nan }, roots: [])
        let first = terms[0]
        for p in progressions {
            let h = name(p) + " sequence"
            if p.geometric {
                if terms.count >= 2 {
                    let second = terms[1], gap = second.index - first.index
                    d.steps.append(Step(label: "\(h): the ratio of two terms", math: t("\(letter)_\(second.index)/\(letter)_\(first.index) = \(Sequence.number(second.value))/\(Sequence.number(first.value))"),
                                        note: "In a geometric sequence each term is r times the one before, so \(letter)_\(second.index) = \(letter)_\(first.index)·r^\(gap)."))
                    d.steps.append(Step(label: "Taking the root", math: t("r\(superscript(gap)) = \(Sequence.number(second.value / first.value)), so r = \(p.exactStep)\(p.exactStep.contains("^") || p.exactStep.contains("√") ? " ≈ \(p.alsoNegative ? "±" : "")\(decimal(abs(p.step)))" : "")")))
                }
                if first.index != 1, !p.alsoNegative { d.steps.append(Step(label: "Finding the first term", math: t("\(letter)_1 = \(Sequence.number(first.value))/r^\(first.index - 1) = \(Sequence.number(p.first))"))) }
                d.steps.append(Step(label: "Writing the general term", math: t(geometricTerm(p)), note: p.alsoNegative ? "r may be taken with either sign, the terms given being an even number of steps apart; the first term is then \(Sequence.number(p.first)) or the same with the sign of r^\(first.index - 1)." : nil))
                if !p.alsoNegative { d.steps.append(Step(label: "Writing the sum of n terms", math: t("S_n = \(Sequence.number(p.first))(1 − r^n)/(1 − r)"))) }
            } else {
                if terms.count >= 2 {
                    let second = terms[1], gap = second.index - first.index
                    d.steps.append(Step(label: "\(h): the difference of two terms", math: t("\(letter)_\(second.index) − \(letter)_\(first.index) = \(Sequence.number(second.value)) − \(Sequence.number(first.value)) = \(Sequence.number(second.value - first.value))"),
                                        note: "In an arithmetic sequence each term is d more than the one before, so \(letter)_\(second.index) = \(letter)_\(first.index) + \(gap)d."))
                    let quotient = "\(Sequence.number(second.value - first.value))/\(gap)"
                    d.steps.append(Step(label: "Dividing by the number of steps", math: t("d = \(quotient)" + (quotient == Sequence.number(p.step) ? "" : " = \(Sequence.number(p.step))"))))
                }
                if first.index != 1 { d.steps.append(Step(label: "Finding the first term", math: t("\(letter)_1 = \(Sequence.number(first.value)) − \(first.index - 1)·\(Sequence.number(p.step).contains("/") ? "(\(Sequence.number(p.step)))" : Sequence.number(p.step)) = \(Sequence.number(p.first))"))) }
                let step = Sequence.number(p.step)
                d.steps.append(Step(label: "Writing the general term", math: t("\(letter)_n = \(Sequence.number(p.first)) + \(step.contains("/") ? "(\(step))" : step)(n − 1)")))
                d.steps.append(Step(label: "Writing the sum of n terms", math: t("S_n = n/2·(2·\(Sequence.paren(p.first)) + (n − 1)·\(step.contains("/") ? "(\(step))" : step))")))
            }
            for q in queries { if let line = asked(p, q) { d.steps.append(Step(label: "Evaluating \(q)", math: t(line))) } }
        }
        let s = solution
        d.solutions = [t(s.exact)] + (s.approx.map { [t($0)] } ?? [])
        d.graph = graph()
        return d
    }

    // The terms against their numbers, with the line or curve through them where there is one: a
    // geometric sequence of negative ratio alternates, and has dots only.
    private func graph() -> Graph? {
        guard !progressions.isEmpty else { return nil }
        var curves: [Graph.Curve] = []
        var points = terms.map { CGPoint(x: Double($0.index), y: $0.value) }
        let first = terms[0]
        func label(_ p: Progression, _ sign: Double) -> Math {
            let step = p.step * sign
            let words = p.geometric ? "\(letter)_n = geometric, r = \(Sequence.number(step))" : "\(letter)_n = arithmetic, d = \(Sequence.number(step))"
            return t(words)
        }
        for p in progressions {
            for sign in (p.geometric && p.alsoNegative ? [1.0, -1.0] : [1.0]) {
                let step = p.step * sign
                if p.geometric {
                    if step > 0 {
                        let anchor = p.alsoNegative ? first : (index: 1, value: p.first)
                        curves.append(Graph.Curve(shape: .function { n in anchor.value * pow(step, n - Double(anchor.index)) }, label: label(p, sign)))
                    } else {
                        for n in 1...8 { points.append(CGPoint(x: Double(n), y: term(p, n, sign: sign))) }
                    }
                } else {
                    curves.append(Graph.Curve(shape: .function { n in p.first + step * (n - 1) }, label: label(p, sign)))
                }
            }
        }
        return Graph(xName: "n", yName: "\(letter)_n", curves: curves, points: points)
    }

    var copyText: String {
        guard let p = progressions.first else { return "" }
        if let q = queries.first, q.contains("_"), let n = Int(q.split(separator: "_")[1]) {
            return String(format: "%.12g", q.hasPrefix("S") ? sum(p, n) : term(p, n))
        }
        return String(format: "%.12g", p.step)
    }

    var values: [Double] { [Double(copyText) ?? .nan].filter { !$0.isNaN } }
}
