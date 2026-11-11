import Foundation

// Power series in the one letter, the unknown, as far as a given power: ln(1 + x)cos(x) as
// x − x²/2 − x³/6 + 3x⁵/40 + …, each coefficient exact and allowed to hold other letters, so
// that sin(ax) − a sin(x) is (a − a³)x³/6 + …. A Taylor polynomial is the series cut short, and
// a limit is read from the lowest powers left once a quotient is divided out.
struct Series {
    typealias Coefficient = [Simplification.Term]   // a polynomial in the other letters
    var terms: [Int: Coefficient]                    // power of the unknown → its coefficient
    var order: Int                                   // the powers above this are not known

    // MARK: Building

    static func constant(_ c: Coefficient, _ order: Int) -> Series { Series(terms: c.isEmpty ? [:] : [0: c], order: order) }
    static func number(_ n: Number, _ order: Int) -> Series { constant(n.isZero ? [] : [(n, [:])], order) }

    // The series of e in powers of t, where the unknown is centre + t.
    static func of(_ e: Expr, centre: Number = 0, order: Int) -> Series? {
        switch e {
        case .num(let v): return number(Number(v), order)
        case .constant(_, let v): return number(.approx(v), order)
        case .index(let name): return constant([(1, [name: 1])], order)
        case .unknown:
            var s = number(centre, order)
            s.terms[1] = [(1, [:])]
            return s
        case .neg(let a): return of(a, centre: centre, order: order).map { $0.scaled(-1) }
        case .op(let o, let a, let b):
            guard let l = of(a, centre: centre, order: order) else { return nil }
            switch o {
            case "+": return of(b, centre: centre, order: order).flatMap { l.plus($0) }
            case "-": return of(b, centre: centre, order: order).flatMap { l.plus($0.scaled(-1)) }
            case "*": return of(b, centre: centre, order: order).flatMap { l.times($0) }
            case "/": return of(b, centre: centre, order: order).flatMap { $0.inverse }.flatMap { l.times($0) }
            case "^":
                // e to a power, a whole or fractional power of a series, or a number to a power with the unknown in it.
                if case .num(let base) = a, abs(base - M_E) < 1e-15 { return of(b, centre: centre, order: order)?.applying("exp") }
                if !b.hasUnknown, b.number != nil, case let k? = b.number { return l.power(k) }
                if !a.hasUnknown, let base = a.number, base.double > 0 {
                    return of(b, centre: centre, order: order)?.scaled(Number.approx(log(base.double))).applying("exp")
                }
                return nil
            default: return nil
            }
        case .call(let f, let a):
            guard let inner = of(a, centre: centre, order: order) else { return nil }
            switch f {
            case "sqrt": return inner.power(.exact(Rational(1, 2)!))
            case "cbrt": return inner.power(.exact(Rational(1, 3)!))
            default: return inner.applying(f)
            }
        case .sum, .apply: return nil
        }
    }

    // MARK: Arithmetic

    private static func add(_ a: Coefficient, _ b: Coefficient) -> Coefficient { Simplification.sum(a + b) }
    private static func multiply(_ a: Coefficient, _ b: Coefficient) -> Coefficient? { Simplification.product(a, b) }

    // The coefficient as a number, where it has no letter in it.
    static func numeric(_ c: Coefficient) -> Number? {
        if c.isEmpty { return 0 }
        guard c.count == 1, c[0].powers.isEmpty else { return nil }
        return c[0].coefficient
    }

    var lowest: Int? { terms.keys.filter { !(terms[$0]?.isEmpty ?? true) }.min() }

    func scaled(_ k: Number) -> Series {
        Series(terms: terms.mapValues { $0.map { ($0.coefficient * k, $0.powers) } }.filter { !$0.value.isEmpty }, order: order)
    }

    func plus(_ other: Series) -> Series? {
        var out = terms
        for (power, c) in other.terms { out[power] = Series.add(out[power] ?? [], c) }
        return Series(terms: out.filter { !$0.value.isEmpty }, order: min(order, other.order))
    }

    func times(_ other: Series) -> Series? {
        // What is known of a product: as far as the lower order, shifted by the other's lowest power.
        let known = min(order + (other.lowest ?? 0), other.order + (lowest ?? 0))
        var out: [Int: Coefficient] = [:]
        for (i, a) in terms {
            for (j, b) in other.terms where i + j <= known {
                guard let p = Series.multiply(a, b) else { return nil }
                out[i + j] = Series.add(out[i + j] ?? [], p)
            }
        }
        return Series(terms: out.filter { !$0.value.isEmpty }, order: known)
    }

    // One over it: its lowest term must be a number, c xᵐ, so that 1/(c xᵐ (1 + v)) is
    // x⁻ᵐ/c · (1 − v + v² − …).
    var inverse: Series? {
        guard let m = lowest, let c = Series.numeric(terms[m] ?? []), !c.isZero else { return nil }
        var v = Series(terms: [:], order: order - m)
        for (power, coefficient) in terms where power != m { v.terms[power - m] = coefficient.map { ($0.coefficient / c, $0.powers) } }
        guard var sum = v.composed(with: (0...max(0, order - m)).map { $0 % 2 == 0 ? Number(1) : Number(-1) }) else { return nil }
        sum.terms = Dictionary(uniqueKeysWithValues: sum.terms.map { ($0.key - m, $0.value.map { ($0.coefficient / c, $0.powers) }) })
        sum.order -= 2 * m
        return sum
    }

    // f₀ + f₁v + f₂v² + …, for a series v with nothing below the first power.
    func composed(with f: [Number]) -> Series? {
        guard (lowest ?? 1) >= 1 else { return nil }
        var result = Series.number(f.first ?? 0, order)
        var power = Series.number(1, order)
        for k in 1..<max(f.count, 1) {
            guard let next = power.times(self) else { return nil }
            power = next
            power.order = order
            if !f[k].isZero, let sum = result.plus(power.scaled(f[k])) { result = sum }
            if (power.lowest ?? Int.max) > order { break }
        }
        result.order = order
        return result
    }

    func power(_ k: Number) -> Series? {
        // A whole power, by repeated multiplying (or of the inverse, for one below nought).
        if let r = k.rational, r.isWhole, abs(r.top) <= 64 {
            let base = r.top < 0 ? inverse : self
            guard var result = Optional(Series.number(1, order)), let base else { return nil }
            for _ in 0..<abs(r.top) { guard let next = result.times(base) else { return nil }; result = next }
            return result
        }
        // A fractional one of c(1 + v), c a positive number: c^k (1 + v)^k, by the binomial series.
        guard let c = Series.numeric(terms[0] ?? []), c.double > 0, (lowest ?? 0) == 0 else { return nil }
        var v = Series(terms: [:], order: order)
        for (p, coefficient) in terms where p != 0 { v.terms[p] = coefficient.map { ($0.coefficient / c, $0.powers) } }
        let f = (0...order).map { Number.choose(k, Number($0)) ?? .approx(.nan) }
        return v.composed(with: f)?.scaled(c.power(k))
    }

    // sin, cos, tan, exp, ln and the rest of a series: by the function's own series where the
    // constant term is nought, and by the addition formulae where it is a number.
    func applying(_ f: String) -> Series? {
        let c = Series.numeric(terms[0] ?? []) ?? .approx(.nan)
        guard c.double.isFinite else { return nil }   // a letter in the constant term: sin(a + x)
        var v = self
        v.terms[0] = nil
        let n = order
        func series(_ g: (Int) -> Number) -> Series? { v.composed(with: (0...n).map(g)) }
        let fact = { (k: Int) -> Number in Number.factorialOf(Number(k)) }
        let sin0 = series { $0 % 2 == 1 ? (($0 / 2) % 2 == 0 ? 1 : -1) / fact($0) : 0 }
        let cos0 = series { $0 % 2 == 0 ? (($0 / 2) % 2 == 0 ? 1 : -1) / fact($0) : 0 }
        let exp0 = series { 1 / fact($0) }
        func exact(_ g: (Double) -> Double) -> Number { Number.worked(g(c.double), from: [c]) }
        switch f {
        case "sin":
            if c.isZero { return sin0 }
            guard let s = sin0, let k = cos0 else { return nil }
            return s.scaled(exact(cos)).plus(k.scaled(exact(sin)))
        case "cos":
            if c.isZero { return cos0 }
            guard let s = sin0, let k = cos0 else { return nil }
            return k.scaled(exact(cos)).plus(s.scaled(-exact(sin)))
        case "tan":
            guard let s = applying("sin"), let k = applying("cos")?.inverse else { return nil }
            return s.times(k)
        case "exp":
            return exp0?.scaled(exact(exp))
        case "sinh": return c.isZero ? series { $0 % 2 == 1 ? 1 / fact($0) : 0 } : nil
        case "cosh": return c.isZero ? series { $0 % 2 == 0 ? 1 / fact($0) : 0 } : nil
        case "ln":
            // ln(c(1 + v/c)) = ln c + v/c − (v/c)²/2 + …
            guard c.double > 0 else { return nil }
            let w = v.scaled(1 / c)
            guard let rest = w.composed(with: (0...n).map { $0 == 0 ? 0 : ($0 % 2 == 1 ? 1 : -1) / Number($0) }) else { return nil }
            return c == 1 ? rest : rest.plus(Series.number(exact(log), n))
        case "atan":
            return c.isZero ? series { $0 % 2 == 1 ? (($0 / 2) % 2 == 0 ? 1 : -1) / Number($0) : 0 } : nil
        case "asin":
            guard c.isZero else { return nil }
            return series { k in
                guard k % 2 == 1 else { return 0 }
                let m = (k - 1) / 2
                return Number.factorialOf(Number(2 * m)) / (Number(4).power(Number(m)) * fact(m) * fact(m) * Number(k))
            }
        default: return nil
        }
    }

    // MARK: Writing

    // The terms up to the given power, the lowest first: x − x²/2 − x³/6 + 3x⁵/40.
    func written(as name: String, upTo top: Int, letters: [String]) -> Math {
        var flat: [Simplification.Term] = []
        for power in terms.keys.sorted() where power <= top {
            for term in terms[power] ?? [] { flat.append((term.coefficient, term.powers.merging(power == 0 ? [:] : [name: power]) { a, _ in a })) }
        }
        let writer = Simplification(expr: .num(0), letters: letters + [name], terms: flat)
        return writer.math(flat)
    }

    // The letters in its coefficients, in the order they are met.
    var letters: [String] {
        var out: [String] = []
        for power in terms.keys.sorted() { for term in terms[power] ?? [] { for key in term.powers.keys.sorted() where !out.contains(key) { out.append(key) } } }
        return out
    }
}

// The limit of f as the unknown goes to a number, from the series about it: the constant term,
// where nothing below the first power is left; nil where something is, and f goes off to infinity.
extension Series {
    static func limit(_ f: Expr, at point: Number, order: Int = 8) -> Coefficient? {
        guard let s = of(f, centre: point, order: order), let low = s.lowest ?? Optional(0) else { return nil }
        guard low >= 0, s.order >= 0 else { return nil }
        return s.terms[0] ?? []
    }
}

extension Series {
    // Whether a letter other than the unknown is in it: a in sin(ax).
    static func hasLetter(_ e: Expr) -> Bool {
        switch e {
        case .index: return true
        case .num, .unknown, .constant: return false
        case .neg(let a), .call(_, let a): return hasLetter(a)
        case .op(_, let a, let b): return hasLetter(a) || hasLetter(b)
        case .apply(_, let args): return args.contains(where: hasLetter)
        case .sum(_, let from, let to, let body, _): return hasLetter(from) || hasLetter(to) || hasLetter(body)
        }
    }

    // lim as x → a of f, with letters in it, read from the series about a. The working gives the top
    // and the bottom of a quotient in powers of x as far as is needed, and then their quotient.
    static func limitAnswer(_ f: Expr, _ name: String, at target: String) -> Algebra? {
        guard let point = (try? Parser.constant(target))?.number, point.isExact, let value = limit(f, at: point) else { return nil }
        let letters = (of(f, centre: point, order: 8)?.letters ?? [])
        let writer = Simplification(expr: .num(0), letters: letters, terms: value)
        let answer = writer.math(value)
        let header = row(t("lim \(name) → \(target) "), typeset(f, name))
        var steps: [Step] = []
        let shifted = point.isZero ? name : "(\(name) − \(point))"
        if case .op("/", let top, let bottom) = f, let b = of(bottom, centre: point, order: 8), let low = b.lowest,
           let a = of(top, centre: point, order: low + 2) {
            func shown(_ s: Series) -> Math {
                let first = s.lowest ?? 0
                let cut = Series(terms: s.terms.filter { $0.key <= max(first, low) }, order: s.order)
                return row(cut.written(as: shifted, upTo: max(first, low), letters: s.letters), t(" + …"))
            }
            steps.append(Step(label: "Expanding the top in powers of \(shifted)", math: shown(a)))
            steps.append(Step(label: "Expanding the bottom", math: shown(b)))
            steps.append(Step(label: "Dividing, and letting \(name) → \(target)", math: row(t("= "), answer)))
        } else {
            steps.append(Step(label: "Expanding in powers of \(shifted), and letting \(name) → \(target)", math: row(t("= "), answer)))
        }
        let d = Details(name: "", equation: header, steps: steps, solutions: [row(t("= "), answer)], note: nil, f: { _ in .nan }, roots: [])
        let plain = answer.plain
        return Algebra(solution: Solution(exact: "= " + plain, approx: nil), details: d,
                       copyText: plain.replacingOccurrences(of: "−", with: "-"), values: numeric(value).map { [$0.double] } ?? [])
    }
}

// A Taylor polynomial, asked for as T_5(x), f(x) = ln(1+x)cos(x), as taylor(ln(1+x)cos(x), 5), or
// with the letter named, taylor(f, x, 5); series( … ) and maclaurin( … ) are the same. About nought.
struct Taylor {
    var expr: Expr
    var name: String
    var degree: Int
    var series: Series

    static func parse(_ input: String) -> Taylor? {
        let text = input.trimmingCharacters(in: .whitespaces)
        var body: String, degree: Int, name = "x"
        let heading = try! NSRegularExpression(pattern: "^T_\\(?([0-9]+)\\)?\\s*\\(\\s*([a-z])\\s*\\)\\s*[,;]?\\s*[a-z]\\s*\\(\\s*[a-z]\\s*\\)\\s*=\\s*")
        let whole = NSRange(text.startIndex..., in: text)
        if let m = heading.firstMatch(in: text, range: whole), let n = Range(m.range(at: 1), in: text), let v = Range(m.range(at: 2), in: text),
           let end = Range(m.range, in: text) {
            guard let d = Int(text[n]) else { return nil }
            degree = d
            name = String(text[v])
            body = String(text[end.upperBound...])
        } else if let m = text.range(of: "^(?i:taylor|maclaurin|series)\\s*\\(", options: .regularExpression), text.hasSuffix(")") {
            let inside = String(text[m.upperBound..<text.index(before: text.endIndex)])
            let parts = topLevel(inside)
            guard parts.count >= 2, let n = Int(parts.last!.trimmingCharacters(in: .whitespaces)) else { return nil }
            degree = n
            body = parts[0]
            if parts.count >= 3 {
                let named = parts[1].trimmingCharacters(in: .whitespaces)
                guard named.range(of: "^[a-z]$", options: .regularExpression) != nil else { return nil }
                name = named
            }
        } else { return nil }
        guard (0...20).contains(degree), let tokens = try? Parser.tokenize(body) else { return nil }
        var letters: [String] = []
        for token in tokens { if case .letter(let s) = token, s != name, s != "e", !letters.contains(s) { letters.append(s) } }
        let mapped = tokens.map { $0 == .letter("e") && name != "e" ? .constant(M_E) : $0 }
        var state = Parser.State(tokens: mapped, unknown: name, bound: letters)
        guard let expr = try? state.expression(), state.at == mapped.count, expr.hasUnknown,
              let s = Series.of(expr, order: degree), s.order >= degree else { return nil }
        return Taylor(expr: expr, name: name, degree: degree, series: s)
    }

    // "a, b, c" at the top level of brackets.
    static func topLevel(_ s: String) -> [String] {
        var parts: [String] = [], current = "", depth = 0
        for c in s {
            if "([{".contains(c) { depth += 1 } else if ")]}".contains(c) { depth -= 1 }
            if c == ",", depth == 0 { parts.append(current); current = "" } else { current.append(c) }
        }
        parts.append(current)
        return parts
    }

    var polynomial: Math { series.written(as: name, upTo: degree, letters: series.letters) }

    var solution: Solution { Solution(exact: "T_\(degree)(\(name)) = " + polynomial.plain, approx: "The Taylor polynomial of degree \(degree) about \(name) = 0") }

    var details: Details {
        let header = row(t("T_\(degree)(\(name)),   f(\(name)) = "), typeset(expr, name))
        var steps: [Step] = []
        // Each standard series used, as far as the degree asked for.
        var seen: [String] = []
        func look(_ e: Expr) {
            switch e {
            case .call(_, let a):
                look(a)
                let key = typeset(e, name).plain
                guard !seen.contains(key), let s = Series.of(e, order: degree) else { return }
                seen.append(key)
                steps.append(Step(label: "Expanding \(key)", math: row(typeset(e, name), t(" = "), s.written(as: name, upTo: degree, letters: s.letters), t(" + …"))))
            case .op(let o, let a, let b):
                look(a); look(b)
                if o == "^", case .num(let base) = a, abs(base - M_E) < 1e-15 {
                    let key = typeset(e, name).plain
                    guard !seen.contains(key), let s = Series.of(e, order: degree) else { return }
                    seen.append(key)
                    steps.append(Step(label: "Expanding \(key)", math: row(typeset(e, name), t(" = "), s.written(as: name, upTo: degree, letters: s.letters), t(" + …"))))
                }
            case .neg(let a): look(a)
            default: break
            }
        }
        look(expr)
        if steps.count > 1 || steps.isEmpty {
            steps.append(Step(label: "Multiplying out, and keeping the terms up to \(name)^\(degree)", math: row(t("T_\(degree)(\(name)) = "), polynomial)))
        } else {
            steps.append(Step(label: "Keeping the terms up to \(name)^\(degree)", math: row(t("T_\(degree)(\(name)) = "), polynomial)))
        }
        return Details(name: "T_\(degree)", equation: header, steps: steps, solutions: [row(t("T_\(degree)(\(name)) = "), polynomial)],
                       note: nil, f: { _ in .nan }, roots: [])
    }
}
