import Foundation

// Statements about whole numbers proved, or shown false, as they are on paper:
//
//   p² − 8q − 11 = 0 has no integer solutions        by contradiction: modulo 8, p² ≡ 3, which no square is
//   n³ − n is divisible by 6, n² + n is even           directly: by taking the divisor out, or by cases on
//                                                      the remainder, n = 6k + r for each r
//   √2 is irrational                                   by contradiction: a/b in lowest terms cannot square to 2
//
// A claim that is not true is shown false by an example: n² + n + 1 is even fails for n = 0. One that is
// neither proved nor disproved by these means is said to be not settled, never guessed.
struct Proof {
    let claim: Math          // what is to be proved, as it reads
    let verdict: String      // the card's line: No integer solutions, 6 | n³ − n, False
    let method: String       // how: Proved by contradiction, modulo 8
    let steps: [Step]
    let conclusion: Math

    var solution: Solution { Solution(exact: verdict, approx: method) }
    var details: Details {
        var d = Details(name: "", equation: claim, steps: steps, solutions: [conclusion], note: nil, f: { _ in .nan }, roots: [])
        d.title = "Conclusion"
        d.graph = nil
        return d
    }

    // MARK: - Reading the claim

    static func parse(_ typed: String) -> Proof? {
        // As LaTeX too, as the panel copies a line: x^{2} - 2y^{2} = 1 has no integer solutions.
        let read = typed.contains("{") || typed.contains("\\") ? Latex.plain(typed) : typed
        var s = read.trimmingCharacters(in: .whitespaces)
        if s.hasSuffix(".") { s.removeLast() }
        s = s.replacingOccurrences(of: "^(?i)(prove|show)( that)?\\s+", with: "", options: .regularExpression)
        let lower = s.lowercased()
        func match(_ pattern: String) -> [String]? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
            return (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: s).map { String(s[$0]) } ?? "" }
        }
        let forAll = "(?:\\s+for\\s+(?:all|every|any)\\s+(?:integers?|whole\\s+numbers?)(?:\\s+[a-z](?:\\s*(?:,|and)\\s*[a-z])*)?)?"
        // √n is irrational.
        if let m = match("^(?:√|sqrt)\\s*\\(?\\s*([0-9]+)\\s*\\)?\\s+is\\s+irrational$"), let n = Int(m[1]) { return irrational(n) }
        // … is even, is odd, is divisible by d, is a multiple of d; d divides …, d | ….
        if let m = match("^(.+?)\\s+is\\s+(even|odd)" + forAll + "$") {
            return divisible(m[1], by: 2, remainder: m[2].lowercased() == "odd" ? 1 : 0)
        }
        if let m = match("^(.+?)\\s+is\\s+(?:divisible\\s+by|a\\s+multiple\\s+of)\\s+([0-9]+)" + forAll + "$"), let d = Int(m[2]) {
            return divisible(m[1], by: d, remainder: 0)
        }
        if let m = match("^([0-9]+)\\s*(?:divides|\\|)\\s*(.+?)" + forAll + "$"), let d = Int(m[1]) {
            return divisible(m[2], by: d, remainder: 0)
        }
        // An equation with no solutions in whole numbers, said in words or with ∈ ℤ.
        guard lower.contains("=") else { return nil }
        if let m = match("^(.+?=.+?)\\s+has\\s+no\\s+(?:integer|whole[- ]number)\\s+solutions?$")
            ?? match("^(.+?=.+?)\\s+has\\s+no\\s+solutions?\\s+in\\s+(?:the\\s+)?(?:integers|whole\\s+numbers|ℤ)$")
            ?? match("^(.+?=[^,]+?)\\s*,\\s*[a-z](?:\\s*,\\s*[a-z])*\\s*(?:∈|in)\\s*(?:ℤ|z|the\\s+integers|integers)$")
            ?? match("^(.+?=.+?)\\s+(?:for|with|over|in)\\s+(?:the\\s+)?integers(?:\\s+[a-z](?:\\s*(?:,|and)\\s*[a-z])*)?$") {
            return noIntegerSolutions(m[1])
        }
        return nil
    }

    // MARK: - Polynomials in whole numbers

    // A polynomial with whole-number coefficients, as its terms: 3p²q is (3, [p: 2, q: 1]).
    struct Poly {
        var terms: [(coefficient: Int, powers: [String: Int])]
        var letters: [String]

        static func read(_ text: String) -> (Poly, Expr)? {
            guard let tokens = try? Parser.tokenize(text) else { return nil }
            let letters = tokens.reduce(into: [String]()) { if case .letter(let l) = $1, !$0.contains(l) { $0.append(l) } }
            guard !letters.isEmpty, letters.count <= 3 else { return nil }
            var state = Parser.State(tokens: tokens, unknown: "", bound: letters)
            guard let expr = try? state.expression(), state.at == tokens.count else { return nil }
            return from(expr, letters).map { ($0, expr) }
        }

        static func from(_ expr: Expr, _ letters: [String]) -> Poly? {
            guard let collected = Simplification.collected(expr) else { return nil }
            var terms: [(Int, [String: Int])] = []
            for term in collected {
                guard case .exact(let r) = term.coefficient, r.bottom == 1 else { return nil }
                terms.append((r.top, term.powers))
            }
            return Poly(terms: terms, letters: letters)
        }

        func value(_ at: [String: Int], mod m: Int) -> Int {
            var total = 0
            for (c, powers) in terms {
                var v = ((c % m) + m) % m
                for (letter, p) in powers { for _ in 0..<p { v = v * (((at[letter] ?? 0) % m + m) % m) % m } }
                total = (total + v) % m
            }
            return total
        }

        func value(_ at: [String: Int]) -> Int? {
            var total = 0.0
            for (c, powers) in terms {
                var v = Double(c)
                for (letter, p) in powers { v *= pow(Double(at[letter] ?? 0), Double(p)) }
                total += v
            }
            return abs(total) < 9e15 ? Int(total) : nil
        }

        // Written as the rest of the app writes a polynomial.
        var math: Math {
            let terms = self.terms.map { (coefficient: Number($0.coefficient), powers: $0.powers) }
            let sorted = terms.sorted { a, b in
                let (da, db) = (a.powers.values.reduce(0, +), b.powers.values.reduce(0, +))
                if da != db { return da > db }
                for letter in letters where a.powers[letter] != b.powers[letter] { return (a.powers[letter] ?? 0) > (b.powers[letter] ?? 0) }
                return false
            }
            guard !sorted.isEmpty else { return t("0") }
            return Simplification(expr: .num(0), letters: letters, terms: sorted).math(sorted)
        }

        // Every way of giving each letter a remainder from 0 to m − 1.
        func residues(_ m: Int) -> [[String: Int]] {
            var all: [[String: Int]] = [[:]]
            for letter in letters { all = all.flatMap { base in (0..<m).map { var v = base; v[letter] = $0; return v } } }
            return all
        }
    }

    private static func letters(_ list: [String]) -> String {
        list.count <= 1 ? list.joined() : list.dropLast().joined(separator: ", ") + " and " + list.last!
    }

    // MARK: - No solutions in whole numbers, by contradiction

    static func noIntegerSolutions(_ equation: String) -> Proof? {
        let sides = equation.split(separator: "=", omittingEmptySubsequences: false).map(String.init)
        guard sides.count == 2, let (left, l) = Poly.read(sides[0]) ?? constant(sides[0]),
              let (right, r) = Poly.read(sides[1]) ?? constant(sides[1]) else { return nil }
        let names = (left.letters + right.letters).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        guard !names.isEmpty, names.count <= 3 else { return nil }
        guard let p = Poly.from(.op("-", l, r), names) else { return nil }
        let claim = row(typeset(l, ""), t(" = "), typeset(r, ""), t(" has no integer solutions"))
        let who = letters(names)

        // The least modulus at which no remainders satisfy it.
        for m in 2...16 where pow(Double(m), Double(names.count)) <= 5000 {
            guard !p.residues(m).contains(where: { p.value($0, mod: m) == 0 }) else { continue }
            var steps = [Step(label: "Supposing the contrary", math: row(p.math, t(" = 0")),
                              note: "Suppose there are integers \(who) for which this holds.")]
            // What is left modulo m, its number on the other side: p² ≡ 3 (mod 8).
            var reduced = p
            reduced.terms = p.terms.map { (($0.coefficient % m + m) % m, $0.powers) }.filter { $0.0 != 0 }
            let constant = reduced.terms.first { $0.powers.isEmpty }?.coefficient ?? 0
            var variable = reduced
            variable.terms = reduced.terms.filter { !$0.powers.isEmpty }
            // A letter whose every term is a multiple of m is gone: 8q modulo 8.
            variable.letters = names.filter { name in variable.terms.contains { $0.powers[name] != nil } }
            let target = (m - constant) % m
            steps.append(Step(label: "Reducing modulo \(m)", math: row(variable.math, t(" ≡ \(target)  (mod \(m))")),
                              note: "Every term whose coefficient is a multiple of \(m) is ≡ 0, and the number is taken to the other side."))
            // The values it can take: one letter's table, or the set of them over every remainder.
            let values = Set(variable.residues(m).map { variable.value($0, mod: m) }).sorted()
            if variable.letters.count == 1, let v = variable.letters.first, variable.terms.allSatisfy({ Array($0.powers.keys) == [v] }) {
                let table = (0..<m).map { r in "\(r) ↦ \(variable.value([v: r], mod: m))" }.joined(separator: ",  ")
                steps.append(Step(label: "Listing every remainder of \(v)", math: t(table),
                                  note: "Every integer \(v) leaves one of the remainders 0 to \(m - 1) on division by \(m); so " + variable.math.plain
                                        + " is ≡ one of " + values.map(String.init).joined(separator: ", ") + " (mod \(m))."))
            } else {
                steps.append(Step(label: "Trying every remainder", math: nil,
                                  note: "Over all remainders of \(who) modulo \(m), " + variable.math.plain + " is ≡ one of "
                                        + values.map(String.init).joined(separator: ", ") + " (mod \(m))."))
            }
            steps.append(Step(label: "Reaching a contradiction", math: nil,
                              note: "\(target) is not among them, so no integers \(who) satisfy the equation, contrary to the supposition."))
            let conclusion = row(typeset(l, ""), t(" = "), typeset(r, ""), t(" has no solution in integers"))
            steps.append(Step(label: "Hence", math: conclusion))
            return Proof(claim: claim, verdict: "No integer solutions", method: "Proved by contradiction, modulo \(m)", steps: steps, conclusion: conclusion)
        }
        // A solution among small numbers shows the claim false.
        if let found = search(p, { $0 == 0 }) {
            let shown = names.map { "\($0) = \(found[$0]!)" }.joined(separator: ", ")
            let conclusion = t("False: \(shown) is a solution")
            return Proof(claim: claim, verdict: "False", method: "\(shown) is a solution", steps: [
                Step(label: "Exhibiting a solution", math: t(shown), note: "With these, " + p.math.plain + " = 0; so the equation has integer solutions.")
            ], conclusion: conclusion)
        }
        return unsettled(claim, "There is no contradiction modulo 2 to 16, and no solution with each of \(who) between −30 and 30.")
    }

    private static func constant(_ text: String) -> (Poly, Expr)? {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)) else { return nil }
        return (Poly(terms: value == 0 ? [] : [(value, [:])], letters: []), .num(Double(value)))
    }

    // The first values, nearest 0, from −30 to 30 for each letter, that pass the test.
    private static func search(_ p: Poly, _ test: (Int) -> Bool) -> [String: Int]? {
        let order = [0] + (1...30).flatMap { [$0, -$0] }
        var tried = 0
        func go(_ i: Int, _ at: [String: Int]) -> [String: Int]? {
            if i == p.letters.count {
                tried += 1
                return p.value(at).map(test) == true ? at : nil
            }
            for v in order where tried < 300_000 {
                var next = at; next[p.letters[i]] = v
                if let found = go(i + 1, next) { return found }
            }
            return nil
        }
        return go(0, [:])
    }

    private static func unsettled(_ claim: Math, _ why: String) -> Proof {
        Proof(claim: claim, verdict: "Not settled", method: why, steps: [Step(label: "Why it is not settled", math: nil, note: why + " Neither a proof nor a counterexample was found.")],
              conclusion: t("Not settled"))
    }

    // MARK: - Divisible by d, directly

    static func divisible(_ text: String, by d: Int, remainder target: Int) -> Proof? {
        guard d >= 2, d <= 1000, let (p, expr) = Poly.read(text) else { return nil }
        let typed = typeset(expr, "")
        let what = d == 2 ? (target == 0 ? "even" : "odd") : "divisible by \(d)"
        let claim = row(typed, t(" is \(what) for every integer \(letters(p.letters))"))
        let verdict = d == 2 ? row(typed, t(" is \(what)")).plain : "\(d) | \(typed.plain)"
        // What it is to be: d(…) for divisible and even, 2(…) + 1 for odd.
        func written(_ q: Poly) -> Math {
            let inside = row(t("\(d)("), q.math, t(")"))
            return target == 0 ? inside : row(inside, t(" + \(target)"))
        }
        func quotient(_ p: Poly) -> Poly? {
            var q = p
            var rest = p.terms
            if let i = rest.firstIndex(where: { $0.powers.isEmpty }) { rest[i].coefficient -= target } else if target != 0 { rest.append((-target, [:])) }
            guard rest.allSatisfy({ $0.coefficient % d == 0 }) else { return nil }
            q.terms = rest.map { ($0.coefficient / d, $0.powers) }.filter { $0.0 != 0 }
            return q
        }
        var steps: [Step] = []
        if p.math.plain != typed.plain { steps.append(Step(label: "Multiplying out", math: row(typed, t(" = "), p.math))) }

        // Every term's coefficient a multiple of d already: d taken out.
        if let q = quotient(p) {
            steps.append(Step(label: "Taking out \(d)", math: row(typed, t(" = "), written(q)),
                              note: "What is in the brackets is an integer whenever \(letters(p.letters)) \(p.letters.count == 1 ? "is one" : "are integers"); so the whole is \(what)."))
            steps.append(Step(label: "Hence", math: claim))
            return Proof(claim: claim, verdict: verdict, method: "Proved directly", steps: steps, conclusion: claim)
        }
        // A counterexample, where there is one.
        if let found = search(p, { (($0 % d) + d) % d != target }) {
            let shown = p.letters.map { "\($0) = \(found[$0]!)" }.joined(separator: ", ")
            let v = p.value(found) ?? 0
            let why = d == 2 ? (v % 2 == 0 ? "which is even" : "which is odd") : "which is not divisible by \(d)"
            let conclusion = t("False: for \(shown), " + typed.plain + " = \(v), \(why)")
            return Proof(claim: claim, verdict: "False", method: "For \(shown), " + typed.plain + " = \(v), \(why)",
                         steps: [Step(label: "Giving a counterexample", math: t(shown), note: "Then " + typed.plain + " = \(v), \(why); one case where it fails disproves it.")],
                         conclusion: conclusion)
        }
        // One letter: by cases on its remainder, each case d(…) + target.
        guard p.letters.count == 1, let n = p.letters.first, d <= 12 else {
            return unsettled(claim, "The coefficients are not all multiples of \(d), and no counterexample was found among small numbers.")
        }
        let k = ["k", "m", "j", "t"].first { $0 != n } ?? "k"
        steps.append(Step(label: "Taking each remainder in turn", math: t("\(n) = \(d)\(k) + r,  r = 0, 1, …, \(d - 1)"),
                          note: "Every integer leaves one of these remainders on division by \(d), for some integer \(k); so these cases cover every \(n)."))
        for r in 0..<d {
            let substituted = expr.replacingIndex(n, with: r == 0 ? .op("*", .num(Double(d)), .index(k)) : .op("+", .op("*", .num(Double(d)), .index(k)), .num(Double(r))))
            guard let expanded = Poly.from(substituted, [k]), let q = quotient(expanded) else { return nil }
            steps.append(Step(label: "When \(n) = \(d)\(k)" + (r == 0 ? "" : " + \(r)"), math: row(typed, t(" = "), written(q))))
        }
        steps.append(Step(label: "Hence", math: claim, note: "In every case it is \(target == 0 ? "\(d) times an integer" : "2 times an integer, plus 1")."))
        return Proof(claim: claim, verdict: verdict, method: "Proved directly, by cases on \(n) modulo \(d)", steps: steps, conclusion: claim)
    }

    // MARK: - √n is irrational, by contradiction

    static func irrational(_ n: Int) -> Proof? {
        guard n >= 2, n <= 1_000_000 else { return nil }
        let claim = t("√\(n) is irrational")
        let root = Int(Double(n).squareRoot().rounded())
        if root * root == n {
            return Proof(claim: claim, verdict: "False", method: "√\(n) = \(root), a whole number",
                         steps: [Step(label: "Finding the root", math: t("√\(n) = \(root)"), note: "\(n) is the square of \(root), so its square root is rational.")],
                         conclusion: t("False: √\(n) = \(root)"))
        }
        var steps = [Step(label: "Supposing the contrary", math: t("√\(n) = a/b"),
                          note: "Suppose √\(n) is rational: a/b, with a and b positive integers and no factor common to both.")]
        steps.append(Step(label: "Squaring", math: t("a² = \(n)b²")))
        let primes = factors(n)
        if primes.count == 1, primes.first!.1 == 1 {
            // n prime: the textbook proof, both a and b divisible by n.
            steps.append(Step(label: "Showing \(n) divides a", math: t("\(n) | a²  ⇒  \(n) | a"),
                              note: "\(n) is prime, and a prime that divides a product divides one of its factors (Euclid's lemma). Write a = \(n)c."))
            steps.append(Step(label: "Substituting a = \(n)c", math: t("\(n * n)c² = \(n)b²,  so  b² = \(n)c²")))
            steps.append(Step(label: "Showing \(n) divides b", math: t("\(n) | b²  ⇒  \(n) | b"), note: "By the same lemma."))
            steps.append(Step(label: "Reaching a contradiction", math: nil, note: "Then \(n) divides both a and b, which have no common factor."))
        } else {
            // n with a prime to an odd power: count that prime on each side.
            let p = primes.first { $0.1 % 2 == 1 }!.0
            let k = primes.first { $0.0 == p }!.1
            steps.append(Step(label: "Counting the factors of \(p)", math: t("a² = \(n)b²"),
                              note: "In a², the prime \(p) appears an even number of times, as every prime in a square does. In \(n)b² it appears \(k) time\(k == 1 ? "" : "s") from \(n) and an even number from b²: an odd number of times."))
            steps.append(Step(label: "Reaching a contradiction", math: nil, note: "One number cannot have two different factorisations into primes (the fundamental theorem of arithmetic)."))
        }
        steps.append(Step(label: "Hence", math: claim, note: "The supposition is false, so √\(n) is not rational."))
        return Proof(claim: claim, verdict: "√\(n) is irrational", method: "Proved by contradiction", steps: steps, conclusion: claim)
    }

    private static func factors(_ n: Int) -> [(Int, Int)] {
        var out: [(Int, Int)] = [], m = n, p = 2
        while p * p <= m {
            var k = 0
            while m % p == 0 { m /= p; k += 1 }
            if k > 0 { out.append((p, k)) }
            p += 1
        }
        if m > 1 { out.append((m, 1)) }
        return out
    }
}

extension Expr {
    // The same expression with one letter of it replaced by another expression: n by 6k + 2.
    func replacingIndex(_ name: String, with value: Expr) -> Expr {
        switch self {
        case .index(let k) where k == name: return value
        case .neg(let a): return .neg(a.replacingIndex(name, with: value))
        case .op(let o, let a, let b): return .op(o, a.replacingIndex(name, with: value), b.replacingIndex(name, with: value))
        case .call(let f, let a): return .call(f, a.replacingIndex(name, with: value))
        case .apply(let f, let args): return .apply(f, args.map { $0.replacingIndex(name, with: value) })
        default: return self
        }
    }
}
