import Foundation

// An expression in letters with no = in it is not solved but tidied: like terms are collected,
// 2x + 3x to 5x, and what every term has in common is taken out, xb + xc to x(b + c). Nothing is
// multiplied out for its own sake, and a quadratic is not factorised: that is what x² − 5x + 6 = 0
// is for.
//
// A card comes up only when the result is simpler than what was typed, with fewer terms or less
// in them, so that a + b, and x(b + c) typed that way already, bring up none.
struct Simplification {
    typealias Term = (coefficient: Double, powers: [String: Int])

    var expr: Expr
    var letters: [String]   // in the order they are first met, which is the order they are written in
    var terms: [Term]       // with like terms collected, in the order each is first met

    // MARK: Reading

    static func parse(_ input: String) -> Simplification? {
        // It must look like algebra and not like a word: something in it other than letters and
        // hyphens (wi-fi), and no run of four letters or more (rock+roll).
        guard input.contains(where: { $0.isNumber || "+*/^()".contains($0) }), !hasWord(input),
              let tokens = try? Parser.tokenize(input), !tokens.contains(.symbol("=")) else { return nil }

        var letters: [String] = []
        for token in tokens {
            if case .letter(let s) = token, !letters.contains(s) { letters.append(s) }
        }
        var state = Parser.State(tokens: tokens, unknown: "", bound: letters)
        guard !letters.isEmpty, let expr = try? state.expression(), state.at == tokens.count,
              let terms = collected(expr) else { return nil }
        let result = Simplification(expr: expr, letters: letters, terms: terms)
        return result.isSimpler ? result : nil
    }

    // Whether there is a run of four letters or more in it that is not a name the parser knows:
    // a word, then, and not letters multiplied together.
    static func hasWord(_ input: String) -> Bool {
        var spelled = input
        for name in Array(Greek.names.keys) + Functions.names + ["pi", "ans", "Ans", "clip"] { spelled = spelled.replacingOccurrences(of: name, with: " ") }
        return spelled.split(whereSeparator: { !($0.isLetter && $0.isASCII) }).contains { $0.count >= 4 }
    }

    // The expression as a sum of terms, each a number times letters to whole powers, which may
    // be below zero: z⁻¹, and x divided by y. Nil for what is not one: a letter under a root or a
    // sine, or a sum divided by or raised to a power below zero.
    static func collected(_ e: Expr) -> [Term]? {
        switch e {
        case .num(let v), .constant(_, let v):
            return v == 0 ? [] : [(v, [:])]
        case .index(let name):
            return [(1, [name: 1])]
        case .unknown, .sum, .call:
            return nil
        case .neg(let a):
            return collected(a).map { $0.map { (-$0.coefficient, $0.powers) } }
        case .op(let o, let a, let b):
            guard let l = collected(a), let r = collected(b) else { return nil }
            switch o {
            case "+": return sum(l + r)
            case "-": return sum(l + r.map { (-$0.coefficient, $0.powers) })
            case "*": return product(l, r)
            case "/":
                guard r.count == 1, r[0].coefficient != 0 else { return nil }
                return product(l, [(1 / r[0].coefficient, r[0].powers.mapValues { -$0 })])
            case "%": return nil
            default:
                let k = r.isEmpty ? 0 : r[0].coefficient
                guard r.count <= 1, r.first?.powers.isEmpty ?? true, abs(k) <= 8, k == k.rounded() else { return nil }
                if k < 0 {
                    guard l.count == 1 else { return nil }
                    return [(pow(l[0].coefficient, k), l[0].powers.mapValues { $0 * Int(k) })]
                }
                var out: [Term]? = [(1, [:])]
                for _ in 0..<Int(k) { out = out.flatMap { product($0, l) } }
                return out
            }
        }
    }

    // Like terms added together, each where the first of its kind stood; one that comes to
    // nothing is dropped.
    static func sum(_ terms: [Term]) -> [Term] {
        var out: [Term] = []
        for term in terms {
            if let i = out.firstIndex(where: { $0.powers == term.powers }) {
                out[i].coefficient = added(out[i].coefficient, term.coefficient)
            } else {
                out.append(term)
            }
        }
        return out.filter { $0.coefficient != 0 }
    }

    static func product(_ a: [Term], _ b: [Term]) -> [Term]? {
        guard a.count * b.count <= 64 else { return nil }
        var out: [Term] = []
        for x in a {
            for y in b { out.append((x.coefficient * y.coefficient, x.powers.merging(y.powers, uniquingKeysWith: +).filter { $0.value != 0 })) }
        }
        return sum(out)
    }

    // MARK: The common factor

    // What every term has in it: the highest whole number that divides every coefficient, and
    // each letter to the lowest power it has anywhere. Nil when that is nothing but 1, or there
    // is only the one term to take it out of.
    var factor: Term? {
        guard terms.count >= 2 else { return nil }
        var powers: [String: Int] = [:]
        for name in letters {
            let lowest = terms.map { $0.powers[name] ?? 0 }.min() ?? 0
            if lowest > 0 { powers[name] = lowest }
        }
        var number = 1.0
        if terms.allSatisfy({ abs($0.coefficient - $0.coefficient.rounded()) < 1e-9 && abs($0.coefficient) < 1e9 }) {
            number = Double(terms.reduce(0) { gcd($0, Int($1.coefficient.rounded())) })
            if terms.allSatisfy({ $0.coefficient < 0 }) { number = -number }
        }
        return number == 1 && powers.isEmpty ? nil : (number, powers)
    }

    // The terms with the common factor taken out of each.
    private func inside(_ factor: Term) -> [Term] {
        terms.map { term in
            let left = term.powers.merging(factor.powers) { has, taken in has - taken }.filter { $0.value > 0 }
            return (term.coefficient / factor.coefficient, left)
        }
    }

    // MARK: Whether it is worth showing

    // Fewer terms than were typed, or as many with less in them.
    private var isSimpler: Bool {
        func typed(_ e: Expr) -> Int {
            if case .op(let o, let a, let b) = e, o == "+" || o == "-" { return typed(a) + typed(b) }
            return 1
        }
        func parts(_ e: Expr) -> Int {
            switch e {
            case .num, .index, .unknown, .constant: return 1
            case .neg(let a), .call(_, let a): return parts(a)
            case .op(_, let a, let b): return parts(a) + parts(b)
            case .sum: return 1
            }
        }
        func parts(_ term: Term) -> Int {
            (term.coefficient == 1 && !term.powers.isEmpty ? 0 : 1) + term.powers.values.reduce(0) { $0 + (abs($1) > 1 ? 2 : 1) }
        }
        let count = factor == nil ? max(terms.count, 1) : 1
        let size = factor.map { parts($0) + inside($0).reduce(0) { $0 + parts($1) } } ?? max(terms.reduce(0) { $0 + parts($1) }, 1)
        return count < typed(expr) || (count == typed(expr) && size < parts(expr))
    }

    // MARK: Writing

    // 5x, x²y, −ab: the number, left out when it is 1, and the letters in the order they came.
    // Letters to powers below zero go under a line: 2x over y².
    private func math(_ term: Term, signed: Bool = true) -> Math {
        func letters(_ wanted: (Int) -> Bool) -> [Math] {
            self.letters.compactMap { name in
                guard let power = term.powers[name], wanted(power) else { return nil }
                return abs(power) == 1 ? t(name) : .power(t(name), t("\(abs(power))"))
            }
        }
        let size = abs(term.coefficient), above = letters { $0 > 0 }
        var below = letters { $0 < 0 }
        // A coefficient that is a fraction is written as one, its lower half with the letters
        // below the line: y over 77b, not 0.012987y over b.
        var number = decimal(size)
        if Options.exact, abs(size - size.rounded()) > 1e-9, let (p, q) = rational(size), q <= 1000, p != 0 {
            number = "\(p)"
            below.insert(t("\(q)"), at: 0)
        }
        var top: [Math] = number != "1" || above.isEmpty ? [t(number)] : []
        top += above
        let whole: Math = below.isEmpty ? .row(top) : .fraction(.row(top), .row(below))
        return signed && term.coefficient < 0 ? row(t("−"), whole) : whole
    }

    func math(_ terms: [Term]) -> Math {
        guard !terms.isEmpty else { return t("0") }
        // A sum begins with a term that is added where it has one: 3 − y, not −y + 3.
        var terms = terms
        if terms[0].coefficient < 0, let first = terms.firstIndex(where: { $0.coefficient > 0 }) { terms.insert(terms.remove(at: first), at: 0) }
        var parts: [Math] = []
        for (i, term) in terms.enumerated() {
            if i > 0 { parts.append(t(term.coefficient < 0 ? " − " : " + ")) }
            parts.append(math(term, signed: i == 0))
        }
        return .row(parts)
    }

    // The whole of it tidied: x(b + c), 5x, 2(x + 2).
    var result: Math {
        guard let factor else { return math(terms) }
        return row(math(factor), t("("), math(inside(factor)), t(")"))
    }

    var solution: Solution { Solution(exact: "= " + result.plain, approx: nil) }

    var details: Details {
        let typed = typeset(expr, "")
        var d = Details(name: "", equation: typed, steps: [], solutions: [row(t("= "), result)], note: nil, f: { _ in .nan }, roots: [])
        let sum = math(terms)
        // One term typed, m⁴z⁻¹·mz³, has its powers put together; several have their like terms collected.
        var single = true
        if case .op(let o, _, _) = expr, o == "+" || o == "-" { single = false }
        if sum.plain != typed.plain { d.steps.append(Step(label: single ? "Combining the powers" : "Collecting like terms", math: row(t("= "), sum))) }
        if factor != nil { d.steps.append(Step(label: "Taking out the common factor", math: row(t("= "), result))) }
        return d
    }
}

// A formula with several letters in it, turned round to give one of them: 1/(7b) = 11x/y is
// x = y/(77b). The letter is x, or y if there is no x, unless it is asked for by name with
// "x=?" after the equation. It can be done where the letter comes once, as itself, as one over
// itself (1/f = 1/u + 1/v), as its square (E = mv²/2) or as one over its square (F = kq/r²); not where it is in both, or under a sine.
struct Rearrangement {
    typealias Term = Simplification.Term

    var left: Expr, right: Expr
    var writer: Simplification   // the letters in the order they came, for writing terms out
    var letter: String
    var power: Int               // 1, −1, 2 or −2: how the letter comes
    var coefficient: [Term]      // what multiplies it
    var rest: [Term]             // everything else, taken to the other side
    var top: [Term], bottom: [Term]   // what the letter, or its power, is equal to

    // "…, x=?" or "… x=?" after an equation names the letter wanted.
    static func asked(_ input: String) -> (equation: String, letter: String)? {
        guard let match = input.range(of: "[,;\\s]+[A-Za-z_0-9θωλαβφρτμ]+\\s*=\\s*\\?\\s*$", options: .regularExpression) else { return nil }
        let name = input[match].trimmingCharacters(in: CharacterSet(charactersIn: ",; ?=").union(.whitespaces))
        guard let token = try? Parser.tokenize(name), token.count == 1, case .letter(let letter) = token[0] else { return nil }
        return (String(input[..<match.lowerBound]), letter)
    }

    static func parse(_ input: String, for wanted: String? = nil) -> Rearrangement? {
        guard let tokens = try? Parser.tokenize(input), tokens.filter({ $0 == .symbol("=") }).count == 1 else { return nil }
        var letters: [String] = []
        for token in tokens {
            if case .letter(let s) = token, !letters.contains(s) { letters.append(s) }
        }
        guard letters.count >= 2, let letter = wanted ?? (letters.contains("x") ? "x" : nil), letters.contains(letter),
              !Simplification.hasWord(input) else { return nil }
        var state = Parser.State(tokens: tokens, unknown: "", bound: letters)
        guard let left = try? state.expression(), state.take("="), let right = try? state.expression(), state.at == tokens.count,
              let l = Simplification.collected(left), let r = Simplification.collected(right) else { return nil }
        // y = mx + b is already a formula, for y. It is turned round only when that is asked for.
        if wanted == nil, case .index = left { return nil }

        // Everything on one side: the terms with the letter in, which must all have it to the
        // one power, and the rest.
        let all: [Term] = Simplification.sum(l + r.map { (-$0.coefficient, $0.powers) })
        let with = all.filter { $0.powers[letter] != nil }
        guard let power = with.first?.powers[letter], [1, -1, 2, -2].contains(power), with.allSatisfy({ $0.powers[letter] == power }) else { return nil }
        var coefficient: [Term] = with.map { ($0.coefficient, $0.powers.filter { $0.key != letter }) }
        var rest: [Term] = all.filter { $0.powers[letter] == nil }.map { (-$0.coefficient, $0.powers) }
        // Written with the letter's side positive: 11x/y = 1/(7b), not −11x/y = −1/(7b).
        if coefficient.allSatisfy({ $0.coefficient < 0 }) {
            coefficient = coefficient.map { (-$0.coefficient, $0.powers) }
            rest = rest.map { (-$0.coefficient, $0.powers) }
        }
        guard !rest.isEmpty || power > 0 else { return nil }

        // letter^power = rest / coefficient; and for one over the letter, the other way up.
        var top: [Term] = power < 0 ? coefficient : rest, bottom: [Term] = power < 0 ? rest : coefficient
        // Divided through by a number, or one term by another; a sum over letters is left as
        // the one fraction, (v − u)/a.
        if bottom.count == 1, bottom[0].coefficient != 0, bottom[0].powers.isEmpty || top.count == 1 {
            top = Simplification.product(top, [(1 / bottom[0].coefficient, bottom[0].powers.mapValues { -$0 })]) ?? top
            bottom = [(1, [:])]
        } else {
            // No letter left under a line within either: both are multiplied through by whatever clears them.
            for name in letters {
                let lowest = (top + bottom).map { $0.powers[name] ?? 0 }.min() ?? 0
                guard lowest < 0, let a = Simplification.product(top, [(1, [name: -lowest])]),
                      let b = Simplification.product(bottom, [(1, [name: -lowest])]) else { continue }
                (top, bottom) = (a, b)
            }
            if bottom.allSatisfy({ $0.coefficient < 0 }) {
                top = top.map { (-$0.coefficient, $0.powers) }
                bottom = bottom.map { (-$0.coefficient, $0.powers) }
            }
        }
        // The letter wanted is written last in a term: ax + bx.
        let writer = Simplification(expr: .num(0), letters: letters.filter { $0 != letter } + [letter], terms: [])
        return Rearrangement(left: left, right: right, writer: writer, letter: letter, power: power,
                             coefficient: coefficient, rest: rest, top: top, bottom: bottom)
    }

    private var quotient: Math {
        if bottom.count == 1, bottom[0].powers.isEmpty, bottom[0].coefficient == 1 { return writer.math(top) }
        return .fraction(writer.math(top), writer.math(bottom))
    }

    // x = y/(77b); for a square, both roots.
    var result: Math {
        abs(power) == 2 ? row(t("\(letter) = ±"), .root(quotient)) : row(t("\(letter) = "), quotient)
    }

    var solution: Solution { Solution(exact: result.plain, approx: nil) }

    var details: Details {
        var d = Details(name: letter, equation: row(typeset(left, ""), t(" = "), typeset(right, "")), steps: [], solutions: [result],
                        note: nil, f: { _ in .nan }, roots: [])
        // The terms with the letter in on the left, as they stand, and the rest on the right.
        let withLetter: [Term] = coefficient.map { ($0.coefficient, $0.powers.merging([letter: power]) { a, _ in a }) }
        let gathered = row(writer.math(withLetter), t(" = "), writer.math(rest))
        if gathered.plain != d.equation.plain { d.steps.append(Step(label: "Collecting the terms in \(letter)", math: gathered)) }
        if abs(power) == 2 {
            d.steps.append(Step(label: "Isolating \(letter)²", math: row(.power(t(letter), t("2")), t(" = "), quotient)))
            d.steps.append(Step(label: "Taking the square root", math: result))
        } else {
            d.steps.append(Step(label: "Hence", math: result))
        }
        return d
    }
}
