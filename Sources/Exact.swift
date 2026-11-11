import Foundation

// Numbers as they are worked on paper: a fraction kept as a fraction, 1/3 and 35/2048, for as long
// as everything done to it is adding, taking away, multiplying, dividing, a whole power, a root
// that comes out, a factorial or a choice; and a decimal only once something irrational is done,
// √2 or sin 1, or the fraction would be too large to hold. What is exact is then never guessed
// back from a decimal.

extension Int {
    // A decimal as a whole number, cut toward nought; nil where it is infinite, not a number, or
    // beyond 64 bits. Int( ) itself stops the program there, as it would for x² = 10⁴⁰⁰, so a
    // decimal that may be any of those is turned into a whole number through this.
    init?(fitting v: Double) {
        guard v.isFinite, v > -9.2e18, v < 9.2e18 else { return nil }
        self.init(v)
    }
}

// p/q in lowest terms, q above nought. Nil from any working that would not fit in 64 bits.
struct Rational: Hashable, CustomStringConvertible {
    let top: Int
    let bottom: Int

    init?(_ top: Int, _ bottom: Int = 1) {
        guard bottom != 0, top != Int.min, bottom != Int.min else { return nil }
        let g = Swift.max(gcd(top, bottom), 1)
        let sign = bottom < 0 ? -1 : 1
        self.top = sign * top / g
        self.bottom = sign * bottom / g
    }

    // A decimal as it is written, to fifteen figures: 0.1 is 1/10, and 2.5e-3 is 1/400.
    init?(decimal v: Double) {
        guard v.isFinite else { return nil }
        if v == v.rounded(), abs(v) < 9e15 { self.init(Int(v)); return }
        let parts = String(format: "%.15g", v).split(separator: "e", omittingEmptySubsequences: false)
        let mantissa = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard let whole = Int(mantissa[0] + (mantissa.count > 1 ? mantissa[1] : "")),
              var power = parts.count > 1 ? Int(parts[1]) : 0 else { return nil }
        power -= mantissa.count > 1 ? mantissa[1].count : 0
        var top = whole, bottom = 1
        for _ in 0..<abs(power) {
            if power > 0 {
                let (t, o) = top.multipliedReportingOverflow(by: 10); if o { return nil }; top = t
            } else {
                let (b, o) = bottom.multipliedReportingOverflow(by: 10); if o { return nil }; bottom = b
            }
        }
        self.init(top, bottom)
    }

    static let zero = Rational(0)!, one = Rational(1)!

    var double: Double { Double(top) / Double(bottom) }
    var isWhole: Bool { bottom == 1 }
    var isNegative: Bool { top < 0 }
    var description: String { fraction(top, bottom) }

    static func + (a: Rational, b: Rational) -> Rational? {
        // Over the lowest common bottom, which keeps the working small: 1/6 + 1/10 over 30, not 60.
        let g = gcd(a.bottom, b.bottom)
        let (x, o1) = a.top.multipliedReportingOverflow(by: b.bottom / g)
        let (y, o2) = b.top.multipliedReportingOverflow(by: a.bottom / g)
        let (s, o3) = x.addingReportingOverflow(y)
        let (d, o4) = (a.bottom / g).multipliedReportingOverflow(by: b.bottom)
        return o1 || o2 || o3 || o4 ? nil : Rational(s, d)
    }
    static prefix func - (a: Rational) -> Rational { Rational(-a.top, a.bottom)! }
    static func - (a: Rational, b: Rational) -> Rational? { a + (-b) }
    static func * (a: Rational, b: Rational) -> Rational? {
        // Each top cancelled against the other bottom first, so that 2048/3 × 3/2048 does not overflow.
        let g1 = Swift.max(gcd(a.top, b.bottom), 1), g2 = Swift.max(gcd(b.top, a.bottom), 1)
        let (t, o1) = (a.top / g1).multipliedReportingOverflow(by: b.top / g2)
        let (d, o2) = (a.bottom / g2).multipliedReportingOverflow(by: b.bottom / g1)
        return o1 || o2 ? nil : Rational(t, d)
    }
    static func / (a: Rational, b: Rational) -> Rational? {
        guard b.top != 0 else { return nil }
        return a * Rational(b.bottom, b.top)!
    }
    // A whole power, below nought too: (2/3)⁻² is 9/4.
    func power(_ k: Int) -> Rational? {
        if k < 0 { return top == 0 ? nil : Rational(bottom, top)?.power(-k) }
        var result = Rational.one, base = self, k = k
        while k > 0 {
            if k & 1 == 1 { guard let r = result * base else { return nil }; result = r }
            k >>= 1
            if k > 0 { guard let b = base * base else { return nil }; base = b }
        }
        return result
    }
    // The decimal it is in full, where it ends: 35/2048 is 0.01708984375; nil for 1/3.
    var terminatingDecimal: String? {
        var b = bottom, twos = 0, fives = 0
        while b % 2 == 0 { b /= 2; twos += 1 }
        while b % 5 == 0 { b /= 5; fives += 1 }
        let places = Swift.max(twos, fives)
        guard b == 1, places <= 18 else { return nil }
        // top/bottom × 10^places is a whole number: its digits, with the point put back.
        guard let scale = Rational(10)?.power(places), let shifted = self * scale, shifted.isWhole else { return nil }
        var digits = String(abs(shifted.top))
        while digits.count <= places { digits = "0" + digits }
        let point = digits.index(digits.endIndex, offsetBy: -places)
        var text = places == 0 ? digits : digits[..<point] + "." + digits[point...]
        while text.contains("."), text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return (top < 0 ? "−" : "") + text
    }

    // Whether it is better written as a fraction than as a decimal: always where the lower half is
    // 1000 or less, 5/2 and 7/8; above that, where the fraction is the shorter of the two exact
    // forms, 35/2048 and not 0.01708984375, but 6.28318 and not 314159/50000; and always where the
    // decimal never ends, 1/1001.
    var prefersFraction: Bool {
        guard bottom > 1000, let full = terminatingDecimal else { return true }
        return String(abs(top)).count + String(bottom).count < full.filter(\.isNumber).count
    }

    // The qth root, where it comes out: 4/9 to the half is 2/3, −8 to the third is −2.
    func root(_ q: Int) -> Rational? {
        guard q >= 1, q % 2 == 1 || top >= 0 else { return nil }
        func whole(_ n: Int) -> Int? {
            let r = Int((pow(Double(abs(n)), 1 / Double(q))).rounded())
            for c in [r - 1, r, r + 1] where c >= 0 {
                if let p = Rational(c)?.power(q), p.top == abs(n) { return n < 0 ? -c : c }
            }
            return nil
        }
        guard let t = whole(top), let b = whole(bottom) else { return nil }
        return Rational(t, b)
    }
}

enum Number: CustomStringConvertible {
    case exact(Rational)
    case approx(Double)

    // A number as typed is exact, 0.1 being 1/10; one of more than twelve figures is not one that
    // was typed but π, e or a decimal already rounded, and stays a decimal.
    init(_ v: Double) {
        let typed = v == v.rounded() && abs(v) < 9e15 || Double(String(format: "%.12g", v)) == v
        self = typed ? Rational(decimal: v).map(Number.exact) ?? .approx(v) : .approx(v)
    }
    init(_ n: Int) { self = .exact(Rational(n)!) }

    var double: Double {
        switch self {
        case .exact(let r): return r.double
        case .approx(let v): return v
        }
    }
    var rational: Rational? { if case .exact(let r) = self { r } else { nil } }
    var isExact: Bool { rational != nil }
    var description: String { rational?.description ?? decimal(double) }

    // Exactly where both are exact and the answer fits; as a decimal otherwise.
    private static func combine(_ a: Number, _ b: Number, _ exact: (Rational, Rational) -> Rational?, _ approx: (Double, Double) -> Double) -> Number {
        if let x = a.rational, let y = b.rational, let r = exact(x, y) { return .exact(r) }
        return .approx(approx(a.double, b.double))
    }
    // Decimals are added as the rest of the solver adds them: what is left is nought where it is
    // only rounding, 0.1 + 0.2 − 0.3.
    static func + (a: Number, b: Number) -> Number { combine(a, b, +, added) }
    static func - (a: Number, b: Number) -> Number { combine(a, b, -, { added($0, -$1) }) }
    static func * (a: Number, b: Number) -> Number { combine(a, b, *, *) }
    static func / (a: Number, b: Number) -> Number { combine(a, b, /, /) }
    static prefix func - (a: Number) -> Number { a.rational.map { .exact(-$0) } ?? .approx(-a.double) }

    // A power: exact for a whole power, and for a fractional one whose root comes out, 8^(2/3) = 4.
    func power(_ e: Number) -> Number {
        if let b = rational, let k = e.rational, abs(k.top) <= 4096, k.bottom <= 64,
           let rooted = k.bottom == 1 ? b : b.root(k.bottom), let r = rooted.power(k.top) { return .exact(r) }
        return .approx(pow(double, e.double))
    }

    // n!, for a whole n from 0 to 20; beyond that, as a decimal.
    static func factorialOf(_ n: Number) -> Number {
        guard let k = n.rational, k.isWhole, k.top >= 0, k.top <= 20 else { return .approx(factorial(n.double)) }
        return .exact(Rational((1...Swift.max(1, k.top)).reduce(1, *))!)
    }

    // What a function or operator not worked exactly gives: exact where what went in was exact and
    // what came out is whole, as gcd(12, 18) and floor(7/2) are; a decimal otherwise.
    static func worked(_ v: Double, from inputs: [Number]) -> Number {
        inputs.allSatisfy(\.isExact) && v == v.rounded() && abs(v) < 9e15 ? Number(v) : .approx(v)
    }

    // n(n − 1)⋯(n − r + 1), r factors: the number of arrangements, and the top of a choice. n may
    // be any number, as in a binomial expansion with n = 1/2; r must be whole and not below nought.
    static func falling(_ n: Number, _ r: Int) -> Number {
        var result = Number(1)
        for i in 0..<r { result = result * (n - Number(i)) }
        return result
    }

    // C(n, r) = n(n − 1)⋯(n − r + 1)/r!, which is n!/(r!(n − r)!) for whole n; nought where r is
    // greater than a whole n, and 1/16 for n = 1/2, r = 3. Nil where r is not whole or is below nought.
    static func choose(_ n: Number, _ r: Number) -> Number? {
        guard let k = r.rational, k.isWhole, k.top >= 0, k.top <= 10_000 else { return nil }
        // For a whole n, the smaller of r and n − r gives the same with fewer factors.
        var r = k.top
        if let m = n.rational, m.isWhole, m.top >= 0, m.top >= r { r = Swift.min(r, m.top - r) }
        var result = Number(1)
        for i in 0..<r { result = result * (n - Number(i)) / Number(i + 1) }
        return result
    }

    // P(n, r) = n(n − 1)⋯(n − r + 1). Nil where r is not whole or is below nought.
    static func arrangements(_ n: Number, _ r: Number) -> Number? {
        guard let k = r.rational, k.isWhole, k.top >= 0, k.top <= 10_000 else { return nil }
        return falling(n, k.top)
    }
}

// Written as numbers are in the solver: 1 for Number(1), compared by value, exact or not.
extension Number: ExpressibleByIntegerLiteral, Equatable, Comparable {
    init(integerLiteral value: Int) { self.init(value) }
    static func == (a: Number, b: Number) -> Bool {
        if let x = a.rational, let y = b.rational { return x == y }
        return a.double == b.double
    }
    static func < (a: Number, b: Number) -> Bool { a.double < b.double }
    var magnitude: Number { double < 0 ? -self : self }
    var isZero: Bool { double == 0 }
}

extension Expr {
    // The value worked exactly where every part of it allows that; nil where there is a letter in
    // it, and a decimal (.approx) for what is irrational, a physical constant, or too large.
    var number: Number? { worked(asTyped: false) }

    // The same, every number in it taken as exactly what was typed, however many figures it has:
    // for ===, where 1/3 is not 0.3333333333333333.
    var typedNumber: Number? { worked(asTyped: true) }

    private func worked(asTyped: Bool) -> Number? {
        let number: (Expr) -> Number? = { $0.worked(asTyped: asTyped) }
        switch self {
        case .num(let v): return asTyped ? Rational(decimal: v).map(Number.exact) ?? .approx(v) : Number(v)
        case .constant(_, let v): return .approx(v)
        case .unknown, .index: return nil
        case .neg(let a): return number(a).map { -$0 }
        case .op(let o, let a, let b):
            guard let x = number(a), let y = number(b) else { return nil }
            switch o {
            case "+": return x + y
            case "-": return x - y
            case "*": return x * y
            case "/": return y.double == 0 ? .approx(x.double / y.double) : x / y
            case "^": return x.power(y)
            case "⒞": return Number.choose(x, y) ?? .approx(.nan)
            case "⒫": return Number.arrangements(x, y) ?? .approx(.nan)
            default: return Number.worked(eval(0), from: [x, y])
            }
        case .call(let f, let a):
            guard let x = number(a) else { return nil }
            switch f {
            case "fact": return Number.factorialOf(x)
            case "abs": return x.double < 0 ? -x : x
            case "sqrt": return x.double < 0 ? .approx(.nan) : x.power(.exact(Rational(1, 2)!))
            case "cbrt": return x.power(.exact(Rational(1, 3)!))
            default: return Number.worked(eval(0), from: [x])
            }
        case .apply(_, let args):
            let inputs = args.compactMap(number)
            return inputs.count == args.count ? Number.worked(eval(0), from: inputs) : nil
        // The k of a sum has a value only inside it: a sum is worked as a decimal, or not at all
        // where another letter is in it.
        case .sum:
            let v = eval(0)
            return hasUnknown || v.isNaN ? nil : .approx(v)
        }
    }
}
