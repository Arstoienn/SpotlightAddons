import Foundation

// An expression in letters with no = in it is not solved but tidied: like terms are collected,
// 2x + 3x to 5x, and what every term has in common is taken out, xb + xc to x(b + c). Nothing is
// multiplied out for its own sake. A polynomial in one letter that factorises, x² − 5x + 6, is
// factorised by the pipeline (Pipeline.swift), as factor( ) would.
//
// A card comes up only when the result is simpler than what was typed, with fewer terms or less
// in them, so that a + b, and x(b + c) typed that way already, bring up none.
struct Simplification {
    typealias Term = (coefficient: Number, powers: [String: Int])

    var expr: Expr
    var letters: [String]   // in the order they are first met, which is the order they are written in
    var terms: [Term]       // with like terms collected, in the order each is first met
    var multiplied = false  // a sum raised to a power, or sums multiplied, which are written out

    // MARK: Reading

    // always: the card is wanted whether or not it is simpler, as it is for an expression with values
    // given and letters left, x + y with x = 2 being y + 2.
    static func parse(_ input: String, always: Bool = false, constants: Set<String> = []) -> Simplification? {
        // It must look like algebra and not like a word: something in it other than letters and
        // hyphens (wi-fi), and no run of four letters or more (rock+roll).
        guard input.contains(where: { $0.isNumber || "+*/^()".contains($0) }), !hasWord(input),
              let tokens = try? Parser.tokenize(input), !tokens.contains(.symbol("=")) else { return nil }

        var letters: [String] = []
        for token in tokens {
            if case .letter(let s) = token, !letters.contains(s), !constants.contains(s) { letters.append(s) }
        }
        var state = Parser.State(tokens: tokens, unknown: "", constants: constants, bound: letters)
        guard !letters.isEmpty, let expr = try? state.expression(), state.at == tokens.count,
              let terms = collected(expr) else { return nil }
        var result = Simplification(expr: expr, letters: letters, terms: terms)
        // A sine or a cosine among them is the trigonometric identities' to tidy, where they can:
        // 3sin²x + 3cos²x is 3, not 3(sin²x + cos²x).
        if !always, result.names.contains(where: { name in ["sin", "cos", "tan", "sec", "csc", "cot"].contains { name.hasPrefix($0) } }),
           TrigSimplification.parse(input) != nil { return nil }
        // (a+b)^2 and (x+1)(x−1) are multiplied out: that is what they are typed for.
        if multipliesSums(expr) || always, terms.count >= 1 {
            result.multiplied = multipliesSums(expr)
            result.terms = terms.sorted { a, b in
                let (da, db) = (a.powers.values.reduce(0, +), b.powers.values.reduce(0, +))
                if da != db { return da > db }
                for letter in letters where a.powers[letter] != b.powers[letter] { return (a.powers[letter] ?? 0) > (b.powers[letter] ?? 0) }
                return false
            }
            return result
        }
        return result.isSimpler ? result : nil
    }

    // A sum to a power, nought and one included (which have little to write out), or two sums multiplied.
    private static func multipliesSums(_ e: Expr) -> Bool {
        func isSum(_ e: Expr) -> Bool {
            if case .op(let o, _, _) = e, o == "+" || o == "-" { return true }
            if case .neg(let a) = e { return isSum(a) }
            return false
        }
        switch e {
        case .op("^", let base, .num(let n)): return (isSum(base) && n == n.rounded() && n >= 0 && n <= 64) || multipliesSums(base)
        case .op("*", let a, let b): return (isSum(a) && isSum(b)) || multipliesSums(a) || multipliesSums(b)
        case .op(_, let a, let b): return multipliesSums(a) || multipliesSums(b)
        case .neg(let a): return multipliesSums(a)
        default: return false
        }
    }

    // Whether there is a run of four letters or more in it that is not a name the parser knows:
    // a word, then, and not letters multiplied together.
    static func hasWord(_ input: String) -> Bool {
        var spelled = input
        for name in Array(Greek.names.keys) + Functions.names + ["pi", "ans", "Ans", "clip"] { spelled = spelled.replacingOccurrences(of: name, with: " ") }
        return spelled.split(whereSeparator: { !($0.isLetter && $0.isASCII) }).contains { $0.count >= 4 }
    }

    // The expression as a sum of terms, each an exact number times letters to whole powers, which
    // may be below zero: z⁻¹, and x divided by y. A function of the letters, sin(x) or √x, is one
    // thing among them, so that 2sin(x) + 3sin(x) is 5sin(x). Nil for a sum divided by or raised
    // to a power below zero, or for one that would multiply out to more than 400 terms.
    static func collected(_ e: Expr) -> [Term]? {
        // A part with no letter in it that works out exactly is that number: x/3! is x/6, and
        // C(8, 3)(2x)³ is 448x³. One that is irrational, √2, is left as it is.
        if case .exact(let r)? = e.number { return r.top == 0 ? [] : [(.exact(r), [:])] }
        switch e {
        case .num(let v):
            return v == 0 ? [] : [(Number(v), [:])]
        case .constant(_, let v):
            return v == 0 ? [] : [(.approx(v), [:])]
        case .index(let name):
            return [(1, [name: 1])]
        case .unknown, .sum:
            return nil
        case .call, .apply:
            return e.number == nil ? [(1, [typeset(e, "").plain: 1])] : nil
        case .neg(let a):
            return collected(a).map { $0.map { (-$0.coefficient, $0.powers) } }
        case .op(let o, let a, let b):
            guard let l = collected(a), let r = collected(b) else { return nil }
            switch o {
            case "+": return sum(l + r)
            case "-": return sum(l + r.map { (-$0.coefficient, $0.powers) })
            case "*": return product(l, r)
            case "/":
                guard r.count == 1, !r[0].coefficient.isZero else { return nil }
                return product(l, [(1 / r[0].coefficient, r[0].powers.mapValues { -$0 })])
            // C(n, 2) with a letter in it is one thing, as a function of it is.
            case _ where Binary.table[o] != nil:
                return [(1, [typeset(e, "").plain: 1])]
            default:
                guard r.count <= 1, r.first?.powers.isEmpty ?? true else { return nil }
                guard let k = (r.first?.coefficient ?? 0).rational, k.isWhole, abs(k.top) <= 1000 else { return nil }
                let n = k.top
                // One term to any whole power: its number to that power, and each power in it
                // multiplied by it, (2x³)¹² being 4096x³⁶.
                if l.count == 1 {
                    guard n >= 0 || !l[0].coefficient.isZero else { return nil }
                    return [(l[0].coefficient.power(.exact(k)), l[0].powers.mapValues { $0 * n }.filter { $0.value != 0 })]
                }
                // A sum is multiplied out, which is cut short only by the terms it would come to.
                guard n >= 0, n <= 64 else { return nil }
                var out: [Term]? = [(1, [:])]
                for _ in 0..<n { out = out.flatMap { product($0, l) } }
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
                out[i].coefficient = out[i].coefficient + term.coefficient
            } else {
                out.append(term)
            }
        }
        return out.filter { !$0.coefficient.isZero }
    }

    static func product(_ a: [Term], _ b: [Term]) -> [Term]? {
        guard a.count * b.count <= 4096 else { return nil }
        var out: [Term] = []
        for x in a {
            for y in b { out.append((x.coefficient * y.coefficient, x.powers.merging(y.powers, uniquingKeysWith: +).filter { $0.value != 0 })) }
        }
        let collected = sum(out)
        return collected.count <= 400 ? collected : nil
    }

    // The letters in the order they came, then whatever else is in the terms, sin(x), as it is met.
    var names: [String] {
        var out = letters
        for term in terms { for key in term.powers.keys.sorted() where !out.contains(key) { out.append(key) } }
        return out
    }

    // MARK: The common factor

    // What every term has in it: the highest whole number that divides every coefficient, and
    // each letter to the lowest power it has anywhere. Nil when that is nothing but 1, or there
    // is only the one term to take it out of.
    var factor: Term? {
        guard terms.count >= 2 else { return nil }
        var powers: [String: Int] = [:]
        for name in names {
            let lowest = terms.map { $0.powers[name] ?? 0 }.min() ?? 0
            if lowest > 0 { powers[name] = lowest }
        }
        var number: Number = 1
        if terms.allSatisfy({ $0.coefficient.rational?.isWhole == true && abs($0.coefficient.double) < 1e9 }) {
            number = Number(terms.reduce(0) { gcd($0, $1.coefficient.rational!.top) })
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
            case .apply(_, let args): return args.reduce(0) { $0 + parts($1) }
            }
        }
        // A function of the letters weighs what is inside it, so that sin(x + π/2) left as it was
        // is not counted simpler for being one thing.
        var weights: [String: Int] = [:]
        func weigh(_ e: Expr) {
            switch e {
            case .call(_, let a): weights[typeset(e, "").plain] = parts(a); weigh(a)
            case .apply(_, let args): weights[typeset(e, "").plain] = args.reduce(0) { $0 + parts($1) }; args.forEach(weigh)
            case .op(let o, let a, let b):
                if Binary.table[o] != nil { weights[typeset(e, "").plain] = parts(a) + parts(b) }
                weigh(a); weigh(b)
            case .neg(let a): weigh(a)
            default: break
            }
        }
        weigh(expr)
        func parts(_ term: Term) -> Int {
            (term.coefficient == 1 && !term.powers.isEmpty ? 0 : 1)
                + term.powers.reduce(0) { $0 + (weights[$1.key] ?? 1) + (abs($1.value) > 1 ? 1 : 0) }
        }
        let count = factor == nil ? max(terms.count, 1) : 1
        let size = factor.map { parts($0) + inside($0).reduce(0) { $0 + parts($1) } } ?? max(terms.reduce(0) { $0 + parts($1) }, 1)
        return count < typed(expr) || (count == typed(expr) && size < parts(expr))
    }

    // MARK: Writing

    // 5x, x²y, −ab: the number, left out when it is 1, and the letters in the order they came.
    // Letters to powers below zero go under a line: 2x over y².
    private func math(_ term: Term, signed: Bool = true) -> Math {
        let order = names + term.powers.keys.sorted().filter { !names.contains($0) }
        func letters(_ wanted: (Int) -> Bool) -> [Math] {
            order.compactMap { name in
                guard let power = term.powers[name], wanted(power) else { return nil }
                return abs(power) == 1 ? t(name) : .power(t(name), t("\(abs(power))"))
            }
        }
        let above = letters { $0 > 0 }
        var below = letters { $0 < 0 }
        // A coefficient that is a fraction is written as one, its lower half with the letters
        // below the line: y over 77b, and 35x⁴/2048; one shorter as the decimal it is, as typed
        // decimals are, is that decimal, 1.333333x. One known only as a decimal is rounded.
        var number: String
        switch term.coefficient.magnitude {
        // A whole number in full, 1399358844975; in powers of ten only where that is all of it, 5×10¹⁴.
        case .exact(let r) where r.isWhole:
            let short = decimal(r.double)
            number = Double(short.replacingOccurrences(of: "−", with: "-")) == r.double || short.contains("×") && Rational(decimal: r.double).map({ $0 == r }) == true && String(abs(r.top)).trimmingCharacters(in: CharacterSet(charactersIn: "0")).count <= 6 ? short : String(abs(r.top))
        case .exact(let r) where !Options.exact: number = decimal(r.double)
        case .exact(let r) where r.prefersFraction:
            number = "\(r.top)"
            below.insert(t("\(r.bottom)"), at: 0)
        // One worked from a physical constant is a decimal, as the constant is: 646.8 + 27.5v².
        case .approx(let v): number = decimal(v)
        // A decimal as typed is given to the figures chosen, or as the fraction it is to twelve
        // figures: 1.33333x, and 8x/7 for 1.142857142857x.
        case .exact(let r):
            let v = r.double
            if Options.exact, let (p, q) = rational(v), abs(Double(p) / Double(q) - v) <= 1e-12 * max(1, v), q > 1 {
                number = "\(p)"
                below.insert(t("\(q)"), at: 0)
            } else {
                number = decimal(v)
            }
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
        guard let factor, !multiplied else { return math(terms) }
        return row(math(factor), t("("), math(inside(factor)), t(")"))
    }

    var solution: Solution { Solution(exact: "= " + result.plain, approx: nil) }

    // (a + b)ⁿ = Σ C(n, k) aⁿ⁻ᵏ bᵏ: the coefficients C(n, 0) … C(n, n), the terms with a and b
    // written in (the first three, …, and the last, where there are more than seven), and the
    // terms worked out. Nil for anything but two terms to a whole power from 2 to 64.
    private var binomialSteps: [Step]? {
        guard case .op("^", let base, .num(let p)) = expr, p == p.rounded(), p >= 2, p <= 64,
              case .op(let o, let a, let bTyped) = base, o == "+" || o == "-" else { return nil }
        let n = Int(p)
        let b: Expr = o == "-" ? .neg(bTyped) : bTyped
        let coefficients = (0...n).map { k in Number.choose(Number(n), Number(k))?.description ?? "?" }
        // A part in brackets only where it needs them, (2x²)⁹ and (−3y)⁶ but x⁴; a 1 left out.
        func part(_ e: Expr, _ power: Int) -> Math? {
            guard power > 0 else { return nil }
            if case .num(1) = e { return nil }
            var bare = false
            switch e {
            case .index: bare = true
            case .num(let v): bare = v >= 0
            default: break
            }
            if !bare, power == 1, case .op("*", _, _) = e { bare = true }
            let m: Math = bare ? typeset(e, "") : .group(typeset(e, ""))
            return power == 1 ? m : .power(m, t("\(power)"))
        }
        func term(_ k: Int) -> Math {
            var parts: [Math] = coefficients[k] == "1" ? [] : [t(coefficients[k])]
            // 60x and 9·(2x²)⁸: a dot only before a bracket.
            for piece in [part(a, n - k), part(b, k)].compactMap({ $0 }) {
                var bracketed = false
                if case .group = piece { bracketed = true }
                if case .power(.group, _) = piece { bracketed = true }
                if !parts.isEmpty, bracketed { parts.append(t("·")) }
                parts.append(piece)
            }
            return parts.isEmpty ? t("1") : .row(parts)
        }
        let shown: [Int?] = n <= 6 ? Array(0...n) : [0, 1, 2, nil, n]
        var written: [Math] = [t("= ")]
        for (i, k) in shown.enumerated() {
            if i > 0 { written.append(t(" + ")) }
            written.append(k.map(term) ?? t("…"))
        }
        let row = n <= 12 ? coefficients.joined(separator: ", ")
                          : (coefficients.prefix(4) + ["…"] + coefficients.suffix(2)).joined(separator: ", ")
        return [
            Step(label: "Applying the binomial theorem", math: Math.row([.power(t("(a + b)"), t("n")), t(" = "), .bigOperator("∑", lower: t("k=0"), upper: t("n")),
                                                                          t(" "), .power(t(""), t("n")), t("C_k "), .power(t("a"), t("n−k")), .power(t("b"), t("k"))])),
            Step(label: "Writing the coefficients \(superscript(n))C_k, row \(n) of Pascal's triangle", math: t(row)),
            Step(label: "Substituting a = \(typeset(a, "").plain), b = \(typeset(b, "").plain)", math: .row(written)),
            Step(label: "Working out each term", math: .row([t("= "), math(terms)])),
        ]
    }

    var details: Details {
        let typed = typeset(expr, "")
        var d = Details(name: "", equation: typed, steps: [], solutions: [row(t("= "), result)], note: nil, f: { _ in .nan }, roots: [])
        // Two terms to a whole power, by the binomial theorem: the row of Pascal's triangle, each
        // term written with its coefficient, and then each worked out.
        if let steps = binomialSteps {
            d.steps = steps
            return d
        }
        let sum = math(terms)
        // One term typed, m⁴z⁻¹·mz³, has its powers put together; several have their like terms collected.
        var single = true
        if case .op(let o, _, _) = expr, o == "+" || o == "-" { single = false }
        if sum.plain != typed.plain { d.steps.append(Step(label: multiplied ? "Multiplying out and collecting like terms" : single ? "Combining the powers" : "Collecting like terms", math: row(t("= "), sum))) }
        if factor != nil, !multiplied { d.steps.append(Step(label: "Taking out the common factor", math: row(t("= "), result))) }
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
        guard let match = input.range(of: "[,;\\s]+[A-Za-z_0-9θωλαβφρτμεσ]+\\s*=\\s*\\?\\s*$", options: .regularExpression) else { return nil }
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
              !insideFunction(left, letter), !insideFunction(right, letter),
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

    // Whether the letter stands inside a function, sin(x), where it cannot be got at by moving terms.
    private static func insideFunction(_ e: Expr, _ letter: String) -> Bool {
        switch e {
        case .call(_, let a): return Grouped.mentions(a, [letter])
        case .apply(_, let args): return args.contains { Grouped.mentions($0, [letter]) }
        case .op(let o, let a, let b) where Binary.table[o] != nil: return Grouped.mentions(a, [letter]) || Grouped.mentions(b, [letter])
        case .op(_, let a, let b): return insideFunction(a, letter) || insideFunction(b, letter)
        case .neg(let a): return insideFunction(a, letter)
        case .sum: return Grouped.mentions(e, [letter])
        default: return false
        }
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
